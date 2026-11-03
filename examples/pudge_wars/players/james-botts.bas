deepHold = 1
hookStrobe = 1

dim ids(9)
dim px(9)
dim py(9)
dim hp(9)
dim peak(9)
dim team(9)
dim alive(9)
dim layer(9)
dim shield(9)
dim caught(9)
dim rot(9)
dim sampleX(9)
dim sampleY(9)
dim sampleTick(9)
dim vx(9)
dim vy(9)
dim carried(9)
dim air(9)
dim safe(9)
dim lanes(9)
dim trk(186)
dim kxT(98)
dim stP(9)
dim stT(15)
dim bhR(15)
dim led(168)
dim lr(31)


sub root(n)
  rootLo = 0
  rootHi = 256
  while rootLo + 1 < rootHi
    rootMid = (rootLo + rootHi) \ 2
    if rootMid * rootMid <= n then
      rootLo = rootMid
    else
      rootHi = rootMid
    end if
  wend
  rootValue = rootLo
end sub

sub disk(ax, ay, bx, by, cx, cy, radius)
  diskDx = bx - ax
  diskDy = by - ay
  diskLen = diskDx * diskDx + diskDy * diskDy
  diskX = cx - ax
  diskY = cy - ay
  diskDot = diskX * diskDx + diskY * diskDy
  diskHit = 0
  if diskDot <= 0 then
    if diskX * diskX + diskY * diskY <= radius * radius then diskHit = 1
  elseif diskDot >= diskLen then
    diskX = cx - bx
    diskY = cy - by
    if diskX * diskX + diskY * diskY <= radius * radius then diskHit = 1
  else
    diskCross = diskX * diskDy - diskY * diskDx
    if diskCross * diskCross <= radius * radius * diskLen then diskHit = 1
  end if
end sub

sub bigHook()
  if selfBuff = 0 and purchased = 0 then
    if buyPower(3) = 1 then purchased = 1
  end if
end sub

sub throwAt(tx, ty, recipient)
  shotAccepted = 0
  scr1 = 0
  if thrown = 1 or hookReady = 0 then exit sub
  if tx < 8 then tx = 8
  if tx > 119 then tx = 119
  if ty < 8 then ty = 8
  if ty > 119 then ty = 119
  scr2 = tx - originX
  scr3 = ty - originY
  root(scr2 * scr2 + scr3 * scr3)
  if rootValue = 0 then exit sub
  shotDist = rootValue
  shotX = tx
  shotY = ty
  if rootValue > reach then
    shotX = originX + scr2 * reach \ rootValue
    shotY = originY + scr3 * reach \ rootValue
  end if
  scr2 = shotX - originX
  scr3 = shotY - originY
  fountainX = 129 - 2 * originX
  fountainY = 129 - 2 * originY
  fountainLen = scr2 * scr2 + scr3 * scr3
  fountainDot = fountainX * scr2 + fountainY * scr3
  fountainBlocked = 0
  if fountainDot <= 0 then
    if fountainX * fountainX + fountainY * fountainY <= 49 then fountainBlocked = 1
  elseif fountainDot >= 2 * fountainLen then
    fountainX = 129 - 2 * shotX
    fountainY = 129 - 2 * shotY
    if fountainX * fountainX + fountainY * fountainY <= 49 then fountainBlocked = 1
  else
    fountainDot = fountainX * scr3 - fountainY * scr2
    if fountainDot * fountainDot <= 49 * fountainLen then fountainBlocked = 1
  end if
  if fountainBlocked = 1 then exit sub
  for scr2 = 0 to count - 1
    if alive(scr2) = 1 and team(scr2) = selfTeam and ids(scr2) <> selfId and ids(scr2) <> recipient and selfHooked = 0 then
      if shield(scr2) = 0 then
        disk(originX, originY, shotX, shotY, px(scr2), py(scr2), clearance)
        if diskHit = 1 and diskDot < diskLen then exit sub
        if diskHit = 1 then scr1 = 1
        disk(originX, originY, shotX, shotY, px(scr2) + vx(scr2) \ 2, py(scr2) + vy(scr2) \ 2, clearance)
        if diskHit = 1 and diskDot < diskLen then exit sub
        if diskHit = 1 then scr1 = 1
      end if
    end if
  next scr2
  if rescueRequest = 1 then
    shotAccepted = rescueAlly(recipient)
  else
    shotAccepted = hookTo(tx, ty)
  end if
  if shotAccepted = 1 then
    thrown = 1
    castX = tx
    castY = ty
    if shotSlot >= 0 then
      if team(shotSlot) <> selfTeam and ids(shotSlot) < 16 then lr(ids(shotSlot)) = lr(ids(shotSlot)) + 1
    end if
    if hookNotes < 380 then
      hookNotes = hookNotes + 1
      shotNote$ = "{""x"":" + STR$(tx) + ",""y"":" + STR$(ty) + ",""r"":" + STR$(recipient) + ",""t"":0"
      if shotSlot >= 0 then shotNote$ = "{""x"":" + STR$(tx) + ",""y"":" + STR$(ty) + ",""r"":" + STR$(recipient) + ",""t"":" + STR$(ids(shotSlot)) + ",""tx"":" + STR$(px(shotSlot)) + ",""ty"":" + STR$(py(shotSlot)) + ",""vx"":" + STR$(vx(shotSlot)) + ",""vy"":" + STR$(vy(shotSlot))
      if scr1 = 1 then shotNote$ = shotNote$ + ",""bl"":1"
      if shotBranch$ = "rune" then shotNote$ = shotNote$ + ",""dl"":" + STR$(runeLed)
      note("hook", shotBranch$, shotNote$ + ",""d"":" + STR$(shotDist) + ",""b"":" + STR$(selfBuff) + "}")
    end if
  end if
end sub

sub moveTo(mx, my, why)
  mvWhy = why
  if selfLayer = selfTeam and trajHook < 0 and fleeRot = 0 then
    for h = 0 to hookCount() - 1
      o = hookOwner(h)
      allyMark = 0
      if hookTeam(h) = selfTeam then allyMark = 1
      if (allyMark = 0 or (allyOk = 1 and o <> selfId)) and (hookFlying(h) = 1 or hookVictim(h) = 0) and o >= 0 and o < 16 then
        if trk(68 + o) = worldTick and trk(136 + o) <> 0 then
          tdx = hookX(h) - trk(o)
          tdy = hookY(h) - trk(17 + o)
          tLen = tdx * tdx + tdy * tdy
          twx = selfX - hookX(h)
          twy = selfY - hookY(h)
          tAlong = twx * tdx + twy * tdy
          tDist = tdx * twy - tdy * twx
          if threat >= 0 then
            if hookOwner(threat) <> o then tLen = 0
          end if
          if tLen >= 9 and (tAlong > 0 or trk(119 + o) = 0) and tDist * tDist <= 144 * tLen then
            stepX = mx - selfX
            stepY = my - selfY
            d2 = tdx * stepY - tdy * stepX
            if (tDist > 0 and d2 < 0) or (tDist < 0 and d2 > 0) then
              d2 = stepX * tdx + stepY * tdy
              mx = selfX + tdx * d2 \ tLen
              my = selfY + tdy * d2 \ tLen
            end if
          end if
        end if
      end if
    next h
  end if
  if selfLayer = selfTeam and trajHook < 0 and threat < 0 and why >= 5 and why <= 12 then
    for h = 0 to hookCount() - 1
      o = hookOwner(h)
      if hookTeam(h) <> selfTeam and hookFlying(h) = 1 and o >= 0 and o < 16 then
        if trk(68 + o) = worldTick and trk(119 + o) = 0 then
          tdx = hookX(h) - trk(o)
          tdy = hookY(h) - trk(17 + o)
          tLen = tdx * tdx + tdy * tdy
          twx = selfX - hookX(h)
          twy = selfY - hookY(h)
          tDist = tdx * twy - tdy * twx
          if tLen >= 9 and twx * tdx + twy * tdy > 0 and tDist * tDist <= 256 * tLen then
            stepX = mx - selfX
            stepY = my - selfY
            d2 = tdx * stepY - tdy * stepX
            if (tDist > 0 and d2 < 0) or (tDist < 0 and d2 > 0) then
              kx(4, 1)
              d2 = stepX * tdx + stepY * tdy
              mx = selfX + tdx * d2 \ tLen
              my = selfY + tdy * d2 \ tLen
            end if
          end if
        end if
      end if
    next h
  end if
  if selfLayer = selfTeam and why <> 2 and why <> 3 and (my < 32 or my > 95) then
    kx(68, 1)
    if my < 32 then my = 32
    if my > 95 then my = 95
  end if
  if selfLayer = selfTeam and (mx < curveMinX or mx > curveMaxX) then
    kx(2, 1)
    if mx < curveMinX then mx = curveMinX
    if mx > curveMaxX then mx = curveMaxX
  end if
  if selfLayer <> selfTeam and selfLayer <> 2 and ((selfTeam = 1 and mx > riverWest + 20) or (selfTeam = 0 and mx < riverEast - 20)) then
    kx(31, 1)
    mx = riverEast
    if selfTeam = 1 then mx = riverWest
  end if
  if mx < 8 then mx = 8
  if mx > 119 then mx = 119
  if my < 8 then my = 8
  if my > 119 then my = 119
  walkTo(mx, my)
