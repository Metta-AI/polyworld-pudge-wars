# Pudge Wars v14 — semantic policy reference

Oracle: `pudge-wars-rusher:v14` (`41212e9a-6383-40f8-b44e-f4ceb64ef9c9`).
Runtime: 3v3 on Coworld 0.3.17, simulator 37. This document is structured prose,
not executable configuration. Execution internals live in the frozen skill library.

This is the starting semantic account of the existing oracle, not a newly accepted
strategy. Source inspection suggests the account; empirical probes must establish
its fidelity. A coach can cite the stable IDs below. No goal change is proposed.

The initial verification projection is the defensive-Blink initiation decision,
including competing fountain/river/rescue rules. Its exact glossary and finite
probe partitions will be recorded with the first experiment. Agreement must be
at least 99% in that projection and isolation must have zero violations; all
unmodeled behavior and any broader unverified claims remain explicit residuals.

## [runtime-v14] Run the frozen v14 skill library

Layer: Execution interface.

Use oracle.py with SHA-256 b848fa26c978ff1553ef91a00ddc1f85af32b5b2bfd4c67bd983f74cf66232b6. Instantiate BasePolicy with ally healing and fishing spacing enabled. The host applies JSON replies one tick later.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [s-alive] Alive

Layer: Situation.

Alive means self.alive is true. A dead agent emits no action and clears recovery and rescue commitment.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [s-bank] Bank and river

Layer: Situation.

Home bank means self.layer equals self.team. River means layer 2. The other land layer is the enemy bank. Distances below are Euclidean tile distances unless explicitly stated otherwise.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [s-visible] Visible target

Layer: Situation.

A combat target is a living, fog-visible enemy without a shield. The primary target is the nearest such enemy, preserving input order for ties. Hidden coordinates are unavailable.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [s-low] Low health

Layer: Situation.

Low health means HP is strictly below 40 percent of maximum HP. In team games, recovery remains active until HP is at least 75 percent. In duels only the 40-percent predicate controls retreat.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [s-threat] Nearby projectile

Layer: Situation.

A nearby projectile is an enemy hook in its flying phase within 22 tiles. The nearest qualifies as the threat. v14 does not check whether its trajectory approaches this player.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [s-close] Close combat

Layer: Situation.

Close hooking uses distance at most 20. Melee acquisition uses at most 5.5. An unfavorable nearby enemy within 12 triggers retreat. Rot proximity uses at most 8.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [s-brawl] Favorable brawl

Layer: Situation.

A brawl is favorable if own HP plus 40 reaches the target HP, target HP is at most 120, or self occupies enemy land. This is a heuristic, not a calibrated win probability.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [s-free] Free for support

Layer: Situation.

Free means on home land, not hooked, not recovering, with no nearby projectile and no foreign-Rot retreat. Rescue initiation also excludes all foreign Rot.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [s-ping] Fresh teammate ping

Layer: Situation.

A ping is fresh for age 0 through 95 ticks. A swimmer explicitly requests rescue when its own fresh ping is within 4 tiles of it.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [s-rescue] Ally needs rescue

Layer: Situation.

An ally needs rescue when carried by an enemy chain, or in water with HP at most 60 percent or an explicit nearby ping. A returning friendly chain already owns its rescue.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [s-rune] Upcoming rune

Layer: Situation.

An upcoming drop is eligible for lane assignment when its remaining clock is positive and at most 256 ticks. The nearest living, unhooked, non-rotting home-bank ally at at least 40-percent HP owns collection; ID breaks ties.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [s-lane] Clear friendly firing lane

Layer: Situation.

A shot is blocked if another unshielded ally is within hook radius plus 3.1 tiles of its segment, either now or at half its eight-tick motion estimate. The intended support recipient is exempt. Shields greater than 9 ticks exempt an ally.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [s-shop] Shopping opportunity

Layer: Situation.

Shop access comes from self.in_shop. A planned shop visit requires at least 12 gold, an unfinished treads or longflight rank, and no higher-priority movement.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [s-heal] Safe healing pair

Layer: Situation.

Both players must be living, on home land, unhooked, unshielded, not rotting, more than 28 tiles from visible enemies and hostile hooks, and not carried by a hook. The recipient lacks at least 120 HP; the healer has a ready hook, at least 60-percent HP, no owned hook, a 4–24 tile gap, and is at most 4 tiles forward of the recipient. Choose lowest recipient health fraction, shortest gap, then IDs.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [b-velocity] Observed unit motion

