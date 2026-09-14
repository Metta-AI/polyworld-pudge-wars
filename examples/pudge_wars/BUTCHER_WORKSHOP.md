# Butcher workshop

The default roster uses the customized butcher on both banks: the original
red/purple west paint and the blue east paint. The authored mesh, UVs,
texture, and skin weights are preserved. The studio floor is excluded.

## Open the independent viewer

From the repository root:

```sh
nim c -d:release -o:char_viewer examples/pudge_wars/char_viewer.nim
./char_viewer
```

The workshop opens with a looping cleaver chop. Select a motion from the
dropdown on the left. Space pauses; left/right arrows step 1/60 s.
Scrubbing pauses playback. Change speed to inspect foot contact. Drag to
orbit, right-drag or shift-drag to pan, and scroll to zoom. W/E/B choose a
team or both. F3 hides the panel, T switches toon/PBR, and R restarts.
The Floor, Bones, and Turntable switches help inspect the pose from any angle.

## Butcher blades

The default in-game butcher carries a **Slaughter cleaver** in the left hand,
with team-coloured binding, a broad honed edge, leather grip, brass furniture,
and a real hanging hole through the steel. Melee now uses a dedicated downward
chop instead of reusing the hook throw. Hook/grapple casts retain their own
animation. The weapon follows the full animated wrist transform.

The grip holds the sharp edge below the spine even at rest. The chop keeps
its blade plane aligned with the downward stroke, rather than twisting flat
late in the swing; the diagonal Slash uses the same corrected grip. The
blade projects forward enough to keep its lower edge above the floor.

Use the blade dropdown or **K** to cycle three versions:

- **Slaughter cleaver**: heavy, square-ended butcher's slab; the game default.
- **Hooked skinner**: narrower swept belly and a long, hooked gutting point.
- **Bone splitter**: oversized curved chopping blade with a jagged spine.

**C** selects Chop; **V** selects the alternate cross-body Slash. Both loop
in the workshop and use the existing 19-tick melee cadence. The forearm rolls
the sharpened edge into the cut, with planted feet and torso-led recovery.
Slash is a preview alternative; the live game uses Chop.

Enable **Compare all three blades** to see them side by side in motion.
The **Character / Knife / Hook** controls switch between equipped characters
and isolated prop inspection. Blade selection is a workshop preview, not a
saved loadout. The original authored mesh and skin are unchanged.

```sh
# Open all three variants together, on the character or as isolated props.
BUTCHER_COMPARE_KNIVES=1 ./char_viewer
BUTCHER_COMPARE_KNIVES=1 BUTCHER_KNIFE_ONLY=1 ./char_viewer
# 0 = cleaver, 1 = skinner, 2 = splitter (full display names also work).
BUTCHER_KNIFE=2 BUTCHER_CLIP=ButcherSlash ./char_viewer
```

Select Hook to preview the weighted sidearm cast with the weapon and chain.
The free hand braces the chain while the throwing shoulder drives forward.
Use the “Hook” prop control for a close-up of the hook alone; orbit to inspect
the curved iron blade, sharpened inward tip, rear eyelet, and alternating
chain links. The shank wrap carries the team color.

“East: compare old experiment” loads the old blue model on the right.
Choose any previous clip from the dropdown; both sides play at the same
normalized phase, so different clip lengths can be compared. The old rig's
vertical offset is intentionally visible against the floor reference.

## Clips

| Clip | Duration | Behavior |
| --- | --- | --- |
| ButcherIdle | 3.20 s | Visible chest breathing and shoulder sway, planted boots |
| ButcherRun | 0.72 s | Longer, heavy stride with broad arm swings and higher boot clearance |
| ButcherHook | 0.594 s | Weighted sidearm windup, chain-hand brace, release at 0.28125 s, recovery |
| ButcherDeath | 1.35 s | Deeper buckle, fall backward, impact rebound, settle and hold |
| ButcherVictory | 2.40 s | Chest-up laugh and raised fist pump |
| ButcherWalk | 1.12 s | Deliberate patrol with clear steps and arm swings |
| ButcherBackpedal | 0.90 s | Guarded backward steps |
| ButcherStrafeLeft / Right | 0.90 s | Lateral steps while facing forward |
| ButcherChop | 0.594 s | High cleaver windup, edge-first downward cut, heavy recovery |
| ButcherSlash | 0.594 s | Cross-body cut with a hip-led follow-through |

