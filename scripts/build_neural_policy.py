#!/usr/bin/env python3
"""Build the illustrative tensor policy ZIP; no ML framework is required."""
import argparse
import json
from pathlib import Path
import struct
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def build(output: Path) -> None:
    tensors, weights = [], bytearray()
    for name, shape, values in [
        ("encoder", [6, 6], [float(row == col) for row in range(6) for col in range(6)]),
        ("policy", [3, 6], [-3, 0, 0, 0, 0, 0, 0, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        ("bias", [3], [0.7, -2, 0.1]),
    ]:
        tensors.append({"name": name, "dtype": "float32", "shape": shape,
                        "resource": "weights.bin", "offset": len(weights)})
        weights.extend(struct.pack(f"<{len(values)}f", *values))
    output.parent.mkdir(parents=True, exist_ok=True)
    entries = {"policy.bas": (ROOT / "examples/pudge_wars/players/neural.bas").read_bytes(),
               "tensors.json": json.dumps({"tensors": tensors}).encode(), "weights.bin": weights}
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, data in entries.items():
            info = zipfile.ZipInfo(name, date_time=(2026, 10, 9, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, data)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "tmp/pudge-neural.zip")
    args = parser.parse_args()
    build(args.output)
    print(args.output)