end sub

sub perp(pdx, pdy, ps)
  root(pdx * pdx + pdy * pdy)
  stepX = 0 - pdy * 10 * ps \ rootValue
  stepY = pdx * 10 * ps \ rootValue
  pBlocked = 0
  if selfY + stepY < 12 or selfY + stepY > 115 then pBlocked = 1
  if selfLayer <> selfTeam and selfLayer <> 2 then
    if selfTeam = 0 and (selfX + stepX <= riverEast or selfX + stepX > 113) then pBlocked = 1
    if selfTeam = 1 and (selfX + stepX < 14 or selfX + stepX >= riverWest) then pBlocked = 1
  elseif selfX + stepX < curveMinX or selfX + stepX > curveMaxX then
    pBlocked = 1
  end if
end sub

sub lineSide(lo, lx, ly)
  lsDy = 0
  if lo >= 0 and lo < 16 then
    if trk(68 + lo) = worldTick then
      tdx = lx - trk(lo)
      tdy = ly - trk(17 + lo)
      lsSide = trk(136 + lo)
      if lsSide <> 1 and lsSide <> -1 then
        lsSide = tdx * (selfY - ly) - tdy * (selfX - lx)
      end if
      if tdx * tdx + tdy * tdy >= 9 and tdx * lsSide > 0 then lsDy = 1
      if tdx * tdx + tdy * tdy >= 9 and tdx * lsSide < 0 then lsDy = -1
    end if
  end if
end sub

sub note(noteKind$, noteFn$, noteArgs$)
  if noteCount >= 800 and noteKind$ <> "hook" then exit sub
  noteCount = noteCount + 1
  ANNOTATE(worldTick, noteKind$, noteFn$, noteArgs$)
end sub

sub kx(kxK, kxA)
  if worldTick - kxT(kxK) > 32 then
    kxT(kxK) = worldTick
    print "kx " + STR$(kxK) + " " + STR$(worldTick) + " " + STR$(kxA)
  end if
end sub

sub ledgerPay(lk)
  led(32 + lk) = led(32 + lk) + 1
  lgB = 0
  if led(32 + lk) >= 3 then lgB = led(32 + lk) - 2
  if led(32 + lk) >= 9 then lgB = led(32 + lk) - 1
  if lgB > 9 then lgB = 9
  led(lk) = led(lk) + 3 + lgB + 2 * (1 - lgSeen)
  lgSeen = 1
end sub

sub curveEnd(cx, cy)
  curveScale = 1024
  if cx > 0 and selfX + cx > curveMaxX - (11 + dropDx) * (1 - selfTeam) then curveScale = (curveMaxX - (11 + dropDx) * (1 - selfTeam) - selfX) * 1024 \ cx
  if cx < 0 and selfX + cx < curveMinX + (11 + dropDx) * selfTeam then curveScale = (curveMinX + (11 + dropDx) * selfTeam - selfX) * 1024 \ cx
  if cy > 0 and selfY + cy > 95 then
    curveYScale = (95 - selfY) * 1024 \ cy
    if curveYScale < 0 then curveYScale = 0
    if curveYScale < curveScale then curveScale = curveYScale
  end if
  if cy < 0 and selfY + cy < 32 then
    curveYScale = (32 - selfY) * 1024 \ cy
    if curveYScale < 0 then curveYScale = 0
    if curveYScale < curveScale then curveScale = curveYScale
  end if
  curveEndX = selfX + cx * curveScale \ 1024
  curveEndY = selfY + cy * curveScale \ 1024
  curveStep = (curveEndX - selfX) * (curveEndX - selfX) + (curveEndY - selfY) * (curveEndY - selfY)
end sub

if worldTick < previousTick or (selfShield > 0 and previousShield = 0) then
  count = 0
  recovering = 0
  rescueUntil = 0
  curveActive = 0
  dodgeSide = 0
  lastSeen = 0
  if worldTick < previousTick then
    hookNotes = 0
    noteCount = 0
    helloSent = 0
    nextPingTick = 0
    for o = 0 to 15
      trk(68 + o) = -100
    next o
    nextSpacingNote = 0
    for o = 0 to 31
      lr(o) = 0
    next o
    for o = 0 to 96
      kxT(o) = -100
    next o
    nextLaneNote = 0
    for o = 0 to 167
      led(o) = 0
    next o
    lgSeen = 0
    lgRunes = 0
  end if
end if
if worldTick - previousTick >= 32 and previousTick > 0 then
  if scuttleOn = 0 and led(64 + selfId) > 0 and previousTick - led(64 + selfId) <= 96 then ledgerPay(led(48 + selfId))
  lgSeen = 1
end if
previousTick = worldTick
previousShield = selfShield
if selfHp <= 0 then
  curveActive = 0
  recovering = 0
  end
end if
for i = 0 to count - 1
  alive(i) = 0
  carried(i) = 0
  air(i) = 0
next i
for obj = 0 to objectCount() - 1
  if objectKind(obj) = 1 then
    oid = objectId(obj)
    slot = -1
    for i = 0 to count - 1
      if ids(i) = oid then slot = i
    next i
    if slot < 0 and count < 10 then
      slot = count
      count = count + 1
      ids(slot) = oid
      peak(slot) = 1200
      sampleTick(slot) = -1
      vx(slot) = 0
      vy(slot) = 0
      carried(slot) = 0
      air(slot) = 0
    end if
    if slot >= 0 then
      px(slot) = objectX(obj)
      py(slot) = objectY(obj)
      hp(slot) = objectHp(obj)
      if hp(slot) > peak(slot) then peak(slot) = hp(slot)
      team(slot) = objectTeam(obj)
      alive(slot) = objectAlive(obj)
      layer(slot) = objectLayer(obj)
      shield(slot) = objectShielded(obj)
      caught(slot) = objectHooked(obj)
      rot(slot) = objectRot(obj)
      if oid < 16 then
        if objectAlive(obj) = 0 and led(128 + oid) = 1 then
          led(128 + oid) = 2
        else
          led(128 + oid) = objectAlive(obj)
        end if
      end if
      if sampleTick(slot) < 0 or worldTick - sampleTick(slot) > 96 or alive(slot) = 0 then
        sampleX(slot) = px(slot)
        sampleY(slot) = py(slot)
        sampleTick(slot) = worldTick
        vx(slot) = 0
        vy(slot) = 0
      elseif worldTick - sampleTick(slot) >= 8 then
        vx(slot) = (px(slot) - sampleX(slot)) * 8 \ (worldTick - sampleTick(slot))
        vy(slot) = (py(slot) - sampleY(slot)) * 8 \ (worldTick - sampleTick(slot))
        sampleX(slot) = px(slot)
        sampleY(slot) = py(slot)
        sampleTick(slot) = worldTick
      end if
      if oid = selfId then
        me = slot
        selfObject = obj
      end if
    end if
  end if
next obj
peak(me) = selfMaxHp
lrN = 0
for h = 0 to hookCount() - 1
  if hookOwner(h) = selfId then lrN = hookVictim(h)
next h
if lrN <> lrV and lrN > 0 and lrN < 16 then
  for i = 0 to count - 1
    if ids(i) = lrN and team(i) <> selfTeam then lr(16 + lrN) = lr(16 + lrN) + 1
  next i
