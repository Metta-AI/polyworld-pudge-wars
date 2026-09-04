## Pudge Wars map: seed determinism, bank layers, and the river layer.

import
  std/[sets, strformat, strutils],
  polyworld/pathing,
  ../examples/pudge_wars/content,
  ../examples/pudge_wars/maps

const SeedsUnderTest = 12'i32

echo "Testing map determinism"
block sameSeedSameMap:
  let
    first = generateMap(2026)
    second = generateMap(2026)
  doAssert first.hash == second.hash, "the same seed produced two maps"
  doAssert first.seed == 2026
  doAssert first.hash != 0, "the map fingerprint is empty"

block differentSeedsDifferentMaps:
  var seen: HashSet[uint64]
  for seed in 1'i32 .. SeedsUnderTest:
    let map = generateMap(seed)
    doAssert map.hash notin seen, &"seed {seed} collided with another map"
    seen.incl map.hash

echo "Testing two bank layers split by a river layer"
block riverAndBanks:
  let map = generateMap(2026)
  discard map
  doAssert layers.len == 4
  doAssert PlayWestMax < RiverCenterX
  doAssert PlayEastMin > RiverCenterX
  doAssert riverTile(RiverCenterX)
  doAssert riverTile(RiverCenterX - RiverHalfWidth)
  doAssert riverTile(RiverCenterX + RiverHalfWidth)
  doAssert not riverTile(PlayWestMax)
  doAssert not riverTile(PlayEastMin)
  doAssert westBank(PlayWestMax)
  doAssert eastBank(PlayEastMin)
  doAssert not westBank(RiverCenterX)
  doAssert not eastBank(RiverCenterX)
  doAssert landTile(PlayWestMax)
  doAssert landTile(PlayEastMin)
  doAssert not landTile(RiverCenterX)
  doAssert layerAtX(PlayWestMax) == int32(WestLayer)
  doAssert layerAtX(PlayEastMin) == int32(EastLayer)
  doAssert layerAtX(RiverCenterX) == int32(RiverLayer)
  doAssert homeLayer(WestTeam) == int32(WestLayer)
  doAssert homeLayer(EastTeam) == int32(EastLayer)
  doAssert homeBankX(WestTeam) == PlayWestMax
  doAssert homeBankX(EastTeam) == PlayEastMin
  doAssert layers[RiverLayer].water == false
  doAssert layers[WaterLayer].water
  for z in 0 ..< GridTiles:
    doAssert not isWalkable(WestLayer, RiverCenterX, z),
      "west walking must stop at the river"
    doAssert not isWalkable(EastLayer, RiverCenterX, z),
      "east walking must stop at the river"
    doAssert not isWalkable(RiverLayer, RiverCenterX, z),
      "pathing never graph-links the river; gameplay uses tileStandable"
    doAssert layers[RiverLayer].tiles[z * GridTiles + RiverCenterX].exists,
      "the river layer still has a bed to stand in"
  doAssert islandTile(IslandCenterX, IslandCenterZ)
  doAssert not islandTile(PlayWestMax, IslandCenterZ)
  doAssert not isWalkable(RiverLayer, IslandCenterX, IslandCenterZ)
  doAssert hookReboundTile(IslandCenterX, IslandCenterZ),
    "the fountain is a hook rebound surface"
  doAssert not hookReboundTile(RiverCenterX, 20),
    "river water is not a wall for hooks"
  doAssert hookReboundTile(-1, 64)
  doAssert hookReboundTile(GridTiles, 64)
  doAssert hookReboundTile(22, -1)
  doAssert hookReboundTile(22, GridTiles)
  doAssert layers[RiverLayer].tiles[
    IslandCenterZ * GridTiles + IslandCenterX
  ].kind == StoneTile
  doAssert not layers[WaterLayer].tiles[
    IslandCenterZ * GridTiles + IslandCenterX
  ].exists, "the fountain should sit above the water sheet"
  let layout = spawnLayoutFromSeed(2026)
  for (x, z) in layout.west:
    doAssert westBank(x)
    doAssert isWalkable(WestLayer, x, z),
      &"west spawn ({x},{z}) is not walkable"
    doAssert not isWalkable(EastLayer, x, z),
      "east must not walk the west bank"
    doAssert layers[WestLayer].tiles[z * GridTiles + x].kind == RoadTile
  for (x, z) in layout.east:
    doAssert eastBank(x)
    doAssert isWalkable(EastLayer, x, z),
      &"east spawn ({x},{z}) is not walkable"
    doAssert not isWalkable(WestLayer, x, z),
      "west must not walk the east bank"
    doAssert layers[EastLayer].tiles[z * GridTiles + x].kind == RoadTile

