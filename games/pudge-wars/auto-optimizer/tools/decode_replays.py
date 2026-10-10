#!/usr/bin/env python3
"""Download and decode the hosted replays of a summarized XP eval.

    decode_replays.py --label iter3-directional --decoder /path/to/pwheadless [--root DIR]

Reads evals/<label>/summary.json (from `hosted.py xp summarize`), fetches every
clean episode's `replay.pwr` through the API (no S3 access needed), writes the
replay root layout that replay_survey.py / edge_exposure.py consume
(`ROOT/<ereq_id>/row.json`, `replay.pwr`, `decoder.log`,
`decoded/latest/events.jsonl`) and refuses to count an episode whose decoder
log does not say `replay verified: every tick matched`.

The decoder is `nim c -d:release -d:headless -o:pwheadless
examples/pudge_wars/pw.nim` built from the game source that produced the
tapes. Replays (~2 MB each) are written under the git-ignored .runtime/ tree
by default; only the survey JSON they produce is committed.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hosted import EVALS, client, save_json  # noqa: E402

RUNTIME = EVALS.parent / ".runtime" / "replays"
VERIFIED = "replay verified: every tick matched"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--label", required=True)
    ap.add_argument("--decoder", required=True)
    ap.add_argument("--root", help=f"replay root (default {RUNTIME}/<label>)")
    ap.add_argument("--limit", type=int)
    a = ap.parse_args()
    summary = json.loads((EVALS / a.label / "summary.json").read_text())
    root = Path(a.root) if a.root else RUNTIME / a.label
    root.mkdir(parents=True, exist_ok=True)
    rows = summary["clean_rows"][: a.limit] if a.limit else summary["clean_rows"]
    status = []
    with client() as c:
        for row in rows:
            ep_dir = root / row["id"]
            ep_dir.mkdir(exist_ok=True)
            save_json(ep_dir / "row.json", row)
            tape = ep_dir / "replay.pwr"
            if not tape.exists():
                tape.write_bytes(c.get_bytes(f"/v2/episode-requests/{row['id']}/artifacts/replay"))
            log = ep_dir / "decoder.log"
            events = ep_dir / "decoded" / "latest" / "events.jsonl"
            if not (events.exists() and log.exists() and VERIFIED in log.read_text()):
                proc = subprocess.run([a.decoder, "--replay", str(tape), "--duellog", str(ep_dir / "decoded")],
                                      capture_output=True, text=True, timeout=600)
                log.write_text(proc.stdout + proc.stderr)
                latest = sorted((ep_dir / "decoded").glob("match_*"))
                if latest and not events.exists():
                    (ep_dir / "decoded" / "latest").symlink_to(latest[-1].name)
            ok = events.exists() and VERIFIED in log.read_text()
            status.append({"id": row["id"], "verified": ok, "bytes": tape.stat().st_size})
            print(f"{row['id']} verified={ok}")
    save_json(EVALS / a.label / "replay_decode.json",
              {"root": str(root), "decoder": a.decoder, "episodes": len(status),
               "verified": sum(s["verified"] for s in status), "rows": status})
    print(f"{sum(s['verified'] for s in status)}/{len(status)} replays verified -> {root}")


if __name__ == "__main__":
    main()
