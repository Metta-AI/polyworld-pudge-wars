## Deterministic Pudge Wars constants.
##
## Modeled on Warcraft 3 Pudge Wars v2.03d: two banks split by a river,
## every player is a butcher, Meat Hook is the kill skill, Blink is a
## 48-tile dodge teleport that can hop the river, land in the water, or
## blink out onto a bank, and kills buy hook upgrades.

import std/os, polyworld/[common, hashes]

const
  TickRate* = 32'i32
  PudgeCount* = 6
  TeamSize* = 3
  DuelPudgeCount* = 2
    ## Roster size of the 1v1 duel mode: one butcher a side on the
    ## middle spawn lane. Everything else plays by the stock rules.
  DuelKillGoal* = 10'i32
    ## Default first-to-N kills in a duel; short enough for an
    ## analyze-improve loop between matches.
  DuelMinutes* = 10'i32
    ## Default duel duration when no explicit length is given.
  KillGoal* = 30'i32
    ## Default first-to-N kill win condition; matches may override it
    ## (`World.killGoal`) and replays record the active goal in their setup.
  RespawnTicks* = TickRate * 4
  HookCooldownTicks* = TickRate * 2
  AttackTicks* = 19'i32
  DecisionTicks* = 1'i32
  MaxUpgradeLevel* = 10
  WorldScale* = 60_000'i32
  HookWindupTicks* = 9'i32
    ## ~0.28 s cast point (up from 0.19): the telegraph is readable,
    ## so dodging a seen throw is a skill, not a coin flip.
    ## Cast point before the hook head leaves the hand (~0.19 s at 32 Hz).
    ## The caster turns to face the aim point and is rooted while winding
    ## up. Zero restores instant release.
  SpawnShieldTicks* = TickRate * 2
    ## Post-respawn protection: unhookable and unattackable until the
    ## butcher acts (walk, hook, or attack) or the window expires.
  FountainHealPercent* = 2'i32
    ## Percent of max HP restored per heal pulse while idling on the own
    ## team's spawn pad.
  FountainHealPeriodTicks* = TickRate div 2
    ## Ticks between fountain heal pulses.
  FountainPadRadius* = 2'i32
    ## Chebyshev tile radius around a team's spawn tiles that counts as
    ## the healing pad (matches the stamped road pad).
  WalkSnapTiles* = 24'i32
    ## Command forgiveness: a rejected walk target snaps to the nearest
    ## walkable tile on the butcher's bank within this Chebyshev radius.
  RunePeriodTicks* = TickRate * 20
    ## Default ticks between river rune spawns. Matches record the live
    ## period in their setup; 0 disables runes entirely.
  RuneBuffTicks* = TickRate * 15
  AllyHookHeal* = 120'i32
  SightRadiusTiles* = 20'i32
    ## Fog-of-war vision radius per living butcher (team-shared).
    ## Presentation only: bots and the sim are unaffected, so this
    ## stays out of the content hash.
    ## Hooking a teammate patches them up: support play with the same
    ## aim skill as the kill shot (~14% of base HP per landed save).
  GoldPerKill* = 3'i32
    ## Shop currency: earned only through play, spent only in base.
  GoldPerDeny* = 1'i32
    ## A landed mid-air deflection pays out too.
  GoldFirstBlood* = 2'i32
    ## Extra gold for the match's first enemy kill.
    ## Dota 2 First Blood is +135 unreliable gold (liquipedia Gold);
    ## 135 / 60 ≈ 2 at the same ÷60 scale as streak bonuses.
  MultiKillWindowTicks* = TickRate * 18
    ## Dota 2 multi-kill window is 18 s between successive hero kills
    ## (liquipedia Attribute bonuses: `multikill time window`).
    ## Display only: double / triple / ultra / rampage. No gold.
  ShopRadiusTiles* = 4'i32
    ## Chebyshev reach of each base's shop pad.
  ShopFlaskGold* = 5'i32
    ## Instant full heal.
  ShopHasteGold* = 4'i32
  ShopRegenGold* = 4'i32
  ShopBigHookGold* = 6'i32
  ShopDoubleDamageGold* = 8'i32
    ## How long one picked-up rune empowers its butcher.
  ShopBootsGold* = 10'i32
    ## River Treads: one inventory slot, ranks stack move speed.
  ShopLongshotGold* = 12'i32
    ## Longflight Brand: hook damage grows with tiles of flight.
  ShopWallGold* = 10'i32
    ## Bank Palisade: place a timed HP wall on your bank.
  ShopMineGold* = 10'i32
    ## Hooktrap: place an invisible mine enemies can hook.
  InventorySlots* = 4'i32
    ## HUD inventory wells. One unique family per slot; buy-again ranks it.
  ItemMaxRank* = 5'i32
    ## Matches WC3 Pudge Wars v2.03d: five levels, purchase upgrades in place.
  ItemBootsSpeedPercent* = 8'i32
    ## Extra move speed per Treads rank, percent of `MovePerTick`.
  ItemLongshotPercent* = 1'i32
    ## Extra hook damage percent per tile of flight, per Brand rank.
  PlaceRangeTiles* = 3'i32
    ## Chebyshev reach for wall/mine drops from the butcher.
  WallDurationTicks* = TickRate * 10
    ## Base palisade lifetime before it crumbles.
  WallDurationPerRankTicks* = TickRate * 2
  WallBaseHp* = 120'i32
  WallHpPerRank* = 40'i32
  WallCooldownTicks* = TickRate * 10
  WallCooldownCutPerRank* = TickRate
  WallCooldownMinTicks* = TickRate * 6
  MaxWallsPerPlayer* = 2'i32
  MineDurationTicks* = TickRate * 40
  MineBaseDamage* = 80'i32
  MineDamagePerRank* = 20'i32
  MineCooldownTicks* = TickRate * 8
  MineRadius* = WorldScale
    ## Mine body the hook disk has to clip.
  MineBlastRadius* = WorldScale * 2
  MaxMinesPerPlayer* = 2'i32
  FirstPropId* = 2000'i32
  WallObjectKind* = 2'i32
  MineObjectKind* = 3'i32

