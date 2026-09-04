## F2 / Fluffy start must not IndexDefect on an empty span stack.

import polyworld/profiles

echo "Testing F2 start inside profileBlock (the mid-game crash)"
profileBlock "frame":
  profileBlock "before":
    discard
  toggleRuntimeTrace()
  profileBlock "simulate":
    discard
  profileBlock "draw":
    discard
  profilePush("worldDraw")
  profilePop()

echo "test_pw_fluffy: all checks passed"
