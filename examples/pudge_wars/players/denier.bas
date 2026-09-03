' Pudge Wars hook breaker — lives to intercept enemy hooks, stacks
' speed and radius, then punishes exposed catches and drowners.
'
' Rot: blight a close or hooked butcher while HP is above 40% and we
' are not in the river; walk inland out of anyone else's cloud.
'
' See base.bas for the full host API.

if selfPoints > 0 then
  if buyUpgrade(2) = 0 then
    if buyUpgrade(3) = 0 then
      if buyUpgrade(0) = 0 then
        buyUpgrade(1)
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
bestId = 0
bestX = 0
bestY = 0
bestDistance = 2147483647
closeId = 0
closeDistance = 2147483647
saveId = 0
saveX = 0
saveY = 0
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
        if distance < bestDistance then
          bestDistance = distance
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

cutX = 0
cutY = 0
cutId = 0
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
      if cutId = 0 then
        cutId = 1
        cutX = hookX(h)
        cutY = hookY(h)
      end if
      if hookVictim(h) <> 0 then
        cutId = 2
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
  lineX = riverWest + 2
else
  lineX = riverEast - 2
end if
padX = homeX
lineY = homeY
if lineY < 8 then
  lineY = 8
end if
if lineY > 119 then
  lineY = 119
end if

dx = bestX - selfX
if dx < 0 then
  dx = 0 - dx
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
    stayDrink = 0
    if headLayer = 2 then
      stayDrink = 1
    end if
    if drownId <> 0 then
      stayDrink = 1
    end if
    if stayDrink = 0 then
      if selfTeam = 0 then
        flashed = blinkTo(riverWest, selfY)
      else
        flashed = blinkTo(riverEast, selfY)
      end if
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
  mood = 8
  if hookReady = 1 then
    if cutId > 0 then
      hookTo(cutX, cutY)
      mood = 3
    else
      if bestId <> 0 then
        hookTo(bestX, bestY)
        mood = 6
      end if
    end if
  end if
else
if fleeRot = 0 and closeId <> 0 then
  attackTarget(closeId)
  mood = 1
else
  if hookReady = 1 then
    if cutId = 2 then
      hookTo(cutX, cutY)
      mood = 2
    else
      if cutId = 1 then
        hookTo(cutX, cutY)
        mood = 3
      else
        if saveId <> 0 then
          hookTo(saveX, saveY)
          mood = 9
        else
          if headId <> 0 then
            hookTo(headX, headY)
            mood = 4
          else
            if drownId <> 0 then
              hookTo(drownX, drownY)
              mood = 5
            else
              if bestId <> 0 then
                if dx <= 36 then
                  hookTo(bestX, bestY)
                  mood = 6
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

if flashed = 0 then
  if selfLayer <> 2 then
    if selfHooked = 0 then
      if fleeRot = 1 then
        walkTo(padX, lineY)
        if mood = 0 then
          mood = 10
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
    print "chop chop"
  end if
  if mood = 2 then
    print "denied"
  end if
  if mood = 3 then
    print "snip that hook"
  end if
  if mood = 4 then
    print "finish the catch"
  end if
  if mood = 5 then
    print "river tax"
  end if
  if mood = 6 then
    print "punish"
  end if
  if mood = 7 then
    print "watching the line"
  end if
  if mood = 8 then
    print "dodge and hook"
  end if
  if mood = 9 then
    print "got you, hang on"
  end if
  if mood = 10 then
    print "backing off rot"
  end if
end if