type
  Team* = enum
    WestTeam,
    EastTeam
  PudgeState* = enum
    Alive,
    Dying
  HookPhase* = enum
    HookIdle,
    HookFlying,
    HookReeling
  UpgradeKind* = enum
    UpgradeDamage,
    UpgradeDistance,
    UpgradeSpeed,
    UpgradeRadius
  RuneKind* = enum
    ## River rune buffs, WC3-style: one timed power-up per butcher.
    RuneHaste,
    RuneDoubleDamage,
    RuneRegen,
    RuneBigHook
  ShopItem* = enum
    ## Base-pad catalog. 0-4 are timed/consumable powerups (keys 5-9);
    ## 5-8 are the four permanent inventory families (one HUD well
    ## each). Buy-again ranks to 5; inventory full rejects a new
    ## family. Flask/rune powerups stay distinct from the wells.
    ShopFlask,
    ShopHaste,
    ShopRegen,
    ShopBigHook,
    ShopDoubleDamage,
    ShopBoots,
    ShopLongshot,
    ShopWall,
    ShopMine
  PropKind* = enum
    ## Placed shop gadgets: a visible HP wall, or a hidden mine.
    PropWall,
    PropMine
  PudgeSpec* = object
    name*: string
    modelPath*: string
    runClip*: string
    idleClip*: string
    deathClip*: string
    attackClip*: string
    victoryClip*: string
    targetHeight*: float32

