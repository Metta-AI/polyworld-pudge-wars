// Prisma-style cinematic void + pixel-arc loader for the WASM boot
// overlay. Separate canvas from the game. dispose() before the first
// game frame so Emscripten keeps WebGL.
import * as THREE from 'three'

var BONE = 0xe1e0cc
var VOID = 0x07080b
var BLOOD = 0xdc4840

function prefersReduce () {
  return window.matchMedia &&
    window.matchMedia('(prefers-reduced-motion: reduce)').matches
}

function paintBar (progress, errored) {
  var bar = document.getElementById('bootBar')
  if (!bar) return
  bar.style.width = Math.round(Math.max(0.08, progress) * 100) + '%'
  bar.style.background = errored ? '#f0a8a2' : '#e1e0cc'
}

export function mountBootScene (host) {
  if (!host || host.querySelector('[data-pw-void]')) return null
  if (typeof WebGLRenderingContext === 'undefined') return null

  paintBar(0.08, false)

  var canvas = document.createElement('canvas')
  canvas.setAttribute('data-pw-void', '')
  canvas.setAttribute('aria-hidden', 'true')
  host.insertBefore(canvas, host.firstChild)

  var renderer
  try {
    renderer = new THREE.WebGLRenderer({
      canvas: canvas,
      antialias: true,
      alpha: false,
      powerPreference: 'low-power'
    })
  } catch (err) {
    canvas.remove()
    return null
  }

  renderer.setClearColor(VOID, 1)
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.5))
  renderer.outputColorSpace = THREE.SRGBColorSpace

  var scene = new THREE.Scene()
  scene.fog = new THREE.Fog(VOID, 10, 26)

  var camera = new THREE.PerspectiveCamera(42, 1, 0.1, 40)
  camera.position.set(0, 4.2, 8.8)
  camera.lookAt(0, 0.15, 0)

  scene.add(new THREE.AmbientLight(0xffffff, 0.32))
  var key = new THREE.DirectionalLight(0xe1e0cc, 0.95)
  key.position.set(5, 8, 3)
  scene.add(key)
  var pool = new THREE.PointLight(0xff6a28, 1.8, 14, 2)
  pool.position.set(0, 2.4, 0)
  scene.add(pool)
  var westLight = new THREE.PointLight(0xe07a4a, 1.1, 9, 2)
  westLight.position.set(-5, 1.6, 1)
  scene.add(westLight)
  var eastLight = new THREE.PointLight(0x7ad4c8, 1.0, 9, 2)
  eastLight.position.set(5, 1.6, -1)
  scene.add(eastLight)

  var coals = new THREE.Mesh(
    new THREE.PlaneGeometry(28, 18),
    new THREE.MeshStandardMaterial({
      color: 0x140804,
      metalness: 0.22,
      roughness: 0.72,
      emissive: 0x3a1208,
      emissiveIntensity: 0.35
    })
  )
  coals.rotation.x = -Math.PI / 2
  coals.position.y = -0.22
  scene.add(coals)

  var pit = new THREE.Mesh(
    new THREE.PlaneGeometry(3.4, 16),
    new THREE.MeshStandardMaterial({
      color: 0x4a1408,
      metalness: 0.18,
      roughness: 0.42,
      emissive: 0xff4a14,
      emissiveIntensity: 0.85,
      transparent: true,
      opacity: 0.92
    })
  )
  pit.rotation.x = -Math.PI / 2
  pit.position.y = -0.12
  scene.add(pit)

  var grate = new THREE.Mesh(
    new THREE.PlaneGeometry(3.6, 16),
    new THREE.MeshStandardMaterial({
      color: 0x2a2018,
      metalness: 0.62,
      roughness: 0.38,
      emissive: 0x1a0c06,
      emissiveIntensity: 0.2,
      transparent: true,
      opacity: 0.35
    })
  )
  grate.rotation.x = -Math.PI / 2
  grate.position.y = -0.08
  scene.add(grate)

  var westBank = new THREE.Mesh(
    new THREE.BoxGeometry(3.6, 0.55, 9.2),
    new THREE.MeshStandardMaterial({
      color: 0x2a1c16,
      roughness: 0.82,
      metalness: 0.12
    })
  )
  westBank.position.set(-5.5, 0.22, 0)
  var eastBank = new THREE.Mesh(
    new THREE.BoxGeometry(3.6, 0.55, 9.2),
    new THREE.MeshStandardMaterial({
      color: 0x162228,
      roughness: 0.82,
      metalness: 0.12
    })
  )
  eastBank.position.set(5.5, 0.22, 0)
  scene.add(westBank, eastBank)

  var agents = new THREE.Group()
  var spots = [
    [-4.25, 0.38, -1.25],
    [-4.25, 0.38, 0],
    [-4.25, 0.38, 1.25],
    [4.25, 0.38, -1.25],
    [4.25, 0.38, 0],
    [4.25, 0.38, 1.25]
  ]
  var i
  for (i = 0; i < spots.length; i++) {
    var mesh = new THREE.Mesh(
      new THREE.IcosahedronGeometry(0.13, 0),
      new THREE.MeshStandardMaterial({
        color: i < 3 ? 0xe07a4a : 0x7ad4c8,
        emissive: i < 3 ? 0xe07a4a : 0x3d8a80,
        emissiveIntensity: 0.35,
        roughness: 0.35
      })
    )
    mesh.position.fromArray(spots[i])
    agents.add(mesh)
  }
  scene.add(agents)

  var progress = 0.08
  var target = 0.08
  var errored = false
  var still = prefersReduce()
  var raf = 0
  var disposed = false
  var t0 = performance.now()

  function resize () {
    var w = host.clientWidth || window.innerWidth
    var h = host.clientHeight || window.innerHeight
    renderer.setSize(w, h, false)
    camera.aspect = w / Math.max(h, 1)
    camera.updateProjectionMatrix()
  }

  function setProgress (n) {
    target = Math.max(0.08, Math.min(1, n))
  }

  function setError (on) {
    errored = !!on
    paintBar(progress, errored)
  }

  function paint (now) {
    if (disposed) return
    var t = (now - t0) / 1000
    progress += (target - progress) * 0.06
    paintBar(progress, errored)

    var flicker = still ? 0 : Math.sin(t * 7.2) * 0.12 + Math.sin(t * 11.4) * 0.06
    pool.intensity = 1.35 + progress * 0.7 + flicker
    pool.color.setHex(errored ? BLOOD : 0xff6a28)
    pit.material.emissive.setHex(errored ? BLOOD : 0xff4a14)
    pit.material.emissiveIntensity = 0.72 + progress * 0.35 + flicker

    if (!still) {
      for (i = 0; i < agents.children.length; i++) {
        agents.children[i].position.y =
          0.38 + Math.sin(t * 1.15 + i * 0.9) * 0.1
      }
      camera.position.x = Math.sin(t * 0.12) * 1.7
      camera.position.y = 4.15 + Math.sin(t * 0.09) * 0.22
      camera.position.z = 8.7 + Math.cos(t * 0.1) * 0.35
      camera.lookAt(0, 0.15, 0)
    }

    renderer.render(scene, camera)
    raf = requestAnimationFrame(paint)
  }

  function dispose () {
    if (disposed) return
    disposed = true
    cancelAnimationFrame(raf)
    window.removeEventListener('resize', resize)
    scene.traverse(function (obj) {
      if (obj.geometry) obj.geometry.dispose()
      if (obj.material) {
        if (Array.isArray(obj.material)) {
          obj.material.forEach(function (m) { m.dispose() })
        } else {
          obj.material.dispose()
        }
      }
    })
    renderer.dispose()
    if (renderer.forceContextLoss) renderer.forceContextLoss()
    if (canvas.parentNode) canvas.parentNode.removeChild(canvas)
  }

  resize()
  window.addEventListener('resize', resize)
  raf = requestAnimationFrame(paint)

  var api = {
    setProgress: setProgress,
    setError: setError,
    dispose: dispose
  }
  window.pwBoot = api
  return api
}

mountBootScene(document.getElementById('boot'))
