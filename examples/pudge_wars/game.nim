## Fresh Meat match setup, command line, and the headless runner.

import
  std/[os, strformat, strutils, tables],
  polyworld/[cli, profiles, tapes],
  content,
  maps,
  sim,
  bots,
  practice,
  hybrid,
  replays,
  netclient,
  netsim,
  netpredict

when defined(headless):
  import std/[times, monotimes]
  import branch

type
  NetRole* = enum
    ## How this process relates to a match.
    NetOff,   ## Ordinary local simulation.
    NetHost,  ## Runs the authoritative sim and serves remote clients.
    NetClient ## Follows a host's action tape over the network.

proc usage() =
  echo "Fresh Meat"
  echo "  --bot:PATH              Fill butcher slots with that script."
  echo "  --bot:PATH:N            Fill N slots with that file."
  echo "  --bot PATH[:N]          The equivalent two-argument form."
  echo "  --human[:SLOT]          A human drives one slot (0-based;"
  echo "                          default the first free slot)."
  echo "                          Repeatable. Bots fill the rest."
  echo "  --team-size N           N vs N, N=1..5 (default 3). Spawns"
  echo "                          2N butchers. --duel is still the"
  echo "                          ladder 1v1 (slot 1 of the 3-lane pads)."
  echo "  --duel                  1v1 mode: one butcher a side on the"
  echo "                          middle lane. Bots default to"
  echo "                          players/challenger.bas; first to " &
    $DuelKillGoal & "."
  echo "  --duellog DIR           Write per-match analysis logs (events"
  echo "                          .jsonl, summary.json, history.jsonl)"
  echo "                          under DIR. Defaults to duels/ in duel"
  echo "                          mode; also works for NvN and replays."
  echo "  --replay PATH           Play an action replay instead of bots."
  echo "  --branch PATH           Headless: score decision windows of a"
  echo "                          recorded match by counterfactual rollout"
  echo "                          (see --branch-ticks, --branch-slot)."
  echo "  --branch-ticks T,T,...  Window ticks to branch at."
  echo "  --branch-slot N         Traced seat (0-based)."
  echo "  --branch-options A,B    Option ids to score (default every"
  echo "                          eligible one plus none)."
  echo "  --horizon TICKS         Rollout length (default " &
    $(5 * TickRate) & ")."
  echo "  --branch-seeds N        Rollouts per option (default 1)."
  echo "  --branch-out PATH       JSONL output (default stdout)."
  echo "  --branch-teachers A,B   Scripts asked what they would do at"
  echo "                          each window (one teacher row each)."
  echo "  --branch-bot PATH       Script for the other seats after the"
  echo "                          branch (default players/base.bas)."
  echo "  --record PATH           Record match actions to a replay."
  echo "  --seconds NUMBER        Duration in seconds (default 1200)."
  echo "  --minutes NUMBER        Duration in minutes (default 20)."
  echo "  --ticks NUMBER          Duration in ticks (default 38400)."
  echo "  --seed NUMBER           Live game map seed."
  echo "  --killGoal NUMBER       First team to NUMBER kills wins" &
    " (default " & $KillGoal & ")."
  echo "  --botEvery NUMBER       Bots decide every NUMBER ticks" &
    " (default 1)."
  echo "  --botAimNoise NUMBER    Bot hook aim scatter in tiles" &
    " (default 0)."
  echo "  --runes NUMBER          Seconds between river rune drops" &
    " (default " & $(RunePeriodTicks div TickRate) &
    "; public north/south + kind cycle; 0 disables)."
  echo "  --difficulty NAME       Bot preset: easy, fair, or pro."
  echo "  --practice              Jev practice coach on the human seat:"
  echo "                          live cues on the HUD (P hides them) and a"
  echo "                          decision trace per match."
  echo "  --hybrid:SLOT           BASIC plays continuously; D1 advises target,"
  echo "                          lane and aggression (--coach local|none)."
  echo "  --hybrid-delay-ticks N  Minimum observation-to-application delay."
  echo "  --hybrid-plan PATH      Replay a tactical intervention JSON array"
  echo "                          without inference (one hybrid seat only)."
  echo "  --tactical-shadow:SLOT Record tactical windows without controlling"
  echo "                          this human or BASIC seat (for coaching)."
  echo "  --practice-dir DIR      Where practice traces go (default the"
  echo "                          user data dir)."
  echo "  --coach NAME|URL        Decision model for the coach and pilots:"
  echo "                          jev (TypeSafe, default), d1 (Liquid),"
  echo "                          local (sidecar on 127.0.0.1:8765), or a"
  echo "                          base URL. Keys: typesafe.key, liquid.key."
  echo "  --coach-model NAME      Model name for that endpoint."
  echo "  --shadow[:SLOT]         Record a script seat as a teacher trace"
  echo "                          (bot-SLOT/ beside the match; bare = every"
  echo "                          script seat)."
  echo "  --pilot-noise P         Pilots execute a random eligible option"
  echo "                          instead of the cue with chance P (0..1)."
  echo "  --asks periodic         Open decision windows on the heartbeat only"
  echo "                          (default: also on contact, hooks, deaths)."
  echo "  --thresholds PATH       Fitted confidence thresholds for cues and"
  echo "                          pilots (default <data dir>/thresholds.json;"
  echo "                          --thresholds:off keeps the constants)."
  echo "  --pilot[:SLOT]          The decision model drives one slot"
  echo "                          through the human intent path and"
  echo "                          records a pilot trace. Repeatable."
  echo "  --quickcast             Hook casts on key press at the cursor."
  echo "  --autocast              Meat Hook autocast: RMB an enemy throws."
  echo "  --keys PATH             Key bindings file (action = KeyName)."
  echo "  --mute                  Start with the sound off (default; M toggles)."
  echo "  --sound                 Start with the sound on."
  echo "  --play=false            Start the graphical transport paused."
  echo "  --speed NUMBER          Graphical start speed: 1, 2, 4, or 16."
  echo "  --windowSize WxH        Graphical window, such as 1024x576."
  echo "  --windowPos X,Y         Place the window at screen point X,Y (top-left)."
  echo "  --vsync:off             Unlock the frame rate (default on)."
  echo "  --host                  Serve a lobby so friends can join over"
  echo "                          the network (needs bots on all 2N seats;"
  echo "                          fills them with base.bas when unset)."
  echo "  --port NUMBER           Lobby port for --host (default 8000)."
  echo "  --autostart             Skip the lobby: the hosted match runs"
  echo "                          at once and joiners drop in mid-game."
  echo "  --join URL              Join a hosted match, for example"
  echo "                          ws://192.168.1.10:8000/ws"
  echo "  --slot NUMBER           Seat to request when joining (1-10;"
  echo "                          default spectate)."
  echo "  --name TEXT             Your player name for networked play."
  echo "  --label TEXT            Nameplate for the next seat (repeat"
  echo "                          once per butcher; coworld / replay)."
  echo "  --token TEXT            Seat token from the lobby page (the"
  echo "                          browser client passes this itself)."
  echo "  --netsim SPEC           Dev network sim on the follower:"
  echo "                          local|good|poor|extreme|off, or"
  echo "                          100+/-50 or 250+/-40,loss=2 (NETSIM.md)."
  echo "  --netsim-latency MS     One-way delay; overrides --netsim."
  echo "  --netsim-jitter MS      +/- variation around latency."
  echo "  --netsim-loss PERCENT   Outbound packet loss 0..100."
  echo "Compile with -d:headless for command-line simulation."
  echo "Compile with -d:emscripten for the web backend."

