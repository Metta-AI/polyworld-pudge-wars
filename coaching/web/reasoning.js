"use strict";
let lastReasoning = "", reasoningBusy = false;
async function reasoningAction(operation, args) {
  if (reasoningBusy) return;
  reasoningBusy = true; text($("error"), "");
  try {
    const result = await api("/api/reasoning", {operation, id:crypto.randomUUID(), ...args});
    text($("reply"), result.message || result.status);
    return result;
  } catch (error) { showError(error); }
  finally { reasoningBusy = false; }
}
function feedbackContext() {
  if (!state?.context_id) throw new Error("Start a match to ground the feedback in gameplay.");
  return {context_id:state.context_id, base_semantic_revision:state.reasoning.model.revision};
}
$("belief-form").onsubmit = async event => {
  event.preventDefault();
  try {
    await reasoningAction("record_reasoning", {...feedbackContext(), kind:"belief", subject_id:$("belief-id").value,
      confidence:Number($("belief-confidence").value), text:$("belief-rationale").value.trim()});
  } catch (error) { showError(error); }
};
$("feedback-form").onsubmit = async event => {
  event.preventDefault();
  try {
    await reasoningAction("record_reasoning", {...feedbackContext(), kind:$("feedback-kind").value,
      subject_id:$("feedback-subject").value || null, text:$("feedback-text").value.trim(), prediction:$("feedback-prediction").value.trim()});
  } catch (error) { showError(error); }
};
function renderReasoning(s) {
  const r = s.reasoning;
  if (!r) return;
  const key = JSON.stringify(r);
  if (key === lastReasoning) return;
  lastReasoning = key;
  text($("semantic-revision"), `Working model v${r.model.revision}`);
  text($("semantic-model"), JSON.stringify(r.model, null, 2));
  $("beliefs").replaceChildren();
  for (const belief of r.model.beliefs) {
    const card = node("div", null, "belief-card");
    card.append(node("strong", belief.claim), node("p", belief.rationale),
      node("small", `Human confidence: ${Math.round(belief.confidence*100)}% · ${belief.evidence_ids.length} revision sources`));
    const strategy = r.model.strategies.find(t => t.belief_id === belief.id);
    if (strategy) card.append(node("p", `Strategic implication: ${strategy.consequence}`, "tiny muted"));
    $("beliefs").append(card);
  }
  $("generations").replaceChildren();
  for (const generation of [...r.generations].reverse()) {
    const card = node("div", null, "generation-card");
    const currentMeaning = generation.submissions.some(c => c.policy.provenance.semantic_hash === r.hash);
    const status = generation.active ? (currentMeaning ? "Active trial" : "Active trial from an earlier working model") : generation.stale ? "Superseded by a newer model, policy or match" : generation.status.replaceAll("_", " ");
    card.append(node("strong", `${generation.belief_id} · ${status}`));
    if (!generation.stale && !generation.active) {
      const generate = node("button", "Generate example policy");
      generate.onclick = () => reasoningAction("generate_reference_candidate", {request_id:generation.id});
      card.append(node("p", "The offline example uses a reference synthesizer. Voice can propose a full policy through the same checks.", "tiny muted"), generate);
    }
    for (const submission of generation.submissions) {
      const count = submission.report.checks.filter(c => c.passed).length;
      card.append(node("p", `${submission.generator}: ${count}/${submission.report.checks.length} behavioral contracts passed. Competitive strength untested.`));
      card.append(node("p", submission.explanation, "tiny muted"));
      const checks = node("details"); checks.append(node("summary", "Inspect behavioral evidence and generated policy"));
      for (const c of submission.report.checks) checks.append(node("div", `${c.passed ? "✓" : "✕"} ${c.name}`, "tiny"));
      checks.append(node("p", "Synthetic contract scenario · these are not live game outcomes.", "tiny muted"));
      const pair = node("div", null, "comparison");
      for (const [label, action] of [["BEFORE", submission.report.example.before], ["AFTER", submission.report.example.after]]) {
        const column = node("div"); column.append(node("b", label), node("span", JSON.stringify(action))); pair.append(column);
      }
      checks.append(pair, node("pre", JSON.stringify(submission.policy, null, 2))); card.append(checks);
      if (submission.report.passed && !generation.stale && !generation.active) {
        const apply = node("button", "Try this policy", "primary");
        apply.onclick = () => reasoningAction("try_reasoning_candidate", {request_id:generation.id, submission_id:submission.id});
        card.append(apply);
      }
    }
    $("generations").append(card);
  }
  $("ontology-proposals").replaceChildren();
  for (const proposal of r.model.proposals.slice(-3)) {
    const card = node("div", null, "generation-card");
    card.append(node("strong", "Ontology proposal · needs grounding"), node("p", proposal.description),
      node("p", proposal.prediction || "A testable prediction is still needed.", "tiny"), node("p", proposal.next_step, "tiny muted"));
    $("ontology-proposals").append(card);
  }
  $("semantic-feedback").replaceChildren();
  for (const event of [...r.feedback].reverse().slice(0,4)) {
    $("semantic-feedback").append(node("p", `${event.kind} · ${event.subject_id || "unassigned"}: ${event.text}`, "tiny muted"));
  }
}