echo "Testing the playable AABB ratio the debug overlay prints"
block playableBounds:
  doAssert PlayableWidthTiles == PlayEastMax - PlayWestMin + 1
  doAssert PlayableDepthTiles == PlayZMax - PlayZMin + 1
  doAssert PlayableWidthTiles == 101
  doAssert PlayableDepthTiles == 96
  doAssert WestBankWidthTiles == 39
  doAssert EastBankWidthTiles == 39
  doAssert WestBankWidthTiles + EastBankWidthTiles +
    (RiverEastX - RiverWestX + 1) == PlayableWidthTiles

echo "Testing the water sheet shares the river midline"
block waterMidline:
  discard generateMap(2026)
  doAssert RiverWestX == RiverCenterX - RiverHalfWidth
  doAssert RiverEastX == RiverCenterX + RiverHalfWidth
  doAssert (RiverWestX + RiverEastX) div 2 == RiverCenterX
  doAssert riverTile(RiverWestX)
  doAssert riverTile(RiverEastX)
  doAssert not riverTile(RiverWestX - 1)
  doAssert not riverTile(RiverEastX + 1)
  const SampleZ = 20
  doAssert not islandTile(RiverCenterX, SampleZ)
  var
    waterWest = GridTiles
    waterEast = -1
  for x in RiverWestX .. RiverEastX:
    if layers[WaterLayer].tiles[SampleZ * GridTiles + x].exists:
      waterWest = min(waterWest, x)
      waterEast = max(waterEast, x)
  doAssert waterWest <= RiverCenterX, $waterWest
  doAssert waterEast >= RiverCenterX, $waterEast
  doAssert abs((waterWest + waterEast) - 2 * RiverCenterX) <= 1,
    "visual water band must be centered on RiverCenterX, got " &
      $waterWest & ".." & $waterEast
  doAssert layers[WaterLayer].tiles[SampleZ * GridTiles + RiverCenterX].exists
  doAssert IslandCenterX == RiverCenterX,
    "the fountain must sit on the same midline as the water"

