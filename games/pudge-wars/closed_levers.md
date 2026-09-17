# Prior experiments and constraints

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

## pudge-auto-optimizer campaign (Python policy, hosted 1v1 XP protocol)

| Lever | Why it is closed |
|---|---|
| Collision-classified dodge trigger (Blink only for hooks whose tracked heading passes within 8 tiles; v2/v3, [experiment](experiments/2026-09-17-collision-threat.md)) | v3 vs v1, n=40 each, same window, 0 taint: 0.325±0.074 vs 0.425±0.078 (−10 pp, 0.93 SE) with a −38 pp (≈2.2 SE) regression vs `a-aron-pudge-rusher:v1`; low-HP recoveries rose 17.9→19.7/game although the filter skipped ~65% of in-range hooks. Do not retry with a guessed margin. Reopen only after measuring the true catch radius from replays (hooked events joined to `threat_class`) so "wide" is defined by data, and only with hooked/death counts instrumented in both arms. Code stays available as `PUDGE_THREAT_FILTER=collision`. |
