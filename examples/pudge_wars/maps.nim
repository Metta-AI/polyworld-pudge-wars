## Pudge Wars map: two bank layers split by a river layer.
##
## The 128×128 grid is generated from an explicit seed using only integers.
## West and east are separate walkable layers that stop at the river.
## The river is its own walkable layer (`RiverLayer`): butchers dumped or
## blinked into the water walk there. Pathing `isWalkable` stays false on
## the bed so banks never graph-link through it; gameplay standing uses
## `tileStandable`. Walking cannot cross the waterline. Blink and hooks
## may enter and leave. Playable banks carry seeded bounce trees, mirrored
## east and kept off spawn lanes and the shop. This module writes
## `pathing.layers` once and returns a fingerprinted `MapData`.

import
  polyworld/[hashes, noises, pathing, profiles, rngs],
  content

const
  WestLayer* = 0
  EastLayer* = 1
  RiverLayer* = 2
  WaterLayer* = 3
  TerrainAmplitudeSteps = 8'i32
  WaterLevelSteps* = -9'i32
  RiverBedSteps = -18'i32
  BankRaiseSteps = 6'i32
  RiverCenterX* = 64
    ## Tile column at the visual water / river-bed midline. Inclusive
    ## river columns are `RiverWestX` .. `RiverEastX`; pickups spawn here.
  RiverHalfWidth* = 11
  RiverWestX* = RiverCenterX - RiverHalfWidth
  RiverEastX* = RiverCenterX + RiverHalfWidth
  PlayWestMin* = 14
    ## Pulled in from 8: a slightly tighter field keeps fights nearer
    ## the river, and both banks are now exactly 39 tiles deep.
  PlayWestMax* = RiverCenterX - RiverHalfWidth - 1
  PlayEastMin* = RiverCenterX + RiverHalfWidth + 1
  PlayEastMax* = GridTiles - 14
  PlayZMin* = 16
    ## Trimmed with PlayZMax: the lanes run 96 tiles, down from 112.
  PlayZMax* = GridTiles - 17
  PlayableWidthTiles* = PlayEastMax - PlayWestMin + 1
    ## Inclusive tile span of both banks plus the river.
  PlayableDepthTiles* = PlayZMax - PlayZMin + 1
  WestBankWidthTiles* = PlayWestMax - PlayWestMin + 1
  EastBankWidthTiles* = PlayEastMax - PlayEastMin + 1
  IslandCenterX* = RiverCenterX
  IslandCenterZ* = 64
  IslandRadius* = 3
  WestShopX* = 22
    ## Shop stays on the old mid-bank pad. Spawn pads jitter around
    ## the lanes; buying and waking up are not the same tile.
  EastShopX* = 106
    ## Mirror of WestShopX across RiverCenterX (2*64 - 22).
  ShopZ* = 64
  SpawnLayoutStream = 0xC3A5E91B07F2D814'u64
    ## Dedicated RNG salt so pad rolls do not steal the match stream
    ## (contested rune scoops and hook-clash ties).
  SpawnLaneZ* = [40, 64, 88]
  SpawnWestXMin* = 18
  SpawnWestXMax* = 36
  SpawnZJitter* = 10
  SpawnMinSep* = 8
  SpawnRollTries = 64
  IslandHeightSteps* = 8'i32
  RimCliffDepth = 1
    ## One-tile rock lip facing the field: the vertical wall you see.
  RimCliffSteps = 24'i32
    ## ~3 tiles of cliff at the playable AABB. The old +8 step raise
    ## read as a cobblestone floor from the RTS camera.
  RimHillSteps = 20'i32
    ## Wooded highland behind the lip, slightly below the cliff top.
  ForestNoiseStream = 0xD1B54A32D192ED03'u64
  ForestDetailStream = 0x8CB92BA72F3D8DD7'u64
  ForestRollStream = 0x2545F4914F6CDD1D'u64
  BankNoiseStream = 0xA0761D6478BD642F'u64
  BankTreeStream = 0x6F1A9C40B3E27D85'u64
    ## Dedicated RNG salt for playable-bank bounce trees.
  BankTreesPerSide* = 8
    ## Fixed count a bank. East is the X-mirror, so the field is fair.
  BankTreeCols = 2
  BankTreeRiverMargin* = 6
    ## Keep the waterline open for dumps, lip fights, and hop-outs.
  BankTreeRimMargin = 2
  BankTreeShopClear = 5
    ## Chebyshev keepout around the shop pad.
  BankTreeLaneClear = 3
    ## Chebyshev keepout around the three spawn-lane Z rows.
  BankTreeAisleX* = 30
    ## North-south fire lane through the west bank. East mirrors it.
  BankTreeAisleClear = 1
  BankTreeMinSep = 8
  BankTreePlaceTries = 24

