## Fog of war: team sight from a butcher id (replay spectator POV).

import
  polyworld/pathing,
  ../examples/pudge_wars/[content, fog, maps, replays, sim]

let map = generateMap(2026)

proc freshGame(): Game =
  newGame(map, TickRate * 30, false, ReplayData())

echo "Testing fogTeamOf from a butcher id"
block:
  let game = freshGame()
  let west = game.world.pudges[0]
  let east = game.world.pudges[3]
  doAssert west.team == WestTeam
  doAssert east.team == EastTeam
  doAssert fogTeamOf(game.world, west.id) == WestTeam.ord
  doAssert fogTeamOf(game.world, east.id) == EastTeam.ord
  doAssert fogTeamOf(game.world, 0) == -1
  doAssert fogTeamOf(game.world, 99_999) == -1

echo "Testing omniscient team sees the whole map"
block:
  let game = freshGame()
  doAssert fogCanSeeTeam(game.world, -1, worldAtTile(22, 64))
  doAssert fogCanSeeTeam(game.world, -1, worldAtTile(105, 64))
  doAssert fogCanSeeTeam(game.world, -1, worldAtTile(RiverCenterX, 64))

echo "Testing home bank and river stay lit without crossing"
block:
  let game = freshGame()
  let westTeam = fogTeamOf(game.world, game.world.pudges[0].id)
  doAssert fogCanSeeTeam(game.world, westTeam, worldAtTile(22, 64)),
    "own spawn pad must stay lit"
  doAssert fogCanSeeTeam(game.world, westTeam, worldAtTile(PlayWestMax, 64)),
    "the whole home bank stays lit"
  doAssert fogCanSeeTeam(
    game.world, westTeam, worldAtTile(playWestMaxAt(IslandCenterZ), 64)
  ), "the west fountain bulge is home bank"
  doAssert fogCanSeeTeam(game.world, westTeam, worldAtTile(RiverCenterX, 64)),
    "the river is always terrain-visible"
  doAssert not fogCanSeeTeam(
    game.world, westTeam, worldAtTile(playEastMinAt(IslandCenterZ), 64)
  ), "the east fountain bulge stays dark"
  doAssert not fogCanSeeTeam(game.world, westTeam, worldAtTile(105, 64)),
    "the far enemy fountain is dark until a teammate carries sight"

echo "Testing a living teammate scouts the enemy bank"
block:
  let game = freshGame()
  let westId = game.world.pudges[0].id
  let westTeam = fogTeamOf(game.world, westId)
  game.world.pudges[0].placePudge(90, 64)
  doAssert fogCanSeeTeam(game.world, westTeam, worldAtTile(105, 64)),
    "a butcher 15 tiles from the east fountain should light it"
  game.world.pudges[0].state = Dying
  doAssert not fogCanSeeTeam(game.world, westTeam, worldAtTile(105, 64)),
    "a dying butcher must stop scouting"

echo "Testing fogShownPudgeTeam hides enemies in the dark"
block:
  let game = freshGame()
  let westTeam = fogTeamOf(game.world, game.world.pudges[0].id)
  doAssert fogShownPudgeTeam(game.world, westTeam, game.world.pudges[0])
  doAssert not fogShownPudgeTeam(game.world, westTeam, game.world.pudges[3])
  doAssert fogShownPudgeTeam(game.world, -1, game.world.pudges[3])

proc hasScriptObject(world: World, viewer, targetId: int32): bool =
  var value: WorldObject
  for i in 0 ..< worldObjectCount(world, viewer):
    if worldObjectAt(world, viewer, i, value) and value.id == targetId:
      return true
  false

