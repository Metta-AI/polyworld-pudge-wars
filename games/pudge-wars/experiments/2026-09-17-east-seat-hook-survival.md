# Iteration 5 — do not pull an enemy we cannot out-brawl (long-hook HP gate)

Campaign: `pudge-auto-optimizer` (records in [`../auto-optimizer/`](../auto-optimizer/)).
Base arm: `pudge-auto-optimizer:v4` (`774d5ee5-d4ad-49de-82cc-54457a53041e`,
latest accepted behaviour = champion v1 + edge-band clamp; v1 stays the
formal champion, see `STATE.pending_decisions`). Source at branch HEAD is
already v4 behaviour (`LEAD_DIVISOR = 30`, iteration 4 rolled back).
Candidate arm: `pudge-auto-optimizer:v6` (filled in on upload).
Status: **open** — hypothesis pre-registered 2026-09-17T12Z by
devin-c6eafeae (this file's first version was the east-seat survival
question; the seat diagnostic and the v4 replay decode below narrowed it
to the pull-exchange lever recorded here before the change was written).

## Hypothesis record

**Observation.** The east-seat gap (v4 directional east 0.550 vs west
0.750, n=20 each; pooled iterations 0–4 east ≈ 0.40 ± 0.04 vs west
≈ 0.62 ± 0.04) is a *survival* gap: east 14.75 deaths/game vs west 8.75.
Decoding the 40 v4 directional replays event-by-event shows where a large
slice of those deaths come from: **our own landed long hooks**. After we
land a hook from > 30 tiles the victim is reeled onto us; within the next
6 s the victim dies 63% of the time and *we* die 20% (648 pulls). Split by
the HP edge we hold once the hook damage is in (`me.hp + 40 >= victim.hp`,
the same test the policy's `brawl` flag uses): pulls where we still hold
the edge (n=576) — victim dies 0.66, we die 0.14; pulls where we do **not**
(n=72, 1.8/game, our mean HP 605 vs victim 910 after the hook) — victim
dies **0.08**, we die **0.61** (47% of those deaths are the reeled enemy's
own point-blank hook). East makes more of these bad pulls (2.05/game →
1.35 deaths/game) than west (1.55/game → 0.85), and east pulls a
still-healthy victim (> 800 HP after the hook) on 44% of landings vs 28%
west. The bad-pull bucket alone is ~1.1 deaths/game with almost no kills
attached.

**Causal guess.** A landed long hook is a *pull*, not just damage: it
delivers the enemy adjacent to us at our hold with our hook on a 2 s
cooldown and theirs usually ready. When we are the weaker pudge after the
hook lands (typically because we are walking home to recover, or the enemy
just healed), `brawl` is false, the policy walks home with a full-HP rusher
attached, and it dies to the close hook/melee/rot exchange. The throw itself
is the decision we control: the code throws every long hook it can
(`target` visible within `reach + radius`, or a blind poke at the enemy's
last seen position), without asking whether reeling this enemy in is
survivable. Skipping only those throws where the *post-hook* HP edge is
against us should remove most of the 0.61-death pulls while keeping the
0.66-kill ones.

**Evidence.** `../auto-optimizer/evals/iter4-directional-v4/replay_survey.json`
(40 decoder-verified replays) plus the pull-exchange tabulation of the same
replays (hook_landed dist > 30 by our seat → kill events within 192 ticks,
victim HP from `victimHpAfter`, our HP from the nearest state row):
brawl-edge pulls 576 / no-edge pulls 72; per-seat, per-bucket and
per-opponent counts in
`../auto-optimizer/evals/iter4-directional-v4/pull_exchange.json`
(`tools/pull_exchange.py`, reproducible from the decoded replay root). Hook damage
per landed long hook is symmetric (ours 525, theirs 535 mean) and never
lethal on its own, so the pull exchange, not chip damage, decides these
deaths. Native constants used for the prediction: `BaseHookDamage 200`,
`HookDamagePerLevel 15`, `ItemLongshotPercent 1`/tile/rank
(`examples/pudge_wars/content.nim`). `closed_levers.md`: collision-threat
filter (v3), longer lead (v5) closed; the pull gate is the "killability
gate" it lists as a distinct hypothesis. Seat diagnostic
`iter5-diag-mirror-v4` (`xreq_9033037e`, v4 vs v4, n=40 clean, taint 0):
identical code wins **23 west / 12 east / 5 draws** (west share 0.638 ± 0.076,
west kills 11.18 vs east 8.90/game, +2.28 ± 0.99). So ~0.1–0.14 of the
~0.2 east deficit is a native/host seat prior (a)/(b), the remainder (c);
the hosted `xp summarize` score is meaningless for a mirror (both slots
carry the same version id) — read `evals/iter5-diag-mirror-v4/results/`.
The pull gate has no seat term; it targets the (c) part, which the pull
tabulation shows is concentrated in the east seat.

**Missing data.** Whether the bad pulls are thrown at a *visible* target
or as blind pokes at the last seen position (replays do not carry our
vision); the gate covers both when the last sighting is ≤ 3 s old, so the
readout does not depend on it. New trace event `pull_skip`
(span, our hp, enemy hp, predicted landed damage; one per 32 ticks while a
throw is being withheld) joins to the replay clock via `tick`.

**Change (exactly one).** `coworld/player/base.py`: a long hook
(span ≥ 30 tiles, the `LEAD_TRACE_SPAN` regime) is thrown only if the
enemy, after the predicted hook damage
`(200 + 15·damage_level) · (1 + 0.01·longshot_rank·span)`, would be at or
below `our_hp + 40` — the exact edge the existing `brawl` flag demands
before fighting a reeled enemy — or is already ≤ 120 HP. Applies to the
visible-target throw and to the blind poke at a ≤ 3 s-old last sighting
(stale pokes at the far bank lip are unchanged: no HP knowledge). Short
hooks, rescue/heal hooks, threat/rune/swimmer hooks untouched. Constants:
`PULL_HP_MARGIN = 40`. Mirrored on `team` by construction (no seat term).
Unit test `test_long_hook_does_not_pull_an_enemy_it_cannot_out_brawl`.

**Expected metric movement.** Pulls with the HP edge against us: 1.8/game
→ ≲ 0.3/game (only via stale pokes); our deaths/game 10.7 → ≤ 9.7 (−1),
east more than west; long hooks landed/game down ≤ 10% (16.2 → ≥ 14.5) and
kills/game down ≤ 0.3 (16.0 → ≥ 15.7); `pull_skip` present in the smoke
artifacts. Clean aggregate win rate v6 > v4 in the matched window; east
seat improves more than west.

**Eval plan.** Smoke n=3 (`iter5-smoke`, zero tracebacks, new trace event
present if any). Matched directional n=40 vs top-3 for v6
(`iter5-directional`) and v4 (`iter5-directional-v4`) in the same window;
readout by seat and opponent, taint-filtered. Decision rule per
`STATE.eval_protocol`; directional is direction only.

**Overfit risk.** Against a passive sniper that never punishes a pull, the
withheld throws are lost chip damage / denies; the tripwire is the
per-opponent split (v16 row must not fall below v4's by > 1 SE) and total
long hooks landed. The gate uses our own HP prediction only — no opponent
identification.

**Rollback condition.** Candidate clean win rate ≤ v4 − 1 pooled SE in the
same window, or deaths/game not down (≥ v4's), or kills/game down > 1, or
any traceback / missing `pull_skip` in the smoke. Rollback = remove the
`pull_wins` gate (three call sites + constants) → v4 source.
## Run log (iteration 5, 2026-09-17)

- Smoke `iter5-smoke` (`xreq_68d87223`): clean n=3, taint 0, 0 tracebacks,
  `pull_skip` present in all three logs (63 / 8 / 4 events; e.g. hp=920 vs
  enemy 1200, landed=200 → skipped; hp=260 vs 1200 with longshot landed=318
  → skipped). Smoke score 1/3 is not evidence (n=3).
- Directional arms launched 13:36Z on the identical protocol
  (top_n=3, 40 episodes): candidate v6 `xreq_7c995925`, matched baseline v4
  `xreq_424b4fe0`. Verdict block to be written by the harvesting run:
  compare v6 vs v4 pooled and per seat, plus `pull_exchange.py` on the v6
  replays to confirm the unfavorable-pull bucket shrank (mechanism check).

## Verdict (iteration 5, written 2026-09-17 14:1xZ)

**Decision: no_signal → reject as new base; lever stays open (refine, not closed).**
Champion `pudge-auto-optimizer:v1` unchanged; behaviour base stays `v4`.

| arm | clean win rate | west | east | vs a-aron:v1 | vs richard:v7 | vs rusher:v16 | deaths/game |
| --- | --- | --- | --- | --- | --- | --- | --- |
| v6 `xreq_7c995925` | **0.575 ± 0.078** (n=40, taint 0) | 0.700 (20) | 0.450 (20) | 0.778 (9) | 0.643 (14) | 0.412 (17) | 12.7 |
| v4 `xreq_424b4fe0` (same window) | **0.487 ± 0.080** (n=39, 1 episode still running at write time) | 0.550 (20) | 0.421 (19) | 0.556 (9) | 0.500 (12) | 0.444 (18) | 13.3 |

Delta +0.088, pooled SE 0.112 → **+0.79 SE: no detectable change at n=40.**
No slice regresses beyond 1 SE (v16 0.412 vs 0.444, −0.3 SE); deaths did not
rise (tripwire passed); 0 tracebacks in 40/40 logs, `pull_skip` 20.5/game
(≈ 27 s of blocked long throws per 20-min game — the gate fires rarely).
History note: v4 scored 0.650 ± 0.076 in the iteration-4 window and 0.487 ±
0.080 here — a 0.16 swing for identical code, so cross-window comparisons
are worthless; only the matched arm counts.

**Mechanism check failed.** `pull_exchange.py` on the v6 replays
(`evals/iter5-directional/pull_exchange.json`): unfavourable long-hook
landings (`no_edge`) were **81** (policy died in 0.69 of them) vs **72** in
the v4 arm (0.61). Reconstructing each unfavourable landing back to its
`hook_launched`:

| launch path | v4 | v6 |
| --- | --- | --- |
| gate would have passed at launch, but we lost HP during the hook's flight (mutual exchange) | 16 | 26 |
| aimed at a visible target the gate should block | 16 | 4 |
| aim at the far bank lip (x≈50 / x≈78 = the **stale blind poke**, age > 3 s, exempt from the gate) | 38 | 50 |
| rune hook passing through the enemy | ~0 | 1 |

So the gate did remove the visible-target unfavourable pulls (16 → 4) but
they were the minority; the exempt stale poke — thrown at the bank lip, then
flying its full 60-tile range into whoever stands behind it — produces the
bulk, and with fewer visible throws the held hook is released as a stale
poke a moment later instead. The exemption ("no HP knowledge") was wrong:
`last_enemy["hp"]` from a few seconds ago is still a good estimate (HP only
moves by hook damage and slow regen).

**Rollback:** none needed — v4 remains the base; v6 is not built upon.

**Next (iteration 6, one change):** the complete pull gate on v4 — apply
`pull_wins(last_enemy.hp, span)` to the stale poke too (and consider
suppressing the bank-lip poke entirely while `low`/recovering), keep the
visible-target gate. Prediction: `no_edge` landings fall below ~40/40 games
(mechanism), own deaths −1/game; verdict by matched directional + the same
`pull_exchange.py` table. If the stale-poke gate also fails to move
`no_edge`, close the lever.
