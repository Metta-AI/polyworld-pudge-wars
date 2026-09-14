"""Local demo: existing native engine + existing WASM client + semantic policy.

Run python -m coaching.server, then open http://127.0.0.1:8787.
"""
from __future__ import annotations

import argparse
import asyncio
from collections import deque
from copy import deepcopy
import importlib.util
import json
import os
from pathlib import Path
import secrets
import socket
import sys
import time
from urllib.parse import urlencode

from aiohttp import ClientSession, ClientTimeout, WSMsgType, web

from .policy import (CAPABILITIES, GUARDS, INTENTS, SELECTORS, PolicyError,
                     compile_policy, decide, facts, initial_policy, interpret, readable)
from .realtime import DEFAULT_MODEL, RealtimeCall
from .reasoning import ReasoningLab, evaluate_candidate, reference_candidate

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "examples/pudge_wars/emscripten"


def load_opponent(slot):
    # Keep the package context for sibling imports while giving each seat
    # separate module globals (opponent tracking is stateful).
    name = f"coworld.player.coaching_opponent_{slot}_{secrets.token_hex(4)}"
    spec = importlib.util.spec_from_file_location(name, ROOT / "coworld/player/player.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    module.PERSONALITY = "rusher"
    return module


class Demo:
    def __init__(self, port=8787, autopilot=False):
        self.port, self.autopilot = port, autopilot
        self.csrf = secrets.token_urlsafe(24)
        self.policy = compile_policy(initial_policy().document())
        self.remembered_path = ROOT / "tmp/coaching/remembered-policy.json"
        self.remembered = (compile_policy(json.loads(self.remembered_path.read_text()))
                           if self.remembered_path.exists() else self.policy)
        self.policy = self.remembered
        self.reasoning = ReasoningLab(ROOT / "tmp/coaching/reasoning" / str(port))
        self.previous = []
        self.pending = None
        self.pending_remembered = None
        self.contexts = deque(maxlen=480)
        self.trace = {}
        self.timeline = deque(maxlen=70)
        self.jobs = {}
        self.receipts = {}
        self.selected_id = None
        self.process = None
        self.client = None
        self.tasks = set()
        self.voice = None
        self.voice_status = "Voice ready" if os.environ.get("OPENAI_API_KEY") else "Voice needs OPENAI_API_KEY on the server"
        self.phase = "ready"
        self.match_id = ""
        self.game_url = ""
        self.error = ""
        self.run_dir = None
        self.active_tick = None
        self.agent_id = None
        self.coach_id = None

    def log(self, kind, **data):
        event = {"kind": kind, "at": time.time(), "match_id": self.match_id, **data}
        self.timeline.appendleft(event)
        if self.run_dir:
            with (self.run_dir / "coaching.jsonl").open("a") as output:
                output.write(json.dumps(event) + "\n")

    def spawn(self, coroutine):
        task = asyncio.create_task(coroutine)
        self.tasks.add(task)
        def done(t):
            self.tasks.discard(t)
            if not t.cancelled() and t.exception():
                self.error = str(t.exception())
                self.log("error", message=self.error)
        task.add_done_callback(done)
        return task

    def latest_context_id(self):
        return self.contexts[-1]["id"] if self.contexts else None

    def context_bundle(self, context_id=None):
        if not self.contexts:
            raise PolicyError("Start the match and wait for the first agent observation.")
        chosen = next((c for c in self.contexts if c["id"] == context_id), None) if context_id else self.contexts[-1]
        if chosen is None:
            raise PolicyError("That gameplay context has expired. Retrieve fresh context.")
        return {"context_id": chosen["id"], "match_id": self.match_id, "speech_time": chosen["obs"],
                "current_tick": self.contexts[-1]["obs"]["tick"], "coach_id": self.coach_id,
                "selected_enemy_id": chosen.get("selected_id"), "policy": self.policy.document(),
                "reasoning": self.reasoning.view(self.policy, self.match_id),
                "trace_at_context": chosen["trace"], "latest_trace": self.trace,
                "recent": [{"tick": c["obs"]["tick"], "score": c["obs"]["score"],
                            "selected": c["trace"].get("selected", {})} for c in list(self.contexts)[-96::16]],
                "capabilities": {"version": CAPABILITIES, "conditions": GUARDS,
                                 "selectors": sorted(SELECTORS), "intents": INTENTS},
                "arbitration": "First feasible rule per channel, ascending priority. Failed hook requirements fall through; movement is independent."}

    async def start(self):
        await self.stop_match()
        self.match_id = secrets.token_hex(8)
        self.run_dir = ROOT / "tmp/coaching" / self.match_id
        self.run_dir.mkdir(parents=True)
        # A rematch preserves explicit durable strategy; transient references expire.
        self.reset_policy_for_match()
        self.pending = None
        self.pending_remembered = None
        self.previous.clear()
        self.contexts.clear()
        self.timeline.clear()
        self.receipts.clear()
        self.jobs.clear()
        self.trace = {}
        self.agent_id = self.coach_id = None
        self.selected_id = None
        self.error = ""
        self.active_tick = None
        with socket.socket() as reservation:
            reservation.bind(("127.0.0.1", 0))
            self.engine_port = reservation.getsockname()[1]
        tokens = [secrets.token_urlsafe(24) for _ in range(4)]
        config = {"tokens": tokens, "players": [{"name": x} for x in ["You", "Loom", "Red 1", "Red 2"]],
                  "max_ticks": 32 * 600, "kill_goal": 30, "seed": 7, "fog": True,
                  "player_connect_timeout_seconds": 40}
        config_path = self.run_dir / "config.json"
        config_path.write_text(json.dumps(config))
        config_path.chmod(0o600)
        env = {k: v for k, v in os.environ.items() if not k.startswith(("OPENAI_", "COGAME_"))}
        env.update(COGAME_HOST="127.0.0.1", COGAME_PORT=str(self.engine_port),
                   COGAME_CONFIG_URI=config_path.as_uri(),
                   COGAME_RESULTS_URI=(self.run_dir / "results.json").as_uri(),
                   COGAME_SAVE_REPLAY_URI=(self.run_dir / "replay.pwr").as_uri())
        binary = ROOT / "tmp/coaching/pwcoworld"
        if not binary.exists():
            raise PolicyError("Build the native host with scripts/coach_demo.sh first.")
        output = (self.run_dir / "engine.log").open("w")
        try:
            self.process = await asyncio.create_subprocess_exec(str(binary), env=env, cwd=ROOT,
                                                                stdout=output, stderr=output)
        finally:
            output.close()
        self.phase = "starting"
        for _ in range(100):
            if self.process.returncode is not None:
                raise PolicyError(f"Game host exited. Inspect {self.run_dir / 'engine.log'}.")
            try:
                async with self.client.get(f"http://127.0.0.1:{self.engine_port}/healthz") as response:
                    if response.status == 200:
                        break
            except OSError:
                pass
            await asyncio.sleep(0.05)
        else:
            raise PolicyError("Game host did not become ready.")
        for slot in range(0 if self.autopilot else 1, 4):
            self.spawn(self.player(slot, tokens[slot], self.match_id))
        params = {"join": f"ws://127.0.0.1:{self.port}/engine/ws", "token": tokens[0], "slot": "0", "name": "You"}
        self.game_url = "/play/pw.html?" + urlencode(params)
        self.log("match_started", policy_hash=self.policy.fingerprint)

    async def player(self, slot, token, match_id):
        memory = {}
        opponent = load_opponent(slot) if slot >= 2 else None
        uri = f"http://127.0.0.1:{self.engine_port}/player?" + urlencode({"slot": slot, "token": token})
        async with self.client.ws_connect(uri, heartbeat=20) as ws:
            async for message in ws:
                if message.type != WSMsgType.TEXT:
                    continue
                obs = json.loads(message.data)
                if obs.get("done"):
                    self.phase = "finished"
                    self.log("match_finished", score=obs.get("score"))
                    return
                if obs.get("type") != "observation" or match_id != self.match_id:
                    continue
                if slot == 1:
                    self.phase = "playing"
                    self.agent_id = obs["self"]["id"]
                    self.coach_id = next(p["id"] for p in obs["visible"]["pudges"] if p["slot"] == 0)
                    # The engine echoes unsequenced acceptance. Keep it separate from
                    # rule attribution: a delayed response can cross a tick boundary.
                    if self.trace:
                        self.trace["next_observation_acceptance"] = obs.get("accepted", {})
                        if obs.get("accepted", {}).get("hook_to") is True:
                            self.log("hook_accepted", observed_tick=obs["tick"],
                                     acceptance=obs["accepted"], preceding_decision=deepcopy(self.trace),
                                     attribution="Unsequenced engine echo; the preceding decision is context, not a correlated receipt.")
                    if self.pending:
                        self.activate_pending(obs["tick"])
                    action, memory, trace = decide(self.policy, obs, self.coach_id, memory)
                    self.trace = trace
                    context = {"id": f"{match_id}:{obs['tick']}", "obs": obs, "trace": trace,
                               "selected_id": self.selected_id}
                    self.contexts.append(context)
                    if obs["tick"] % 8 == 0:
                        with (self.run_dir / "decisions.jsonl").open("a") as out:
                            out.write(json.dumps(context) + "\n")
                elif slot == 0:
                    partner_id = next(p["id"] for p in obs["visible"]["pudges"] if p["slot"] == 1)
                    action, memory, _ = decide(initial_policy(), obs, partner_id, memory)
                else:
                    action = opponent.choose_action(obs)
                await ws.send_json(action)

    async def stop_match(self):
        if self.voice:
            await self.voice.close()
            self.voice = None
        for task in list(self.tasks):
            task.cancel()
        await asyncio.gather(*list(self.tasks), return_exceptions=True)
        if self.process and self.process.returncode is None:
            self.process.terminate()
            try:
                await asyncio.wait_for(self.process.wait(), timeout=4)
            except asyncio.TimeoutError:
                self.process.kill()
                await self.process.wait()
        self.process = None

    def reset_policy_for_match(self):
        doc = self.remembered.document()
        doc["revision"] = self.policy.revision + (self.policy.fingerprint != self.remembered.fingerprint)
        self.policy = compile_policy(doc)

    def remembered_after(self, candidate):
        if candidate.provenance.get("scope") != "persistent":
            return self.remembered
        # Persist the edit, not the whole match's temporary strategy.
        doc = self.remembered.document()
        before = {r.id: r for r in self.policy.rules}
        after = {r.id: r for r in candidate.rules}
        durable = {r["id"]: r for r in doc["rules"]}
        for rule_id in before.keys() - after.keys():
            durable.pop(rule_id, None)
        for raw in candidate.document()["rules"]:
            if before.get(raw["id"]) != after[raw["id"]] and raw["scope"] == "persistent":
                durable[raw["id"]] = raw
        doc["rules"] = list(durable.values())
        if candidate.retreat_percent != self.policy.retreat_percent:
            doc["retreat_percent"] = candidate.retreat_percent
        doc["revision"] = candidate.revision
        doc["provenance"] = candidate.provenance
        return compile_policy(doc)

    def activate_pending(self, tick):
        self.policy, self.pending = self.pending, None
        self.remembered, self.pending_remembered = self.pending_remembered, None
        self.remembered_path.parent.mkdir(parents=True, exist_ok=True)
        staging = self.remembered_path.with_suffix(".pending")
        staging.write_text(json.dumps(self.remembered.document(), indent=2))
        staging.replace(self.remembered_path)
        self.active_tick = tick
        self.log("policy_active", revision=self.policy.revision, tick=tick)
        generation_id = self.policy.provenance.get("generation_id")
        if generation_id in self.reasoning.requests:
            request = self.reasoning.requests[generation_id]
            request["status"] = "active_trial"
            self.reasoning.save_request(request)

    def stage(self, candidate, context, message):
        if self.pending:
            raise PolicyError("A previous revision is awaiting activation. Retrieve context after the next decision.")
        if self.phase != "playing":
            raise PolicyError("A live match is required for a policy update.")
        current = self.contexts[-1]["obs"]
        enemies = {p["id"] for p in facts(current, self.coach_id)["enemies"]}
        then_enemies = {p["id"] for p in facts(context["speech_time"], self.coach_id)["enemies"]}
        old = {r.id: r for r in self.policy.rules}
        for r in candidate.rules:
            if old.get(r.id) == r:
                continue
            if r.scope != "temporary" and r.scope != candidate.provenance.get("scope", "match"):
                raise PolicyError("Changed rules must use the requested edit lifetime.")
            if r.target_id is not None and (r.target_id not in enemies or r.target_id not in then_enemies):
                raise PolicyError("That target is no longer visible/alive. Retrieve fresh context.")
            if r.until_tick is not None and r.until_tick <= current["tick"]:
                raise PolicyError("That temporary instruction has already expired.")
            if r.until_tick is not None and r.until_tick > context["speech_time"]["tick"] + 32 * 8:
                raise PolicyError("Temporary instructions may last at most eight seconds from their context.")
        remembered = self.remembered_after(candidate)
        before = decide(self.policy, context["speech_time"], self.coach_id)[2]
        after = decide(candidate, context["speech_time"], self.coach_id)[2]
        (self.run_dir / f"policy-{candidate.revision}.json").write_text(json.dumps(candidate.document(), indent=2))
        self.previous.append((self.policy, self.remembered))
        self.pending, self.pending_remembered = candidate, remembered
        self.log("policy_compiled", revision=candidate.revision, message=message,
                 context_id=context["context_id"], before=before, after=after,
                 policy_hash=candidate.fingerprint)
        job_id = secrets.token_hex(6)
        self.jobs[job_id] = {"status": "running", "revision": candidate.revision}
        history = [deepcopy(c["obs"]) for c in self.contexts]
        self.spawn(self.check_candidate(job_id, self.policy, candidate, history, self.coach_id))
        return {"status": "compiled_pending_activation", "revision": candidate.revision,
                "message": message, "job_id": job_id, "before": before, "after": after,
                "note": "Decision comparisons use the same observation; they are not new match outcomes."}

    async def check_candidate(self, job_id, parent, candidate, history, coach_id):
        def check():
            changed = hooks = 0
            a_memory, b_memory = {}, {}
            for obs in history:
                a, a_memory, _ = decide(parent, obs, coach_id, a_memory)
                b, b_memory, _ = decide(candidate, obs, coach_id, b_memory)
                changed += a != b
                hooks += a.get("hook_to") != b.get("hook_to")
            return {"status": "complete", "revision": candidate.revision,
                    "observations": len(history), "changed_decisions": changed,
                    "changed_hooks": hooks, "kind": "recorded-context shadow comparison",
                    "competitive": "untested", "scope": "observed decision behavior, not policy strength"}
        self.jobs[job_id] = await asyncio.to_thread(check)
        self.log("background_check", job_id=job_id, report=self.jobs[job_id])

    def record_reasoning(self, args):
        context = self.context_bundle(args["context_id"])
        result = self.reasoning.record(kind=args["kind"], text=args["text"], context=context,
                                       base_revision=args["base_semantic_revision"], subject_id=args.get("subject_id"),
                                       confidence=args.get("confidence"), prediction=args.get("prediction", ""))
        if args["kind"] == "belief":
            result["generation_request"] = self.reasoning.request(args["subject_id"], self.policy, context)
        self.log("semantic_feedback", feedback_kind=args["kind"], event_id=result["event_id"],
                 semantic_revision=result["semantic_revision"], semantic_hash=result["semantic_hash"])
        return result

    async def submit_reasoning_candidate(self, args, generator):
        request = self.reasoning.assert_current(args["request_id"], self.policy, self.match_id)
        if not isinstance(args["explanation"], str) or not 1 <= len(args["explanation"]) <= 2000:
            raise PolicyError("A generated policy needs a brief explanation of how it realizes the belief.")
        candidate, report = await asyncio.to_thread(evaluate_candidate, deepcopy(request), args["policy"], generator, args["explanation"])
        # Evaluation is asynchronous. A correction can arrive while it runs.
        self.reasoning.assert_current(args["request_id"], self.policy, self.match_id)
        submission = {"id": secrets.token_hex(8), "generator": generator, "explanation": args["explanation"],
                      "policy": candidate.document(), "policy_hash": candidate.fingerprint, "report": report}
        request["submissions"].append(submission)
        request["status"] = "ready_for_trial" if report["passed"] else "rejected"
        self.reasoning.save_request(request)
        self.log("generation_checked", request_id=request["id"], submission_id=submission["id"],
                 semantic_hash=request["semantic_hash"], policy_hash=candidate.fingerprint, report=report)
        return {"status": request["status"], "message": "Candidate checked. Inspect its evidence before trying it.",
                "request_id": request["id"], "submission": submission}

    async def reasoning_action(self, name, args, generator="external-generator"):
        if name == "record_reasoning":
            return self.record_reasoning(args)
        if name == "submit_policy_candidate":
            return await self.submit_reasoning_candidate(args, generator)
        if name == "generate_reference_candidate":
            request = self.reasoning.assert_current(args["request_id"], self.policy, self.match_id)
            return await self.submit_reasoning_candidate({"request_id": request["id"],
                "policy": reference_candidate(request),
                "explanation": "Offline reference synthesis illustrates the stated belief direction within its protected scope."},
                "offline-reference-v1")
        if name == "try_reasoning_candidate":
            request = self.reasoning.assert_current(args["request_id"], self.policy, self.match_id)
            submission = next((s for s in request["submissions"] if s["id"] == args["submission_id"]), None)
            if submission is None or not submission["report"]["passed"]:
                raise PolicyError("Only a candidate that passed its behavioral contracts can be tried.")
            candidate = compile_policy(submission["policy"])
            result = self.stage(candidate, self.context_bundle(), submission["explanation"])
            request["status"] = "trial_pending_activation"
            self.reasoning.save_request(request)
            return result
        raise PolicyError("Unknown semantic reasoning operation.")

    async def tool_call(self, name, args, call_id):
        if call_id in self.receipts:
            return self.receipts[call_id]
        if name == "get_job":
            return self.jobs.get(args["job_id"], {"status": "unknown_job"})
        if name in {"record_reasoning", "submit_policy_candidate", "try_reasoning_candidate"}:
            result = await self.reasoning_action(name, args, generator="openai-realtime")
            self.receipts[call_id] = result
            return result
        if args.get("base_revision") != self.policy.revision:
            raise PolicyError("Stale policy revision. Retrieve the current context before editing.")
        if name == "rollback_policy":
            if not self.previous or self.pending or self.phase != "playing":
                raise PolicyError("No completed edit is available to undo.")
            prior, remembered = self.previous[-1]
            doc = prior.document()
            doc["revision"] = self.policy.revision + 1
            doc["provenance"] = {"undoes_revision": self.policy.revision}
            self.pending = compile_policy(doc)
            self.pending_remembered = remembered
            self.previous.pop()
            result = {"status": "compiled_pending_activation", "revision": doc["revision"]}
        elif name == "patch_policy":
            context = self.context_bundle(args["context_id"])
            doc = self.policy.document()
            by_id = {r["id"]: r for r in doc["rules"]}
            for rule_id in args["remove_rule_ids"]:
                if rule_id not in by_id:
                    raise PolicyError(f"Rule {rule_id} does not exist.")
                del by_id[rule_id]
            for raw in args["upsert_rules"]:
                by_id[raw["id"]] = raw
            doc["rules"] = list(by_id.values())
            if args.get("retreat_percent") is not None:
                doc["retreat_percent"] = args["retreat_percent"]
            doc["revision"] += 1
            doc["provenance"] = {"instruction": args["instruction"], "context_id": args["context_id"],
                                 "call_id": call_id, "parent_hash": self.policy.fingerprint, "scope": args["scope"]}
            candidate = compile_policy(doc)
            result = self.stage(candidate, context, args["instruction"])
        else:
            raise PolicyError("Unknown tool.")
        self.receipts[call_id] = result
        return result

    def state(self):
        latest = self.contexts[-1] if self.contexts else None
        return {"csrf": self.csrf, "phase": self.phase, "match_id": self.match_id, "error": self.error,
                "game_url": self.game_url, "policy": self.policy.document(), "readable": readable(self.policy),
                "pending_revision": self.pending.revision if self.pending else None, "active_tick": self.active_tick,
                "context_id": self.latest_context_id(), "observation": latest["obs"] if latest else None,
                "trace": self.trace, "timeline": list(self.timeline)[:25], "jobs": self.jobs,
                "selected_id": self.selected_id, "voice_status": self.voice_status,
                "reasoning": self.reasoning.view(self.policy, self.match_id),
                "realtime_model": os.environ.get("OPENAI_REALTIME_MODEL", DEFAULT_MODEL),
                "voice_configured": bool(os.environ.get("OPENAI_API_KEY"))}


def create_app(demo):
    @web.middleware
    async def guard(request, handler):
        if request.method not in {"GET", "HEAD"} and request.headers.get("X-Coach-Session") != demo.csrf:
            raise web.HTTPForbidden(text="Invalid local coaching session.")
        try:
            return await handler(request)
        except (PolicyError, ValueError, KeyError, TypeError) as exc:
            return web.json_response({"error": str(exc)}, status=400)

    app = web.Application(middlewares=[guard], client_max_size=128 * 1024)

    async def state(request):
        return web.json_response(demo.state(), headers={"Cache-Control": "no-store"})

    async def start(request):
        await demo.start()
        return web.json_response(demo.state())

    async def coach(request):
        args = await request.json()
        identifier = args.get("id", secrets.token_hex(8))
        if identifier in demo.receipts:
            return web.json_response(demo.receipts[identifier])
        context = demo.context_bundle(args.get("context_id"))
        normalized = args["text"].strip().lower().rstrip(".!?")
        if normalized in {"good job", "good job, keep going", "keep going", "well done"}:
            payload = demo.record_reasoning({"kind": "encouragement", "text": args["text"],
                        "context_id": context["context_id"], "base_semantic_revision": demo.reasoning.model.revision})
            demo.receipts[identifier] = payload
            return web.json_response(payload)
        if normalized == "think of the game as a continuous unit":
            payload = demo.record_reasoning({"kind": "frame", "text": args["text"],
                        "context_id": context["context_id"], "base_semantic_revision": demo.reasoning.model.revision})
            demo.receipts[identifier] = payload
            return web.json_response(payload)
        result = interpret(args["text"], demo.policy, context["speech_time"], demo.coach_id,
                           context["selected_enemy_id"], utterance_id=identifier)
        if result.policy:
            payload = demo.stage(result.policy, context, result.message)
        else:
            payload = {"status": result.status, "message": result.message, "trace": context["trace_at_context"]}
            demo.log("coaching_response", **payload)
        demo.receipts[identifier] = payload
        return web.json_response(payload)

    async def reasoning(request):
        args = await request.json()
        identifier = args.pop("id", secrets.token_hex(8))
        if identifier in demo.receipts:
            return web.json_response(demo.receipts[identifier])
        result = await demo.reasoning_action(args.pop("operation"), args)
        demo.receipts[identifier] = result
        return web.json_response(result)

    async def reasoning_export(request):
        return web.json_response({"model": demo.reasoning.model.document(),
                                  "model_hash": demo.reasoning.model.fingerprint,
                                  "feedback": demo.reasoning.feedback,
                                  "generations": list(demo.reasoning.requests.values())},
                                 headers={"Content-Disposition": 'attachment; filename="loom-reasoning.json"'})

    async def select(request):
        args = await request.json()
        current = demo.context_bundle()["speech_time"]
        target = args.get("id")
        if target is not None and target not in {e["id"] for e in facts(current, demo.coach_id)["enemies"]}:
            raise PolicyError("Select a currently visible enemy.")
        demo.selected_id = target
        demo.contexts[-1]["selected_id"] = target
        return web.json_response({"selected_id": target})

    async def rollback(request):
        args = await request.json()
        return web.json_response(await demo.tool_call("rollback_policy", args, secrets.token_hex(8)))

    async def voice(request):
        if demo.voice:
            await demo.voice.close()
        demo.voice = RealtimeCall(demo, demo.client)
        try:
            answer = await demo.voice.connect(await request.text())
        except Exception:
            await demo.voice.close()
            demo.voice = None
            raise
        demo.voice_status = "OpenAI Realtime connected"
        return web.Response(text=answer, content_type="application/sdp")

    async def voice_stop(request):
        if demo.voice:
            await demo.voice.close()
            demo.voice = None
        demo.voice_status = "Voice disconnected"
        return web.json_response({"status": "disconnected"})

    async def game_socket(request):
        if not demo.process:
            raise web.HTTPConflict(text="Start a match first.")
        if request.headers.get("Origin") != f"http://127.0.0.1:{demo.port}":
            raise web.HTTPForbidden(text="Game connection must come from the local demo.")
        downstream = web.WebSocketResponse(max_msg_size=8 * 1024 * 1024)
        await downstream.prepare(request)
        async with demo.client.ws_connect(f"http://127.0.0.1:{demo.engine_port}/ws", max_msg_size=8 * 1024 * 1024) as upstream:
            async def relay(source, destination):
                async for msg in source:
                    if msg.type == WSMsgType.BINARY:
                        await destination.send_bytes(msg.data)
                    elif msg.type == WSMsgType.TEXT:
                        await destination.send_str(msg.data)
                await destination.close()
            tasks = [asyncio.create_task(relay(downstream, upstream)), asyncio.create_task(relay(upstream, downstream))]
            await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
            for task in tasks:
                task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)
        return downstream

    async def index(request):
        return web.FileResponse(ROOT / "coaching/web/index.html")

    async def lifecycle(app):
        demo.client = ClientSession(timeout=ClientTimeout(total=10))
        yield
        await demo.stop_match()
        await demo.client.close()

    app.cleanup_ctx.append(lifecycle)
    app.router.add_get("/", index)
    app.router.add_get("/api/state", state)
    app.router.add_post("/api/start", start)
    app.router.add_post("/api/coach", coach)
    app.router.add_post("/api/reasoning", reasoning)
    app.router.add_get("/api/reasoning/export", reasoning_export)
    app.router.add_post("/api/select", select)
    app.router.add_post("/api/rollback", rollback)
    app.router.add_post("/api/voice", voice)
    app.router.add_post("/api/voice/stop", voice_stop)
    app.router.add_get("/engine/ws", game_socket)
    app.router.add_static("/play", ASSETS, show_index=False)
    app.router.add_static("/assets", ROOT / "coaching/web", show_index=False)
    return app


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--autopilot", action="store_true", help="Use a bot for the human seat during automated checks.")
    args = parser.parse_args()
    demo = Demo(args.port, args.autopilot)
    web.run_app(create_app(demo), host="127.0.0.1", port=args.port)


if __name__ == "__main__":
    main()
