# Battle Royale Design Research — Hook Royale

Design research for a top-down, deterministic-sim, bot-vs-human battle
royale on the PolyWorld engine (RTS camera, integer sim @ 32 ticks/s,
replays, BASIC-scripted bots, 1 human + N bots, LAN party hosting),
building on Fresh Meat (momentum hooks, wall bounces, mid-air clashes,
melee, drowning river, runes, kill scoring). Web-grounded, August 2026.
No code here — design only. Sources at the bottom.

Engine facts this report calibrates against (verified in
`maps.nim` / `content.nim`): 128×128 tile grid (~112×112 playable),
run speed 11.5 tiles/s, hook base range 64 tiles, hook flight
~19→58 tiles/s (accelerating), hook disk 3.5 tiles, hook cooldown 2 s
(windup ~0.2 s), 420 base HP, hook 80 damage, melee 28, drown 10 HP
per 0.5 s.

---

## 1. Why the BR loop is fun — and what breaks it

The loop is four interlocking pressures, each covering a weakness of
the others [S1]:

- **The shrinking zone is the "invisible director."** Its whole job is
  to force encounters and delete passive play. It carves every match
  into legible phases: loot → rotate/skirmish → high-stakes endgame.
  Remove it and the match stalls into a camping simulator [S1].
- **Drop choice is the first real decision.** Hot-drop for fast fights
  and early power, or quiet-drop for a safe curve. It sets each
  match's narrative before the first hit [S1, S3].
- **Loot scarcity is hope.** Landing empty-handed and scrambling for
  the first weapon is a deliberate engagement spike; the power curve
  from "nothing" to "kitted" is the genre's progression fantasy
  compressed into minutes [S1].
- **One life is consequence.** Permadeath is what makes footsteps
  matter. Circle = tension, loot = hope, permadeath = consequence,
  map = possibility; together they generate emergent stories (the
  clutch, the unlucky drop, the last-second heal) [S1].

What ruins BRs, per the same literature and case studies:

- **Dead time.** Minutes of walking or empty looting without a
  decision. The 2026 industry trend is aggressive compression: even
  Fortnite is trialing storm changes that cut ~2:30 off matches
  (wait −98 s, close −50 s, circles 7–20% smaller) [S8], and PUBG's
  gamescom 2026 pitch is "shorter, more meaningful matches" [S2].
- **Loot RNG deciding fights.** If the purple-gun player beats the
  gray-gun player regardless of skill, fights are decided before they
  start. Mitigations: high loot density, rarity as side-grades, skill
  weapons.
