# Iteration 7 — post-pull bank escape (Blink home when outgunned on the enemy bank)

Campaign: `pudge-auto-optimizer` (records in [`../auto-optimizer/`](../auto-optimizer/)).
Iteration: 7   Base: `pudge-auto-optimizer:v4` (`774d5ee5-d4ad-49de-82cc-54457a53041e`,
behaviour base = champion v1 + edge-band clamp)   Candidate: `pudge-auto-optimizer:v8`
(filled in on upload)   Session: `devin-0106ba60e0e848a58326fd7c0aa63e7d`
Status: **open** — hypothesis pre-registered 2026-09-17T18Z before the code change.

Relation to iterations 5–6: the pull-gate lever (throw fewer long hooks) is
closed. This iteration leaves every throw untouched and changes what the
policy does *after it has been pulled*: the same HP criterion that already
decides `brawl` on our own bank is applied on the enemy bank, and an
unfavourable brawl there is replaced by a Blink toward home.

## Hypothesis record

**Observation.** `../auto-optimizer/evals/iter4-directional-v4/replay_survey.json`
(40 decoded v4 replays, iteration-4 window, 470 own deaths): 372 deaths have an
enemy hook landing on us within the preceding 10 s, and **270 of those chains
start with a long (>30-tile) hook that lands on us on our own bank**, at a
median HP of 1281 before the hit (q25 987) — i.e. we are pulled at (near) full
health, and die a median 140 ticks (4.4 s, q75 6 s) later after 2–3 hits.
61 % of all long hooks that land on us on our own bank (280 / 460) are
followed by our death within 10 s. Hits on us split by bank: on our own bank
the hit distance is bimodal (q25 4.6, q50 5.4, q75 60); on the enemy bank 90 %
of hits are point-blank (q25/50/75 = 4.57/4.57/4.59) — the follow-up hooks
after a pull, where opponents are 96 % accurate. Per game on the enemy bank we
die 7.55 times and kill 5.53; when we do kill there we hold a median 1163 HP,
when we die there the killer holds a median 817 HP (q75 1232; 51 % of those
deaths with the enemy at ≥ 800 HP). East seat: 8.75 enemy-bank deaths/game
vs 6.35 west — the seat gap lives in this exchange.

**Causal guess.** Today `brawl` is forced `True` whenever we stand on the
enemy bank (`not own_land and not river`), regardless of HP, so a pulled
pudge stands and trades (`attack_target`, Rot) against an enemy who has the
first hit (200+), Rot, melee and a 96 %-accurate point-blank re-hook every
2 s. The only dodge on the enemy bank is the reactive Blink, which fires only
when a hook is already flying (≤ 22 tiles) and at point-blank range the
flight is ~5–7 ticks — too short for observe → act on the hosted bridge.
Blinking pre-emptively the tick we are released from the reel, *toward home*
(onto our bank in the mid strip where the river is narrow; into the river on
the side lanes), breaks the chain before the first follow-up hook: the
enemy's hook is on cooldown (2 s) for the pull it just landed, and at 20
tiles a swimmer moving straight away is a ≪ 96 % target. When the exchange is
favourable (our HP + 40 ≥ theirs, or they are ≤ 120 HP) the brawl is kept —
that is where our 5.5 enemy-bank kills/game come from.

