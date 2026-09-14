# Deliberate healing and fishing formation

Status: completed; primary competitive confirmation and other-opponent
guardrails passed. The initial design was created before candidate
implementation or new XP results. Promotion readback is recorded below.

Baseline: rusher v10 `6d9aa2b5-5a1c-4c06-9c77-6f2265b43848`.
Opponent: Myasnik v5 `05abab38-0b6e-42ec-a90d-91be5fb17bba`, still the
current 3v3 leader at the campaign's initial readback. Canonical game v0.3.13,
source `0767d18ab8a86925a8c5c937702143be1c62778c`.
Artifacts: `duels/support-spacing-83ndgym1/`. Prior levers and the Pudge
evaluation binding were read before this record.

## Independent hypotheses

H1: An unpressured player can heal an injured same-bank teammate with a
short, deliberate friendly hook, improving sustain enough to outweigh lost
attack opportunities. Exclude shielded/carried allies, threatening hooks,
nearby enemies/Rot and an urgent follow-up kill. Claim one healer and stop
moving while the healing chain returns. Measure actual healing from the
replay simulation, and log the policy's intent privately.

H2: Stable fishing lanes, one claimed rune collector, and separation from
nearby teammates can reduce clustering without giving up rune control or
useful offensive pressure. Keep rescue, defense, combat and shop priorities.
Only the default fishing movement changes. A single player has no formation.

First compare baseline, healing-only, spacing-only. Test the combination only
if at least one individual arm passes the directional screen and neither
clearly regresses. Do not attribute a combination result to one component.

## Predictions and decision rules

Local scenarios must show H1 accepts a safe healing opportunity, declines
unsafe/duplicate opportunities, produces actual healing, and preserves urgent
actions. H2 must produce separated fishing destinations on both banks,
preserve emergency actions, and assign only one rune collector. Baseline mode
must remain action-equivalent to frozen v10 on collected live observations.

Each initial arm: two requests of ten episodes, one per bank, same pinned
opponent. Fresh independent generated seeds; not a paired-seed test. Drain
one arm before the next. Do not stop based on partial results.

Primary directional pass: win rate at least baseline +10 percentage points
AND mean kill margin at least baseline +2. A drop of at least 10 points in
win rate AND at least 2 kills in margin is a directional regression. Anything
between is inconclusive. These are screening thresholds, not significance
claims or a permission to promote from twenty games.

Mechanism checks: H1 must produce verified deliberate healing in at least
five games and higher effective friendly healing per alive minute. H2 must
reduce all-three clustering by at least 25% relative while losing no more
than 10% of runes/minute or enemy catches/minute. Changes that alter a proxy
without the outcome screen passing are not confirmed improvements.

If a candidate passes, run a fresh balanced confirmation against Myasnik
(at least 40 per arm, in 10–20-episode requests) and regression probes against
another current leading opponent plus 1v1. Assess confidence intervals and
mechanism exposure before changing the active champion. If screens are
inconclusive, preserve candidates and v10 and report the uncertainty rather
than launch an unbounded tuning search.

## Confounds and limits

Friendly contact is not automatically effective healing; HP may already be
full, and transport can disrupt a teammate. Count restored HP at the sim's
healing operation. Clustering can be useful for rescues, so compare ordinary
fishing and whole-match results. Logging must be bounded and asynchronous;
replay counters independently verify effects. Runtime scheduling and fresh
seeds add variance; this campaign can detect large effects, not small gains.
Healing/spacing should leave 1v1 actions unchanged.

## Requests and verdict

Request bodies and IDs are appended to the study's `requests.json` at creation.
The final result, mechanism evidence and verdict will be recorded here.

### Completed initial baseline and healing screen

All 40 games completed with unique generated seeds within each arm; no
failed episodes. Every replay hash, terminal score and per-seat counter
verified under the released engine with the direct healing observer.

| Arm | Version | W–L | Mean kill margin | Healing HP / alive-player minute | Clustering | Enemy catches / minute |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Baseline | v10 | 6–14 | −1.85 | 142.49 | 17.33% | 6.16 |
| Healing only | v11 | 11–9 | +1.25 | 252.84 | 17.32% | 5.96 |
| Spacing only | v12 | 19–1 | +11.80 | 57.18 | 0.15% | 6.56 |
| Combined | v13 | 20–0 | +12.75 | 123.68 | 0.16% | 6.70 |

