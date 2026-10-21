# Pudge Wars training bridge

`examples/pudge_wars/training_host.nim` runs the hosted Nim simulation without
the WebSocket clock. It calls the same `observation` and `applyAction` functions
as the game server. The learner sees one fog-clipped butcher seat; all other
seats run the bundled `base.bas` opponent. The Python bridge adds a compact
semantic question, a 191-value numeric observation, seven action heads, and
the bundled Base Python teacher. It accepts `reset`, `encode`, `teacher`, and
`step` on newline-delimited JSON.

Build the host from the repository root after `scripts/setup.sh`:

```sh
nim c -d:release -d:headless -o:/tmp/pwtraining examples/pudge_wars/training_host.nim
```

Run the certified duel or league roster with their published tick limits:

```sh
python coworld/player/training_bridge.py /tmp/pwtraining 2 15360
python coworld/player/training_bridge.py /tmp/pwtraining 6 38400
```

Pass the Python command and its arguments to Metta's
`recipes.external.coworld_metta_rl.train` or `recipes.external.coworld.train`.
Both recipes probe the numeric codec before training. Declare the bridge, the
Nim binary, and `examples/pudge_wars/players/base.bas` as PufferLib assets.
Pass the same command through Metta post-training's repeated
`--bridge-command` options for `collect-teacher` or `collect-jev`, with
`--players 1` and `--max-decisions` matching the chosen tick limit. The
bridge returns a terminal utility from the certified kill goal or time limit.

The numeric action fields cover walking, hooking, blinking, attacks, item and
upgrade purchases, Rot, ward/wall/mine placement, pings, and halting. Spatial
targets use tile coordinates from the hosted JSON protocol. The Jev question
offers visible enemy, river, and hold choices. Bot opponents use the native
BASIC policy; they are training opponents, not a replay of hosted player pods.
