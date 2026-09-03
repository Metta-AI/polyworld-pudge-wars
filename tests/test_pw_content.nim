## Pudge Wars balance table, upgrade curves, and butcher model names.

import
  std/[json, os, sets, streams, strformat, strutils],
  polyworld/common,
  ../examples/pudge_wars/content

proc readGltfClips(path: string): HashSet[string] =
  ## Reads animation names out of one binary glTF container.
  doAssert fileExists(path), &"missing asset: {path}"
  let stream = newFileStream(path, fmRead)
  doAssert stream != nil, &"cannot open asset: {path}"
  defer:
    stream.close()
  doAssert stream.readStr(4) == "glTF", &"not a binary glTF: {path}"
  discard stream.readUint32()
  discard stream.readUint32()
  let
    chunkLength = stream.readUint32()
    chunkKind = stream.readUint32()
  doAssert chunkKind == 0x4E4F534A'u32, &"first chunk is not JSON: {path}"
  let document = parseJson(stream.readStr(int(chunkLength)))
  if document.hasKey("animations"):
    for animation in document["animations"]:
      if animation.hasKey("name"):
        result.incl animation["name"].getStr()

echo "Testing the published roster and win condition"
block:
  doAssert PudgeCount == 6
  doAssert TeamSize == 3
  doAssert PudgeCount == TeamSize * 2
  doAssert KillGoal > 0
  doAssert TickRate > 0
  doAssert RespawnTicks > 0
  doAssert HookCooldownTicks > 0
  doAssert WestSpawns.len == TeamSize
  doAssert EastSpawns.len == TeamSize
  doAssert EastSpawns[0][0] == 2 * 64 - WestSpawns[0][0],
    "east default pads must mirror west"

echo "Testing hook and butcher curves stay positive and increase"
block:
  doAssert BaseHitPoints > 0
  doAssert BaseMeleeDamage > 0
  doAssert MeleeRange > 0
  doAssert MovePerTick > 0
  doAssert hookDamage(0) == BaseHookDamage
  doAssert hookRange(0) == BaseHookRange
  doAssert hookSpeed(0) == BaseHookSpeed
  doAssert hookReelSpeed(0) == BaseHookSpeed * HookReelMul
  doAssert hookRadius(0) == BaseHookRadius
  doAssert hookDamage(1) > hookDamage(0)
  doAssert hookRange(1) > hookRange(0)
  doAssert hookSpeed(1) > hookSpeed(0)
  doAssert hookReelSpeed(1) > hookReelSpeed(0)
  doAssert hookRadius(1) > hookRadius(0)
  doAssert BaseHookRange == 56 * WorldScale
  doAssert BaseHookRange >= (36 * WorldScale * 3) div 2,
    "default range should be at least 1.5× the prior 36-tile throw"
  doAssert BaseHookRange <= 36 * WorldScale * 2,
    "default range should stay at or under 2× the prior 36-tile throw"
  doAssert BaseHookRange >= 24 * WorldScale * 2,
    "default throw should cross the ~24-tile river with leftover"
  doAssert BaseHookRadius == WorldScale * 11 div 4,
    "sim latch disk must be the 2.75-tile hook grab"
  doAssert HookAccel == 1_800'i32
  doAssert HookSpeedMax == BaseHookSpeed * HookSpeedMaxMul
  doAssert HookSpeedMaxMul >= 2'i32 and HookSpeedMaxMul <= 4'i32
  doAssert BaseHookSpeed >= 36_000'i32, "hooks should cross the river quickly"
  doAssert HookReelMul >= 2'i32, "legacy 2× table stays published"
  doAssert HookCooldownTicks <= TickRate * 2
  doAssert MovePerTick >= 21_600'i32,
    "walk should be at least the prior 21_600 default"
  doAssert MovePerTick <= 32_400'i32,
    "walk should stay at or under 1.5× the prior 21_600 default"
  doAssert TickRate == 32
  doAssert RespawnTicks == TickRate * 4
  doAssert HookCooldownTicks == TickRate * 2
  doAssert BlinkCooldownTicks == TickRate * 8
  doAssert BlinkCooldownTicks > HookCooldownTicks
  doAssert BlinkRange == BlinkRangeTiles * WorldScale
  doAssert BlinkRangeTiles == 48'i32
    # 2× the prior 24-tile dodge; sim clamp uses this cap.
  doAssert RotRadius == 8 * WorldScale
  doAssert RotRadius > MinSeparation,
    "rot must reach a butcher standing at melee standoff"
  doAssert RotDamage > 0
  doAssert RotPeriodTicks == TickRate div 2
  doAssert RotSlowPercent == 40
  doAssert DrownPeriodTicks == TickRate div 2
  doAssert AttackTicks == 19
  doAssert MovePerTick == 27_000'i32
  doAssert BaseHookSpeed * TickRate == 48_000'i32 * 24'i32,
    "hook tiles-per-second should match the 24 Hz faster default"
  doAssert hookDamage(MaxUpgradeLevel) == hookDamage(MaxUpgradeLevel + 4)
  doAssert pudgeMaxHp(2) > pudgeMaxHp(0)
  doAssert pudgeMaxHp(-3) == BaseHitPoints
  doAssert HookDumpDistance > 0
  doAssert HookClashRadius > 0
  doAssert ChunkAnnounceTicks > 0
  doAssert DrownDamage > 0
  doAssert DrownPeriodTicks > 0
  doAssert StruggleSpeed == MovePerTick,
    "water walk must match land walk"
  doAssert PudgeCollisionRadius >= WorldScale * 12 div 5,
    "collision radius must be at least 2.4 tiles so meshes do not stack"
  doAssert PudgeCollisionRadius <= WorldScale * 3,
    "collision radius must stay at or under 3.0 tiles"
  doAssert MinSeparation == PudgeCollisionRadius * 2
  doAssert MeleeRange >= MinSeparation,
    "melee must still reach when two solid bodies are at standoff"

