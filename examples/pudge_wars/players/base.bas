' Pudge Wars base butcher — the baseline all-rounder every seat
' falls back to. Velocity-led hooks, committed dodges, brawls only
' with an HP edge, pad healing, and team play: rescue hooked or
' swimming allies (ally hooks heal), finish any catch, hold spread
' lanes. Against a hook-cutter it holds a standoff outside the
' cutter's poke range and throws in punish windows.
'
' Evolved via headless self-play (see spar.sh / duel_loop.md):
' vs the old base 20-0, vs challenger 18-2, vs the denier even,
' sweeps aggressive/sniper/patient/support.
'
' Other policies in this folder:
'   aggressive.bas  push and brawl (damage/speed)
'   support.bas     rescues and denies (distance/radius)
'   sniper.bas      long-range wounded targets only
'   denier.bas      hook intercept specialist
'   patient.bas     safe kills, banks upgrade points
'
' Flash: dodge on the home bank then hook the same tick; stretch inland;
' dump-chase is the only hop that lands in water. Far-bank ghosts keep
' last velocity and climb the far lip — fog pokes aim at that lane, not
' a cold inland column. Shop: Longflight then Treads, then Big Hook,
' palisade on the river lip, mines in the fog brush.
'
' Host data:
'   selfId, selfTeam, selfX, selfY, selfHp, selfMaxHp
'   selfKills, selfPoints, selfGold, selfInShop, selfLayer, selfHooked
'   selfBuff (0 none, else rune kind + 1), selfRot (1 if our Rot is on)
'   hookReady, blinkReady, worldTick, riverWest, riverEast
'     (side-lane lips 52/76; mid fountain land sits closer)
'   homeX, homeY  (this butcher's spawn pad; retreat here)
'   runeSoon (ticks until the next river drop; 0 if runes are off)
'   runeNextKind, runeNextX, runeNextY  (the coming drop; -1 if off)
'
' Objects are fog-clipped like the human view:
'   objectId, objectTeam, objectX, objectY, objectHp, objectAlive
'   objectLayer, objectHooked, objectShielded, objectRot
'   objectKind: 1 butcher, else a gadget (wall/mine/ward)
' Own team always shows. Enemies and walls only inside shared sight
' (home bank, river, 20 tiles of a living teammate or team ward, or
' the padded corridor along an in-flight team hook). Enemy mines and
' wards stay hidden.
' Layers: 0 west bank, 1 east bank, 2 river
'
' Flying hooks (both teams; filter with hookTeam / hookOwner):
'   hookCount, hookTeam, hookX, hookY, hookFlying, hookVictim, hookOwner
' Hook heads in the fog are omitted, same as the renderer.
'
' River runes (hook one to steal its power):
'   runeCount, runeX(i), runeY(i), runeKind(i)
'   runeSoon, runeNextKind, runeNextX, runeNextY
' Rune kinds: 0 haste, 1 double damage, 2 regen, 3 big hook,
'   4 lightning, 5 bounty (instant gold; does not replace a buff)
' Drops are a public clock, not RNG: first at 0:20, then every 20 s.
' Even drops spawn north (y=16) and drift south; odd spawn south
' (y=111). Each kind visits both ends before the next: haste N/S,
' then double damage, regen, big hook, lightning, bounty. Time the
' spawn; gank anyone camping it. Runes live in the river, so they
' stay visible.
'
' Actions return 1 when accepted:
'   walkTo(x, y), hookTo(x, y), blinkTo(x, y), rotToggle(), attackTarget(id)
'   buyUpgrade(kind), buyPower(id), itemRank(kind), upgradeLevel(kind)
'   placeWall(x, y), placeMine(x, y), placeWard(x, y), halt(), ping(x, y)
' Rot is a toggle: 8-tile blight, 48 DPS including self, 40% slow,
' and nobody in a cloud can blink. Turn it on to finish a melee;
' turn it off and walk inland when someone else is rotting you.
' Upgrade kinds: 0 damage, 1 distance, 2 speed, 3 radius
' Spend every kill point the same tick; throw range and lead scale
' with upgradeLevel after the buy. Shop (own pad, gold): 0 flask,
' 1 haste, 2 regen, 3 big hook, 4 2x, 5 river treads, 6 longflight
' brand, 7 palisade, 8 hooktrap, 9 farwatch ward. Permanents occupy 5
' inventory slots and rank to 5 — keep buying the same family.
' C/V/B place wall/mine/ward. Wards last 45 s and light fog.
'
' print lines are captured for logs. They are not shown in the world;
' nameplates use the bot's script name. Print on changes, not every tick.

