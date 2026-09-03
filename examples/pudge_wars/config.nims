import "../../src/polyworld/emscripten.nims"

setupEmscripten(thisDir())

when defined(emscripten):
  # The networked follower speaks the browser's WebSocket.
  switch("passL", "-lwebsocket.js")
