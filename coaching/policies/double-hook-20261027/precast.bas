' Lead a visible teammate hook that is about to catch an exposed enemy.
comboShot = 0
if hookReady = 1 and thrown = 0 and free = 1 and foreignRot = 0 and targetD2 > 400 then
  for comboH = 0 to hookCount() - 1
    if thrown = 0 and hookFlying(comboH) = 1 and hookTeam(comboH) = selfTeam and hookOwner(comboH) <> selfId then
      comboReeler = -1
      for comboI = 0 to count - 1
        if alive(comboI) = 1 and ids(comboI) = hookOwner(comboH) then comboReeler = comboI
      next comboI
      if comboReeler >= 0 then
        comboDx = hookX(comboH) - px(comboReeler)
        comboDy = hookY(comboH) - py(comboReeler)
        root(comboDx * comboDx + comboDy * comboDy)
        comboLen = rootValue
        if comboLen >= 12 then
          root(3600 + 600 * comboLen)
          comboPull = rootValue
          if comboPull > 180 then comboPull = 180
          comboEndX = hookX(comboH) + comboDx * 12 \ comboLen
          comboEndY = hookY(comboH) + comboDy * 12 \ comboLen
          comboVictim = -1
          comboNear = 145
          for comboI = 0 to count - 1
            if alive(comboI) = 1 and team(comboI) <> selfTeam and shield(comboI) = 0 and caught(comboI) = 0 then
              comboDot = (px(comboI) - hookX(comboH)) * comboDx + (py(comboI) - hookY(comboH)) * comboDy
              comboD2 = (px(comboI) - hookX(comboH)) * (px(comboI) - hookX(comboH)) + (py(comboI) - hookY(comboH)) * (py(comboI) - hookY(comboH))
              if comboDot >= 0 and comboD2 < comboNear then
                disk(hookX(comboH), hookY(comboH), comboEndX, comboEndY, px(comboI) + vx(comboI) \ 2, py(comboI) + vy(comboI) \ 2, 5)
                if diskHit = 1 then
                  comboVictim = comboI
                  comboNear = comboD2
                end if
              end if
            end if
          next comboI
          if comboVictim >= 0 then
            root(comboNear)
            comboEta = (rootValue - 4) * 100 \ comboPull
            if comboEta < 0 then comboEta = 0
            comboStartX = px(comboVictim) + vx(comboVictim) * comboEta \ 8
            comboStartY = py(comboVictim) + vy(comboVictim) * comboEta \ 8
            comboDx = px(comboReeler) - comboStartX
            comboDy = py(comboReeler) - comboStartY
            root(comboDx * comboDx + comboDy * comboDy)
            comboLen = rootValue
            comboSpeed = 60 + 3 * speedLevel
            if selfBuff = 5 then comboSpeed = comboSpeed * 2
            comboFlight = 50
            comboTravel = 0
            comboT = 0
            comboFound = 0
            while comboT < 80 and comboTravel < (comboLen - 6) * 100 and comboFound = 0
              comboT = comboT + 1
              if comboT > comboEta then comboTravel = comboTravel + comboPull
              if comboT >= 9 then
                if comboSpeed < 180 then comboSpeed = comboSpeed + 3
                comboFlight = comboFlight + comboSpeed
                comboX = comboStartX + comboDx * comboTravel \ (comboLen * 100)
                comboY = comboStartY + comboDy * comboTravel \ (comboLen * 100)
                root((comboX - originX) * (comboX - originX) + (comboY - originY) * (comboY - originY))
                if comboFlight + 300 >= rootValue * 100 and comboFlight <= reach * 100 then
                  throwAt(comboX, comboY, 0)
                  if shotAccepted = 1 then
                    comboShot = 1
                  end if
                  comboFound = 1
                end if
              end if
            wend
          end if
        end if
      end if
    end if
  next comboH
end if
