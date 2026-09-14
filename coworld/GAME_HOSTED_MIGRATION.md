# Pudge Wars and game-hosted policies

Assessment: 2026-09-09, against fetched Metta main
`048a7f400ca8b5fef987dead04b152e027671a57`.

**Use game-hosted for a BASIC-only competition. Keep the current league on
platform-hosted until its entrants have a migration path.** The live canonical
Coworld is `pudge-wars:0.3.13`
(`cow_8ef8b994-1cd2-4ebb-b452-22ea8a46404e`); it accepts Docker policies.
This update publishes Aaron's improved rusher in that existing format.

Runtime migration and game-rule upgrades are separate changes. In particular,
the live engine still sells permanent wards for 8 gold with 3-tile placement;
the working tree supplies free, consumable wards with 32-tile placement. The
Python policy detects the newer observation field before using that strategy.
Switching the hosting mode alone would not introduce those newer game rules.

## What the new runtime provides

The [runtime contract](https://github.com/Metta-AI/metta/blob/048a7f400ca8b5fef987dead04b152e027671a57/packages/coworld/src/coworld/docs/PLAYER_RUNTIMES.md)
adds `game.player_runtime: "game-hosted"`. The runner stages verified player
files and the game executes every seat inside its game container. This removes
the need for separate player pods and a WebSocket action exchange for BASIC
bots. It does not guarantee a speedup; measure episode time and resource use.

This fits Pudge Wars' existing BASIC VM: each player already has a separate VM,
typed game host functions, 64 KiB source and 2 MiB memory limits, and a 20,000
instruction / 50,000 work-unit budget per invocation. A `.bas` upload could use
the same source as native evaluations, eliminating the current Python port.

Changing the manifest alone is insufficient. Docker and file policy kinds
cannot mix in this runtime, existing uploads are not converted, and the new
mode currently supports episodes only. Hosted human play and persistent player
workflows require platform-hosted. The game can read all submitted player files;
that visibility must be clear to entrants.

## Concrete migration work

1. Add a BASIC file loader to `coworld_host.nim`. Read the
   [seat document](https://github.com/Metta-AI/metta/blob/048a7f400ca8b5fef987dead04b152e027671a57/packages/coworld/src/coworld/docs/artifacts/PLAYER_SEATS.md)
   from `COGAME_PLAYER_SEATS_URI`, using each explicit slot and `file_uri`.
   The staged filename is simply `file`; do not infer the format from its suffix.
   Compile each file under the existing VM limits and invoke it through the same
   observation and action rules as native BASIC play.
2. Write separate private seat logs to every `log_uri`, including empty logs.
   Bound output and keep private bot prints out of public game logs. Finish
   replay and logs before writing results. Declare terminal policy errors using
   `COGAME_PLAYER_FAILURE_URI` with the failed seat index. Optional status alone
   does not assign fault. Preserve the health and global viewer routes.
3. Publish a separate manifest with `game.player_runtime: "game-hosted"` and
   bundled `player[].file` entries instead of `player[].image`. Document the
   accepted BASIC dialect, scheduling, limits and fault handling. Certify the
   complete package, including invalid files, exhausted budgets, seat isolation,
   private logs and full replayable games.
4. Start a sibling BASIC league, or arrange replacement file uploads for the
   current entrants before moving the canonical league. Compare paired seeds
   and both banks against native BASIC to catch execution-order differences.
   Measure startup, elapsed episode time and peak memory against Docker seats.

The existing rusher update therefore does not switch the shared league's runtime.
It remains usable immediately by both the 3v3 and 1v1 leagues.
