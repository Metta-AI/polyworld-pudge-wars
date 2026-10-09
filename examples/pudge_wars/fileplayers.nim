## Runner-staged BASIC seats. No player source or output enters public logs.
import std/[json, os, strutils, times, uri], bassy,
  polyworld/[annotations, policies], bots, sim

const
  PlayerLogLimit* = 10 * 1024 * 1024
  Truncation = "\n[Player log truncated at 10 MiB.]\n"

type
  FilePlayerError* = object of CatchableError
  Seat = object
    path, logPath: string
    size: int64
    log: File
    bytes: int
    truncated, failed: bool
    annotations: AnnotationSink
  FilePlayers* = ref object
    seats: seq[Seat]
    statusPath, failurePath: string

proc localPath*(value: string): string =
  let parsed = parseUri(value)
  if parsed.scheme != "file" or parsed.hostname.len > 0 or
      parsed.query.len > 0 or parsed.anchor.len > 0 or
      not parsed.path.startsWith("/"):
    raise newException(FilePlayerError, "Expected an absolute local file URI")
  result = decodeUrl(parsed.path, decodePlus = false)
  if '\0' in result:
    raise newException(FilePlayerError, "Invalid local file URI")

proc writeAtomic*(path, bytes: string) =
  createDir(path.parentDir)
  writeFile(path & ".tmp", bytes)
  moveFile(path & ".tmp", path)

proc playerLog*(players: FilePlayers, slot: int, text: string) =
  if players.seats[slot].truncated:
    return
  let remaining = PlayerLogLimit - Truncation.len - players.seats[slot].bytes
  if text.len <= remaining:
    players.seats[slot].log.write(text)
    players.seats[slot].bytes += text.len
  else:
    if remaining > 0:
      players.seats[slot].log.write(text[0 ..< remaining])
    players.seats[slot].log.write(Truncation)
    players.seats[slot].truncated = true

proc playerPrinter(players: FilePlayers, slot: int): PrintProc =
  result = proc(event: PrintEvent) =
    case event.kind
    of TextPrint: players.playerLog(slot, event.text)
    of ValuePrint: players.playerLog(slot, $event.value)
    of FixedPrint: players.playerLog(slot, $event.fixedValue)
    of NewlinePrint: players.playerLog(slot, "\n")

proc flushOutput(file: File): cint {.importc: "fflush", header: "<stdio.h>".}
proc closeOutput(file: File): cint {.importc: "fclose", header: "<stdio.h>".}

proc close*(players: FilePlayers) =
  var failed = false
  for seat in players.seats.mitems:
    if seat.log != nil:
      # Nim's standard flush/close wrappers discard stdio errors.
      if flushOutput(seat.log) != 0: failed = true
      if closeOutput(seat.log) != 0: failed = true
      seat.log = nil
    if seat.annotations.close() == AnnotationWriteFailed:
      failed = true
  if failed:
    raise newException(FilePlayerError, "Cannot finalize private player outputs")

proc openFilePlayers*(document: JsonNode, count: int,
                      failureUri: string): FilePlayers =
  let schema = document{"schema"}.getStr
  if document.kind != JObject or
      schema notin ["coworld-player-seats/1", "coworld-player-seats/2"] or
      not document.hasKey("seats") or
      document{"seats"}.kind != JArray or document["seats"].len != count:
    raise newException(FilePlayerError, "Invalid file-player roster")
  result = FilePlayers(seats: newSeq[Seat](count),
    failurePath: localPath(failureUri))
  let statusUri = document{"player_status_uri"}.getStr
  if statusUri.len > 0:
    result.statusPath = localPath(statusUri)
  var paths: seq[string]
  # Validate every destination before opening any output.
  for slot, node in document["seats"].getElems:
    if node.kind != JObject or not node.hasKey("slot") or
        node["slot"].kind != JInt or node["slot"].getInt != slot or
        not node.hasKey("size_bytes") or node["size_bytes"].kind != JInt or
        node["size_bytes"].getBiggestInt < 0:
      raise newException(FilePlayerError, "Invalid file-player seat")
    let path = localPath(node{"file_uri"}.getStr)
    let logPath = localPath(node{"log_uri"}.getStr)
    if logPath in paths:
      raise newException(FilePlayerError, "Player log destinations must be unique")
    paths.add logPath
    result.seats[slot] = Seat(path: path, logPath: logPath,
      size: node["size_bytes"].getBiggestInt)
    let annotationUri = node{"annotations_uri"}.getStr
    if annotationUri.len > 0:
      if schema != "coworld-player-seats/2":
        raise newException(FilePlayerError, "Annotations require seats schema 2")
      result.seats[slot].annotations = newAnnotationSink(localPath(annotationUri))
  try:
    for seat in result.seats.mitems:
      createDir(seat.logPath.parentDir)
      seat.log = open(seat.logPath, fmWrite)
  except IOError, OSError:
    result.close()
    raise

proc writeStatus(players: FilePlayers) =
  if players.statusPath.len == 0:
    return
  var statuses = newJArray()
  for slot, seat in players.seats:
    statuses.add %*{
      "slot": slot, "state": "exited",
      "exit_code": (if seat.failed: 1 else: 0),
      "reason": (if seat.failed: "BASIC VM disabled" else: "Completed"),
      "finished_at": now().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'")
    }
  writeAtomic(players.statusPath, $(%*{"schema_version": "1", "players": statuses}))

proc rejectPlayer(players: FilePlayers, slot: int, message: string) =
  players.seats[slot].failed = true
  players.playerLog(slot, "BASIC loading error: " & message & "\n")
  players.close()
  players.writeStatus()
  writeAtomic(players.failurePath, $(%*{
    "message": "Policy loading failed for player slot " & $slot,
    "failed_policy_index": slot
  }))

proc load*(players: FilePlayers, game: Game): bool =
  ## Runner verifies hashes; we independently bound reads and verify lengths.
  for slot, seat in players.seats:
    # Missing or mismatched staged bytes are an infrastructure fault, not blame
    # assigned to the policy author.
    if getFileSize(seat.path) != seat.size:
      raise newException(FilePlayerError, "Staged player size mismatch")
    if seat.size > MaxPackageBytes:
      players.rejectPlayer(slot, "Policy upload exceeds 16 MiB")
      return false
    let input = open(seat.path, fmRead)
    var source = newString(MaxPackageBytes + 1)
    try:
      source.setLen(input.readBuffer(addr source[0], source.len))
    finally:
      input.close()
    if source.len.int64 != seat.size:
      raise newException(FilePlayerError, "Staged player changed while reading")
    try:
      game.loadBotSource(slot, source, players.playerPrinter(slot), seat.annotations)
    except BasicError, PolicyError:
      players.rejectPlayer(slot, getCurrentExceptionMsg())
      return false
    players.playerLog(slot, "Player slot " & $slot & " started.\n")
  true

proc captureErrors*(players: FilePlayers, game: Game) =
  for slot, vm in game.heroVms:
    if vm.failed and not players.seats[slot].failed:
      players.seats[slot].failed = true
      players.playerLog(slot, "BASIC error: " & vm.lastError & "\n")

proc finish*(players: FilePlayers, game: Game) =
  game.closeBotServices()
  players.captureErrors(game)
  players.close()
  players.writeStatus()