end if
lrV = lrN
scr3 = 0
scr4 = 0
for i = 0 to count - 1
  scr1 = stP(i) \ 8 - hp(i)
  scr2 = 0
  if alive(i) = 1 and scr1 >= 20 then
    if team(i) <> selfTeam and rot(i) = 1 and hp(i) >= 300 then
      scr2 = stP(i) mod 8 + 1
      if scr2 > 6 then scr2 = 6
      if scr2 = 6 and stT(ids(i)) = 0 then stT(ids(i)) = worldTick
    end if
    if team(i) = selfTeam and caught(i) = 1 and scr1 >= 290 and scr1 <= 349 then
      for h = 0 to hookCount() - 1
        if hookVictim(h) = ids(i) and hookTeam(h) <> selfTeam and hookOwner(h) >= 0 and hookOwner(h) < 16 then bhR(hookOwner(h)) = worldTick
      next h
    end if
  end if
  stP(i) = hp(i) * 8 + scr2
  if team(i) <> selfTeam and alive(i) = 1 then
    if stT(ids(i)) > 0 then scr3 = 1
    if bhR(ids(i)) > 0 and worldTick - bhR(ids(i)) <= 480 then scr4 = 1
  end if
next i
deepOn = scr3 * scr4
if selfHp * 100 >= selfMaxHp * 75 then recovering = 0
if selfHp * 100 < selfMaxHp * 40 then recovering = 1
target = -1
targetD2 = 2147483647
catchTarget = -1
catchD2 = 2147483647
scr4 = -1
swimmerD2 = 2147483647
foreignRot = 0
mateD2 = 2147483647
nearFoe = 0
teamCount = 0
for i = 0 to count - 1
  if team(i) = selfTeam then teamCount = teamCount + 1
  if alive(i) = 1 then
    d2 = (px(i) - selfX) * (px(i) - selfX) + (py(i) - selfY) * (py(i) - selfY)
    if ids(i) <> selfId and rot(i) = 1 and d2 <= 64 then foreignRot = 1
    if ids(i) <> selfId and team(i) = selfTeam and d2 < mateD2 then mateD2 = d2
    if team(i) <> selfTeam and d2 <= 64 then nearFoe = 1
    if team(i) <> selfTeam and shield(i) = 0 then
      if d2 < targetD2 then
        target = i
        targetD2 = d2
      end if
      if caught(i) = 1 and d2 < catchD2 then
        catchTarget = i
        catchD2 = d2
      end if
      if layer(i) = 2 and d2 < swimmerD2 then
        scr4 = i
        swimmerD2 = d2
      end if
    end if
  end if
next i
if worldTick >= nextSpacingNote and selfLayer = selfTeam then
  nextSpacingNote = worldTick + 2048
  nearMate = -1
  mates = 0
  for i = 0 to count - 1
    if i <> me and alive(i) = 1 and team(i) = selfTeam and layer(i) = selfTeam then
      mates = mates + 1
      d2 = py(i) - selfY
      if d2 < 0 then d2 = 0 - d2
      if nearMate < 0 or d2 < nearMate then nearMate = d2
    end if
  next i
  note("spacing", "own_bank", "{""d"":" + STR$(nearMate) + ",""n"":" + STR$(mates) + ",""y"":" + STR$(selfY) + "}")
end if
if target >= 0 then
  lastSeen = worldTick
  lastX = px(target)
  lastY = py(target)
  lastVx = vx(target)
  lastVy = vy(target)
end if
threat = -1
threatD2 = 485
ownHook = -1
ownRescue = 0
for h = 0 to hookCount() - 1
  for i = 0 to count - 1
    if hookOwner(h) = ids(i) then air(i) = 1
    if hookVictim(h) = ids(i) then carried(i) = hookTeam(h) + 1
  next i
  if hookOwner(h) = selfId then
    ownHook = h
    for i = 0 to count - 1
      if team(i) = selfTeam and hookVictim(h) = ids(i) then ownRescue = 1
    next i
  end if
  if hookTeam(h) <> selfTeam and hookFlying(h) = 1 then
    d2 = (hookX(h) - selfX) * (hookX(h) - selfX) + (hookY(h) - selfY) * (hookY(h) - selfY)
    if d2 < threatD2 then
      threatD2 = d2
      threat = h
    end if
  end if
next h
if selfHp > 0 and worldTick >= nextPingTick then
  pingKind$ = ""
  if helloSent = 0 and worldTick < 64 then
    pingKind$ = "hello"
    helloSent = 1
  elseif selfHooked = 1 and carried(me) = 2 - selfTeam then
    pingKind$ = "rescue"
  elseif selfLayer = 2 then
    pingKind$ = "rescue"
  end if
  if pingKind$ <> "" then
    ping(selfX, selfY)
    nextPingTick = worldTick + 32
  end if