echo "Testing both banks step in on X around the fountain"
block fountainLandBulge:
  discard generateMap(2026)
  doAssert RiverMidHalfWidth == RiverHalfWidth - IslandLandReach
  doAssert riverHalfWidthAt(IslandCenterZ) == RiverMidHalfWidth
  doAssert riverHalfWidthAt(20) == RiverHalfWidth
  doAssert riverHalfWidthAt(40) == RiverHalfWidth
  doAssert playWestMaxAt(IslandCenterZ) ==
    RiverCenterX - RiverMidHalfWidth - 1
  doAssert playEastMinAt(IslandCenterZ) ==
    RiverCenterX + RiverMidHalfWidth + 1
  doAssert playWestMaxAt(IslandCenterZ) > PlayWestMax
  doAssert playEastMinAt(IslandCenterZ) < PlayEastMin
  doAssert not riverTile(playWestMaxAt(IslandCenterZ), IslandCenterZ)
  doAssert westBank(playWestMaxAt(IslandCenterZ), IslandCenterZ)
  doAssert eastBank(playEastMinAt(IslandCenterZ), IslandCenterZ)
  doAssert isWalkable(
    WestLayer, playWestMaxAt(IslandCenterZ), IslandCenterZ
  ), "the west fountain bulge must be walkable bank"
  doAssert isWalkable(
    EastLayer, playEastMinAt(IslandCenterZ), IslandCenterZ
  ), "the east fountain bulge must be walkable bank"
  doAssert layerAt(playWestMaxAt(IslandCenterZ), IslandCenterZ) ==
    int32(WestLayer)
  doAssert layerAt(playEastMinAt(IslandCenterZ), IslandCenterZ) ==
    int32(EastLayer)
  doAssert riverTile(RiverWestX, 20)
  doAssert not riverTile(RiverWestX, IslandCenterZ)
  doAssert riverTile(RiverCenterX, IslandCenterZ)
  doAssert not islandTile(playWestMaxAt(IslandCenterZ), IslandCenterZ)
  let
    gap = playEastMinAt(IslandCenterZ) - playWestMaxAt(IslandCenterZ)
    waterWest = playWestMaxAt(IslandCenterZ) + 1
  doAssert gap > IslandRadius * 2,
    "a water channel must still separate the two lips"
  doAssert riverTile(waterWest, IslandCenterZ)
  doAssert not layers[WaterLayer].tiles[
    IslandCenterZ * GridTiles + playWestMaxAt(IslandCenterZ)
  ].exists, "the bulge should sit above the water sheet"
  doAssert layers[WestLayer].tiles[
    IslandCenterZ * GridTiles + playWestMaxAt(IslandCenterZ)
  ].kind == GrassTile
  doAssert layers[RiverLayer].tiles[
    IslandCenterZ * GridTiles + IslandCenterX
  ].kind == StoneTile

echo "Testing the rim is a cliff lip with woods behind it"
block rimWallsAndTrees:
  discard generateMap(2026)
  let
    westField = layers[WestLayer].tiles[64 * GridTiles + PlayWestMin]
    westLip = layers[WestLayer].tiles[64 * GridTiles + (PlayWestMin - 1)]
    westWoods = layers[WestLayer].tiles[64 * GridTiles + (PlayWestMin - 4)]
    eastLip = layers[EastLayer].tiles[64 * GridTiles + (PlayEastMax + 1)]
  doAssert isWalkable(WestLayer, PlayWestMin, 64)
  doAssert westField.kind == GrassTile or westField.kind == RoadTile
  doAssert westLip.kind == RockTile, "the field edge must be a rock lip"
  doAssert westLip.impassable
  doAssert westLip.tops[0] > westField.tops[0] + 8,
    "the cliff must rise more than the old one-tile cobblestone slab"
  doAssert hookReboundTile(PlayWestMin - 1, 64)
  doAssert eastLip.kind == RockTile
  doAssert eastLip.impassable
  doAssert westWoods.impassable
  doAssert not isWalkable(WestLayer, PlayWestMin - 4, 64)
  var trees = 0
  for z in 0 ..< GridTiles:
    for x in 0 ..< GridTiles:
      if riverTile(x):
        continue
      let layer =
        if x < RiverCenterX: WestLayer else: EastLayer
      if layers[layer].tiles[z * GridTiles + x].kind == TreeTile:
        inc trees
  doAssert trees >= 400, "the highland must carry a visible tree line"
  doAssert rimDist(PlayWestMin, 64) <= 0
  doAssert rimDist(PlayWestMin - 1, 64) == 1
  doAssert rimDist(PlayWestMin - 4, 64) == 4

echo "Testing seeded spawn layout: mirror, spacing, determinism"
block spawnLayout:
  let a = spawnLayoutFromSeed(2026)
  let b = spawnLayoutFromSeed(2026)
  doAssert a == b, "the same seed must roll the same pads"
  var seenShift = false
  for seed in 1'i32 .. 24'i32:
    let layout = spawnLayoutFromSeed(seed)
    for s in 0 ..< TeamSize:
      let
        west = layout.west[s]
        east = layout.east[s]
      doAssert west.x >= SpawnWestXMin and west.x <= SpawnWestXMax
      doAssert east.x == mirrorSpawnX(west.x)
      doAssert east.z == west.z
      doAssert westBank(west.x)
      doAssert eastBank(east.x)
      if west.x != WestSpawns[s][0] or west.z != SpawnLaneZ[s]:
        seenShift = true
    for i in 0 ..< TeamSize:
      for j in i + 1 ..< TeamSize:
        let
          dx = abs(layout.west[i].x - layout.west[j].x)
          dz = abs(layout.west[i].z - layout.west[j].z)
        doAssert max(dx, dz) >= SpawnMinSep,
          "teammate pads must stay apart"
    let other = spawnLayoutFromSeed(seed + 1)
    if other.west != layout.west:
      seenShift = true
  doAssert seenShift, "pads must move across seeds"

