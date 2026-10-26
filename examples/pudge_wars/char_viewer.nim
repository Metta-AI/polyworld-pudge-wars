## Butcher clip viewer: orbit the Fresh Meat player models and flip every
## named clip with debug toggles. Same load path and toon shading as ./pw.
##
## Run from the repo root:
##   nim r examples/pudge_wars/char_viewer.nim

import
  std/[math, os, strformat, strutils, tables, times],
  bumpy, chroma, gltf, opengl, pixie, silky, vmath, windy,
  butcherhook, butcherknife, content,
  polyworld/[characters, chrome, common, shapes, viewers]

const
  AtlasPath = DataRoot & "/themes/pw.atlas.png"
  AppIconPath = "examples/pudge_wars/macos/AppIcon.png"

proc ensureAtlas() =
  if fileExists(AtlasPath):
    return
  let builder = newHudAtlas()
  builder.addDefaultFonts()
  builder.write(AtlasPath)

ensureAtlas()
let (window, sk) = initGameWindow(
  "Fresh Meat — Butcher Workshop",
  AtlasPath,
  ivec2(1280, 800),
  iconPath = AppIconPath
)

let scene = newCharacterScene(window)
var stage = initShapeRenderer()
var weapons = initShapeRenderer()
scene.useToonShading()
scene.setToonHour(12)

var
  models: array[Team, CharacterModel]
  legacyModels: array[Team, CharacterModel]
  clipNames: seq[string]
proc collectClipNames(model: CharacterModel): seq[string] =
  let spec = PudgeSpecs[WestTeam]
  const variants = [
    "ButcherWalk", "ButcherBackpedal", "ButcherStrafeLeft", "ButcherStrafeRight",
    "RunLegsOnly", "RunWalk", "RunSwagger", "RunFlee1", "RunFlee2",
    "RunUpstairs", "GeneratedIdle"
  ]
  for name in [spec.idleClip, spec.runClip, spec.attackClip, spec.deathClip,
               spec.victoryClip]:
    if name in model.clips:
      result.add name
  for name in variants:
    if name in model.clips and name notin result:
      result.add name
  for name in model.clips.keys:
    if name notin result:
      result.add name

for team in Team:
  let spec = PudgeSpecs[team]
  if not fileExists(spec.modelPath):
    quit("missing " & spec.modelPath)
  models[team] = loadCharacterModel(spec.modelPath, spec.targetHeight)
  let legacyPath = DataRoot & "/characters/butcher/" &
    (if team == WestTeam: "butcher.glb" else: "butcher_east.glb")
  if fileExists(legacyPath):
    legacyModels[team] = loadCharacterModel(legacyPath, spec.targetHeight)
  if clipNames.len == 0:
    clipNames = collectClipNames(models[team])

if clipNames.len == 0:
  quit("butcher GLB has no animation clips")

type
  ViewTeam = enum
    ViewWest, ViewEast, ViewBoth
  PropView = enum
    ShowCharacter, ShowKnife, ShowHook

var
  selectedClip = "ButcherChop"
  lastSelectedClip = selectedClip
  viewTeam = ViewBoth
  loopClips = true
  paused = false
  useToon = true
  playSpeed = 1.0'f32
  animTime = 0.0'f32
  showPanel = true
  cameraYaw = 0.35'f32
  cameraPitch = 0.3'f32
  cameraDistance = 21.0'f32
  cameraTarget = vec3(-1.7, PudgeSpecs[WestTeam].targetHeight * 0.56, 0)
  cameraEye = vec3(0, 0, 0)
  rotating = false
  panning = false
  lastFrameTime = epochTime()
  showGround = true
  showSkeleton = false
  propView = ShowCharacter
  knifeName = KnifeNames[DefaultButcherKnife.ord]
  compareKnives = false
  compareLegacy = false
  legacyClip = "RunForward"
  autoTurn = false
  facing = 0.0'f32
  screenshotFrame = 0
  captureFrame = 0
  captureDir = getEnv("BUTCHER_CAPTURE_DIR")
  captureFrames = getEnv("BUTCHER_CAPTURE_FRAMES", "120").parseInt

if captureDir.len > 0:
  createDir(captureDir)

if existsEnv("BUTCHER_CLIP"):
  selectedClip = getEnv("BUTCHER_CLIP")
  lastSelectedClip = selectedClip