end if
allyOk = 0
if selfHooked = 0 and selfMaxHp - selfHp < 120 then allyOk = 1
trajHook = -1
trajD2 = 2147483647
for h = 0 to hookCount() - 1
  scr1 = 0
  if hookFlying(h) = 0 and hookVictim(h) = 0 then scr1 = 1
  allyMark = 0
  if hookTeam(h) = selfTeam then allyMark = 1
  if (allyMark = 0 or (allyOk = 1 and hookOwner(h) <> selfId)) and (hookFlying(h) = 1 or scr1 = 1) then
    o = hookOwner(h)
    if o >= 0 and o < 16 then
      if worldTick - trk(68 + o) > 8 or (trk(119 + o) = 1 and scr1 = 0) then
        trk(o) = hookX(h)
        trk(17 + o) = hookY(h)
        trk(34 + o) = hookX(h)
        trk(51 + o) = hookY(h)
        trk(85 + o) = 0
        trk(136 + o) = 0
        trk(153 + o) = 0
        trk(170 + o) = 0
      end if
      if trk(119 + o) = 0 and scr1 = 1 then trk(85 + o) = 0
      trk(119 + o) = scr1
      rtSeg = 0
      if scr1 = 0 and allyMark = 0 and ((selfTeam = 0 and hookX(h) < riverWest) or (selfTeam = 1 and hookX(h) > riverEast)) then
        rtP = trk(153 + o) mod 16385
        tdx = trk(o)
        tdy = trk(17 + o)
        if rtP > 0 then
          tdx = (rtP - 1) \ 128
          tdy = (rtP - 1) mod 128
        end if
        rtBx = tdx
        rtBy = tdy
        if trk(170 + o) > 0 then
          rtBx = (trk(170 + o) - 1) \ 128
          rtBy = (trk(170 + o) - 1) mod 128
        end if
        tdx = rtBx - tdx
        tdy = rtBy - tdy
        tLen = tdx * tdx + tdy * tdy
        twx = hookX(h) - rtBx
        twy = hookY(h) - rtBy
        tDist = twx * twx + twy * twy
        tAlong = 0
        if tLen >= 9 and tDist >= 4 then
          if (tdx * twy - tdy * twx) * (tdx * twy - tdy * twx) > 4 * tLen and (tdx * twy - tdy * twx) * (tdx * twy - tdy * twx) * 100 >= 12 * tLen * tDist then tAlong = 1
          if tdx * twx + tdy * twy < 0 and (tdx * twx + tdy * twy) * (tdx * twx + tdy * twy) >= 4 * tLen then tAlong = 1
        end if
        if tAlong = 1 then
          trk(153 + o) = rtBx * 128 + rtBy + 1 + rtP * 16385
          trk(170 + o) = 0
        elseif tDist >= 36 then
          trk(170 + o) = hookX(h) * 128 + hookY(h) + 1
        end if
      end if
      tdx = hookX(h) - trk(o)
      tdy = hookY(h) - trk(17 + o)
      if (hookX(h) - trk(34 + o)) * tdx + (hookY(h) - trk(51 + o)) * tdy < 0 then
        trk(o) = trk(34 + o)
        trk(17 + o) = trk(51 + o)
        tdx = hookX(h) - trk(o)
        tdy = hookY(h) - trk(17 + o)
        if trk(136 + o) <> 0 then trk(136 + o) = 2
        if scr1 = 0 and allyMark = 0 and ((selfTeam = 0 and hookX(h) < riverWest) or (selfTeam = 1 and hookX(h) > riverEast)) then
          rtP = trk(153 + o) mod 16385
          if rtP <> trk(34 + o) * 128 + trk(51 + o) + 1 then
            trk(153 + o) = trk(34 + o) * 128 + trk(51 + o) + 1 + rtP * 16385
            trk(170 + o) = 0
          end if
        end if
      end if
      if scr1 = 1 and allyMark = 0 then
        hlI = -1
        for i = 0 to count - 1
          if ids(i) = o and alive(i) = 1 then hlI = i
        next i
        if hlI >= 0 then
          if (px(hlI) - hookX(h)) * (px(hlI) - hookX(h)) + (py(hlI) - hookY(h)) * (py(hlI) - hookY(h)) >= 9 then
            kx(53, 1)
            trk(o) = 2 * hookX(h) - px(hlI)
            trk(17 + o) = 2 * hookY(h) - py(hlI)
            tdx = px(hlI) - hookX(h)
            tdy = py(hlI) - hookY(h)
          end if
        end if
        rtP = trk(153 + o)
        tAlong = 0
        while rtP > 0 and tAlong = 0
          rtBx = ((rtP mod 16385) - 1) \ 128
          rtBy = ((rtP mod 16385) - 1) mod 128
          tDist = (hookX(h) - rtBx) * (hookX(h) - rtBx) + (hookY(h) - rtBy) * (hookY(h) - rtBy)
          tLen = (trk(34 + o) - rtBx) * (trk(34 + o) - rtBx) + (trk(51 + o) - rtBy) * (trk(51 + o) - rtBy)
          if tDist <= 4 or (tDist > tLen and tLen <= 25) then
            rtP = rtP \ 16385
          else
            tAlong = 1
          end if
        wend
        trk(153 + o) = rtP
        if tAlong = 1 then
          kx(80, 1)
          trk(o) = 3 * hookX(h) - 2 * rtBx
          trk(17 + o) = 3 * hookY(h) - 2 * rtBy
          tdx = 2 * (rtBx - hookX(h))
          tdy = 2 * (rtBy - hookY(h))
          rtSeg = 1
        end if
      end if
      trk(68 + o) = worldTick
      trk(34 + o) = hookX(h)
      trk(51 + o) = hookY(h)
      vhX = hookX(h)
      vhY = hookY(h)
      if rtSeg = 1 then
        rtAx = hookX(h)
        rtAy = hookY(h)
        rtQ = trk(153 + o)
        rtK = 0
        rtDone = 0
        while rtDone = 0
          rtE = 2
          if rtQ > 0 then
            rtBx = ((rtQ mod 16385) - 1) \ 128
            rtBy = ((rtQ mod 16385) - 1) mod 128
            rtQ = rtQ \ 16385
            rtE = 0
          elseif hlI >= 0 then
            rtBx = px(hlI)
            rtBy = py(hlI)
            rtE = 1
          end if
          if rtE = 2 then
            rtDone = 1
          else
            twx = rtBx - rtAx
            twy = rtBy - rtAy
            tLen = twx * twx + twy * twy
            if tLen >= 9 then
              root(tLen)
              tAlong = (selfX - rtAx) * twx + (selfY - rtAy) * twy
              tDist = (selfX - rtAx) * (selfX - rtAx) + (selfY - rtAy) * (selfY - rtAy)
              if tAlong > 0 and (rtE = 1 or tAlong <= tLen + 6 * rootValue) and tDist * tLen - tAlong * tAlong <= 64 * tLen then
                vhX = rtAx
                vhY = rtAy
                tdx = twx
                tdy = twy
                rtDone = 1
                if rtK > 0 then kx(86, 1)
              end if
            end if
            rtAx = rtBx
            rtAy = rtBy
            rtK = rtK + 1
            if rtE = 1 then rtDone = 1
          end if
        wend
      end if
      tLen = tdx * tdx + tdy * tdy
      if tLen >= 9 then
        twx = selfX - vhX
        twy = selfY - vhY
        tAlong = twx * tdx + twy * tdy
        tDist = twx * twx + twy * twy
        if tAlong > 0 and tDist * tLen - tAlong * tAlong <= 64 * tLen then
          if trk(85 + o) = 0 then
            trk(85 + o) = 1
            dodgeFlip = 1
            if tdx * twy - tdy * twx < 0 then dodgeFlip = -1
            if tdx * twy - tdy * twx = 0 and selfY > 64 then dodgeFlip = -1
            perp(tdx, tdy, dodgeFlip)
            if trk(136 + o) = 0 or trk(136 + o) = 2 then
              trk(136 + o) = dodgeFlip
              if pBlocked = 1 then trk(136 + o) = 0 - dodgeFlip
            end if
          end if
          if tDist + allyMark * 200000 < trajD2 then
            trajD2 = tDist + allyMark * 200000
            trajHook = h
            trajDx = tdx
            trajDy = tdy
            trajCross = tdx * twy - tdy * twx
            trajLen = tLen
          end if
        elseif tAlong > 0 and trk(136 + o) <> 0 and tDist * tLen - tAlong * tAlong <= 144 * tLen and tDist + 100000 + allyMark * 200000 < trajD2 then
          dodgeFlip = 1
          if tdx * twy - tdy * twx < 0 then dodgeFlip = -1
          perp(tdx, tdy, dodgeFlip)
          if (trk(136 + o) = 2 or trk(136 + o) = dodgeFlip) and pBlocked = 0 then
            trajD2 = tDist + 100000 + allyMark * 200000
            trajHook = h
            trajDx = tdx
            trajDy = tdy
            trajCross = tdx * twy - tdy * twx
            trajLen = tLen
          end if
        end if
      end if
    end if
  end if
next h
if selfLayer = 2 then trajHook = -1
lsDy = 0
if threat >= 0 then lineSide(hookOwner(threat), hookX(threat), hookY(threat))
if threat < 0 then
  dodgeSide = 0
elseif dodgeSide = 0 then
  dodgeSide = 1
  if hookY(threat) > selfY then dodgeSide = -1
  if selfY < 20 then dodgeSide = 1
  if selfY > 108 then dodgeSide = -1
end if
if lsDy <> 0 then dodgeSide = lsDy
brawl = 0
if target >= 0 then
  if selfHp + 40 >= hp(target) or hp(target) <= 120 or (selfLayer <> selfTeam and selfLayer <> 2) then brawl = 1
end if
wantRot = 0
if targetD2 <= 64 and brawl = 1 and selfLayer <> 2 and recovering = 0 and selfHp > 96 then wantRot = 1
chOn = 0
if ccPrev > 0 and selfHooked = 0 and selfLayer <> selfTeam and selfLayer <> 2 and selfHp >= 600 then
  for i = 0 to count - 1
    if ids(i) = ccPrev and alive(i) = 1 and (px(i) - selfX) * (px(i) - selfX) + (py(i) - selfY) * (py(i) - selfY) <= 64 then
      ccLand = worldTick
      ccCap = ccPrev
    end if
  next i
end if
ccPrev = 0
if selfHooked = 1 then
  for h = 0 to hookCount() - 1
    if hookVictim(h) = selfId and hookTeam(h) <> selfTeam then ccPrev = hookOwner(h)
  next h
end if
if ccLand > 0 and worldTick - ccLand > 24 then ccLand = 0
if ccLand > 0 then
  for h = 0 to hookCount() - 1
    if hookOwner(h) = ccCap and ccLand > 0 and (hookFlying(h) = 1 or (hookVictim(h) <> 0 and (hookVictim(h) <> selfId or selfHooked = 1))) then
      ccEnd = worldTick + 48
      ccLand = 0
    end if
  next h
end if
if worldTick < ccEnd and selfLayer <> selfTeam and selfLayer <> 2 and selfHooked = 0 then
  kx(56, 1)
  chOn = 1
end if
if chOn = 1 then wantRot = 0
hsOn = 0
hsN = 0
if ownHook >= 0 then hsN = hookVictim(ownHook)
if hsN > 0 then
  for i = 0 to count - 1
    if ids(i) = hsN and team(i) <> selfTeam then
      hsId = hsN
      hsT = worldTick + 96
    end if
  next i
end if
if hookStrobe > 0 and hsId > 0 and worldTick <= hsT and selfLayer = selfTeam and selfHooked = 0 and selfHp > 400 then
  for i = 0 to count - 1
    if ids(i) = hsId and alive(i) = 1 then
      hsN = (px(i) - selfX) * (px(i) - selfX) + (py(i) - selfY) * (py(i) - selfY)
      if hsN <= 64 and (mateD2 > 64 or mateD2 >= hsN) and selfHp - hp(i) >= 150 then hsOn = 1
    end if
  next i
end if
if hsOn = 1 then
  wantRot = 1
  kx(98, 1)
