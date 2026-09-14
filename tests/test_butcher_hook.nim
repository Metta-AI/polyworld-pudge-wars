## Held meat hook is a smaller horizontal C in the right hand.
import std/[math, strformat], gltf, vmath,
  polyworld/characters,
  ../examples/pudge_wars/[butcherhook, content]

const HeldRadius = BaseHookRadius.float32 / WorldScale.float32 * HeldHookVisualScale

proc pose(model: CharacterModel, clip: string, phase: float32) =
  let root = model.file.root
  let index = model.clipIndex(clip)
  root.activeClips = @[index]
  root.animTime = phase * model.clipDuration(index)
  root.updateAnimation(0)

proc heldHook(model: CharacterModel, clip: string, phase, yaw: float32): Mat4 =
  model.pose(clip, phase)
  butcherHeldHookTransform(
    model.characterJointTransform("R_Hand", vec3(0), yaw), yaw, HeldRadius)

for team in Team:
  let model = loadCharacterModel(PudgeSpecs[team].modelPath, PudgeSpecs[team].targetHeight)
  for yaw in [0'f32, PI.float32 / 2, PI.float32, -PI.float32 / 2]:
    echo &"Testing held hook: {team}, yaw {yaw:.2f}"
    let rest = model.heldHook("ButcherIdle", 0, yaw)
    let eye = rest * HookEye
    let tip = rest * HookTip
    let hang = tip - eye
    doAssert abs(hang.y) < 0.20'f32,
      "held hook must lie in the same horizontal plane as a thrown hook"
    doAssert abs(length(hang) - HeldRadius * length(HookTip - HookEye)) < 0.08'f32,
      "held hook must use the carried visual scale"
    doAssert length(hang) < BaseHookRadius.float32 / WorldScale.float32 *
        length(HookTip - HookEye) * 0.9'f32,
      "carried hook must be smaller than the thrown latch disk"
    doAssert eye.y > 0.80'f32 and tip.y > 0.80'f32,
      "horizontal hook must stay off the floor"
    let knifeHand = model.characterJointTransform("L_Hand", vec3(0), yaw) * vec3(0)
    let hookHand = model.characterJointTransform("R_Hand", vec3(0), yaw) * vec3(0)
    doAssert length(eye - knifeHand) > length(eye - hookHand),
      "the held hook must sit in R_Hand, opposite the cleaver"
    for clip in ["ButcherIdle", "ButcherRun", "ButcherWalk"]:
      var lowest = 10'f32
      for frame in 0..8:
        let posed = model.heldHook(clip, frame.float32 / 8, yaw)
        lowest = min(lowest, min((posed * HookEye).y, (posed * HookTip).y))
      doAssert lowest > 0.50'f32, &"{clip} hook buried in the floor ({lowest:.3f})"
echo "test_butcher_hook: all checks passed"
