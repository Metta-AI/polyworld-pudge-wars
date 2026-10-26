// Live match bridge for the WASM client. Nim echoes `pw-state:{json}`
// while the match runs, then `pw-match:{json}` and `pw-nav:recap|home`.
// Join progress still arrives as `join:` lines. The site wraps this
// page in an iframe and listens on postMessage.
(function () {
  var recap = null
  var live = {
    phase: 'boot',
    tick: 0,
    seconds: 0,
    killGoal: 30,
    west: 0,
    east: 0,
    you: -1,
    started: false,
    finished: false,
    note: 'Loading arena'
  }

  function siteRoot() {
    var path = location.pathname
    var play = path.lastIndexOf('/play/')
    if (play >= 0) return location.origin + path.slice(0, play + 1)
    return location.origin + '/'
  }

  function inSiteFrame() {
    try {
      return window.parent && window.parent !== window &&
        window.parent.location.origin === location.origin
    } catch (err) {
      return window.parent && window.parent !== window
    }
  }

  function isSiteWithRecap() {
    if (inSiteFrame()) return true
    var host = location.hostname
    var port = location.port
    if (host === 'pudgewars.com' || host === 'www.pudgewars.com') return true
    if (/\.vercel\.app$/.test(host)) return true
    if (
      (host === 'localhost' || host === '127.0.0.1') &&
      (port === '' || port === '3000' || port === '3001' || port === '3005')
    ) {
      return true
    }
    return false
  }

  function derive(next) {
    next.started = next.phase === 'starting' ||
      next.phase === 'live' ||
      next.phase === 'over' ||
      (next.tick || 0) > 0
    next.finished = next.phase === 'over'
    return next
  }

  function saveRecap() {
    if (!recap) return
    try {
      sessionStorage.setItem('pw-recap', JSON.stringify(recap))
    } catch (err) {}
  }

  function saveLive() {
    try {
      sessionStorage.setItem('pw-live', JSON.stringify(live))
    } catch (err) {}
  }

  function post(kind, payload) {
    if (!inSiteFrame()) return
    try {
      var msg = { source: 'pudge-wars', kind: kind }
      if (kind === 'nav') msg.to = payload
      else msg.data = payload
      window.parent.postMessage(msg, location.origin)
    } catch (err) {}
  }

  function emitLive(patch) {
    for (var key in patch) {
      if (Object.prototype.hasOwnProperty.call(patch, key)) {
        live[key] = patch[key]
      }
    }
    live = derive(live)
    saveLive()
    post('state', live)
  }

  function goHome() {
    saveRecap()
    if (inSiteFrame()) {
      post('nav', 'home')
      return
    }
    location.href = siteRoot()
  }

  function goRecap() {
    saveRecap()
    if (inSiteFrame()) {
      post('nav', 'recap')
      return
    }
    if (isSiteWithRecap()) {
      location.href = siteRoot() + 'recap'
      return
    }
    showOverlay(true)
  }

  function headline(data) {
    if (data.headline === 'victory') return 'Victory'
    if (data.headline === 'defeat') return 'Defeat'
    if (data.winner === 'west') return 'West wins'
    return 'East wins'
  }

  function clock(seconds) {
    var m = Math.floor((seconds || 0) / 60)
    var s = (seconds || 0) % 60
    return m + ':' + String(s).padStart(2, '0')
  }

  function playerRows(data) {
    var players = data.players || []
    var html = ''
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      html +=
        '<tr>' +
        '<td>P' + p.id + (p.you ? ' (you)' : '') + '</td>' +
        '<td>' + p.team + '</td>' +
        '<td>' + (p.kills || 0) + '</td>' +
        '<td>' + (p.deaths || 0) + '</td>' +
        '<td>' + (p.hooksLanded || 0) + '/' + (p.hooksThrown || 0) + '</td>' +
        '<td>' + (p.headshots || 0) + '</td>' +
        '<td>' + (p.denies || 0) + '</td>' +
        '</tr>'
    }
    return html
  }

  function showOverlay(expanded) {
    if (inSiteFrame()) return
    if (!document.getElementById('pwRecapStyle')) {
      var style = document.createElement('style')
      style.id = 'pwRecapStyle'
      style.textContent =
        '#pwRecap{position:fixed;inset:0;z-index:20;display:flex;align-items:flex-end;justify-content:center;padding:24px;pointer-events:none}' +
        '.pw-recap-card{pointer-events:auto;width:min(560px,100%);margin-bottom:28px;padding:18px 20px 16px;background:rgba(7,8,11,.92);border:1px solid #c8ff3d;color:#e1e0cc;font-family:"Avenir Next","Segoe UI",system-ui,sans-serif;text-align:center}' +
        '.pw-recap-kicker{margin:0;font-size:11px;letter-spacing:.18em;text-transform:uppercase;color:#6b7380}' +
        '#pwRecapHead{margin:6px 0 4px;font-size:28px;letter-spacing:.12em;text-transform:uppercase;color:#e1e0cc}' +
        '#pwRecapScore{margin:0 0 14px;font-size:13px;letter-spacing:.08em;color:#b4bac4}' +
        '.pw-recap-table{width:100%;border-collapse:collapse;margin:0 0 14px;font-size:12px;text-align:left}' +
        '.pw-recap-table th,.pw-recap-table td{padding:4px 6px;border-bottom:1px solid rgba(255,255,255,.1)}' +
        '.pw-recap-table th{font-size:10px;letter-spacing:.1em;text-transform:uppercase;color:#6b7380}' +
        '.pw-recap-actions{display:flex;gap:10px;justify-content:center;flex-wrap:wrap}' +
        '.pw-recap-actions button{min-height:40px;padding:0 16px;border:1px solid #c8ff3d;background:#c8ff3d;color:#07080b;font-size:12px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;cursor:pointer}' +
        '.pw-recap-actions button:last-child{background:transparent;color:#c8ff3d}'
      document.head.appendChild(style)
    }
    var existing = document.getElementById('pwRecap')
    if (existing) existing.remove()
    var onSite = isSiteWithRecap()
    var table = onSite && !expanded
      ? ''
      : '<table class="pw-recap-table"><thead><tr><th>Butcher</th><th>Bank</th><th>K</th><th>D</th><th>Hooks</th><th>HS</th><th>Deny</th></tr></thead><tbody>' +
        playerRows(recap) +
        '</tbody></table>'
    var actions =
      '<div class="pw-recap-actions">' +
      (onSite
        ? '<button type="button" id="pwRecapStats">View stats</button>'
        : '') +
      '<button type="button" id="pwRecapHome">' +
      (onSite ? 'Back to Fresh Meat' : 'Back to lobby') +
      '</button></div>'
    var root = document.createElement('div')
    root.id = 'pwRecap'
    root.innerHTML =
      '<div class="pw-recap-card">' +
      '<p class="pw-recap-kicker">Match complete</p>' +
      '<h1 id="pwRecapHead"></h1>' +
      '<p id="pwRecapScore"></p>' +
      table +
      actions +
      '</div>'
    document.body.appendChild(root)
    document.getElementById('pwRecapHead').textContent = headline(recap)
    document.getElementById('pwRecapScore').textContent =
      'West ' + (recap.west || 0) +
      ' · ' + clock(recap.seconds) +
      ' · ' + (recap.east || 0) + ' East'
    var statsBtn = document.getElementById('pwRecapStats')
    if (statsBtn) statsBtn.onclick = goRecap
    document.getElementById('pwRecapHome').onclick = goHome
  }

  function applyJoinLine(text) {
    if (/join failed/i.test(text)) {
      emitLive({ phase: 'dropped', note: text })
      return
    }
    if (/playing seat|spectating/i.test(text)) {
      emitLive({ phase: 'starting', note: text.replace(/^join:\s*/i, '') })
      return
    }
    if (/connected|waiting|lobby open/i.test(text)) {
      emitLive({ phase: 'joining', note: text.replace(/^join:\s*/i, '') })
    }
  }

  emitLive(live)
  var pulses = 0
  var pulseTimer = setInterval(function () {
    emitLive(live)
    pulses += 1
    if (pulses >= 12) clearInterval(pulseTimer)
  }, 400)

  window.pwHandleGameLine = function (line) {
    var text = '' + line
    if (text.indexOf('pw-state:') === 0) {
      try {
        var parsed = JSON.parse(text.slice('pw-state:'.length))
        emitLive(parsed)
      } catch (err) {}
      return true
    }
    if (text.indexOf('pw-match:') === 0) {
      try {
        recap = JSON.parse(text.slice('pw-match:'.length))
        saveRecap()
        emitLive({
          phase: 'over',
          tick: recap.tick,
          seconds: recap.seconds,
          killGoal: recap.killGoal,
          west: recap.west,
          east: recap.east,
          you: recap.you,
          winner: recap.winner
        })
        post('match', recap)
        showOverlay()
      } catch (err) {}
      return true
    }
    if (text.indexOf('pw-nav:recap') === 0) {
      goRecap()
      return true
    }
    if (text.indexOf('pw-nav:home') === 0) {
      goHome()
      return true
    }
    if (/^join:/i.test(text) || /join failed/i.test(text)) {
      applyJoinLine(text)
      return false
    }
    return false
  }
})()
