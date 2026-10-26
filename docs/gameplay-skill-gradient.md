# Gameplay and skill-gradient investigation — 2026-10-13

Here, skill gradient means that better decisions lead to reliably better game
outcomes. It does not mean gradient-based neural training. The current BASIC
league runtime and working-tree policy are the subject of this investigation.

Across 192 complete matches, shortening aim prediction from divisor 9 to 30
passed the registered local score-margin rule in both formats. Its 3v3 record
was **27 wins, 20 losses, one draw**, with mean margin **+3.27 kills** and a
95% seed-block interval **[+0.96, +5.73]**. It remains a research candidate;
the default receives only the independently verified threat-selection fix.
All 192 replays reproduced their recorded state hashes after correcting the
replay checker's duel map reconstruction.

## Concrete improvements

- Base's nearest-hook scan mixed one hook's distance with another hook's
  coordinates. Keep all three values in the same minimum-distance update.
  A two-hook scenario demonstrates the wrong dodge direction before the fix
  and correct, order-independent selection afterward.
- The coaching replay checker inferred map geometry from roster size. Hosted
  duels instead use the three-lane map with two seats. Reconstruct from the
  recorded map hash, as the game viewer already does, and reject unknown maps.
- `scripts/evaluate_skill_gradient.py` now freezes the candidate, baseline and
  host executable; plays each seed from both banks; retains results, seat logs
  and replays; and reports uncertainty over seed blocks. Failed policies abort
  the evaluation. An identical-policy control checks that bank effects cancel.

The threat fix is a correctness improvement. A stronger bot is a separate
claim, evaluated in the linked experiment. The replay fix improves the ability
to verify gameplay; it does not itself change gameplay.

## Next gameplay experiments, in priority order

| Change to investigate | Concrete evidence | Test that could justify keeping it |
| --- | --- | --- |
| Restore chain-cut rescue opportunities | In `base.bas`, `hookVictim(h) <> 0` is checked only inside `hookFlying(h) = 1`. `bots.nim` returns 1 only for `HookFlying`; `sim.nim:latchHook` switches to `HookReeling` when it attaches a victim. Thus an ordinary captured teammate cannot trigger this cut branch. | Place an ally on a returning enemy chain. Separate outbound threat detection from victim-chain detection; show an accepted intercept, actual chain release and safer ally survival. Then measure rescue exposure, deaths and match outcomes against multiple opponents. Keep empty returning hooks out of the victim-chain branch. |
| Spend Blink on collision threats | The current bot reacts to distance alone within 22 tiles. The nearest-hook fix still cannot distinguish a near miss or receding hook from an approaching hit. | Matched fixtures for approaching, receding, parallel and crossing trajectories, on both banks. Require avoided catches without unnecessary Blink expenditure, then fresh bank-balanced matches. Track the full hook lifecycle and fog-visible observations; do not substitute a direction tweak for trajectory detection. |
| Improve duel pacing without erasing defensive skill | Both completed 48-game duel comparisons reached the eight-minute time limit in every match; average total kills were approximately five against a goal of ten per side. | First measure contact-to-kill conversion, time spent recovering, sight/contact uptime and idle time. Compare one lever at a time: duel kill goal, combat-interrupted recovery, or a contestable objective. Require shorter inactive periods while a stronger policy still beats its ablations. A shorter clock alone is not better gameplay. |
| Make progression of skill measurable | Historical promotions and the current default differ, and short prediction may help one format but hurt another. A single self-play win rate can hide those interactions. | Maintain frozen opponents and separate 1v1/3v3 panels. Test aim, defense, support and resource-control ablations independently. Reserve fresh seeds after selection. For a human-facing difficulty ladder, verify ordered outcomes and playtest telegraph readability, successful escapes and recovery opportunities. |

The rescue finding is source-level evidence, not a demonstrated competitive
benefit. Likewise, the duel result identifies a symptom, not proof that healing
causes it. Neutral healing currently reaches 16 tiles and restores 1.5% max HP
per second, including hooked players; own-pad recovery restores 2% every half
second to unhooked players. These are candidate mechanisms to instrument, not
reasons to change balance blindly.

## Reproduce

The exact experiment protocol and completed results are recorded in
[the experiment](../games/pudge-wars/experiments/2026-10-13-skill-gradient.md).
Use a new output directory and new seeds for a new hypothesis:

```sh
python3 scripts/evaluate_skill_gradient.py candidate.bas baseline.bas \
  --binary tmp/skill-gradient-build/pwleague --output tmp/new-comparison \
  --first-seed 102001 --seeds 24 --team-size 3
nim c --hints:off -d:release -o:tmp/test-threat -r tests/test_pw_threat_selection.nim
python3 -m unittest discover -s tests -p test_skill_gradient.py
```

The interval describes local score margin against one frozen opponent. It is
not a hosted leaderboard confidence interval or evidence of human enjoyment.