' ---- tunables -------------------------------------------------------
engageDist = 34      ' max tiles to attempt a lead hook
leadDiv = 9          ' aim lead divisor (drift/8t * span / leadDiv)
holdBack = 4         ' tiles back from the waterline in 1v1
jukeAmp = 3          ' juke amplitude in tiles
dodgeDist = 22       ' react to enemy hooks inside this range
retreatPct = 40      ' pad-heal below this percent of max HP
brawlMargin = 40     ' melee only if selfHp + margin >= enemy hp
runeDist = 26        ' hook runes inside this range when idle
runeSoonWalk = 256   ' walk to the next drop inside this many ticks (~8s)
runeCampDist = 14    ' hook enemies camping the next drop inside this
cutDist = 30         ' cut victim-carrying enemy hooks inside this
blinkHop = 16        ' perpendicular dodge hop, tiles (20-tile blink)
fogPoke = 8          ' tiles into the far bank when nobody is visible
' ---------------------------------------------------------------------

' ---- scan objects ---------------------------------------------------
bestIdx = -1
bestD2 = 2147483647
headIdx = -1
headD2 = 2147483647
swimIdx = -1
swimD2 = 2147483647
saveIdx = -1
saveD2 = 2147483647
closeIdx = -1
closeD2 = 2147483647
campIdx = -1
campD2 = 2147483647
allyX = homeX
allyY = homeY
preyRot = 0
foreignRot = 0
rotX = 0
rotY = 0
laneAllies = 0
laneRank = 0
index = 0
while index < objectCount()
  if objectTeam(index) = selfTeam then
    if objectAlive(index) = 1 then
      laneAllies = laneAllies + 1
      if objectId(index) < selfId then
        laneRank = laneRank + 1
      end if
    end if
    if objectId(index) <> selfId and objectAlive(index) = 1 then
      allyX = objectX(index)
      allyY = objectY(index)
      adx = objectX(index) - selfX
      ady = objectY(index) - selfY
      ad2 = adx * adx + ady * ady
      if objectRot(index) = 1 then
        if ad2 <= 64 then
          foreignRot = 1
          rotX = objectX(index)
          rotY = objectY(index)
        end if
      end if
      if objectHooked(index) = 1 or objectLayer(index) = 2 then
        if ad2 < saveD2 then
          saveD2 = ad2
          saveIdx = index
        end if
      end if
    end if
  else
    if objectAlive(index) = 1 then
      odx = objectX(index) - selfX
      ody = objectY(index) - selfY
      od2 = odx * odx + ody * ody
      if od2 < bestD2 then
        bestD2 = od2
        bestIdx = index
      end if
      if objectHooked(index) = 1 and od2 < headD2 then
        headD2 = od2
        headIdx = index
      end if
      if objectLayer(index) = 2 and od2 < swimD2 then
        swimD2 = od2
        swimIdx = index
      end if
      if od2 <= 30 and od2 < closeD2 then
        closeD2 = od2
        closeIdx = index
      end if
      if runeSoon > 0 then
        if runeSoon <= runeSoonWalk then
          cdx = objectX(index) - runeNextX
          cdy = objectY(index) - runeNextY
          if cdx < 0 then
            cdx = 0 - cdx
          end if
          if cdy < 0 then
            cdy = 0 - cdy
          end if
          if cdx <= runeCampDist then
            if cdy <= runeCampDist then
              cd2 = cdx * cdx + cdy * cdy
              if cd2 < campD2 then
                campD2 = cd2
                campIdx = index
              end if
            end if
          end if
        end if
      end if
      if objectKind(index) = 1 and od2 <= 64 then
        preyRot = 1
        if objectRot(index) = 1 then
          foreignRot = 1
          rotX = objectX(index)
          rotY = objectY(index)
        end if
      end if
    end if
  end if
  index = index + 1