echo "Testing both butcher models and clips resolve"
block:
  for team in Team:
    let
      spec = PudgeSpecs[team]
      clips = readGltfClips(spec.modelPath)
    doAssert spec.name.len > 0
    doAssert spec.targetHeight >= 5.0'f32, "butchers should read as large WC3 pudges"
    doAssert spec.runClip in clips, &"{spec.modelPath} has no {spec.runClip}"
    doAssert spec.idleClip in clips, &"{spec.modelPath} has no {spec.idleClip}"
    doAssert spec.deathClip in clips, &"{spec.modelPath} has no {spec.deathClip}"
    doAssert spec.attackClip in clips,
      &"{spec.modelPath} has no {spec.attackClip}"
    doAssert spec.victoryClip in clips,
      &"{spec.modelPath} has no {spec.victoryClip}"
    doAssert fileExists(portraitPath(team)),
      "missing portrait: " & portraitPath(team)

echo "Testing the web replay pack lists butcher HUD assets"
block:
  let
    webdataPath = currentSourcePath().parentDir / "../examples/pudge_wars/webdata.txt"
    webdata = readFile(webdataPath)
  var entries: seq[string]
  for line in webdata.splitLines:
    let entry = line.strip()
    if entry.len == 0 or entry.startsWith("#"):
      continue
    entries.add entry
  proc packed(rel: string): bool =
    for entry in entries:
      if rel == entry or rel.startsWith(entry & "/"):
        return true
    false
  proc dataRel(path: string): string =
    let prefix = DataRoot & "/"
    doAssert path.startsWith(prefix), path
    path[prefix.len .. ^1]
  for team in Team:
    let
      modelRel = dataRel(PudgeSpecs[team].modelPath)
      portraitRel = dataRel(portraitPath(team))
    doAssert packed(modelRel), "webdata.txt missing " & modelRel
    doAssert packed(portraitRel), "webdata.txt missing " & portraitRel
  for rel in [
    dataRel(iconPath(HookAbilityIcon, "abilities")),
    dataRel(iconPath(BlinkAbilityIcon, "abilities")),
    dataRel(iconPath(RotAbilityIcon, "abilities")),
    dataRel(iconPath(AttackIcon))
  ]:
    doAssert packed(rel), "webdata.txt missing " & rel
  for item in ShopBoots .. ShopMine:
    let name = ShopItemIcons[item]
    if name.len == 0:
      continue
    let rel = dataRel(iconPath(name, "items"))
    doAssert packed(rel), "webdata.txt missing " & rel