Layer: Belief.

Retain each visible living unit position. Every at least 8 ticks, estimate displacement scaled to an eight-tick interval. Unobserved velocity is not ground truth; no calibration claim has been established.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [b-memory] Remember the last enemy

Layer: Belief.

Remember the nearest visible enemy and last-seen tick. For at most 96 ticks extrapolate its position using observed motion. Later probe near the opposite river lip, retaining projected lane height clamped to 16–111.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [b-roster] Stable team identity

Layer: Belief.

Remember observed teammate IDs across deaths for stable fishing lanes. Reset all policy memory when the observed tick goes backwards. This memory does not reveal enemy state.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [g-win] Win the match

Layer: Goal.

Prefer reaching the team kill objective while preventing enemy kills. Preserve this goal during research; any proposal to change it requires human review.

Provenance: Human: existing requests to win, heal and cooperate; restated without a goal change.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [g-survive] Preserve fighting strength

Layer: Goal.

Avoid preventable deaths and regain health so the team can keep fighting. This goal supports g-win and does not authorize indefinite inactivity.

Provenance: Human: existing requests to win, heal and cooperate; restated without a goal change.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [g-support] Useful cooperation

Layer: Goal.

Use healing, rescues, and separate fishing lanes to support g-win. Human praise or a successful heal alone is not evidence of a win-rate benefit.

Provenance: Human: existing requests to win, heal and cooperate; restated without a goal change.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [k-economy] Economy interface v14

Layer: Skill.

Start on each living decision with points or shop access. Finish after emitting the feasible purchase requests for that observation. The host validates purchases. Never suppress defensive actions to wait for a purchase.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [k-rescue] Rescue interface v14

Layer: Skill.

Start when free for support and the nearest eligible rescuer is self. Throw safely at the selected ally. Hold position for ten ticks or while the friendly rescue chain carries an ally; interrupt for death, capture, danger, or recovery.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [k-blink] Defensive Blink interface v14

Layer: Skill.

Start when Blink is ready and a fountain escape, river exit, or nearby projectile applies. Prioritize those three in that order. For a nearby projectile, Blink inland and sideways without inspecting its motion. End after issuing one Blink request; readiness and the host decide availability next tick.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [k-fountain] Fountain escape interface v14

Layer: Skill.

Start on enemy land, unhooked and not rotting, at y 56–72 on simulator 35 or newer. Avoid leaving close combat unless recovering. Request the computed home-bank point only within 20 tiles with a clear landing corridor and no nearby Rot. End after the request.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [k-hook] Hook selection interface v14

Layer: Skill.

Start when a hook is ready, self is not hooked, and no earlier shot claimed this tick. Emit at most one ally-safe shot and stop after the first successful claim. The physical hook lifetime and windup are controlled by the engine.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [k-heal] Healing interface v14

Layer: Skill.

Start when free for support, outside foreign Rot, with no enemy catch or swimmer and no earlier shot, and self owns the safe healing pair. Throw at that recipient and hold for ten ticks as rescue does. Interrupt on the same danger conditions.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [k-melee] Melee interface v14

Layer: Skill.

Start for a favorable nearby target within 5.5 tiles when not fleeing Rot. Emit attack_target; the engine sustains the attack until interrupted by later commands or loss of eligibility.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [k-recovery] Recovery interface v14

Layer: Skill.

Enter recovery below 40-percent HP. Continue choosing the home pad until at least 75-percent HP in team games, subject to higher-priority escape and combat movement. Death clears commitment. Duel recovery ends once no longer below 40 percent.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [k-fish] Fishing interface v14

Layer: Skill.

Start when higher-priority movement is absent. Maintain a stable roster lane from 32 to 96, add a bounded periodic juke, and reserve at least 24 vertical tiles around the single rune collector. Terminate when danger, support, combat, ping, shopping, or a ward trip takes priority.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [k-ward] Ward interface v14

Layer: Skill.

With a modern carried ward on home land, place three tiles beyond the enemy lip when within 32 tiles; adjust central lanes to y 50. Otherwise approach five tiles behind the home lip only when no higher-priority movement is busy. Stop once the charge is consumed or the opportunity ends.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [t-economy] Invest in useful reach

Layer: Strategy.

For g-win, select economy independently of movement: spend points in distance, speed, damage, radius order; at the shop obtain a free ward, a flask below half HP, alternate longflight and treads purchases, and buy big-hook when eligible.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [t-rot] Bound Rot exposure

