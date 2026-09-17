#!/usr/bin/env python3
"""Iteration ledger for the Pudge Wars auto-optimizer campaign.

One JSON record per policy iteration lives in ledger.jsonl; LEDGER.md is
rendered from it. Every record carries the LLM compute cost of the Devin session
that produced it (ACUs, the unit Devin bills in) plus the hosted eval compute
spend, so cost per iteration is never reconstructed from memory.

    ledger.py start --iteration 1 --session <devin_id> --mode ultra \
        --change "one-line attributable change" --hypothesis experiments/001-x.md
    ledger.py set --iteration 1 policy_ref=pudge-auto-optimizer:v2 \
        policy_version_id=<uuid> image_digest=sha256:... eval_id=cfeval_...
    ledger.py cost --iteration 1 --acus 3.25 [--final] [--session <devin_id>]
    ledger.py hosted-cost --iteration 1 --spent-before 64.17 --spent-after 71.02
    ledger.py verdict --iteration 1 --decision promote|reject|no_signal|rerun \
        --summary "candidate 0.61±0.05 vs baseline 0.55±0.05, n=100"
    ledger.py render
    ledger.py show [--iteration N]
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
LEDGER = ROOT / "ledger.jsonl"
RENDERED = ROOT / "LEDGER.md"
STATE = ROOT / "STATE.json"

FIELDS = [
    "iteration", "started_at", "finished_at", "devin_session_id", "devin_session_url", "devin_mode",
    "change", "hypothesis", "base_ref", "policy_ref", "policy_version_id", "image_digest", "source_commit",
    "eval_id", "eval_kind", "eval_n_clean", "eval_n_tainted", "verdict", "verdict_summary",
    "llm_cost_acus", "llm_cost_acus_final", "llm_cost_usd", "hosted_compute_usd", "notes",
]


def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def load() -> list[dict[str, Any]]:
    if not LEDGER.exists():
        return []
    return [json.loads(line) for line in LEDGER.read_text().splitlines() if line.strip()]


def dump(rows: list[dict[str, Any]]) -> None:
    LEDGER.write_text("".join(json.dumps(r, sort_keys=True) + "\n" for r in rows))
    render(rows)


def find(rows: list[dict[str, Any]], iteration: int) -> dict[str, Any]:
    for r in rows:
        if r["iteration"] == iteration:
            return r
    sys.exit(f"iteration {iteration} not in ledger")


def usd(row: dict[str, Any]) -> float | None:
    rate = json.loads(STATE.read_text()).get("cost", {}).get("usd_per_acu")
    acus = row.get("llm_cost_acus")
    return round(rate * acus, 2) if rate is not None and acus is not None else None


def render(rows: list[dict[str, Any]]) -> None:
    lines = [
        "# Pudge Wars auto-optimizer ledger",
        "",
        "Rendered from `ledger.jsonl` by `tools/ledger.py render`; do not edit by hand.",
        "LLM cost is the Devin session's ACU consumption (`acus_consumed` from the Devin",
        "session API); `final=no` means the session was still running when recorded and",
        "the next session must backfill it with `ledger.py cost --final`. USD is only",
        "filled when `cost.usd_per_acu` is set in STATE.json. Hosted compute is the",
        "Coworld daily-budget delta observed across the iteration's evals.",
        "",
        "| Iter | Started (UTC) | Devin session | Mode | Change | Policy | Eval | Verdict | LLM cost (ACU) | Final | LLM USD | Hosted USD |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    total_acus = 0.0
    total_hosted = 0.0
    for r in rows:
        acus = r.get("llm_cost_acus")
        total_acus += acus or 0.0
        total_hosted += r.get("hosted_compute_usd") or 0.0
        session = f"[{r.get('devin_session_id', '')[:8]}]({r['devin_session_url']})" if r.get("devin_session_url") else r.get("devin_session_id", "")
        policy = f"`{r.get('policy_ref', '')}`" if r.get("policy_ref") else ""
        ev = f"`{r['eval_id']}` ({r.get('eval_kind', '')}, clean {r.get('eval_n_clean', '?')}/taint {r.get('eval_n_tainted', '?')})" if r.get("eval_id") else ""
        verdict = f"**{r['verdict']}** — {r.get('verdict_summary', '')}" if r.get("verdict") else "pending"
        lines.append("| " + " | ".join([
            str(r["iteration"]), r.get("started_at", "")[:16], session, r.get("devin_mode", ""),
            (r.get("change") or "").replace("|", "/"), policy, ev, verdict.replace("|", "/"),
            f"{acus:.2f}" if acus is not None else "unrecorded",
            "yes" if r.get("llm_cost_acus_final") else "no",
            f"{r['llm_cost_usd']:.2f}" if r.get("llm_cost_usd") is not None else "",
            f"{r['hosted_compute_usd']:.2f}" if r.get("hosted_compute_usd") is not None else "",
        ]) + " |")
    lines += ["", f"Totals: {total_acus:.2f} ACU across {len(rows)} iteration(s); hosted compute ${total_hosted:.2f}.", ""]
    RENDERED.write_text("\n".join(lines))


def cmd_start(a: argparse.Namespace) -> None:
    rows = load()
    if any(r["iteration"] == a.iteration for r in rows):
        sys.exit(f"iteration {a.iteration} already exists; use `set`")
    rows.append({
        "iteration": a.iteration, "started_at": now(), "devin_session_id": a.session,
        "devin_session_url": f"https://app.devin.ai/sessions/{a.session.removeprefix('devin-')}" if a.session else None,
        "devin_mode": a.mode, "change": a.change, "hypothesis": a.hypothesis, "base_ref": a.base_ref,
        "llm_cost_acus": None, "llm_cost_acus_final": False,
    })
    dump(rows)
    print(f"started iteration {a.iteration}")


def cmd_set(a: argparse.Namespace) -> None:
    rows = load()
    row = find(rows, a.iteration)
    for kv in a.pairs:
        key, _, value = kv.partition("=")
        if key not in FIELDS:
            sys.exit(f"unknown field {key}; known: {FIELDS}")
        try:
            row[key] = json.loads(value)
        except json.JSONDecodeError:
            row[key] = value
    dump(rows)
    print(json.dumps(row, indent=2, sort_keys=True))


def cmd_cost(a: argparse.Namespace) -> None:
    rows = load()
    row = find(rows, a.iteration)
    if a.session and row.get("devin_session_id") and a.session != row["devin_session_id"]:
        sys.exit(f"session mismatch: ledger has {row['devin_session_id']}, got {a.session}")
    row["llm_cost_acus"] = a.acus
    row["llm_cost_acus_final"] = bool(a.final)
    row["llm_cost_recorded_at"] = now()
    row["llm_cost_usd"] = usd(row)
    dump(rows)
    print(f"iteration {a.iteration}: {a.acus} ACU final={bool(a.final)} usd={row['llm_cost_usd']}")


def cmd_hosted_cost(a: argparse.Namespace) -> None:
    rows = load()
    row = find(rows, a.iteration)
    row["hosted_compute_usd"] = round((row.get("hosted_compute_usd") or 0.0) + max(0.0, a.spent_after - a.spent_before), 2)
    dump(rows)
    print(f"iteration {a.iteration}: hosted compute ${row['hosted_compute_usd']:.2f}")


def cmd_verdict(a: argparse.Namespace) -> None:
    rows = load()
    row = find(rows, a.iteration)
    row["verdict"] = a.decision
    row["verdict_summary"] = a.summary
    row["finished_at"] = now()
    dump(rows)
    print(f"iteration {a.iteration}: {a.decision}")


def cmd_render(_: argparse.Namespace) -> None:
    render(load())
    print(f"rendered {RENDERED}")


def cmd_show(a: argparse.Namespace) -> None:
    rows = load()
    print(json.dumps(find(rows, a.iteration) if a.iteration is not None else rows, indent=2, sort_keys=True))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("start"); p.add_argument("--iteration", type=int, required=True); p.add_argument("--session", required=True)
    p.add_argument("--mode", default="ultra"); p.add_argument("--change", required=True); p.add_argument("--hypothesis")
    p.add_argument("--base-ref"); p.set_defaults(fn=cmd_start)
    p = sub.add_parser("set"); p.add_argument("--iteration", type=int, required=True); p.add_argument("pairs", nargs="+"); p.set_defaults(fn=cmd_set)
    p = sub.add_parser("cost"); p.add_argument("--iteration", type=int, required=True); p.add_argument("--acus", type=float, required=True)
    p.add_argument("--final", action="store_true"); p.add_argument("--session"); p.set_defaults(fn=cmd_cost)
    p = sub.add_parser("hosted-cost"); p.add_argument("--iteration", type=int, required=True)
    p.add_argument("--spent-before", type=float, required=True); p.add_argument("--spent-after", type=float, required=True); p.set_defaults(fn=cmd_hosted_cost)
    p = sub.add_parser("verdict"); p.add_argument("--iteration", type=int, required=True)
    p.add_argument("--decision", required=True, choices=["promote", "reject", "no_signal", "rerun", "baseline", "weak_evidence"])
    p.add_argument("--summary", required=True); p.set_defaults(fn=cmd_verdict)
    sub.add_parser("render").set_defaults(fn=cmd_render)
    p = sub.add_parser("show"); p.add_argument("--iteration", type=int); p.set_defaults(fn=cmd_show)
    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
