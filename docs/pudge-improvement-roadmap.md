# Pudge Wars: where to improve next

Follow-up: [healing and fishing-spacing experiment](../games/pudge-wars/experiments/2026-09-09-support-spacing.md)
implements the first two hypotheses and records the new hosted screens,
fresh confirmation design, exact-healing observer, and reusable XP/comparison
tools. The investigation below describes the evidence available before that
campaign; consult the experiment record for its current results.

Investigation: 2026-09-09. The next useful policy experiments are **selective
ally healing, coordinated rune collection, and preventing enemy-bank
captures**. Base already has competitive aim and finishing ability. Improve
those other skills through separate experiments rather than bundle more
aim, economy and movement changes into another unexplainable port.

These are ranked hypotheses, not demonstrated fixes. This investigation
reused completed games, downloaded their replays, and added analysis tools
and local skill bindings. It did not launch new XP requests or replace v10.

## What the existing games establish

All 20 hosted v10-versus-Myasnik replays reproduced every state hash and all
**4,996,154 recorded actions** using the matching v0.3.13 engine. That covers
205.93 simulated minutes, 20 unique seeds, and ten games on each starting
bank. Terminal scores, ticks, seeds and per-seat kill/death/hook counters
matched the hosted results. Base won 11–9, with total kills tied 521–521.
This remains a close matchup, not a reliable advantage.

| Metric across the same 20 games | Base v10 | Myasnik v5 | Interpretation |
| --- | ---: | ---: | --- |
| Hooks thrown per team-minute | 50.80 | 62.64 | Base applies 18.9% less hook pressure |
| Recorded enemy catches / throws | 12.13% | 11.58% | Aggregate enemy contact efficiency is comparable; this is an incomplete logger measure |
| Recorded friendly catches | 1,624 | 3,363 | Potential sustain/positioning difference; friendly hooks heal |
| Runes taken | 493 | 432 | Base has a resource-control strength to preserve |
| Headshots | 156 | 136 | Follow-up finishing is already competitive |
| All-three clustering, pair distances ≤12 tiles | 17.51% | 5.19% | Base groups much more often; denominator is samples with all three alive |
| Sampled unhooked hook readiness | 39.77% | 25.47% | Supports investigating unused pressure; does not prove a safe shot existed |
| Enemy-bank position before death | 335 / 522 | 249 / 522 | Base more often finishes a life after being transported across |

The hook-record coverage is 96.0% of throws for Base and 96.9% for Myasnik;
some hooks begin and disappear inside a tick. Friendly catches can heal,
rescue, or disrupt an ally. Neither the headline `hooks_landed` counter nor
the logger's nearest-enemy `target` is a clean measure of aimed enemy hits.
Death locations use the last 4 Hz state sample, at most eight ticks earlier.
Damage and kill-cause categories are heuristic; they are not precise causal
attribution. The instrument documents these limitations explicitly.

Clustering alone does not explain the losses: Base clusters 17.60% in wins
and 17.41% in losses. Its hook volume is also slightly higher in losses.
Myasnik's recorded enemy catches per throw rise from 10.88% in Base wins to
12.42% in Base losses. These associations guide interventions; they do not
establish which behavior causes the result.

## Three policy experiments, in order

### 1. Enable deliberate ally healing

The live engine's `latchHook` restores up to **120 HP** on friendly contact
(`AllyHookHeal` in the released `content.nim`). Myasnik has more than twice
as many recorded friendly catches. Base's `throw` guard rejects ally paths,
except for a specific rescue target; the rescue branch mainly handles enemy
chains or allies stranded in the river. It has no deliberate ordinary
same-bank healing behavior.

**Hypothesis:** a healthy support player can turn some otherwise low-value
shots into effective healing, keeping damaged teammates fighting without
unnecessary shop retreats. This could explain part of Myasnik's ability to
sustain pressure. Effective healing and rival intent are currently unknown,
so raw friendly-contact counts cannot confirm it.

Change location: [`BasePolicy.throw` and rescue selection](../coworld/player/base.py).
Prototype one claimed healer, a damaged unshielded ally on the same bank,
a safe destination, no existing friendly rescue chain, and no urgent enemy
finish or incoming threat. Keep normal ally avoidance elsewhere.

Measure actual HP restored, displacement, duplicate heal attempts, enemy
shot volume, ally survival and final win/kill margin. First use controlled
scenarios to prove healing fires and does not yank a teammate into danger.
If healing increases but lost offense outweighs it, reject the policy change.
There is no direct teammate-healing benefit in 1v1.

### 2. Coordinate rune collection while preserving firing lanes

The lane branch assigns different lanes, then `rune_next` overrides every
available teammate's destination with the same rune Y for the final 256
ticks before a drop. Rank also depends on which lower-ID allies are alive,
so deaths can shift assignments. The viewed 16–30 loss has all three Base
players together near the northern wall at 1:00. The 20-game survey confirms
much more clustering than Myasnik, including on Base's own bank.

**Hypothesis:** one collector with stable covering lanes can preserve most
of Base's rune advantage while reducing shot suppression and idle travel.
This amplifies a working skill rather than simply abandoning rune control.

Change location: [`rank`, `throw`, and the `rune_next` movement override](../coworld/player/base.py).
Compare one nearest eligible collector plus two separated teammates against
the unchanged policy. Keep aim and healing unchanged in this experiment.

Measure rune share, useful throws/minute, time blocked by an ally, readiness
without an action, clustering, and win/kill margin. Logs must establish that
the collector branch and shot-suppression branch actually fired. Lower
clustering without better pressure or outcomes is not a successful fix.
No formation change should activate in 1v1.

### 3. Prevent captures with better threat selection