- **Camping.** Solved structurally: damage ramps, moving late
  circles, healing penalties in gas (Brawl Stars halves healing in
  poison [S6]), anti-stall stacks (LoL Arena's Ring of Char [S7]).
- **Third-party frustration.** Winning a fight then dying to a fresh
  vulture is the genre's most-cited sore spot [S9]. Key finding for
  us: **top-down largely self-mitigates this.** Rock Paper Shotgun on
  ZombsRoyale: the top-down view "gave all players an equal footing
  and prevented third-partying" — you see the vulture coming — making
  it "far, far less frustrating" than 3D BRs [S5].
- **Early death = wasted session.** Mitigated by short matches +
  instant requeue (surviv.io's stated philosophy: minimize time
  between matches [S4]) and by second chances (Reload, Gulag) [S10].

## 2. What Fortnite teaches — and what survives top-down translation

- **Building/editing is the highest skill ceiling in the genre — and
  it walled out the audience.** Zero Build (2022) brought back lapsed
  players and streamers overnight; an estimated **80–90% of new
  players stick with Zero Build**, and it has at times overtaken Build
  in players [S11, S12]. The lesson is not "skill mechanics bad" — it
  is: **the signature skill mechanic must not gate basic
  participation.** Zero Build still layered skill back in via
  movement (sprint/mantle/slide) and positioning. Our hook is already
  shaped right: anyone can throw one; mastery is prediction, momentum,
  bounces, clashes.
- **Movement is the other half of the skill gradient.** Mobility items
  (shockwave/overdrive grenades, grapplers, launch pads) consistently
  top item tier lists, and rotation guides state a mobility slot is
  "often worth more than a third weapon" late-game [S13, S14].
  Translation: mobility must be a first-class loot category — and ours
  can literally be the hook (terrain latch, bounce boosts).
- **Rarity tiers (gray→gold)** are instant power-legibility and give
  looting a purpose gradient. Trivially portable to top-down.
- **Chests + supply drops**: guaranteed-spawn containers with cues
  structure drop routing; airdrops are public risk magnets that pull
  players into optional contests. Portable.
- **Storm phasing** (Chapter 6: 12 phases; 1% max-HP/s damage in
  phases 1–5 escalating to 2/5/8/10%/s; circles *move* from phase 6
  on) is a wait/close/damage table — pure integer data, perfect for a
  deterministic sim [S15]. The Reload mode table (40-player small
  map, first wait 50 s, ~13 compressed phases) is the best template
  for our match length [S15].
- **Healing economy**: white HP vs blue shield, minis capped at 50,
  channel-time vulnerability. The rhythm fight → reset → re-fight is
  load-bearing; healing *while exposed* being dangerous is the point.
- **Reboot vans / Reload respawns**: Reload's insight is that death as
  a *temporary setback* rewards aggression — kills shave your team's
  respawn timers; reboots shut off near endgame to restore one-life
  tension; solo players can *earn back* a reboot by dealing damage
  [S10, S16]. Reload pulled 1M+ players its launch weekend on a
  chest-littered condensed map [S16].
- **Live events / battle pass**: retention theater, orthogonal to
  the core loop. Out of scope.

Translates cleanly to top-down: rarity, chests/drops, storm table,
healing economy, mobility-as-loot, solo second chance. Does not
translate: building (see Skip list), verticality/mantling, 100-player
scale.

## 3. Top-down / isometric BR case studies

- **Battlerite Royale (2018, †2019)** — 30-player top-down
  cooldown-combat BR. Died of *business*, not design: shipped as a
  standalone $20 title that split an already-small community, right as
  Apex launched; contemporaries called the mode itself "an excellent
  spin on the genre" [S17]. Design cautions that do stand: the BR
  macro layer diluted the arena fights that made the base game great,
  and big-map loot sparseness created dead time. Keep fights frequent
  and loot simple.
- **Eternal Return (2020– )** — the surviving top-down BR/MOBA hybrid,
  18 players. Its core skill is **resource routing**: crafting routes
  are "closer to a MOBA build order than typical BR looting";
  "preparation is the win condition" [S18]. It also proves **discrete
  area closures** (whole districts become restricted on a timer)
  work as a zone system — very friendly to a tile sim. Its failure
  mode: a 400-item knowledge cliff that crushes onboarding [S18].
  Steal the routing *skill*, skip the crafting *complexity*.
- **surviv.io (2017, †2023)** — proof that 2D BR at speed works:
  3–5 minute matches, 50–100 player (bot-padded) lobbies, escalating
  red-zone damage, bushes for stealth, "minimize time between
  matches" as an explicit design philosophy; PC Gamer called it one of
  the most enjoyable BRs, full stop [S4].
- **ZombsRoyale.io (2018– )** — 100 slots (heavily bot-filled),
  ~5 minute matches, 120M+ downloads. Rarity colors, endgame mythic
  airdrops, gas 2–10 damage. RPS verdict quoted above: top-down =
  equal footing, less third-party frustration, "less satisfying than
  winning a 45-minute PUBG match — but also far, far less
  frustrating" [S5]. Short matches shrink the sting of death.
- **Brawl Stars Showdown** — the micro-BR gold standard: 10 players,
  ~2–3 minutes. **Power Cubes** are the cleanest BR economy ever
  shipped: boxes *and* kills feed one power currency (+400 HP, +10%
  damage each); dead players drop 1 + ⅓ of their cubes (cap 5), so
  the leader is a walking jackpot; poison gas deals 20% max-HP/s,
  ramps if you linger, and **halves healing** [S6]. Bush stealth
  drives its vision game. Its one chronic disease — teaming in solo —
  literally cannot happen in a bot lobby.
- **MOBA mini-royales** — Dota Underlords is an autobattler (not a
  BR; skip). **LoL Arena** (2v2×8) is the relevant one: TFT-style
  **augment drafts** create per-run identity/variance, the Ring of
  Fire spawns 30 s into each round, and **Ring of Char** stacks
  punish repeat fire-dodging so stalling degrades across rounds; Deep
  Water terrain blocks movement but *not* vision (exactly our river);
  Power Flower is a neutral objective giving ranged players an angle
  in closed arenas [S7].
- **Fog of war** is top-down's native information game — the
  replacement for 3D's "who holds high ground." MOBA doctrine (vision
  control, bush ambushes, jungle pathing) is a proven skill axis
  [S19], and an RTS engine gets FoW nearly free. None of the io-BRs
  ship true FoW; that is headroom for us, not a warning.

