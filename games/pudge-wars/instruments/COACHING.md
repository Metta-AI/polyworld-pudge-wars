# Local coaching instruments

These validate a small BASIC policy learned from a human demonstration. They
make no hosted league or human-vs-autoresearch claims. Keep empty origins and
previous IR/code versions immutable. Record fresh development/confirmation seeds.

```sh
python3 -m coaching.symbolic.basic_coaching_ir generate ir.md policy.bas
python3 -m coaching.symbolic.basic_coaching_ir extract policy.bas recovered.ir.md
python3 -m coaching.symbolic.basic_coaching_ir generate recovered.ir.md regenerated.bas
cmp policy.bas regenerated.bas
python3 -m unittest tests/test_basic_coaching_ir.py

nim c -d:release -d:headless --hints:off --warnings:off \
  -o:tmp/coaching-match games/pudge-wars/instruments/coaching_match.nim
tmp/coaching-match /path/to/policy.bas /path/to/empty.bas 3 91015 3840 /tmp/new-coaching-match -

nim c -d:release -d:headless --hints:off --warnings:off \
  -o:tmp/coaching-replay-check games/pudge-wars/instruments/coaching_replay_check.nim
tmp/coaching-replay-check /tmp/new-coaching-match/replay.pwr
```

The match harness arguments are candidate, opponent, team size, seed, ticks,
new output directory, optional fixture (`-` for stock), optional cadence and
optional aim noise. Defaults are cadence 1, noise 0, kill goal 30. All seats are
bots. Switch candidate/opponent order to evaluate both banks. It writes native
events, engine counters, per-seat VM status, and an action/state-hash replay.
Native `.hooksLanded` is an engine counter; logger contact events can omit hooks
born and destroyed within one tick. Damage-by-cause events can combine simultaneous
hook/melee damage. Use controlled ablations and engine outcomes for causal claims.

Fixtures use `{"players":[{"slot":0,"x":40,"y":90},{"slot":1,"x":46,"y":90}]}`.
They relocate players without rewriting the map/spawn pads; these custom-start
tapes are labelled `replay_resimulatable:false`. Reproduce them with the harness
and fixture. The replay checker is for stock-start tapes from the SAME source.
Never claim a live human's performance from these all-bot runs.

`coaching_session.py` joins a preserved native event-log snapshot to a video
interval using an externally verified zero-tick anchor. Read its CLI docstring;
the helper does not guess intent, damage attribution or clock alignment.

`basic_coaching_ir` supports one policy family and rejects unknown executable
changes. Only its fenced contract is machine interpreted. Human-readable layer
definitions and rationales need agent review; arbitrary edits to prose do not
automatically alter BASIC. The code-derived IR explicitly marks intent unknown.
