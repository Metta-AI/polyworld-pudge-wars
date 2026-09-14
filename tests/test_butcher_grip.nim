## Check the actual rendered socket and blade geometry, not a second copy
## of the grip math in Python. CPU-only GLB posing; no window/GL context.
import std/[math, strformat], gltf, vmath,
  polyworld/characters,
  ../examples/pudge_wars/[butcherknife, content]

proc equipmentAt(model: CharacterModel, clip: string, phase, yaw: float32): Mat4 =
  let root = model.file.root
  let index = model.clipIndex(clip)
  root.activeClips = @[index]
  root.animTime = phase * model.clipDuration(index)
  root.updateAnimation(0)
  butcherKnifeTransform(model.characterJointTransform("L_Hand",vec3(0),yaw))

for team in Team:
  let model = loadCharacterModel(PudgeSpecs[team].modelPath,1)
  for yaw in [0'f32, PI.float32/2, PI.float32, -PI.float32/2]:
    echo &"Testing edge-down grip: {team}, yaw {yaw:.2f}"
    let rest = model.equipmentAt("ButcherIdle",0,yaw)
    let edgeDirection = normalize(rest*vec3(1,0,0)-rest*vec3(0))
    doAssert edgeDirection.y < -0.9'f32,
      "idle grip must put the sharpened edge below the spine, not the flat face"
    for knife in ButcherKnife:
      for row in knifeProfile(knife):
        for x in [row.left,row.right]:
          doAssert (rest*vec3(x,row.y,0)).y > -0.005'f32,
            "edge-down grip must not bury the blade in the floor"
    for clip in ["ButcherChop", "ButcherSlash"]:
      var worstFlat = 0'f32
      var leastEdge = 1'f32
      # The full committed stroke AND follow-through, including the late
      # cut that the original two-timestamp regression check missed.
      for frame in 26..60:
        let phase = frame.float32/100
        let current = model.equipmentAt(clip,phase,yaw)
        let before = model.equipmentAt(clip,phase-0.002'f32,yaw)
        let after = model.equipmentAt(clip,phase+0.002'f32,yaw)
        let normal = normalize(current*vec3(0,0,1)-current*vec3(0))
        # Both long sections of the actual cleaver cutting edge.
        let rows = knifeProfile(SlaughterCleaver)
        for i in 1..2:
          let a = rows[i]
          let b = rows[i+1]
          let point = vec3((a.right+b.right)*0.5'f32,(a.y+b.y)*0.5'f32,0)
          let velocity = normalize(after*point-before*point)
          let localEdge = vec3(b.y-a.y,a.right-b.right,0)
          let edge = normalize(current*localEdge-current*vec3(0))
          worstFlat = max(worstFlat,abs(dot(normal,velocity)))
          leastEdge = min(leastEdge,dot(edge,velocity))
          doAssert abs(dot(normal,velocity)) < 0.40'f32,
            &"{clip} phase {phase:.2f}: broad face leads the stroke ({abs(dot(normal,velocity)):.3f})"
          doAssert dot(edge,velocity) > 0.30'f32,
            &"{clip} phase {phase:.2f}: spine leads instead of the cutting edge"
          if clip == "ButcherChop" and frame >= 42:
            doAssert edge.y < -0.60'f32,
              "the cleaver's sharpened edge must point down through impact"
      echo &"  {clip}: flat-leading <= {worstFlat:.3f}, edge-leading >= {leastEdge:.3f}"
echo "test_butcher_grip: all checks passed"