const
  BaseHitPoints* = 840'i32
    ## Doubled: fights are brawls now, not two-hook exchanges. Kills
    ## still grow max HP, and the shop flask heals it all back.
  HitPointsPerLevel* = 35'i32
  BaseMeleeDamage* = 28'i32
  PudgeCollisionRadius* = WorldScale * 13 div 5
    ## 2.6 tiles. Visual butchers are ~5–6 units tall; 1.5 tiles still
    ## stacked meshes on the waterline. Centers stay at least 5.2 tiles
    ## apart so two living bodies show a clear gap.
  MinSeparation* = PudgeCollisionRadius * 2
  MeleeRange* = MinSeparation
    ## Fight at the collision standoff, not inside the opponent.
  AutoAcquireRange* = MeleeRange + WorldScale * 2
    ## Idle human butchers pick up enemies this close and walk into melee.
  MovePerTick* = 27_000'i32
    ## 14.4 tiles/s at 32 Hz. 25% faster than the prior 21_600 default.
  MoveAccel* = MovePerTick div 8
    ## Momentum: per-tick speed gained toward the ordered direction
    ## (~0.25 s from rest to top speed at 32 Hz).
  MoveBrake* = MovePerTick div 6
    ## Per-tick speed shed while stopping, coasting, or pivoting on an
    ## order behind the butcher (~0.19 s from sprint to rest, ~0.9 tiles
    ## of skid). Turns of 90° or less carve at full speed instead of
    ## braking (`steerVelocity`), so only stops and reversals pay this.
  BaseHookDamage* = 80'i32
  HookDamagePerLevel* = 15'i32
  BaseHookRange* = 56 * WorldScale
    ## Trimmed from 64: throws are commitments again; the Distance
    ## upgrade climbs back toward the old cross-map reach.
    ## ~1.78× the prior 36-tile default. The river is ~24 tiles; this
    ## crosses it from a spawn with leftover for bank depth and bounces.
  HookRangePerLevel* = 4 * WorldScale
  BaseHookSpeed* = 36_000'i32
  HookSpeedPerLevel* = 1_800'i32
  HookReelMul* = 2'i32
    ## Legacy 2× table used by `hookReelSpeed`. Live reel uses the hook's
    ## peak outbound speed, not this multiplier.
  HookAccel* = 1_800'i32
    ## Added to outbound speed each extending tick. Integer, not a step.
  HookSpeedMaxMul* = 3'i32
    ## Peak outbound cap as a multiple of `BaseHookSpeed` (3× = 108_000).
  HookSpeedMax* = BaseHookSpeed * HookSpeedMaxMul
  BaseHookRadius* = WorldScale * 11 div 4
    ## 2.75 tiles (down from 3.5): hooks demand real aim now; radius
    ## upgrades claw the old width back over a match.
    ## Latch is this disk plus `PudgeCollisionRadius`. The in-world
    ## head is a meat hook; this radius is the grab disk, not the mesh.
  GrappleCooldownTicks* = TickRate * 6
    ## E-grapple: terrain-latch utility cast, ~6 s between pulls.
  GrappleRange* = 20 * WorldScale
    ## Shorter than a max hook: a mobility tool, not a poke.
  GrappleRadius* = WorldScale
    ## Slim head: it grabs walls, not butchers.
  BlinkRangeTiles* = 48'i32
    ## 48-tile dodge hop (2× the prior 24). Lands on the farthest
    ## walkable tile along the aim ray: river water is flown over, so
    ## a hop can clear to the opposite bank, but water is never a
    ## landing. Cliffs, palisades, and occupied circles truncate the
    ## hop to the last legal point in front of them.
  BlinkRange* = BlinkRangeTiles * WorldScale
  BlinkCooldownTicks* = TickRate * 8
    ## 8 s: clearly longer than Meat Hook's 2 s, a real commitment.
  RotRadius* = 8 * WorldScale
    ## 8-tile blight disk. Must exceed `MinSeparation` (5.2 tiles) so a
    ## butcher in melee — or standing on your hip — is inside the cloud.
  RotDamage* = 24'i32
    ## HP per pulse per live cloud. Overlapping disks each fire, so two
    ## butchers rotting the same tile deal 48 (96 DPS) — slow does not
    ## stack. 48 DPS from one cloud is a real commitment against 840 HP.
  RotPeriodTicks* = TickRate div 2
    ## Pulse cadence; matches drown so the two DoTs read as kin.
  RotSlowPercent* = 40'i32
    ## Move-speed cut while inside any rot disk, including your own.
  HookRadiusPerLevel* = WorldScale div 8
  HookDumpDistance* = WorldScale
  HookClashRadius* = WorldScale div 2
    ## Extra deflection grace beyond the two hook disks: half a
    ## tile (up from a sixth) so a deliberate mid-air deny is landable
    ## by humans without making reactive bot denies unmissable.
  ChunkAnnounceTicks* = TickRate * 4
  DrownDamage* = 10'i32
  DrownPeriodTicks* = TickRate div 2
  StruggleSpeed* = MovePerTick
    ## River locomotion uses the land walk. Kept as an alias so the
    ## content fingerprint still names the water step.
  PudgeObjectKind* = 1'i32
  RuneDriftPerTick* = WorldScale div 8
    ## River current speed: 4 tiles per second at 32 Hz, so a rune takes
    ## ~28 s to cross the arena and at most two float at once.
  RuneRadius* = WorldScale
    ## Orb body radius: hooks latch at disk + this, walkers grab at
    ## `RunePickupRadius`.
  RunePickupRadius* = PudgeCollisionRadius
    ## Body-contact grab reach. Deliberately no rune-radius bonus: the
    ## midline spawn sits far enough from both banks that a dry butcher
    ## can never reach one; wading (or hooking) is the price.
  RuneHastePercent* = 40'i32
    ## Haste rune: extra move speed while buffed.
  RuneDamageMul* = 2'i32
    ## Double Damage rune: hook damage multiplier at release.
  RuneRegenPercent* = 3'i32
    ## Regen rune: percent of max HP restored per pulse.
  RuneRegenPeriodTicks* = TickRate div 2
    ## Ticks between Regen rune heal pulses.
  RuneBigHookPercent* = 50'i32
    ## Big Hook rune: extra hook range and disk radius at release.
  RuneBigHookDamagePercent* = 50'i32
    ## Big Hook rune: extra hook damage at release (1.5× unbuffed).
    ## Same round percent as the size buff; cheaper than Double Damage
    ## (2×) because the throw also grows and wins clashes.
  RuneNames*: array[RuneKind, string] = [
    "Haste",
    "Double Damage",
    "Regen",
    "Big Hook"
  ]
  WestSpawns* = [(22, 40), (22, 64), (22, 88)]
    ## Lane-center defaults and the fallback if a pad roll cannot
    ## separate teammates. Live matches use `spawnLayoutFromSeed`.
  EastSpawns* = [(106, 40), (106, 64), (106, 88)]
    ## Mirror of WestSpawns across RiverCenterX (2*64 - 22 = 106).
  PudgeSpecs*: array[Team, PudgeSpec] = [
    PudgeSpec(
      name: "West Butcher",
      modelPath: DataRoot & "/characters/rpg_monsters/orc.glb",
      runClip: "RunForward",
      idleClip: "IdleNormal",
      deathClip: "Death",
      attackClip: "Attack01",
      victoryClip: "Victory",
      targetHeight: 6.2
    ),
    PudgeSpec(
      name: "East Butcher",
      modelPath: DataRoot & "/characters/rpg_monsters/demon_king.glb",
      runClip: "RunForward",
      idleClip: "IdleNormal",
      deathClip: "Death",
      attackClip: "Attack01",
      victoryClip: "Victory",
      targetHeight: 6.6
    )
  ]
  UpgradeNames*: array[UpgradeKind, string] = [
    "Hook Damage",
    "Hook Distance",
    "Hook Speed",
    "Hook Radius"
  ]
  HookAbilityIcon* = "meat_hook"
  BlinkAbilityIcon* = "riftwake"
    ## HUD well for F-blink: a rift/phase mark already in abilities/.
  RotAbilityIcon* = "withering_idol"
    ## HUD well for R-rot: a sick-green idol already in abilities/.
  AttackIcon* = "attack"
  PortraitKeys*: array[Team, string] = ["pudge_west", "pudge_east"]
  UpgradeIcons*: array[UpgradeKind, string] = [
    "hook_damage",
    "hook_distance",
    "hook_speed",
    "hook_radius"
  ]
  HeadshotIcon* = "hook_headshot"
  ChunkIcon* = "hook_chunk"
  DenyIcon* = "hook_deny"
  RiverDumpIcon* = "river_dump"
  ShopItemNames*: array[ShopItem, string] = [
    "Flask",
    "Haste",
    "Regen",
    "Big Hook",
    "2x Damage",
    "River Treads",
    "Longflight Brand",
    "Bank Palisade",
    "Hooktrap"
  ]
  ShopItemIcons*: array[ShopItem, string] = [
    "",
    "",
    "",
    "",
    "",
    "river_treads",
    "longflight_brand",
    "bank_palisade",
    "hooktrap"
  ]
  ShopPrices*: array[ShopItem, int32] = [
    ShopFlaskGold,
    ShopHasteGold,
    ShopRegenGold,
    ShopBigHookGold,
    ShopDoubleDamageGold,
    ShopBootsGold,
    ShopLongshotGold,
    ShopWallGold,
    ShopMineGold
  ]

