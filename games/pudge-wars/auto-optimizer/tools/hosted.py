#!/usr/bin/env python3
"""Hosted-evaluation helpers for the Pudge Wars auto-optimizer campaign.

Every subcommand reads campaign constants from STATE.json (league, coworld,
identity) and writes durable evidence under the campaign's evals/ directory so a
fresh session can resume from disk.

    hosted.py whoami                       # assert the active Coworld player
    hosted.py budget                       # Coworld daily compute budget
    hosted.py versions                     # our policy versions (name, vN, id)
    hosted.py cf create --candidate <ref> [--baseline <ref>] [--n N] --label L
    hosted.py cf poll <cfeval_id> --label L [--timeout SEC]
    hosted.py cf summarize --label L       # taint filter + per-slot readout
    hosted.py xp create --policy <ref> --label L [--episodes N] [--top-n K]
    hosted.py xp poll <xreq_id> --label L
    hosted.py xp summarize --label L --policy <version-id>
    hosted.py logs <episode_request_id> --policy <version-id> --agent IDX

A <ref> is `name:vN` or a policy-version UUID.
"""
from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

import httpx
from coworld.api_client import CoworldApiClient
from softmax import auth as softmax_auth

ROOT = Path(__file__).resolve().parents[1]
STATE_PATH = ROOT / "STATE.json"
EVALS = ROOT / "evals"
SERVER = "https://softmax.com/api"


def state() -> dict[str, Any]:
    return json.loads(STATE_PATH.read_text())


def save_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True, default=str) + "\n")


def client(*, user: bool = False) -> CoworldApiClient:
    """Player-session client (writes as our player) or user-token client (reads
    across players: other people's versions, budget)."""
    if user:
        token = softmax_auth.load_user_token(server=SERVER)
        if token is None:
            sys.exit("no user token; run: softmax set-token \"$SOFTMAX_USER_API_TOKEN\"")
        return CoworldApiClient(server_url=SERVER, token=token)
    return CoworldApiClient.from_login(server_url=SERVER)


def entries(page: Any) -> list[dict[str, Any]]:
    return page if isinstance(page, list) else page.get("entries", [])


def raw_get(c: CoworldApiClient, path: str, **params: Any) -> Any:
    response = c._http_client.get(path, headers=c._headers(), params=params or None, timeout=60.0)
    response.raise_for_status()
    return response.json()


def raw_post(c: CoworldApiClient, path: str, body: dict[str, Any]) -> Any:
    response = c._http_client.post(path, headers=c._headers(), json=body, timeout=120.0)
    if response.status_code >= 400:
        sys.exit(f"{path} -> {response.status_code}: {response.text[:800]}")
    return response.json()


def resolve_ref(ref: str) -> tuple[str, str]:
    """Return (policy_version_id, label) for `name:vN` or a UUID (user-token read)."""
    with client(user=True) as c:
        if ":" not in ref:
            row = raw_get(c, f"/stats/policy-versions/{ref}")
            return ref, f"{row.get('name') or row.get('policy_name')}:v{row['version']}"
        name, version = ref.rsplit(":v", 1)
        page = raw_get(c, "/stats/policy-versions", name_exact=name, version=int(version), limit=10)
    for row in entries(page):
        if row.get("name") == name and int(row.get("version", -1)) == int(version):
            return row["id"], ref
    sys.exit(f"policy version not found: {ref}")


def binom_se(p: float, n: int) -> float:
    return math.sqrt(p * (1 - p) / n) if n else float("nan")


# ----------------------------------------------------------------------------
# identity / budget / versions
# ----------------------------------------------------------------------------

def cmd_whoami(_: argparse.Namespace) -> None:
    want = state()["identity"]["player_id"]
    out = subprocess.run(["coworld", "player", "list", "--json"], check=True, capture_output=True, text=True).stdout
    players = json.loads(out)
    rows = players if isinstance(players, list) else players.get("players", players.get("entries", []))
    active = [p for p in rows if p.get("active")]
    if len(active) != 1 or active[0]["id"] != want:
        names = [(p["id"], p.get("name")) for p in active]
        sys.exit(f"active player is {names}, expected {want}. Run: coworld player use {want}")
    print(f"active player OK: {active[0]['id']} ({active[0].get('name')})")