end if
if selfHp <= 96 and nearFoe = 1 and (selfLayer <> selfTeam or (selfHooked = 1 and carried(me) = 2 - selfTeam)) then
  scuttleOn = 1
  if selfRot = 1 then rotToggle()
  rotToggle()
elseif hsOn = 1 then
  scuttleOn = 0
  if selfRot = 1 then rotToggle()
  rotToggle()
else
  scuttleOn = 0
  rmOff = 0
  if wantRot = 1 and mateD2 <= 100 and mateD2 < targetD2 then rmOff = 1
  if wantRot * (1 - rmOff) <> selfRot then rotToggle()
end if
fleeRot = 0
if foreignRot = 1 and wantRot = 0 then fleeRot = 1

left = selfPoints
while left > 0
  purchased = buyUpgrade(1)
  if purchased = 0 then purchased = buyUpgrade(2)
  if purchased = 0 then purchased = buyUpgrade(0)
  if purchased = 0 then purchased = buyUpgrade(3)
  if purchased = 0 then
    left = 0
  else
    left = left - 1
  end if
wend
if selfInShop = 1 then
  buyPower(9)
  purchased = 0
  if selfHp * 2 < selfMaxHp then
    buyPower(0)
  end if
  bigHook()
  buying = 1
  while buying = 1
    buying = 0
    if itemRank(1) < 5 then
      buying = buyPower(6)
    end if
    if itemRank(0) < 5 then
      if buyPower(5) = 1 then buying = 1
    end if
  wend
  if itemRank(1) > 0 then bigHook()
end if
distanceLevel = upgradeLevel(1)
speedLevel = upgradeLevel(2)
scr5 = upgradeLevel(3)
reach = 60 + 4 * distanceLevel
clearance = 6 + (scr5 + 7) \ 8
if selfBuff = 4 then
  reach = reach * 3 \ 2
  clearance = 8 + (scr5 * 3 + 15) \ 16
end if
for i = 0 to count - 1
  o = ids(i)
  if o < 16 then
    if led(128 + o) = 2 then
      led(128 + o) = 0
      if team(i) = selfTeam then
        lgK = -1
        if led(64 + o) > 0 and worldTick - led(64 + o) <= 96 then
          lgK = led(48 + o)
        else
          lgD = 2147483647
          for j = 0 to count - 1
            if alive(j) = 1 and team(j) <> selfTeam and ids(j) < 16 then
              d2 = (px(j) - px(i)) * (px(j) - px(i)) + (py(j) - py(i)) * (py(j) - py(i))
              if d2 < lgD then
                lgD = d2
                lgK = ids(j)
              end if
            end if
          next j
        end if
        if lgK >= 0 then ledgerPay(lgK)
        lgSeen = 1
      else
        led(32 + o) = 0
        led(16 + o) = 0
        lgSeen = 1
      end if
    end if
  end if
next i
for h = 0 to hookCount() - 1
  o = hookOwner(h)
  if o >= 0 and o < 16 then
    if hookTeam(h) = selfTeam then
      led(80 + o) = worldTick
      led(96 + o) = hookX(h)
      led(112 + o) = hookY(h)
    elseif hookVictim(h) > 0 and hookVictim(h) < 16 then
      led(48 + hookVictim(h)) = o
      led(64 + hookVictim(h)) = worldTick
    end if
  end if
next h
for i = 0 to count - 1
  o = ids(i)
  if team(i) = selfTeam and o < 16 then
    if led(80 + o) = worldTick - 1 and alive(i) = 1 and (led(96 + o) - px(i)) * (led(96 + o) - px(i)) + (led(112 + o) - py(i)) * (led(112 + o) - py(i)) > 36 then
      for h = 0 to hookCount() - 1
        lgK = hookOwner(h)
        if hookTeam(h) <> selfTeam and lgK >= 0 and lgK < 16 and (hookX(h) - led(96 + o)) * (hookX(h) - led(96 + o)) + (hookY(h) - led(112 + o)) * (hookY(h) - led(112 + o)) <= 100 then
          led(16 + lgK) = worldTick + 480
        end if
      next h
    end if
  end if
next i
for r = 0 to lgRunes - 1
  lgK = 0
  for q = 0 to runeCount() - 1
    if runeKind(q) = led(146 + 3 * r) and (runeX(q) - led(144 + 3 * r)) * (runeX(q) - led(144 + 3 * r)) + (runeY(q) - led(145 + 3 * r)) * (runeY(q) - led(145 + 3 * r)) <= 9 then lgK = 1
  next q
  if lgK = 0 then
    lgK = -1
    lgD = 26
    for j = 0 to count - 1
      if alive(j) = 1 then
        d2 = (px(j) - led(144 + 3 * r)) * (px(j) - led(144 + 3 * r)) + (py(j) - led(145 + 3 * r)) * (py(j) - led(145 + 3 * r))
        if d2 < lgD then
          lgD = d2
          lgK = j
        end if
      end if
    next j
    if lgK >= 0 then
      if team(lgK) <> selfTeam and ids(lgK) < 16 then
        o = ids(lgK)
        if led(146 + 3 * r) = 5 then led(o) = led(o) + 4
        if led(146 + 3 * r) = 3 then led(16 + o) = worldTick + 480
      end if
    end if
  end if
next r
lgRunes = 0
for q = 0 to runeCount() - 1
  if lgRunes < 8 then
    led(144 + 3 * lgRunes) = runeX(q)
    led(145 + 3 * lgRunes) = runeY(q)
    led(146 + 3 * lgRunes) = runeKind(q)
    lgRunes = lgRunes + 1
  end if
next q
lgFlag = 0
for o = 0 to 15
  if led(o) >= 6 and led(16 + o) <= worldTick then
    led(o) = led(o) - 6
    led(16 + o) = worldTick + 480
  end if
  if led(16 + o) > worldTick then lgFlag = 1
next o
holdX = riverWest - 16
curveMinX = 8
curveMaxX = riverWest - 1
if selfTeam = 1 then
  holdX = riverEast + 16
  curveMinX = riverEast + 1
  curveMaxX = 119
end if
dropDx = 0
dropOn = 1
for h = 0 to hookCount() - 1
  if hookTeam(h) <> selfTeam then dropOn = 0
next h
if dropOn = 1 then dropDx = 8
if deepOn = 1 and selfLayer = selfTeam then
  kx(97, deepHold)
  if deepHold = 1 then dropDx = 8
end if
if lgFlag = 1 then
  kx(96, 1)
  dropDx = dropDx + 14
end if
holdX = holdX - dropDx * (1 - 2 * selfTeam)
originX = selfX
originY = selfY
thrown = 0
blinked = 0
attacking = 0
rescueRequest = 0
free = 0
if selfLayer = selfTeam and selfHooked = 0 and recovering = 0 and threat < 0 and fleeRot = 0 then free = 1
if free = 1 and (ownRescue = 1 or worldTick < rescueUntil) and trajHook < 0 then
  curveActive = 0
  walkTo(selfX, selfY)
  end
end if
if foreignRot = 0 and hookReady = 1 and free = 1 then
  for i = 0 to count - 1
    if alive(i) = 1 and team(i) = selfTeam and ids(i) <> selfId then
      if allyNeedsRescue(ids(i)) = 1 then
        rescueRequest = 1
        shotBranch$ = "rescue"
        shotSlot = -1
        throwAt(px(i), py(i), ids(i))
        rescueRequest = 0
        if shotAccepted = 1 then
          rescueUntil = worldTick + 12
          if trajHook < 0 then
            curveActive = 0
            walkTo(selfX, selfY)
            end
          end if
        end if
      end if
    end if
  next i
end if
if selfHooked = 1 and hookReady = 1 and carried(me) = 2 - selfTeam then
  kx(10, 1)
  ccX = 119 - 111 * selfTeam
  ccY = selfY
  for h = 0 to hookCount() - 1
    if hookVictim(h) = selfId and hookTeam(h) <> selfTeam then
      for i = 0 to count - 1
        if ids(i) = hookOwner(h) and alive(i) = 1 then
          ccX = px(i)
          ccY = py(i)
        end if
      next i
    end if
  next h
  shotBranch$ = "cut"
  shotSlot = -1
  throwAt(ccX, ccY, 0)