type
  MapData* = object
    seed*: int32
    hash*: uint64
    teamSize*: int
      ## Pads stamped onto this map. 3v3 keeps the classic three-lane
      ## roll; 4v4/5v5 stamp extra roads and so hash differently.

  SpawnPad* = tuple[x, z: int]
  SpawnLayout* = object
    ## Home pads a bank. East is the X-mirror of west so neither side
    ## is a tile closer to the river; slot order is shared so opposite
    ## butchers face each other. Length is the match N (1..5).
    west*: seq[SpawnPad]
    east*: seq[SpawnPad]

proc riverBlend(x: int): int32 =
  ## How deep inside the river band a *corner* is, 0 on the banks to 1 at
  ## the bed. Peak is the midline of tile `RiverCenterX` — halfway between
  ## corners `RiverCenterX` and `RiverCenterX + 1` — so the water sheet,
  ## river bed, fountain, and pickup spawn share one X.
  let
    span = abs(x * 2 - (RiverCenterX * 2 + 1))
    bankSpan = RiverHalfWidth * 2 + 1
    ratio = clamp(
      int32((bankSpan - span) * MapBlendScale div bankSpan),
      0'i32,
      MapBlendScale
    )
  smoothstep(ratio)

proc riverTile*(x: int): bool =
  ## Returns whether this column is the uncrossable river.
  abs(x - RiverCenterX) <= RiverHalfWidth

proc westBank*(x: int): bool =
  ## Returns whether a tile sits on the west playable bank.
  x >= PlayWestMin and x <= PlayWestMax

proc eastBank*(x: int): bool =
  ## Returns whether a tile sits on the east playable bank.
  x >= PlayEastMin and x <= PlayEastMax

proc landTile*(x: int): bool =
  ## Returns whether a column is walkable land rather than river.
  westBank(x) or eastBank(x)

proc keyboardSteerDest*(tileX, tileZ, dirX, dirZ: int): tuple[x, z: int] =
  ## WASD walk target: about 8 tiles along the pressed axes,
  ## clamped to the playable AABB. An inland press while hugging a rim
  ## aims past the wall tile so D at the west cliff is not an instant
  ## arrive on the overlapping strip.
  var
    tx = tileX + dirX * 8
    tz = tileZ + dirZ * 8
  if dirX > 0:
    tx = max(tx, PlayWestMin + 8)
  elif dirX < 0:
    tx = min(tx, PlayEastMax - 8)
  if dirZ > 0:
    tz = max(tz, PlayZMin + 8)
  elif dirZ < 0:
    tz = min(tz, PlayZMax - 8)
  if dirX != 0 and dirZ == 0:
    if tileZ <= PlayZMin:
      tz = PlayZMin + 1
    elif tileZ >= PlayZMax:
      tz = PlayZMax - 1
  if dirZ != 0 and dirX == 0:
    if tileX <= PlayWestMin:
      tx = PlayWestMin + 1
    elif tileX >= PlayEastMax:
      tx = PlayEastMax - 1
  tx = clamp(tx, PlayWestMin, PlayEastMax)
  tz = clamp(tz, PlayZMin, PlayZMax)
  if dirX > 0:
    tx = max(tx, PlayWestMin + 1)
  elif dirX < 0:
    tx = min(tx, PlayEastMax - 1)
  if dirZ > 0:
    tz = max(tz, PlayZMin + 1)
  elif dirZ < 0:
    tz = min(tz, PlayZMax - 1)
  (tx, tz)

proc homeLayer*(team: Team): int32 =
  ## Returns the bank layer that team walks on at spawn.
  if team == WestTeam: int32(WestLayer) else: int32(EastLayer)

