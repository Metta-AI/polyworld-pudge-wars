## Director camera: scored interests pick hooks over idle butchers.

import
  polyworld/actioncam,
  ../examples/pudge_wars/content,
  ../examples/pudge_wars/director,
  ../examples/pudge_wars/maps,
  ../examples/pudge_wars/replays,
  ../examples/pudge_wars/sim

echo "Testing director notes living butchers"
block idleRoster:
  let game = newGame(generateMap(2026), TickRate * 8, false, ReplayData())
  var cam = initActionCam()
  feedDirectorCam(cam, game.world, -1)
  doAssert cam.interestCount >= game.world.pudges.len,
    "every living butcher should be a fallback shot"

echo "Testing a flying hook outranks idle butchers"
block flyingHook:
  let game = newGame(generateMap(7), TickRate * 8, false, ReplayData())
  var cam = initActionCam()
  let thrower = game.world.pudges[0]
  game.world.hooks.add Hook(
    id: 100,
    ownerId: thrower.id,
    team: thrower.team,
    phase: HookFlying,
    position: thrower.position,
    origin: thrower.position,
    prior: thrower.position
  )
  feedDirectorCam(cam, game.world, -1)
  cam.chooseShot(0.016'f32, 1)
  doAssert cam.locked
  doAssert cam.lockId == 100, "the flying hook must win the first cut"

echo "Testing fog hides the enemy-bank shot"
block fogCuts:
  let game = newGame(generateMap(11), TickRate * 8, false, ReplayData())
  var cam = initActionCam()
  let west = game.world.pudges[0]
  doAssert west.team == WestTeam
  feedDirectorCam(cam, game.world, -1)
  let omniscient = cam.interestCount
  var westCam = initActionCam()
  feedDirectorCam(westCam, game.world, WestTeam.ord)
  doAssert westCam.interestCount > 0
  doAssert westCam.interestCount < omniscient,
    "east butchers on their bank should stay off a west director"

echo "test_pw_director: all checks passed"
