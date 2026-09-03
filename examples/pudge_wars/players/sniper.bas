' Pudge Wars deadeye — holds the waterline, stacks hook distance and
' damage, and only throws at wounded targets in hook range (never brawls).
'
' Rot: only blight a hooked, drowning, or badly wounded butcher already
' in the 8-tile disk; walk inland out of anyone else's cloud.
'
' See base.bas for the full host API.

if selfPoints > 0 then
  if buyUpgrade(1) = 0 then
    if buyUpgrade(0) = 0 then
      if buyUpgrade(3) = 0 then
        buyUpgrade(2)
      end if
    end if
  end if
end if
if selfInShop = 1 then
  if itemRank(1) = 0 then
    buyPower(6)
  else
    if itemRank(0) = 0 then
      buyPower(5)
    else
      if buyPower(3) = 0 then
        if itemRank(2) = 0 then
          buyPower(7)
        else
          if itemRank(3) = 0 then
            buyPower(8)
          else
            if buyPower(6) = 0 then
              buyPower(5)
            end if
          end if
        end if
      end if
    end if
  end if
end if

headId = 0
headX = 0
headY = 0
headLayer = 0
pickId = 0
pickX = 0
pickY = 0
pickScore = 2147483647
saveId = 0
saveX = 0
saveY = 0
preyFinish = 0
foreignRot = 0
index = 0
while index < objectCount()
  id = objectId(index)
  if objectAlive(index) then
    dx = objectX(index) - selfX
    dy = objectY(index) - selfY
    distance = dx * dx + dy * dy
    if objectTeam(index) <> selfTeam then
      if objectKind(index) = 1 then
        if objectRot(index) = 1 then
          if distance <= 64 then
            foreignRot = 1
          end if
        end if
      end if
      if objectShielded(index) = 0 then
        hp = objectHp(index)
        if objectHooked(index) = 1 then
          if headId = 0 then
            headId = id
            headX = objectX(index)
            headY = objectY(index)
            headLayer = objectLayer(index)
          end if
        end if
        if distance >= 400 then
          if distance <= 3600 then
            if hp < pickScore then
              pickScore = hp
              pickId = id
              pickX = objectX(index)
              pickY = objectY(index)
            end if
          end if
        end if
        if objectKind(index) = 1 then
          if distance <= 64 then
            if objectHooked(index) = 1 then
              preyFinish = 1
            end if
            if objectLayer(index) = 2 then
              preyFinish = 1
            end if
            if hp <= 140 then
              preyFinish = 1
            end if
          end if
        end if
      end if
    else
      if id <> selfId then
        if objectRot(index) = 1 then
          if distance <= 64 then
            foreignRot = 1
          end if
        end if
        if objectHooked(index) = 1 or objectLayer(index) = 2 then
          saveId = id
          saveX = objectX(index)
          saveY = objectY(index)
        end if
      end if
    end if
  end if
  index = index + 1
wend

if trackId <> pickId then
  trackId = pickId
  velTick = 0
  evx = 0
  evy = 0
end if
if worldTick - velTick >= 8 then
  if velTick > 0 then
    evx = pickX - pex
    evy = pickY - pey
  end if
  pex = pickX
  pey = pickY
  velTick = worldTick
end if
span = 36
pdx = pickX - selfX
if pdx < 0 then
  pdx = 0 - pdx
end if
pdy = pickY - selfY
if pdy < 0 then
  pdy = 0 - pdy
end if
if pdx > span then
  span = pdx
end if
if pdy > span then
  span = pdy
end if
aimX = pickX + evx * span / 9
aimY = pickY + evy * span / 9
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

phase = (worldTick / 7 + selfId * 13) mod 24
if phase < 12 then
  juke = phase / 4 - 1
else
  juke = 4 - phase / 4
end if
if selfTeam = 0 then
  lineX = riverWest
else
  lineX = riverEast
end if
padX = homeX
lineY = homeY + juke
if lineY < 8 then
  lineY = 8
end if
if lineY > 119 then
  lineY = 119
end if

wantRot = 0
if preyFinish = 1 and selfLayer <> 2 then
  if selfHp * 5 >= selfMaxHp * 2 then
    wantRot = 1
  end if
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
  end if
end if

cutX = -1
cutY = -1
nearX = -1
nearY = -1
ownX = -1
ownY = -1
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
      if hdx * hdx + hdy * hdy <= 484 then
        nearX = hookX(h)
        nearY = hookY(h)
      end if
      if hookVictim(h) <> 0 then
        cutX = hookX(h)
        cutY = hookY(h)
      end if
    else
      if hookOwner(h) = selfId then
        if hookVictim(h) = 0 then
          ownX = hookX(h)
          ownY = hookY(h)
        end if
      end if
    end if
  end if
  h = h + 1