proc homeBankX*(team: Team): int =
  ## Returns the river-edge column on this team's bank. Walk no longer
  ## auto-paths here; blink (or a hook) is how you leave the water.
  if team == WestTeam: PlayWestMax else: PlayEastMin

proc mirrorSpawnX*(westX: int): int =
  ## Reflects a west-bank column across the river midline.
  2 * RiverCenterX - westX

proc layoutPad*(layout: SpawnLayout, team: Team, slot: int): SpawnPad =
  ## Home tile for one roster slot.
  let n = layout.west.len
  if n <= 0:
    return (WestSpawns[0][0], WestSpawns[0][1])
  let i = clamp(slot, 0, n - 1)
  if team == WestTeam: layout.west[i] else: layout.east[i]

proc spreadLaneZ(n: int): seq[int] =
  ## Even Z bases along the playable strip. N=3 does not use this.
  if n <= 1:
    return @[IslandCenterZ]
  let
    lo = PlayZMin + 8
    hi = PlayZMax - 7
  result.setLen(n)
  for i in 0 ..< n:
    result[i] = lo + (hi - lo) * i div (n - 1)

proc rollWestPads(
    rng: var Rng,
    lanes: openArray[int],
    n: int
): seq[SpawnPad] =
  ## Jitter inland until teammate pads clear `SpawnMinSep`, then stop.
  result.setLen(n)
  var ok = false
  for _ in 0 ..< SpawnRollTries:
    for s in 0 ..< n:
      let
        x = int(rng.between(int32(SpawnWestXMin), int32(SpawnWestXMax)))
        z = clamp(
          lanes[s] + int(rng.between(int32(-SpawnZJitter), int32(SpawnZJitter))),
          PlayZMin + 4,
          PlayZMax - 4
        )
      result[s] = (x, z)
    ok = true
    for a in 0 ..< n:
      for b in a + 1 ..< n:
        let
          dx = abs(result[a].x - result[b].x)
          dz = abs(result[a].z - result[b].z)
        if max(dx, dz) < SpawnMinSep:
          ok = false
    if ok:
      break
  if not ok:
    for s in 0 ..< n:
      let x =
        if s < WestSpawns.len: WestSpawns[s][0]
        else: WestSpawns[0][0]
      result[s] = (x, lanes[s])

proc mirrorEast(west: seq[SpawnPad]): seq[SpawnPad] =
  result.setLen(west.len)
  for s, pad in west:
    result[s] = (mirrorSpawnX(pad.x), pad.z)

proc spawnLayoutClassic(seed: int32): SpawnLayout =
  ## Bit-identical 3-lane roll: shuffle SpawnLaneZ, jitter, mirror east.
  var rng = initRng(seed, SpawnLayoutStream)
  var lanes = SpawnLaneZ
  for i in countdown(TeamSize - 1, 1):
    let j = int(rng.below(int32(i + 1)))
    swap lanes[i], lanes[j]
  let west = rollWestPads(rng, lanes, TeamSize)
  SpawnLayout(west: west, east: west.mirrorEast)

proc spawnLayoutSpread(seed: int32, n: int): SpawnLayout =
  ## N pads along the bank. Own RNG consumption; not the 3v3 stream.
  var rng = initRng(seed, SpawnLayoutStream)
  var lanes = spreadLaneZ(n)
  for i in countdown(n - 1, 1):
    let j = int(rng.below(int32(i + 1)))
    swap lanes[i], lanes[j]
  let west = rollWestPads(rng, lanes, n)
  SpawnLayout(west: west, east: west.mirrorEast)

proc spawnLayoutFromSeed*(seed: int32, teamSize = TeamSize): SpawnLayout =
  ## Home pads for one match N. Same seed and N always yield the same
  ## pads (independent of the rune RNG). N=3 is the original shuffle.
  let n = clampTeamSize(teamSize)
  if n == TeamSize:
    spawnLayoutClassic(seed)
  else:
    spawnLayoutSpread(seed, n)

proc nearShopPad*(x, z: int): bool =
  ## True inside the shop keepout on either bank.
  max(abs(x - WestShopX), abs(z - ShopZ)) < BankTreeShopClear or
    max(abs(x - EastShopX), abs(z - ShopZ)) < BankTreeShopClear