wend

enemyAlive = 0
ex = 0
ey = 0
ehp = 0
eid = 0
eshield = 0
if bestIdx >= 0 then
  enemyAlive = 1
  ex = objectX(bestIdx)
  ey = objectY(bestIdx)
  ehp = objectHp(bestIdx)
  eid = objectId(bestIdx)
  eshield = objectShielded(bestIdx)
  lastEx = ex
  lastEy = ey
  lastSeen = worldTick
  lastLayer = objectLayer(bestIdx)
end if

' ---- velocity of the tracked enemy (8-tick samples) -----------------
' Keep the last sample when they vanish: a fogged butcher is on the
' far bank (home bank and river stay lit), so dead-reckon from here.
if enemyAlive = 1 then
  if eid <> velId then
    velId = eid
    velTick = 0
    evx = 0
    evy = 0
  end if
  if worldTick - velTick >= 8 then
    if velTick > 0 then
      evx = ex - pex
      evy = ey - pey
    end if
    pex = ex
    pey = ey
    velTick = worldTick
  end if
end if

dx = ex - selfX
if dx < 0 then
  dx = 0 - dx
end if
dy = ey - selfY
if dy < 0 then
  dy = 0 - dy
end if

' ---- island line of sight -------------------------------------------
' Perpendicular distance from the throw line to the fountain (64,64):
' a blocked throw bounces off the rocks and always misses.
losClear = 1
if enemyAlive = 1 then
  ldx = ex - selfX
  ldy = ey - selfY
  len2 = ldx * ldx + ldy * ldy
  icx = 64 - selfX
  icy = 64 - selfY
  t = icx * ldx + icy * ldy
  if t > 0 and t < len2 then
    cross = icy * ldx - icx * ldy
    if cross < 0 then
      cross = 0 - cross
    end if
    if cross * cross <= 25 * len2 then
      losClear = 0
    end if
  end if
end if

' Lane shift while the island blocks the line: stand on the SAME
' side of y=64 as the enemy so the segment never crosses the rocks.
' 3 s of hysteresis so the lane does not snap back and re-block.
if losClear = 0 then
  islandTick = worldTick
  if ey >= 64 then
    islandSide = 1
  else
    islandSide = -1
  end if
else
  if worldTick - islandTick > 96 then
    islandSide = 0
  end if
end if

' ---- shopping: spend every point; radius > distance > speed > damage
' selfPoints is a start-of-tick snapshot, so count spends locally.
left = selfPoints
while left > 0
  got = 0
  if buyUpgrade(3) = 1 then
    got = 1
  else
    if buyUpgrade(1) = 1 then
      got = 1
    else
      if buyUpgrade(2) = 1 then
        got = 1
      else
        if buyUpgrade(0) = 1 then
          got = 1
        end if
      end if
    end if
  end if
  if got = 1 then
    left = left - 1
  else
    left = 0
  end if
wend

' ---- gold shop: flask if hurting, then rank Longflight/Treads to 5 ---
if selfInShop = 1 then
  if selfHp * 2 < selfMaxHp then
    buyPower(0)
  end if
  if itemRank(1) < 5 then
    buyPower(6)
  end if
  if itemRank(0) < 5 then
    buyPower(5)
  end if
  buyPower(3)
  if itemRank(2) < 5 then
    buyPower(7)
  end if
  if itemRank(3) < 5 then
    buyPower(8)
  end if
end if