echo "Testing worldObjectCount matches renderer fog"
block:
  let game = freshGame()
  let
    west = game.world.pudges[0].id
    east = game.world.pudges[3].id
  game.world.pudges[0].placePudge(22, 64)
  game.world.pudges[1].placePudge(22, 40)
  game.world.pudges[2].placePudge(22, 88)
  game.world.pudges[3].placePudge(105, 64)
  game.world.pudges[4].placePudge(105, 40)
  game.world.pudges[5].placePudge(105, 88)
  doAssert hasScriptObject(game.world, west, west)
  doAssert hasScriptObject(game.world, west, game.world.pudges[1].id)
  doAssert not hasScriptObject(game.world, west, east),
    "scripts must not see an enemy on the far bank"
  doAssert not hasScriptObject(game.world, east, west)
  game.world.pudges[0].placePudge(90, 64)
  doAssert hasScriptObject(game.world, west, east),
    "a living teammate on the far bank must share sight with scripts"
  game.world.pudges[3].placePudge(RiverCenterX, 40)
  doAssert hasScriptObject(game.world, west, east),
    "an enemy in the river is always visible"

echo "Testing worldObjectCount hides far-bank walls"
block:
  let game = freshGame()
  let west = game.world.pudges[0].id
  game.world.pudges[0].placePudge(22, 64)
  game.world.pudges[3].placePudge(105, 64)
  game.world.props.add Prop(
    id: game.world.nextPropId,
    kind: PropWall,
    ownerId: game.world.pudges[3].id,
    team: EastTeam,
    tileX: 100,
    tileZ: 64,
    hp: 120,
    maxHp: 120,
    ticksLeft: 100,
    alive: true
  )
  inc game.world.nextPropId
  let wallId = game.world.props[^1].id
  doAssert not hasScriptObject(game.world, west, wallId),
    "an enemy palisade in the dark must not leak through object queries"
  game.world.pudges[0].placePudge(90, 64)
  doAssert hasScriptObject(game.world, west, wallId),
    "shared sight must reveal the same wall a human would see"

echo "Testing a team ward scouts the enemy bank"
block:
  let game = freshGame()
  let
    west = game.world.pudges[0].id
    westTeam = fogTeamOf(game.world, west)
    east = game.world.pudges[3].id
  game.world.pudges[0].placePudge(22, 64)
  game.world.pudges[3].placePudge(105, 64)
  doAssert not fogCanSeeTeam(game.world, westTeam, worldAtTile(105, 64))
  game.world.props.add Prop(
    id: game.world.nextPropId,
    kind: PropWard,
    ownerId: west,
    team: WestTeam,
    tileX: 100,
    tileZ: 64,
    hp: 1,
    maxHp: 1,
    ticksLeft: WardDurationTicks,
    alive: true
  )
  inc game.world.nextPropId
  let wardId = game.world.props[^1].id
  doAssert fogCanSeeTeam(game.world, westTeam, worldAtTile(105, 64)),
    "a living ward must light tiles around its stake"
  doAssert fogShownPudgeTeam(game.world, westTeam, game.world.pudges[3]),
    "an enemy standing on the ward must come out of the fog"
  doAssert hasScriptObject(game.world, west, east),
    "scripts must share the ward's sight"
  doAssert hasScriptObject(game.world, west, wardId),
    "the planting team always sees its own ward"
  doAssert not hasScriptObject(game.world, east, wardId),
    "the other team must not see a hidden ward"
  game.world.props[^1].alive = false
  doAssert not fogCanSeeTeam(game.world, westTeam, worldAtTile(105, 64)),
    "a dead ward must stop scouting"

proc addTestHook(
    world: World,
    owner: Pudge,
    tileX, tileZ: int,
    phase = HookFlying
) =
  world.hooks.add Hook(
    id: world.nextHookId,
    ownerId: owner.id,
    team: owner.team,
    phase: phase,
    position: worldAtTile(tileX, tileZ),
    origin: worldAtTile(tileX, tileZ),
    prior: worldAtTile(tileX, tileZ),
    heading: heading(-WorldScale, 0),
    range: BaseHookRange,
    speed: BaseHookSpeed,
    peakSpeed: BaseHookSpeed,
    radius: BaseHookRadius,
    damage: BaseHookDamage
  )
  inc world.nextHookId

