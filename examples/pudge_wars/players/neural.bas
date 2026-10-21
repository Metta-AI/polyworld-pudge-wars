' Small tensor MLP example. Package with scripts/build_neural_policy.py.
' The supplied weights are illustrative, not a trained competitive policy.
dim shape(0)
dim observations(5)
if initialized = 0 then
  encoder = tensorLoad("encoder")
  policy = tensorLoad("policy")
  bias = tensorLoad("bias")
  shape(0) = 6
  inputs = tensorCreate("float32", shape)
  hidden = tensorCreate("float32", shape)
  shape(0) = 3
  logits = tensorCreate("float32", shape)
  initialized = 1
end if

target = -1
distance = 2147483647
for i = 0 to objectCount() - 1
  if objectTeam(i) <> selfTeam and objectAlive(i) <> 0 then
    dx = objectX(i) - selfX
    dy = objectY(i) - selfY
    d = dx * dx + dy * dy
    if d < distance then
      distance = d
      target = i
    end if
  end if
next i
observations(0) = selfHp / selfMaxHp
observations(1) = hookReady
observations(2) = 0
observations(3) = selfHooked
observations(4) = selfRot
observations(5) = 1
if target >= 0 then observations(2) = 1
tensorImport(inputs, observations)
tensorDense(inputs, encoder, 0, hidden)
tensorRelu(hidden, hidden)
tensorDense(hidden, policy, bias, logits)
action = tensorArgmax(logits)
if worldTick = 0 then print "Neural policy ready"
if action = 0 then
  walkTo(homeX, homeY)
elseif action = 1 and target >= 0 then
  safeHookTo(objectX(target), objectY(target))
else
  x = riverWest - 1
  if selfTeam = 1 then x = riverEast + 1
  walkTo(x, homeY)
end if