Healing-only passes the pre-recorded directional outcome and mechanism
criteria. It produced 753 verified deliberate healing contacts, restoring
89,473 HP, across all 20 games. Total friendly healing, including incidental
contacts, was 150,649 HP versus baseline's 85,203. The earlier historical
v10 sample was 11–9; that variation makes fresh confirmation essential.
No reliable win-rate improvement or promotion is claimed from this screen.

Spacing-only also passes the directional outcome and mechanism criteria:
99.1% less all-three clustering, enemy catches/minute up 6.4%, runes/minute
down 5.8% (2.38 versus 2.53). All twenty replays verified, with twenty unique
seeds and no failed episodes. Reduced incidental healing is expected from
separation; the combined arm tests whether deliberate healing can coexist
with the formation. These initial comparisons are selection evidence.

Combined v13 satisfies the pre-recorded selection rule versus healing-only
and the spacing mechanism thresholds. It is frozen as the confirmation
candidate. All twenty combined replays verified. It restored 34,900 HP
through 291 verified deliberate contacts, with exposure in every game.
Rune collection was 2.44/minute (baseline 2.53). Its healing exceeds the
spacing-only screen but not clustered baseline's total incidental healing.
The 20–0 versus spacing's 19–1 does not establish healing's incremental value.

The combined screen has nineteen distinct seeds: east episodes
`ereq_a8b3c88d-cc59-495b-9897-436491ed6509` and
`ereq_38e3820e-e5ac-4b6f-801d-e49a0777c557` both received seed 170244075.
Both won, with different terminal margins. The released host defaults to
millisecond wall-clock seeds (`coworld_host.nim:1189`), so simultaneous starts
can collide. Retain every episode, disclose this dependence, and treat this
as a selection screen. The strict comparison tool correctly rejected an
independent-sample statistical claim on all twenty rows.

| Arm / bank | Request |
| --- | --- |
| baseline west | `xreq_385b3d9e-3de4-40b2-9ca3-a00ca209179f` |
| baseline east | `xreq_742c2988-dc0c-4832-a88e-85627855e952` |
| healing west | `xreq_f358bdb6-9f74-4524-bd2e-0c3b3a0c531d` |
| healing east | `xreq_98c201e5-e95b-4395-a5d4-1124678ef1e2` |
| spacing west | `xreq_8620a4be-f6d0-40ef-b624-1bccea61a81d` |
| spacing east | `xreq_4233f05c-dbcf-4741-a7ba-c0328705a19b` |
| combined west | `xreq_b2148bc8-5a14-4192-986f-ce7baaf9101c` |
| combined east | `xreq_22eaae43-769b-4e56-ba2d-734f8bc8112f` |

### Confirmation design (recorded before confirmation runs)

If the spacing screen is not a directional regression, test the combination
for twenty games. Select the combination over healing-only for confirmation
only if it improves the screen win rate by at least ten percentage points
and kill margin by at least two, while satisfying the spacing mechanism
criteria. Otherwise carry healing-only forward. This is selection, not an
independent confirmation result.

Compare the frozen selected candidate and frozen v10 on 40 fresh games each,
20 per starting bank, still against the same Myasnik version. Drain each arm
before the next. Confirmation of competitive improvement requires positive
win-rate difference with two-sided Fisher exact p < 0.05 and improved mean
kill margin. Report 95% uncertainty intervals as well. A weaker result is
inconclusive, even if it resembles the screen; do not enlarge the campaign
repeatedly until significance appears.

Seed-collision handling, recorded after the screen exposed the host behavior
but before any confirmation requests: retain and descriptively report all
forty games per arm. For inferential comparisons, take the lexicographically
smallest episode ID per distinct seed (an outcome-independent rule), and
report that effective sample size and excluded duplicate IDs. Require at
least 36 distinct seeds per arm; fewer makes this fixed campaign inconclusive.
Reject cross-arm seed reuse. Confidence intervals and Fisher's test use this
one-episode-per-seed sample; require positive kill-margin improvement in both
that sample and all forty games. Do not add games after seeing the result.

Only a confirmed candidate proceeds toward promotion, with a matched probe
against another current leading policy and a 1v1 regression check. The latter
must establish preserved duel behavior, not infer it from 3v3 outcomes.