def cmd_budget(_: argparse.Namespace) -> None:
    with client(user=True) as c:
        b = raw_get(c, f"/v2/coworlds/{state()['coworld']['name']}/budget")
    print(json.dumps({k: b[k] for k in ("daily_budget_usd", "spent_today_usd", "remaining_usd", "resets_at", "budget_status")}, indent=2))


def cmd_versions(_: argparse.Namespace) -> None:
    name = state()["identity"]["policy_name"]
    with client() as c:
        page = raw_get(c, "/stats/policy-versions", name_exact=name, limit=100)
    for row in sorted(entries(page), key=lambda r: int(r.get("version", 0))):
        if row.get("name") != name:
            continue
        print(f"{name}:v{row['version']}  {row['id']}  {row.get('created_at')}  tags={row.get('tags')}")


# ----------------------------------------------------------------------------
# counterfactual evals: candidate replaces the baseline in the baseline's own
# ladder games (same seed, same opponent, same fillers).
# ----------------------------------------------------------------------------

def cmd_cf_create(args: argparse.Namespace) -> None:
    st = state()
    baseline_ref = args.baseline or st["reference"]["ladder_anchor_ref"]
    cand_id, cand_label = resolve_ref(args.candidate)
    base_id, base_label = resolve_ref(baseline_ref)
    with client(user=True) as c:
        body = {
            "candidate_policy_version_id": cand_id,
            "baseline_policy_version_id": base_id,
            "league_id": st["league"]["id"],
            "source": "tournament",
            "n": args.n,
            "idempotency_key": f"pudge-auto-optimizer:{args.label}:{cand_id}:{base_id}:{args.n}",
        }
        out_dir = EVALS / args.label
        save_json(out_dir / "cf-request.json", {**body, "candidate_label": cand_label, "baseline_label": base_label})
        result = raw_post(c, "/v2/counterfactual-evals", body)
    save_json(out_dir / "cf-eval.json", result)
    print(json.dumps({"id": result["id"], "status": result["status"], "candidate": cand_label, "baseline": base_label, "n": args.n}))


def cmd_cf_poll(args: argparse.Namespace) -> None:
    out_dir = EVALS / args.label
    deadline = time.time() + args.timeout
    with client(user=True) as c:
        while True:
            result = raw_get(c, f"/v2/counterfactual-evals/{args.cfeval_id}")
            save_json(out_dir / "cf-eval.json", result)
            done = sum(1 for p in result.get("pairs", []) if p.get("outcome") is not None)
            print(f"{result['status']} paired={result.get('n_paired')} scored={done}/{result.get('n_requested')} "
                  f"W/N/L={result.get('wins')}/{result.get('neutrals')}/{result.get('losses')}", flush=True)
            if result["status"] in ("completed", "failed", "skipped", "cancelled") or time.time() > deadline:
                break
            time.sleep(args.interval)
    if result["status"] != "completed":
        print(f"not complete: status={result['status']} skip_reason={result.get('skip_reason')} error={result.get('error')}")


