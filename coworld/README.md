# Pudge Wars CoWorld: IDE and Hermes context

This repository owns the game and its CoWorld package. The Pudge Wars website
owns browser play and publishes agent-readable guidance. Observatory supplies
competition records and hosted execution; the existing Softmax IDE supplies the
assistant workspace.

## Published context

| Resource | URL |
| --- | --- |
| Game-owned site and browser play | https://pudge-wars-site-theta.vercel.app/ |
| Agent context index | https://pudge-wars-site-theta.vercel.app/llms.txt |
| Complete readable guide | https://pudge-wars-site-theta.vercel.app/llms-full.txt |
| JSON guide bundle with document hashes and revision | https://pudge-wars-site-theta.vercel.app/api/coworld/context |
| CoWorld identity and evaluation options | https://pudge-wars-site-theta.vercel.app/api/coworld |
| Public competition snapshot | https://pudge-wars-site-theta.vercel.app/api/coworld/competition |

IDE/Hermes can read these public resources through its permitted tool path.
Record the bundle revision when using it as context. The site does not currently
provide an experiment queue, saved policy registry, automatic goal engine or
installed Hermes extension. Existing sessions must explicitly load the context.

## Dedicated fast-XP option

For full-speed BASIC policy experiments, use
**https://fast-xp-k8s-prod.tail0f4a29.ts.net/**. This is a separate evaluation
service from Observatory episode requests and browser play.

- Read `/docs/llms.txt`, then `/docs/pudge-wars/run.md` on that host for the current
  caller contract. `GET /v1/games` reports the active game release and admission
  state; `/v1/metrics` reports the deployed seat count.
- Requires Softmax Tailscale access. No API token or Authorization header is
  needed; do not forward a site or Observatory credential.
- POST JSON to `/v1/games/pudge-wars/run`. The game identifier is `pudge-wars`,
  while this package's CoWorld name is `pudge-wars-basic`.
- Each roster player supplies exactly one of BASIC `source`, ZIP
  `package_base64`, or a submitted `policy_ref`. Pin policy versions; a leaderboard
  display name is not a policy reference. Source is limited to 64 KiB; ZIPs to
  16 MiB with exactly one `.bas` entry and optional model resources.
- Supply an integer `seed`; `num_episodes` is 1–10. Each episode increments the
  seed. Unpinned entries rotate; pinned slots stay fixed. For six seats, 0–2 are
  West and 3–5 East. Check the deployed roster before pinning slots.
- Pin optional `game_version` to the exact `current_version` from `/v1/games`.
  Omit `config.max_ticks` for the deployed league duration; short execution
  checks may override it within the Pudge-specific 1–40000 limit.
- The same HTTP response returns a replay/log ZIP. There is **no polling or
  later-download endpoint**. Allow at least 15 minutes for batches plus ten
  minutes for cold starts, and longer for queued work. A lost connection may
  leave work running with no recoverable response.
- Batches contain `manifest.json` and per-game directories. Check every episode's
  status, not just the overall HTTP 200. Private logs are returned only for
  uploaded source/packages, never for `policy_ref` entries.
- HTTP 429 means no work was admitted: honor `Retry-After`, add bounded
  exponential jitter and retry the unchanged payload within the budget. Do not
  blindly retry a timeout/disconnection or silently change a rejected version.
- External LLM/Jev calls and human play are outside this endpoint. These
  evaluations do not submit a policy or update league rankings.

The published complete guide includes payload examples, throughput guidance,
error handling and a balanced baseline/candidate experiment. Fetch the live
service documentation before execution; this summary is discovery context.

## Evaluation workflow

Record the user's selected player, existing goal, baseline, one hypothesis and
the exact candidate source/package hash. Freeze opponent versions, teammate
assignments, game release, seed schedule, duration, metric and budget for each
comparison. Public standings do not establish ownership or execution permission.

Evaluate baseline and candidate against the same field, and play each seed block
from both banks. Explicitly pin the full roster: fast-XP does not swap banks for
pinned candidates. Mono tests fill the candidate's entire bank; mixed tests put
it beside other policies. Check the actual league format before making league
claims. Seed/bank pairs and multiple seats are correlated observations; keep their
identity rather than counting every seat as an independent game.

Inspect representative losses with a decoder matching the producing game
revision. Connect direct behavior (hooks, blinks, movement, rot) to intermediate
effects (upgrades, runes, denies), then outcomes. Keep candidate-seat metrics
separate from team totals. Report counts, failures, draws and uncertainty; confirm
promising changes on fresh seeds. Policy promotion is a separate authorized step.

For local execution, see `coworld/GAME_HOSTED_MIGRATION.md` and
`scripts/run_episode.py`. Existing `games/pudge-wars/skills/eval-design/README.md`
and `games/pudge-wars/skills/replay-inspection/README.md` include historical
Observatory campaigns. Their 10–20 episode requests, polling and independent-seed
assumptions belong to those campaign tools, not the fast-XP API above.

## Hermes boundary and release discovery

The shared Hermes UI contract owns context-in and commands-out. Keep this
game-specific guidance in the game context; it does not require a separate SOUL
distribution. Displaying a goal/task/leaderboard is distinct from executing work.

Fast-XP submission is an `external.action`; discovery is `external.read`. Calls
to the service and replay analysis run in the separately permissioned container,
without the agent filesystem or core credentials. Results enter as untrusted tool
responses, not injected artifacts or profile instructions. A backend adapter must
handle the long response and bounded ZIP inspection; the site's draft Hermes SDK
does not implement that runner.

This guide is also embedded in `game.docs.pages` of the BASIC manifest template.
A source checkout sees it at the commit containing this change. Consumers pinned
to an older source commit or published CoWorld manifest keep the older context;
publishing a new CoWorld release is a separate operation.