proc takePwDurationFlag(
    options: var GameOptions,
    arguments: seq[string],
    index: var int,
    argument: string
): bool =
  ## `--seconds` / `--minutes` / `--ticks` at this game's 32 Hz tick rate.
  var
    name = ""
    text = ""
  if argument.startsWith("--seconds="):
    name = "--seconds"
    text = argument[10 .. ^1]
  elif argument.startsWith("--minutes="):
    name = "--minutes"
    text = argument[11 .. ^1]
  elif argument.startsWith("--ticks="):
    name = "--ticks"
    text = argument[8 .. ^1]
  else:
    case argument
    of "--seconds", "--minutes", "--ticks":
      name = argument
      text = arguments.argumentValue(index, argument)
    else:
      return false
  let count = parsePositiveInt32(text, name)
  var ticks = int64(count)
  case name
  of "--seconds":
    ticks = int64(count) * int64(TickRate)
  of "--minutes":
    ticks = int64(count) * 60'i64 * int64(TickRate)
  of "--ticks":
    discard
  else:
    return false
  if ticks > int32.high:
    fail(name & " is too large")
  options.maximumTicks = int32(ticks)
  options.seconds = options.maximumTicks div TickRate
  true

proc addHumanSlot(options: var GameOptions, text: string) =
  ## Adds one human seat: an explicit slot index or the first free one.
  var slot = -1'i32
  if text.len > 0:
    slot = parseInt32(text, "--human")
    if slot < 0 or slot >= MaxPudgeCount:
      fail("--human slot must be between 0 and " & $(MaxPudgeCount - 1))
  else:
    for candidate in 0'i32 ..< int32(MaxPudgeCount):
      if candidate notin options.humanSlots:
        slot = candidate
        break
    if slot < 0:
      fail("every slot already has a human")
  if slot in options.humanSlots:
    fail("slot " & $slot & " already has a human")
  options.humanSlots.add slot

proc addPilotSlot(options: var GameOptions, text: string) =
  ## Adds one model-driven seat: an explicit slot or the first free one.
  var slot = -1'i32
  if text.len > 0:
    slot = parseInt32(text, "--pilot")
    if slot < 0 or slot >= MaxPudgeCount:
      fail("--pilot slot must be between 0 and " & $(MaxPudgeCount - 1))
  else:
    for candidate in 0'i32 ..< int32(MaxPudgeCount):
      if candidate notin options.humanSlots and
          candidate notin options.pilotSlots:
        slot = candidate
        break
    if slot < 0:
      fail("every slot already has a human or pilot")
  if slot in options.humanSlots or slot in options.pilotSlots:
    fail("slot " & $slot & " already has a human or pilot")
  options.pilotSlots.add slot

proc applyDifficulty(options: var GameOptions, name: string) =
  ## Bot handicap presets; explicit knob flags given later still win.
  case name.strip().toLowerAscii()
  of "easy":
    options.botEvery = 16
    options.botAimNoise = 2
  of "fair":
    options.botEvery = 8
    options.botAimNoise = 1
  of "pro":
    options.botEvery = 1
    options.botAimNoise = 0
  else:
    fail("--difficulty must be easy, fair, or pro")

proc findStockBot(): string =
  ## Default autopilot policy for empty seats.
  for candidate in [
    "examples/pudge_wars/players/base.bas",
    "players/base.bas"
  ]:
    if fileExists(candidate):
      return candidate
  fail(
    "need players/base.bas (run from the repo root) or an explicit --bot PATH"
  )

proc findChallengerScript(): string =
  ## The evolving duel policy, looked up from the repo root or the
  ## example directory.
  for candidate in [
    "examples/pudge_wars/players/challenger.bas",
    "players/challenger.bas"
  ]:
    if fileExists(candidate):
      return candidate
  fail(
    "--duel needs players/challenger.bas (run from the repo root) " &
    "or an explicit --bot PATH"
  )

when defined(headless):
  var branchOptions*: BranchOptions
    ## `--branch`: score recorded decision windows instead of playing.

var
  thresholdsPath* = ""
    ## `--thresholds PATH`: fitted confidence thresholds for the coach
    ## and pilots. Empty reads `<data dir>/thresholds.json` when present.
  thresholdsOff* = false
    ## `--thresholds:off`: keep the built-in constants.

var
  pilotNoise* = 0.0
  hybridSlots*: seq[int]
  tacticalShadowSlots*: seq[int]
  hybridDelay* = 0'i32
  hybridPlan* = ""
  shadowSlots*: seq[int32]
    ## `--shadow:SLOT`: script seats recorded as teacher traces.
  shadowAll* = false
    ## `--shadow`: every script seat.
    ## `--pilot-noise P`: chance per window that a pilot executes a random
    ## eligible option instead of its cue (mistake coverage for traces).

