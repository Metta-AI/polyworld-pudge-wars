// Touch bridge for phones and tablets. Windy's browser backend only
// listens for mouse, wheel, and keyboard events, so this file turns
// touches into the mouse input the game already understands:
//
//   tap                  left click (pick a butcher, transport, minimap)
//   one-finger drag      world: middle-button pan; HUD: left drag (scrub)
//   two-finger pinch     wheel zoom
//   two-finger drag      middle-button pan
//
// It also caps the canvas backing store. A 3x phone would otherwise
// render every frame at full device resolution, which costs fill rate
// and memory for detail nobody can see at arm's length.
//
// Load before pw.js: windy reads devicePixelRatio when it sizes the
// canvas, and every mouse coordinate is scaled by the same ratio, so
// overriding it here keeps picks and pixels consistent.
(function () {
  var coarse = window.matchMedia &&
    window.matchMedia('(pointer: coarse)').matches
  if (!coarse) return

  var MaxRatio = 2
  var PixelBudget = 2560 * 1440
  var TapSlop = 10
  var TapMillis = 350

  var nativeRatio = window.devicePixelRatio || 1
  function cappedRatio () {
    var area = Math.max(1, window.innerWidth * window.innerHeight)
    var budget = Math.sqrt(PixelBudget / area)
    return Math.max(1, Math.min(nativeRatio, MaxRatio, budget))
  }
  try {
    Object.defineProperty(window, 'devicePixelRatio', {
      configurable: true,
      get: cappedRatio
    })
  } catch (err) {}

  var gesture = null

  function canvas () {
    return document.getElementById('canvas')
  }

  function mouse (type, x, y, button) {
    var target = canvas()
    if (!target) return
    // `buttons` mirrors what is held after this event so windy's
    // button state matches a real mouse.
    var held = type === 'mouseup' || button < 0 ? 0 : button === 1 ? 4 : 1
    target.dispatchEvent(new MouseEvent(type, {
      bubbles: true,
      cancelable: true,
      clientX: x,
      clientY: y,
      button: Math.max(0, button),
      buttons: held
    }))
  }

  // Windy scales wheel deltas by -1 when navigator.platform says Mac and
  // by 0.2 otherwise (an iPhone or Android). Pre-scale so a pinch zooms
  // the same way and amount everywhere; iPadOS reports MacIntel.
  var wheelScale = /Mac/.test(navigator.platform || '') ? 1 : -5

  function wheel (x, y, deltaY) {
    var target = canvas()
    if (!target) return
    deltaY *= wheelScale
    target.dispatchEvent(new WheelEvent('wheel', {
      bubbles: true,
      cancelable: true,
      clientX: x,
      clientY: y,
      deltaY: deltaY,
      deltaMode: 0
    }))
  }

  function overHud (x, y) {
    // The game answers in its own HUD layout when the build exports it.
    var probe = window.Module && window.Module._pwPointerOverUi
    if (probe) return probe(x, y) !== 0
    return y > window.innerHeight * 0.72
  }

  function midpoint (touches) {
    return {
      x: (touches[0].clientX + touches[1].clientX) / 2,
      y: (touches[0].clientY + touches[1].clientY) / 2
    }
  }

  function spread (touches) {
    var dx = touches[0].clientX - touches[1].clientX
    var dy = touches[0].clientY - touches[1].clientY
    return Math.sqrt(dx * dx + dy * dy)
  }

  function release () {
    if (gesture && gesture.button >= 0) {
      mouse('mouseup', gesture.x, gesture.y, gesture.button)
    }
    gesture = null
  }

  function onStart (event) {
    event.preventDefault()
    var touches = event.touches
    if (touches.length >= 2) {
      release()
      var mid = midpoint(touches)
      mouse('mousemove', mid.x, mid.y, -1)
      mouse('mousedown', mid.x, mid.y, 1)
      gesture = {
        kind: 'pinch',
        button: 1,
        x: mid.x,
        y: mid.y,
        spread: spread(touches)
      }
      return
    }
    if (gesture) return
    var t = touches[0]
    mouse('mousemove', t.clientX, t.clientY, -1)
    gesture = {
      kind: 'one',
      button: -1,
      hud: overHud(t.clientX, t.clientY),
      x: t.clientX,
      y: t.clientY,
      startX: t.clientX,
      startY: t.clientY,
      began: performance.now()
    }
    // HUD presses go down at once so scrub bars and the minimap feel
    // like a mouse. World presses wait to see tap versus drag.
    if (gesture.hud) {
      gesture.button = 0
      mouse('mousedown', t.clientX, t.clientY, 0)
    }
  }

  function onMove (event) {
    event.preventDefault()
    if (!gesture) return
    var touches = event.touches
    if (gesture.kind === 'pinch') {
      if (touches.length < 2) return
      var mid = midpoint(touches)
      var next = spread(touches)
      gesture.x = mid.x
      gesture.y = mid.y
      mouse('mousemove', mid.x, mid.y, 1)
      if (gesture.spread > 0 && next > 0) {
        // Fingers apart zooms in, like the wheel rolling forward.
        var deltaY = Math.log(gesture.spread / next) * 600
        if (Math.abs(deltaY) > 0.5) wheel(mid.x, mid.y, deltaY)
      }
      gesture.spread = next
      return
    }
    var t = touches[0]
    gesture.x = t.clientX
    gesture.y = t.clientY
    if (gesture.button < 0) {
      var dx = t.clientX - gesture.startX
      var dy = t.clientY - gesture.startY
      if (dx * dx + dy * dy < TapSlop * TapSlop) return
      gesture.button = 1
      mouse('mousedown', gesture.startX, gesture.startY, 1)
    }
    mouse('mousemove', t.clientX, t.clientY, gesture.button)
  }

  function onEnd (event) {
    event.preventDefault()
    if (!gesture) return
    if (gesture.kind === 'pinch') {
      if (event.touches.length === 0) release()
      return
    }
    if (gesture.button < 0 &&
        performance.now() - gesture.began < TapMillis) {
      mouse('mousedown', gesture.x, gesture.y, 0)
      mouse('mouseup', gesture.x, gesture.y, 0)
      gesture = null
      return
    }
    release()
  }

  // The HUD is laid out for a wide screen; portrait clips the score and
  // shows a sliver of the arena. Suggest turning the phone, briefly.
  var RotateHintMillis = 4000
  var rotateHint = null
  function updateRotateHint () {
    var portrait = window.innerHeight > window.innerWidth
    if (!portrait) {
      if (rotateHint) rotateHint.style.opacity = '0'
      return
    }
    if (rotateHint) return
    rotateHint = document.createElement('div')
    rotateHint.textContent = 'Turn your phone sideways to see the whole arena'
    rotateHint.style.cssText = [
      'position:fixed', 'left:50%', 'top:42%', 'transform:translateX(-50%)',
      'z-index:5', 'padding:10px 16px', 'max-width:calc(100vw - 32px)',
      'box-sizing:border-box', 'text-align:center',
      'font:500 14px/1.4 "Avenir Next","Segoe UI",system-ui,sans-serif',
      'color:#e1e0cc', 'background:rgba(7,8,11,0.82)',
      'pointer-events:none', 'transition:opacity 0.4s ease'
    ].join(';')
    document.body.appendChild(rotateHint)
    setTimeout(function () { rotateHint.style.opacity = '0' }, RotateHintMillis)
  }

  function attach () {
    var target = canvas()
    if (!target) return
    updateRotateHint()
    window.addEventListener('resize', updateRotateHint)
    var opts = { passive: false }
    target.addEventListener('touchstart', onStart, opts)
    target.addEventListener('touchmove', onMove, opts)
    target.addEventListener('touchend', onEnd, opts)
    target.addEventListener('touchcancel', onEnd, opts)
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', attach)
  } else {
    attach()
  }
})()
