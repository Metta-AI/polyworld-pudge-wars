' Measure visible hook-head speed over four ticks, retaining the last outbound
' estimate across the catch. Reset samples on phase changes and visibility gaps.
for reelH = 0 to hookCount() - 1
  reelSlot = -1
  for reelI = 0 to count - 1
    if ids(reelI) = hookOwner(reelH) then reelSlot = reelI
  next reelI
  if reelSlot >= 0 then
    reelPhaseNow = hookFlying(reelH)
    if reelSeen(reelSlot) = 0 or worldTick - reelSeen(reelSlot) > 8 then
      reelTick(reelSlot) = worldTick
      reelX(reelSlot) = hookX(reelH)
      reelY(reelSlot) = hookY(reelH)
      reelSpeed(reelSlot) = 0
    elseif reelPhase(reelSlot) <> reelPhaseNow then
      reelTick(reelSlot) = worldTick
      reelX(reelSlot) = hookX(reelH)
      reelY(reelSlot) = hookY(reelH)
    elseif worldTick - reelTick(reelSlot) >= 4 then
      reelDx = hookX(reelH) - reelX(reelSlot)
      reelDy = hookY(reelH) - reelY(reelSlot)
      root((reelDx * reelDx + reelDy * reelDy) * 100)
      reelSpeed(reelSlot) = rootValue * 10 \ (worldTick - reelTick(reelSlot))
      if reelPhaseNow = 1 then reelSpeed(reelSlot) = reelSpeed(reelSlot) + 6
      if reelSpeed(reelSlot) < 60 then reelSpeed(reelSlot) = 60
      if reelSpeed(reelSlot) > 180 then reelSpeed(reelSlot) = 180
      reelTick(reelSlot) = worldTick
      reelX(reelSlot) = hookX(reelH)
      reelY(reelSlot) = hookY(reelH)
    end if
    reelPhase(reelSlot) = reelPhaseNow
    reelSeen(reelSlot) = worldTick
  end if
next reelH