proc onSpawnLane*(z: int): bool =
  ## True on the open east-west aisles through the three spawn rows.
  for lane in SpawnLaneZ:
    if abs(z - lane) <= BankTreeLaneClear:
      return true
  false

proc onBankAisle*(x: int): bool =
  ## True on the open north-south fire lane on either bank.
  abs(x - BankTreeAisleX) <= BankTreeAisleClear or
    abs(x - mirrorSpawnX(BankTreeAisleX)) <= BankTreeAisleClear

proc islandTile*(x, z: int): bool =
  ## Returns whether this tile is the rocky fountain in the river.
  let
    dx = x - IslandCenterX
    dz = z - IslandCenterZ
  dx * dx + dz * dz <= IslandRadius * IslandRadius

proc rimDist*(x, z: int): int =
  ## Chebyshev distance outside the playable AABB. Zero on the field.
  max(
    max(PlayWestMin - x, x - PlayEastMax),
    max(PlayZMin - z, z - PlayZMax)
  )

proc fieldTreeTile*(x, z: int): bool =
  ## True when this playable-bank tile is a bounce tree.
  if not landTile(x) or z < PlayZMin or z > PlayZMax:
    return false
  if layers.len <= EastLayer:
    return false
  let layer = if westBank(x): WestLayer else: EastLayer
  layers[layer].tiles[z * GridTiles + x].kind == TreeTile

proc hookReboundTile*(x, z: int): bool =
  ## True when a flying Meat Hook reflects here.
  ##
  ## Map edge, the fountain, and blocked land are solid. River water is
  ## open: hooks fly over it.
  if x < 0 or x >= GridTiles or z < 0 or z >= GridTiles:
    return true
  if islandTile(x, z):
    return true
  if riverTile(x):
    return false
  if x < RiverCenterX:
    not isWalkable(WestLayer, x, z)
  else:
    not isWalkable(EastLayer, x, z)

proc layerAtX*(x: int): int32 =
  ## Returns the gameplay layer that owns this world column.
  if riverTile(x):
    int32(RiverLayer)
  elif x < RiverCenterX:
    int32(WestLayer)
  else:
    int32(EastLayer)

proc mapFingerprint(): uint64 =
  ## Hashes packed terrain and walkability in stable order.
  var hash = HashySeed
  hash.addHashy(layers.len)
  for layerIndex, layer in layers:
    hash.addHashy(layer.originX)
    hash.addHashy(layer.originZ)
    hash.addHashy(layer.width)
    hash.addHashy(layer.depth)
    hash.addHashy(layer.slab)
    hash.addHashy(layer.water)
    for tileIndex, tile in layer.tiles:
      hash.addHashy(uint32(tile.flags))
      hash.addHashy(uint32(tile.kind))
      for value in tile.tops:
        hash.addHashy(value)
      for value in tile.bottoms:
        hash.addHashy(value)
      hash.addHashy(layerWalkable[layerIndex][tileIndex])
  uint64(hash)

proc emptyLayer(): QuadLayer =
  QuadLayer(
    originX: 0, originZ: 0,
    width: GridTiles, depth: GridTiles,
    slab: false,
    tiles: newSeq[Tile](GridTiles * GridTiles)
  )

