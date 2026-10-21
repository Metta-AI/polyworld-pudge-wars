# Coaching review — session 2026-09-15t21-41-17-535zc09870

## Captured inputs versus repository baseline

Both `input.ir.md` and `input.policy.txt` have zero bytes and SHA-256
`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.
`session.json` identifies **Blank policy**, commit
`559a80429f68bbf01df0ace9e45745d4fffb1276`, and explicitly says execution is
unverified. There is no captured behavior to diff against v14 and no basis for
attributing the recorded play to the repository policy.

At loop start, `coworld/player/base.py` matches both existing frozen v14 oracles
byte for byte: `b848fa26c978ff1553ef91a00ddc1f85af32b5b2bfd4c67bd983f74cf66232b6`.
This is the chosen evaluation baseline with healing and spacing enabled.
Existing uncommitted work and the separate E03 confirmation are recorded in
`session-reference.json`; this loop does not incorporate that candidate.

The recorder inputs, notes, media and synthesis remain untouched. Their hashes
are recorded in `session-reference.json`. No written feedback was supplied.
The transcript and model synthesis are marked unreviewed by their producers.

## Intent, observations and implementation hypotheses

| Suggestion | Human intent and source | Checked observation | Implementation decision |
| --- | --- | --- | --- |
| Hook an ally/enemy engagement | Speech-33, 03:00–03:13; speech-37/38, 03:33–03:49: either ally healing or enemy damage can be useful. | Frame 223s shows multiple overlapping chains; pixels do not establish exact hit selection or healing. | E04 tests a **pair midpoint** after urgent priorities, with an injured ally, measured melee proximity and other-friendly collision checks. Midpoint, thresholds and ordering are our explicit hypotheses. No guaranteed positive outcome is claimed. |
| CurveHook | Speech-51/52, 05:51–05:58 describes repositioning as the hook returns. | Frames 354s/355s show changed player/chain arrangements; 358s shows close combat. Captured input includes changes among W/A/S/D and multiple casts; the camera and coordinates prevent inferring one constant world-perpendicular maneuver. | Correct the skill description to conditional return steering. Keep it inactive: unconditional movement from cast to completion is unsupported. Prior E02 already failed its fixed screen. |
| Middle fountain | Speech-56/57, 06:45–06:53 reports unintended bounces. | Frames 408s/410s show chains near the obstacle and a death/respawn sequence; these sampled frames alone do not isolate a bounce or establish precise geometry. | Ground the predicate in the native collision code. E05 tests a straight-segment guard for non-support throws; deliberate support requests remain exempt. |
| DualUtilityOutcome | Repeated ally-saving intent in speech-11/13/43 and two useful contacts in speech-38. | The intent is intelligible without inferring reward magnitudes from the video. | Refine the existing cooperation goal; do not invent reward weights or treat healing as a guaranteed win benefit. |

Read the evidence directly:

- [Session notes](</Users/aaln/Documents/Policy Loops/sessions/2026-09-15t21-41-17-535zc09870/notes.md>)
- [Manifest](</Users/aaln/Documents/Policy Loops/sessions/2026-09-15t21-41-17-535zc09870/session.json>)
- [Recording](</Users/aaln/Documents/Policy Loops/sessions/2026-09-15t21-41-17-535zc09870/recording.webm>)
- [Unreviewed synthesis](</Users/aaln/Documents/Policy Loops/sessions/2026-09-15t21-41-17-535zc09870/synthesis/13d8b670-9bb1-4792-a560-dbc7d7231a7d/report.md>)
- [Extracted input events, 348–359 seconds](curve-input-evidence.json)

## Engine grounding and limits

`maps.nim` places the central tile at `(64,64)` and defines `IslandRadius=3`.
`sim.nim:worldAtTile` adds a half-tile center offset; `coworld_host.nim` converts
world position to policy coordinates. Consequently the disk center is
**(64.5,64.5)**. `islandHookRadius` adds another half-tile to the tile radius,
giving **3.5**. The hook head collides with this disk; the separate unit-contact
radius is not added. The initial approximate-center compilation is archived and
excluded from scored results. This distinction required changing both the IR
and symbolic implementation.

The old predicted-enemy shot uses a conservative 5-tile filter around `(64,64)`.
E05 retains that existing rule while adding the correct disk test to the other
non-support throw attempts. Its segment ends at hook reach, starts at a pending
Blink destination if present, and does not claim general obstacle navigation.
The public observation rounds coordinates to .001 tiles, so this remains a
geometric model from observed positions, not exact access to hidden fixed-point
engine state. Already selected Blink requests can be rejected by the host.

`sim.nim:advanceReel` first retraces retained bounce waypoints, then moves toward
the owner's current landing point. This supports conditional return steering,
not unconditional control of the outbound hook heading. The existing full native
simulation tests include head-on and glancing fountain bounces and were run for
this loop. Video time is not simulation time. We do not infer unobservable
enemy coordinates or accepted actions from captured key presses.

## Prior return-steering evidence

E02: 24 games, seeds 916001–916012, 13 wins, mean margin +0.667, 95% seed-block
interval [-0.292, 1.792]. Only 24 movement decisions changed among 1,289,028.
This rejects that candidate's retention gate, not all possible CurveHook
skills. A future test needs materially different exposure and measured return
contacts. Re-running the same skill would spend games without a new hypothesis.
