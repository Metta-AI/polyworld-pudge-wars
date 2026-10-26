## Externally timed motion must be repeatable across shared-model render passes.
import gltf, vmath
import polyworld/animblend

let file = readGltfFile("examples/pudge_wars/assets/hookem/cowboy_west.glb")
let root = file.root
let first = newClipPlayer(root)
let second = newClipPlayer(root)
let idle = first.clipIndex("ButcherIdle")
let throwClip = first.clipIndex("ButcherHook")
doAssert idle >= 0 and throwClip >= 0

proc pose(): seq[tuple[pos: Vec3, rot: Quat]] =
  for node in root.walkNodes:
    result.add (node.pos, node.rot)

proc matches(a, b: seq[tuple[pos: Vec3, rot: Quat]]): bool =
  if a.len != b.len: return false
  for i in 0..<a.len:
    if length(a[i].pos-b[i].pos) > 0.00001'f32: return false
    let x = a[i].rot
    let y = b[i].rot
    let dot = x.x*y.x+x.y*y.y+x.z*y.z+x.w*y.w
    if abs(abs(dot)-1'f32) > 0.00001'f32: return false
  true

first.sampleClip(idle, 0.3, 0)
let expected = pose()
first.sampleClip(idle, 0.3, 0)
doAssert matches(pose(), expected), "shadow/color passes changed the pose"
second.sampleClip(throwClip, 0.25, 0)
doAssert not matches(pose(), expected), "cast should have its own pose"
first.sampleClip(idle, 0.3, 0)
doAssert matches(pose(), expected), "another instance contaminated the first cowboy"

first.sampleClip(throwClip, 0, 0)
doAssert first.fading, "cast should cross-fade from ready stance"
doAssert matches(pose(), expected), "transition must begin at outgoing pose"
first.sampleClip(throwClip, 0.06, 0.06)
let halfway = pose()
first.sampleClip(throwClip, 0.06, 0)
doAssert matches(pose(), halfway), "second render pass advanced the cross-fade"
first.sampleClip(throwClip, 0.15, 0.09)
doAssert not first.fading
second.sampleClip(throwClip, 0.15, 0)
doAssert not matches(pose(), halfway), "cast did not advance"
let direct = pose()
first.sampleClip(throwClip, 0.15, 0)
doAssert matches(pose(), direct), "completed fade must match simulation-timed cast"
echo "test_hookem_motion: all checks passed"