' Live hook stats after this tick's spends.
' Host calls stay on their own assignment — nested upgradeLevel
' in an arithmetic expression parse-fails on some binaries.
distLv = upgradeLevel(1)
radLv = upgradeLevel(3)
spdLv = upgradeLevel(2)
engageNow = engageDist + 4 * distLv + radLv
if selfBuff = 4 then
  engageNow = engageNow + engageNow / 2
end if
leadNow = leadDiv + spdLv
if leadNow < 1 then
  leadNow = 1
end if

' ---- incoming hooks: threat to me, or a victim to cut free ----------
threatX = -1
threatY = -1
threatD2 = 2147483647
cutX = -1
cutY = -1
ownHookX = -1
ownHookY = -1
h = 0
while h < hookCount()
  if hookFlying(h) = 1 then
    if hookTeam(h) <> selfTeam then
      hdx = hookX(h) - selfX
      if hdx < 0 then
        hdx = 0 - hdx
      end if
      hdy = hookY(h) - selfY
      if hdy < 0 then
        hdy = 0 - hdy
      end if
      if hdx * hdx + hdy * hdy <= dodgeDist * dodgeDist then
        if hdx * hdx + hdy * hdy < threatD2 then
          threatD2 = hdx * hdx + hdy * hdy
        end if
        threatX = hookX(h)
        threatY = hookY(h)
      end if
      if hookVictim(h) <> 0 and hookVictim(h) <> selfId then
        if hdx <= cutDist and hdy <= cutDist then
          cutX = hookX(h)
          cutY = hookY(h)
        end if
      end if
    else
      if hookOwner(h) = selfId then
        if hookVictim(h) = 0 then
          ownHookX = hookX(h)
          ownHookY = hookY(h)
        end if
      end if
    end if
  end if
  h = h + 1
wend

' ---- cutter detection: are our pokes being shot out of the air? ----
ourAir = 0
enemyAir = 0
h = 0
while h < hookCount()
  if hookFlying(h) = 1 then
    if hookTeam(h) = selfTeam then
      ourAir = 1
    else
      enemyAir = 1
    end if
  end if
  h = h + 1
wend
if prevOurAir = 1 and ourAir = 0 then
  if headIdx >= 0 then
    denyStreak = 0
  else
    if prevEnemyAir = 1 and enemyAir = 0 then
      ' Both chains died the same tick: that is a mid-air clash,
      ' not a plain miss. A miss during their unrelated poke is not.
      denyStreak = denyStreak + 1
      if denyStreak >= 3 then
        cutterUntil = worldTick + 960
      end if
    end if
  end if
end if
if prevEnemyAir = 1 and enemyAir = 0 then
  ' Their chain just spent itself: ~2 s of cut-proof throwing.
  punishUntil = worldTick + 50
end if
prevOurAir = ourAir
prevEnemyAir = enemyAir
cutterMode = 0
if worldTick <= cutterUntil then
  cutterMode = 1
end if

' Just shaken off a cutter's chain: zigzag clear before standing to
' throw. Only against cutters — against melee chasers a zigzag just
' lengthens our path and gets us run down.
if prevHooked = 1 and selfHooked = 0 then
  escapeUntil = worldTick + 48
end if
prevHooked = selfHooked
escaping = 0
if cutterMode = 1 and worldTick <= escapeUntil then
  ' Zigzag only with open ground: adjacent to a melee chaser the
  ' zigzag just lengthens our path and we get run down.
  if closeIdx < 0 then
    escaping = 1
  end if
end if
if enemyAir = 1 then
  lastEnemyAirTick = worldTick
end if
pokeSafe = 1
if cutterMode = 1 then
  pokeSafe = 0
  if enemyAir = 1 then
    pokeSafe = 1
  end if
  if worldTick <= punishUntil then
    pokeSafe = 1
  end if
  if worldTick - lastEnemyAirTick > 192 then
    ' The cutter has gone dormant: poke again before a mutual
    ' standoff turns the match into a staring contest.
    pokeSafe = 1
  end if
end if

