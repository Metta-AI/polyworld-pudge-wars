"use strict";
const $ = id => document.getElementById(id);
let state = null, loadedMatch = null, pc = null, microphone = null, remoteAudio = null, dc = null;
let busy = false, voiceConnecting = false, lastRules = "", lastChanges = "", lastTargets = "";
const text = (element, value) => { element.textContent = value; };
function node(tag, content, className) { const n = document.createElement(tag); if (content != null) n.textContent = content; if (className) n.className = className; return n; }
async function api(path, data, sdp = false) {
  const response = await fetch(path, {method: "POST", headers: {"X-Coach-Session": state.csrf,
    "Content-Type": sdp ? "application/sdp" : "application/json"}, body: sdp ? data : JSON.stringify(data)});
  if (!response.ok) { let message; try { message = (await response.json()).error; } catch (_) { message = `Request failed (${response.status})`; } throw new Error(message); }
  return sdp ? response.text() : response.json();
}
function showError(error) { text($("error"), error.message || String(error)); }
function actionText(trace) { const action = trace?.action || {}; return Object.keys(action).length ? JSON.stringify(action) : "No new action"; }
function render(s) {
  state = s;
  renderHumanGuide(s);
  renderTactical(s);
  if (typeof renderReasoning === "function") renderReasoning(s);
  text($("status"), {ready:"Ready to play",starting:"Joining arena",playing:"Match live",finished:"Match complete"}[s.phase] || s.phase);
  text($("revision"), `v${s.policy.revision}${s.pending_revision ? ` → v${s.pending_revision}` : ""}`);
  text($("voice-model"), s.realtime_model);
  if (!pc) text($("voice-status"), s.voice_status);
  text($("voice-help"), s.voice_configured ? "Connect to speak naturally. Context retrieval, rule changes, and background checks run through server-owned tools." : "Voice is wired to OpenAI Realtime. Set OPENAI_API_KEY in the server environment to connect. You can test the same policy update path with typed lessons now.");
  if (s.error) text($("error"), s.error);
  if (s.game_url && s.match_id !== loadedMatch) {
    loadedMatch = s.match_id; $("game").src = s.game_url; $("game").hidden = false; $("welcome").hidden = true;
    text($("start"), "New match");
    text($("reply"), "Loom is playing. Give a lesson when you see something to change.");
    text($("changes"), "Your lessons will appear here with a before/after decision comparison.");
    text($("jobs"), "No lesson checks yet.");
    lastChanges = "";
  }
  const selected = Object.values(s.trace.selected || {});
  const rulesKey = JSON.stringify([s.policy, selected]);
  if (rulesKey !== lastRules) {
    lastRules = rulesKey; $("rules").replaceChildren();
    for (const r of s.readable) {
      const card = node("div", null, `rule${selected.includes(r.id) ? " selected" : ""}`);
      const head = node("div", null, "rule-head"); head.append(node("span", r.channel), node("span", `${r.priority} · ${r.scope}`));
      card.append(head, node("p", r.text), node("small", r.id)); $("rules").append(card);
    }
    text($("ir"), JSON.stringify(s.policy, null, 2));
  }
  if (s.observation) {
    const o = s.observation; text($("tick"), `Tick ${o.tick}`);
    $("decision").replaceChildren();
    for (const [channel, rule] of Object.entries(s.trace.selected || {})) {
      const row = node("div", null, "decision-row"); row.append(node("strong", channel + " · "), node("span", rule)); $("decision").append(row);
    }
    $("decision").append(node("div", actionText(s.trace), "tiny"));
    const accepted = s.timeline.find(e => e.kind === "hook_accepted");
    if (accepted) $("decision").append(node("p", `Last engine hook acceptance: tick ${accepted.observed_tick}.`, "tiny muted"));
    const me = o.self;
    const ownHook = o.visible.hooks.some(h => h.owner_id === me.id);
    text($("context"), `Loom: ${me.hp}/${me.max_hp} HP · Hook ${ownHook ? "in flight" : me.hook_ready ? "ready" : "cooling down"} · ${o.visible.pudges.length} visible players`);
    const enemies = o.visible.pudges.filter(p => p.team !== me.team && p.alive && !p.shield);
    const targetKey = JSON.stringify([enemies.map(p => p.id), s.selected_id]);
    if (targetKey !== lastTargets) {
      lastTargets = targetKey; $("targets").replaceChildren();
      for (const enemy of enemies) {
        const b = node("button", `Enemy ${enemy.id}`, enemy.id === s.selected_id ? "active" : "");
        b.onclick = () => api("/api/select", {id: enemy.id}).catch(showError); $("targets").append(b);
      }
      if (!enemies.length) $("targets").append(node("span", "No visible enemies yet", "muted tiny"));
    }
  }
  const changes = s.timeline.filter(e => e.kind === "policy_compiled").slice(0, 4);
  const changesKey = JSON.stringify(changes);
  if (changes.length && changesKey !== lastChanges) {
    lastChanges = changesKey; $("changes").replaceChildren();
    for (const change of changes) {
      const card = node("div", null, "change"); card.append(node("strong", `Policy v${change.revision}`), node("p", change.message));
      const pair = node("div", null, "comparison");
      for (const [title, trace] of [["BEFORE · SAME OBSERVATION", change.before], ["AFTER · SAME OBSERVATION", change.after]]) {
        const col = node("div"); col.append(node("b", title), node("span", actionText(trace))); pair.append(col);
      }
      card.append(pair); $("changes").append(card);
    }
  }
  const jobs = Object.values(s.jobs).slice(-3).reverse();
  if (jobs.length) {
    $("jobs").replaceChildren();
    for (const job of jobs) $("jobs").append(node("div", job.status === "complete" ? `v${job.revision}: ${job.changed_decisions}/${job.observations} recorded decisions changed; ${job.changed_hooks} hook choices changed. Competitive strength untested.` : `Checking v${job.revision}…`, "job"));
  }
}
async function poll() {
  try { const response = await fetch("/api/state", {cache:"no-store"}); if (!response.ok) throw new Error("Local server unavailable"); render(await response.json()); }
  catch (error) { expireHumanGuide(); showError(error); }
  setTimeout(poll, 300);
}
$("start").onclick = async () => {
  if (busy) return; busy = true; $("start").disabled = true; text($("error"), "");
  try { await disconnectVoice(); render(await api("/api/start", {})); }
  catch (error) { showError(error); } finally { busy = false; $("start").disabled = false; }
};
$("welcome-start").onclick = () => $("start").click();
$("lab-open").onclick = () => $("lab-dialog").showModal();
$("lab-close").onclick = () => $("lab-dialog").close();
$("lab-dialog").addEventListener("close", () => {
  if (!$("game").hidden) $("game").focus();
});
async function lesson(value) {
  if (!state?.context_id) { text($("reply"), "Start the match first; Loom needs gameplay context."); return; }
  text($("error"), "");
  try { const result = await api("/api/coach", {text:value, context_id:state.context_id, id:crypto.randomUUID()}); text($("reply"), result.message); }
  catch (error) { showError(error); }
}
$("coach-form").onsubmit = event => { event.preventDefault(); const value = $("instruction").value.trim(); if (value) { lesson(value); $("instruction").value = ""; } };
for (const button of document.querySelectorAll("[data-lesson]")) button.onclick = () => lesson(button.dataset.lesson);
$("undo").onclick = () => api("/api/rollback", {base_revision:state.policy.revision}).then(() => text($("reply"), "Previous strategy will resume on the next decision.")).catch(showError);

