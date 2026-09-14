# support_spatial_12: orthogonal policy IR

Format: symbolic policy text v1. Binding: pudge-skills-v2.
Origin: After the wide formation reduced contact but lost more confirmation games: preserve useful teammate proximity while retaining unique rune ownership and local avoidance. Only lane_spacing changes.

## 1. Situation

Players have team, identity, tile position, health, cooldown and inventory. Hooks have owner, victim, location and flight state. Inputs are each seat's fog-filtered observation. Numeric regions and affordances are defined by the skill contracts below; missing enemies remain unobserved, not absent from the world.

## 2. Belief

The observe skill retains sampled velocity and last-seen enemy position as point estimates, without calibrated confidence. Fog shooting, when selected, consumes that estimate. No hidden simulator state, opponent intentions or fabricated Bayesian probabilities enter selection. Context and memory reset when simulation ticks decrease; each seat owns its own state.

## 3. Goal

Named skill purposes below explain local preferences. Ordered control flow and channel claims resolve their conflicts. These labels are author/library interpretations; source code alone cannot recover a human's original reasons or a unique global reward function.

## 4. Skill

All skills terminate for this decision unless their contract explicitly retains state. Non-stopping steps compose actions; first feasible hook request claims the hook channel. Movement routines set the requested destination; later permitted movement can replace it. A rejected request does not establish a successful game outcome.

**skill.alive — Participation.** Whether self is alive. A false result can end selection without actions.

**skill.observe — Situation and belief update.** Classify low health at retreat_percent; estimate visible velocity from samples at least eight ticks apart; retain last-seen target and dodge side. Estimates are uncalibrated, not probabilities.

**skill.remember_roster — Stable team roles.** Remember every observed teammate, including dead seats, ordered by home_y then ID. Death does not renumber lanes. Missing roster members remain remembered until the match resets.

**skill.economy — Long-term capacity.** Spend skill points on distance, speed, damage, then radius; buy available free wards, a low-health flask, repeated reach/boots ranks and an unoccupied hook buff. Decisions use confirmed inventory for later ward trips.

**skill.combat — Survival and local combat.** Enable rot only for favorable close combat away from river/low health. Compare own health plus forty against nearest target, target <=120 health, or being stranded on enemy land. Attack within 5.5 tiles when favorable; mark hostile/ally rot exposure for movement.

**skill.sustain_rescue — Teammate availability.** While safely on our bank, hold position during our friendly rescue flight or its ten-tick commitment. Higher danger/low health interrupts. Returns true while holding.

**skill.rescue — Teammate availability.** Try the nearest living teammate on an enemy hook or below/equal 60% health in the river. Coordinated mode elects one eligible rescuer by distance then ID; success holds position and starts a ten-tick rescue commitment. Returns true only when a hook request is emitted.

**skill.blink_defense — Survival.** If blink is ready, escape the river toward our bank or move away from an incoming hook within the actual twenty-tile blink disk. Never chase offensively.

**skill.hooked — Control availability.** Whether an enemy hook currently restricts our control; a true result may end selection after defensive actions.

**skill.follow_up — Team conversion.** Try a visible enemy carried by a friendly hook, aiming between victim and reeler. Claims hook only if the throw primitive accepts its checks. End after one request.

**skill.close_shot — Immediate pressure.** Try the nearest visible enemy within twenty tiles while outside the river.

**skill.intercept_hook — Defense.** Try a hostile flying hook within fourteen tiles. This attempts an interception; it does not guarantee one.

**skill.swimming_shot — Team conversion.** Try the nearest eligible enemy in the river.

**skill.aimed_shot — Pressure under motion uncertainty.** Try the nearest eligible enemy within current reach plus five. Lead its sampled velocity by lead times Chebyshev distance divided by thirty plus speed rank. Exclude an aim segment within five tiles of the center.

**skill.rune_shot — Resource acquisition.** Outside the river, try an observed rune within a thirty-six-tile square, in observation order. First feasible throw wins.