if existsEnv("BUTCHER_TIME"):
  animTime = getEnv("BUTCHER_TIME").parseFloat.float32
  paused = true
if existsEnv("BUTCHER_YAW"):
  cameraYaw = getEnv("BUTCHER_YAW").parseFloat.float32
if existsEnv("BUTCHER_CLEAN"):
  showPanel = false
  cameraTarget.x = 0
if existsEnv("BUTCHER_LEGACY"):
  compareLegacy = true
if existsEnv("BUTCHER_BONES"):
  showSkeleton = true
if existsEnv("BUTCHER_WEAPON_ONLY"):
  propView = ShowHook
if existsEnv("BUTCHER_KNIFE_ONLY"):
  propView = ShowKnife
if existsEnv("BUTCHER_KNIFE"):
  let choice = getEnv("BUTCHER_KNIFE").toLowerAscii
  for knife in ButcherKnife:
    if choice == $knife.ord or choice == KnifeNames[knife.ord].toLowerAscii:
      knifeName = KnifeNames[knife.ord]
if existsEnv("BUTCHER_COMPARE_KNIVES"):
  compareKnives = true
  cameraDistance = if propView == ShowKnife: 24 else: 28
if existsEnv("BUTCHER_SOLO"):
  viewTeam = ViewWest
  cameraDistance = 18
if existsEnv("BUTCHER_DISTANCE"):
  cameraDistance = getEnv("BUTCHER_DISTANCE").parseFloat.float32
loopClips = selectedClip notin ["ButcherHook", "ButcherDeath"]

proc clipDescription(name: string): string =
  case name
  of "ButcherIdle": "Slow breathing / planted boots"
  of "ButcherRun": "Heavy stride / counter-swing"
  of "ButcherHook": "Release: 0.281s / then recover"
  of "ButcherChop": "High windup / heavy downward cut"
  of "ButcherSlash": "Hip-led cross-body cut / follow-through"
  of "ButcherDeath": "Buckle / fall / settle and hold"
  of "ButcherVictory": "Chest-up laugh / fist pump"
  of "ButcherWalk": "Slow patrol / double support"
  of "ButcherBackpedal": "Guarded retreat"
  of "ButcherStrafeLeft", "ButcherStrafeRight": "Side step / keep target in sight"
  else: "Original retarget experiment"

proc clipIndexOf(model: CharacterModel, name: string): int =
  if name.len == 0: -1
  elif name in model.clips: model.clipIndex(name)
  else: -1

proc clipDurationOf(model: CharacterModel, name: string): float32 =
  let clip = clipIndexOf(model, name)
  if clip < 0: 0'f32 else: clipDuration(model, clip)

proc mouseOverUi(): bool =
  for state in subWindowStates.values:
    if state.visible and sk.mousePos.overlaps(rect(state.pos, state.size)):
      return true
  false

