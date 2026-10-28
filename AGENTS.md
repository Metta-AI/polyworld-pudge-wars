# Pudge Wars agent context

Start with [coworld/README.md](coworld/README.md) for the game-owned website,
IDE/Hermes context, and the dedicated fast-XP evaluation option. The published
context index is https://pudge-wars-site-theta.vercel.app/llms.txt; the complete
guide is available as text and JSON through the links in that index.

For BASIC policy evaluation, fast-XP uses
`https://fast-xp-k8s-prod.tail0f4a29.ts.net/v1/games/pudge-wars/run` from Softmax
Tailscale. Read its `/docs/llms.txt` and `/docs/pudge-wars/run.md` before calling.
The fast-XP game is `pudge-wars`; the CoWorld name is `pudge-wars-basic`.

Keep goal, hypothesis, immutable policy version, evaluation and evidence linked.
Compare baseline and candidate against the same pinned field, using both banks;
distinguish mono-team tests from mixed-team league evaluation. Preserve failed
episodes and uncertainty. Replay with the producing game revision.

Existing guides under `games/pudge-wars/skills/` also describe older Observatory
campaigns. Their API limits, polling and seed semantics do not apply to fast-XP.
Use the current service-specific guide. Publishing context does not authorize a
job, promote a policy, or install a Hermes extension. External endpoint calls
must use the separately permissioned container and return untrusted tool data.

The manifest's `game.docs.pages[agent-context]` mirrors `coworld/README.md` so the
same guidance is available to clients loading only the CoWorld manifest. Update
that inline page when changing the guide. Existing published CoWorld versions
remain immutable; editing this repository does not update a pinned release.
