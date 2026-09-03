' Pudge Wars lifeguard — hangs back, stacks hook reach and radius,
' and prioritizes rescues, denies, and ally ping calls over kills.
'
' Rot: blight a close or hooked butcher while HP is above 40% and we
' are not in the river; walk inland out of anyone else's cloud.
'
' See base.bas for the full host API.

if selfPoints > 0 then
  if buyUpgrade(1) = 0 then
    if buyUpgrade(3) = 0 then
      if buyUpgrade(2) = 0 then
        buyUpgrade(0)
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

headId = 0
headX = 0
headY = 0
headLayer = 0
drownId = 0
drownX = 0
drownY = 0
saveId = 0
saveX = 0
saveY = 0
bestId = 0
bestX = 0
bestY = 0
closeId = 0
closeDistance = 2147483647
preyRot = 0
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
        if objectHooked(index) = 1 then
          if headId = 0 then
            headId = id
            headX = objectX(index)
            headY = objectY(index)
            headLayer = objectLayer(index)
          end if
        end if
        if objectLayer(index) = 2 then
          if drownId = 0 then
            drownId = id
            drownX = objectX(index)
            drownY = objectY(index)
          end if
        end if
        if bestId = 0 then
          bestId = id
          bestX = objectX(index)
          bestY = objectY(index)
        end if
        if distance < 36 then
          if distance < closeDistance then
            closeDistance = distance
            closeId = id
          end if
        end if
        if objectKind(index) = 1 then
          if distance <= 64 then
            preyRot = 1
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
        if objectHooked(index) = 1 then
          saveId = id
          saveX = objectX(index)
          saveY = objectY(index)
        end if
        if objectLayer(index) = 2 then
          if saveId = 0 then
            saveId = id
            saveX = objectX(index)
            saveY = objectY(index)
          end if
        end if
      end if
    end if
  end if
  index = index + 1
wend

cutX = 0
cutY = 0
cutVictim = 0
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
      if cutX = 0 then
        cutX = hookX(h)
        cutY = hookY(h)
      end if
      if hookVictim(h) <> 0 then
        cutVictim = 1
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

if selfTeam = 0 then
  lineX = riverWest - 4
else
  lineX = riverEast + 4
end if
padX = homeX
lineY = homeY
if lineY < 8 then
  lineY = 8
end if
if lineY > 119 then
  lineY = 119
end if

wantRot = 0
if preyRot = 1 and selfLayer <> 2 then
  if closeId <> 0 or headId <> 0 then
    if selfHp * 5 >= selfMaxHp * 2 then
      wantRot = 1
    end if
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

mood = 0
if dodgeFlash = 1 then
  mood = 8
  if hookReady = 1 then
    if saveId <> 0 then
      hookTo(saveX, saveY)
      mood = 2
    else
      if cutVictim = 1 then
        hookTo(cutX, cutY)
        mood = 3
      else
        if bestId <> 0 then
          hookTo(bestX, bestY)
          mood = 6
        end if
      end if
    end if
  end if
else
if fleeRot = 0 and closeId <> 0 then
  attackTarget(closeId)
  mood = 1
else
  if hookReady = 1 then
    if saveId <> 0 then
      hookTo(saveX, saveY)
      mood = 2
    else
      if cutVictim = 1 then
        hookTo(cutX, cutY)
        mood = 3
      else
        if allyPingAge >= 0 then
          if allyPingAge < 96 then
            hookTo(allyPingX, allyPingY)
            mood = 4
          end if
        end if
        if mood = 0 then
          if drownId <> 0 then
            hookTo(drownX, drownY)
            mood = 5
          else
            if headId <> 0 then
              hookTo(headX, headY)
              mood = 6
            end if
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
          mood = 9
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
              mood = 7
            end if
          end if
        end if
      end if
      if fleeRot = 0 then
      if mood <> 7 or needCore = 0 then
        walkTo(lineX, lineY)
        if mood = 0 then
          mood = 7
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
    print "keeping them off you"
  end if
  if mood = 2 then
    print "got you, hang on"
  end if
  if mood = 3 then
    print "not today"
  end if
  if mood = 4 then
    print "on your ping"
  end if
  if mood = 5 then
    print "fish them out"
  end if
  if mood = 6 then
    print "secure the catch"
  end if
  if mood = 7 then
    print "covering the back"
  end if
  if mood = 8 then
    print "dodge and hook"
  end if
  if mood = 9 then
    print "backing off rot"
  end if
end if