end if
if selfHooked = 1 and hookReady = 1 and selfLayer = selfTeam and target >= 0 and targetD2 <= reach * reach then
  tdx = px(target) - originX
  tdy = py(target) - originY
  root(tdx * tdx + tdy * tdy)
  tLen = rootValue
  heldHit = -1
  heldSpeed = 60 + 3 * speedLevel
  heldTrav = 0
  heldTick = 9
  heldR2 = 275 + 125 * scr5 \ 10
  if selfBuff = 4 then heldR2 = heldR2 * 3 \ 2
  heldR2 = (heldR2 + 360) * (heldR2 + 360)
  while tLen > 0 and heldHit < 0 and heldTrav < reach * 100
    heldSpeed = heldSpeed + 3
    if heldSpeed > 180 then heldSpeed = 180
    heldTrav = heldTrav + heldSpeed
    heldTick = heldTick + 1
    stepX = originX * 100 + tdx * heldTrav \ tLen
    stepY = originY * 100 + tdy * heldTrav \ tLen
    for j = 0 to count - 1
      if alive(j) = 1 and shield(j) = 0 and ids(j) <> selfId and (team(j) = selfTeam or j = target) then
        twx = px(j) * 100 + vx(j) * 100 * heldTick \ 8 - stepX
        twy = py(j) * 100 + vy(j) * 100 * heldTick \ 8 - stepY
        if twx > -2000 and twx < 2000 and twy > -2000 and twy < 2000 then
          if twx * twx + twy * twy <= heldR2 then
            if team(j) = selfTeam or heldHit < 0 then heldHit = j
          end if
        end if
      end if
    next j
  wend
  if heldHit = target then
    shotBranch$ = "held"
    shotSlot = target
    throwAt(px(target), py(target), 0)
  end if
end if
if selfHooked = 1 then
  curveActive = 0
  end
end if
if blinkReady = 1 then
  scr1 = selfX
  scr2 = selfY
  crossing = 0
  if selfLayer = 2 then
    scr1 = riverWest
    if selfTeam = 1 then scr1 = riverEast
  elseif selfLayer <> selfTeam and selfY >= 56 and selfY <= 72 and (recovering = 1 or targetD2 > 144) then
    half = 11 - 6 * (256 - (selfY - 64) * (selfY - 64)) \ 256
    scr1 = 64 - half - 2
    if selfTeam = 1 then scr1 = 64 + half + 2
    crossing = 1
  elseif threat >= 0 then
    scr1 = selfX - 14
    if selfLayer = 1 then scr1 = selfX + 14
    scr2 = selfY + 14 * dodgeSide
  end if
  if scr1 < 8 then scr1 = 8
  if scr1 > 119 then scr1 = 119
  if scr2 < 8 then scr2 = 8
  if scr2 > 119 then scr2 = 119
  if crossing = 1 then
    scr3 = 0
    if (scr1 - selfX) * (scr1 - selfX) + (scr2 - selfY) * (scr2 - selfY) > 400 then scr3 = 1
    for i = 0 to count - 1
      if alive(i) = 1 and ids(i) <> selfId then
        if rot(i) = 1 and (px(i) - scr1) * (px(i) - scr1) + (py(i) - scr2) * (py(i) - scr2) <= 144 then scr3 = 1
        if layer(i) <> selfLayer then
          disk(selfX, selfY, scr1, scr2, px(i), py(i), 4)
          if diskHit = 1 then scr3 = 1
        end if
      end if
    next i
    for obj = 0 to objectCount() - 1
      if objectKind(obj) = 2 then
        disk(selfX, selfY, scr1, scr2, objectX(obj), objectY(obj), 4)
        if diskHit = 1 then scr3 = 1
      end if
    next obj
    if scr3 = 1 then
      scr1 = selfX
      scr2 = selfY
    end if
  end if
  if scr1 <> selfX or scr2 <> selfY then
    blinked = blinkTo(scr1, scr2)
    if blinked = 1 then
      originX = objectX(selfObject)
      originY = objectY(selfObject)
    end if
  end if
end if

if free = 1 and foreignRot = 0 and hookReady = 1 then
  pairAlly = -1
  scr5 = -1
  pairHp = 100001
  pairDistance = 2147483647
  for i = 0 to count - 1
    if alive(i) = 1 and team(i) = selfTeam and ids(i) <> selfId and shield(i) = 0 and caught(i) = 0 then
      for j = 0 to count - 1
        if alive(j) = 1 and team(j) <> selfTeam and shield(j) = 0 and caught(j) = 0 and layer(i) = layer(j) then
          d2 = (px(i) - px(j)) * (px(i) - px(j)) + (py(i) - py(j)) * (py(i) - py(j))
          midX = (px(i) + px(j)) \ 2
          midY = (py(i) + py(j)) \ 2
          aimD2 = (midX - selfX) * (midX - selfX) + (midY - selfY) * (midY - selfY)
          allyD2 = (px(i) - selfX) * (px(i) - selfX) + (py(i) - selfY) * (py(i) - selfY)
          fraction = hp(i) * 1000 \ peak(i)
          if d2 <= 30 and aimD2 <= reach * reach then
            if fraction < pairHp or (fraction = pairHp and allyD2 < pairDistance) then
              pairAlly = i
              scr5 = j
              pairHp = fraction
              pairDistance = allyD2
            end if
          end if
        end if
      next j
    end if
  next i
  shotBranch$ = "pair"
  shotSlot = scr5
  if pairAlly >= 0 then throwAt((px(pairAlly) + px(scr5)) \ 2, (py(pairAlly) + py(scr5)) \ 2, ids(pairAlly))
end if
shotBranch$ = "close"
shotSlot = target
if target >= 0 and targetD2 <= 400 and selfLayer <> 2 then throwAt(px(target), py(target), 0)
if catchTarget >= 0 then
  reeler = catchTarget
  for h = 0 to hookCount() - 1
    if hookVictim(h) = ids(catchTarget) then
      for i = 0 to count - 1
        if ids(i) = hookOwner(h) then reeler = i
      next i
    end if
  next h
  shotBranch$ = "catch"
  shotSlot = catchTarget
  throwAt((px(catchTarget) + px(reeler)) \ 2, (py(catchTarget) + py(reeler)) \ 2, 0)
end if
shotBranch$ = "intercept"
shotSlot = -1
if threat >= 0 and threatD2 <= 196 then throwAt(hookX(threat), hookY(threat), 0)
shotBranch$ = "swimmer"
shotSlot = scr4
if scr4 >= 0 then throwAt(px(scr4), py(scr4), 0)

if free = 1 and foreignRot = 0 and catchTarget < 0 and scr4 < 0 and thrown = 0 and hookReady = 1 then
  for i = 0 to count - 1
    safe(i) = 0
    if alive(i) = 1 and team(i) = selfTeam and layer(i) = selfTeam and caught(i) = 0 and shield(i) = 0 and rot(i) = 0 and carried(i) = 0 then
      safe(i) = 1
      for j = 0 to count - 1
        if alive(j) = 1 and team(j) <> selfTeam then
          d2 = (px(i) - px(j)) * (px(i) - px(j)) + (py(i) - py(j)) * (py(i) - py(j))
          if d2 <= 784 then safe(i) = 0
        end if
      next j
      for h = 0 to hookCount() - 1
        if hookTeam(h) <> selfTeam then
          d2 = (px(i) - hookX(h)) * (px(i) - hookX(h)) + (py(i) - hookY(h)) * (py(i) - hookY(h))
          if d2 <= 784 then safe(i) = 0
        end if
      next h
    end if
  next i
  healer = -1
  recipient = -1
  healHp = 100001
  healD2 = 2147483647
  for i = 0 to count - 1
    if safe(i) = 1 and peak(i) - hp(i) >= 120 then
      for j = 0 to count - 1
        if j <> i and safe(j) = 1 and air(j) = 0 and hp(j) * 100 >= peak(j) * 60 then
          d2 = (px(i) - px(j)) * (px(i) - px(j)) + (py(i) - py(j)) * (py(i) - py(j))
          forward = px(j) - px(i)
          if selfTeam = 1 then forward = 0 - forward
          fraction = hp(i) * 1000 \ peak(i)
          if d2 >= 16 and d2 <= 576 and forward <= 4 then
            if fraction < healHp or (fraction = healHp and d2 < healD2) then
              healer = j
              recipient = i
              healHp = fraction
              healD2 = d2
            end if
          end if
        end if
      next j
    end if
  next i
  if healer = me and selfBuff = 4 then kx(82, 1)
  if healer = me and selfBuff <> 4 then
    shotBranch$ = "heal"
    shotSlot = -1
    throwAt(px(recipient), py(recipient), ids(recipient))
    if shotAccepted = 1 then
      rescueUntil = worldTick + 12
      if trajHook < 0 then
        curveActive = 0
        walkTo(selfX, selfY)
        end
      end if
    end if
  end if
