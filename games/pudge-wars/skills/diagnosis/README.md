# Diagnose a Pudge policy

Start with [META.md](../../META.md), [closed_levers.md](../../closed_levers.md)
and the [replay survey binding](../replay-inspection/README.md). Separate 1v1
from 3v3 and each opponent/version. Translate each finding into a falsifiable
mechanism at a specific policy branch before changing it.

| Failure class | Evidence to collect | Main source |
| --- | --- | --- |
| Lost pressure | Throws/minute, ready-but-unused periods, rejected/suppressed shots, visibility and active hook lifetimes | `coworld/player/base.py`: `throw`, fog fallback, rescue hold |
| Unsafe team support | Effective ally healing, unnecessary displacement, duplicate rescuers, chain steals | `base.py`: ally segment guard and rescue ownership; `sim.nim`: `latchHook` |
| Contested rune / lost formation | All-alive pair distances, collector assignments, rune wins, clear firing lanes | `base.py`: lane rank and `rune_next` movement override |
| Failed defense / capture | Threat heading, Blink readiness/use, first catch, escape and subsequent death | `base.py`: `threat`, Blink, river and low-HP branches |
| Failed conversion | Enemy catch → follow-up headshot/melee/kill; danger to other allies | `base.py`: `caught`, `brawl`, attack and Rot branches |
| Economy or vision stall | Real purchases, effective heals, missed shop visits, upgrade points and ward version | `base.py`: shop and modern-ward branches |
| Execution failure | Observation age, sent/accepted actions, rejected reason, exceptions or budget exhaustion | `coworld_host.nim`, policy driver/private logs |

These are investigation categories, not assertions that every failure is
present. Logged kill causes are estimates. Current v10 has no decision trace;
announce that limitation when intent or branch exposure cannot be established.
Do not label all friendly catches as errors: live ally hooks heal 120 HP.

Present a small set of independent hypotheses: stop a harmful behavior,
enable a missing capability, or make an observed strength more dependable.
Use the [eval design](../eval-design/README.md) for a proposed comparison.
The first survey and ranked hypotheses are in the
[roadmap](../../../../docs/pudge-improvement-roadmap.md).
