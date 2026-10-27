  comboFound = 0
  if thrown = 0 and hookReady = 1 and selfHooked = 0 and reeler <> catchTarget and reelSpeed(reeler) > 0 and worldTick = reelSeen(reeler) then
    comboDx = px(reeler) - px(catchTarget)
    comboDy = py(reeler) - py(catchTarget)
    root(comboDx * comboDx + comboDy * comboDy)
    comboLen = rootValue
    comboPull = reelSpeed(reeler)
    comboSpeed = 60 + 3 * speedLevel
    if selfBuff = 5 then comboSpeed = comboSpeed * 2
    comboFlight = 50
    comboTravel = 0
    comboT = 0
    while comboT < 80 and comboTravel < (comboLen - 6) * 100 and comboFound = 0
      comboT = comboT + 1
      comboTravel = comboTravel + comboPull
      if comboT >= 9 then
        if comboSpeed < 180 then comboSpeed = comboSpeed + 3
        comboFlight = comboFlight + comboSpeed
        comboX = px(catchTarget) + comboDx * comboTravel \ (comboLen * 100)
        comboY = py(catchTarget) + comboDy * comboTravel \ (comboLen * 100)
        root((comboX - originX) * (comboX - originX) + (comboY - originY) * (comboY - originY))
        if comboFlight + 300 >= rootValue * 100 and comboFlight <= reach * 100 then
          throwAt(comboX, comboY, 0)
          comboFound = 1
        end if
      end if
    wend
  end if