def cmd_cf_summarize(args: argparse.Namespace) -> None:
    out_dir = EVALS / args.label
    result = json.loads((out_dir / "cf-eval.json").read_text())
    pairs = result.get("pairs", [])
    rows: list[dict[str, Any]] = []
    taint: list[dict[str, Any]] = []
    with client(user=True) as c:
        for p in pairs:
            row = dict(p)
            ereq = p.get("candidate_episode_request_id")
            if ereq:
                try:
                    detail = raw_get(c, f"/v2/episode-requests/{ereq}")
                except httpx.HTTPError as exc:  # keep going; record the gap
                    detail = {"status": "unknown", "error": str(exc)}
                row["candidate_status"] = detail.get("status")
                row["candidate_error"] = detail.get("error")
                row["candidate_error_type"] = detail.get("error_type")
                row["candidate_failed_policy_index"] = detail.get("failed_policy_index")
                row["opponent"] = [
                    f"{q.get('policy_name')}:v{q.get('version')}"
                    for q in detail.get("participants", [])
                    if q.get("kind") == "policy" and not q.get("is_filler")
                    and q.get("policy_version_id") != result["candidate_policy_version_id"]
                ]
            if p.get("outcome") is None or row.get("candidate_status") not in (None, "completed"):
                taint.append(row)
            else:
                rows.append(row)
    save_json(out_dir / "cf-pairs.json", {"clean": rows, "tainted": taint})

    def tally(sel: list[dict[str, Any]]) -> dict[str, Any]:
        n = len(sel)
        wins = sum(1 for r in sel if r["outcome"] == 1)
        losses = sum(1 for r in sel if r["outcome"] == -1)
        cand = [r["candidate_score"] for r in sel if r.get("candidate_score") is not None]
        base = [r["baseline_score"] for r in sel if r.get("baseline_score") is not None]
        cand_rate = sum(cand) / len(cand) if cand else float("nan")
        base_rate = sum(base) / len(base) if base else float("nan")
        return {
            "n": n, "wins": wins, "neutral": n - wins - losses, "losses": losses,
            "net_score": (wins - losses) / n if n else None,
            "candidate_win_rate": cand_rate, "candidate_se": binom_se(cand_rate, len(cand)) if cand else None,
            "baseline_win_rate_same_games": base_rate, "baseline_se": binom_se(base_rate, len(base)) if base else None,
        }

    by_slot = {}
    for slot in sorted({r["probe_slot"] for r in rows}):
        by_slot[f"slot_{slot}"] = tally([r for r in rows if r["probe_slot"] == slot])
    by_opp: dict[str, Any] = {}
    for r in rows:
        key = ",".join(r.get("opponent") or ["?"])
        by_opp.setdefault(key, []).append(r)
    summary = {
        "cfeval_id": result["id"], "status": result["status"], "verdict_platform": result.get("verdict"),
        "candidate": result.get("candidate_policy_label"), "baseline": result.get("baseline_policy_label"),
        "requested": result.get("n_requested"), "clean": len(rows), "tainted": len(taint),
        "taint_rate": len(taint) / max(1, len(pairs)),
        "overall": tally(rows), "by_probe_slot": by_slot,
        "by_opponent": {k: tally(v) for k, v in sorted(by_opp.items())},
        "taint_reasons": sorted({str(t.get("candidate_error_type") or t.get("candidate_status") or "unscored") for t in taint}),
    }
    save_json(out_dir / "summary.json", summary)
    o = summary["overall"]
    print(f"{summary['candidate']} vs {summary['baseline']} in {summary['baseline']}'s ladder games: "
          f"clean n={o['n']} (tainted {len(taint)}), candidate win rate {o['candidate_win_rate']:.3f}±{(o['candidate_se'] or 0):.3f} "
          f"vs baseline {o['baseline_win_rate_same_games']:.3f}±{(o['baseline_se'] or 0):.3f} on the same games; "
          f"pairwise W/N/L={o['wins']}/{o['neutral']}/{o['losses']} net={o['net_score']}; platform verdict={summary['verdict_platform']}")
    for k, v in by_slot.items():
        print(f"  {k}: n={v['n']} cand={v['candidate_win_rate']:.3f} base={v['baseline_win_rate_same_games']:.3f} W/N/L={v['wins']}/{v['neutral']}/{v['losses']}")
    for k, v in summary["by_opponent"].items():
        print(f"  vs {k}: n={v['n']} cand={v['candidate_win_rate']:.3f} base={v['baseline_win_rate_same_games']:.3f}")


