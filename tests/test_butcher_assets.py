"""Validate the delivered GLBs, including skin contact after interpolation.

Run: python3 -m unittest discover -s tests -p test_butcher_assets.py
Requires the sibling art checkout and numpy, like scripts/build_butcher.py.
"""
import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from build_butcher import ASSETS, CLIPS, Glb, Rig, rotation


def sample(glb, rig, animation, t):
    rig.reset()
    for channel in animation["channels"]:
        sampler = animation["samplers"][channel["sampler"]]
        times = glb.read(sampler["input"]).ravel()
        values = glb.read(sampler["output"])
        i = min(max(int(np.searchsorted(times, t, side="right"))-1, 0), len(times)-2)
        alpha = np.clip((t-times[i])/(times[i+1]-times[i]), 0, 1)
        a, b = values[i].astype(float), values[i+1].astype(float)
        node = channel["target"]["node"]
        if channel["target"]["path"] == "rotation":
            dot = np.dot(a,b)
            if dot < 0:
                b, dot = -b, -dot
            angle = np.arccos(np.clip(dot,-1,1))
            if angle > 1e-4:
                value = (np.sin((1-alpha)*angle)*a+np.sin(alpha*angle)*b)/np.sin(angle)
            else:
                value = a*(1-alpha)+b*alpha
            rig.local[node][:3,:3] = rotation(value)
        else:
            rig.local[node][:3,3] = a*(1-alpha)+b*alpha


class ButcherAssets(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.west = Glb(ASSETS/"butcher_game.glb")
        cls.east = Glb(ASSETS/"butcher_game_east.glb")
        cls.source = Glb(ASSETS/"butcher.glb")

    def test_authored_mesh_and_skin_preserved(self):
        for glb in (self.west, self.east):
            mesh = glb.doc["meshes"][0]["primitives"][0]
            original = self.source.doc["meshes"][0]["primitives"][0]
            for attribute in ("POSITION", "NORMAL", "TEXCOORD_0", "JOINTS_0", "WEIGHTS_0"):
                np.testing.assert_array_equal(glb.read(mesh["attributes"][attribute]),
                                              self.source.read(original["attributes"][attribute]))
            np.testing.assert_array_equal(glb.read(mesh["indices"]), self.source.read(original["indices"]))
            self.assertEqual(len(glb.doc["meshes"]), 1, "studio floor must not be in the player model")

    def test_teams_share_clips_but_have_distinct_paint(self):
        self.assertEqual(self.west.doc["nodes"], self.east.doc["nodes"])
        for west, east in zip(self.west.doc["animations"], self.east.doc["animations"]):
            self.assertEqual(west["name"], east["name"])
            for a, b in zip(west["samplers"], east["samplers"]):
                for key in ("input", "output"):
                    np.testing.assert_array_equal(self.west.read(a[key]),self.east.read(b[key]))
        def texture(glb):
            v = glb.doc["bufferViews"][glb.doc["images"][0]["bufferView"]]
            return bytes(glb.binary[v["byteOffset"]:v["byteOffset"]+v["byteLength"]])
        self.assertNotEqual(texture(self.west), texture(self.east))
        self.assertEqual(texture(self.west), texture(self.source))

    def test_clips_timing_unit_quaternions_and_loop_seams(self):
        self.assertEqual([a["name"] for a in self.west.doc["animations"]], [c[0] for c in CLIPS])
        for animation, (_, duration, loop, _) in zip(self.west.doc["animations"], CLIPS):
            with self.subTest(clip=animation["name"]):
                for channel in animation["channels"]:
                    sampler = animation["samplers"][channel["sampler"]]
                    times = self.west.read(sampler["input"]).ravel()
                    values = self.west.read(sampler["output"])
                    self.assertTrue(np.all(np.diff(times)>0))
                    self.assertAlmostEqual(times[0], 0)
                    self.assertAlmostEqual(times[-1], duration, places=6)
                    self.assertTrue(np.isfinite(values).all())
                    self.assertEqual(len(values), len(times))
                    if channel["target"]["path"] == "rotation":
                        np.testing.assert_allclose(np.linalg.norm(values,axis=1),1,atol=1e-6)
                        if loop:
                            self.assertAlmostEqual(abs(np.dot(values[0],values[-1])),1,places=5)
                    elif loop:
                        np.testing.assert_allclose(values[0],values[-1],atol=1e-6)
        hook = self.west.doc["animations"][2]
        self.assertAlmostEqual(hook["extras"]["releaseTime"],9/32)
        self.assertAlmostEqual(CLIPS[2][1],19/32)

    def test_boot_contact_in_playback_and_death_hold(self):
        rig = Rig(self.west)
        for animation, (_, duration, _, _) in zip(self.west.doc["animations"], CLIPS):
            for t in np.linspace(0,duration,37):
                with self.subTest(clip=animation["name"],time=t):
                    sample(self.west,rig,animation,t)
                    vertices = rig.skinned()
                    self.assertTrue(np.isfinite(vertices).all())
                    # Also checks between baked keyframes, where rotation
                    # interpolation can dip slightly below the sampled floor.
                    self.assertGreater(float(vertices[:,1].min()),-.005)
                    self.assertLess(float(vertices[:,1].min()),.005)
                    self.assertLess(float(np.ptp(vertices[:,0])),1.8)
        death = self.west.doc["animations"][3]
        sample(self.west,rig,death,1.1)
        settled = rig.skinned()
        sample(self.west,rig,death,1.35)
        np.testing.assert_allclose(rig.skinned(),settled,atol=1e-5)

    def test_melee_has_large_arm_arc_and_returns_to_rest(self):
        rig = Rig(self.west)
        hand = rig.names["L_Hand"]
        # Full weapon orientation is tested with the real Nim socket and
        # blade geometry in test_butcher_grip.nim, not duplicated grip math.
        for name in ("ButcherChop", "ButcherSlash"):
            animation = next(a for a in self.west.doc["animations"] if a["name"] == name)
            with self.subTest(clip=name):
                hands = []
                for t in np.linspace(0,19/32,61):
                    sample(self.west,rig,animation,t)
                    world = rig.world()[hand]
                    hands.append(world[:3,3].copy())
                self.assertGreater(np.ptp(np.array(hands)[:,1]), .25)
                np.testing.assert_allclose(hands[0],hands[-1],atol=1e-5)


if __name__ == "__main__":
    unittest.main()
