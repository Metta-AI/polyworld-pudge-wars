"""Build the anticipatory double-hook policy from the frozen local baseline."""
from pathlib import Path

root = Path(__file__).resolve().parent
source = (root / "baseline.bas").read_text()
marker = "' E06b: prefer wounded ally/enemy melee midpoints, excluding only that ally."
if source.count(marker) != 1:
    raise ValueError("Expected exactly one double-hook insertion point")
source = source.replace(marker, (root / "precast.bas").read_text() + "\n" + marker)
(root / "candidate.bas").write_text(source)
