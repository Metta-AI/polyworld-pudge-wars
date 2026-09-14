# Pudge Wars investigation bindings

This repository owns the game and its policy sources. These bindings adapt the
installed research skills to Pudge Wars; they do not require the CoGames,
Mettagrid, CogsGuard, or agent-policies repository layouts.

| Binding | Entry point |
| --- | --- |
| `replay-inspection` | [Replay format, viewing and survey](skills/replay-inspection/README.md) |
| `eval-design` | [Hosted comparisons](skills/eval-design/README.md) |
| `diagnosis` | [Failure vocabulary and evidence](skills/diagnosis/README.md) |

Read [META.md](META.md) and [closed_levers.md](closed_levers.md) before proposing
another policy change. The [improvement investigation](../../docs/pudge-improvement-roadmap.md)
records the current findings and next experiments. No automatic deployment or
XP spending is implied by this manifest.

Build/upload surface: `coworld/player/Dockerfile`, documented in
[the player README](../../coworld/player/README.md). Build linux/amd64 and
select the experimental arm with the `POLICY_ARM` build argument. The image
starts `python -m coworld.examples.pudgewars.player.player`; register that argv
explicitly at upload. Record each immutable upload immediately in
[VERSION_LOG.md](players/pudge-wars-rusher/VERSION_LOG.md). Source/runtime pins
remain those in META.md; a game rebuild is not needed for these Python changes.
