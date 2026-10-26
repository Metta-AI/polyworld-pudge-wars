## Layout and hit-region checks for the compact, three-panel Pudge HUD.
import vmath, polyworld/gameuis, ../examples/pudge_wars/hudlayout

for window in [vec2(640, 360), vec2(800, 600), vec2(1024, 768),
    vec2(1280, 1000), vec2(1920, 1080), vec2(2560, 1440),
    vec2(3440, 1440), vec2(5120, 1440), vec2(5120, 2160)]:
  let scale = pudgeHudScale(window)
  let size = window / scale
  doAssert scale <= 1.25
  for transportHeight in [0.0'f32, 20.0'f32]:
    let hud = placePudgeHud(size, transportHeight)
    let panels = [hud.bar, hud.minimap, hud.inventory, hud.chat, hud.shop]
    for panel in panels:
      doAssert panel.inside(size), $window & ": offscreen panel"
      doAssert panel.origin.y + panel.size.y <= size.y - transportHeight
    doAssert not panelsOverlap(panels), $window & ": overlapping panels"
    doAssert abs(hud.bar.origin.x + hud.bar.size.x / 2 - size.x / 2) < 0.01
    doAssert hud.minimap.origin.x < hud.bar.origin.x
    doAssert hud.inventory.origin.x > hud.bar.origin.x + hud.bar.size.x
    doAssert hud.minimap.size.y * scale <= window.y * 0.26
    # Every action uses the same rectangle for drawing and clicking.
    doAssert not panelsOverlap(hud.actions)
    for action in hud.actions:
      doAssert hud.bar.contains(action.origin)
      doAssert hud.bar.contains(action.origin + action.size - vec2(0.1))
      doAssert not action.overlaps(hud.hpBar)
      doAssert not action.overlaps(hud.resourceBar)
      let mousePixels = (action.origin + action.size / 2) * scale
      doAssert action.contains(mousePixels / scale)
    # The square map accepts corner clicks, including the former circular dead zone.
    let map = hud.minimap.minimapMap()
    doAssert map.contains(map.origin + vec2(1))
    doAssert map.contains(map.origin + map.size - vec2(1))
    doAssert not map.overlaps(hud.buttons)

doAssert pudgeHudScale(vec2(3440, 1440)) == pudgeHudScale(vec2(5120, 1440)),
  "extra ultrawide width must not enlarge the HUD"

# Browser viewers lay out in CSS pixels (physical size / density).
doAssert screenHudScale(vec2(1170, 2532), 3) == 3
doAssert screenHudScale(vec2(2360, 1640), 2) == 2
doAssert screenHudScale(vec2(1920, 1080), 1) == 1
doAssert screenHudScale(vec2(5120, 1440), 1) == 1.25

for css in [vec2(390, 844), vec2(844, 390), vec2(820, 1180), vec2(1180, 820)]:
  for transportHeight in [0.0'f32, 44.0'f32]:
    let hud = placePudgeHud(css, transportHeight)
    let panels = [hud.bar, hud.minimap, hud.inventory, hud.chat, hud.shop]
    for panel in panels:
      doAssert panel.inside(css), $css & " t=" & $transportHeight &
        ": offscreen " & $panel
      if panel.size.x > 0:
        doAssert panel.origin.y + panel.size.y <= css.y - transportHeight + 0.01,
          $css & ": panel crosses the transport"
    doAssert not panelsOverlap(panels), $css & " t=" & $transportHeight &
      ": overlapping panels"
    doAssert not panelsOverlap(hud.actions)
    for action in hud.actions:
      doAssert hud.bar.contains(action.origin), $css & ": action outside bar"
      doAssert hud.bar.contains(action.origin + action.size - vec2(0.1))
      doAssert not action.overlaps(hud.hpBar)
      doAssert not action.overlaps(hud.resourceBar)
    let map = hud.minimap.minimapMap()
    doAssert map.contains(map.origin + vec2(1))
    doAssert map.contains(map.origin + map.size - vec2(1))
    doAssert not map.overlaps(hud.buttons)

echo "test_pw_hudlayout: all checks passed"