proc takeThresholdFlag(arguments: seq[string], index: var int,
    argument: string): bool =
  if argument.startsWith("--tactical-shadow:"):
    let slot = int(parseInt32(argument[18 .. ^1], "--tactical-shadow"))
    if slot notin tacticalShadowSlots: tacticalShadowSlots.add slot
  elif argument.startsWith("--hybrid:"):
    let slot = int(parseInt32(argument[9 .. ^1], "--hybrid"))
    if slot notin hybridSlots: hybridSlots.add slot
  elif argument == "--hybrid-delay-ticks":
    hybridDelay = parseInt32(arguments.argumentValue(index, argument), argument)
    if hybridDelay < 0: fail("--hybrid-delay-ticks must be nonnegative")
  elif argument == "--hybrid-plan":
    hybridPlan = arguments.argumentValue(index, argument)
  elif argument == "--shadow":
    shadowAll = true
  elif argument.startsWith("--shadow:"):
    shadowSlots.add parseInt32(argument[9 .. ^1], "--shadow")
  elif argument == "--pilot-noise":
    pilotNoise = parseFloat(arguments.argumentValue(index, "--pilot-noise"))
  elif argument.startsWith("--pilot-noise="):
    pilotNoise = parseFloat(argument[14 .. ^1])
  elif argument == "--asks":
    askEvents = arguments.argumentValue(index, "--asks") != "periodic"
  elif argument.startsWith("--asks="):
    askEvents = argument[7 .. ^1] != "periodic"
  elif argument == "--thresholds":
    thresholdsPath = arguments.argumentValue(index, "--thresholds")
  elif argument.startsWith("--thresholds="):
    thresholdsPath = argument[13 .. ^1]
  elif argument == "--thresholds:off":
    thresholdsOff = true
  else:
    return false
  true

proc takeBranchFlag(options: var GameOptions, arguments: seq[string],
    index: var int, argument: string): bool =
  ## Handles one answer-key flag. The tape also becomes --replay so the
  ## ordinary replay game is built for the rollouts to clone.
  when defined(headless):
    template value(name: string): string =
      arguments.argumentValue(index, name)
    case argument
    of "--branch":
      branchOptions.path = value("--branch")
      options.replayPath = branchOptions.path
    of "--branch-ticks":
      branchOptions.ticks = parseTicks(value("--branch-ticks"))
    of "--branch-slot":
      branchOptions.slot = int(parseInt32(value("--branch-slot"), "--branch-slot"))
    of "--branch-options":
      for part in value("--branch-options").split(','):
        if part.strip().len > 0:
          branchOptions.options.add part.strip()
    of "--horizon":
      branchOptions.horizon = parsePositiveInt32(value("--horizon"), "--horizon")
    of "--branch-seeds":
      branchOptions.seeds = int(parsePositiveInt32(value("--branch-seeds"), "--branch-seeds"))
    of "--branch-out":
      branchOptions.outPath = value("--branch-out")
    of "--branch-teachers":
      for part in value("--branch-teachers").split(','):
        if part.strip().len > 0:
          branchOptions.teachers.add part.strip()
    of "--branch-bot":
      branchOptions.botPath = value("--branch-bot")
    else:
      return false
    true
  else:
    false

