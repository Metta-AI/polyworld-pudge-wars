# Executable grounding: what this experiment represents

These documents are a **bounded executable projection** of the seven-layer proposal. The normative strategy block is text; its skill names resolve to inspectable, content-hash-pinned Python definitions in `coaching/symbolic/skills.py`. The generator emits explicit calls and conditional returns. It does not import or invoke an original complete policy.

The experiment separates two claims:

1. Can a grounded textual policy produce useful play in the real simulation?
2. Can executable strategy code be extracted into text and regenerated without changing decisions or memory?

Neither claim establishes that arbitrary prose, arbitrary symbolic code, or an inferred explanation of an author's intent can be translated losslessly.

## The two starting policies

`loom.policy.md` grounds the small movement-and-hook policy described in `../loom-current.md`: recover from the river, retreat at low health, follow a teammate's lane, rescue, and shoot the nearest clear target. This is a **projection**, not an assertion of exact equivalence with `coaching.policy.decide`: it chooses the lowest-ID living teammate as coach; shares the library's explicit hooked/own-flight guard; and uses the projected rescue eligibility and channel rules. It omits economy, upgrades, combat, wards and speculative aiming. Scores refer to this generated Loom projection.

`support.policy.md` is an assistant-authored candidate informed by `../exchange-partner.md` and inspection of `coworld/player/base.py`. It grounds observable defense, coordinated rescue, a rescue commitment, hook follow-up, velocity-based aiming, fog speculation, combat, economy and positioning as separate skills. It is **not an exact extraction of Base**. Among its differences are symmetric teammate lanes, explicit friendly-chain follow-up, and different ordering of combat and rescue. The original Base source is frozen separately as the opponent.

## What is orthogonal, and what remains coupled

The text distinguishes observed situation, memory/estimates, named goals, skill contracts, selection order, action emission, and revision. Strategy rules and exposed parameters can change independently of skill implementations. The shared binding hash is part of the policy artifact: changing a primitive changes policy semantics and requires another evaluation. Generated programs verify that hash when instantiated.

This first grammar represents strategy as an ordered decision list with action-channel claims and optional early termination. It does not yet implement a general partial-order goal solver. Goal labels are explicit interpretations of the skill library, not recovered psychological intentions. Numeric predicates and affordances live in the pinned skill contracts; they are not arbitrary description-logic expressions. Velocity is an uncalibrated point estimate. The `lead` parameter controls how strongly an estimate influences aiming; it is not a posterior probability or a belief in an opponent's intentions.

Each game supplies each seat's own fog-filtered observation. The policy cannot inspect hidden simulator state. Generated and regenerated copies see the same observation histories in shadow checks, then selected regenerated policies also play complete games independently to check trajectory identity.

Trace `result` is a skill's Boolean control return. It is not an observed success in the game: for example, movement and economy may emit actions while returning false to continue selection. The first benchmark's `skill_successes` field counts truthy control returns only. Command acceptance counts are separate and do not attribute later hits or rescues to exact requests.

## Reverse direction and its boundary

Extraction reads executable calls, literal parameters, conditions and returns using Python's AST. It does not read an embedded IR, comments or an attached original document. It regenerates a canonical AST and compares the entire module to reject behavior it cannot account for. A hand edit to a supported executable parameter must appear in recovered text and alter the expected action. Unknown code is rejected rather than described as understood.

Within this grammar, extraction is exact modulo the equivalent spellings `STOP IF` and `TRY ... THEN FINISH`, formatting and module documentation. Extraction cannot reconstruct the original prose rationale or arbitrary existing controllers. Library skill meanings remain a trusted authoring obligation, tested with concrete interventions; a matching round trip alone does not prove those meanings correct.

## Deliberately unresolved parts of the exchange proposal

The full exchange ontology still needs an exchange-phase tracker, interruptible options beyond rescue, explicit belief uncertainty and opponent learning, declarative goal conflicts, and receipt-correlated claims about successful effects. Those concepts are not silently replaced with unsupported predicates. Free Energy Principle and hemisphere analogies motivate revision but do not constitute implemented learning algorithms here.

The improvement loop extracts the executable candidate back into text, proposes bounded lead variants from that recovered IR, selects on development maps, and checks the selected candidate against both the initial policy and its untuned parent on separate maps and both banks. It preserves code, recovered text, hashes, decision samples and game results. The next iteration starts from the recovered parent unless the candidate passes the exploratory held-out improvement gate. This is a first strategy-parameter loop; it does not autonomously invent new ontology categories or establish the human-coaching hypothesis.
