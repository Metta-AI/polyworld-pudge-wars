## Pudge Wars map: two bank layers split by a river layer.
##
## The 128×128 grid is generated from an explicit seed using only integers.
## West and east are separate walkable layers that stop at the river.
## The river is its own walkable layer (`RiverLayer`): butchers dumped or
## blinked into the water walk there. Pathing `isWalkable` stays false on
## the bed so banks never graph-link through it; gameplay standing uses
## `tileStandable`. Walking cannot cross the waterline. Blink and hooks
## may enter and leave. This module writes `pathing.layers` once and
## returns a fingerprinted `MapData`.

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
    ## Dedicated RNG salt so pad rolls do not steal the rune stream.
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

type
  MapData* = object
    seed*: int32
    hash*: uint64

  SpawnPad* = tuple[x, z: int]
  SpawnLayout* = object
    ## Three home pads a bank. East is the X-mirror of west so neither
    ## side is a tile closer to the river; slot order is shared so
    ## opposite butchers face each other.
    west*: array[TeamSize, SpawnPad]
    east*: array[TeamSize, SpawnPad]

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
  ## WASD/arrow walk target: about 8 tiles along the pressed axes,
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
  ## Home tile for one roster slot. Slot is 0..2.
  let i = clamp(slot, 0, TeamSize - 1)
  if team == WestTeam: layout.west[i] else: layout.east[i]

proc spawnLayoutFromSeed*(seed: int32): SpawnLayout =
  ## Lane-shuffles the three Z bases, jitters inland, and mirrors east.
  ## Same seed always yields the same pads (independent of the rune RNG).
  var rng = initRng(seed, SpawnLayoutStream)
  var lanes = SpawnLaneZ
  for i in countdown(TeamSize - 1, 1):
    let j = int(rng.below(int32(i + 1)))
    swap lanes[i], lanes[j]
  var west: array[TeamSize, SpawnPad]
  var ok = false
  for _ in 0 ..< SpawnRollTries:
    for s in 0 ..< TeamSize:
      let
        x = int(rng.between(int32(SpawnWestXMin), int32(SpawnWestXMax)))
        z = clamp(
          lanes[s] + int(rng.between(int32(-SpawnZJitter), int32(SpawnZJitter))),
          PlayZMin + 4,
          PlayZMax - 4
        )
      west[s] = (x, z)
    ok = true
    for a in 0 ..< TeamSize:
      for b in a + 1 ..< TeamSize:
        let
          dx = abs(west[a].x - west[b].x)
          dz = abs(west[a].z - west[b].z)
        if max(dx, dz) < SpawnMinSep:
          ok = false
    if ok:
      break
  if not ok:
    for s in 0 ..< TeamSize:
      west[s] = (WestSpawns[s][0], lanes[s])
  result.west = west
  for s in 0 ..< TeamSize:
    result.east[s] = (mirrorSpawnX(west[s].x), west[s].z)

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

proc generateMap*(seed: int32): MapData {.measure.} =
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

  let layout = spawnLayoutFromSeed(seed)
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
  result.hash = mapFingerprint()