The guardrail design was fixed before any guardrail requests: if the primary
confirmation passes, compare candidate and v10 for twenty games each against
both relh v2 (`c5d5b0a0-5f4f-48bd-84f8-312e428996dc`) and sniper v3
(`bdb51abd-dabe-4107-82fd-aaeff96ec706`), ten per bank. They are the next two
opposing champions after Myasnik in the refreshed ranking (ranks 3 and 4;
Aaron's v10 is rank 2). Drain the baseline arm before the candidate arm.
Any failures require investigation; a win-rate drop of at least fifteen
percentage points AND mean margin drop of at least two kills against either
opponent blocks promotion. Passing this small probe means no detected large
regression, not statistical non-inferiority. The full-game duel action check
below establishes the intended 1v1 invariance; retain v10's existing duel
membership because these features target team play.

### Debug evidence and remaining failure mode

Combined v13 completed two full released-engine duels, seeds 61013/61014,
one per bank. Every one of the candidate's 30,720 actions exactly matched
frozen v10 on the same observations. These are action regression checks,
not hosted competitive results. The Docker WebSocket probe separately
verified combined-mode startup, 64 actions, a healing request, and final exit.

Spacing's one screen loss (`ereq_9716b677-8bcd-4f2b-b248-faba00e224b1`, 8–30)
had zero all-three clusters in the sampled states. Frames at 150/190/230
seconds show the formation continuing through its worst scoring interval.
It recorded 43 enemy catches versus Myasnik's 66, and 21 of 30 deaths on the
enemy bank. Rescue/survival after being caught remains a candidate for later
work; the lane change does not solve every hook exchange. These catch counts
come from the event logger, which can miss immediately disappearing hooks;
death locations use the nearest preceding state sample. The terminal score
and actual friendly healing are exact replay-verified values.

Labeled native recordings: `watch-spacing-win.command` (30–12) and
`watch-spacing-loss.command` (8–30) in the study directory. They use the
released viewer matching these hosted episodes.

### Fresh confirmation progress

Baseline v10 completed 40 games with 40 distinct seeds and no failures:
19 wins, 21 losses, mean kill margin +0.25. West 8–12, east 11–9.
All forty replay hashes and terminal/per-seat counters verified. Clustering
17.41%, rune collection 2.54/minute, enemy catches 5.91/minute, actual
friendly healing 141.62 HP/alive-player-minute. This is a fresh comparison
baseline, separate from the initial 6–14 selection screen.

| Arm / bank | Episodes | Request |
| --- | ---: | --- |
| confirmation baseline west | 20 | `xreq_4f74e0b8-460a-4a43-a910-e62df4be869d` |
| confirmation baseline east | 20 | `xreq_a6536b0b-9f6d-42ee-ae03-b4679974f239` |
| confirmation combined west | 20 | `xreq_e85b4c97-6c78-4fba-965f-10de0bb73e35` |
| confirmation combined east | 20 | `xreq_a46da308-c827-4d55-8fae-7b6f26987ba8` |

The frozen combined candidate finished 35–5 (west 17–3, east 18–2), mean
kill margin +10.25, versus v10's 19–21 and +0.25. Both arms have forty
distinct seeds, with no cross-arm reuse or failed episodes. Every replay
verified. The primary competitive confirmation passes: +40 percentage points
in win rate, Newcombe 95% interval +19.74 to +56.18 points, two-sided Fisher
exact p=0.0002541, and +10.0 mean kill margin. Individual Wilson intervals
are 73.9–94.5% for v13 and 32.9–62.5% for v10.

Candidate clustering was 0.2715% (baseline 17.4062%); enemy catches rose
15.6% to 6.8324/minute. It produced 653 verified deliberate healing contacts,
restoring 77,871 HP, across all forty games. Total friendly healing was
131.72 HP/alive-player-minute versus baseline's 141.62; formation also removes
many incidental contacts. Healing's incremental win benefit over spacing
alone remains unconfirmed.

Rune collection was 2.27838/minute versus 2.53518, a **10.13% decline**.
This narrowly misses the 10% mechanism target on fresh data even though
the initial selection passed it. Do not claim all mechanism targets fully
replicated. The pre-recorded primary competitive confirmation passed; the
other-opponent guardrails remain necessary before a promotion decision.
`confirmation-comparison.json` retains all identities, intervals, outcomes,
and mechanism rates. The seed-collision contingency excluded no confirmation
episodes.

### Other-opponent guardrails

Baseline v10 finished 15–5 against relh (mean margin +5.55), and 19–1
against sniper (+11.90), with twenty distinct seeds per opponent. All forty
replays verified. A local downloader connection reset interrupted harvesting;
resuming collected the original completed games without creating replacements.
The read helper now retries transient transport/429/5xx failures up to three
times, and the replay watcher warns when harvester status becomes stale.
Injected transport, server-error, permanent-error and retry-exhaustion checks
passed. This was an artifact-collection failure, not a failed game.

| Arm / opponent / bank | Episodes | Request |
| --- | ---: | --- |
| baseline / relh / west | 10 | `xreq_345cc33a-08ae-4f27-9aa4-e91a51c72328` |
| baseline / relh / east | 10 | `xreq_417f220a-8b39-457a-98cb-65be5b516774` |
| baseline / sniper / west | 10 | `xreq_32511180-55a6-416d-b4af-7eefde1daa6f` |
| baseline / sniper / east | 10 | `xreq_b1759540-cabc-43ca-a228-a8ef24aabf87` |
| combined / relh / west | 10 | `xreq_8cd67ff5-9108-422a-983e-d4d7d0c583da` |
| combined / relh / east | 10 | `xreq_10b2828b-c199-4b58-9a53-638b9e3aaf3f` |
| combined / sniper / west | 10 | `xreq_e57ee0c6-4528-49f6-8bc5-6c04edfede6a` |
| combined / sniper / east | 10 | `xreq_597d3fe2-3b5c-4aa2-adbf-2ebb343b8444` |

V13 completed 20–0 against relh (mean margin +14.45) and 20–0 against
sniper (+16.50), with twenty distinct seeds per opponent. Both bank blocks
were 10–0. All forty replays verified. Neither comparison triggered the
pre-recorded large-regression rule. These remain small guardrail probes;
the primary fresh Myasnik comparison provides the main competitive evidence.

### Decision and limits

Promote the frozen v13 image for 3v3 based on the primary competitive
confirmation and both other-opponent guardrails. The 10.13% rune-rate decline
is a measured cost and narrowly misses the original mechanism target;
promotion does not imply complete replication of that resource-control target.
Healing alone remains a promising but inconclusive win-rate screen. The
combination improves over v10; its incremental benefit over spacing alone
has not been established by fresh confirmation. Keep all three experimental
modes available for a future component comparison.

The driver and Docker build now default to `combined`. The tested v13 image
already explicitly sets that environment mode; its frozen source and image
identity remain in the study's `candidate/` and upload records. `base.py`
is unchanged from the uploaded candidate. Explicit `baseline` selects the
v10 behavior. Keep v10's existing duel membership, since this is a team-play
upgrade. Two full released-engine duels verified 30,720 identical candidate
actions on the same observations.

This fixed campaign comprises 240 hosted episodes in twenty requests of
10–20 episodes each. No games failed or were replaced; one generated seed
was duplicated within the combined selection screen, with both games
retained and disclosed. Fresh confirmation and each guardrail arm have
unique seeds. Network timing, unpaired map draws, and small guardrail samples
limit generalization to other opponents or a future game release.

The next targeted hypothesis is collector availability: the formation
selector checks health, bank, carry and Rot state, but a selected collector
may subsequently prioritize a shop trip, rescue hold or dodge. Join the
collector trace to missed runes before changing eligibility. Also consider
a fresh spacing-only versus combined comparison to isolate healing's value.
Do not reuse this campaign as an untouched holdout for either change.

### Promotion and final audit

Submission `sub_e1cde498-cdd3-471e-b476-f0821e393c79` is **placed**.
The membership API confirms v13 as Aaron's active 3v3 champion:
`lpm_66b2a56a-e50a-4675-b118-0c62fa163d90`, status `competing`, substatus
`active`, `is_champion=true`. V10 remains the active duel champion.

The final audit covers every one of the 240 episodes and all 48,782,011
recorded actions, representing 2,379.74 simulated minutes. All saved replay
files were rehashed against their verified surveys. There are 239 distinct
seeds overall, with only the already disclosed selection-screen duplicate.
`final-audit.json`, `v13-submissions.json` and `active-champions-after.json`
preserve the readbacks and checks.

All 35 policy and six analysis checks pass. After changing the defaults, the
direct driver produced 64 actions identical to the frozen v13 driver;
explicit `baseline` still disables both features, and `base.py` matches the
uploaded source byte-for-byte. A final optional local container rebuild/run
could not complete because the Docker daemon was unresponsive, including
for the previously working frozen image; the hung build was stopped. No
replacement image was uploaded. The promoted v13 image had already passed
its Docker WebSocket probe and 100 hosted games in this campaign.

`watch-combined-win.command` plays a labeled, verified 30–9 win over Myasnik;
the deliberate heal at tick 711 (22.22 seconds) restores 120 HP from P2 to P1.