proc shopPrice*(item: ShopItem): int32 =
  ## Gold charged for one purchase (or one rank-up) of this catalog row.
  ShopPrices[item]

proc isPermanent*(item: ShopItem): bool =
  ## True for inventory families; false for flask/rune powerups.
  item >= ShopBoots

proc shopItemBlurb*(item: ShopItem): string =
  ## One-line HUD tooltip for a shop row.
  case item
  of ShopFlask: "Instant full heal."
  of ShopHaste: "15s haste rune."
  of ShopRegen: "15s regen rune."
  of ShopBigHook: "15s bigger hook, +" & $RuneBigHookDamagePercent &
    "% damage."
  of ShopDoubleDamage: "15s double hook damage."
  of ShopBoots: "+" & $ItemBootsSpeedPercent & "% move speed per rank."
  of ShopLongshot: "Hook hits deal +" & $ItemLongshotPercent &
    "% damage per tile of flight, per rank."
  of ShopWall: "Place a HP wall on your bank (C, then click). Cooldown."
  of ShopMine: "Place a hidden mine (V, then click). Enemy hooks detonate it."

proc iconPath*(name: string, kind = "icons"): string =
  ## Returns a polyworld_data path for one published PNG.
  DataRoot & "/" & kind & "/" & name & ".png"

