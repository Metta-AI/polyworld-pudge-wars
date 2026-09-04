## Shared graphical viewer bootstrap for Polyworld games.

import
  std/[math, os, strutils, times],
  opengl, pixie, silky, vmath, windy,
  common, player

const
  DefaultWindowSize* = ivec2(1280, 800)
  DefaultFontPath* = DataRoot & "/fonts/Rubik-Regular.ttf"
  BoldFontPath* = DataRoot & "/fonts/Rubik-Bold.ttf"
  MonoFontPath* = DataRoot & "/fonts/OverpassMono-Regular.ttf"
  MainThemeDir* = DataRoot & "/themes/main/"
  UiDir* = DataRoot & "/ui/"
  IconDir* = DataRoot & "/icons/"
  HudIconSize = 64

proc damping*(rate, dt: float32): float32 =
  ## Returns a frame-rate-independent exponential easing fraction.
  1.0'f32 - exp(-rate * dt)

proc shortestTurn*(current, target: float32): float32 =
  ## Returns the shortest signed turn between two yaw angles.
  var delta = target - current
  while delta > PI.float32:
    delta -= (2 * PI).float32
  while delta < -PI.float32:
    delta += (2 * PI).float32
  delta

proc addDefaultFonts*(builder: AtlasBuilder) =
  ## Adds the shared HUD type ramp used by every graphical client.
  builder.addFont(BoldFontPath, "H1", 32.0)
  builder.addFont(DefaultFontPath, "Default", 18.0)
  builder.addFont(DefaultFontPath, "Hud", 15.0)
  builder.addFont(DefaultFontPath, "Small", 12.0)
  if fileExists(MonoFontPath):
    builder.addFont(MonoFontPath, "Mono", 18.0)

proc addHudGlyphs(builder: AtlasBuilder) =
  ## Packs the shared transport and HUD glyphs every game can draw.
  for file in walkDir(IconDir):
    if not file.path.endsWith(".png"):
      continue
    let
      name = splitFile(file.path).name
      icon = readImage(file.path).resize(HudIconSize, HudIconSize)
    if not builder.addImage(name, icon):
      raise newException(
        ValueError,
        "the UI atlas is too small for HUD icons"
      )

proc newHudAtlas*(size = 1024): AtlasBuilder =
  ## Starts an atlas with the shared main theme and UI images.
  result = newAtlasBuilder(size, 4)
  result.addDir(MainThemeDir, MainThemeDir)
  result.addDir(UiDir, UiDir)
  result.addHudGlyphs()

proc gameWindowSize*(width, height: int32): IVec2 =
  ## Returns a requested window size, or the shared default.
  if width > 0 and height > 0:
    ivec2(width, height)
  else:
    DefaultWindowSize

when defined(macosx) and not defined(emscripten):
  {.passL: "-framework Cocoa".}
  {.compile: "macos_appicon.m".}
  proc polyworldSetApplicationIcon(path: cstring) {.importc, cdecl.}

proc applyWindowIcon(window: Window, path: string) =
  ## Sets the Dock / taskbar / window icon when a PNG is on disk.
  if path.len == 0 or not fileExists(path):
    return
  when defined(emscripten):
    discard
  else:
    window.icon = readImage(path)
    when defined(macosx):
      polyworldSetApplicationIcon(path.cstring)

when defined(emscripten):
  {.emit: """#include <emscripten.h>""".}

proc viewerIsFullscreen*(window: Window): bool =
  ## True when the OS or browser has taken this viewer full screen.
  ## Windowed and in-page viewers stay false so edge-scroll does not
  ## fire while the pointer is leaving toward chrome.
  when defined(emscripten):
    discard window
    var flag: cint = 0
    {.emit: """
    `flag` = EM_ASM_INT({
      var d = typeof document === 'undefined' ? null : document;
      if (d && (d.fullscreenElement || d.webkitFullscreenElement ||
          d.mozFullScreenElement || d.msFullscreenElement))
        return 1;
      if (typeof screen === 'undefined') return 0;
      return (window.innerWidth >= screen.width - 16 &&
              window.innerHeight >= screen.height - 16) ? 1 : 0;
    });
    """.}
    flag != 0
  else:
    window.fullscreen

proc initGameWindow*(
    title,
    atlasPath: string,
    size = DefaultWindowSize,
    vsync = true,
    iconPath = ""
): (Window, Silky) =
  ## Creates the spectator window, GL context, and Silky atlas client.
  let window = newWindow(title, size, vsync = vsync)
  applyWindowIcon(window, iconPath)
  window.makeContextCurrent()
  loadExtensions()
  let sk = newSilky(window, atlasPath)
  window.runeInputEnabled = true
  window.onRune = proc(rune: Rune) =
    sk.inputRunes.add(rune)
  (window, sk)

var
  presentDeadline = 0.0
  presentPaceHz = 0

proc present*(window: Window, paceHz = 0) =
  ## Swaps the back buffer, then optionally waits so presents stay on one
  ## cadence. Zero lets the window's vsync set the rate. ProMotion vsync
  ## alone flips between 8.33 ms and 16.67 ms.
  window.swapBuffers()
  when defined(emscripten):
    discard
  else:
    if paceHz <= 0:
      presentDeadline = 0
      presentPaceHz = 0
      return
    if paceHz != presentPaceHz:
      presentDeadline = 0
      presentPaceHz = paceHz
    let
      step = 1.0 / paceHz.float64
      now = epochTime()
    if presentDeadline <= 0 or now > presentDeadline + step * 2:
      presentDeadline = now + step
      return
    let remain = presentDeadline - now
    if remain > 0.001:
      sleep(int(remain * 1000.0))
    presentDeadline += step

proc presentFrame*(window: Window, paceHz = 0) {.inline.} =
  ## Alias for `present`.
  window.present(paceHz)

proc frameDelta*(
    lastFrameTime: var float64,
    captureStep = 1.0'f32 / 60.0'f32
): float32 =
  ## Returns clamped wall-clock dt, or a fixed step when capturing.
  let now = epochTime()
  result = clamp(now - lastFrameTime, 0.0, 0.1).float32
  lastFrameTime = now
  when defined(takeScreenshot):
    result = captureStep

proc simulationActive*(transport: Player): bool =
  ## Returns whether presentation should advance on this frame.
  transport.playing or transport.targetTick >= 0

proc atLiveTickCap*(tick, maximumTicks: int32, live: bool): bool =
  ## Returns whether a live match has used its configured tick budget.
  live and tick >= maximumTicks

proc applyScreenshotCamera*(cameraDistance: var float32) =
  ## Overrides camera distance from CAM_DIST when capturing.
  when defined(takeScreenshot):
    if existsEnv("CAM_DIST"):
      cameraDistance = getEnv("CAM_DIST").parseFloat.float32
  else:
    discard cameraDistance

proc captureScreenshot*(
    window: Window,
    frame: var int,
    waitFrames: int,
    defaultPath: string
) =
  ## Writes one back-buffer capture after waitFrames when capturing.
  when defined(takeScreenshot):
    inc frame
    if frame < waitFrames:
      return
    let
      path =
        if existsEnv("SCREENSHOT_PATH"):
          getEnv("SCREENSHOT_PATH")
        else:
          defaultPath
      image = newImage(window.size.x, window.size.y)
    glReadPixels(
      0,
      0,
      window.size.x.GLsizei,
      window.size.y.GLsizei,
      GL_RGBA,
      GL_UNSIGNED_BYTE,
      image.data[0].addr
    )
    image.flipVertical()
    image.writeFile(path)
    quit(0)
  else:
    discard (window, frame, waitFrames, defaultPath)
