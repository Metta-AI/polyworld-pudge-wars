# v16-derived BASIC rusher — executable semantic contract

This is a bounded port of `session-20260915-bundle/retained.policy.py` (E06b,
published as Python v16), with healing and spread fishing enabled. It is not
decision-equivalent to Python. The seven layers below are grounded by
`controller.bas`; the compiler recognizes this whole program family and rejects
unsupported executable or prose edits. Provenance and competitive evidence are
in README.md, outside the executable contract.

1. **Situation.** Cache at most ten fighter IDs from the fog-filtered BASIC
   object API. Ignore gadgets as combat targets and shielded enemies. Choose
   the nearest exposed enemy, catch, swimmer, and incoming flying enemy hook
   (within 32 tiles). Resolve ties by observed object order. All team members,
   including dead members, retain their lane rank. Never consult hidden enemies.
2. **Belief and memory.** Sample each fighter's integer tile position at least
   eight ticks apart; normalize displacement to eight ticks. Reset velocity
   after a gap over 96 ticks or observed death. Maintain the last visible enemy
   for speculative fog casts. Teammate max HP is unavailable: use max(1200,
   highest observed HP), a lower bound, for health fractions. Other players'
   hook cooldowns are unavailable; healing arbitration can exclude active
   chains but cannot know readiness. Reset options and cached samples on tick
   rollback or a new spawn shield. Death is skipped by the host.
   Also sample each visible owner's hook-head displacement at least four ticks
   apart. Reset hook samples on visibility gaps over eight ticks and phase
   changes; retain the last speed across a phase change. Estimate end-of-flight
   speed with a six-centitile acceleration allowance; clamp to 60–180 centitiles
   per tick. This is observed motion, not access to hidden upgrade levels.
3. **Goal.** Preserve the game's kill objective. Prioritize emergency ally
   rescue and self-preservation; then prefer ally/enemy melee midpoints to
   either heal the ally or damage the enemy. This goal is authored provenance,
   not intent inferred from code or a claim of optimal play.
4. **Skills.** Spend points on distance, speed, damage, radius. At the shop,
   request a free ward, a flask below half health, repeated Longflight/Treads,
   then Big Hook only without an active buff. Recover below retreatPct until
   recoverUntilPct. Use Rot for favorable nearby combat. Blink out of water,
   across the narrow fountain when escaping, or inland from incoming hooks;
   reject occupied/Rot-contaminated fountain crossings. All throws reject
   fountain segments and friendly corridors except the intended recipient.
5. **Strategy.** Hold an existing ally rescue; try native coordinated rescue;
   defend with Blink; try the wounded-ally priority ordering of melee pairs
   (lowest ally health fraction, then distance), close combat, a catch aimed
   toward its observed reeler, close hook interception, and swimmers. For an
   existing catch-target shot with measured hook speed, predict the reel and
   our nine-tick windup plus accelerating flight for up to 80 ticks. Try a
   three-tile collision allowance within reach, before the victim reaches six
   tiles from the reeler. Fall back to the original midpoint when no predicted
   shot is accepted. Keep existing casting priorities and movement. Try one
   deterministic safe healing pair (missing >=120 HP, healer >=60%, distance
   4–24, both >28 from enemies/hooks, at most four tiles forward). Then try
   velocity-led nearest-target combat, runes, and a fog lane. A rejected first
   melee pair falls through to later skills, not another pair. Unlike Python,
   the old additional five-tile ordinary-shot fountain margin is omitted;
   the universal 3.5-tile fountain disk remains.
6. **Execution.** Movement prioritizes Rot escape, hook dodge, leaving water,
   melee, catch finishing, recovery, one native human-ping responder, shopping,
   and stable fishing lanes. Lanes span Y32–96; one nearest eligible teammate
   pursues an upcoming rune within 256 ticks; others seek 24-tile spacing on
   Y16–108 (best effort if the roster is too large). Ward trips use only idle
   movement. If curveEnabled, an eligible accepted throw starts persistent
   perpendicular movement through the 9-tick windup, flight and return. Retain
   pending state for 12 ticks; clear when an observed hook ends. Reverse at
   own-bank bounds (X8..west-1 or east+1..119, Y16..111). Recovery, capture,
   death/respawn, off-bank state, Blink, melee, nearby hooks/Rot and ally rescue
   interrupt it. A carried ward also interrupts CurveHook so an idle ward trip
   reaches placement range. After placement, normal curve eligibility resumes.
   CurveHook may still override fishing, shopping, and rally movement.
7. **Update and numeric binding.** No runtime learning. Edit the registered
   parameters, regenerate BASIC, extract and regenerate it, then evaluate on
   fresh paired-bank maps. Coordinates and velocity are integer tiles; division
   truncates toward zero. Midpoints truncate. Use integer floor square root
   to clip range and quantize eight-tile perpendicular steps. Fountain center
   (64.5,64.5), radius 3.5 uses doubled-coordinate integer cross products,
   including segment endpoints; clipped endpoints are integer approximations.
   Friendly clearance is 5 + ceil(radiusLevel/8), or
   8 + ceil(3*radiusLevel/16) under Big Hook. The ordinary margin is a measured
   pressure/safety tradeoff, not a guarantee of collision clearance with integer
   observations.
   Check current and half-sample
   projected teammate positions, skipping shielded teammates. These differ
   from Python floating positions and exact shield duration. BASIC actions
   apply synchronously; engine acceptance owns collision, windup, and budget
   enforcement. Native rescue eligibility/arbitration replaces Python's
   readiness-based nearest-rescuer selection.

Only the following parameter block is editable in this registered family.

```pudge-rusher-basic
{
  "holdBack": 16,
  "leadDiv": 30,
  "retreatPct": 40,
  "recoverUntilPct": 75,
  "curveEnabled": 1
}
```