Pacing norms across the genre: top-down matches run **2–8 minutes**
(Brawl 2–3, surviv 3–5, Zombs ~5, Battlerite ~10; Eternal Return
~15+ is the outlier *and* the onboarding-pain outlier), with lobbies
of **10–40 real players** (Brawl 10, ER 18, BRR 30, Reload 40; the
"100-player" io games are bot-padded).

## 4. High-skill-gradient mechanics, ranked (ceiling × implementability here)

| # | Mechanic | Skill ceiling | Fit in deterministic tile sim |
|---|----------|---------------|-------------------------------|
| 1 | **Hook skillshots** (prediction, displacement, clashes) | Proven for two decades: hooks are "the fadeaway threes, the Hail Mary passes… one of the best interactions in any multiplayer game" [S20]; displacement is rare, high-impact, and a mutual mind game (Dota wiki: "one of the most difficult abilities to use in all of Dota") [S21] | Already shipped, with momentum + bounces + clashes on top of vanilla |
| 2 | **Movement tech** (momentum, skid, hook-boosts, terrain latches) | Fortnite evidence: movement mastery and mobility items dominate high-level play [S13, S14] | Momentum/accel/brake already integer; terrain latch is the same hook math |
| 3 | **Zone prediction & rotation** (rotate early vs gatekeep, edge-riding) | The macro skill in every BR guide [S14]; deterministic circles make expert prediction *more* rewarding | A phase table of integers; free |
| 4 | **Vision play** (FoW, bushes, scouting, info denial) | Core MOBA skill axis [S19]; unique top-down advantage | RTS engine native |
| 5 | **Cooldown management** (2 s hook CD windows, forced dodges) | Battlerite/ER's whole combat game | Trivial in a tick sim |
| 6 | **Resource routing** (drop choice, chest routes, rune timings) | ER's "preparation is the win condition" [S18], minus the crafting cliff | Seeded deterministic spawns = learnable routes |
| 7 | **Cover & destructibles** (breaking trees/rocks, angle carving) | Zero Build shows cover play carries fights without building [S11]; destruction reshapes bounce geometry mid-fight | Tile flags flip; hooks already raycast vs tiles |
| 8 | **Healing windows** (channel heals under threat) | The reset rhythm every BR runs on | Timers + interrupts, integer |
| 9 | **Comeback micro** (kill piñatas, bounties) | Brawl's cube-drop turns leaders into objectives [S6] | Drop tables, deterministic |
| 10 | **Endgame micro** (moving circles, 1v1v1 clash standoffs) | Fortnite moving phases 6+ [S15]; our clash system shines at 3 players | Offset/drift is more table data |

## (a) The 10–15 features that matter most — ranked

1. **Deterministic shrinking zone (phase table: wait/close/damage,
   late circles offset & moving)** — the invisible director that turns
   a hook arena into a story arc: forced rotations, no camping, free
   endgame drama [S1, S15].
2. **Hook-as-power-curve loot: everyone always has a hook; all loot
   modifies it** (range, flight speed, disk size, bounce count, reel,
   damage; exotic hooks late) — keeps BR "hope" (loot → power) while
   ensuring fights are still decided by aim, not drops [S1, S11].
3. **Fog of war + bush/forest stealth** — top-down's replacement for
   high ground: scouting, ambushes, and info denial as a skill axis
   the io-BRs never shipped; nearly free on an RTS engine [S19, S5].
4. **Terrain self-hook (latch trees/rocks/walls to yank yourself; keep
   wall bounces)** — Fortnite proves a mobility slot outvalues a third
   weapon [S13, S14]; making mobility a *hook skillshot* doubles the
   signature mechanic's ceiling instead of adding a new system.
5. **Drop choice over named POIs with legible loot density** — the
   first meaningful decision of every match; hot vs quiet drop sets
   the match narrative and gives bots readable landing personas [S1, S3].
6. **Kill piñata (dead units drop their mods + part of their power)**
   — Brawl Stars' cleanest idea: kills are lootable jackpots,
   contesting fights pays, and the snowballing leader becomes a
   walking bounty that pulls the lobby toward them [S6].