Layer: Strategy.

For g-win and g-survive, enable Rot only with an enemy within 8, favorable brawl, no river, no recovery, and HP above 96. Otherwise disable it. Treat another nearby Rot cloud as retreat-worthy when not using our own Rot.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [t-rescue] Honor rescue ownership

Layer: Strategy.

For g-support, keep a safe active rescue before starting another. When free, choose the nearest eligible ally and let the nearest eligible rescuer own it. A successful rescue claim ends this decision after holding position.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [t-defense] Escape before fishing

Layer: Strategy.

For g-survive, select k-blink after rescue checks and before ordinary hook selection. A successful Blink request suppresses later walking. A hooked player stops after defensive and economy requests.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [t-hook-close] Close hooking first

Layer: Strategy.

For g-win, k-hook first attempts the nearest enemy within 20 while self is outside water.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [t-hook-catch] Follow existing catches

Layer: Strategy.

For g-win, if no shot is claimed, k-hook aims halfway between the first caught enemy and its visible reeler. If the reeler is unknown, use the victim position.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [t-hook-threat] Counter a close projectile

Layer: Strategy.

For g-survive, if no shot is claimed and the nearest threat is within 14, k-hook aims at that projectile. The counter-hook heuristic is retained without claiming it is effective.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [t-hook-swim] Exploit an exposed swimmer

Layer: Strategy.

For g-win, if no shot is claimed, k-hook targets the first visible enemy in water.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [t-heal] Heal during a safe opening

Layer: Strategy.

For g-support, select k-heal after urgent shots and before speculative distant shots. A successful healing claim ends this decision.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [t-hook-lead] Lead a visible target

Layer: Strategy.

For g-win, if no shot is claimed, lead the nearest target using its eight-tick displacement and Chebyshev distance divided by 30 plus speed rank. Skip this attempt if its segment passes within 5 tiles of the fountain center.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [t-hook-rune] Take a reachable rune

Layer: Strategy.

For g-win, when outside water and no shot is claimed, attempt visible runes within 36 tiles on each axis in observation order.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [t-hook-fog] Probe the remembered lane

Layer: Strategy.

For g-win, when no target is visible, outside water and after tick 8, use k-hook to probe the opposite-bank point supplied by b-memory, or the current lane if no enemy has been remembered.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [t-move] Choose one movement skill

Layer: Strategy.

For g-survive and g-win, movement priority is foreign-Rot escape, projectile dodge, river exit, melee commitment, favorable catch conversion, recovery or unfavorable-close retreat, eligible teammate ping, shopping, then fishing. Ward approach may replace only idle fishing.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [u-loop] Research acceptance

Layer: Update.

Freeze the original oracle. Write each semantic edit and prediction before compile. Verify decision-table isolation and coverage, evaluate on a fixed seeded pool, lift behavior, reconcile, and ablate every edit. Keep only with the predicted delta interval excluding zero. Preserve rejected iterations in an append-only ledger.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.

## [u-coaching] Co-play notes are hypotheses

Layer: Update.

Attach each human note by session and timestamp to the affected block. Check its screenshot and video context. Notes do not change the running policy or count as win-rate evidence; compile and test a candidate afterward.

Provenance: Source account of frozen v14, authored 2026-09-15; requires behavioral verification.

Evidence: Untested semantic account; no ablation effect or confidence interval established.



## [g-dual-utility] Two useful outcomes of a support hook

Layer: Goal.

DualUtilityOutcome means HealAlly OR DamageEnemy, subordinate to g-win and g-support. It explains why a wounded ally and enemy in a melee can both be acceptable contacts. It adds no reward weight, guarantee of contact, or override of survival and rescue priorities. Healthy allies can be displaced without healing value. Preserve the existing match objective.

Provenance: Session 2026-09-15t21-41-17-535zc09870, speech-33 and speech-37/38, 03:00–03:13 and 03:33–03:49. Coach intent checked against linked frames; exact simultaneous-contact outcomes are not established by the recording.

Evidence: Descriptive refinement of existing cooperation goals. Behavioral and match validation is required for any new strategy realizing it.

## [k-curve-reviewed] CurveHook research status

Layer: Skill.

CurveHook is an inactive research proposal: reposition during an empty hook's return when a target-directed safe displacement can improve its return path. The engine retains bounce waypoints before chasing the owner's landing point. Do not execute unconditional perpendicular movement from cast initiation until retraction ends. No CurveHook strategy is enabled in this policy.