proc parseGameOptions(): GameOptions =
  # killGoal and duration start unset (zero) so duel mode can pick its
  # own defaults after the flags are read.
  result = GameOptions(
    seed: 2026,
    speed: 1,
    windowWidth: 1024,
    windowHeight: 576,
    botEvery: 1,
    runeSeconds: -1,
    joinSlot: -1,
    mute: true
  )
  var
    netsimSpec = ""
    netsimHasLatency = false
    netsimHasJitter = false
    netsimHasLoss = false
    netsimLatency = 0
    netsimJitter = 0
    netsimLoss = 0.0
  let arguments = commandLineParams()
  var index = 0
  while index < arguments.len:
    let argument = arguments[index]
    if result.takePwDurationFlag(arguments, index, argument):
      discard
    elif result.takeBranchFlag(arguments, index, argument):
      discard
    elif takeThresholdFlag(arguments, index, argument):
      discard
    elif result.takeCommonFlag(arguments, index, argument):
      discard
    elif argument == "--human":
      result.addHumanSlot("")
    elif argument.startsWith("--human:"):
      result.addHumanSlot(argument[8 .. ^1])
    elif argument == "--duel":
      result.duel = true
    elif argument == "--team-size":
      result.teamSize = parsePositiveInt32(
        arguments.argumentValue(index, "--team-size"), "--team-size"
      )
    elif argument.startsWith("--team-size="):
      result.teamSize = parsePositiveInt32(argument[12 .. ^1], "--team-size")
    elif argument == "--duellog":
      result.matchLogDir = arguments.argumentValue(index, "--duellog")
    elif argument.startsWith("--duellog="):
      result.matchLogDir = argument[10 .. ^1]
    elif argument == "--practice":
      result.practice = true
    elif argument == "--practice:off" or argument == "--no-practice":
      result.practice = false
    elif argument == "--practice-dir":
      result.practiceDir = arguments.argumentValue(index, "--practice-dir")
    elif argument.startsWith("--practice-dir="):
      result.practiceDir = argument[15 .. ^1]
    elif argument == "--coach":
      result.coachEndpoint = arguments.argumentValue(index, "--coach")
    elif argument.startsWith("--coach="):
      result.coachEndpoint = argument[8 .. ^1]
    elif argument == "--coach-model":
      result.coachModel = arguments.argumentValue(index, "--coach-model")
    elif argument.startsWith("--coach-model="):
      result.coachModel = argument[14 .. ^1]
    elif argument == "--pilot":
      result.addPilotSlot("")
    elif argument.startsWith("--pilot:"):
      result.addPilotSlot(argument[8 .. ^1])
    elif argument == "--quickcast":
      result.quickcast = true
    elif argument == "--autocast":
      result.autocast = true
    elif argument == "--mute":
      result.mute = true
    elif argument == "--sound":
      result.mute = false
    elif argument == "--keys":
      result.keysPath = arguments.argumentValue(index, "--keys")
    elif argument.startsWith("--keys="):
      result.keysPath = argument[7 .. ^1]
    elif argument == "--killGoal":
      result.killGoal = parsePositiveInt32(
        arguments.argumentValue(index, "--killGoal"), "--killGoal"
      )
    elif argument.startsWith("--killGoal="):
      result.killGoal = parsePositiveInt32(argument[11 .. ^1], "--killGoal")
    elif argument == "--botEvery":
      result.botEvery = parsePositiveInt32(
        arguments.argumentValue(index, "--botEvery"), "--botEvery"
      )
    elif argument.startsWith("--botEvery="):
      result.botEvery = parsePositiveInt32(argument[11 .. ^1], "--botEvery")
    elif argument == "--botAimNoise":
      result.botAimNoise = parseInt32(
        arguments.argumentValue(index, "--botAimNoise"), "--botAimNoise"
      )
    elif argument.startsWith("--botAimNoise="):
      result.botAimNoise = parseInt32(argument[14 .. ^1], "--botAimNoise")
    elif argument == "--runes":
      result.runeSeconds = parseInt32(
        arguments.argumentValue(index, "--runes"), "--runes"
      )
    elif argument.startsWith("--runes="):
      result.runeSeconds = parseInt32(argument[8 .. ^1], "--runes")
    elif argument == "--difficulty":
      result.applyDifficulty(
        arguments.argumentValue(index, "--difficulty")
      )
    elif argument.startsWith("--difficulty="):
      result.applyDifficulty(argument[13 .. ^1])
    elif argument == "--host":
      if result.hostPort == 0:
        result.hostPort = 8000
    elif argument == "--autostart":
      result.autoStart = true
    elif argument == "--port":
      result.hostPort = parsePositiveInt32(
        arguments.argumentValue(index, "--port"), "--port"
      )
    elif argument.startsWith("--port="):
      result.hostPort = parsePositiveInt32(argument[7 .. ^1], "--port")
    elif argument == "--join":
      result.joinUrl = arguments.argumentValue(index, "--join")
    elif argument.startsWith("--join="):
      result.joinUrl = argument[7 .. ^1]
    elif argument == "--slot":
      result.joinSlot = parsePositiveInt32(
        arguments.argumentValue(index, "--slot"), "--slot"
      ) - 1
    elif argument.startsWith("--slot="):
      result.joinSlot = parsePositiveInt32(argument[7 .. ^1], "--slot") - 1
    elif argument == "--name":
      result.playerName = arguments.argumentValue(index, "--name")
    elif argument.startsWith("--name="):
      result.playerName = argument[7 .. ^1]
    elif argument == "--label":
      result.seatLabels.add arguments.argumentValue(index, "--label")
    elif argument.startsWith("--label="):
      result.seatLabels.add argument[8 .. ^1]
    elif argument == "--token":
      result.joinToken = arguments.argumentValue(index, "--token")
    elif argument.startsWith("--token="):
      result.joinToken = argument[8 .. ^1]
    elif argument == "--netsim" or argument.startsWith("--netsim="):
      netsimSpec =
        if argument.startsWith("--netsim="): argument[9 .. ^1]
        else: arguments.argumentValue(index, "--netsim")
    elif argument == "--netsim-latency" or
        argument.startsWith("--netsim-latency="):
      let text =
        if argument.startsWith("--netsim-latency="): argument[17 .. ^1]
        else: arguments.argumentValue(index, "--netsim-latency")
      let value = parseInt32(text, "--netsim-latency")
      if value < 0:
        fail("--netsim-latency must be >= 0")
      netsimHasLatency = true
      netsimLatency = int(value)
    elif argument == "--netsim-jitter" or
        argument.startsWith("--netsim-jitter="):
      let text =
        if argument.startsWith("--netsim-jitter="): argument[16 .. ^1]
        else: arguments.argumentValue(index, "--netsim-jitter")
      let value = parseInt32(text, "--netsim-jitter")
      if value < 0:
        fail("--netsim-jitter must be >= 0")
      netsimHasJitter = true
      netsimJitter = int(value)
    elif argument == "--netsim-loss" or argument.startsWith("--netsim-loss="):
      let text =
        if argument.startsWith("--netsim-loss="): argument[14 .. ^1]
        else: arguments.argumentValue(index, "--netsim-loss")
      try:
        netsimLoss = parseFloat(text)
      except ValueError:
        fail("--netsim-loss must be a number")
      if netsimLoss < 0.0 or netsimLoss > 100.0:
        fail("--netsim-loss must be between 0 and 100")
      netsimHasLoss = true
    else:
      case argument
      of "--help", "-h":
        usage()
        quit(0)
      else:
        fail("unknown argument: " & argument)
    inc index
  if netsimSpec.len > 0 or netsimHasLatency or netsimHasJitter or
      netsimHasLoss:
    # Preset/spec first, then individual overrides, so flag order does
    # not matter: `--netsim poor --netsim-jitter 80` is 250±80.
    var cfg: NetSimConfig
    if netsimSpec.len > 0:
      let (ok, parsed) = parseNetSimArg(netsimSpec)
      if not ok:
        fail("--netsim expects local|good|poor|extreme|off or " &
          "100+/-50[,loss=2], got: " & netsimSpec)
      cfg = parsed
    else:
      cfg = NetSimConfig(
        enabled: true, latencyMs: 0, jitterMs: 0, packetLossPercent: 0.0,
        delayOutbound: true, delayInbound: true)
    if netsimHasLatency: cfg.latencyMs = netsimLatency
    if netsimHasJitter: cfg.jitterMs = netsimJitter
    if netsimHasLoss: cfg.packetLossPercent = netsimLoss
    if netsimHasLatency or netsimHasJitter or netsimHasLoss:
      cfg.enabled = true
    netSimConfigure(cfg)
    if cfg.enabled:
      netSimSetLogging(true)
  # Unset goal and duration take the mode's defaults: duels are
  # shorter so the play-analyze-improve loop turns around quickly.
  if result.teamSize == 0:
    result.teamSize = int32(TeamSize)
  elif result.teamSize < 1 or result.teamSize > MaxTeamSize:
    fail("--team-size must be between 1 and " & $MaxTeamSize)
  if result.duel and result.teamSize != int32(TeamSize):
    fail("--duel cannot combine with --team-size")
  if result.killGoal <= 0:
    result.killGoal = if result.duel: DuelKillGoal else: KillGoal
  if result.maximumTicks <= 0:
    let minutes = if result.duel: DuelMinutes else: DefaultMinutes
    result.maximumTicks = minutes * 60 * TickRate
    result.seconds = result.maximumTicks div TickRate
  if result.duel:
    if result.hostPort != 0 or result.joinUrl.len > 0 or result.autoStart:
      fail("--duel is a local mode; it cannot combine with --host or --join")
    for slot in result.humanSlots:
      if slot >= DuelPudgeCount:
        fail("--duel seats are 0 (west) and 1 (east)")
  if result.botAimNoise < 0:
    fail("--botAimNoise must be zero or positive")
  if result.runeSeconds >= 0 and
      int64(result.runeSeconds) * int64(TickRate) > int64(int32.high):
    fail("--runes is too large")
  if result.joinSlot >= MaxPudgeCount:
    fail("--slot must be between 1 and " & $MaxPudgeCount)
  if result.joinUrl.len > 0:
    if hybridSlots.len > 0 or tacticalShadowSlots.len > 0:
      fail("tactical modes cannot be combined with --join")
    # A joining client follows the host's tape; nothing local applies.
    if result.hostPort != 0:
      fail("--join cannot be combined with --host")
    if result.replayPath.len > 0 or result.recordPath.len > 0:
      fail("--join cannot be combined with --replay or --record")
    if result.botGroups.len > 0 or result.humanSlots.len > 0:
      fail("--join cannot be combined with --bot or --human; " &
        "use --slot to pick a seat")
    return
  if result.autoStart and result.hostPort == 0:
    fail("--autostart requires --host")
  let seats =
    if result.duel: DuelPudgeCount
    else: matchPudgeCount(int(result.teamSize))
  for slot in result.humanSlots:
    if slot >= seats:
      fail("--human slot " & $slot & " is outside this roster of " & $seats)
  for slot in result.pilotSlots:
    if slot >= seats:
      fail("--pilot slot " & $slot & " is outside this roster of " & $seats)
  for slot in hybridSlots:
    if slot < 0 or slot >= seats: fail("--hybrid slot is outside the roster")
    if int32(slot) in result.humanSlots or int32(slot) in result.pilotSlots:
      fail("--hybrid needs a BASIC seat, not a human or pilot seat")
  for slot in tacticalShadowSlots:
    if slot < 0 or slot >= seats: fail("--tactical-shadow slot is outside the roster")
    if slot in hybridSlots or int32(slot) in result.pilotSlots:
      fail("tactical shadow seats cannot overlap hybrid or pilot seats")
  if tacticalShadowSlots.len > 0 and (result.hostPort != 0 or result.replayPath.len > 0):
    fail("--tactical-shadow is currently supported for local live matches only")
  if hybridSlots.len > 0:
    if result.pilotSlots.len > 0:
      fail("--hybrid cannot share a match with blocking --pilot seats")
    if result.hostPort != 0 or result.replayPath.len > 0:
      fail("--hybrid is currently supported for local live matches only")
    if result.coachEndpoint.len == 0: result.coachEndpoint = "local"
  if hybridPlan.len > 0 and hybridSlots.len != 1:
    fail("--hybrid-plan requires exactly one --hybrid seat")
  if result.pilotSlots.len > 0 and result.hostPort != 0:
    fail("--pilot cannot be combined with --host")
  if result.hostPort != 0:
    if result.replayPath.len > 0:
      fail("--host cannot be combined with --replay")
    if result.botGroups.len == 0:
      # Every hosted seat needs script autopilot so a leaver's butcher
      # keeps fighting; fill the roster with the stock bot.
      result.botGroups.addBotSpec(findStockBot() & ":" & $seats)
    if result.botGroups.botCount != seats:
      fail(
        "--host needs bot scripts for all " & $seats &
        " seats (autopilot for leavers); configured " &
        $result.botGroups.botCount
      )
    if result.humanSlots.len > 1:
      fail("--host claims at most one --human seat for the host player")
  result.validateGameOptions(0, "")
  if result.replayPath.len == 0:
    if result.duel and result.botGroups.len == 0 and
        result.humanSlots.len < seats:
      # A bare duel pits the seats without humans against the
      # evolving challenger policy.
      result.botGroups.addBotSpec(
        findChallengerScript() & ":" &
          $(seats - result.humanSlots.len - result.pilotSlots.len)
      )
    elif result.botGroups.len == 0:
      # Local --human and spectate: stock autopilot on every seat.
      # --host already filled above. Human seats still take input;
      # the VM is fallback if they release (T).
      result.botGroups.addBotSpec(findStockBot() & ":" & $seats)
    let
      bots = result.botGroups.botCount
      humans = result.humanSlots.len
    if bots != seats and bots + humans != seats:
      fail(
        "live games need bots for all " & $seats &
        " seats or all " & $(seats - humans) &
        " non-human seats; configured " & $bots
      )

