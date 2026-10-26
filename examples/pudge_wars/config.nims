import "../../src/polyworld/emscripten.nims"

setupEmscripten(thisDir())

when defined(emscripten):
  # The networked follower speaks the browser's WebSocket.
  switch("passL", "-lwebsocket.js")

when defined(emscripten):
  switch("passL", "--preload-file " & thisDir() & "/assets/hookem@/examples/pudge_wars/assets/hookem")
  switch("passL", "--preload-file " & thisDir() & "/players/base.bas@/base.bas")