# ----------------------------------------------------------------------------
# experience requests (fresh episodes on the league field)
# ----------------------------------------------------------------------------

def cmd_xp_create(args: argparse.Namespace) -> None:
    st = state()
    pid, label = resolve_ref(args.policy)
    roster = [{"player": {"policy_ref": pid}, "slot": -1}]
    if args.opponent:
        oid, olabel = resolve_ref(args.opponent)
        roster.append({"player": {"policy_ref": oid}, "slot": -1})
    else:
        olabel = f"top_n={args.top_n}"
        roster.append({"player": {"top_n": args.top_n}, "slot": -1})
    with client() as c:
        body = {
            "idempotency_key": f"pudge-auto-optimizer:{args.label}",
            "private": False,
            "target": {"league_id": st["league"]["id"]},
            "roster": roster,
            "num_episodes": args.episodes,
            "notes": f"pudge-auto-optimizer {args.label}: {label} vs {olabel}",
        }
        out_dir = EVALS / args.label
        save_json(out_dir / "request-body.json", body)
        result = raw_post(c, "/v2/experience-requests", body)
    save_json(out_dir / "xp_request.json", result)
    print(json.dumps({"id": result["id"], "status": result["status"], "episodes": result.get("episode_count")}))


def cmd_xp_poll(args: argparse.Namespace) -> None:
    out_dir = EVALS / args.label
    deadline = time.time() + args.timeout
    with client() as c:
        while True:
            result = raw_get(c, f"/v2/experience-requests/{args.xreq_id}")
            save_json(out_dir / "xp_request.json", result)
            print(f"{result['status']} completed={result.get('completed_count')} failed={result.get('failed_count')} "
                  f"running={result.get('running_count')} pending={result.get('pending_count')}/{result.get('episode_count')}", flush=True)
            terminal = result["status"] in ("completed", "failed", "cancelled") or (
                result.get("completed_count", 0) + result.get("failed_count", 0) >= result.get("episode_count", 1))
            if terminal or time.time() > deadline:
                break
            time.sleep(args.interval)


def cmd_xp_summarize(args: argparse.Namespace) -> None:
    out_dir = EVALS / args.label
    with client() as c:
        episodes = raw_get(c, f"/v2/experience-requests/{args.xreq_id}/episodes") if args.xreq_id else \
            json.loads((out_dir / "xp_request.json").read_text())["episodes"]
    save_json(out_dir / "episodes.json", episodes)
    pid, _ = resolve_ref(args.policy)
    clean: list[dict[str, Any]] = []
    taint: list[dict[str, Any]] = []
    for ep in episodes:
        mine = [p for p in ep.get("participants", []) if p.get("policy_version_id") == pid]
        score = next((s["score"] for s in ep.get("scores") or [] if s["policy_version_id"] == pid), None)
        if ep.get("status") != "completed" or not mine or score is None:
            taint.append({"id": ep["id"], "status": ep.get("status"), "error_type": ep.get("error_type"), "error": ep.get("error"),
                          "reason": "not completed" if ep.get("status") != "completed" else "policy absent" if not mine else "unscored"})
            continue
        seats = len(ep["participants"])
        opp = [f"{p['policy_name']}:v{p['version']}" for p in ep["participants"]
               if p.get("kind") == "policy" and not p.get("is_filler") and p.get("policy_version_id") != pid]
        clean.append({"id": ep["id"], "episode_id": ep.get("episode_id"), "slot": mine[0]["position"], "seats": seats,
                      "team": "west" if mine[0]["position"] < seats / 2 else "east",
                      "score": score, "opponents": opp, "variant": ep.get("variant_name"), "cost_usd": ep.get("cost_usd"),
                      "replay_url": ep.get("replay_url")})

    def tally(sel: list[dict[str, Any]]) -> dict[str, Any]:
        n = len(sel)
        p = sum(r["score"] for r in sel) / n if n else float("nan")
        return {"n": n, "win_rate": p, "se": binom_se(p, n) if n else None}

    summary = {
        "xreq_id": args.xreq_id, "policy": args.policy, "clean": len(clean), "tainted": len(taint),
        "taint_rate": len(taint) / max(1, len(episodes)), "overall": tally(clean),
        "by_team": {t: tally([r for r in clean if r["team"] == t]) for t in ("west", "east")},
        "by_opponent": {k: tally([r for r in clean if ",".join(r["opponents"]) == k])
                        for k in sorted({",".join(r["opponents"]) for r in clean})},
        "taint_reasons": sorted({str(t.get("error_type") or t.get("reason")) for t in taint}),
        "hosted_cost_usd": round(sum(ep.get("cost_usd") or 0 for ep in episodes), 4),
    }
    save_json(out_dir / "summary.json", {**summary, "clean_rows": clean, "tainted_rows": taint})
    o = summary["overall"]
    print(f"{args.policy}: clean n={o['n']} (tainted {len(taint)}), win rate {o['win_rate']:.3f}±{(o['se'] or 0):.3f}")
    for k, v in summary["by_team"].items():
        print(f"  {k}: n={v['n']} win={v['win_rate']:.3f}")
    for k, v in summary["by_opponent"].items():
        print(f"  vs {k}: n={v['n']} win={v['win_rate']:.3f}")


