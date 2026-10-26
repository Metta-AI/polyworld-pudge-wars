# hookem — Polyworld playable prototype

A Western riverbank arena with human cowboys and rope lassos. This branch is a
separate first art pass; the existing production game remains **Pudge Wars**.

The game runs in Polyworld's Nim engine, skeletal animation, terrain, particles,
and WebAssembly renderer. It retains the existing deterministic simulation,
policy API, replay schema, damage, collision, and ranked rules. Internal
`pudge_wars` identifiers remain for compatibility. The Coworld manifest publishes
to the separate `hookem` namespace; the Pudge Wars listing remains unchanged.

## Play locally

```sh
bash coworld/tools/build_replay_viewer.sh "$PWD/tmp/hookem-wasm"
python3 -m http.server 8766 --bind 127.0.0.1 --directory tmp/hookem-wasm
```

Open http://127.0.0.1:8766. Right-click to move; Q then click to lasso, E to tether,
F to sidestep, R to toggle Dust Up. The browser shell starts one human with bots.

For a self-contained Mac app:

```sh
bash examples/pudge_wars/macos/build_app.sh
open tmp/desktop/hookem.app
```

## Art and motion

- Original low-poly cowboys, team bandannas, broad hats, boots, and rope coils.
- Open snare heads with iron ferrules, tapered rope loops, and heavy
  team-wrapped iron collars; the gameplay latch radius is unchanged.
- Overhead lasso twirling with a circling wrist, an overhead throw released at
  the existing 9/32-second cast point, and a two-handed rope gathering motion.
- Cross-fades between locomotion and rope handling; interpolated attack motion.
- Full 32 TPS human pace, with measured TPS and target rate beside FPS.
- Blue-green flowing river, splash particles, dusty banks, broadleaf trees,
  perimeter fences, compact dark HUD, and new ability icons.

Generate cowboy meshes and motion with `python3 scripts/build_hookem.py`
(requires numpy and the shared `../polyworld_data` animation rig). Generated
GLBs, portraits, vector logo and icons are checked in under
`examples/pudge_wars/assets/hookem`. The source rig and existing death, melee,
and victory motions are reused; model geometry and rope-handling motions are
new. Existing ability/rune rules and some legacy effects remain in this first
pass. This is a playable prototype, not final production art or a new ranked
release.
