# User preferences (verbatim, attributed, dated)

**Aaron (aaln), 2026-09-17, session 53dc4bedf928403fa5309ba0df2a6aa4:**

> auto research to improve the policy to rise in the league ladder ranking of the pudge wars game.
> ensure you record the LLM compute cost of every policy iteration. Use the ultra devin model.
> Start from the baseline default python policy of pudge wars and keep improving. track your progress in a branch.
> Setup automation for every 3 hours to continue new iterations on top of the previous latest policy.

Interpretation recorded by the optimizer:

- Autonomy is widened for the research loop: hypothesize, change, build, upload,
  and evaluate without pausing for approval each iteration (overrides the
  optimizer-seed propose-and-pause default for those steps).
- League **submission** is not covered by the above and stays behind an explicit
  go-ahead (`STATE.json` → `submission.allowed`).
- "Baseline default python policy" = `coworld/player` at the repo's main HEAD,
  Dockerfile defaults (`rusher` personality, `combined` arm) — the same code as
  the bundled Rusher starter. Not `pudge-wars-rusher:v16`, which is Aaron's
  current #1 entrant and is used only as a comparison reference.