echo "Testing worldHookCount hides a hook in the dark"
block:
  let game = freshGame()
  let west = game.world.pudges[0].id
  game.world.pudges[0].placePudge(22, 64)
  game.world.pudges[3].placePudge(105, 64)
  addTestHook(game.world, game.world.pudges[3], 105, 64)
  doAssert worldHookCount(game.world, west) == 0,
    "a hook head on the far bank is in the fog"
  game.world.hooks[^1].position = worldAtTile(RiverCenterX, 64)
  doAssert worldHookCount(game.world, west) == 1,
    "the same hook becomes visible once its head enters the river"

echo "Testing a flying hook scouts the enemy bank"
block:
  let game = freshGame()
  let westTeam = fogTeamOf(game.world, game.world.pudges[0].id)
  game.world.pudges[0].placePudge(22, 64)
  game.world.pudges[3].placePudge(105, 64)
  doAssert not fogCanSeeTeam(game.world, westTeam, worldAtTile(105, 64))
  addTestHook(game.world, game.world.pudges[0], 105, 64)
  doAssert fogCanSeeTeam(game.world, westTeam, worldAtTile(105, 64)),
    "an in-flight hook must light tiles on its chain"
  doAssert fogShownPudgeTeam(game.world, westTeam, game.world.pudges[3]),
    "an enemy standing on the hook head must come out of the fog"
  doAssert hasScriptObject(game.world, game.world.pudges[0].id, game.world.pudges[3].id),
    "scripts must share the hook's sight"

echo "Testing a hook lights a padded line, not a disk"
block:
  let game = freshGame()
  let westTeam = fogTeamOf(game.world, game.world.pudges[0].id)
  game.world.pudges[0].placePudge(22, 64)
  addTestHook(game.world, game.world.pudges[0], 90, 64)
  let pad = int(HookSightPadTiles)
  doAssert fogCanSeeTeam(game.world, westTeam, worldAtTile(90, 64)),
    "the head sits on the corridor"
  doAssert fogCanSeeTeam(game.world, westTeam, worldAtTile(80, 64)),
    "tiles already swept behind the head stay lit"
  doAssert fogCanSeeTeam(game.world, westTeam, worldAtTile(90, 64 + pad)),
    "padding off the chain stays lit"
  doAssert fogCanSeeTeam(game.world, westTeam, worldAtTile(90 + pad, 64)),
    "the corridor must continue past the head along the throw"
  doAssert not fogCanSeeTeam(game.world, westTeam, worldAtTile(105, 64)),
    "tiles well past the look-ahead must stay fogged"
  doAssert not fogCanSeeTeam(game.world, westTeam, worldAtTile(90, 64 + pad + 2)),
    "a butcher-disk offset off the chain must stay dark"

echo "Testing a bounced hook follows both segments"
block:
  let game = freshGame()
  let westTeam = fogTeamOf(game.world, game.world.pudges[0].id)
  game.world.pudges[0].placePudge(22, 64)
  addTestHook(game.world, game.world.pudges[0], 90, 50)
  game.world.hooks[^1].bounces.add worldAtTile(90, 40)
  doAssert fogCanSeeTeam(game.world, westTeam, worldAtTile(90, 40)),
    "the bounce pin sits on the corridor"
  doAssert fogCanSeeTeam(game.world, westTeam, worldAtTile(90, 45)),
    "the outbound stub after the bounce stays lit"
  doAssert not fogCanSeeTeam(game.world, westTeam, worldAtTile(105, 40)),
    "a disk around the bounce must not light the far fountain lane"

echo "Testing an idle hook does not scout"
block:
  let game = freshGame()
  let westTeam = fogTeamOf(game.world, game.world.pudges[0].id)
  game.world.pudges[0].placePudge(22, 64)
  addTestHook(game.world, game.world.pudges[0], 105, 64, HookIdle)
  doAssert not fogCanSeeTeam(game.world, westTeam, worldAtTile(105, 64)),
    "a hook still in the hand must not light the far bank"

echo "Testing a reeling hook still scouts"
block:
  let game = freshGame()
  let westTeam = fogTeamOf(game.world, game.world.pudges[0].id)
  game.world.pudges[0].placePudge(22, 64)
  addTestHook(game.world, game.world.pudges[0], 105, 40, HookReeling)
  doAssert fogCanSeeTeam(game.world, westTeam, worldAtTile(105, 40)),
    "a reeling hook must keep lighting its chain"

