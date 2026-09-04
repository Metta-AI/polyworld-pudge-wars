function arenaGeometry(message) {
  return {
    width: message.width || 128,
    height: message.height || 128,
    riverWest: message.river_west || 53,
    riverEast: message.river_east || 75
  }
}

function pudgesFrom(message) {
  if (message.pudges) return message.pudges
  if (message.visible && message.visible.pudges) return message.visible.pudges
  return []
}

function hooksFrom(message) {
  if (message.hooks) return message.hooks
  if (message.visible && message.visible.hooks) return message.visible.hooks
  return []
}

function drawArena(canvas, message, options) {
  const ctx = canvas.getContext('2d')
  const geo = arenaGeometry(message)
  const pad = 10
  const scale = Math.min(
    (canvas.width - pad * 2) / geo.width,
    (canvas.height - pad * 2) / geo.height
  )
  const ox = (canvas.width - geo.width * scale) / 2
  const oy = (canvas.height - geo.height * scale) / 2
  ctx.clearRect(0, 0, canvas.width, canvas.height)
  ctx.fillStyle = '#1a3a28'
  ctx.fillRect(ox, oy, geo.width * scale, geo.height * scale)
  ctx.fillStyle = '#2a5a9a'
  ctx.fillRect(
    ox + geo.riverWest * scale,
    oy,
    (geo.riverEast - geo.riverWest) * scale,
    geo.height * scale
  )
  ctx.fillStyle = 'rgba(255,255,255,0.08)'
  ctx.fillRect(ox, oy, geo.riverWest * scale, geo.height * scale)
  ctx.fillRect(
    ox + geo.riverEast * scale,
    oy,
    (geo.width - geo.riverEast) * scale,
    geo.height * scale
  )
  const toX = (x) => ox + x * scale
  const toY = (y) => oy + y * scale
  for (const hook of hooksFrom(message)) {
    ctx.strokeStyle = hook.team === 0 ? '#7dd3fc' : '#fda4af'
    ctx.lineWidth = 2
    const owner = pudgesFrom(message).find((p) => p.slot === hook.owner)
    if (owner) {
      ctx.beginPath()
      ctx.moveTo(toX(owner.x), toY(owner.y))
      ctx.lineTo(toX(hook.x), toY(hook.y))
      ctx.stroke()
    }
    ctx.fillStyle = '#fef08a'
    ctx.beginPath()
    ctx.arc(toX(hook.x), toY(hook.y), 4, 0, Math.PI * 2)
    ctx.fill()
  }
  for (const rune of (message.visible && message.visible.runes) || message.runes || []) {
    ctx.fillStyle = '#fde047'
    ctx.beginPath()
    ctx.arc(toX(rune.x), toY(rune.y), 5, 0, Math.PI * 2)
    ctx.fill()
  }
  const names = message.player_names || []
  for (const pudge of pudgesFrom(message)) {
    const color = pudge.team === 0 ? '#38bdf8' : '#fb7185'
    ctx.globalAlpha = pudge.alive ? 1 : 0.35
    ctx.fillStyle = color
    ctx.beginPath()
    ctx.arc(toX(pudge.x), toY(pudge.y), 8, 0, Math.PI * 2)
    ctx.fill()
    if (pudge.shield) {
      ctx.strokeStyle = '#f8fafc'
      ctx.lineWidth = 2
      ctx.stroke()
    }
    ctx.globalAlpha = 1
    ctx.fillStyle = '#0f172a'
    ctx.font = '10px sans-serif'
    ctx.textAlign = 'center'
    ctx.fillText(String(pudge.slot + 1), toX(pudge.x), toY(pudge.y) + 3)
    if (options && options.showNames && names[pudge.slot]) {
      ctx.fillStyle = '#e2e8f0'
      ctx.fillText(names[pudge.slot], toX(pudge.x), toY(pudge.y) - 12)
    }
  }
  return { ox, oy, scale, geo }
}

function worldFromEvent(canvas, event, transform) {
  const rect = canvas.getBoundingClientRect()
  const x = ((event.clientX - rect.left) * canvas.width) / rect.width
  const y = ((event.clientY - rect.top) * canvas.height) / rect.height
  return {
    x: (x - transform.ox) / transform.scale,
    y: (y - transform.oy) / transform.scale
  }
}

function scoreLine(message) {
  const score = message.score || { west: 0, east: 0 }
  const goal = message.kill_goal || 0
  return `West ${score.west} – ${score.east} East  (first to ${goal})  tick ${message.tick}/${message.max_ticks}`
}