proc generateMap*(seed: int32, teamSize = TeamSize): MapData {.measure.} =
  ## Builds the two banks, the river bed, water sheet, and edge woods.
  proc ground(cx, cz: int): int32 =
    let value =
      valueNoise(seed, BankNoiseStream, cx, cz, 20) * 3 +
      valueNoise(seed, 0xE7037ED1A0B428DB'u64, cx, cz, 10)
    int32(roundDivision(
      int64(value) * TerrainAmplitudeSteps,
      int64(MapBlendScale) * 4
    ))

  proc makeCorner(cx, cz: int): int32 =
    result = ground(cx, cz) + BankRaiseSteps
    result = blendHeight(result, RiverBedSteps, riverBlend(cx))

  var cornerHeights: array[(GridTiles + 1) * (GridTiles + 1), int16]
  for z in 0 .. GridTiles:
    for x in 0 .. GridTiles:
      cornerHeights[z * (GridTiles + 1) + x] = int16(makeCorner(x, z))
  template corner(cx, cz: int): int32 =
    int32(cornerHeights[(cz) * (GridTiles + 1) + (cx)])

  var
    westLayer = emptyLayer()
    eastLayer = emptyLayer()
    riverLayer = emptyLayer()
  template bankTile(layer: QuadLayer, x, z: int): var Tile =
    layer.tiles[(z) * GridTiles + (x)]

  proc stamp(layer: var QuadLayer, x, z: int, tile: Tile) =
    bankTile(layer, x, z) = tile

  var forestRng = initRng(seed, ForestRollStream)
  for z in 0 ..< GridTiles:
    for x in 0 ..< GridTiles:
      let
        tops = [
          corner(x, z), corner(x + 1, z),
          corner(x, z + 1), corner(x + 1, z + 1)
        ]
        heightSum = tops[0] + tops[1] + tops[2] + tops[3]
        kind =
          if riverTile(x): MarshTile
          elif z <= 6 or z >= GridTiles - 7: RockTile
          else: GrassTile
      var tile = Tile(
        flags: TileExists or TileConnectedEast or TileConnectedSouth,
        kind: kind,
        tops: packedHeights(tops)
      )
      let outsideField =
        not riverTile(x) and (
          x < PlayWestMin or x > PlayEastMax or
          z < PlayZMin or z > PlayZMax
        )
      if outsideField:
        # A one-tile rock lip at the field edge, then a wooded highland
        # out to the grid. Hooks still carom; the old uniform +8 rock
        # slab read as a cobblestone floor from the camera.
        let
          dist = rimDist(x, z)
          cliff = dist <= RimCliffDepth
          jagged = int32(roundDivision(
            int64(valueNoise(seed, ForestDetailStream, x, z, 6)) * 5,
            MapBlendScale
          ))
          extra =
            if cliff: RimCliffSteps + jagged
            else: RimHillSteps + jagged
        var raised: array[4, int32]
        for i in 0 .. 3:
          raised[i] = tops[i] + extra
        if cliff:
          tile.kind = RockTile
        else:
          let
            forest = int64(
              valueNoise(seed, ForestNoiseStream, x, z, 16) * 2 +
              valueNoise(seed, ForestDetailStream, x, z, 8)
            )
            roll = int64(forestRng.below(int32(MapBlendScale)))
          if forest > 0 and roll * 100 < forest * 72:
            tile.kind = TreeTile
          else:
            tile.kind = GrassTile
        tile.tops = packedHeights(raised)
        tile.impassable = true
      if riverTile(x):
        tile.impassable = true
        if islandTile(x, z):
          let
            dx = x - IslandCenterX
            dz = z - IslandCenterZ
            rise = IslandHeightSteps + 4'i32 - int32(dx * dx + dz * dz)
            raised = [
              max(tops[0], rise), max(tops[1], rise),
              max(tops[2], rise), max(tops[3], rise)
            ]
          tile.kind = StoneTile
          tile.tops = packedHeights(raised)
        stamp(riverLayer, x, z, tile)
      else:
        if heightSum < WaterLevelSteps * 4:
          tile.impassable = true
        if x < RiverCenterX:
          stamp(westLayer, x, z, tile)
        else:
          stamp(eastLayer, x, z, tile)

  let n = clampTeamSize(teamSize)
  let layout = spawnLayoutFromSeed(seed, n)
  for (sx, sz) in layout.west:
    for dz in -2 .. 2:
      for dx in -2 .. 2:
        let x = sx + dx
        let z = sz + dz
        if westBank(x) and z >= 0 and z < GridTiles:
          bankTile(westLayer, x, z).kind = RoadTile
  for (sx, sz) in layout.east:
    for dz in -2 .. 2:
      for dx in -2 .. 2:
        let x = sx + dx
        let z = sz + dz
        if eastBank(x) and z >= 0 and z < GridTiles:
          bankTile(eastLayer, x, z).kind = RoadTile

  var treeRng = initRng(seed, BankTreeStream)
  let
    xLo = PlayWestMin + BankTreeRimMargin
    xHi = PlayWestMax - BankTreeRiverMargin
    zLo = PlayZMin + BankTreeRimMargin
    zHi = PlayZMax - BankTreeRimMargin
    xSpan = max(xHi - xLo + 1, 1)
    zSpan = max(zHi - zLo + 1, 1)
  var planted: seq[SpawnPad]
  proc treeClear(x, z: int): bool =
    if bankTile(westLayer, x, z).kind == RoadTile:
      return false
    if bankTile(westLayer, x, z).impassable:
      return false
    if nearShopPad(x, z) or onSpawnLane(z) or onBankAisle(x):
      return false
    for (px, pz) in planted:
      if max(abs(px - x), abs(pz - z)) < BankTreeMinSep:
        return false
    true
  proc stampTree(x, z: int) =
    bankTile(westLayer, x, z).kind = TreeTile
    bankTile(westLayer, x, z).impassable = true
    let ex = mirrorSpawnX(x)
    if eastBank(ex):
      bankTile(eastLayer, ex, z).kind = TreeTile
      bankTile(eastLayer, ex, z).impassable = true
    planted.add (x, z)
  var row = 0
  while row < (BankTreesPerSide div BankTreeCols):
    var col = 0
    while col < BankTreeCols:
      let
        cellX0 = xLo + xSpan * col div BankTreeCols
        cellX1 = xLo + xSpan * (col + 1) div BankTreeCols - 1
        cellZ0 = zLo + zSpan * row * BankTreeCols div BankTreesPerSide
        cellZ1 = zLo + zSpan * (row + 1) * BankTreeCols div BankTreesPerSide - 1
        cellW = max(cellX1 - cellX0 + 1, 1)
        cellH = max(cellZ1 - cellZ0 + 1, 1)
      var placed = false
      for _ in 0 ..< BankTreePlaceTries:
        let
          tx = cellX0 + int(treeRng.below(int32(cellW)))
          tz = cellZ0 + int(treeRng.below(int32(cellH)))
        if westBank(tx) and tz >= zLo and tz <= zHi and treeClear(tx, tz):
          stampTree(tx, tz)
          placed = true
          break
      if not placed:
        let
          mx = (cellX0 + cellX1) div 2
          mz = (cellZ0 + cellZ1) div 2
        if westBank(mx) and mz >= zLo and mz <= zHi and treeClear(mx, mz):
          stampTree(mx, mz)
      inc col
    inc row

  var water = QuadLayer(
    originX: 0, originZ: 0,
    width: GridTiles, depth: GridTiles,
    slab: true,
    water: true,
    tiles: newSeq[Tile](GridTiles * GridTiles)
  )
  for z in 0 ..< GridTiles:
    for x in 0 ..< GridTiles:
      let tops = [
        corner(x, z), corner(x + 1, z),
        corner(x, z + 1), corner(x + 1, z + 1)
      ]
      if not islandTile(x, z) and
          tops[0] + tops[1] + tops[2] + tops[3] < WaterLevelSteps * 4:
        water.tiles[z * GridTiles + x] = Tile(
          flags: TileExists,
          tops: packedHeights([
            WaterLevelSteps, WaterLevelSteps,
            WaterLevelSteps, WaterLevelSteps
          ]),
          bottoms: packedHeights([
            WaterLevelSteps - 3, WaterLevelSteps - 3,
            WaterLevelSteps - 3, WaterLevelSteps - 3
          ])
        )

  layers = @[westLayer, eastLayer, riverLayer, water]
  computeWalkable()
  result.seed = seed
  result.teamSize = n
  result.hash = mapFingerprint()

proc generateMapMatching*(seed: int32, expectedHash: uint64): MapData =
  ## Picks the N whose stamped pads reproduce `expectedHash`. Tries 3v3
  ## first so stock tapes stay on the fast path, then 1, 2, 4, 5.
  ## Unknown hashes keep the 3v3 map (callers still hash-check).
  result = generateMap(seed, TeamSize)
  if result.hash == expectedHash:
    return
  for n in [1, 2, 4, MaxTeamSize]:
    let candidate = generateMap(seed, n)
    if candidate.hash == expectedHash:
      return candidate
