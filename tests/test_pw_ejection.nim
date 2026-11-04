## A completed reel onto a bounce tree must not teleport its visitor home.
import
  polyworld/[fixed, pathing, tapes],
  ../examples/pudge_wars/[content, maps, replays, sim]

let map = generateMap(2026)

proc blockedDumpTile(layer: int32): tuple[x, z: int] =
  for z in PlayZMin .. PlayZMax:
    for x in PlayWestMin + 2 .. PlayEastMax - 2:
      if fieldTreeTile(x, z) and not walkableTile(layer, int32(x), int32(z)) and
          walkableTile(layer, int32(x + 1), int32(z)):
        return (x, z)
  doAssert false, "fixture requires a bounce tree beside legal ground"

for (ownerIndex, victimIndex) in [(0, 3), (3, 0)]:
  let game = newGame(map, 100, false, ReplayData())
  let layer = homeLayer(game.world.pudges[ownerIndex].team)
  let tree = blockedDumpTile(layer)
  let ownerId = game.world.pudges[ownerIndex].id
  let victimId = game.world.pudges[victimIndex].id
  game.world.pudges[ownerIndex].placePudge(tree.x + 1, tree.z)
  game.world.pudges[victimIndex].placePudge(tree.x, tree.z)
  game.world.pudges[victimIndex].layer = layer
  game.world.pudges[victimIndex].hp = 900
  game.world.pudges[victimIndex].shieldTicks = 0
  game.world.pudges[victimIndex].hookedBy = ownerId
  let at = worldAtTile(tree.x, tree.z)
  game.world.hooks.add Hook(
    id: game.world.nextHookId,
    ownerId: ownerId,
    victimId: victimId,
    team: game.world.pudges[ownerIndex].team,
    phase: HookReeling,
    position: at,
    prior: at,
    origin: game.world.pudges[ownerIndex].position,
    heading: heading(-WorldScale, 0),
    range: BaseHookRange,
    speed: BaseHookSpeed,
    peakSpeed: HookSpeedMax,
    radius: BaseHookRadius,
    damage: BaseHookDamage
  )
  inc game.world.nextHookId
  tickWorld(game, proc() = discard)
  let victim = game.world.pudges[victimIndex]
  let landed = tileOf(victim.position)
  doAssert victim.hookedBy == 0, "the reel must actually finish"
  doAssert victim.layer == layer,
    "terrain correction after a foreign-bank dump must preserve that bank"
  doAssert walkableTile(layer, int32(landed.x), int32(landed.z)),
    "the visitor must land on legal terrain"
  doAssert abs(landed.x - tree.x) <= WalkSnapTiles + 1 and
      abs(landed.z - tree.z) <= WalkSnapTiles + 1,
    "correct locally instead of falling back to a distant spawn"
  doAssert victim.hp == 900, "terrain correction must not simulate a death or heal"

echo "Foreign-bank dump correction passed on both banks"