wend

flashed = 0
dodgeFlash = 0
if blinkReady = 1 then
  if selfLayer = 2 then
    if selfTeam = 0 then
      flashed = blinkTo(riverWest, selfY)
    else
      flashed = blinkTo(riverEast, selfY)
    end if
  else
    if nearX >= 0 then
      if nearY > selfY then
        hopY = selfY - 24
      else
        hopY = selfY + 24
      end if
      if hopY < 16 then
        hopY = 16
      end if
      if hopY > 111 then
        hopY = 111
      end if
      if selfTeam = 0 then
        hopX = selfX - 8
        if hopX > riverWest then
          hopX = riverWest
        end if
      else
        hopX = selfX + 8
        if hopX < riverEast then
          hopX = riverEast
        end if
      end if
      flashed = blinkTo(hopX, hopY)
      if flashed = 1 then
        dodgeFlash = 1
      end if
    else
      if ownX >= 0 then
        edx = ownX - selfX
        edy = ownY - selfY
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
          hopX = ownX + edx
          hopY = ownY + edy
          if selfTeam = 0 then
            if hopX > riverWest then
              hopX = riverWest
            end if
          else
            if hopX < riverEast then
              hopX = riverEast
            end if
          end if
          flashed = blinkTo(hopX, hopY)
        end if
      end if
      if flashed = 0 then
        if headId <> 0 then
          if headLayer = 2 then
            flashed = blinkTo(headX, headY)
          else
            cdx = headX - selfX
            if cdx < 0 then
              cdx = 0 - cdx
            end if
            cdy = headY - selfY
            if cdy < 0 then
              cdy = 0 - cdy
            end if
            if cdx > 8 or cdy > 8 then
              if selfTeam = 0 then
                flashed = blinkTo(riverWest, headY)
              else
                flashed = blinkTo(riverEast, headY)
              end if
            end if
          end if
        end if
      end if
    end if
  end if
end if

mood = 0
if dodgeFlash = 1 then
  mood = 4
  if hookReady = 1 then
    if pickId <> 0 then
      hookTo(aimX, aimY)
      mood = 2
    else
      if headId <> 0 then
        hookTo(headX, headY)
        mood = 1
      end if
    end if
  end if
else
if hookReady = 1 then
  if cutX >= 0 then
    hookTo(cutX, cutY)
    mood = 5
  else
    if saveId <> 0 then
      hookTo(saveX, saveY)
      mood = 6
    else
      if headId <> 0 then
        hookTo(headX, headY)
        mood = 1
      else
        if pickId <> 0 then
          if pickScore * 2 <= selfMaxHp then
            hookTo(aimX, aimY)
            mood = 2
          end if
        end if
      end if
    end if
  end if
end if
end if

if flashed = 0 then
  if selfLayer <> 2 then
    if selfHooked = 0 then
      if fleeRot = 1 then
        walkTo(padX, lineY)
        if mood = 0 then
          mood = 7
        end if
      end if
      needCore = 0
      if itemRank(1) = 0 then
        needCore = 1
      end if
      if itemRank(0) = 0 then
        needCore = 1
      end if
      if needCore = 1 then
        if selfGold >= 10 then
          if nearX < 0 then
            walkTo(padX, lineY)
            if mood = 0 then
              mood = 3
            end if
          end if
        end if
      end if
      if fleeRot = 0 then
      if mood <> 3 or needCore = 0 then
        if walkHold <= 0 then
          holdX = lineX
          holdY = lineY
          walkHold = 13
        end if
        walkHold = walkHold - 1
        walkTo(holdX, holdY)
        if mood = 0 then
          mood = 3
        end if
      end if
      end if
    end if
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
    if laneSlot = 1 then
      mineY = selfY - 3
    end if
    placeMine(wallX, mineY)
  end if
end if

if mood <> saidMood then
  saidMood = mood
  if mood = 1 then
    print "reel that one in"
  end if
  if mood = 2 then
    print "long shot"
  end if
  if mood = 3 then
    print "waiting for blood"
  end if
  if mood = 4 then
    print "dodge and hook"
  end if
  if mood = 5 then
    print "snip that hook"
  end if
  if mood = 6 then
    print "got you, hang on"
  end if
  if mood = 7 then
    print "backing off rot"
  end if
end if
