"""Offline belief-intervention demonstration, not a model-quality experiment."""
import argparse
from dataclasses import replace
import json
from pathlib import Path
import tempfile

from .policy import compile_policy, initial_policy
from .reasoning import ReasoningLab, evaluate_candidate, probe_observation, reference_candidate


def evaluate():
    records = []
    parent = compile_policy(initial_policy().document())
    for belief_id in ("catch_value", "punishment_risk"):
        for confidence in (0.2, 0.8):
            with tempfile.TemporaryDirectory() as directory:
                lab = ReasoningLab(Path(directory))
                lab.model = replace(lab.model, beliefs=tuple(replace(b, confidence=confidence) if b.id == belief_id else b for b in lab.model.beliefs))
                request = lab.request(belief_id, parent, {"match_id": "synthetic", "context_id": "synthetic:100", "speech_time": probe_observation()})
                for variant in (0, 1):
                    policy, report = evaluate_candidate(request, reference_candidate(request, variant),
                                                        "offline-reference-v1", "Controlled belief intervention.")
                    records.append({"belief_id": belief_id, "confidence": confidence, "variant": variant,
                                    "semantic_hash": lab.model.fingerprint, "policy_hash": policy.fingerprint,
                                    "retreat_percent": policy.retreat_percent, "report": report})
    return {"kind": "offline reference-synthesis contract demonstration", "model_calls": 0,
            "candidates": len(records), "passed": sum(r["report"]["passed"] for r in records),
            "limitation": "The reference mapping encodes the desired direction. This verifies plumbing and contracts, not the research hypothesis or competitive strength.",
            "records": records}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=Path("tmp/coaching/belief-intervention.json"))
    args = parser.parse_args()
    report = evaluate()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(f"{report['passed']}/{report['candidates']} reference candidates passed; {report['model_calls']} model calls.")
    print(report["limitation"])
    print(args.output)
    if report["passed"] != report["candidates"]:
        raise SystemExit(1)


if __name__ == "__main__": main()
