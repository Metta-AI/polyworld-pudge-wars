## Follower soak harness: joins a hosted match with the real network
## client and follows the live tape to the end, verifying every tick
## hash exactly like the graphics client. Exits non-zero on desync.
##
## Native:  nim c -d:release examples/pudge_wars/pw_follow.nim
## wasm32:  nim c -d:emscripten examples/pudge_wars/pw_follow.nim
##          (run the emitted pw_follow.js under node)
##
##   pw_follow --join ws://localhost:8000/ws --name Soak

import
  std/[os, strutils, times],
  sim, game, netclient, netpredict

when defined(emscripten):
  proc emscripten_sleep(milliseconds: cuint)
    {.importc, header: "<emscripten.h>".}
  proc idle() = emscripten_sleep(5)
else:
  proc idle() = sleep(5)

proc main() =
  if netRole != NetClient:
    echo "error: pw_follow needs --join URL"
    quit(1)
  # Optional intent-injection proof: PW_WALK="x,y" sends one walk order
  # for this seat shortly after start, so a soak can confirm netproto
  # intents actually drive the authoritative sim (not just follow it).
  let walkTarget = getEnv("PW_WALK")
  # PW_PREDICT exercises the graphics client's prediction path headlessly:
  # enable the predictor, record local walks, and rebuild every loop, so
  # a soak can prove prediction never corrupts the confirmed follow.
  let usePredict = getEnv("PW_PREDICT").len > 0
  var walkSent = false
  let startedAt = epochTime()
  while true:
    let events = netClientPump(run)
    if events.restarted:
      netClientRestart(events.setup)
    if usePredict and netClientSeat() >= 0:
      if not predictor.enabled or predictor.seat != netClientSeat():
        predictor.enable(netClientSeat(), leadFromRttMs(netPingMs() + netPingJitterMs()))
    if walkTarget.len > 0 and not walkSent and run.world.tick >= 3 and
        netClientSeat() >= 0:
      let parts = walkTarget.split(',')
      if parts.len == 2:
        let intent = HumanIntent(
          slot: int32(netClientSeat()), kind: IntentWalk,
          a: int32(parseInt(parts[0])), b: int32(parseInt(parts[1])))
        if usePredict and predictor.enabled:
          let wanted = uint32(run.world.tick) + uint32(predictor.lead)
          predictor.record(intent, wanted)
          netQueueIntent(intent, wanted)
        else:
          netQueueIntent(intent)
        walkSent = true
        echo "follow: sent walk intent to ", walkTarget
    # Advance only through ticks the host has finished and hashed,
    # mirroring the graphics loop's live-edge rule.
    while run.world.tick < int32(run.replayPlayer.data.hashes.len):
      advanceGame()
    if usePredict and predictor.enabled and not run.world.gameOver:
      predictor.lead = leadFromRttMs(netPingMs() + netPingJitterMs())
      predictor.rebuild(run)
    if run.hashCheck.mismatches > 0:
      echo "follow: DESYNC - ", run.hashCheck.error
      quit(2)
    if netClientPhase() in {NcDropped, NcDesynced}:
      echo "follow: dropped - ", netClientError()
      break
    if run.world.gameOver:
      echo "follow: game over at tick ", run.world.tick
      break
    if run.world.tick >= run.maximumTicks:
      echo "follow: time limit at tick ", run.world.tick
      break
    if epochTime() - startedAt > 900.0:
      echo "follow: timed out waiting for the match to end"
      quit(3)
    idle()
  if netClientSeat() >= 0 and netClientSeat() < run.world.pudges.len:
    let p = run.world.pudges[netClientSeat()].position
    echo "follow: seat ", netClientSeat(), " pos ", p.x, ",", p.z
  if usePredict:
    echo "follow: predict pending ", predictor.pending.len,
      " (0 = every local intent reconciled off the tape)"
  echo "follow: ticks ", run.world.tick,
    " mismatches ", run.hashCheck.mismatches,
    " hash ", run.stateHash().toHex(16)
  netShutdown()

main()