7. **Bot cast with personas + a skill dial** (drop routing, loot
   greed, zone discipline, fight/flee thresholds, third-party
   appetite) — Fortnite fills up to 90 of 100 slots with bots to keep
   matches alive and kills achievable [S22, S23]; in our lobbies bots
   ARE the matchmaking, and the `players/*.bas` persona system plus
   the duel-loop telemetry is already the training pipeline.
8. **Solo second chance: the reboot duel** (die before phase N → one
   1v1 hook duel vs a bot on a tiny island; win to re-drop, once) —
   in a 1-human lobby, human death ends the product; Reload/Gulag
   show a *skill-based* second chance preserves aggression without
   cheapening one-life tension, and Reload shuts reboots off near
   endgame to restore it [S10, S16].
9. **Healing with vulnerability windows + gas heal penalty** (channel
   to heal, interruptible; healing halved in the zone) — creates the
   fight → reset → re-fight rhythm and structurally kills zone-edge
   stalling [S6, S15].
10. **Chests with cues + one endgame supply drop** — guaranteed loot
    magnets make routing a learnable skill; a telegraphed late-game
    drop is an optional objective that pulls finalists into contact —
    and ours can be *hooked* from range, which is a fight starter [S3, S5].
11. **Destructible cover (hookable/breakable trees & rocks)** — the
    20%-cost analog of building: fights permanently reshape dodge
    geometry and feed the bounce system new angles mid-fight; Zero
    Build proves cover play carries fights without construction [S11].
12. **Runes as timed, telegraphed map spikes** (Haste / Double Damage
    / Regen / Big Hook — already built) — contested power-ups give the
    mid-game a reason to fight *before* the zone forces it [S7].
