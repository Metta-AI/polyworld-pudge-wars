# Iteration 6 — complete the long-hook pull gate (stale blind poke included)

Campaign: `pudge-auto-optimizer` (records in [`../auto-optimizer/`](../auto-optimizer/)).
Iteration: 6   Base: `pudge-auto-optimizer:v4` (`774d5ee5-d4ad-49de-82cc-54457a53041e`,
behaviour base = champion v1 + edge-band clamp)   Candidate: `pudge-auto-optimizer:v7`
(filled in on upload)   Session: `devin-41e370ba6c204f26a8e9b95ff86cc7f5`
Status: **open** — hypothesis pre-registered 2026-09-17T15Z before the code change.

Relation to iteration 5: v6 (visible-target pull gate, `no_signal`) is not the
base; the candidate is v4 + the *complete* pull gate (visible target, fresh poke
**and** stale poke). The attributable change versus v4 is "long hooks are gated
on out-brawling the reeled enemy"; versus v6 the delta is only the stale-poke
path, which iteration 5 showed carries the bulk of the unfavourable pulls.

## Hypothesis record

**Observation.** Iteration 5's mechanism check
(`../auto-optimizer/evals/iter5-directional/pull_exchange.json`, 40 decoded
v6 replays vs 40 matched v4 replays) found 81 unfavourable long-hook landings
(`no_edge`: after the hook damage the reeled enemy still holds more than our
HP + 40) in v6 vs 72 in v4; the policy died within 6 s in 0.69 / 0.61 of them.
Tracing each landing back to its launch: the visible-target gate did its job
(unfavourable visible-target pulls 16 → 4) but **50 of 81** (v6) and 38 of 72
(v4) came from the *stale blind poke* — the throw at the far bank lip
(`east + 2` / `west − 2`) made when no enemy has been visible for more than
3 s. That hook flies its full 60+ tile range past the lip and reels in
whoever stands behind it, typically a full-HP pudge that just healed. The
iteration-5 code exempted that path from the gate ("no HP knowledge").

**Causal guess.** `last_enemy["hp"]` from a few seconds (even a minute) ago is
still a usable estimate: HP moves only by hook damage and slow regen, and the
error is biased toward *under*-estimating the enemy's HP (they heal while out
of sight), which makes the gate err on the side of throwing — the same
behaviour as today, never worse. Gating the stale poke on
`pull_wins(last_enemy.hp, span_to_aim)` removes most of the remaining
unfavourable pulls while leaving every short/rescue/threat/rune hook and every
pull we can win untouched. Because the stale poke is the majority path, this
is where the death reduction predicted in iteration 5 (−1/game) should
actually materialise.

**Evidence.** `evals/iter5-directional/pull_exchange.json` and the launch
reconstruction table in
[`2026-09-17-east-seat-hook-survival.md`](2026-09-17-east-seat-hook-survival.md)
(verdict section): stale-poke share of `no_edge` landings 38/72 (v4) and
50/81 (v6). `pull_skip` fired only 20.5 times/game in v6 (≈ 27 s of withheld
throws per game), i.e. the gate rarely engaged — consistent with the exempt
path taking over. Hosted log triage: 0 tracebacks in 40/40 v6 logs, so the
gate code path is sound. `closed_levers.md`: the visible-only gate is listed
as *no signal, lever open*; the complete gate is the recorded next step, not
a re-run of a refuted lever.

**Missing data.** Which blind-poke age produces the unfavourable landings
(the replay cannot tell a fresh from a stale poke). The `pull_skip` trace
event gains `poke_age` (ticks since the last sighting) on the blind-poke
paths so the readout can split withheld throws into visible / fresh-poke /
stale-poke buckets; joins to the replay clock via `tick`.