echo "Testing N vs N spawn: 3v3 frozen, 5v5 extra pads"
block nvnSpawn:
  let classic = spawnLayoutFromSeed(2026)
  doAssert classic == spawnLayoutFromSeed(2026, 3)
  doAssert classic.west.len == TeamSize
  let three = generateMap(2026, 3)
  doAssert generateMap(2026).hash == three.hash,
    "explicit N=3 must stamp the same roads as the default map"
  doAssert three.teamSize == TeamSize
  let five = generateMap(2026, 5)
  doAssert five.hash != three.hash, "5v5 pads must change the map hash"
  doAssert five.teamSize == 5
  let layout5 = spawnLayoutFromSeed(2026, 5)
  doAssert layout5.west.len == 5
  doAssert layout5.east.len == 5
  for i in 0 ..< 5:
    doAssert layout5.east[i].x == mirrorSpawnX(layout5.west[i].x)
    doAssert layout5.east[i].z == layout5.west[i].z
    doAssert westBank(layout5.west[i].x)
    doAssert eastBank(layout5.east[i].x)
  for i in 0 ..< 5:
    for j in i + 1 ..< 5:
      let
        dx = abs(layout5.west[i].x - layout5.west[j].x)
        dz = abs(layout5.west[i].z - layout5.west[j].z)
      doAssert max(dx, dz) >= SpawnMinSep
  let one = spawnLayoutFromSeed(2026, 1)
  doAssert one.west.len == 1
  let matched = generateMapMatching(2026, five.hash)
  doAssert matched.hash == five.hash
  doAssert matched.teamSize == 5
  let unknown = generateMapMatching(2026, 1'u64)
  doAssert unknown.teamSize == TeamSize
  doAssert unknown.hash == three.hash

echo "Testing seeded bounce trees on the playable grass"
block fieldTrees:
  discard generateMap(2026)
  var
    westTrees = 0
    eastTrees = 0
  for z in PlayZMin .. PlayZMax:
    for x in PlayWestMin .. PlayWestMax:
      if fieldTreeTile(x, z):
        inc westTrees
        doAssert hookReboundTile(x, z),
          "a field tree must rebound hooks"
        doAssert not isWalkable(WestLayer, x, z),
          "a field tree must block walking"
        doAssert not onSpawnLane(z)
        doAssert not onBankAisle(x)
        doAssert not nearShopPad(x, z)
        doAssert abs(x - PlayWestMax) >= BankTreeRiverMargin
        let ex = mirrorSpawnX(x)
        doAssert fieldTreeTile(ex, z),
          "east must mirror each west bounce tree"
    for x in PlayEastMin .. PlayEastMax:
      if fieldTreeTile(x, z):
        inc eastTrees
  doAssert westTrees == eastTrees
  doAssert westTrees >= BankTreesPerSide - 2,
    "each bank needs a full set of bounce trees"
  doAssert westTrees <= BankTreesPerSide
  let again = generateMap(2026)
  discard again
  var westAgain = 0
  for z in PlayZMin .. PlayZMax:
    for x in PlayWestMin .. PlayWestMax:
      if fieldTreeTile(x, z):
        inc westAgain
  doAssert westAgain == westTrees, "the same seed must plant the same trees"
  doAssert generateMap(7).hash != generateMap(2026).hash

echo "test_pw_maps: all checks passed"
let sample = generateMap(2026)
echo "  seed 2026 mapHash = ", toHex(sample.hash)