The first five retain their existing clip indices; Chop is selected by a
cosmetic melee subtype without changing the simulation's attack state/hash.
Walk/backpedal/strafe and Slash are preview alternatives.
Hook and death play once by default in the workshop. Other clips loop.
All motion is in place; simulation owns world movement. The viewer's speed
control is for inspection and does not change the game defaults.

The second motion pass increases amplitude while keeping the same cadence
and cast timing. Run arm swing is 26 degrees (previously 12); run stride is
0.255 model units (previously 0.19), and swing-foot lift is 0.06 (previously
0.036). Torso roll remains limited so the larger gestures keep a stable stance.

## Assets and rebuild

Assets live in `../polyworld_data/characters/butcher/`:

- `butcher_game.glb`, `butcher_game_east.glb`: production models, eleven clips each.
- Matching `*.profile.png`: roster portraits.
- `butcher_motion.json`: clip metadata and measured floor contact.
- `butcher.blend`: unchanged authored source, identical to the supplied file.
- `butcher_authored.glb`: unchanged supplied export, including its studio floor.
- `butcher.glb`, `butcher_east.glb`: preserved earlier rig/retarget experiments.

The production GLBs can be imported into Blender to edit the baked actions.
The original `.blend` remains the unanimated source; it is not overwritten.

The bespoke animation builder uses two-bone leg IK, world-space body and
arm poses, and actual skinned vertices to correct sole contact. It samples
at approximately 60 Hz and explicitly closes each looping pose. Hook timing
matches `HookWindupTicks = 9`, `AttackTicks = 19`, and `TickRate = 32`.

The weapons are procedural geometry shared by the game and workshop in
`butcherhook.nim` and `butcherknife.nim`, not embedded in the character GLBs.
No additional textures or downloaded models are required. In-game chains attach
to the animated guide hand; the hook flies without the old spinning-star
effect. Collision radius, projectile speed, cast timing, and damage are
unchanged. The workshop shows a short illustrative out-and-back flight,
not a simulation of the full game trajectory.
Melee damage, reach, cooldown, replay hashes, and hit adjudication are also
unchanged: the new chop is presentation, not a new combat rule.

```sh
# Requires numpy in the selected Python environment; no external API calls.
python3 scripts/build_butcher.py
python3 -m unittest discover -s tests -p test_butcher_assets.py
nim r -d:release tests/test_butcher_grip.nim
nim r tests/test_pw_content.nim
```

Use `--assets PATH` to rebuild against a different art checkout. Rebuilding
writes only `butcher_game*` and `butcher_motion.json`; it preserves the input
rig, previous animation experiments, and authored Blender source.
The browser asset manifest packages the new production models and portraits.

For reproducible captures:

```sh
nim c -d:release -d:takeScreenshot -o:tmp/butcher_shot examples/pudge_wars/char_viewer.nim
BUTCHER_CLIP=ButcherHook BUTCHER_TIME=0.28125 SCREENSHOT_PATH=tmp/hook.png ./tmp/butcher_shot
BUTCHER_WEAPON_ONLY=1 SCREENSHOT_PATH=tmp/hook_prop.png ./tmp/butcher_shot
BUTCHER_COMPARE_KNIVES=1 BUTCHER_KNIFE_ONLY=1 SCREENSHOT_PATH=tmp/blades.png ./tmp/butcher_shot
BUTCHER_CLIP=ButcherRun BUTCHER_CLEAN=1 BUTCHER_SOLO=1 \
  BUTCHER_CAPTURE_DIR=tmp/run_frames BUTCHER_CAPTURE_FRAMES=120 ./tmp/butcher_shot
ffmpeg -framerate 60 -i tmp/run_frames/frame%04d.png -c:v libx264 -pix_fmt yuv420p tmp/butcher_run.mp4
```

`BUTCHER_DISTANCE` overrides the camera distance for captures. Solo mode now
frames the raised cleaver as well as the feet. Python asset tests check
melee arc amplitude, skin preservation, team paint, floor contact, and clip
seams. `test_butcher_grip.nim` uses the actual renderer attachment and blade
profiles: both paints, four facings, idle edge-down/floor clearance, and
35 samples across each cut and follow-through. It catches late flat-side
slaps that a check of only two early timestamps would miss.

Useful feedback includes the clip, timestamp, camera angle, and whether the
weight, arm swing, or foot placement feels wrong. These are custom animations
for an exaggerated, short-legged character, not motion capture.