def cmd_logs(args: argparse.Namespace) -> None:
    with client() as c:
        text = c.get_text(f"/v2/episode-requests/{args.episode_request_id}/{args.policy}/policy-logs/{args.agent}")
    if args.out:
        Path(args.out).parent.mkdir(parents=True, exist_ok=True)
        Path(args.out).write_text(text)
    tracebacks = text.count("Traceback (most recent call last)")
    print(f"{len(text)} bytes, tracebacks={tracebacks}")
    if not args.out:
        print(text[-4000:])


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("whoami").set_defaults(fn=cmd_whoami)
    sub.add_parser("budget").set_defaults(fn=cmd_budget)
    sub.add_parser("versions").set_defaults(fn=cmd_versions)

    cf = sub.add_parser("cf").add_subparsers(dest="sub", required=True)
    p = cf.add_parser("create"); p.add_argument("--candidate", required=True); p.add_argument("--baseline")
    p.add_argument("--n", type=int, default=None); p.add_argument("--label", required=True); p.set_defaults(fn=cmd_cf_create)
    p = cf.add_parser("poll"); p.add_argument("cfeval_id"); p.add_argument("--label", required=True)
    p.add_argument("--timeout", type=int, default=3600); p.add_argument("--interval", type=int, default=60); p.set_defaults(fn=cmd_cf_poll)
    p = cf.add_parser("summarize"); p.add_argument("--label", required=True); p.set_defaults(fn=cmd_cf_summarize)

    xp = sub.add_parser("xp").add_subparsers(dest="sub", required=True)
    p = xp.add_parser("create"); p.add_argument("--policy", required=True); p.add_argument("--opponent")
    p.add_argument("--top-n", type=int, default=3); p.add_argument("--episodes", type=int, default=2)
    p.add_argument("--label", required=True); p.set_defaults(fn=cmd_xp_create)
    p = xp.add_parser("poll"); p.add_argument("xreq_id"); p.add_argument("--label", required=True)
    p.add_argument("--timeout", type=int, default=3600); p.add_argument("--interval", type=int, default=60); p.set_defaults(fn=cmd_xp_poll)
    p = xp.add_parser("summarize"); p.add_argument("--label", required=True); p.add_argument("--policy", required=True)
    p.add_argument("--xreq-id", dest="xreq_id"); p.set_defaults(fn=cmd_xp_summarize)

    p = sub.add_parser("logs"); p.add_argument("episode_request_id"); p.add_argument("--policy", required=True)
    p.add_argument("--agent", type=int, default=0); p.add_argument("--out"); p.set_defaults(fn=cmd_logs)

    args = ap.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
