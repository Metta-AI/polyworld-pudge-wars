' Jev chooses a posture; BASIC handles movement and hooks between judgments.
' A missing endpoint or failed request keeps the local fallback active.
if request > 0 then
  status = oraclePoll(request)
  if status > 0 then
    posture = oracleAnswer(request, "posture")
    print "Jev posture: ", posture
    request = 0
  elseif status = -1 then
    print "Jev unavailable: ", llmError$(request)
    request = 0
  end if
end if
if worldTick >= nextQuestion and oracleReady() = 0 then
  oracleStateText("game", "Fresh Meat: hook enemies across a river, survive and score team kills.")
  oracleState("self.hp", selfHp)
  oracleState("self.maxHp", selfMaxHp)
  oracleState("self.hookReady", hookReady)
  oracleState("self.kills", selfKills)
  oracleQuestion("posture", 2, "Choose whether this butcher should engage or recover.")
  oracleCriterion("posture", "engage", "Approach the river and hook visible enemies when healthy.")
  oracleCriterion("posture", "recover", "Return home to heal when health is low.")
  request = oracleAsk()
  nextQuestion = worldTick + 480
end if
if posture = 1 or selfHp * 3 < selfMaxHp then
  walkTo(homeX, homeY)
else
  x = riverWest - 1
  if selfTeam = 1 then x = riverEast + 1
  walkTo(x, homeY)
  if hookReady <> 0 then
    for i = 0 to objectCount() - 1
      if objectTeam(i) <> selfTeam and objectAlive(i) <> 0 then
        if safeHookTo(objectX(i), objectY(i)) <> 0 then exit for
      end if
    next i
  end if
end if