echo "Testing published Pudge Wars icons resolve"
block:
  doAssert fileExists(iconPath(HookAbilityIcon, "abilities")),
    "missing " & iconPath(HookAbilityIcon, "abilities")
  doAssert fileExists(iconPath(BlinkAbilityIcon, "abilities")),
    "missing " & iconPath(BlinkAbilityIcon, "abilities")
  doAssert fileExists(iconPath(RotAbilityIcon, "abilities")),
    "missing " & iconPath(RotAbilityIcon, "abilities")
  for kind in UpgradeKind:
    let path = iconPath(UpgradeIcons[kind])
    doAssert fileExists(path), "missing " & path
  for name in [HeadshotIcon, ChunkIcon, DenyIcon, RiverDumpIcon]:
    let path = iconPath(name)
    doAssert fileExists(path), "missing " & path
  doAssert fileExists(iconPath("river_treads", "items")),
    "missing river treads item icon"
  doAssert fileExists(iconPath("longflight_brand", "items")),
    "missing longflight brand item icon"
  doAssert fileExists(iconPath("bank_palisade", "items")),
    "missing bank palisade item icon"
  doAssert fileExists(iconPath("hooktrap", "items")),
    "missing hooktrap item icon"
  doAssert InventorySlots == 4
  doAssert ItemMaxRank == 5
  doAssert isPermanent(ShopBoots)
  doAssert isPermanent(ShopLongshot)
  doAssert isPermanent(ShopWall)
  doAssert isPermanent(ShopMine)
  doAssert not isPermanent(ShopFlask)
  doAssert shopPrice(ShopLongshot) == ShopLongshotGold
  doAssert shopPrice(ShopWall) == ShopWallGold
  doAssert shopPrice(ShopMine) == ShopMineGold
  doAssert longshotDamage(100, 0, 10 * WorldScale) == 100
  doAssert longshotDamage(100, 1, 10 * WorldScale) == 110
  doAssert longshotDamage(100, 1, 20 * WorldScale) == 120
  doAssert longshotDamage(100, 2, 10 * WorldScale) > longshotDamage(100, 1, 10 * WorldScale)
  doAssert RuneBigHookDamagePercent == 50
  doAssert bigHookDamage(BaseHookDamage) == 120
  doAssert bigHookDamage(BaseHookDamage) ==
    BaseHookDamage + BaseHookDamage * RuneBigHookDamagePercent div 100
  doAssert bigHookDamage(0) == 0
  doAssert "damage" in shopItemBlurb(ShopBigHook)

echo "Testing published Pudge Wars recordings resolve"
block:
  const Clips = [
    "hook_throw", "hook_latch", "hook_clash", "melee", "splash", "kill",
    "death", "respawn", "upgrade", "ping", "deny", "takeover", "victory",
    "defeat", "voice_laugh", "voice_troll_a", "voice_troll_b", "voice_eat",
    "voice_grunt", "voice_monster"
  ]
  for name in Clips:
    let path = soundPath(name)
    doAssert fileExists(path), "missing " & path
  doAssert fileExists(soundPath("hook_throw").parentDir / "license.md"),
    "missing sounds license"

echo "Testing the content fingerprint is stable"
block:
  doAssert contentHash() != 0
  doAssert contentHash() == contentHash()

echo "test_pw_content: all checks passed"
echo "  contentHash = ", toHex(contentHash())