**skill.fog_shot — Exploration under partial observation.** When no eligible enemy is visible, project the last-seen position using velocity; after ninety-six ticks use a bank-edge horizontal prior. Clamp to the enemy bank and arena. This is an uncertain speculative shot, not an observed enemy.

**skill.formation_positioning — Survival, information and team space.** Resolve the existing tactical movement priorities, then ward placement/approach, then spread_formation in one skill, avoiding computing an idle lane that will be replaced. Priority: foreign rot, hook dodge, river exit, melee, caught target, low/unfavorable retreat, shop, then fishing. Only routine fishing/ward approach is changed. Assign stable, symmetric lanes, bounded to y=24..104. For an announced rune within rune_window ticks, elect one healthy unhooked teammate on our bank whose assigned lane is nearest the rune (ID breaks ties). Reserve its rune lane; other seats choose distinct lanes at least lane_spacing apart when space permits. A bounded two-tile juke stays inside each lane. Survival, rescue, melee, caught-enemy approach and shop travel retain priority. Confirmed ward stock is placed across the river within 32 tiles; routine travel may approach that range. bank_margin controls normal fishing distance behind the bank lip.

**skill.clear_occupied_route — Personal space and progress along the bank.** For nonurgent own-bank walking, test the next lookahead tiles against visible living bodies. A body ahead within clearance affords a short unobstructed detour, not repeated walking through it. Choose a progress-making eight-tile waypoint with body clearance inside the conservative bank rectangle x=18..west_lip-4 or east_lip+4..110, y=20..107. Retain a safe waypoint for up to 24 ticks to avoid alternating sides. Already-close bodies may be escaped but not approached. If no safe waypoint exists, hold this tick and retry. Blink, river escape, incoming-hook dodge, low-health retreat, rescue, melee and caught-enemy approach bypass this skill. Terrain pathfinding still belongs to the engine; unseen obstacles are not inferred.

## 5. Strategy

The block below is normative executable text. DO attempts a skill and continues; TRY finishes the decision only when the skill reports success; STOP IF/UNLESS ends the decision on its condition. FINISH preserves actions already composed. Ordering is an explicit conditional preference over resource use, not a scalar reward. Skill parameters override only their named contracts. Prose supplies the ontology and interpretation; the supported compiler consumes this block and the pinned skill definitions.

```policy-ir
POLICY support_spatial_12
BINDINGS pudge-skills-v2 b8321385c799af309e2163793d8fea3d3108b762446f49ffdeed748cdbce5fed
STOP UNLESS alive
DO observe(retreat_percent=40)
DO remember_roster
DO economy
DO combat
TRY sustain_rescue THEN FINISH
TRY rescue(coordinated=True) THEN FINISH
DO blink_defense
STOP IF hooked
DO follow_up
DO close_shot
DO intercept_hook
DO swimming_shot
DO aimed_shot(lead=1.0)
DO rune_shot
DO fog_shot
DO formation_positioning(bank_margin=16, lane_spacing=12, rune_window=256)
DO clear_occupied_route(clearance=7, lookahead=12)
```

## 6. Execution

Generate straight-line Python calls and explicit conditional returns against the pinned skill library. No original complete policy or embedded source is executed. A code-derived extraction must account for the whole supported AST; unknown statements are rejected. Reproducibility requires this policy, binding content hash, engine version, observation history and initial memory. Real-time network scheduling is outside an accelerated simulator comparison.

## 7. Update

Revise a named skill parameter or preference order in this text; generate a candidate; extract its executable behavior back to text; regenerate; compare full action histories and completion scores. Keep held-out seeds separate from candidate selection and preserve failed attempts. Performance evidence may propose a strategy/skill change; it does not recover an author's rationale or authorize unrecorded goal changes. Changes inside a skill require a new binding hash and new behavioral evidence. General ontology induction and unrestricted code extraction remain outside this bounded grammar.