proc updateCamera() =
  let overUi = mouseOverUi()
  if window.buttonPressed[MouseLeft] and not overUi:
    if window.buttonDown[KeyLeftShift] or window.buttonDown[KeyRightShift]:
      panning = true
    else:
      rotating = true
  if window.buttonPressed[MouseRight] and not overUi:
    panning = true
  if not window.buttonDown[MouseLeft] and not window.buttonDown[MouseRight]:
    rotating = false
    panning = false
  let delta = window.mouseDelta.vec2
  if rotating:
    cameraYaw -= delta.x * 0.01
    cameraPitch = clamp(cameraPitch + delta.y * 0.01, -1.2'f32, 1.5'f32)
  if panning:
    let
      right = vec3(cos(cameraYaw), 0, -sin(cameraYaw))
      panSpeed = cameraDistance * 0.0012
    cameraTarget = cameraTarget - right * delta.x * panSpeed
    cameraTarget.y = cameraTarget.y + delta.y * panSpeed
  if not overUi and window.scrollDelta.y != 0:
    cameraDistance = clamp(
      cameraDistance * pow(0.92'f32, window.scrollDelta.y),
      4.0'f32, 80.0'f32
    )

proc cameraView(): Mat4 =
  let eyeOffset = vec3(
    sin(cameraYaw) * cos(cameraPitch),
    sin(cameraPitch),
    cos(cameraYaw) * cos(cameraPitch)
  ) * cameraDistance
  cameraEye = cameraTarget + eyeOffset
  lookAt(cameraEye, cameraTarget, vec3(0, 1, 0))

proc selectClip(name: string) =
  selectedClip = name
  lastSelectedClip = name
  animTime = 0
  loopClips = name notin ["ButcherHook", "ButcherDeath"]

proc handleHotkeys() =
  if window.buttonPressed[KeyK]:
    knifeName = KnifeNames[(KnifeNames.find(knifeName)+1) mod KnifeNames.len]
  if window.buttonPressed[KeyC]:
    selectClip("ButcherChop")
  if window.buttonPressed[KeyV]:
    selectClip("ButcherSlash")
  if window.buttonPressed[KeyF3]:
    showPanel = not showPanel
  if window.buttonPressed[KeySpace]:
    paused = not paused
  if window.buttonPressed[KeyR]:
    animTime = 0
  if window.buttonPressed[KeyT]:
    useToon = not useToon
  if window.buttonPressed[KeyW]:
    viewTeam = ViewWest
  if window.buttonPressed[KeyE]:
    viewTeam = ViewEast
  if window.buttonPressed[KeyB]:
    viewTeam = ViewBoth
  if window.buttonPressed[KeyG]:
    showGround = not showGround
  if window.buttonPressed[KeyS]:
    showSkeleton = not showSkeleton
  if window.buttonPressed[KeyLeft]:
    paused = true
    animTime = max(0'f32, animTime - 1'f32 / 60)
  if window.buttonPressed[KeyRight]:
    paused = true
    animTime = min(clipDurationOf(models[WestTeam], selectedClip), animTime + 1'f32 / 60)
  if window.buttonPressed[Key0] or window.buttonPressed[KeyBackspace]:
    selectClip("")
  if window.buttonPressed[Key1] and clipNames.len > 0:
    selectClip(clipNames[0])
  if window.buttonPressed[Key2] and clipNames.len > 1:
    selectClip(clipNames[1])
  if window.buttonPressed[Key3] and clipNames.len > 2:
    selectClip(clipNames[2])
  if window.buttonPressed[Key4] and clipNames.len > 3:
    selectClip(clipNames[3])
  if window.buttonPressed[Key5] and clipNames.len > 4:
    selectClip(clipNames[4])

proc shownTeams(): seq[Team] =
  if compareKnives: return @[WestTeam, EastTeam, WestTeam]
  case viewTeam
  of ViewWest: @[WestTeam]
  of ViewEast: @[EastTeam]
  of ViewBoth: @[WestTeam, EastTeam]

proc teamX(index, count: int): float32 =
  if count == 1: 0'f32
  elif count == 3: (index-1).float32 * 5.6'f32
  elif index == 0: -4.2'f32
  else: 4.2'f32

window.onFrame = proc() =
  let dt = if captureDir.len > 0: 1'f32/60 else: frameDelta(lastFrameTime)
  handleHotkeys()
  if selectedClip != lastSelectedClip:
    selectClip(selectedClip)
  updateCamera()
  if useToon:
    scene.useToonShading()
  else:
    scene.shading = PbrCharacters

  let duration = clipDurationOf(models[WestTeam], selectedClip)
  if autoTurn:
    facing += dt * 0.3
  if not paused and selectedClip.len > 0:
    animTime += dt * playSpeed
    if duration > 0:
      if loopClips:
        animTime = animTime mod duration
      else:
        animTime = min(animTime, duration)

  let
    aspect = window.size.x.float32 / max(window.size.y.float32, 1)
    view = cameraView()
    proj = perspective(45.0'f32, aspect, 0.1'f32, 200.0'f32)
    teams = shownTeams()

  glClearColor(0.05, 0.07, 0.10, 1.0)
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
  beginCharacters(scene, window, view, proj, cameraEye)
  stage.clear()
  if showGround:
    stage.addQuad(vec3(-40,-0.035,-40), vec3(-40,-0.035,40),
      vec3(40,-0.035,40), vec3(40,-0.035,-40), rgbx(27,34,42,254))
    for i in -12..12:
      let p = i.float32 * 2
      stage.addLine(vec3(p,0,-24), vec3(p,0,24), rgbx(60,69,78,100), 0.018)
      stage.addLine(vec3(-24,0,p), vec3(24,0,p), rgbx(60,69,78,100), 0.018)
    for index, team in teams:
      let x = teamX(index, teams.len)
      let c = if team == WestTeam: rgbx(131,67,58,80) else: rgbx(55,92,125,80)
      stage.addCircle(vec3(x,0.015,0), 2.6, c)
    stage.draw(proj * view)
  for index, team in teams:
    let
      legacy = compareLegacy and team == EastTeam and legacyModels[team] != nil
      model = if legacy: legacyModels[team] else: models[team]
      name = if legacy: legacyClip else: selectedClip
      clip = clipIndexOf(model, name)
      x = teamX(index, teams.len)
      knife = ButcherKnife(if compareKnives: index else: KnifeNames.find(knifeName))
      teamColor = if team == WestTeam: rgbx(160,62,46,254) else: rgbx(47,100,153,254)
      sampleTime = if legacy and duration > 0:
        animTime / duration * clipDurationOf(model, name)
        else: animTime
    if propView == ShowCharacter:
      drawCharacter(scene, model, vec3(x, 0, 0), facing, clip, sampleTime)
    weapons.clear()
    if propView != ShowHook:
      let transform = if propView == ShowKnife:
          translate(vec3(x,1.9,0)) * rotateY(facing) * rotateZ(-0.18'f32) * scale(vec3(1.5))
        else:
          butcherKnifeTransform(model.characterJointTransform("L_Hand",vec3(x,0,0),facing))
      weapons.addButcherKnife(transform,knife,teamColor)
    if propView == ShowHook:
      let transform = translate(vec3(x,3,0)) * rotateY(facing) *
        rotateX(PI.float32/2) * scale(vec3(2.5))
      let eye = transform * HookEye
      weapons.addHookChain([eye+vec3(0,2.6,0),eye],size=0.75)
      weapons.addButcherHook(transform,teamColor)
    elif propView == ShowCharacter and not legacy:
      let
        rightHand = model.characterJointTransform("R_Hand",vec3(x,0,0),facing)
        heldRadius = BaseHookRadius.float32 / WorldScale.float32 * HeldHookVisualScale
        thrownRadius = BaseHookRadius.float32 / WorldScale.float32
        release = HookWindupTicks.float32/TickRate.float32
        flying = selectedClip == "ButcherHook" and duration > 0 and
          animTime > release
      if flying:
        let
          flight = clamp((animTime-release)/(duration-release),0'f32,1'f32)
          grip = butcherHeldHookEye(rightHand, facing, heldRadius)
          direction = vec3(sin(facing),0,cos(facing))
          eye = grip + direction*sin(flight*PI.float32)*5.0'f32
          transform = hookTransform(eye, facing, thrownRadius) * translate(-HookEye)
          middle = (grip+eye)*0.5'f32 - vec3(0,0.16,0)
        weapons.addHookChain([grip,middle,eye],size=0.40)
        weapons.addButcherHook(transform,teamColor)
      else:
        weapons.addButcherHook(
          butcherHeldHookTransform(rightHand, facing, heldRadius), teamColor)
    weapons.draw(proj*view,opaque=true)
    if showSkeleton and propView == ShowCharacter:
      stage.clear()
      let transform = translate(vec3(x,0,0)) * rotateY(facing) * model.baseTransform
      proc bones(node: Node, parent: Mat4) =
        let world = parent * node.trs
        for child in node.nodes:
          let childWorld = world * child.trs
          if node.name notin ["Root", "Armature", "Butcher"] and
              not child.name.contains("Twist"):
            stage.addLine(world * vec3(0,0,0), childWorld * vec3(0,0,0),
              rgbx(247,216,112,255), 0.025)
          bones(child, world)
      bones(model.file.root, transform)
      glClear(GL_DEPTH_BUFFER_BIT)
      stage.draw(proj * view)
  finishCharacters(scene)

  glDisable(GL_DEPTH_TEST)
  glDisable(GL_CULL_FACE)
  glDisable(GL_BLEND)
  glDisable(GL_MULTISAMPLE)

  sk.beginUi(window, window.size)
  if showPanel:
    for index, team in teams:
      let world = vec3(teamX(index, teams.len), 7.6, 0)
      let projected = proj * view * vec4(world, 1)
      if projected.w > 0:
        let center = vec2(
          (projected.x / projected.w * 0.5 + 0.5) * window.size.x.float32,
          (0.5 - projected.y / projected.w * 0.5) * window.size.y.float32)
        let label = if propView == ShowHook:
            (if team == WestTeam: "WEST / BUTCHER'S HOOK" else: "EAST / BUTCHER'S HOOK")
          elif compareKnives: KnifeNames[index].toUpperAscii
          elif propView == ShowKnife: knifeName.toUpperAscii
          elif team == WestTeam: "WEST / ORIGINAL PAINT"
          elif compareLegacy: "EAST / OLD EXPERIMENT"
          else: "EAST / BLUE PAINT"
        sk.drawLabel(label, center - vec2(130,12), vec2(260,24),
          rgbx(218,221,226,255), "Small", CenterAlign)
  ui:
    if showPanel:
      subWindow("Workshop", showPanel, vec2(12, 12), vec2(330, 770)):
        text "title":
          characters "BUTCHER / MOTION LAB"
        group "teams":
          box 290, 30
          layout LeftToRight
          radioButton("West", viewTeam, ViewWest)
          radioButton("East", viewTeam, ViewEast)
          radioButton("Both", viewTeam, ViewBoth)
        text "clips":
          characters "MOTION CLIPS"
        dropDown(selectedClip, clipNames)
        group "melee":
          box 290, 30
          layout LeftToRight
          button "Chop [C]":
            selectClip("ButcherChop")
          button "Slash [V]":
            selectClip("ButcherSlash")
        radioButton("Original rest pose", selectedClip, "")
        text "knife":
          characters "BUTCHER'S BLADE [K to cycle]"
        dropDown(knifeName, @KnifeNames)
        text "knifeDescription":
          font "Small"
          characters knifeDescription(ButcherKnife(KnifeNames.find(knifeName)))
        let wasComparing = compareKnives
        checkBox("Compare all three blades", compareKnives)
        if compareKnives != wasComparing:
          cameraDistance = if not compareKnives: 21
            elif propView == ShowKnife: 24 else: 28
        let previousPropView = propView
        group "props":
          box 290, 30
          layout LeftToRight
          radioButton("Character", propView, ShowCharacter)
          radioButton("Knife", propView, ShowKnife)
          radioButton("Hook", propView, ShowHook)
        if compareKnives and propView != previousPropView:
          cameraDistance = if propView == ShowKnife: 24 else: 28
        text "description":
          font "Small"
          characters clipDescription(selectedClip)
        group "playback":
          box 290, 30
          layout LeftToRight
          checkBox("Loop", loopClips)
          checkBox("Pause", paused)
          button "Restart":
            animTime = 0
        text "speed":
          characters &"Speed: {playSpeed:.2f}"
        scrubber("speed", playSpeed, 0.0'f32, 3.0'f32, "")
        if duration > 0:
          text "time":
            characters &"Time: {animTime:.2f} / {duration:.2f}s"
          let beforeScrub = animTime
          scrubber("time", animTime, 0.0'f32, duration, "")
          if animTime != beforeScrub:
            paused = true
        group "stage":
          box 290, 30
          layout LeftToRight
          checkBox("Floor", showGround)
          checkBox("Bones", showSkeleton)
          checkBox("Toon", useToon)
        checkBox("Turntable", autoTurn)
        checkBox("East: compare old experiment", compareLegacy)
        if compareLegacy and legacyModels[EastTeam] != nil:
          let oldNames = collectClipNames(legacyModels[EastTeam])
          dropDown(legacyClip, oldNames)
          viewTeam = ViewBoth
        text "help1":
          font "Small"
          characters "F3 panel  Space pause  R restart"
        text "help2":
          font "Small"
          characters "1-5 clips  0 bind  arrows step"
        text "help3":
          font "Small"
          characters "Drag orbit / right-drag pan"
        text "help4":
          font "Small"
          characters "W/E/B team / scroll zoom"
  sk.endUi()
  if captureDir.len > 0:
    let frame = newImage(window.size.x, window.size.y)
    glReadPixels(0, 0, window.size.x.GLsizei, window.size.y.GLsizei,
      GL_RGBA, GL_UNSIGNED_BYTE, frame.data[0].addr)
    frame.flipVertical()
    frame.writeFile(captureDir / &"frame{captureFrame:04}.png")
    inc captureFrame
    if captureFrame >= captureFrames:
      quit(0)
  else:
    captureScreenshot(window, screenshotFrame, 1, "tmp/butcher_workshop.png")
  present(window)

while not window.closeRequested:
  pollEvents()
