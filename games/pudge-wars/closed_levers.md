# Prior experiments and constraints

The [2026-10-14 BASIC transfer](../../coaching/policies/basic-rusher/README.md)
ported retained Python v16/E06b as a complete package. The corrected candidate
won 24/24 full-cadence screen games and 96/96 fresh confirmation games against
the previous BASIC Base, with +23.896 mean paired-bank margin. It also won
48/48 stock-opponent checks; duels had 22 kill-goal wins and two time limits.
All 192 corrected-policy matches replay-verified. The package is now the local
default Base; deployed on 2026-10-14 as `pudge-basic-base:v2`, with an independently
verified active champion membership and a passing hosted runtime/replay smoke.
These comparisons
do not isolate any individual ingredient or establish hosted/mixed-team strength.
Used seeds: initial superseded fair screen 1014101–1014124; corrected screen
1014201–1014212; confirmation 1014301–1014348; stock opponents 1014401–1014404;
duels 1014501–1014512; game-hosted integration 1014601–1014602.

The [2026-10-13 skill-gradient investigation](experiments/2026-10-13-skill-gradient.md)
used seeds 101401–101424 for two isolated candidates in 1v1/3v3, both banks.
These are no longer fresh holdouts. Shorter lead passed its local self-play
rule but remains unpromoted pending combined-policy and broader validation.
Nearest-threat coordinates passed a correctness fixture without demonstrating
competitive benefit (3v3 margin -0.500, 95% seed-block interval [-1.688, 0.500]).
Instrument-control seeds 101501–101502 were also used.

Read the [native Base study](../../examples/pudge_wars/BASE_POLICY_AUTORESEARCH.md)
before tuning. These entries preserve negative or limited results; they do not
claim a lever can never work in another engine or matchup.

| Lever | Evidence and current status |
| --- | --- |
| Shorter lead, divisor 9 → 30 | Promoted after native selection and fresh paired-seed evaluation. This empirical lead is not an exact flight solver. Do not retune using its old holdout seeds. |
| Fighter-only scans | Inconsistent native selection results; not promoted. Needs new evidence to reopen. |
| Headshots aimed toward actual reeler | Inconsistent native selection results; not independently established. The Python port includes its own version, so do not attribute hosted gains to this alone. |
| More perpendicular defensive Blink | Inconsistent native selection results. A future trajectory-aware threat detector is a different hypothesis; do not repeat the old directional tweak as a new finding. |
| Free long-range wards on live v0.3.13 | Wrong mechanics: live wards cost 8 gold, persist, and place within 3 tiles. New free consumable wards require the newer protocol. |
| Raising the coaching retreat threshold | Controlled scenario changed movement; natural competitive benefit remains unproven. Existing coaching verification describes behavior masked by higher-priority branches. |
| Deliberate short same-bank healing alone | Verified effective healing rose 77% in a 20-game screen, but 11–9 vs baseline 6–14 is only directional. Healing's incremental win benefit over spacing remains unconfirmed. |
| Stable fishing lanes plus one rune collector | Spacing-only screened 19–1 vs 6–14. Combined with healing, frozen v13 independently confirmed 35–5 vs 19–21, then went 20–0 against each of relh/sniper; promoted for 3v3. Preserve the component distinction. |
| Rune control under v13's formation | Fresh rune collection fell 10.13%, narrowly outside the original 10% mechanism target despite a large win-rate gain. Collector availability is a new hypothesis to diagnose, not an already demonstrated fix. |

Previous native holdouts 2001–2024 and hosted episodes already inspected are
diagnostic data now, not fresh validation for another candidate.

The [1,200-HP study](experiments/2026-09-10-hp1200-blink.md) used native
6101–6106 development and 6201–6212 confirmation seeds, plus 6301–6312 for
duel follow-up. Early damage ranks and routine center camping/raids did not
improve the native win rate. Stable native team lanes, continued recovery and
safe Blink escapes were retained together; recovery alone remains uncertain.
Native duel changes were rejected and the previous duel decisions preserved.
These seeds are now used evidence. Python results remain directional.

The [support/spacing campaign](experiments/2026-09-09-support-spacing.md)
and its 240 hosted episodes are likewise used evidence after v13's promotion.

The [session melee/fountain loop](../../coaching/policies/session-20260915-scrum/README.md)
retained frozen v14 after two separate 24-game native screens. E04's wounded
ally/enemy midpoint hooks had mean margin 0.0 (95% seed-block interval
[-4.625, 4.958]); E05's non-support fountain guard had -1.542
([-6.333, 3.708]). Both passed scoped behavioral reconciliation but failed their
preregistered improvement gates. Neither establishes a hosted effect or rules
out small benefits. Seeds 917501–917512 and 917301–917312 are now used evidence;
the superseded center64 attempt used 917101–917112 and is also not a holdout.
Revisit only with a new targeting/measurement hypothesis, not the same filter
and a relabeled seed extension. The engine fountain disk is centered at
(64.5,64.5), radius 3.5 in policy coordinates; knowing the correct geometry alone
did not improve shot selection in this screen.

The user then requested [all three coaching suggestions together](../../coaching/policies/session-20260915-bundle/README.md).
The complete E06b package (earlier/broader melee-centroid priority, continuous
CurveHook with native windup handling, and an all-throw fountain guard) passed
its 48-game screen and a fresh 96-game native confirmation: **67–29**, mean
paired-bank margin **+7.146**, 95% seed-block interval **[4.948, 9.198]** versus
frozen v14. Retain its research IR/policy pair. This does not reverse the
individual E04/E05 findings or isolate which part helped, and hosted transfer
remains untested. E06a's favorable 38–10 screen had no flight/return movement
exposure because its pending state expired before the nine-tick cast windup;
that incomplete implementation remains archived. Seeds 918101–918124,
918301–918324, and 918401–918448 are now used evidence; 918001 was a native
lifecycle smoke. Ground persistent skills in actual engine timing and reconcile
floating-point boundary conventions in the IR before claiming full fidelity.
