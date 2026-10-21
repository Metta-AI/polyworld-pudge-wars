"use strict";
let guideExpiry = null;
function guideText(id, value) {
  const element = document.getElementById(id);
  // Avoid repeatedly announcing an unchanged action to screen readers.
  if (element.textContent !== value) element.textContent = value;
}
function expireHumanGuide() {
  clearTimeout(guideExpiry);
  document.getElementById("guide-overlay").hidden = true;
  guideText("guide-title", "Getting a fresh read…");
  guideText("guide-reason", "Keep an eye on the arena.");
  guideText("guide-control", "");
  guideText("guide-source", "Reconnecting");
  guideText("guide-strategy", "Take a moment to reassess");
  guideText("guide-strategy-reason", "Watch the arena while fresh guidance is unavailable.");
  if (typeof expireTactical === "function") expireTactical();
}
function renderHumanGuide(s) {
  const g = s.human_guide;
  if (!g) return;
  clearTimeout(guideExpiry);
  const toggle = document.getElementById("guide-toggle");
  toggle.textContent = g.enabled ? "Pause" : "Resume";
  toggle.setAttribute("aria-label", g.enabled ? "Pause coach" : "Resume coach");
  toggle.setAttribute("aria-pressed", String(g.enabled));
  const notes = {
    local: "Local coaching is active. Add TYPESAFE_API_KEY to .env.local and restart to connect Jev.",
    ready: "Jev is ready to read the next exchange.",
    connected: "You're in control. Suggestions refresh as the situation changes.",
    auth_error: "Jev couldn't authenticate. Local coaching continues. Check the server key, then restart.",
    unavailable: "Jev is temporarily unavailable. Local coaching continues while it reconnects.",
    paused: "Coaching is paused. Resume whenever you'd like a hand.",
    stale: "Waiting for fresh match observations.",
    finished: "Match complete. Start a new match to keep practicing.",
    waiting: "Start a match for live guidance. You move with WASD or right-click and aim your hook with Q."
  };
  guideText("guide-note", notes[g.status] || "");
  const overlay = document.getElementById("guide-overlay");
  overlay.hidden = !g.action?.urgent;
  document.querySelector(".human-guide").classList.toggle("urgent", Boolean(g.action?.urgent));
  if (!g.action) {
    guideText("guide-source", g.status === "paused" ? "Paused" : g.status === "finished" ? "Match complete" : "Standing by");
    guideText("guide-title", g.status === "paused" ? "You've got this" : g.status === "finished" ? "One more round?" : "Let's find an opening");
    guideText("guide-reason", g.status === "paused" ? "Resume when you want a hand." : "One suggestion at a time, as the fight unfolds.");
    guideText("guide-control", "");
    guideText("guide-strategy", "Play together");
    guideText("guide-strategy-reason", "Find separate throwing lanes and look for chances to follow up on Loom's catches.");
    guideText("guide-detail", g.configured ? "Jev is configured on the local server." : "Local hints are available. Jev needs a TypeSafe API key on the server.");
    return;
  }
  const a = g.action, plan = g.strategy;
  const title = (a.tentative ? "Consider: " : "") + a.title;
  guideText("guide-title", title);
  guideText("guide-reason", a.why);
  guideText("guide-control", a.control);
  guideText("guide-source", a.source === "jev" ? (a.tentative ? "Maybe · Jev" : "Jev") : "Local");
  guideText("guide-overlay-label", a.urgent ? "ACT NOW" : "YOUR NEXT MOVE");
  guideText("guide-overlay-title", title);
  guideText("guide-overlay-control", a.control);
  overlay.classList.toggle("urgent", a.urgent);
  guideText("guide-strategy", plan.title);
  guideText("guide-strategy-reason", plan.why);
  const confidence = a.confidence == null ? "Immediate action uses a local game rule." : `Action: ${Math.round(a.confidence * 100)}% Jev confidence.`;
  const planConfidence = plan.confidence == null ? "Strategy uses a local guide." : `Strategy: ${Math.round(plan.confidence * 100)}% Jev confidence.`;
  guideText("guide-detail", `${confidence} ${planConfidence} Tick ${g.tick}. ${g.latency_ms == null ? "" : `Last Jev response: ${g.latency_ms} ms.`} ${g.requests} requests this match. Hooks and rescues need 85% confidence for a direct Jev cue; 60–85% is shown as an option. Lower confidence uses local guidance.`);
  guideExpiry = setTimeout(expireHumanGuide, g.ttl_ms || 1500);
}
document.getElementById("guide-toggle").onclick = async () => {
  const button = document.getElementById("guide-toggle");
  button.disabled = true;
  try { render(await api("/api/human-guide", {enabled: !state.human_guide.enabled})); }
  catch (error) { showError(error); }
  finally { button.disabled = false; }
};
document.getElementById("guide-expand").onclick = async () => {
  try {
    if (document.fullscreenElement) await document.exitFullscreen();
    else await document.documentElement.requestFullscreen();
  } catch (error) { showError(error); }
};
document.addEventListener("fullscreenchange", () => {
  const button = document.getElementById("guide-expand");
  button.setAttribute("aria-label", document.fullscreenElement ? "Exit full screen" : "Full screen");
  button.title = button.getAttribute("aria-label");
});
function setCoachPanel(visible) {
  document.body.classList.toggle("panel-hidden", !visible);
  document.getElementById("panel-toggle").setAttribute("aria-expanded", String(visible));
  if (!visible && !document.getElementById("game").hidden) document.getElementById("game").focus();
}
document.getElementById("panel-toggle").onclick = () => setCoachPanel(document.body.classList.contains("panel-hidden"));
const smallScreen = matchMedia("(max-width: 700px)");
setCoachPanel(!smallScreen.matches);
smallScreen.addEventListener("change", event => setCoachPanel(!event.matches));
