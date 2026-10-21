# Softmax Game of the Week: human launch priorities

Prepared 2026-10-13. Launch date and invitation URL are not yet confirmed.
This is a local source/test review, not a production readiness sign-off.

The launch goal is for a teammate to join, understand the hook fight, finish
a satisfying match and choose to play again. Stronger bot self-play is secondary.

## Before inviting the team

1. **Make playing together obvious.** The homepage uses `PlayButton` with
   `tone="hero"`, which hides Invite. The FAQ nevertheless says “Invite from
   the hero.” Expose the friend-lobby action beside Play, use recognizable
   player names and rehearse joining one shared lobby from separate browsers.
2. **Make startup failures recoverable.** `components/play-button.tsx` schedules
   later `poll()` calls with `setTimeout`; their rejected promises are outside
   the initial `play()` catch. A later network/JSON failure can leave the UI
   busy indefinitely. Handle each poll failure, check HTTP responses, clear
   timers on navigation and provide retry. Pending state currently has no
   `haveHumans`/`needHumans` fields although the UI displays them; show arena
   startup progress instead of an undefined player count.
3. **Prove the actual launch path.** Use the exact invitation URL and pinned
   client/host combination. Rehearse solo play, friend joining, simultaneous
   arrivals, a full match, refresh/reconnect and a second match. Verify browser
   state hashes as well as native replays. Record cold-start time and failures.
4. **Teach only what the first fight needs.** Show movement, aiming/hooks,
   Blink escape, the kill goal and recovery. Check a first-time player can
   identify their butcher and explain what killed them. Introduce Rot,
   upgrades, ally rescue and runes after the basics are understood.
5. **Check pacing with humans.** The recent local bot study timed out in every
   tested duel. Use 3v3 as the initial playtest format and measure actual human
   match length and inactive time before choosing the launch limits. Avoid
   shipping speculative balance changes immediately before the invitation.

The website files above are in the sibling `pudge-wars-site` repository.
The BASIC league deployment workflow and the human platform-hosted package
are separate surfaces. Confirm which runtime the invitation opens before
assuming a league update changes the human game.

## Rehearsal and first-session measurements

Run a small first-time-player rehearsal before the broad invitation. Capture
join completion, time to controllable movement, time to first useful hook,
disconnect recovery, match duration and whether players voluntarily start a
second match. Ask what they thought happened when they died and which action
they wanted but could not discover. Save the replay and exact build identity
for reported problems. These are proposed measurements, not collected results.

## Local verification so far

- Browser launcher: 4/4 tests pass, including hosted/Observatory proxy paths,
  spectators and seat-zero credentials.
- Website library tests: 11/11 pass (join, lobby, live status, recap and hero).
- Native networking suite passes, including reconnect retries and exhaustion.
- Earlier gameplay study: 192 native replays verified, with zero hash mismatch
  after correcting the replay checker's duel-map reconstruction. This does
  not establish live browser or production readiness.

The source findings above are not yet browser-reproduced launch defects.
Production URL, load capacity, cold-start behavior and first-time human
playability still need verification.