var options* = parseGameOptions()

proc optionRunePeriod*(): int32 =
  ## The live-game rune spawn period in ticks from `--runes`.
  if options.runeSeconds < 0:
    RunePeriodTicks
  else:
    options.runeSeconds * TickRate

var
  run*: Game
  predictor* = newPredictor()
    ## Client-side prediction for a WASM human seat. Enabled only by the
    ## emscripten graphics loop; stays disabled (a no-op passthrough) for
    ## native, LAN, host, and replay, so those paths render bit-for-bit
    ## the confirmed world exactly as before.
  netRole* = NetOff
    ## Whether this process hosts, follows, or plays alone.
  localSeat* = -1
    ## Roster seat this process's input drives; -1 spectates. Distinct
    ## from `run.humanSlots`, which lists every human-driven seat in
    ## the match (a host tracks its remote players there too).

proc netPlayerName*(): string =
  ## The display name for networked play.
  if options.playerName.len > 0:
    return options.playerName
  if options.hostPort != 0: "Host" else: "Player"

proc overlayWorld*(): World =
  ## World the HUD and overlays should read. A predicting WASM seat
  ## uses the look-ahead copy so a local ping appears this frame.
  if predictor.enabled and predictor.predicted != nil:
    predictor.predicted.world
  else:
    run.world

proc predictedPudge*(index: int): Pudge =
  ## The state to render for one roster seat. The local WASM seat draws
  ## from the prediction world (so a click moves it this frame); every
  ## other seat, and every non-predicting build, draws the confirmed
  ## world unchanged. Same pudge `id` either way, so the render-space
  ## interpolators stay keyed correctly.
  if index < 0 or index >= run.world.pudges.len:
    return
  result = run.world.pudges[index]
  if predictor.enabled and predictor.predicted != nil and
      index == predictor.seat and
      index < predictor.predicted.world.pudges.len:
    result = predictor.predicted.world.pudges[index]
    # Draw the smoothed position so a misprediction teleport (high latency /
    # jitter) eases out instead of snapping. Render-only: `result` is a value
    # copy, and the sim/prediction worlds keep the true position.
    let rp = localRenderPoint(predictor)
    result.position.x = rp.x
    result.position.z = rp.z