The loss replay's 6:49–7:31 stretch contains five Base deaths on the west
bank, including repeated captures of P6. Across all games, Base's final
sample before death is on the enemy bank in 64.2% of deaths, versus 47.7%
for Myasnik. This is stronger evidence for investigating the capture chain
than for simply raising a generic retreat threshold.

Base selects the nearest flying enemy hook within 22 tiles using distance
alone and may spend Blink immediately. It does not estimate whether that
hook is approaching, its projected collision, or a safe escape trajectory.
**Hypothesis:** spending defense on actual collision threats can prevent
some captures and preserve Blink for escapes. This is distinct from the
previous inconsistent experiment that merely rotated the Blink direction.

Change location: [`threat`, `dodge_side`, Blink and river branches](../coworld/player/base.py).
First trace approaching versus receding hooks, readiness at first catch,
Blink use/rejection, and the post-catch sequence. Existing replay states
show outcomes but do not establish whether Base saw or misread each threat.

Measure first enemy catches per alive minute, enemy-bank deaths, successful
escapes and final outcomes. A lower Blink-use count alone proves nothing.
Validate this separately in 1v1, where defense has no teammate rescue fallback.

## Game and evaluation improvements

| Priority | Work | Why it helps continuing improvement |
| --- | --- | --- |
| First | Add bounded private decision traces: observation tick, branch, target, suppressed-shot reason, chosen support owner, threat estimate, and sent/accepted action ticks | v10 currently logs connection/final status, so we cannot join world truth to its decisions. Current host action echoes already provide a starting point. |
| First | Record explicit hook-contact/healing/damage events at the simulation operation, including actual HP restored and chain ownership | Existing end-of-tick inference misses short-lived hooks and can misattribute simultaneous damage. This is needed to test the healing mechanism. |
| Next | Make the hosted batch runner reusable, with immutable roster IDs, source/image identities, completion harvesting and seed readback | The current XP helpers live in an ignored study directory. Prevent version drift, partial-batch conclusions and mislabelled paired tests. |
| Next | Attach policy labels, slot mapping and build identity to a replay sidecar; generate the named-player launcher automatically | Replays currently require external `--label` arguments. Preserve who-is-who with the recording. |
| Next | Replace millisecond default map seeds with independent randomness or a per-episode seed schedule | The follow-up's combined screen had two simultaneous episodes with seed 170244075. Keep the existing canonical game fixed for comparisons; in a future game release, prevent same-millisecond map collisions. The comparison instrument now detects them and supports a pre-recorded unique-seed analysis. |
| Separate project | Build a sibling BASIC game-hosted Coworld using Metta's file-policy runtime | This could remove Python/BASIC policy drift and per-seat Docker overhead. Measure actual speed and certify VM isolation, budgets and artifacts before migration. |
| Separate validation | Extend coaching tests from branch changes to exposed gameplay interventions and fresh competitive outcomes | Existing controlled coaching tests show intended movement changes, while natural matches often mask those branches. Competitive improvement is not established. |

The [runtime assessment](../coworld/GAME_HOSTED_MIGRATION.md) still applies:
keep the current Docker competition available while developing the BASIC
competition. The newer working-tree ward rules are a separate game release.
Neither a runtime switch nor a graphics update by itself improves policy skill.

## Which agent skills are useful here

| Skill | Fit and remaining adaptation |
| --- | --- |
| `replay-inspection` | Used for this investigation. Added a Pudge binding and durable survey instead of another disposable parser. |
| `diagnose` | Good next-step structure: a few independent mechanisms, evidence and code locations. Added a Pudge failure vocabulary and prior-experiment record. |
| `experiment` | Best for testing one of the three hypotheses. Its generic record command expects a different lab layout; use a local experiment record and the documented Pudge evaluation contract. |
| `run-eval` | Appropriate for hosted measurement. Added the Pudge batch, roster, timing and scoring binding; a durable authenticated XP runner remains to be built. |
| `cg.game.map-mechanics`, `cg.game.leaderboard-gap`, `cg.game.scrimmage-gauntlet` | Useful methods, but supplied commands and metrics target CoGames/CogsGuard. Use this repository's Nim runner and Coworld IDs rather than those commands directly. |
| `cg.game.upgrade-game`, `cg.game.upgrade-player` | Relevant to the separate runtime/protocol migration; own the game here and audit downstream hosts. They are not substitutes for competitive evaluation. |
| `cg.game.skill-improvement` | Use after repeated real failures to improve the shared skill suite. First keep Pudge-specific fixes in this repo; do not generalize a one-game workaround into every game skill. |

The new entry point is [games/pudge-wars/MIXIN.md](../games/pudge-wars/MIXIN.md).
It links replay inspection, evaluation design, diagnosis, opponent versions,
and prior successful/inconsistent experiments. The global installed skills
were not edited.

## Next campaign and reproduction

Start with selective healing and its effective-healing trace. After local
branch-exposure scenarios pass, a directional hosted comparison is four
requests of **10 episodes each**: candidate and v10, each on both banks,
against the same pinned Myasnik v5. These are independent generated-seed
batches unless the API provides and verifies an explicit per-episode paired
schedule. Pre-record mechanism and outcome decision rules before launching.
Finish every request before deciding, then use fresh validation and other
leader/1v1 guardrails before promotion. Twenty games per arm is a screen,
not evidence of a small reliable win-rate gain.

The completed survey is
`duels/coworld-base-l4r3452l/myasnik-survey-v2/survey.json`; all decoded
events, manifests, hashes and source replays are retained beside it.
[CLI and metric definitions](../games/pudge-wars/skills/replay-inspection/README.md)
explain how to reproduce it. The instrument was run on all 20 matches and
cross-checked against their official hosted counters. No new competitive
result is claimed by this investigation.
