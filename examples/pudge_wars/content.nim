## Deterministic Pudge Wars constants.
##
## Modeled on Warcraft 3 Pudge Wars v2.03d: two banks split by a river,
## every player is a butcher, Meat Hook is the kill skill, Blink is a
## short hop that can cross the narrow river gap by the fountain, and
## kills buy hook upgrades.

import std/os, polyworld/[common, hashes]

const
  TickRate* = 32'i32
  PudgeCount* = 6
    ## Default 3v3 roster length. Hashed. N vs N uses `MaxPudgeCount`.
  TeamSize* = 3
    ## Default butchers a bank. Live matches may run 1..MaxTeamSize.
  MaxTeamSize* = 5
    ## Largest N for N vs N. The 3-lane spawn roll stays frozen.
  MaxPudgeCount* = 10
    ## 2 * MaxTeamSize. Lobby wells and seat arrays use this cap.
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
  HookCooldownTicks* = TickRate * 2 + 1
    ## 2 s plus one tick. A round 64-tick cooldown is a multiple of
    ## every even roster (2/4/8 butchers), so the decision-rotation
    ## phase locked to one bank for the whole match and that bank won
    ## every same-cycle hook/rune race. +1 tick makes the throw cycle
    ## drift on 2, 4, 6, 8, and 10 seat boards.
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
    ## Ticks between spawn-pad heal pulses.
  FountainPadRadius* = 2'i32
    ## Chebyshev tile radius around a team's spawn tiles that counts as
    ## the healing pad (matches the stamped road pad).
  IslandFountainHealPermille* = 15'i32
    ## WC3 Fountain of Health: 1.5% of max HP per second (15‰).
    ## Neutral aura around the mid-river island; both teams, any layer.
  IslandFountainHealPeriodTicks* = TickRate
    ## One pulse per second, matching the WC3 fountain.
  IslandFountainRadiusTiles* = 16'i32
    ## Euclidean tiles from the island center. Covers the water around
    ## the rocks and a few tiles of each bank at mid (the side-lane lip
    ## is 12 tiles out; the fountain bulge sits closer). Spawn pads and
    ## the side lanes stay outside.
  IslandFountainRadius* = IslandFountainRadiusTiles * WorldScale
  WalkSnapTiles* = 24'i32
    ## Command forgiveness: a rejected walk target snaps to the nearest
    ## walkable tile on the butcher's bank within this Chebyshev radius.
  RunePeriodTicks* = TickRate * 20
    ## Ticks between river rune drops. The clock is public: first drop
    ## at 0:20, then every 20 s. Location and kind follow a fixed cycle
    ## (not match RNG) so scripts can time the spawn and gank timers.
    ## Matches record the live period; 0 disables drops.
  RuneBuffTicks* = TickRate * 15
  AllyHookHeal* = 120'i32
    ## Hooking a teammate patches them up: support play with the same
    ## aim skill as the kill shot (10% of base HP per landed save).
  SightRadiusTiles* = 20'i32
    ## Fog-of-war vision radius per living butcher and team ward
    ## (team-shared). Presentation and bot observations share this:
    ## scripts only see what a human on that team would. Physics stay
    ## omniscient.
  HookSightPadTiles* = 6'i32
    ## Half-width of the fog corridor along an in-flight hook, and how
    ## far the last segment continues past the head along the throw.
    ## Side padding alone left the tip flush with the shuriken.
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
    ## Hooktrap: hidden mine. Enemy hooks detonate; allied hooks grab.
  ShopWardGold* = 0'i32
    ## Farwatch Ward: free charge from the base shop. The slot restocks
    ## every `WardRestockTicks`; planting spends the charge and clears
    ## the inventory well.
  InventorySlots* = 6'i32
    ## HUD bag wells (3×2, GOTA-style). One unique family per slot;
    ## buy-again ranks it. A planted ward frees its well.
  ItemMaxRank* = 5'i32
    ## Matches WC3 Pudge Wars v2.03d: five levels, purchase upgrades in place.
  ItemBootsSpeedPercent* = 8'i32
    ## Extra move speed per Treads rank, percent of `MovePerTick`.
  ItemLongshotPercent* = 1'i32
    ## Extra hook damage percent per tile of flight, per Brand rank.
  PlaceRangeTiles* = 3'i32
    ## Chebyshev reach for wall/mine drops from the butcher.
  WardPlaceRangeTiles* = 32'i32
    ## Chebyshev plant reach for a carried ward. Side-lane lip-to-lip
    ## is 24 tiles, so a butcher on their waterline can stake the fog
    ## brush on the far bank without walking across.
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
  MineCooldownTicks* = TickRate * 15
  MineRadius* = WorldScale
    ## Mine body the hook disk has to clip.
  MineBlastRadius* = WorldScale * 2
  MaxMinesPerPlayer* = 3'i32
  WardDurationTicks* = TickRate * 45
    ## Observer lifetime: 45 s of team sight, then the stake crumbles.
  WardRestockTicks* = TickRate * 60
    ## Shop restock after picking up a free ward. `wardCooldown` is
    ## this timer, not a place delay.
  WardCooldownTicks* = WardRestockTicks
  WardChargeMax* = 1'i32
    ## Unplanted charges a butcher may carry. One shop pickup.
  MaxWardsPerPlayer* = 1'i32
    ## Living stakes per butcher. Restock is 60 s and life is 45 s,
    ## so a second stake is only in play if you delay the first plant.
  FirstPropId* = 2000'i32
  WallObjectKind* = 2'i32
  MineObjectKind* = 3'i32
  WardObjectKind* = 4'i32

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
    ## Bounty is instant gold, not a timed slot: it does not overwrite
    ## a combat buff.
    RuneHaste,
    RuneDoubleDamage,
    RuneRegen,
    RuneBigHook,
    RuneLightning,
    RuneBounty
  ShopItem* = enum
    ## Base-pad catalog. 0-4 are timed/consumable powerups (keys 5-9);
    ## 5-9 are the five inventory families (boots, brand, palisade,
    ## hooktrap, ward) that occupy the six-well bag. Buy-again ranks
    ## to 5 except wards, which occupy one well until planted.
    ## Inventory full rejects a new family. Flask/rune powerups stay
    ## distinct from the wells.
    ShopFlask,
    ShopHaste,
    ShopRegen,
    ShopBigHook,
    ShopDoubleDamage,
    ShopBoots,
    ShopLongshot,
    ShopWall,
    ShopMine,
    ShopWard
  PropKind* = enum
    ## Placed shop gadgets: a visible HP wall, a hidden mine, or a
    ## timed sight ward.
    PropWall,
    PropMine,
    PropWard
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
  BaseHitPoints* = 1200'i32
    ## Starting HP for every butcher. Kills still grow max HP, and the
    ## shop flask heals it all back.
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
  MovePerTick* = 32_400'i32
    ## 17.3 tiles/s at 32 Hz. 20% faster than the prior 27_000 default.
  MoveAccel* = MovePerTick div 8
    ## Momentum: per-tick speed gained toward the ordered direction
    ## (~0.25 s from rest to top speed at 32 Hz).
  MoveBrake* = MovePerTick div 6
    ## Per-tick speed shed while stopping, coasting, or pivoting on an
    ## order behind the butcher (~0.19 s from sprint to rest, ~0.9 tiles
    ## of skid). Turns of 90° or less carve at full speed instead of
    ## braking (`steerVelocity`), so only stops and reversals pay this.
  BaseHookDamage* = 200'i32
    ## A landed hook is a real chunk: ~17% of 1200 HP, six hits to
    ## kill from full. Upgrades and runes still climb from here.
  HookDamagePerLevel* = 15'i32
  BaseHookRange* = 60 * WorldScale
    ## Lip-to-cliff is 62 tile-centers (`PlayEastMax - PlayWestMax`);
    ## 56 fell ~0.4 tiles short of the grab disk. 60 latches a still
    ## butcher on the far cliff from the river lip (Distance rank 0).
    ## Mid-lane still dies on the fountain. Distance climbs toward the
    ## old 64-tile cross-map reach.
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
  BlinkRangeTiles* = 20'i32
    ## Side-lane lip-to-lip is 24 tiles (`PlayEastMin - PlayWestMax`),
    ## beyond this range. At mid the banks step in, allowing a hop onto
    ## the opposite bank. River water is also a legal landing. Cliffs,
    ## palisades, and occupied circles truncate to the last legal point
    ## in front of them.
  BlinkRange* = BlinkRangeTiles * WorldScale
  BlinkCooldownTicks* = TickRate * 8
    ## 8 s: clearly longer than Meat Hook's 2 s, a real commitment.
  RotRadius* = 8 * WorldScale
    ## 8-tile blight disk. Must exceed `MinSeparation` (5.2 tiles) so a
    ## butcher in melee — or standing on your hip — is inside the cloud.
  RotDamage* = 24'i32
    ## HP per pulse per live cloud. Overlapping disks each fire, so two
    ## butchers rotting the same tile deal 48 (96 DPS) — slow does not
    ## stack. 48 DPS from one cloud is a real commitment against 1200 HP.
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
  DrownDamage* = 30'i32
    ## River tick: 30 HP every half second. A dumped butcher without
    ## a save or hop out lasts about 20 s from full (1200 HP).
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
  RuneLightningDamage* = 120'i32
    ## Charged splash on a landed enemy hook: 10% of 1200 HP. The
    ## victim also takes hook damage; clustered teammates eat this only.
  RuneLightningRadius* = 8 * WorldScale
    ## Same disk as Rot: a melee clump is inside, a lane partner is not.
  RuneLightningTrailDamage* = 8'i32
    ## HP per burn pulse. 16 DPS, a third of Rot, no slow, enemies only.
  RuneLightningTrailRadius* = 2 * WorldScale
    ## Tight corridor: a body at melee standoff is outside; walking the
    ## painted line is inside.
  RuneLightningTrailPeriodTicks* = TickRate div 2
    ## Same pulse cadence as Rot / drown so the DoTs read as kin.
  RuneLightningTrailDurationTicks* = TickRate * 4
    ## Four seconds of burning ground after the charged hook leaves.
  RuneLightningTrailStep* = WorldScale
    ## One patch per tile so a flying hook does not skip cells.
  RuneLightningClashDamage* = 40'i32
    ## Shock through a clashing chain: ~3% of 1200 HP to the other thrower.
  RuneLightningSpeedMul* = 2'i32
    ## Lightning throws fly (and reel) at double the butcher's hook speed.
  MaxFirePatches* = 128'i32
    ## Cap on live lightning trails. Oldest patch yields when full.
  RuneBountyGold* = 4'i32
    ## Instant gold. A kill pays 3; this is a river contest worth a
    ## shop haste/regen and does not overwrite a combat buff.
  RuneNames*: array[RuneKind, string] = [
    "Haste",
    "Double Damage",
    "Regen",
    "Big Hook",
    "Lightning",
    "Bounty"
  ]
  RuneKindCount* = int32(high(RuneKind).ord) + 1
    ## Length of the public kind cycle. Each kind drops north, then
    ## south, then the next kind: haste N/S, double damage N/S, …
  WestSpawns* = [(22, 40), (22, 64), (22, 88)]
    ## Lane-center defaults and the fallback if a pad roll cannot
    ## separate teammates. Live matches use `spawnLayoutFromSeed`.
  EastSpawns* = [(106, 40), (106, 64), (106, 88)]
    ## Mirror of WestSpawns across RiverCenterX (2*64 - 22 = 106).
  ## Same butcher mesh on both banks. West keeps the authored red paint;
  ## east is the blue team recolor. Both GLBs share a Tripo biped skin and
  ## the five named clips.
  PudgeSpecs*: array[Team, PudgeSpec] = [
    PudgeSpec(
      name: "West Butcher",
      modelPath: DataRoot & "/characters/butcher/butcher_game.glb",
      runClip: "ButcherRun",
      idleClip: "ButcherIdle",
      deathClip: "ButcherDeath",
      attackClip: "ButcherHook",
      victoryClip: "ButcherVictory",
      targetHeight: 6.4
    ),
    PudgeSpec(
      name: "East Butcher",
      modelPath: DataRoot & "/characters/butcher/butcher_game_east.glb",
      runClip: "ButcherRun",
      idleClip: "ButcherIdle",
      deathClip: "ButcherDeath",
      attackClip: "ButcherHook",
      victoryClip: "ButcherVictory",
      targetHeight: 6.4
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
    "Hooktrap",
    "Farwatch Ward"
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
    "hooktrap",
    "warding_chalk"
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
    ShopMineGold,
    ShopWardGold
  ]

proc shopPrice*(item: ShopItem): int32 =
  ## Gold charged for one purchase (or one rank-up) of this catalog row.
  ShopPrices[item]

proc shopGoldLabel*(item: ShopItem): string =
  ## Shop row price text. Free catalog rows say FREE, not 0g.
  let gold = shopPrice(item)
  if gold <= 0: "FREE" else: $gold & "g"

proc isPermanent*(item: ShopItem): bool =
  ## True for inventory families; false for flask/rune powerups.
  item >= ShopBoots

const
  PermanentBagOrder*: array[5, ShopItem] = [
    ShopWall, ShopMine, ShopWard, ShopBoots, ShopLongshot
  ]
    ## HUD bag fill order: actives first so a ward/wall/mine keep a
    ## well when the six-slot bag is otherwise full.

proc shopItemMaxRank*(item: ShopItem): int32 =
  ## Rank/charge cap. Wards are a single free charge, not a 1-5 family.
  if item == ShopWard: WardChargeMax else: ItemMaxRank

proc dropReach*(item: ShopItem): int32 =
  ## Chebyshev plant reach for one gadget family.
  if item == ShopWard: WardPlaceRangeTiles else: PlaceRangeTiles

proc shopItemBlurb*(
    item: ShopItem; wallKey = "C", mineKey = "V", wardKey = "B"
): string =
  ## Short explanation for a shop row or inventory well.
  case item
  of ShopFlask: "Drink at the base shop to restore all missing health."
  of ShopHaste: "Haste rune: sprint on land and in the river."
  of ShopRegen: "Regen rune: heal over time."
  of ShopBigHook: "Bigger hook: longer throw, wider grab, extra damage."
  of ShopDoubleDamage: "Double Damage rune: next hooks hit twice as hard."
  of ShopBoots: "Passive. Extra walk speed on land and in the river."
  of ShopLongshot: "Passive. Hook damage grows with how far the hook flew."
  of ShopWall: "Place a HP wall on your bank (" & wallKey & ", then click)."
  of ShopMine:
    "Plant a hidden mine (" & mineKey &
      ", then click; walks there if needed). Ally hooks grab it; enemy hooks detonate it."
  of ShopWard:
    "Free sight ward. Buy at the shop, then plant from inventory (" &
      wardKey &
      "). Click either bank (or the far fog from your lip). Planting spends the charge; the shop restocks one every 60s."

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

proc islandFountainHeal*(maxHp: int32): int32 =
  ## HP restored by one mid-river fountain pulse (1.5% of max).
  max(1'i32, maxHp * IslandFountainHealPermille div 1000)

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
  ## Simultaneous mines: up to three once Hooktrap is owned.
  if rank <= 0: 0'i32 else: MaxMinesPerPlayer

proc maxWardsForRank*(rank: int32): int32 =
  ## Simultaneous living wards. One charge, one stake.
  if rank <= 0: 0'i32 else: MaxWardsPerPlayer

proc formatTiles*(worldUnits: int32): string =
  ## World units as "N.N" tiles for HUD copy.
  let tenths = int(int64(max(worldUnits, 0'i32)) * 10 div WorldScale)
  $(tenths div 10) & "." & $(tenths mod 10)

proc formatSeconds*(ticks: int32): string =
  ## Duration ticks as "N.Ns".
  let tenths =
    (int(max(ticks, 0'i32)) * 10 + int(TickRate) - 1) div int(TickRate)
  $(tenths div 10) & "." & $(tenths mod 10) & "s"

proc rotDps*(): int32 {.inline.} =
  ## Rot pulse converted to damage per second.
  RotDamage * TickRate div max(RotPeriodTicks, 1'i32)

proc thrownHookDamage*(level: int32, bigHook, doubleDamage: bool): int32 =
  ## Meat Hook hit damage after the damage upgrade and combat runes.
  result = hookDamage(level)
  if bigHook:
    result = bigHookDamage(result)
  if doubleDamage:
    result = result * RuneDamageMul

proc thrownHookRange*(level: int32, bigHook: bool): int32 =
  ## Meat Hook travel distance after the distance upgrade and Big Hook.
  result = hookRange(level)
  if bigHook:
    result = result + result * RuneBigHookPercent div 100

proc thrownHookSpeed*(level: int32, lightning: bool): int32 =
  ## Meat Hook flight speed after the speed upgrade and Lightning.
  result = hookSpeed(level)
  if lightning:
    result = result * RuneLightningSpeedMul

proc attackTooltipLines*(damage, periodTicks: int32): seq[string] =
  ## Title, how-to, and swing numbers for the cleaver well.
  @[
    "Attack",
    "Right-click an enemy to walk in and swing. Also chips palisades.",
    $damage & " damage every " & formatSeconds(periodTicks)
  ]

proc hookTooltipLines*(
    damage, rangeUnits: int32,
    longshotRank: int32,
    quickcast, bigHook, doubleDamage, lightning: bool,
    hookKey = "Q"
): seq[string] =
  ## Title, how-to, and live hook numbers for the Meat Hook well.
  var title = "Meat Hook"
  if doubleDamage or bigHook or lightning:
    title.add "  ["
    var first = true
    if doubleDamage:
      title.add "2x"
      first = false
    if bigHook:
      if not first: title.add " + "
      title.add "Big"
      first = false
    if lightning:
      if not first: title.add " + "
      title.add "Bolt"
    title.add "]"
  let how =
    if quickcast:
      "Throws at the cursor. Enemy latch damages and pulls; ally latch heals."
    else:
      "Press " & hookKey &
        ", then click. Enemy latch damages and pulls; ally latch heals."
  var nums = $damage & " dmg - ally +" & $AllyHookHeal & " HP - " &
    formatTiles(rangeUnits) & " tiles - CD " & formatSeconds(HookCooldownTicks)
  result = @[title, how, nums]
  var extra = ""
  if longshotRank > 0:
    extra.add "+" & $(ItemLongshotPercent * longshotRank) & "% dmg/tile"
  if lightning:
    if extra.len > 0:
      extra.add " - "
    extra.add $RuneLightningSpeedMul & "x speed - " &
      $RuneLightningDamage & " splash / " &
      formatTiles(RuneLightningRadius) & " tiles - trail " &
      $RuneLightningTrailDamage & " - clash " & $RuneLightningClashDamage
  if extra.len > 0:
    result.add extra

proc grappleTooltipLines*(grappleKey = "E"): seq[string] =
  ## Title, how-to, and pull numbers for the E-grapple (not on the bar).
  @[
    "Grapple",
    "Press " & grappleKey &
      ", then click. Latches terrain and yanks you to it. Deals no damage.",
    "0 damage - " & formatTiles(GrappleRange) & " tiles - CD " &
      formatSeconds(GrappleCooldownTicks)
  ]

proc rotTooltipLines*(active: bool, rotKey = "R"): seq[string] =
  ## Title, how-to, and pulse numbers for the Rot well.
  @[
    if active: "Rot  [ON]" else: "Rot",
    "Toggle (" & rotKey &
      ") a blight cloud. Damages everyone inside, including you.",
    $RotDamage & " dmg / " & formatSeconds(RotPeriodTicks) &
      " (" & $rotDps() & " DPS) - " & formatTiles(RotRadius) &
      " tiles - " & $RotSlowPercent & "% slow"
  ]

proc blinkTooltipLines*(blinkKey = "F"): seq[string] =
  ## Title, how-to, and hop numbers for the Blink well.
  @[
    "Blink",
    "Hop toward the cursor (" & blinkKey &
      "). Cross the narrow gap by the fountain. Cliffs, walls and bodies stop the hop.",
    $BlinkRangeTiles & " tiles - CD " & formatSeconds(BlinkCooldownTicks)
  ]

proc shopItemTitle*(item: ShopItem, rank: int32): string =
  ## Catalog name, plus rank for inventory families.
  result = ShopItemNames[item]
  if item == ShopWard:
    if rank > 0:
      result.add "  [carrying]"
    else:
      result.add "  [in shop]"
  elif item.isPermanent:
    result.add "  [rank " & $max(rank, 0'i32) & "/" & $ItemMaxRank & "]"

proc shopItemEffect*(item: ShopItem, rank: int32): string =
  ## Numeric damage, heal, or buff for one catalog row at this rank.
  let shown = max(rank, 1'i32)
  case item
  of ShopFlask:
    "Restores all missing HP"
  of ShopHaste:
    "+" & $RuneHastePercent & "% move speed for " & formatSeconds(RuneBuffTicks)
  of ShopRegen:
    $RuneRegenPercent & "% max HP every " & formatSeconds(RuneRegenPeriodTicks) &
      " for " & formatSeconds(RuneBuffTicks)
  of ShopBigHook:
    "+" & $RuneBigHookPercent & "% size - +" & $RuneBigHookDamagePercent &
      "% hook damage for " & formatSeconds(RuneBuffTicks)
  of ShopDoubleDamage:
    $RuneDamageMul & "x hook damage for " & formatSeconds(RuneBuffTicks)
  of ShopBoots:
    "+" & $(ItemBootsSpeedPercent * shown) & "% move speed (" &
      $ItemBootsSpeedPercent & "% per rank)"
  of ShopLongshot:
    "+" & $(ItemLongshotPercent * shown) & "% hook damage per tile of flight (" &
      $ItemLongshotPercent & "% per rank)"
  of ShopWall:
    $wallMaxHp(shown) & " HP - " & formatSeconds(wallDurationTicks(shown)) &
      " life - max " & $maxWallsForRank(shown) & " - CD " &
      formatSeconds(wallCooldownTicks(shown))
  of ShopMine:
    $mineBlastDamage(shown) & " dmg - " & formatTiles(MineBlastRadius) &
      "-tile blast - max " & $maxMinesForRank(shown) & " - " &
      formatSeconds(MineDurationTicks) & " life - CD " &
      formatSeconds(MineCooldownTicks)
  of ShopWard:
    formatTiles(SightRadiusTiles * WorldScale) & "-tile sight - plant within " &
      $WardPlaceRangeTiles & " tiles - " & formatSeconds(WardDurationTicks) &
      " life - shop restocks every " & formatSeconds(WardRestockTicks)

proc shopItemTooltipLines*(
    item: ShopItem, rank: int32;
    wallKey = "C", mineKey = "V", wardKey = "B"
): seq[string] =
  ## Title, explanation, and effect numbers for a shop or inventory well.
  @[
    shopItemTitle(item, rank),
    shopItemBlurb(item, wallKey, mineKey, wardKey),
    shopItemEffect(item, rank)
  ]

proc upgradeTooltipLines*(kind: UpgradeKind, level: int32): seq[string] =
  ## Title, explanation, and current/next numbers for a hook upgrade well.
  let
    maxed = level >= MaxUpgradeLevel
    nextLevel = min(level + 1, MaxUpgradeLevel)
  var effect, numbers: string
  case kind
  of UpgradeDamage:
    effect = "Each rank: +" & $HookDamagePerLevel & " enemy hook damage."
    numbers = $hookDamage(level) & " damage"
    if not maxed:
      numbers.add " > " & $hookDamage(nextLevel)
  of UpgradeDistance:
    effect = "Each rank: +" & formatTiles(HookRangePerLevel) &
      " tiles of hook range."
    numbers = formatTiles(hookRange(level)) & " tiles"
    if not maxed:
      numbers.add " > " & formatTiles(hookRange(nextLevel))
  of UpgradeSpeed:
    effect = "Each rank: faster hook flight (and reel)."
    numbers = formatTiles(hookSpeed(level) * TickRate) & " tiles/s"
    if not maxed:
      numbers.add " > " & formatTiles(hookSpeed(nextLevel) * TickRate)
  of UpgradeRadius:
    effect = "Each rank: a wider hook grab (easier latches)."
    numbers = formatTiles(hookRadius(level)) & " tiles"
    if not maxed:
      numbers.add " > " & formatTiles(hookRadius(nextLevel))
  if maxed:
    numbers.add " - MAXED"
  else:
    numbers.add " - cost: 1 point"
  @[
    UpgradeNames[kind] & "  [rank " & $level & "/" & $MaxUpgradeLevel & "]",
    effect,
    numbers
  ]

proc clampTeamSize*(n: int): int {.inline.} =
  ## N vs N is 1..5 a side.
  if n < 1: 1
  elif n > MaxTeamSize: MaxTeamSize
  else: n

proc matchPudgeCount*(teamSize: int): int {.inline.} =
  ## Both banks: 2, 4, 6, 8, or 10 butchers.
  clampTeamSize(teamSize) * 2

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
  hash.addHashy(IslandFountainHealPermille)
  hash.addHashy(IslandFountainHealPeriodTicks)
  hash.addHashy(IslandFountainRadiusTiles)
  hash.addHashy(IslandFountainRadius)
  hash.addHashy(WalkSnapTiles)
  hash.addHashy(HookAccel)
  hash.addHashy(HookSpeedMaxMul)
  hash.addHashy(RunePeriodTicks)
  hash.addHashy(RuneKindCount)
  hash.addHashy(RuneBuffTicks)
  hash.addHashy(AllyHookHeal)
  hash.addHashy(SightRadiusTiles)
  hash.addHashy(HookSightPadTiles)
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
  hash.addHashy(ShopWardGold)
  hash.addHashy(InventorySlots)
  hash.addHashy(ItemMaxRank)
  hash.addHashy(ItemBootsSpeedPercent)
  hash.addHashy(ItemLongshotPercent)
  hash.addHashy(PlaceRangeTiles)
  hash.addHashy(WardPlaceRangeTiles)
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
  hash.addHashy(WardDurationTicks)
  hash.addHashy(WardRestockTicks)
  hash.addHashy(WardCooldownTicks)
  hash.addHashy(WardChargeMax)
  hash.addHashy(MaxWardsPerPlayer)
  hash.addHashy(FirstPropId)
  hash.addHashy(WallObjectKind)
  hash.addHashy(MineObjectKind)
  hash.addHashy(WardObjectKind)
  hash.addHashy(RuneDriftPerTick)
  hash.addHashy(RuneRadius)
  hash.addHashy(RunePickupRadius)
  hash.addHashy(RuneHastePercent)
  hash.addHashy(RuneDamageMul)
  hash.addHashy(RuneRegenPercent)
  hash.addHashy(RuneRegenPeriodTicks)
  hash.addHashy(RuneBigHookPercent)
  hash.addHashy(RuneBigHookDamagePercent)
  hash.addHashy(RuneLightningDamage)
  hash.addHashy(RuneLightningRadius)
  hash.addHashy(RuneLightningTrailDamage)
  hash.addHashy(RuneLightningTrailRadius)
  hash.addHashy(RuneLightningTrailPeriodTicks)
  hash.addHashy(RuneLightningTrailDurationTicks)
  hash.addHashy(RuneLightningTrailStep)
  hash.addHashy(RuneLightningClashDamage)
  hash.addHashy(RuneLightningSpeedMul)
  hash.addHashy(MaxFirePatches)
  hash.addHashy(RuneBountyGold)
  uint64(hash)