async function disconnectVoice() {
  if (microphone) microphone.getTracks().forEach(track => track.stop()); microphone = null;
  if (dc) dc.close(); dc = null;
  if (pc) pc.close(); pc = null;
  if (remoteAudio) { remoteAudio.srcObject = null; remoteAudio.remove(); remoteAudio = null; }
  $("mute").hidden = true; $("disconnect").hidden = true; $("voice").disabled = false;
  if (state) await api("/api/voice/stop", {}).catch(() => {});
}
$("disconnect").onclick = disconnectVoice;
$("mute").onclick = () => {
  if (!microphone) return; const track = microphone.getAudioTracks()[0]; track.enabled = !track.enabled;
  text($("mute"), track.enabled ? "Mute microphone" : "Unmute microphone");
};
$("voice").onclick = async () => {
  if (voiceConnecting || pc) return;
  if (!state?.voice_configured) { showError(new Error("Set OPENAI_API_KEY on the server and restart scripts/coach_demo.sh to enable OpenAI Realtime voice.")); return; }
  if (state.phase !== "playing") { showError(new Error("Start the match before connecting voice.")); return; }
  voiceConnecting = true; $("voice").disabled = true; text($("error"), "");
  try {
    microphone = await navigator.mediaDevices.getUserMedia({audio:{echoCancellation:true, noiseSuppression:true}});
    pc = new RTCPeerConnection(); remoteAudio = document.createElement("audio"); remoteAudio.autoplay = true; document.body.append(remoteAudio);
    pc.ontrack = event => { remoteAudio.srcObject = event.streams[0]; remoteAudio.play().catch(() => {}); };
    pc.addTrack(microphone.getAudioTracks()[0], microphone);
    dc = pc.createDataChannel("oai-events");
    dc.onmessage = event => {
      const message = JSON.parse(event.data);
      if (message.type === "input_audio_buffer.speech_started") text($("heard"), "Listening…");
      if (message.type === "response.output_audio_transcript.delta") $("heard").textContent += message.delta;
      if (message.type === "response.created") text($("heard"), "");
      if (message.type === "response.output_audio_transcript.done") text($("reply"), message.transcript);
      if (message.type === "error") showError(new Error(message.error?.message || "Realtime session error"));
    };
    pc.onconnectionstatechange = () => text($("voice-status"), `Voice ${pc?.connectionState || "disconnected"}`);
    const offer = await pc.createOffer(); await pc.setLocalDescription(offer);
    const answer = await api("/api/voice", offer.sdp, true);
    await pc.setRemoteDescription({type:"answer", sdp:answer});
    $("mute").hidden = false; $("disconnect").hidden = false;
  } catch (error) { await disconnectVoice(); showError(error); }
  finally { voiceConnecting = false; }
};
window.addEventListener("pagehide", () => {
  if (microphone) microphone.getTracks().forEach(t => t.stop());
  if (pc) {
    pc.close();
    fetch("/api/voice/stop", {method:"POST", headers:{"X-Coach-Session":state.csrf}, keepalive:true}).catch(() => {});
  }
});
poll();