end if
lt = target
ltOk = 0
if target >= 0 and targetD2 <= (reach + clearance) * (reach + clearance) then ltOk = 1
if ltOk = 1 and hookReady = 1 and thrown = 0 then
  if lr(ids(target) mod 16) >= 20 and ids(target) < 16 then
    lpS = -1
    lpR = (lr(16 + ids(target)) + 2) * 1000 \ (lr(ids(target)) + 25)
    for j = 0 to count - 1
      if j <> target and alive(j) = 1 and team(j) <> selfTeam and shield(j) = 0 and ids(j) < 16 then
        if lr(ids(j)) >= 20 then
          lpD = (px(j) - selfX) * (px(j) - selfX) + (py(j) - selfY) * (py(j) - selfY)
          if lpD * 100 <= targetD2 * 132 and lpD <= (reach + clearance) * (reach + clearance) then
            if (lr(16 + ids(j)) + 2) * 1000 \ (lr(ids(j)) + 25) > lpR then
              lpS = j
              lpR = (lr(16 + ids(j)) + 2) * 1000 \ (lr(ids(j)) + 25)
            end if
          end if
        end if
      end if
    next j
    if lpS >= 0 then
      kx(89, 1)
      lt = lpS
    end if
  end if
end if
if ltOk = 1 then
  scr4 = px(lt) - selfX
  if scr4 < 0 then scr4 = 0 - scr4
  spanY = py(lt) - selfY
  if spanY < 0 then spanY = 0 - spanY
  if spanY > scr4 then scr4 = spanY
  shotBranch$ = "lead"
  shotSlot = lt
  throwAt(px(lt) + vx(lt) * scr4 \ (36 + speedLevel), py(lt) + vy(lt) * scr4 \ (36 + speedLevel), 0)
end if
if thrown = 0 and hookReady = 1 and selfHooked = 0 and selfLayer <> 2 and selfBuff <> 4 then
  mcX = -1
  for h = 0 to hookCount() - 1
    o = hookOwner(h)
    if hookTeam(h) <> selfTeam and hookFlying(h) = 1 and o >= 0 and o < 16 and mcX < 0 then
      if trk(68 + o) = worldTick and trk(119 + o) = 0 then
        tdx = hookX(h) - trk(o)
        tdy = hookY(h) - trk(17 + o)
        tLen = tdx * tdx + tdy * tdy
        if tLen >= 9 then
          root(tLen)
          for i = 0 to count - 1
            if alive(i) = 1 and team(i) = selfTeam and ids(i) <> selfId and shield(i) = 0 and mcX < 0 then
              twx = px(i) - hookX(h)
              twy = py(i) - hookY(h)
              tAlong = twx * tdx + twy * tdy
              tDist = tdx * twy - tdy * twx
              if tAlong > 0 and tDist * tDist <= 64 * tLen and (px(i) - selfX) * (px(i) - selfX) + (py(i) - selfY) * (py(i) - selfY) <= reach * reach then
                j = 12
                while j * rootValue <= tAlong and mcX < 0
                  d2 = hookX(h) + tdx * j \ rootValue
                  aimD2 = hookY(h) + tdy * j \ rootValue
                  if (d2 - selfX) * (d2 - selfX) + (aimD2 - selfY) * (aimD2 - selfY) <= (j - 11) * (j - 11) then
                    mcX = d2
                    mcY = aimD2
                  end if
                  j = j + 4
                wend
              end if
            end if
          next i
        end if
      end if
    end if
  next h
  if mcX >= 0 then
    kx(26, 1)
    shotBranch$ = "matecut"
    shotSlot = -1
    throwAt(mcX, mcY, 0)
  end if
end if
if selfLayer <> 2 then
  for r = 0 to runeCount() - 1
    runeDx = runeX(r) - selfX
    runeDy = runeY(r) - selfY
    shotBranch$ = "rune"
    shotSlot = -1
    if selfBuff = 4 then
      if runeKind(r) <> 3 and runeKind(r) <> 5 then runeDx = 999
    end if
    if runeDx * runeDx + runeDy * runeDy <= reach * reach then
      runeAimY = runeY(r)
      runeLed = 0
      if runeSoon > 0 then
        root(runeDx * runeDx + runeDy * runeDy)
        runeV = 62 + 3 * speedLevel
        if selfBuff = 5 then runeV = 122 + 6 * speedLevel
        root(runeV * runeV + 600 * rootValue)
        runeV = 9 + (rootValue - runeV) \ 3
        runeDir = 1
        runeEnd = 16
        if runeNextY < 64 then
          runeDir = -1
          runeEnd = 111
        end if
        runeDx = runeEnd + runeDir * (641 - runeSoon) \ 8 - runeAimY
        runeDy = 127 - runeEnd - runeDir * (1281 - runeSoon) \ 8 - runeAimY
        if runeDx * runeDx > runeDy * runeDy then runeDir = 0 - runeDir
        runeAimY = runeAimY + runeDir * (runeV + 4) \ 8
        runeLed = 1
      end if
      throwAt(runeX(r), runeAimY, 0)
    end if
  next r
end if
resHit = 0
if thrown = 0 and hookReady = 1 and target < 0 and selfLayer <> 2 and selfBuff <> 4 and worldTick > 8 and runeSoon > 0 then
  for r = -1 to runeCount() - 1
    runeDir = 1
    if r < 0 then
      runeAimY = runeNextY
      runeDx = runeNextX - selfX
      runeV = runeSoon
      if runeNextY >= 64 then runeDir = -1
      if runeSoon > 96 then runeDx = 999
    else
      runeAimY = runeY(r)
      runeDx = runeX(r) - selfX
      runeEnd = 16
      if runeNextY < 64 then
        runeDir = -1
        runeEnd = 111
      end if
      runeV = runeEnd + runeDir * (641 - runeSoon) \ 8 - runeAimY
      runeEnd = 127 - runeEnd - runeDir * (1281 - runeSoon) \ 8 - runeAimY
      if runeV * runeV > runeEnd * runeEnd then runeDir = 0 - runeDir
      runeV = 0
    end if
    if resHit = 0 and runeDx * runeDx <= (reach - 3) * (reach - 3) then
      root((reach - 3) * (reach - 3) - runeDx * runeDx)
      runeDy = runeAimY - selfY
      runeEnd = 0
      if runeDy > rootValue then
        runeEnd = runeDy - rootValue
        if runeDir = 1 then runeV = 999
      elseif runeDy < 0 - rootValue then
        runeEnd = 0 - rootValue - runeDy
        if runeDir = -1 then runeV = 999
      elseif r >= 0 then
        runeV = 999
      end if
      runeV = runeV + runeEnd * 8
      if runeV <= 96 then
        resHit = 1
      end if
    end if
  next r
end if
if target < 0 and selfLayer <> 2 and worldTick > 8 and resHit = 0 then
  pokeX = riverEast + 8
  if selfTeam = 1 then pokeX = riverWest - 8
  scr4 = selfY
  if lastSeen > 0 then
    age = worldTick - lastSeen
    scr4 = lastY + lastVy * age \ 8
    if age <= 96 then
      pokeX = lastX + lastVx * age \ 8
    else
      pokeX = riverEast + 2
      if selfTeam = 1 then pokeX = riverWest - 2
    end if
  end if
  if selfTeam = 0 then
    if pokeX < riverEast + 1 then pokeX = riverEast + 1
    if pokeX > 113 then pokeX = 113
  else
    if pokeX > riverWest - 1 then pokeX = riverWest - 1
    if pokeX < 14 then pokeX = 14
  end if
  if scr4 < 16 then scr4 = 16
  if scr4 > 111 then scr4 = 111
  shotBranch$ = "poke"
  shotSlot = -1
  throwAt(pokeX, scr4, 0)
end if
if target >= 0 and targetD2 <= 30 and brawl = 1 and fleeRot = 0 and selfLayer <> 2 and chOn = 0 then
  if selfLayer = selfTeam and layer(target) <> selfTeam then kx(2, 1)
  if selfLayer <> selfTeam or layer(target) = selfTeam then attacking = attackTarget(ids(target))