echo "Testing a dying butcher's hook still scouts"
block:
  let game = freshGame()
  let westTeam = fogTeamOf(game.world, game.world.pudges[0].id)
  game.world.pudges[0].placePudge(22, 64)
  game.world.pudges[0].state = Dying
  addTestHook(game.world, game.world.pudges[0], 105, 64)
  doAssert fogCanSeeTeam(game.world, westTeam, worldAtTile(105, 64)),
    "a chain already in the air must keep scouting after the thrower dies"

echo "Testing a lightning fire trail lights the owning team"
block:
  let game = freshGame()
  let
    west = game.world.pudges[0].id
    westTeam = fogTeamOf(game.world, west)
    eastTeam = fogTeamOf(game.world, game.world.pudges[3].id)
    far = worldAtTile(90, 64)
    home = worldAtTile(40, 64)
  game.world.pudges[0].placePudge(22, 64)
  game.world.pudges[1].placePudge(22, 40)
  game.world.pudges[2].placePudge(22, 88)
  game.world.pudges[3].placePudge(90, 64)
  game.world.pudges[4].placePudge(105, 40)
  game.world.pudges[5].placePudge(105, 88)
  doAssert not fogCanSeeTeam(game.world, westTeam, far),
    "the far bank stays dark until the trail is painted"
  doAssert not fogShownPudgeTeam(game.world, westTeam, game.world.pudges[3])
  game.world.firePatches.add FirePatch(
    ownerId: west,
    team: WestTeam,
    position: far,
    ticksLeft: RuneLightningTrailDurationTicks
  )
  game.world.firePatches.add FirePatch(
    ownerId: west,
    team: WestTeam,
    position: home,
    ticksLeft: RuneLightningTrailDurationTicks
  )
  doAssert fogCanSeeTeam(game.world, westTeam, far),
    "the painting team must see along its fire trail"
  doAssert fogCanSeeTeam(game.world, westTeam, worldAtTile(90, 66)),
    "the trail lights neighboring tiles inside the burn radius"
  doAssert not fogCanSeeTeam(game.world, westTeam, worldAtTile(90, 67)),
    "tiles outside the burn radius stay dark"
  doAssert fogShownPudgeTeam(game.world, westTeam, game.world.pudges[3]),
    "an enemy standing on the trail must show"
  doAssert hasScriptObject(game.world, west, game.world.pudges[3].id),
    "BASIC observations must see an enemy on the trail"
  doAssert not fogCanSeeTeam(game.world, eastTeam, home),
    "the other team must not see through an enemy fire trail"
  var mask: seq[uint8]
  fillTeamVision(game.world, westTeam, mask)
  doAssert mask[64 * GridTiles + 90] == 255
  doAssert mask[67 * GridTiles + 90] == 0
  fillTeamVision(game.world, eastTeam, mask)
  doAssert mask[64 * GridTiles + 40] == 0,
    "stamp must not light the other team through an enemy trail"

echo "Testing fillTeamVision matches per-tile fogCanSeeTeam"
block:
  let game = freshGame()
  game.world.pudges[0].placePudge(90, 64)
  addTestHook(game.world, game.world.pudges[0], 105, 40)
  game.world.hooks[^1].bounces.add worldAtTile(100, 40)
  game.world.firePatches.add FirePatch(
    ownerId: game.world.pudges[0].id,
    team: WestTeam,
    position: worldAtTile(90, 80),
    ticksLeft: RuneLightningTrailDurationTicks
  )
  var mask: seq[uint8]
  fillTeamVision(game.world, WestTeam.ord, mask)
  doAssert mask.len == GridTiles * GridTiles
  for z in 0 ..< GridTiles:
    for x in 0 ..< GridTiles:
      let lit = fogCanSeeTeam(game.world, WestTeam.ord, worldAtTile(x, z))
      doAssert (mask[z * GridTiles + x] == 255) == lit,
        "stamp/scan disagree at " & $x & "," & $z
  fillTeamVision(game.world, -1, mask)
  for value in mask:
    doAssert value == 255

echo "test_pw_fog: all checks passed"
