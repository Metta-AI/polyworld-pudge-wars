"""Rebuild the measured-speed, aim-only experiment from the frozen baseline."""
from pathlib import Path

root = Path(__file__).resolve().parent
source = (root / "baseline.bas").read_text()

def replace_once(marker, replacement):
    global source
    if source.count(marker) != 1:
        raise ValueError(f"Expected exactly one insertion point: {marker}")
    source = source.replace(marker, replacement)

replace_once("dim lanes(9)", "dim lanes(9)\n" + "\n".join(
    f"dim reel{name}(9)" for name in ["X", "Y", "Tick", "Seen", "Phase", "Speed"]))
replace_once("peak(me) = selfMaxHp", (root / "observe-v9.bas").read_text() + "\npeak(me) = selfMaxHp")
marker = r"  throwAt((px(catchTarget) + px(reeler)) \ 2, (py(catchTarget) + py(reeler)) \ 2, 0)"
replace_once(marker, (root / "aim-v9.bas").read_text() + marker)
(root / "candidate-v9.bas").write_text(source)