' Committed dodge side per threat; re-crossing the line eats hooks.
if threatX >= 0 then
  if dodgeSide = 0 then
    if threatY > selfY then
      dodgeSide = -1
    else
      dodgeSide = 1
    end if
    if selfY < 20 and dodgeSide = -1 then
      dodgeSide = 1
    end if
    if selfY > 108 and dodgeSide = 1 then
      dodgeSide = -1
    end if
  end if
else
  dodgeSide = 0
end if

' ---- home ground ----------------------------------------------------
if selfTeam = 0 then
  edgeX = riverWest
  lipX = riverEast + 2
  inlandX = riverEast + fogPoke
else
  edgeX = riverEast
  lipX = riverWest - 2
  inlandX = riverWest - fogPoke
end if
padX = homeX
padY = homeY
if enemyAlive = 1 then
  pokeX = inlandX
  pokeY = ey
else
  if lastEy <> 0 then
    age = worldTick - lastSeen
    predY = lastEy + evy * age / 8
    if lastLayer = 2 then
      predX = lipX + evx * age / 16
    else
      predX = lastEx + evx * age / 8
    end if
    if age > 24 then
      predX = (predX * 2 + lipX) / 3
    end if
    if age > 96 then
      predX = lipX
    end if
    if selfTeam = 0 then
      if predX < riverEast + 1 then
        predX = riverEast + 2
      end if
      if predX > 113 then
        predX = 113
      end if
    else
      if predX > riverWest - 1 then
        predX = riverWest - 2
      end if
      if predX < 14 then
        predX = 14
      end if
    end if
    pokeX = predX
    pokeY = predY
  else
    pokeX = inlandX
    pokeY = selfY
  end if
end if
if pokeY < 16 then
  pokeY = 16
end if
if pokeY > 111 then
  pokeY = 111
end if

' ---- health posture -------------------------------------------------
lowHp = 0
if selfHp * 100 < selfMaxHp * retreatPct then
  lowHp = 1
end if
brawlOk = 0
if enemyAlive = 1 then
  if selfHp + brawlMargin >= ehp then
    brawlOk = 1
  end if
  if ehp <= 120 then
    ' Two swings from death: finish it, margins be damned.
    brawlOk = 1
  end if
end if

' ---- rot: blight a winning melee, leave anyone else's cloud ----------
wantRot = 0
if preyRot = 1 and eshield = 0 and selfLayer <> 2 then
  if brawlOk = 1 then
    wantRot = 1
  end if
end if
if lowHp = 1 then
  wantRot = 0
end if
if selfHp <= 96 then
  wantRot = 0
end if
if wantRot = 1 then
  if selfRot = 0 then
    rotToggle()
  end if
else
  if selfRot = 1 then
    rotToggle()
  end if
end if
fleeRot = 0
if foreignRot = 1 then
  if wantRot = 0 then
    fleeRot = 1
    escaping = 1
  end if
end if