end if

mvWhy = 0
if blinked = 1 then
  curveActive = 0
  end
elseif fleeRot = 1 and (trajHook < 0 or trajD2 >= 100000) then
  moveTo(homeX, selfY + ((worldTick \ 12) mod 2 * 2 - 1) * 8, 1)
elseif trajHook >= 0 then
  trajSide = 1
  if trajCross < 0 then trajSide = -1
  if trajCross = 0 and selfY > 64 then trajSide = -1
  perp(trajDx, trajDy, trajSide)
  o = hookOwner(trajHook)
  if o >= 0 and o < 16 then
    if trajCross * trajCross <= 64 * trajLen then
      trk(136 + o) = trajSide
      if pBlocked = 1 then trk(136 + o) = 0 - trajSide
    elseif trk(136 + o) = 1 or trk(136 + o) = -1 then
      trajSide = trk(136 + o)
      perp(trajDx, trajDy, trajSide)
    end if
    allyMark = 0
    if hookTeam(trajHook) = selfTeam then allyMark = 1
  end if
  if pBlocked = 1 then
    stepX = 0 - stepX
    stepY = 0 - stepY
  end if
  if o >= 0 and o < 16 then
    if allyMark = 0 and trk(119 + o) = 0 and (selfX - trk(o)) * (selfX - trk(o)) + (selfY - trk(17 + o)) * (selfY - trk(17 + o)) >= 2500 then
      stepX = stepX + trajDx * 6 \ rootValue
      stepY = stepY + trajDy * 6 \ rootValue
    end if
  end if
  if selfLayer <> selfTeam then kx(87, 1)
  moveTo(selfX + stepX, selfY + stepY, 2)
elseif chOn = 1 then
  moveTo(homeX, selfY, 7)
elseif threat >= 0 then
  stepX = -2
  if selfTeam = 1 then stepX = 2
  moveTo(selfX + stepX, selfY + dodgeSide * 10, 3)
elseif selfLayer = 2 then
  moveTo(holdX, selfY, 4)
elseif attacking = 1 then
elseif catchTarget >= 0 and recovering = 0 then
  finishX = px(catchTarget)
  if selfTeam = 0 and finishX > holdX then finishX = holdX
  if selfTeam = 1 and finishX < holdX then finishX = holdX
  moveTo(finishX, py(catchTarget), 5)
elseif recovering = 1 or (targetD2 <= 144 and brawl = 0) then
  moveTo(homeX, homeY, 7)
elseif allyPingAge >= 0 and allyPingAge < 96 and allyPingBy <> selfId and teamPingResponder = selfId then
  pingX = allyPingX
  if selfTeam = 0 and pingX > holdX then pingX = holdX
  if selfTeam = 1 and pingX < holdX then pingX = holdX
  moveTo(pingX, allyPingY, 8)
elseif selfInShop = 0 and ((selfGold >= 12 and (itemRank(0) < 5 or itemRank(1) < 5)) or (selfGold >= 6 and selfBuff = 0)) then
  shopX = 22
  if selfTeam = 1 then shopX = 106
  moveTo(shopX, 64, 9)
else
  collector = -1
  collectorD2 = 2147483647
  if runeSoon > 0 and runeSoon <= 256 then
    for i = 0 to count - 1
      if team(i) = selfTeam and alive(i) = 1 and layer(i) = selfTeam and caught(i) = 0 and rot(i) = 0 and hp(i) * 100 >= peak(i) * 40 then
        d2 = (px(i) - runeNextX) * (px(i) - runeNextX) + (py(i) - runeNextY) * (py(i) - runeNextY)
        if d2 < collectorD2 then
          collector = i
          collectorD2 = d2
        end if
      end if
    next i
  end if
  for i = 0 to count - 1
    if team(i) = selfTeam then
      laneRank = 0
      for j = 0 to count - 1
        if team(j) = selfTeam and ids(j) < ids(i) then laneRank = laneRank + 1
      next j
      lanes(i) = 64
      if teamCount > 1 then
        lanes(i) = 40 + 48 * laneRank \ (teamCount - 1)
      end if
    end if
  next i
  if collector >= 0 then
    lanes(collector) = runeNextY
    for i = 0 to count - 1
      if team(i) = selfTeam and i <> collector then
        chosenY = lanes(i)
        chosenDistance = 1000
        for y = 16 to 111 step 4
          available = 1
          for j = 0 to count - 1
            if team(j) = selfTeam and (j = collector or (j < i and j <> collector)) then
              gap = y - lanes(j)
              if gap > -24 and gap < 24 then available = 0
            end if
          next j
          gap = y - lanes(i)
          if gap < 0 then gap = 0 - gap
          if available = 1 and gap < chosenDistance then
            chosenY = y
            chosenDistance = gap
          end if
        next y
        lanes(i) = chosenY
      end if
    next i
  end if
  phase = (worldTick \ 6 + selfId * 7) mod 24
  juke = phase \ 3 - 2
  if phase >= 12 then juke = 6 - phase \ 3
  lineY = lanes(me)
  if worldTick >= nextLaneNote then
    nextLaneNote = worldTick + 2048
    note("lane", "hold", "{""lane"":" + STR$(lanes(me)) + ",""collector"":" + STR$(collector = me) + "}")
  end if
  if collector <> me then lineY = lineY + juke
  if teamCount = 1 and collector < 0 then
    lineY = selfY + juke
    if target >= 0 then lineY = py(target) + juke
  end if
  moveTo(holdX, lineY, 10)
end if
if itemRank(4) > 0 and selfLayer = selfTeam then
  wardX = riverEast + 3
  if selfTeam = 1 then wardX = riverWest - 3
  wardY = selfY
  if wardY > 54 and wardY < 74 then wardY = 50
  if (wardX - selfX) * (wardX - selfX) + (wardY - selfY) * (wardY - selfY) <= 1024 then
    placeWard(wardX, wardY)
  elseif mvWhy = 10 then
    wardStage = riverWest - 5
    if selfTeam = 1 then wardStage = riverEast + 5
    moveTo(wardStage, wardY, 11)
  end if
end if

if selfLayer <> selfTeam or recovering = 1 or attacking = 1 or ownRescue = 1 or worldTick < rescueUntil then
  curveActive = 0
  end
end if
if selfX < curveMinX or selfX > curveMaxX or selfY < 16 or selfY > 111 then
  curveActive = 0
  end
end if
if curveActive = 1 and ownHook < 0 and (curveObserved = 1 or worldTick - curveStarted > 12) then curveActive = 0
if curveActive = 0 and ownHook < 0 and thrown = 1 then
  curveDx = castX - selfX
  curveDy = castY - selfY
  root(curveDx * curveDx + curveDy * curveDy)
  if rootValue > 0 then
    curveVx = 0 - curveDy * 8 \ rootValue
    curveVy = curveDx * 8 \ rootValue
    curveEnd(curveVx, curveVy)
    firstStep = curveStep
    guideX = selfX
    scr1 = 64
    if target >= 0 then
      guideX = px(target)
      scr1 = py(target)
    end if
    scr2 = (curveEndX - guideX) * (curveEndX - guideX) + (curveEndY - scr1) * (curveEndY - scr1)
    curveEnd(0 - curveVx, 0 - curveVy)
    secondDistance = (curveEndX - guideX) * (curveEndX - guideX) + (curveEndY - scr1) * (curveEndY - scr1)
    if curveStep > firstStep or (curveStep = firstStep and secondDistance < scr2) then
      curveVx = 0 - curveVx
      curveVy = 0 - curveVy
    end if
    curveStarted = worldTick
    curveObserved = 0
    curveActive = 1
  end if
end if
if curveActive = 1 and ownHook >= 0 then curveObserved = 1
if threat >= 0 or trajHook >= 0 or foreignRot = 1 or mvWhy < 10 then
  end
end if
if curveActive = 1 then
  curveEnd(curveVx, curveVy)
  if curveStep = 0 then
    curveVx = 0 - curveVx
    curveVy = 0 - curveVy
    curveEnd(curveVx, curveVy)
  end if
  if curveStep > 0 then
    if curveEndY <= 32 or curveEndY >= 95 then kx(69, 1)
    moveTo(curveEndX, curveEndY, 12)
  else
    curveActive = 0
  end if
end if