Provenance: Session speech-51/52, 05:51–05:58. Human says to reposition as the hook goes back. Immediate continuous perpendicular motion was an unreviewed synthesis inference.

Evidence: Prior E02 tested bounded return steering on seeds 916001–916012: 24 games, margin +0.667, 95% seed-block interval [-0.292, 1.792], only 24 changed decisions. Its gate failed; do not repeat this candidate as a new discovery. See ../session-20260915/return-sweep.ir.md and ledger.jsonl.


## [s-engagement] Wounded ally in visible melee

Layer: Situation.

A pair contains a living visible ally other than self and a living visible unshielded enemy. The ally is unshielded, unhooked, and missing at least 120 HP. The enemy is unhooked. They occupy the same layer and are at most 5.5 tiles apart. Their engagement centroid is the arithmetic midpoint of their current observed positions. It is within current hook reach from self and its segment from self is more than 3.5 tiles from (64.5,64.5). Order pairs by ally health fraction, distance from self to ally, ally ID, then enemy ID. A pair is a melee-proximity proxy; the observation does not prove they are attacking each other.

Provenance: speech-37/38 supports hooking the general direction of the fight; exact centroid, 120-HP threshold, ordering and 5.5-tile predicate are explicit implementation hypotheses E04, grounded in existing melee and healing thresholds.

Evidence: E04 rejected for retention: 24 complete games on seeds 917501–917512 across both banks, 12 wins / 12 losses, mean margin 0.0; 95% seed-block bootstrap interval [-4.625, 4.958]. 1,904 finite probes and 1,152,627 runtime decisions have zero scoped semantic/round-trip mismatches; 7,307 hook decisions changed with no non-hook or memory leaks. These are request decisions, not 7,307 distinct accepted casts or heals. See ledger.jsonl and duels/coaching-20260915-scrum/engagement/screen-summary.json.

## [k-engagement-hook] CastHook at a melee midpoint

Layer: Skill.

Try each s-engagement pair in order using the existing throw primitive at its centroid, exempting only that wounded ally from the friendly corridor test. Other allies still block. Stop at the first accepted request. Use current observed positions without a new velocity estimator. CastHook initiation still requires self alive, unhooked, hook ready, and no previously selected hook. Issuing a request does not guarantee an engine-accepted cast or a hit. This skill changes no memory or non-hook action and creates no rescue hold.

Provenance: E04 bounded implementation of the coach's two useful possible contacts.

Evidence: E04 rejected for retention: 24 complete games on seeds 917501–917512 across both banks, 12 wins / 12 losses, mean margin 0.0; 95% seed-block bootstrap interval [-4.625, 4.958]. 1,904 finite probes and 1,152,627 runtime decisions have zero scoped semantic/round-trip mismatches; 7,307 hook decisions changed with no non-hook or memory leaks. These are request decisions, not 7,307 distinct accepted casts or heals. See ledger.jsonl and duels/coaching-20260915-scrum/engagement/screen-summary.json.

## [t-engagement-hook] Prefer a useful melee opportunity

Layer: Strategy.

For g-dual-utility, try k-engagement-hook after the parent's urgent rescue, close combat, caught-enemy, nearby-hook, swimmer and safe-healing rules, before its ordinary predicted enemy shot. Require s-free, no foreign Rot, and no selected hook. If no pair can claim the hook, use the unmodified remaining parent strategy. Preserve purchases, Blink, Rot, attacks, movement and existing memory on identical observations. No unseen target is supplied by this rule.

Provenance: Session 2026-09-15t21-41-17-535zc09870, speech-33/37/38. E04 tests a scoped preference, not a claim that every scrum is desirable.

Evidence: E04 rejected for retention: 24 complete games on seeds 917501–917512 across both banks, 12 wins / 12 losses, mean margin 0.0; 95% seed-block bootstrap interval [-4.625, 4.958]. 1,904 finite probes and 1,152,627 runtime decisions have zero scoped semantic/round-trip mismatches; 7,307 hook decisions changed with no non-hook or memory leaks. These are request decisions, not 7,307 distinct accepted casts or heals. See ledger.jsonl and duels/coaching-20260915-scrum/engagement/screen-summary.json.

Evidence: Executable source and independent reference agree throughout the measured E04 decision stream. Unobserved outcomes and goal rationale remain outside the lifted projection.