' ---- blink: dodge on our bank, dump-chase only into water, stretch inland
mood = 0
blinked = 0
dodgeBlink = 0
if blinkReady = 1 then
  dumpChase = 0
  if swimIdx >= 0 then
    dumpChase = 1
  end if
  if headIdx >= 0 then
    if objectLayer(headIdx) = 2 then
      dumpChase = 1
    end if
  end if
  if selfLayer = 2 then
    if dumpChase = 0 or lowHp = 1 or brawlOk = 0 then
      if selfTeam = 0 then
        landX = riverWest
      else
        landX = riverEast
      end if
      landY = selfY
      if landY > 58 and landY < 70 then
        if selfY >= 64 then
          landY = 74
        else
          landY = 54
        end if
      end if
      blinked = blinkTo(landX, landY)
      if blinked = 1 then
        mood = 14
      end if
    end if
  else
    if threatX >= 0 then
      if selfTeam = 0 then
        hopX = selfX - 16
        if hopX > riverWest then
          hopX = riverWest
        end if
      else
        hopX = selfX + 16
        if hopX < riverEast then
          hopX = riverEast
        end if
      end if
      hopY = selfY + dodgeSide * blinkHop
      if hopY < 16 then
        hopY = 16
      end if
      if hopY > 111 then
        hopY = 111
      end if
      if hopX < 14 then
        hopX = 14
      end if
      if hopX > 113 then
        hopX = 113
      end if
      blinked = blinkTo(hopX, hopY)
      if blinked = 1 then
        mood = 15
        dodgeBlink = 1
      end if
    end if
    if blinked = 0 then
      if headIdx >= 0 and lowHp = 0 then
        hx = objectX(headIdx)
        hy = objectY(headIdx)
        hl = objectLayer(headIdx)
        if hl = 2 then
          blinked = blinkTo(hx, hy)
        else
          if hl <> selfLayer or headD2 > 100 then
            if hl <> selfLayer then
              if selfTeam = 0 then
                hx = riverWest
              else
                hx = riverEast
              end if
            end if
            blinked = blinkTo(hx, hy)
          end if
        end if
        if blinked = 1 then
          mood = 16
        end if
      end if
    end if
    if blinked = 0 then
      if ownHookX >= 0 then
        edx = ownHookX - selfX
        edy = ownHookY - selfY
        if edx < 0 then
          adx = 0 - edx
        else
          adx = edx
        end if
        if edy < 0 then
          ady = 0 - edy
        else
          ady = edy
        end if
        if adx >= 12 or ady >= 12 then
          hopX = ownHookX + edx
          hopY = ownHookY + edy
          if selfTeam = 0 then
            if hopX > riverWest then
              hopX = riverWest
            end if
          else
            if hopX < riverEast then
              hopX = riverEast
            end if
          end if
          if hopX < 8 then
            hopX = 8
          end if
          if hopX > 119 then
            hopX = 119
          end if
          if hopY < 16 then
            hopY = 16
          end if
          if hopY > 111 then
            hopY = 111
          end if
          blinked = blinkTo(hopX, hopY)
          if blinked = 1 then
            mood = 17
          end if
        end if
      end if
    end if
  end if
end if

' Dodge hop then throw in the same tick: the windup starts after the
' teleport, so the missed hook is answered immediately.
if dodgeBlink = 1 then
  if hookReady = 1 then
    if enemyAlive = 1 and eshield = 0 then
      span = dx
      if dy > span then
        span = dy
      end if
      aimX = ex + evx * span / leadNow
      aimY = ey + evy * span / leadNow
      if aimX < 8 then
        aimX = 8
      end if
      if aimX > 119 then
        aimX = 119
      end if
      if aimY < 8 then
        aimY = 8
      end if
      if aimY > 119 then
        aimY = 119
      end if
      thrown = hookTo(aimX, aimY)
      if thrown = 1 then
        mood = 18
      end if
    else
      if enemyAlive = 0 then
        thrown = hookTo(pokeX, pokeY)
        if thrown = 1 then
          mood = 20
        end if
      end if
    end if
  end if
end if

' Headshot even after a blink onto the catch. Same-tick throw.
if hookReady = 1 then
  if headIdx >= 0 then
    hx = objectX(headIdx)
    hy = objectY(headIdx)
    hx = hx + (allyX - hx) / 2
    hy = hy + (allyY - hy) / 2
    thrown = hookTo(hx, hy)
    if thrown = 1 then
      mood = 2
    end if
  end if
end if

' ---- decide ---------------------------------------------------------
if blinked = 0 then
if selfLayer = 2 or selfHooked = 1 then
  mood = 9