proc soundPath*(name: string): string =
  ## Returns a polyworld_data path for one published WAV.
  DataRoot & "/sounds/pudge_wars/" & name & ".wav"

proc portraitPath*(team: Team): string =
  ## Returns the roster portrait beside one butcher's GLB.
  changeFileExt(PudgeSpecs[team].modelPath, ".profile.png")

proc hookDamage*(level: int32): int32 =
  ## Returns Meat Hook damage at one upgrade rank.
  BaseHookDamage + HookDamagePerLevel * clamp(level, 0'i32, MaxUpgradeLevel)

proc hookRange*(level: int32): int32 =
  ## Returns Meat Hook travel distance at one upgrade rank.
  BaseHookRange + HookRangePerLevel * clamp(level, 0'i32, MaxUpgradeLevel)

proc hookSpeed*(level: int32): int32 =
  ## Returns Meat Hook travel speed per tick at one upgrade rank.
  BaseHookSpeed + HookSpeedPerLevel * clamp(level, 0'i32, MaxUpgradeLevel)

proc hookReelSpeed*(level: int32): int32 =
  ## Legacy 2× pull-in table at one upgrade rank. The sim reels at the
  ## hook's peak outbound speed, not this value.
  hookSpeed(level) * HookReelMul

proc hookRadius*(level: int32): int32 =
  ## Returns the hook grab radius at one upgrade rank. Latch uses
  ## this plus `PudgeCollisionRadius` (disk vs body, not hub vs center).
  BaseHookRadius + HookRadiusPerLevel * clamp(level, 0'i32, MaxUpgradeLevel)

proc pudgeMaxHp*(kills: int32): int32 =
  ## Returns current hit points after kill-earned levels.
  BaseHitPoints + HitPointsPerLevel * max(kills, 0'i32)

proc streakBonusGold*(streak: int32): int32 =
  ## Extra gold at this streak length. Paid to the killer as their own
  ## spree bonus (streak after this kill) and again as shutdown gold
  ## (victim's streak at death). Zero below Killing Spree.
  ##
  ## Dota 2 (liquipedia Gold, 7.33+): shutdown only, f(x) = 5x² + 5x,
  ## capped at 10: 60 / 100 / 150 / 210 / 280 / 360 / 450 / 550 for
  ## streaks 3..10+. WC3 DotA 1 (dotawiki.de) was linear 60×(n−2) =
  ## 60 / 120 / … / 480. Dota 2 does not pay the killer for their own
  ## streak; we do, at this same scaled table, so a spree is worth
  ## playing for in a 3-gold kill economy.
  ##
  ## Scale ÷60, nearest int (Godlike 450 → 8, Beyond Godlike 550 → 9).
  ## Shop prices are 4–12 gold; GoldPerKill is 3 vs Dota's ~125 base.
  if streak < 3:
    return 0
  if streak >= 10:
    return 9
  case streak
  of 3: 1
  of 4: 2
  of 5: 3
  of 6: 4
  of 7: 5
  of 8: 6
  of 9: 8
  else: 0

proc killBountyGold*(
    killerStreak, victimStreak: int32, firstBlood: bool
): int32 =
  ## Enemy-kill payout: base + own-streak bonus + shutdown + first blood.
  result = GoldPerKill +
    streakBonusGold(killerStreak) +
    streakBonusGold(victimStreak)
  if firstBlood:
    result += GoldFirstBlood

proc streakTitle*(streak: int32): string =
  ## Dota 2 / WC3 DotA kill-streak banner. Empty below Killing Spree.
  ## Counts: 3 killing spree, 4 dominating, 5 mega kill, 6 unstoppable,
  ## 7 wicked sick, 8 monster kill, 9 godlike, 10+ beyond godlike.
  if streak < 3:
    return ""
  if streak >= 10:
    return "BEYOND GODLIKE"
  case streak
  of 3: "KILLING SPREE"
  of 4: "DOMINATING"
  of 5: "MEGA KILL"
  of 6: "UNSTOPPABLE"
  of 7: "WICKED SICK"
  of 8: "MONSTER KILL"
  of 9: "GODLIKE"
  else: ""

proc multiKillTitle*(count: int32): string =
  ## Dota 2 rapid-kill banner. Empty below a double kill.
  ## 2 double, 3 triple, 4 ultra, 5+ rampage. 18 s window.
  if count < 2:
    return ""
  if count >= 5:
    return "RAMPAGE"
  case count
  of 2: "DOUBLE KILL"
  of 3: "TRIPLE KILL"
  of 4: "ULTRA KILL"
  else: ""

proc streakFeedLine*(name: string, streak: int32): string =
  ## Kill-feed sentence for a named spree. Dota cadence, butcher names.
  let title = streakTitle(streak)
  if title.len == 0:
    return ""
  if streak == 3 or streak == 5 or streak == 8:
    return name & " is on a " & title
  if streak >= 10:
    return name & " is " & title & ", someone kill them"
  name & " is " & title

proc longshotDamage*(baseDamage, rank, traveled: int32): int32 =
  ## Hook hit damage after Longflight Brand: +N% per tile of flight
  ## per rank. Rank 0 is a no-op.
  if rank <= 0 or baseDamage <= 0:
    return max(baseDamage, 0'i32)
  let
    tiles = max(traveled, 0'i32) div WorldScale
    bonus = ItemLongshotPercent * rank * tiles
  baseDamage * (100 + bonus) div 100

proc bigHookDamage*(baseDamage: int32): int32 =
  ## Hook damage after the Big Hook rune: +N% on the throw's base.
  if baseDamage <= 0:
    return 0
  baseDamage * (100 + RuneBigHookDamagePercent) div 100

proc wallMaxHp*(rank: int32): int32 =
  ## Palisade hit points at one item rank.
  WallBaseHp + WallHpPerRank * max(rank, 1'i32)

proc wallDurationTicks*(rank: int32): int32 =
  ## Palisade lifetime at one item rank.
  WallDurationTicks + WallDurationPerRankTicks * max(rank, 1'i32)

proc wallCooldownTicks*(rank: int32): int32 =
  ## Delay between palisade drops at one item rank.
  max(
    WallCooldownMinTicks,
    WallCooldownTicks - WallCooldownCutPerRank * max(rank - 1, 0'i32)
  )

proc mineBlastDamage*(rank: int32): int32 =
  ## Hooktrap explosion damage at one item rank.
  MineBaseDamage + MineDamagePerRank * max(rank, 1'i32)

proc maxWallsForRank*(rank: int32): int32 =
  ## Simultaneous palisades: one at ranks 1-2, two from rank 3.
  if rank >= 3: MaxWallsPerPlayer else: 1'i32

proc maxMinesForRank*(rank: int32): int32 =
  ## Simultaneous mines: one at ranks 1-2, two from rank 3.
  if rank >= 3: MaxMinesPerPlayer else: 1'i32

proc contentHash*(): uint64 =
  ## Fingerprints the published balance table.
  var hash = HashySeed
  hash.addHashy(TickRate)
  hash.addHashy(PudgeCount)
  hash.addHashy(KillGoal)
  hash.addHashy(RespawnTicks)
  hash.addHashy(HookCooldownTicks)
  hash.addHashy(BaseHookDamage)
  hash.addHashy(BaseHookRange)
  hash.addHashy(BaseHookSpeed)
  hash.addHashy(HookSpeedPerLevel)
  hash.addHashy(HookReelMul)
  hash.addHashy(BaseHookRadius)
  hash.addHashy(BaseHitPoints)
  hash.addHashy(PudgeCollisionRadius)
  hash.addHashy(MinSeparation)
  hash.addHashy(MeleeRange)
  hash.addHashy(AutoAcquireRange)
  hash.addHashy(AttackTicks)
  hash.addHashy(MovePerTick)
  hash.addHashy(MoveAccel)
  hash.addHashy(MoveBrake)
  hash.addHashy(HookDumpDistance)
  hash.addHashy(HookClashRadius)
  hash.addHashy(GrappleCooldownTicks)
  hash.addHashy(GrappleRange)
  hash.addHashy(GrappleRadius)
  hash.addHashy(BlinkRangeTiles)
  hash.addHashy(BlinkRange)
  hash.addHashy(BlinkCooldownTicks)
  hash.addHashy(RotRadius)
  hash.addHashy(RotDamage)
  hash.addHashy(RotPeriodTicks)
  hash.addHashy(RotSlowPercent)
  hash.addHashy(ChunkAnnounceTicks)
  hash.addHashy(DrownDamage)
  hash.addHashy(DrownPeriodTicks)
  hash.addHashy(StruggleSpeed)
  hash.addHashy(HookWindupTicks)
  hash.addHashy(SpawnShieldTicks)
  hash.addHashy(FountainHealPercent)
  hash.addHashy(FountainHealPeriodTicks)
  hash.addHashy(FountainPadRadius)
  hash.addHashy(WalkSnapTiles)
  hash.addHashy(HookAccel)
  hash.addHashy(HookSpeedMaxMul)
  hash.addHashy(RunePeriodTicks)
  hash.addHashy(RuneBuffTicks)
  hash.addHashy(AllyHookHeal)
  hash.addHashy(GoldPerKill)
  hash.addHashy(GoldPerDeny)
  hash.addHashy(GoldFirstBlood)
  hash.addHashy(MultiKillWindowTicks)
  for n in 3'i32 .. 10'i32:
    hash.addHashy(streakBonusGold(n))
  hash.addHashy(ShopRadiusTiles)
  hash.addHashy(ShopFlaskGold)
  hash.addHashy(ShopHasteGold)
  hash.addHashy(ShopRegenGold)
  hash.addHashy(ShopBigHookGold)
  hash.addHashy(ShopDoubleDamageGold)
  hash.addHashy(ShopBootsGold)
  hash.addHashy(ShopLongshotGold)
  hash.addHashy(ShopWallGold)
  hash.addHashy(ShopMineGold)
  hash.addHashy(InventorySlots)
  hash.addHashy(ItemMaxRank)
  hash.addHashy(ItemBootsSpeedPercent)
  hash.addHashy(ItemLongshotPercent)
  hash.addHashy(PlaceRangeTiles)
  hash.addHashy(WallDurationTicks)
  hash.addHashy(WallDurationPerRankTicks)
  hash.addHashy(WallBaseHp)
  hash.addHashy(WallHpPerRank)
  hash.addHashy(WallCooldownTicks)
  hash.addHashy(WallCooldownCutPerRank)
  hash.addHashy(WallCooldownMinTicks)
  hash.addHashy(MaxWallsPerPlayer)
  hash.addHashy(MineDurationTicks)
  hash.addHashy(MineBaseDamage)
  hash.addHashy(MineDamagePerRank)
  hash.addHashy(MineCooldownTicks)
  hash.addHashy(MineRadius)
  hash.addHashy(MineBlastRadius)
  hash.addHashy(MaxMinesPerPlayer)
  hash.addHashy(FirstPropId)
  hash.addHashy(WallObjectKind)
  hash.addHashy(MineObjectKind)
  hash.addHashy(RuneDriftPerTick)
  hash.addHashy(RuneRadius)
  hash.addHashy(RunePickupRadius)
  hash.addHashy(RuneHastePercent)
  hash.addHashy(RuneDamageMul)
  hash.addHashy(RuneRegenPercent)
  hash.addHashy(RuneRegenPeriodTicks)
  hash.addHashy(RuneBigHookPercent)
  hash.addHashy(RuneBigHookDamagePercent)
  uint64(hash)
