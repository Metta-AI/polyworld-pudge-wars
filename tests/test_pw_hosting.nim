## The lobby must answer on the LAN address it prints. mummy's serve()
## defaults to localhost, which is how a host can advertise
## http://192.168.x.x:8000/ while the socket only listens on 127.0.0.1.
## The Battle.net-style page is a channel anyone can enter: chat, JOIN
## GAME, and GET /status work without claiming a seat first.

import
  std/[httpclient, json, os, options, strutils, times],
  whisky,
  ../examples/pudge_wars/hosting,
  ../examples/pudge_wars/maps,
  ../examples/pudge_wars/replays,
  ../examples/pudge_wars/sim

const TestPort = 18731'i32

var
  pumpStop = false
  pumpGame: Game

proc pumpLoop() {.thread.} =
  {.gcsafe.}:
    while not pumpStop:
      pumpHosting(pumpGame)
      sleep(5)

proc waitText(ws: WebSocket, timeoutMs: int): JsonNode =
  let deadline = epochTime() + timeoutMs.float / 1000.0
  while epochTime() < deadline:
    let received = ws.receiveMessage(200)
    if received.isNone:
      continue
    let message = received.get()
    if message.kind != TextMessage:
      continue
    try:
      return parseJson(message.data)
    except CatchableError:
      continue
  JsonNode(nil)

echo "Testing the lobby binds the advertised address"
doAssert startHosting(TestPort, "Test", getCurrentDir(), 15, 20),
  "the test lobby server must start"
try:
  let
    url = hostingUrl()
    client = newHttpClient(timeout = 3000)
  defer:
    client.close()
  let response = client.get(url)
  doAssert response.code == Http200,
    "GET " & url & " must return the lobby page"
  doAssert "Fresh Meat" in response.body,
    "GET " & url & " must return the lobby page"
  doAssert "ENTER CHANNEL" in response.body,
    "the lobby must have the Battle.net-style channel gate"
  doAssert "JOIN GAME" in response.body,
    "anyone in the channel must be able to join without picking a slot"
  doAssert response.headers["access-control-allow-origin"] == "*",
    "the lobby page must be fetchable from any origin"

  let statusResponse = client.get(
    "http://127.0.0.1:" & $TestPort & "/status"
  )
  doAssert statusResponse.code == Http200,
    "GET /status must answer"
  let status = parseJson(statusResponse.body)
  doAssert status["host"].getStr() == "Test",
    "/status must name the host"
  doAssert status["t"].getStr() == "lobby",
    "/status must be a lobby snapshot"
  doAssert status["people"].len >= 1,
    "the host must be listed in the channel"

  echo "Testing anyone can enter the channel, chat, and JOIN GAME"
  pumpGame = newGame(generateMap(1), 32, false, ReplayData())
  var pumpThread: Thread[void]
  createThread(pumpThread, pumpLoop)
  let ws = newWebSocket("ws://127.0.0.1:" & $TestPort & "/ws")
  try:
    ws.send($(%*{"t": "hello", "name": "Ana"}), TextMessage)
    var granted = false
    var heardChat = false
    var sawPeople = false
    let deadline = epochTime() + 4.0
    while epochTime() < deadline and (not granted or not heardChat or not sawPeople):
      let node = waitText(ws, 500)
      if node.isNil:
        continue
      let kind = node{"t"}.getStr()
      if kind == "lobby":
        for person in node["people"]:
          if person["name"].getStr() == "Ana":
            sawPeople = true
        if not granted:
          ws.send($(%*{"t": "join"}), TextMessage)
          ws.send($(%*{"t": "chat", "text": "glhf"}), TextMessage)
      elif kind == "grant":
        doAssert node["slot"].getInt() >= 0,
          "JOIN GAME must claim an open seat"
        granted = true
      elif kind == "chat" and node{"text"}.getStr() == "glhf":
        heardChat = true
    doAssert sawPeople, "a joiner must appear in the channel list"
    doAssert granted, "JOIN GAME must grant a seat"
    doAssert heardChat, "channel chat must echo to the sender"
  finally:
    ws.close()
    pumpStop = true
    joinThread(pumpThread)
  doAssert pumpGame.humanPaced, "a claimed LAN seat enables human-paced play"
  pumpHosting(pumpGame)
  doAssert pumpGame.humanPaced, "a disconnect must not accelerate the match"
finally:
  stopHosting("test done")

echo "test_pw_hosting: all checks passed"