else
  if fleeRot = 0 and enemyAlive = 1 and closeIdx >= 0 and eshield = 0 and brawlOk = 1 then
    attackTarget(objectId(closeIdx))
    mood = 1
  else
    thrown = 0
    if hookReady = 1 and escaping = 0 then
      if threatX >= 0 and threatD2 <= 196 then
        ' A hook is closing point-blank: intercept it head-on. The
        ' disks converge, so aiming at its current head connects.
        thrown = hookTo(threatX, threatY)
        mood = 12
      end if
      if thrown = 0 then
        if headIdx >= 0 then
          hx = objectX(headIdx)
          hy = objectY(headIdx)
          hx = hx + (allyX - hx) / 2
          hy = hy + (allyY - hy) / 2
          thrown = hookTo(hx, hy)
          mood = 2
        end if
      end if
      if thrown = 0 and cutX >= 0 then
        ' An ally is on a chain: shoot it down.
        thrown = hookTo(cutX, cutY)
        mood = 8
      end if
      if thrown = 0 then
        if swimIdx >= 0 then
          thrown = hookTo(objectX(swimIdx), objectY(swimIdx))
          mood = 2
        else
          if saveIdx >= 0 then
            thrown = hookTo(objectX(saveIdx), objectY(saveIdx))
            mood = 10
          else
            engageEff = engageNow
            if cutterMode = 1 then
              if engageEff < 44 then
                engageEff = 44
              end if
            end if
            if enemyAlive = 1 and eshield = 0 and losClear = 1 then
              if pokeSafe = 1 and dx <= engageEff and dy <= engageEff then
                span = dx
                if dy > span then
                  span = dy
                end if
                aimX = ex + evx * span / leadNow
                aimY = ey + evy * span / leadNow
                if aimX < 8 then
                  aimX = 8
                end if
                if aimX > 119 then
                  aimX = 119
                end if
                if aimY < 8 then
                  aimY = 8
                end if
                if aimY > 119 then
                  aimY = 119
                end if
                thrown = hookTo(aimX, aimY)
                mood = 3
              end if
            end if
          end if
        end if
      end if
    end if
    if thrown = 0 and hookReady = 1 and mood = 0 then
      r = 0
      while r < runeCount()
        rdx = runeX(r) - selfX
        if rdx < 0 then
          rdx = 0 - rdx
        end if
        rdy = runeY(r) - selfY
        if rdy < 0 then
          rdy = 0 - rdy
        end if
        if rdx <= runeDist and rdy <= runeDist then
          thrown = hookTo(runeX(r), runeY(r))
          mood = 4
          r = runeCount()
        end if
        r = r + 1
      wend
    end if
    if thrown = 0 and hookReady = 1 and mood = 0 then
      if campIdx >= 0 then
        thrown = hookTo(objectX(campIdx), objectY(campIdx))
        mood = 22
      end if
    end if
    if thrown = 0 and hookReady = 1 and mood = 0 then
      if runeSoon > 0 then
        if runeSoon <= 16 then
          rdx = runeNextX - selfX
          if rdx < 0 then
            rdx = 0 - rdx
          end if
          rdy = runeNextY - selfY
          if rdy < 0 then
            rdy = 0 - rdy
          end if
          if rdx <= runeDist and rdy <= runeDist then
            thrown = hookTo(runeNextX, runeNextY)
            mood = 4
          end if
        end if
      end if
    end if
    if thrown = 0 and hookReady = 1 and mood = 0 then
      if enemyAlive = 0 and worldTick > 8 then
        thrown = hookTo(pokeX, pokeY)
        mood = 20
      end if
    end if
    ' Movement stacks under the throw.
    if escaping = 1 then
      zig = ((worldTick / 12) mod 2) * 2 - 1
      ezY = selfY + zig * 8
      if ezY < 8 then
        ezY = 8
      end if
      if ezY > 119 then
        ezY = 119
      end if
      walkTo(padX, ezY)
      if fleeRot = 1 then
        mood = 19
      else
        mood = 13
      end if
    else
    if threatX >= 0 then
      if selfTeam = 0 then
        stepX = 0 - 2
      else
        stepX = 2
      end if
      walkTo(selfX + stepX, selfY + dodgeSide * 10)
      if mood = 0 then
        mood = 5
      end if
    else
    if headIdx >= 0 and lowHp = 0 then
      ' A catch is on a chain: close in so the melee starts the
      ' moment the reel finishes.
      walkTo(objectX(headIdx), objectY(headIdx))
      if mood = 0 then
        mood = 11
      end if
    else
      pulling = 0
      if enemyAlive = 1 and bestD2 <= 144 and brawlOk = 0 then
        pulling = 1
      end if
      if lowHp = 1 then
        pulling = 1
      end if
      needCore = 0
      if itemRank(1) < 5 then
        needCore = 1
      end if
      if itemRank(0) < 5 then
        needCore = 1
      end if
      if selfHp * 2 < selfMaxHp then
        if selfGold >= 5 then
          needCore = 1
        end if
      end if
      wantShop = 0
      if needCore = 1 and selfGold >= 10 and threatX < 0 and headIdx < 0 then
        wantShop = 1
      end if
      if pulling = 1 then
        if selfHp * 100 < selfMaxHp * 90 then
          walkTo(padX, padY)
          mood = 6
        end if
      else
        if wantShop = 1 then
          walkTo(padX, padY)
          if mood = 0 then
            mood = 6
          end if
        else
        if mood <> 1 then
          phase = (worldTick / 6 + selfId * 7) mod 24
          if phase < 12 then
            juke = phase / 3 - 2
          else
            juke = 6 - phase / 3
          end if
          standoff = holdBack
          if cutterMode = 1 then
            ' Outside the cutter's 36-tile poke gate: starve it.
            standoff = 16
          end if
          if selfTeam = 0 then
            lineX = edgeX - standoff
          else
            lineX = edgeX + standoff
          end if
          if laneAllies <= 1 then
            lineY = pokeY + juke * jukeAmp / 2 + islandSide * 14
          else
            lineY = 40 + laneRank * 24 + juke + islandSide * 10
          end if
          if lineY < 8 then
            lineY = 8
          end if
          if lineY > 119 then
            lineY = 119
          end if
          if runeSoon > 0 then
            if runeSoon <= runeSoonWalk then
              lineY = runeNextY
              if mood = 0 then
                mood = 21
              end if
            end if
          end if
          walkTo(lineX, lineY)
          if mood = 0 then
            mood = 7
          end if
        end if
        end if
      end if
    end if
    end if
    end if
  end if