13. **Moving + offset late circles with anti-stall ramp** — endgame
    intensity insurance: center-campers lose their rent and rotation
    prediction stays a live skill to the last second (Fortnite phases
    6+ move; LoL's Ring of Char punishes stalling) [S15, S7].
14. **Post-match skill ledger** (placement + kills + hook accuracy by
    distance, dodge stats, zone-damage taken) — BR fun is emergent
    stories; surfacing the stats the duel pipeline already logs makes
    the skill gradient visible and gives every match a lesson.

## (b) Features to explicitly SKIP

1. **Fortnite-style building/editing** — Zero Build's success (80–90%
   of new players never leave it [S12]) proves the loop doesn't need
   it; top-down APM-construction would fight the hook micro, wreck bot
   pathing and the deterministic tile cache, and cost a quarter of the
   engine. Destructibles (#11) + terrain hooks (#4) capture the
   spatial-improvisation value at a fraction of the cost.
2. **A gun/weapon arsenal** — every weapon slot that isn't a hook
   dilutes the signature mechanic; surviv.io needed 40 guns because it
   had no hook. Variety belongs inside the hook mod space.
3. **Eternal Return-style crafting routes** — its 400-item knowledge
   cliff is the genre's worst onboarding [S18]; we get routing skill
   from chests, runes, and zone reading without the wiki homework.
4. **Vehicles** — rotation is already solved at our map scale by
   11.5 tiles/s movement + Haste + terrain hooks; deterministic
   vehicle physics plus bot driving is a money pit for a mobility
   niche the hook should own anyway.
5. **Squad reboot logistics (cards/vans) and team modes at launch** —
   with 1 human + bots, teammate-revive drama is bot-on-bot noise; the
   solo reboot duel (#8) covers the retention need. If LAN co-op vs
   bots becomes the mode, add Reload-style auto-timers, not card
   ferrying. (Battle pass / live events: also out of scope [S2].)

## (c) Recommended match parameters

| Parameter | Recommendation | Grounding |
|---|---|---|
| Lobby size | **16 units (1 human + 15 bots)**; support 12–24 | Top-down norm is 10–40 [S6, S18, S16]; 16 keeps constant contact at our speeds; 24 bots × 20k instr × 32 Hz ≈ 15M instr/s — cheap |
| Map size | **192×192 tiles** (~176 playable), 6–8 named POIs; the current 128×128 works as a 10–12 player "small mode" | Hook range (64 tiles) should be ≤ ⅓ map width so the early game has approach play; ~48×48 tiles of territory per unit → first contact ~30–60 s; full sprint traverse ~17 s keeps rotations decisions, not commutes |
| Zone phases | **6 phases**, all integer ticks. Radius (of 96): 96→58→38→24→14→8→0. Wait: 45/30/25/20/15/10 s. Close: 20/20/15/15/10/20 s. Damage: 1/1/2/4/6/10% max HP/s (≈4→42 HP/s at 420 HP). Phase 5 center offsets up to 40% of radius; phase 6 drifts | Compressed from Fortnite's Ch6 + Reload tables (1%→10%/s ramp, moving late circles) [S15]; % max-HP damage scales with the power curve [S6]; full close ≈ 4:05 |
| Match length | **Median ~5 min, hard cap ~7**; instant requeue | Top-down sweet spot 3–8 min [S4, S5, S6]; surviv's "minimize time between matches" is the retention engine [S4] |
| TTK | Equal gear: **4–5 hook hits or 3 hooks + melee finish** (80 dmg vs 420 HP) ≈ 8–15 s of engaged fighting early, compressing to **2–3 hooks (~5–8 s)** endgame via damage mods. No single hit > ~45% max HP outside Double Damage windows. The 2 s hook CD is the outplay budget: every miss donates a full dodge-or-punish window | Apex designers: TTK too low kills outplay, too high devalues positioning [S24]; skillshot games sit higher than hitscan because landing hits is the skill; keeping lucky one-shots out keeps loot RNG from deciding fights |
| Loot density | First hook mod within **~15 s of any landing**; ≥1 chest per POI cluster (~1 per 12×12 tiles inside POIs), sparse field spawns between; chests restock (~60 s) only if long matches emerge; 1 supply drop at phase 4; runes on a fixed telegraphed 60 s cadence | Reload "littered with chests so players are up and fighting in no time" + restocking [S16]; Zombs endgame airdrops [S5] |
| Healing | Two items only: channel heal (~3 s, +40% max HP, interruptible, slowed) and instant nibble (+15%, short CD); **healing halved inside the gas**; no passive regen (Regen rune excepted) | Fortnite's channel-vulnerability rhythm [S13]; Brawl's 50% gas rule kills edge-stalling [S6] |

## (d) Making hooks the "building"-tier signature mechanic

Fortnite building earned its status through five properties: always
available from second one; one mechanic serving offense, defense, and
mobility; a skill gap that is *visible* to spectators; a practice
ceiling that never ends; and interaction with every other system.
Map each onto hooks:

1. **The hook is a right, not loot.** Everyone spawns with the base
   hook; loot only modifies it. This is the Zero Build lesson inverted
   — the mechanic gates nothing at entry (anyone can throw), but its
   ceiling (leading targets through bounces into clashes) is
   effectively unbounded [S11, S20, S21].
2. **Three verbs, one mechanic.**
   *Kill*: displace enemies into your melee, the river, or the gas —
   environmental displacement is the highlight factory, and hooking
   someone into the storm at phase 5 is the clip that markets the
   game.
   *Travel*: latch terrain to yank yourself (our grappler/launch pad),
   bounce-boost momentum lines, river crossings.
   *Economy*: hook chests, runes, kill piñatas, and the supply drop
   from range — loot-stealing hooks are the top-down equivalent of the
   pump-edit play, and they weaponize every pickup contest.
3. **The clash is the duel.** Mid-air hook clashes (already built) are
   the mirror-matchup mind game — our edit war. Endgame 1v1v1s with
   three hooks in flight are the format's signature image.
4. **Counterplay doctrine keeps it fair.** MOBA rule: skillshots are
   avoidable by default [S19]. Dodge (momentum movement), counter-
   clash, degradable cover, and the 2 s cooldown clock give the
   defender a full vocabulary — the skill gradient lives on both ends
   of the rope, which is exactly why hooks have anchored competitive
   games for twenty years [S20].
5. **The zone mechanically buffs hooks.** As the circle shrinks, dodge
   space disappears and hook pressure compounds — the genre's endgame
   intensity and our signature mechanic converge without any extra
   design. Storm displacement threat makes the final circles a hook
   pressure cooker.
6. **Bots make the gradient legible and climbable.** Hook prediction
   depth, windup reaction, and dodge cadence are clean bot difficulty
   dials; the existing duel-loop telemetry (accuracy by distance,
   dodge stats) doubles as the player's post-match skill ledger and as
   the SBMM analog for tuning lobbies — Fortnite's bots exist
   precisely to give improving players achievable goals [S22, S23].

## Sources

- [S1] Civiliden, "Expert Breakdown of Popular Battle Royale Game Design" — https://civiliden.com/expert-breakdown-of-popular-battle-royale-game-design/
- [S2] 247videogame, "How PUBG is Aiming to Reinvent the Battle Royale… Again" (gamescom 2026) — https://247videogame.com/how-pubg-is-aiming-to-reinvent-the-battle-royale-again-gamescom-2026/
- [S3] Game-Ace, "Battle royale game development: a production guide" — https://game-ace.com/blog/how-to-make-a-battle-royale-game/
- [S4] Wikipedia, "Surviv.io" (+ Grokipedia entry: 3–5 min matches, zone pacing) — https://en.wikipedia.org/wiki/Surviv.io
- [S5] Wikipedia, "ZombsRoyale.io" (incl. Rock Paper Shotgun quotes on top-down third-partying) — https://en.wikipedia.org/wiki/ZombsRoyale.io
- [S6] Brawl Stars wiki + guides, Solo Showdown (power cubes, gas rules) — https://brawlstars.fandom.com/wiki/Showdown
- [S7] LoL Wiki, "Arena" + Riot "/dev: Arena" (augments, Ring of Fire/Char, Deep Water) — https://leagueoflegends.fandom.com/wiki/Arena_(League_of_Legends)
- [S8] AllThings.how, "Fortnite Speeds Up the Storm… July 27 2026 Hotfix" — https://allthings.how/fortnite-speeds-up-the-storm-and-removes-triangle-circles-in-the-hotfix/
- [S9] GamePron, "Third-Party in Battle Royale" — https://gamepron.com/glossary/third-party-in-battle-royale/
- [S10] Kotaku/GameSpot on Reboot Vans; gamertagmythras Reload guide — https://kotaku.com/the-good-and-bad-of-fortnites-new-respawn-system-1833951661
- [S11] The Verge, "Fortnite's Zero Build mode is bringing people back" — https://www.theverge.com/2022/4/15/23024470/fortnite-zero-build-mode-player-return-twitch-the-fierce-diva-sypherpk
- [S12] Dignitas, "How Zero Build Mode Possibly Saved Fortnite" (80–90% of new players) — https://dignitas.gg/articles/how-zero-build-mode-saved-fortnite
- [S13] GameRant/AllThings tier lists (Overdrive Grenades, mobility meta) — https://gamerant.com/fortnite-override-chapter-7-season-4-best-weapons-items-meta-tier-list/
- [S14] gamertagmythras, "Fortnite Rotation Guide" ("a mobility slot is often worth more than a third weapon") — https://gamertagmythras.com/blog/fortnite/fortnite-rotation-guide
- [S15] Fortnite Wiki, "The Storm" (Ch6 + Reload phase tables) — https://fortnite.fandom.com/wiki/The_Storm
- [S16] Polygon + Nintendo + TechTimes on Fortnite Reload (40→50 players, reboot timers, chest density) — https://www.polygon.com/gaming/24185789/fortnite-reload-new-game-mode/
- [S17] Ten Ton Hammer, "Battlerite: What Went Wrong?" — https://www.tentonhammer.com/articles/battlerite-what-went-wrong
- [S18] MMOHuts Eternal Return review ("preparation is the win condition"); Jon Spencer Reviews (onboarding cliff) — https://mmohuts.com/review/eternal-return-black-survival
- [S19] GameDesignSkills, "MOBA Game Design" (skillshot counterplay doctrine, fog/vision as skill) — https://gamedesignskills.com/game-design/moba/
- [S20] Kotaku, "What Makes Hooks So Damn Good In Competitive Video Games" — https://kotaku.com/what-makes-hooks-so-damn-good-in-competitive-video-game-1795938444
- [S21] Dota 2 Wiki, "Pudge/Guide" — https://dota2.fandom.com/wiki/Pudge/Guide
- [S22] Epic Games support, "How does matchmaking work in Fortnite?" (fewer bots as skill rises) — https://www.epicgames.com/help/en-US/fortnite-battle-royale-c-202300000001636/gameplay-c-202300000001721/how-does-matchmaking-work-in-fortnite-a202300000011382
- [S23] eTeknix (10–90 bots per lobby by SBMM tier); Fortnite Wiki "Bots" (bot behaviors) — https://www.eteknix.com/fortnite-og-mode-features-up-to-90-bots-dependent-on-player-skill/
- [S24] EA/Respawn, "Breach Designer's Notes" (TTK philosophy: high TTK overvalued mobility; lowered for positioning) — https://www.ea.com/games/apex-legends/apex-legends/news/28-0-designers-notes
