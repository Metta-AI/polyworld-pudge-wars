"use strict";
let tacticalState = null, intelEnemy = null, intelHorizon = "next", intelButtons = "";
const intelNode = (tag, value, className) => {
  const el = document.createElement(tag);
  if (value != null) el.textContent = value;
  if (className) el.className = className;
  return el;
};
for (const button of document.querySelectorAll("[data-horizon]")) {
  button.onclick = () => {
    intelHorizon = button.dataset.horizon;
    for (const other of document.querySelectorAll("[data-horizon]")) {
      other.classList.toggle("active", other === button);
      other.setAttribute("aria-pressed", String(other === button));
    }
    if (tacticalState) renderTactical(tacticalState);
  };
}
function expireTactical() {
  if (!tacticalState) return;
  const stale = structuredClone(tacticalState);
  stale.human_guide.status = "stale";
  stale.human_guide.hooks = [];
  stale.human_guide.team = [];
  for (const enemy of stale.human_guide.intel.enemies) {
    enemy.visible = false;
    enemy.forecasts = {};
  }
  renderTactical(stale);
  guideText("intel-map-label", "Reconnecting · last sightings");
}
function renderTactical(s) {
  const g = s.human_guide;
  if (!g) return;
  tacticalState = s;
  const connected = g.status === "connected", live = s.phase === "playing" && !["stale", "paused"].includes(g.status);
  guideText("intel-live", connected ? "JEV LIVE" : g.status === "paused" ? "PAUSED" : live ? "SIGHTINGS" : "STANDBY");
  document.getElementById("intel-live").classList.toggle("connected", connected);
  const intel = g.intel, enemies = intel.enemies;
  if (!enemies.some(e => e.id === intelEnemy)) intelEnemy = enemies[0]?.id ?? null;
  const key = JSON.stringify([g.match_id, enemies.map(e => e.id)]);
  if (key !== intelButtons) {
    intelButtons = key;
    const container = document.getElementById("intel-enemies");
    container.replaceChildren();
    for (const enemy of enemies) {
      const button = intelNode("button", null);
      button.dataset.enemy = String(enemy.id);
      button.append(intelNode("strong", `Enemy ${enemy.slot + 1}`), intelNode("small", ""));
      button.onclick = () => { intelEnemy = enemy.id; renderTactical(tacticalState); };
      container.append(button);
    }
  }
  for (const enemy of enemies) {
    const button = document.querySelector(`[data-enemy="${enemy.id}"]`);
    button.classList.toggle("selected", enemy.id === intelEnemy);
    button.setAttribute("aria-pressed", String(enemy.id === intelEnemy));
    button.querySelector("small").textContent = enemy.visible ? (enemy.last_seen.alive ? "● Visible now" : "Last seen down") : `Unseen · ${enemy.age_seconds.toFixed(1)}s`;
  }
  const enemy = enemies.find(e => e.id === intelEnemy);
  const prediction = enemy?.forecasts[intelHorizon];
  drawIntelMap(g, enemy, prediction);
  const container = document.getElementById("intel-probabilities");
  container.replaceChildren();
  guideText("intel-prediction-title", intelHorizon === "now" ? "Likely now" : "Likely next");
  guideText("intel-age", enemy ? (enemy.visible ? "In sight" : `Seen ${enemy.age_seconds.toFixed(1)}s ago`) : "");
  if (intelHorizon === "now" && enemy?.visible) {
    container.append(intelNode("p", enemy.last_seen.alive ? "In sight. The dot shows their position." : "Last observed down. Watch for their return.", "intel-empty"));
    guideText("intel-map-label", "Observed position");
  } else if (prediction) {
    const probabilities = prediction.probabilities;
    const sorted = Object.entries(probabilities).filter(([k]) => k !== "unknown").sort((a, b) => b[1] - a[1]);
    const top = sorted.filter(([, p]) => p >= .01).slice(0, 2);
    const remainder = sorted.filter(([key]) => !top.some(([shown]) => shown === key)).reduce((sum, [, value]) => sum + value, 0);
    const rows = top.map(([key, probability]) => [intel.zones[key].label, probability]);
    if (remainder > .001) rows.push(["Other regions", remainder]);
    if (probabilities.unknown > .001) rows.push(["Unknown", probabilities.unknown]);
    for (const [label, probability] of rows) {
      const row = intelNode("div", null, "likelihood-row"), heading = intelNode("div", null, "likelihood-label");
      heading.append(intelNode("span", label), intelNode("b", `${Math.round(probability * 100)}%`));
      const bar = intelNode("div", null, "likelihood-bar"), fill = intelNode("i", null);
      fill.style.width = `${probability * 100}%`;
      bar.append(fill); row.append(heading, bar); container.append(row);
    }
    guideText("intel-map-label", intelHorizon === "next" ? "Estimate · 2s after latest read" : "Estimated current region");
  } else {
    const waiting = !enemy ? "Find an enemy to start a read." : g.status === "paused" ? "Estimates paused." : "No fresh estimate. Dashed dots are last sightings.";
    container.append(intelNode("p", waiting, "intel-empty"));
    guideText("intel-map-label", !enemy ? "Waiting for contact" : "Last sightings only");
  }
  guideText("intel-evidence", enemy ? `Enemy ${enemy.slot + 1}: last observed at (${Math.round(enemy.last_seen.x)}, ${Math.round(enemy.last_seen.y)}), ${enemy.last_seen.hp} HP. ${enemy.visible ? "Currently in your team's view." : `${enemy.age_seconds.toFixed(1)} seconds without a sighting.`}` : "Only your team's sightings feed this map.");
}
function drawIntelMap(g, selected, prediction) {
  const canvas = document.getElementById("intel-map"), ctx = canvas.getContext("2d");
  ctx.setTransform(5, 0, 0, 5, 0, 0);
  ctx.clearRect(0, 0, 128, 128);
  ctx.fillStyle = "#0a1520"; ctx.fillRect(0, 0, 128, 128);
  // A schematic of the two banks and their central bulge, not a fog overlay.
  ctx.fillStyle = "#172b34"; ctx.fillRect(6, 10, 47, 107); ctx.fillRect(75, 10, 47, 107);
  ctx.fillStyle = "#143642"; ctx.fillRect(53, 10, 22, 107);
  ctx.fillStyle = "#172b34";
  ctx.beginPath(); ctx.moveTo(53, 48); ctx.lineTo(59, 64); ctx.lineTo(53, 80); ctx.fill();
  ctx.beginPath(); ctx.moveTo(75, 48); ctx.lineTo(69, 64); ctx.lineTo(75, 80); ctx.fill();
  ctx.strokeStyle = "#85b7c012"; ctx.lineWidth = .18;
  for (let n = 8; n <= 120; n += 8) {
    ctx.beginPath(); ctx.moveTo(n, 8); ctx.lineTo(n, 119); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(6, n); ctx.lineTo(122, n); ctx.stroke();
  }
  if (prediction) {
    for (const [key, p] of Object.entries(prediction.probabilities)) {
      const z = g.intel.zones[key];
      if (!z || p < .005) continue;
      const x = z.x + z.width / 2, y = z.y + z.height / 2;
      ctx.save(); ctx.beginPath(); ctx.rect(z.x + 1, z.y + 1, z.width - 2, z.height - 2); ctx.clip();
      const glow = ctx.createRadialGradient(x, y, 0, x, y, Math.max(z.width, z.height) * .8);
      glow.addColorStop(0, `rgba(243,176,92,${.12 + p * .58})`);
      glow.addColorStop(1, "rgba(237,164,78,0)");
      ctx.fillStyle = glow; ctx.fillRect(z.x, z.y, z.width, z.height);
      ctx.strokeStyle = `rgba(244,190,112,${.1 + p * .4})`; ctx.lineWidth = .3;
      ctx.strokeRect(z.x + 1.5, z.y + 1.5, z.width - 3, z.height - 3);
      if (p >= .07) {
        ctx.font = "bold 4px ui-monospace, monospace"; ctx.textAlign = "center"; ctx.fillStyle = "#ffdc9d";
        ctx.fillText(`${Math.round(p * 100)}%`, x, y - 6);
      }
      ctx.restore();
    }
  }
  ctx.fillStyle = "#314852"; ctx.beginPath(); ctx.arc(64, 64, 3.5, 0, Math.PI * 2); ctx.fill();
  ctx.strokeStyle = "#82979588"; ctx.lineWidth = .3; ctx.stroke();
  ctx.font = "2.5px ui-monospace, monospace"; ctx.textAlign = "center"; ctx.fillStyle = "#8aa7b8";
  ctx.fillText("WEST BANK", 28, 6); ctx.fillText("RIVER", 64, 6); ctx.fillText("EAST BANK", 101, 6);
  ctx.fillText("N", 4, 7); ctx.fillText("S", 4, 123);
  function marker(p, label, color, ghost = false, emphasis = false) {
    ctx.save(); ctx.strokeStyle = color; ctx.fillStyle = ghost ? "#101d28" : color; ctx.lineWidth = .5;
    if (ghost) ctx.setLineDash([1, .8]);
    if (emphasis) { ctx.beginPath(); ctx.arc(p.x, p.y, 4.5, 0, Math.PI * 2); ctx.stroke(); }
    ctx.beginPath(); ctx.arc(p.x, p.y, 2.1, 0, Math.PI * 2); ctx.fill(); ctx.stroke();
    ctx.setLineDash([]); ctx.fillStyle = color; ctx.font = "bold 2.8px ui-monospace, monospace"; ctx.textAlign = "center";
    ctx.fillText(label, p.x, p.y - 5.5); ctx.restore();
  }
  for (const enemy of g.intel.enemies) {
    if (enemy.age_seconds > 15) continue;
    const trail = enemy.trail.filter(p => g.tick - p.tick < 96);
    ctx.strokeStyle = "#efa98455"; ctx.lineWidth = .65; ctx.beginPath();
    trail.forEach((p, i) => i ? ctx.lineTo(p.x, p.y) : ctx.moveTo(p.x, p.y)); ctx.stroke();
    marker(enemy.last_seen, `E${enemy.slot + 1}${enemy.visible ? "" : " ?"}`, enemy.visible ? "#ffac93" : "#af987c", !enemy.visible, enemy.id === selected?.id);
  }
  for (const player of g.team) {
    if (!player.alive) continue;
    marker(player, player.id === g.human?.id ? "YOU" : "ALLY", "#93ecda", false, player.id === g.human?.id);
  }
  for (const hook of g.hooks) {
    const owner = g.team.find(p => p.id === hook.owner_id) || g.intel.enemies.find(e => e.id === hook.owner_id && e.visible)?.last_seen;
    ctx.strokeStyle = hook.team === g.human?.team ? "#9ceadc88" : "#ffaf9677"; ctx.lineWidth = .4;
    if (owner) { ctx.beginPath(); ctx.moveTo(owner.x, owner.y); ctx.lineTo(hook.x, hook.y); ctx.stroke(); }
    ctx.fillStyle = hook.team === g.human?.team ? "#b1fff0" : "#ffd0bc";
    ctx.beginPath(); ctx.arc(hook.x, hook.y, 1, 0, Math.PI * 2); ctx.fill();
  }
  canvas.setAttribute("aria-label", selected ? `Tactical map for enemy ${selected.slot + 1}. ${selected.visible ? "Currently visible." : `Last seen ${selected.age_seconds} seconds ago.`} ${prediction ? "Estimated region probabilities are listed below." : "No fresh position forecast."}` : "Tactical map. No enemy sightings yet.");
}