end if
end if

' Palisade on the river lip; mines offset into the fog-side brush.
if blinked = 0 then
  if selfLayer <> 2 then
    if selfTeam = 0 then
      wallX = selfX + 3
      if wallX > riverWest then
        wallX = riverWest
      end if
    else
      wallX = selfX - 3
      if wallX < riverEast then
        wallX = riverEast
      end if
    end if
    placeWall(wallX, selfY)
    mineY = selfY + 3
    if laneRank = 1 then
      mineY = selfY - 3
    end if
    if mineY < 16 then
      mineY = 16
    end if
    if mineY > 111 then
      mineY = 111
    end if
    placeMine(wallX, mineY)
  end if
end if

' ---- intent bubble on change ----------------------------------------
if mood <> saidMood then
  saidMood = mood
  if mood = 1 then
    print "chop chop"
  end if
  if mood = 2 then
    print "reeling you in"
  end if
  if mood = 3 then
    print "hook away"
  end if
  if mood = 4 then
    print "taking that rune"
  end if
  if mood = 5 then
    print "juking"
  end if
  if mood = 6 then
    print "healing up"
  end if
  if mood = 7 then
    print "holding my lane"
  end if
  if mood = 8 then
    print "cutting you free"
  end if
  if mood = 10 then
    print "pulling you out"
  end if
  if mood = 11 then
    print "got you, coming in"
  end if
  if mood = 12 then
    print "not today"
  end if
  if mood = 13 then
    print "shaking loose"
  end if
  if mood = 14 then
    print "flashing out"
  end if
  if mood = 15 then
    print "flashing"
  end if
  if mood = 16 then
    print "diving in"
  end if
  if mood = 17 then
    print "stretching the hook"
  end if
  if mood = 18 then
    print "dodge and hook"
  end if
  if mood = 19 then
    print "backing off rot"
  end if
  if mood = 20 then
    print "poking the fog"
  end if
  if mood = 21 then
    print "timing that rune"
  end if
  if mood = 22 then
    print "punish the timer"
  end if
end if