**Change (exactly one, `coworld/player/base.py`).** In the blind-poke branch
of `BasePolicy.choose_action`, the aim is clamped first and then the throw is
gated on `pull_wins(last_enemy.hp, max(|dx|, |dy|) to the clamped aim,
poke_age=age)` for *every* poke with a known last enemy (fresh ≤ 96 ticks and
stale > 96 ticks alike); with no enemy ever seen the opening poke is
unchanged. `pull_wins` itself is unchanged apart from forwarding extra trace
fields. Constants unchanged (`PULL_HP_MARGIN = 40`, span ≥ 30 regime). The
damage prediction uses the aim span (bank lip), which under-states the
longshot bonus for a hook that flies further — conservative, i.e. it withholds
slightly more than a perfect predictor would. Unit test
`test_stale_blind_poke_is_gated_on_the_last_seen_hp`; the iteration-5 test's
assertion that "a stale poke is not held back" is removed because it pinned
the behaviour this iteration deliberately changes.

**Expected metric movement.** Mechanism (`pull_exchange.py` on the v7
replays): `no_edge` landings **< 40 per 40 games** (v6 81, v4 72), stale-poke
share of them roughly halved; `pull_skip` events/game up from 20.5 (v6) to
≳ 60, most carrying `poke_age > 96`. Outcome: own deaths/game −1 vs the
matched v4 arm (v4 13.5 in the iteration-5 window), long hooks landed/game
down ≤ 15%, kills/game down ≤ 0.5. Clean aggregate win rate v7 > v4 in the
matched window; the east seat gains at least as much as the west.

**Eval plan.** Smoke n=3 (`iter6-smoke`, top-3 field, zero tracebacks,
`pull_skip` with `poke_age` present). Matched directional n=40 vs top-3 for
v7 (`iter6-directional`) and v4 (`iter6-directional-v4`) launched in the same
window; readout taint-filtered by seat and opponent; decision rule per
`STATE.eval_protocol` (directional is direction only; promotion needs the
gate protocol). Mechanism check with `tools/pull_exchange.py` on both arms'
decoded replays when a decoder is available on the harvesting box.

**Overfit risk.** Against a passive sniper that never punishes a pull the
withheld pokes are lost chip damage and lost denies; against a bot that
heals to full and returns, our stale HP estimate is too low and the gate lets
the pull through (today's behaviour, so no new downside). Tripwires: the
`pudge-wars-rusher:v16` slice must not fall more than 1 SE below v4's, long
hooks landed/game must not fall by more than 15%, kills/game by more than
0.5. No opponent identification is used.

**Rollback condition.** Candidate clean win rate ≤ v4 − 1 pooled SE in the
same window, or deaths/game ≥ v4's, or kills/game down > 1, or any traceback
or missing `pull_skip`/`poke_age` in the smoke logs. Rollback = drop the
`pull_wins` gate from the poke branch (v6 source) or the whole gate (v4
source). If the complete gate does not move `no_edge` below ~40/40 games,
**close the pull-gate lever** in `closed_levers.md` and return to the seat
question (team-keyed code asymmetry in the defensive Blink).

## Run log (iteration 6, 2026-09-17)

- 15:0xZ books closed for iteration 5 (ACU final 0.0 — the session API still
  reports 0.0 for automation sessions; no open evals to harvest).
- Iteration opened in the ledger; `spent_today_usd` before any hosted launch:
  17.542306.
- 15:08Z built `pudge-auto-optimizer:iter6` (offline base image, as v5/v6),
  uploaded as **`pudge-auto-optimizer:v7` = `bd16628b-b986-47f7-8e33-e87f74245468`**,
  source `b7653c1`, tags recorded.
- 15:10–15:31Z smoke `xreq_c0656607` (n=3, top-3): completed 3/3, taint 0,
  0 tracebacks, all 3 logs connected; 1 W / 2 L (runtime check only). Trace:
  `pull_skip` 132/game (v6: 20.5/game) with `poke_age` present — 396 skips =
  339 stale (age > 96) / 37 fresh / 20 visible. Example stale skip:
  tick 35680, span 41.5, hp 866 vs enemy_hp 1585, landed 610, poke_age 107.
  The exempt path was indeed the dominant one; the gate now engages ~6× more.
- 15:33Z launched matched directional in the same window:
  v7 `xreq_c505529a-0dca-49c7-81cb-d50b16f35097` (`iter6-directional`) and
  v4 `xreq_f6c102e7-8fad-41be-95b6-1585a34ec5d1` (`iter6-directional-v4`),
  n=40 each vs top-3.