proc validateNetSetup(setup: Setup) =
  ## Rejects a host running an incompatible build before the world is
  ## created from its setup.
  if setup.tickRate != uint16(TickRate):
    fail("host runs at " & $setup.tickRate & " Hz, this build at " &
      $TickRate & " Hz")
  if setup.gridTiles != ReplayGridTiles:
    fail("host map size does not match this build")
  if setup.pudges.len < DuelPudgeCount or setup.pudges.len > MaxPudgeCount:
    fail("host match does not have 2 to " & $MaxPudgeCount & " butchers")
  if setup.maximumTicks == 0 or setup.killGoal <= 0:
    fail("host sent an invalid match setup")

when not defined(emscripten):
  import duellog

  var matchLog*: DuelLogger
    ## Structured per-match analysis log; nil when logging is off.

  proc duelLoggingWanted(): bool =
    ## Local matches log when duel mode or an explicit --duellog asks.
    netRole == NetOff and (options.duel or options.matchLogDir.len > 0)

  proc duelLogBase(): string =
    if options.matchLogDir.len > 0: options.matchLogDir
    else: "duels"

  proc currentSeatScripts(): seq[string] =
    ## Bot script path per roster seat, mirroring `loadBots` seat fill;
    ## human seats stay empty.
    result = newSeq[string](run.world.pudges.len)
    var expanded: seq[string]
    for group in options.botGroups:
      for _ in 0 ..< group.count:
        expanded.add group.path
    if expanded.len == result.len:
      for i in 0 ..< result.len:
        result[i] = expanded[i]
    else:
      var next = 0
      for i in 0 ..< result.len:
        if i in run.humanSlots or next >= expanded.len:
          continue
        result[i] = expanded[next]
        inc next

  proc startDuelLogging*() =
    ## Opens a fresh match directory and logger for the current world.
    if not duelLoggingWanted():
      return
    matchLog = newDuelLogger(
      run, nextMatchDir(duelLogBase()), currentSeatScripts()
    )
    echo "duel log: ", matchLog.dir

proc closeDuelLogging*() =
  ## Finalizes the analysis log: on quit, rematch, or match end.
  when not defined(emscripten):
    if matchLog != nil:
      finishDuelLog(matchLog, run)
  else:
    discard