**Evidence.** Numbers above from `replay_survey.json` (per-episode
`opp_hits_on_me`, `deaths`, `kills`, joined on tick; chain = hits within 320
ticks before a death). Engine facts (`examples/pudge_wars/content.nim`):
Blink range 20 tiles, side-lane lip-to-lip 24, river landing legal
(`blinkLanding`: "including river water"), drown 30 HP / 16 ticks,
hook cooldown 2 s, Blink cooldown 8 s. Iteration-5 v5 finding ("pulling a
full-HP rusher in without killing it hands it the close-range exchange") is
the same exchange seen from the puller's side. `closed_levers.md`: "More
perpendicular defensive Blink" (a direction tweak of the *reactive* dodge) is
closed; a pre-emptive escape gated on HP is a different behaviour and is not
listed.

**Missing data.** Whether Blink is actually available when we are released
from a pull (if the reactive dodge burned it on the incoming long hook, the
escape can never fire and the result is a true null). New trace event
`pull_landed` (tick, layer, own_land, blink_ready, hp, nearest enemy hp and
distance) on the hooked → not-hooked transition, and `bank_escape` (tick,
hp, enemy hp, dist, destination, `via` = fountain|river) when the escape
fires. Both carry `tick` for the replay join; trace is on for the candidate
arm only (v4 was measured with trace on as well in iteration 6, so the
arms match on trace level).

**Change (exactly one, `coworld/player/base.py`).** In
`BasePolicy.choose_action`, before the reactive-threat Blink branch and after
`fountain_escape`/river: if `me.blink_ready`, `game_version ≥ 35`, we stand on
the enemy bank (`not own_land and not river`), we are not hooked, we are not
reeling a caught enemy, the nearest visible enemy is within 12 tiles, and
`me.hp + 40 < enemy.hp and enemy.hp > 120` (the negation of the existing
`brawl` HP clause), then `blink_to` = `fountain_escape(obs, enemies,
retreat=True)` if that returns a landing (mid strip, own bank), else the
point 20 tiles toward our bank at our current `y` (river water). `brawl` and
`rot` are recomputed with the escape, so no `attack_target`/Rot is issued on
the escape tick. All throws remain untouched. **Engine constraint (added in
v9 after the v8 smoke, see run log):** `applyBlinkFine` refuses the hop while
`rotAffected` — standing inside any live Rot disk (`RotRadius` = 8 tiles),
the enemy's or our own. The gate therefore also requires no enemy Rot within 8
tiles (`foreign_rot`; otherwise the v4 brawl is kept unchanged), and when our
own Rot is on the escape tick only switches it off (no attack, no Blink) and
the hop is issued the next tick. `pull_landed` gains `rot_locked`. Unit
tests: `test_outgunned_on_the_enemy_bank_blinks_toward_home` (both seats,
fountain and river destinations), `test_bank_escape_respects_the_rot_blink_lock`
and `test_favourable_enemy_bank_brawl_is_kept`
(HP edge or finishing a ≤ 120 HP enemy still brawls; no escape without Blink).
The existing `test_hook_before_melee_and_fight_when_cornered` (no Blink)
and `test_dodge_on_foreign_bank_heads_inland` (no visible enemy) are
unchanged and must stay green.

**Expected metric movement.** Mechanism: `bank_escape` fires ≳ 3 times/game
(v4 is pulled onto the enemy bank ≈ 7–8 times/game; some pulls have Blink on
cooldown, some are favourable); `pull_landed` with `blink_ready=true` share
reported. Outcome vs the matched v4 arm: own deaths/game −1.5 (11.9 → ≤
10.4), deaths on the enemy bank −20 % when replays can be decoded, time in
river up (3.5 s → ≤ 12 s/game), kills/game down ≤ 1 (some enemy-bank brawls we
would have won at low HP are abandoned). Clean aggregate win rate v8 > v4 in
the matched window; the east seat gains at least as much as the west.

**Eval plan.** Smoke n=3 (`iter7-smoke`, top-3 field, zero tracebacks,
`pull_landed` and `bank_escape` present in the policy_trace lines). Matched
directional n=40 vs top-3 for the candidate (v8 → v9 after the smoke fix; `iter7-directional`) and v4
(`iter7-directional-v4`) launched in the same window; readout taint-filtered,
split by seat and opponent; decision rule per `STATE.eval_protocol`
(directional is direction only; promotion needs the gate protocol at n=100
against champion v1).

**Overfit risk.** Against an opponent that pulls and then walks away (no
follow-up) the escape spends Blink and ~120 HP of drowning for nothing;
against a bot that hooks swimmers accurately the river hop trades a 96 %
point-blank hook for a long hook on a straight-line swimmer. The escape is
gated on HP, so a favourable pull (enemy already chipped) still gets brawled.
Tripwires: kills/game must not fall by more than 1.0; the
`pudge-wars-rusher:v16` and `a-aron-pudge-rusher:v1` slices must not fall
more than 1 SE below v4's in the same window; river time must not exceed
20 s/game. No opponent identification is used.

**Rollback condition.** Candidate clean win rate ≤ v4 − 1 pooled SE in the
same window, or deaths/game not below v4's, or kills/game down > 1, or any
traceback / missing `pull_landed`/`bank_escape` in the smoke logs, or
`bank_escape` < 1/game (mechanism absent: Blink is never ready at release —
then the next hypothesis is to *reserve* Blink for the release instead of
the reactive long-hook dodge). Rollback = remove the escape branch (v4
source). Constants introduced: none new (`40` and `120` reuse the `brawl`
clause; `12` reuses `fountain_escape`'s proximity radius; `20` is Blink
range).

## Run log (iteration 7, 2026-09-17)

- 18:0xZ books closed for iteration 6 (ACU final 0.0 — the session API
  reports 0.0 for this automation's sessions; no open evals to harvest).
- Iteration opened in the ledger; `spent_today_usd` before any hosted launch:
  24.53842.
- 18:13:46Z v8 uploaded (`24128d4e-0b67-4ac3-bd37-b8117cdb0b61`, source
  `32eb7e6`, image `sha256:13a3a868…`). Smoke `iter7-smoke`
  `xreq_700c9ae9-41e9-4b21-9992-70b841795a57`: clean n=3, 0 tracebacks, 3/3
  connected, 1/3 wins (smoke only); `pull_landed` 47.3/game, `bank_escape`
  22.7/game (68 events), all `via=river` (no mid-strip case in 3 games).
- **v8 smoke finding — the mechanism is half-broken.** 62 of 67 inter-event
  gaps between `bank_escape` events are < 256 ticks (Blink cooldown): the
  event fires on consecutive ticks from the same spot with `blink_ready`
  staying true, i.e. the engine refused the hop (e.g. ticks 27716–27753 in
  `ereq_163e6b69`, 38 ticks pinned at the same destination; 37120–37142 in
  `ereq_4eec4cd4`). Cause in `examples/pudge_wars/sim.nim`: `applyBlinkFine`
  returns false while `rotAffected(pudge)` — inside any live Rot disk
  (8 tiles), including our own — and Rot is exactly what a puller runs at
  point blank. During those pinned ticks v8 neither attacked nor rotted
  (`brawl` off), which is strictly worse than v4. Only ~4 of ~7 escape
  attempts actually hopped. Of 65 enemy-bank `pull_landed` events only 3
  had `blink_ready=true` (the reactive dodge on the incoming hook usually
  spends Blink), so the escape mostly fires later in the brawl, not at
  release; 56/65 landings were outgunned by the HP criterion.
- Decision: v8 is **superseded before directional** (same hypothesis, same
  single change, fixed to respect the engine's Rot lock — precedent v2 → v3).
  No win-rate claim from the smoke. v9 = v8 + `not foreign_rot` gate + own
  Rot switched off before the hop; `pull_landed.rot_locked` added.
- 18:42:50Z v9 uploaded (`5acc2a73-0077-4e5d-a82a-e30241e76676`, source
  `6841ee4`). Smoke `iter7-smoke-v9`
  `xreq_fb4870cb-6c9e-489d-aa58-272dc24029a5`: clean n=3, 0 tracebacks, 2/3
  wins (smoke only); `pull_landed` 58.3/game, `bank_escape` 13.7/game.
  Two games clean (3 + 3 well-spaced hops); the east game vs
  `pudge-wars-rusher:v16` still had two pinned runs (ticks 19763–19775 and
  19783–19798, HP and distance frozen, `blink_ready=true` throughout) — so
  the Rot lock was *not* the (only) refusal cause. Host facts found
  afterwards (`coworld_host.nim`): `blink_ready` already folds
  `rotAffected`, windup and hooked into the flag, so a refusal with
  `blink_ready=true` is a landing failure (`blinkLanding` found no legal
  point on the ray — a palisade/body on the first quarter-tile, or off-map);
  and every reply is echoed back next tick in `obs.accepted` with the
  engine's rejection reason (`rot`/`casting`/`hooked`/`cooldown`/`rejected`).
  Also: because the host's `blink_ready` is false inside our *own* Rot, the
  v9 "switch Rot off first" path could never fire on the host (the gate
  required `blink_ready`) — an outgunned brawl with Rot on never escaped.
- Decision: v9 superseded by v10 (same single change): (1) log the echo
  reason and, after a refused hop, hold the escape 32 ticks and brawl as v4
  (`bank_escape_refused{reason}`); (2) track Blink's cooldown from accepted
  hops (`accepted.blink_to == true`, 256 ticks) so the own-Rot switch-off
  fires when Blink is actually off cooldown; if Blink is still not ready the
  tick after the switch-off, the same 32-tick hold applies
  (`reason=rot_off_no_blink`). Unit test
  `test_refused_bank_escape_falls_back_to_the_brawl`.
- 19:15:11Z v10 uploaded (`6cc36a18-5a4e-499d-8aca-75e21ca9bf07`, source
  `92433f5`, image `sha256:33ecb0e7…`). Smoke `iter7-smoke-v10`
  `xreq_e844ef81-349d-4861-8458-9c374ff1e6b1`: clean n=3, 0 tracebacks, 0
  nonparticipating, 2/3 wins (smoke only). **Mechanism now clean**: 4
  `bank_escape` hops in 3 games, every one a single tick (no pinned runs), 0
  `bank_escape_refused` (no hop was refused, so the hold never had to fire).
  **But the rate undershoots the preregistered ≥3/game: 1.3/game.** Of 101
  `pull_landed`, 59 were on the enemy bank and 51 of those outgunned by the
  HP rule; at landing 45/51 had an enemy Rot disk over us (`rot_locked`) and
  only 4 had `blink_ready` — v4 spends Blink on `dodge_blink` ~70×/game, so
  it is usually cooling when the pull lands. The escape can only fire in the
  minority of brawls where the hooker's Rot is off and Blink is up.
- Trust bar before reading the directional: with ~1.3 hops/game the
  predicted deaths effect is small; n=40 per arm resolves ~±8pp only, so the
  readout is *directional only* and the likely honest verdict is "no signal
  at this N" unless the refusal hold or the rare hops move win rate a lot.
  Launched anyway because the matched v4 arm was already in flight and the
  pair is the only outcome readout for the change.
- 19:19Z baseline `iter7-directional-v4`
  `xreq_9071f4e6-f8ba-4609-8456-660557380b40` (v4, top-3, n=40) — completed
  20:05Z: clean 40/40, 0 tracebacks, win rate **0.550 ± 0.079**; west 0.650
  (n=20), east 0.450 (n=20); vs a-aron-pudge-rusher:v1 0.714 (n=14), vs
  co-gas-pudge-blind-hook-richard:v7 0.583 (n=12), vs pudge-wars-rusher:v16
  0.357 (n=14). `dodge_blink` 70.0/game, `recovery_start` 14.4/game.
- 20:05Z candidate `iter7-directional`
  `xreq_66cb8e23-e95d-4d4a-a1a7-18e28b2a9761` (v10, top-3, n=40) launched
  on the identical protocol.