proc newFollowerGame*(setup: Setup): Game =
  ## Builds the follower world for one hosted match: the host's map
  ## seed, an empty streamed tape, and playback locked to it. The
  ## client runs no bots and records nothing - the stream is the tape.
  validateNetSetup(setup)
  var gameMap: MapData
  profileBlock "map":
    gameMap = generateMapMatching(setup.mapSeed, setup.mapHash)
  if gameMap.hash != setup.mapHash:
    fail("map generation differs from the host; update this build")
  result = Game(
    world: newWorld(
      gameMap,
      int32(setup.maximumTicks),
      setup.pudges,
      setup.killGoal,
      setup.runePeriod
    ),
    map: gameMap,
    maximumTicks: int32(setup.maximumTicks),
    botEvery: max(setup.botEvery, 1'i32),
    botAimNoise: max(setup.botAimNoise, 0'i32),
    botSpeech: newSeq[BotSpeech](setup.pudges.len),
    historyPlayback: true,
    replayPlayer: ReplayPlayer(data: initReplayData(setup))
  )
  for i, pudge in setup.pudges:
    if pudge.controller == ControllerHuman:
      result.humanSlots.add i
  if setup.seatLabels.len > 0:
    applySeatLabels(result, setup.seatLabels)

block:
  startProfileTrace()
  if options.joinUrl.len > 0:
    netRole = NetClient
    let boot = netBootstrap(
      options.joinUrl,
      netPlayerName(),
      options.joinToken,
      options.joinSlot
    )
    if not boot.ok:
      fail("join failed: " & boot.error)
    run = newFollowerGame(boot.setup)
    localSeat = netClientSeat()
  else:
    if options.hostPort != 0:
      netRole = NetHost
    var
      replayMode = options.replayPath.len > 0
      mapSeed = options.seed
      replayData: ReplayData
    if replayMode:
      profileBlock "replay":
        replayData = loadReplay(options.replayPath)
      mapSeed = replayData.header.setup.mapSeed
    var gameMap: MapData
    profileBlock "map":
      if replayMode:
        gameMap = generateMapMatching(
          mapSeed, replayData.header.setup.mapHash
        )
      elif options.duel:
        gameMap = generateMap(mapSeed, TeamSize)
      else:
        gameMap = generateMap(mapSeed, int(options.teamSize))
    let configuredTicks =
      if replayMode: int32(replayData.header.setup.maximumTicks)
      else: options.maximumTicks
    run = newGame(
      gameMap, configuredTicks, replayMode, replayData, options.killGoal,
      optionRunePeriod(), options.duel
    )
    if replayMode:
      run.maximumTicks = int32(replayData.hashes.len)
      run.replayPlayer = initReplayPlayer(replayData)
      run.historyPlayback = true
      # Controller provenance from the tape, so analysis logs label
      # human and bot seats correctly on playback.
      for i, pudge in replayData.header.setup.pudges:
        if pudge.controller == ControllerHuman:
          run.humanSlots.add i
    else:
      for slot in options.humanSlots:
        run.humanSlots.add int(slot)
      if options.humanSlots.len > 0:
        localSeat = run.humanSlots[0]
      for slot in options.pilotSlots:
        run.humanSlots.add int(slot)
      run.botEvery = max(options.botEvery, 1'i32)
      run.botAimNoise = max(options.botAimNoise, 0'i32)
      loadBots(run, options.botGroups, hybridSlots)
    if options.seatLabels.len > 0:
      applySeatLabels(run, options.seatLabels)
    elif replayMode and replayData.header.setup.seatLabels.len > 0:
      applySeatLabels(run, replayData.header.setup.seatLabels)
    when not defined(emscripten):
      startDuelLogging()

proc advanceGame*() {.measure.} =
  hybridTick(run)
  tickWorld(run, proc() = runBotDecisions(run))
  practiceTick(run)
  when not defined(emscripten):
    logDuelTick(matchLog, run)

proc beginPractice*() =
  ## Starts the decision-model coach (--practice) and pilots (--pilot)
  ## for this match. The exact action tape lands beside the trace unless
  ## --record chose another path. A network follower never coaches.
  if netRole == NetClient or run.replayMode:
    return
  hybridReset()
  if not thresholdsOff:
    let table = loadThresholds(thresholdsPath)
    if table.loaded:
      echo "thresholds: ", table.path, " (default ", table.default,
        ", ", table.classes.len, " classes)"
  var matchDir = ""
  if options.practice and options.humanSlots.len > 0:
    let started = practiceBegin(run, options.practiceDir, enabled = true,
      model = options.coachModel, endpoint = options.coachEndpoint)
    if started.enabled:
      matchDir = started.dir
      echo "practice trace: ", started.dir, " (", started.provider, " ",
        started.model, ", ", started.status, ")"
  for slot in hybridSlots:
    if matchDir.len == 0: matchDir = newMatchDir(options.practiceDir)
    let adviser = hybridBegin(run, slot, matchDir, options.coachEndpoint,
      options.coachModel, hybridDelay, hybridPlan)
    echo "hybrid seat ", slot, ": ", adviser.dir
  for slot in tacticalShadowSlots:
    if matchDir.len == 0: matchDir = newMatchDir(options.practiceDir)
    let observer = hybridBegin(run, slot, matchDir, shadow = true)
    echo "tactical shadow seat ", slot, ": ", observer.dir
  for slot in options.pilotSlots:
    if matchDir.len == 0:
      matchDir = newMatchDir(options.practiceDir)
    # A headless match has no frame to keep up with, so each pilot waits
    # for its answer; the graphical client never blocks the frame.
    let pilot = pilotBegin(run, int(slot), matchDir,
      model = options.coachModel, endpoint = options.coachEndpoint,
      sync = defined(headless))
    if pilot.enabled:
      if pilotNoise > 0:
        pilot.pilotNoise(pilotNoise, int64(options.seed) * 1000 + int64(slot))
      echo "pilot seat ", slot, ": ", pilot.dir, " (", pilot.provider, " ",
        pilot.model, ", ", pilot.status,
        (if pilotNoise > 0: ", noise " & $pilotNoise else: ""), ")"
  var shadows = shadowSlots
  if shadowAll:
    for slot in 0 ..< run.world.pudges.len:
      if int32(slot) notin options.humanSlots and
          int32(slot) notin options.pilotSlots:
        shadows.add int32(slot)
  for slot in shadows:
    if int(slot) in run.humanSlots:
      echo "shadow seat ", slot, " is a human or pilot seat; skipped"
      continue
    if matchDir.len == 0:
      matchDir = newMatchDir(options.practiceDir)
    let shadow = shadowBegin(run, int(slot), matchDir)
    if shadow.enabled:
      echo "shadow seat ", slot, ": ", shadow.dir
  if matchDir.len > 0 and (options.recordPath.len == 0 or
      options.recordPath.startsWith(practiceDataDir()) or
      (options.practiceDir.len > 0 and
        options.recordPath.startsWith(options.practiceDir))):
    options.recordPath = matchDir / "replay.pwr"

proc vmStatus*(): tuple[active, decisions: int] =
  if run.replayMode:
    result.active = run.world.pudges.len
    result.decisions = run.replayPlayer.actionIndex
  else:
    for vm in run.heroVms:
      if vm != nil and not vm.failed:
        inc result.active
      if vm != nil:
        result.decisions += vm.decisions

proc startReplayRecording*(maximumTicks: uint32) =
  run.recorder = initReplayRecorder(currentSetup(run, maximumTicks))
  run.replayPlayer = ReplayPlayer(data: run.recorder.data)

proc saveRecording*() =
  ## Persists the finished tape: to --record when given, and beside
  ## the analysis log so every logged match keeps its exact replay.
  ## Keeps the original match setup; hash count is the played length.
  hybridFinish(run)
  if run.recorder == nil:
    return
  var paths: seq[string]
  if options.recordPath.len > 0:
    paths.add options.recordPath
  when not defined(emscripten):
    if matchLog != nil:
      let logCopy = matchLog.dir / "replay.pwr"
      if logCopy notin paths:
        paths.add logCopy
  if paths.len == 0:
    return
  for path in paths:
    saveReplay(path, run.recorder.data)
    echo &"replay saved: {path} " &
      &"({run.recorder.data.actions.len} actions)"

var
  rosterOverride: seq[ReplayPudge]
  botGroupsOverride: seq[BotGroup]

proc setRosterExperiment*(disabled: openArray[bool]) =
  ## Applies the host lobby's seat toggles: builds the compacted
  ## roster and the per-seat bot list (disabling seat 3 removes seat
  ## 3's persona specifically). All seats enabled clears the override.
  rosterOverride.setLen(0)
  botGroupsOverride.setLen(0)
  var any = false
  let n = int(options.teamSize)
  let seats = matchPudgeCount(n)
  for i, off in disabled:
    if i >= seats:
      break
    if off:
      any = true
      break
  if not any or options.duel:
    return
  rosterOverride = filteredRoster(disabled, n)
  var flat: seq[string]
  for group in options.botGroups:
    for _ in 0 ..< group.count:
      flat.add group.path
  for seat in 0 ..< seats:
    if (seat < disabled.len and disabled[seat]) or seat >= flat.len:
      continue
    botGroupsOverride.addBotSpec(flat[seat] & ":1")

proc activeRoster*(): seq[ReplayPudge] =
  rosterOverride

proc activeBotGroups*(): seq[BotGroup] =
  if botGroupsOverride.len > 0: botGroupsOverride
  else: options.botGroups

proc rebuildWithRoster*() =
  ## Rebuilds the lobby's preview world with the compacted roster just
  ## before a hosted start. Same arena, fewer seats.
  run = newGame(
    run.map, options.maximumTicks, false, ReplayData(), options.killGoal,
    optionRunePeriod(), options.duel, activeRoster()
  )
  run.botEvery = max(options.botEvery, 1'i32)
  run.botAimNoise = max(options.botAimNoise, 0'i32)
  loadBots(run, activeBotGroups(), hybridSlots)

proc fillBotsTo*(count: int) =
  ## Grows or trims `options.botGroups` so `loadBots` can fill `count`
  ## seats. Extra seats repeat the stock autopilot.
  var flat: seq[string]
  for group in options.botGroups:
    for _ in 0 ..< group.count:
      flat.add group.path
  if flat.len > count:
    flat.setLen(count)
  while flat.len < count:
    flat.add findStockBot()
  options.botGroups.setLen(0)
  for path in flat:
    options.botGroups.addBotSpec(path & ":1")

proc applyTeamSize*(n: int): bool =
  ## Live lobby / local N stepper. Regenerates the map (extra pads
  ## stamp extra roads) and rebuilds the world. No-op once a hosted
  ## match has started, in duel, replay, or as a follower.
  if options.duel or run.replayMode or netRole == NetClient:
    return false
  let next = clampTeamSize(n)
  if next == int(options.teamSize):
    return false
  options.teamSize = int32(next)
  rosterOverride.setLen(0)
  botGroupsOverride.setLen(0)
  fillBotsTo(matchPudgeCount(next))
  let gameMap = generateMap(run.map.seed, next)
  run = newGame(
    gameMap, options.maximumTicks, false, ReplayData(), options.killGoal,
    optionRunePeriod(), false
  )
  run.botEvery = max(options.botEvery, 1'i32)
  run.botAimNoise = max(options.botAimNoise, 0'i32)
  loadBots(run, options.botGroups, hybridSlots)
  true

proc restartMatch*() =
  ## Rematch on the same arena: a fresh world with the launch options
  ## and seats, keeping the already-baked map and terrain. When
  ## recording, the finished match's tape is saved first (the record
  ## path holds the most recent completed match). A network follower
  ## instead rebuilds from the host's next `Start`. Analysis logging
  ## rolls over to a fresh match directory.
  if run.replayMode or netRole == NetClient:
    return
  closeDuelLogging()
  saveRecording()
  run = newGame(
    run.map, options.maximumTicks, false, ReplayData(), options.killGoal,
    optionRunePeriod(), options.duel, activeRoster()
  )
  for slot in options.humanSlots:
    run.humanSlots.add int(slot)
  if netRole == NetOff:
    localSeat = if options.humanSlots.len > 0: run.humanSlots[0] else: -1
  for slot in options.pilotSlots:
    run.humanSlots.add int(slot)
  run.botEvery = max(options.botEvery, 1'i32)
  run.botAimNoise = max(options.botAimNoise, 0'i32)
  loadBots(run, activeBotGroups(), hybridSlots)
  when not defined(emscripten):
    startDuelLogging()

proc netClientRestart*(setup: Setup) =
  ## Rebuilds the follower world when the host rematches. The map seed
  ## matches the old arena (rematches keep it), so baked terrain stays
  ## valid.
  run = newFollowerGame(setup)
  localSeat = netClientSeat()

when defined(headless):
  proc printHeadlessSummary(steps: int, started: float64) =
    let
      elapsed = max(epochTime() - started, 0.000001)
      simulated = steps.float64 / TickRate.float64
      speedup = simulated / elapsed
      status = vmStatus()
      outcome =
        if run.world.gameOver:
          if run.world.winner == WestTeam: "west won" else: "east won"
        else:
          "time limit"
    echo &"result: {outcome}"
    echo &"simulated: {simulated:.2f} s in {elapsed:.4f} s " &
      &"({speedup:.1f}x real time)"
    echo &"score: west {run.world.teamKills[WestTeam.ord]} / " &
      &"east {run.world.teamKills[EastTeam.ord]}  goal {run.world.killGoal}"
    var runesTaken = 0'i32
    for pudge in run.world.pudges:
      runesTaken += pudge.runesTaken
    echo &"combat: hits {run.world.hookHits} misses {run.world.hookMisses} " &
      &"headshots {run.world.headshots} river {run.world.riverDumps} " &
      &"denies {run.world.hookDenies} runes {runesTaken}"
    echo &"hash: {run.stateHash().toHex(16)} map " &
      &"{run.map.hash.toHex(16)}"
    if run.replayMode:
      echo &"replay: {status.decisions}/{run.replayData.actions.len} actions"
    else:
      echo &"scripts: {status.active}/{run.world.pudges.len} active, " &
        &"{status.decisions} decisions"
    when not defined(emscripten):
      if matchLog != nil:
        echo &"duel log: {matchLog.dir}"

  proc runBranchHeadless() =
    ## Answer-key rollouts over the replay game built from --branch.
    var opts = branchOptions
    if opts.ticks.len == 0:
      fail("--branch needs --branch-ticks")
    if opts.slot < 0 or opts.slot >= run.world.pudges.len:
      fail("--branch-slot is outside this roster of " & $run.world.pudges.len)
    if opts.horizon <= 0:
      opts.horizon = int32(DefaultHorizonTicks)
    if opts.seeds <= 0:
      opts.seeds = 1
    if opts.botPath.len == 0:
      opts.botPath = findStockBot()
    runBranch(run, opts)

  proc runHeadless*() =
    if branchOptions.path.len > 0:
      runBranchHeadless()
      return
    let
      stepLimit =
        if run.replayMode:
          run.replayData.hashes.len
        else:
          int(options.maximumTicks)
      started = epochTime()
    if not run.replayMode:
      startReplayRecording(uint32(stepLimit))
    beginPractice()
    startProfileTrace()
    defer:
      finishProfileTrace()
    var steps = 0
    # Headless network hybrids run on the game's wall clock. Inference never
    # freezes simulated time. Offline interventions remain accelerated.
    let realtime = hybridSlots.len > 0 and hybridPlan.len == 0 and
      coachConfig(options.coachEndpoint, options.coachModel).endpoint.len > 0
    let clockStart = getMonoTime()
    while steps < stepLimit and
        (run.replayMode or not run.world.gameOver) and
        run.recordingError.len == 0:
      if realtime:
        let remaining = int64(steps) * 1_000_000_000 div int64(TickRate) -
          (getMonoTime() - clockStart).inNanoseconds
        if remaining > 0: sleep(int((remaining + 999_999) div 1_000_000))
      advanceGame()
      inc steps
      if profileShouldDump(steps):
        finishProfileTrace()
    practiceFinish(run)
    hybridFinish(run)
    if run.recordingError.len > 0:
      raise newException(ReplayError, run.recordingError)
    closeDuelLogging()
    if run.replayMode:
      run.hashCheck.requireReplayComplete(
        uint32(run.world.tick),
        run.replayData.hashes.len
      )
      if not run.replayPlayer.finished:
        raise newException(
          ReplayError,
          "replay simulation did not consume every action"
        )
      echo "replay verified: every tick matched"
    else:
      saveRecording()
    printHeadlessSummary(steps, started)
