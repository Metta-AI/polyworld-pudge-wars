#!/usr/bin/env python3
"""Bake bespoke butcher motion onto the existing skin. Requires numpy.

The authored mesh/UVs/weights are preserved. No service calls or re-rigging.
Run from anywhere: python3 scripts/build_butcher.py
"""

import argparse
import copy
import json
import math
import struct
import shutil
from pathlib import Path

import numpy as np

ASSETS = Path(__file__).resolve().parents[2] / "polyworld_data/characters/butcher"


def unit(v):
    return v / max(np.linalg.norm(v), 1e-12)


def rotation(q):
    x, y, z, w = unit(np.array(q, dtype=float))
    return np.array([
        [1 - 2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
        [2*(x*y+z*w), 1 - 2*(x*x+z*z), 2*(y*z-x*w)],
        [2*(x*z-y*w), 2*(y*z+x*w), 1 - 2*(x*x+y*y)],
    ])


def quaternion(m):
    # Eigen formulation remains stable near 180 degrees.
    k = np.array([
        [m[0,0]-m[1,1]-m[2,2], m[1,0]+m[0,1], m[2,0]+m[0,2], m[2,1]-m[1,2]],
        [m[1,0]+m[0,1], m[1,1]-m[0,0]-m[2,2], m[2,1]+m[1,2], m[0,2]-m[2,0]],
        [m[2,0]+m[0,2], m[2,1]+m[1,2], m[2,2]-m[0,0]-m[1,1], m[1,0]-m[0,1]],
        [m[2,1]-m[1,2], m[0,2]-m[2,0], m[1,0]-m[0,1], np.trace(m)],
    ]) / 3
    _, vectors = np.linalg.eigh(k)
    return vectors[:, -1]


def axis_rotation(axis, degrees):
    axis = unit(np.array(axis, dtype=float))
    angle = math.radians(degrees) / 2
    return rotation([*(axis * math.sin(angle)), math.cos(angle)])


def between(a, b):
    a, b = unit(a), unit(b)
    dot = np.clip(np.dot(a, b), -1, 1)
    if dot < -0.99999:
        return axis_rotation(np.cross(a, [1, 0, 0] if abs(a[0]) < .9 else [0, 1, 0]), 180)
    return rotation([*np.cross(a, b), 1 + dot])


class Glb:
    def __init__(self, path):
        data = Path(path).read_bytes()
        assert data[:4] == b"glTF"
        length = struct.unpack_from("<I", data, 12)[0]
        self.doc = json.loads(data[20:20+length])
        start = 20 + length
        size = struct.unpack_from("<I", data, start)[0]
        self.binary = bytearray(data[start+8:start+8+size])

    def read(self, index):
        a = self.doc["accessors"][index]
        v = self.doc["bufferViews"][a["bufferView"]]
        dtype = {5121: "u1", 5123: "<u2", 5125: "<u4", 5126: "<f4"}[a["componentType"]]
        width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[a["type"]]
        itemsize = np.dtype(dtype).itemsize
        return np.ndarray((a["count"], width), dtype=dtype, buffer=self.binary,
                          offset=v.get("byteOffset", 0)+a.get("byteOffset", 0),
                          strides=(v.get("byteStride", itemsize*width), itemsize)).copy()

    def buffer(self, data):
        self.binary.extend(b"\0" * (-len(self.binary) % 4))
        index = len(self.doc["bufferViews"])
        self.doc["bufferViews"].append({"buffer": 0, "byteOffset": len(self.binary), "byteLength": len(data)})
        self.binary.extend(data)
        return index

    def accessor(self, values, kind):
        values = np.asarray(values, dtype="<f4")
        index = len(self.doc["accessors"])
        self.doc["accessors"].append({
            "bufferView": self.buffer(values.tobytes()), "componentType": 5126,
            "count": len(values), "type": kind,
            "min": values.reshape(len(values), -1).min(axis=0).tolist(),
            "max": values.reshape(len(values), -1).max(axis=0).tolist(),
        })
        return index

    def compact(self):
        # Keep only accessors referenced by mesh, skin and current clips.
        refs = []
        for mesh in self.doc["meshes"]:
            for p in mesh["primitives"]:
                refs.extend((p["attributes"], key) for key in p["attributes"])
                if "indices" in p:
                    refs.append((p, "indices"))
        refs.extend((skin, "inverseBindMatrices") for skin in self.doc["skins"])
        for a in self.doc.get("animations", []):
            for s in a["samplers"]:
                refs.extend([(s, "input"), (s, "output")])
        old_accessors = self.doc["accessors"]
        mapping = {old: new for new, old in enumerate(sorted({obj[key] for obj, key in refs}))}
        self.doc["accessors"] = [copy.deepcopy(old_accessors[old]) for old in mapping]
        for obj, key in refs:
            obj[key] = mapping[obj[key]]
        view_refs = [(a, "bufferView") for a in self.doc["accessors"]]
        view_refs += [(img, "bufferView") for img in self.doc["images"]]
        old_views, old_binary = self.doc["bufferViews"], self.binary
        self.doc["bufferViews"], self.binary = [], bytearray()
        mapping = {}
        for old in sorted({obj[key] for obj, key in view_refs}):
            v = old_views[old]
            start = v.get("byteOffset", 0)
            mapping[old] = self.buffer(old_binary[start:start+v["byteLength"]])
            for key in ("byteStride", "target"):
                if key in v:
                    self.doc["bufferViews"][-1][key] = v[key]
        for obj, key in view_refs:
            obj[key] = mapping[obj[key]]

    def write(self, path):
        self.binary.extend(b"\0" * (-len(self.binary) % 4))
        self.doc["buffers"] = [{"byteLength": len(self.binary)}]
        data = json.dumps(self.doc, separators=(",", ":")).encode()
        data += b" " * (-len(data) % 4)
        Path(path).write_bytes(b"glTF" + struct.pack("<II", 2, 28+len(data)+len(self.binary))
                              + struct.pack("<I", len(data)) + b"JSON" + data
                              + struct.pack("<I", len(self.binary)) + b"BIN\0" + self.binary)


class Rig:
    def __init__(self, glb):
        self.glb = glb
        self.nodes = glb.doc["nodes"]
        self.names = {n["name"]: i for i, n in enumerate(self.nodes)}
        self.parents = {c: i for i, n in enumerate(self.nodes) for c in n.get("children", [])}
        self.base = []
        for n in self.nodes:
            m = np.eye(4)
            m[:3, :3] = rotation(n.get("rotation", [0, 0, 0, 1]))
            m[:3, 3] = n.get("translation", [0, 0, 0])
            self.base.append(m)
        self.reset()
        self.rest = [m.copy() for m in self.world()]
        skin = glb.doc["skins"][0]
        self.joints = skin["joints"]
        self.inverse_bind = glb.read(skin["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
        p = glb.doc["meshes"][0]["primitives"][0]["attributes"]
        self.vertices = np.c_[glb.read(p["POSITION"]), np.ones(len(glb.read(p["POSITION"])))]
        self.weights, self.indices = glb.read(p["WEIGHTS_0"]), glb.read(p["JOINTS_0"])
        vertices = self.skinned()
        self.floor = float(vertices[:, 1].min())
        self.height = float(np.ptp(vertices[:, 1]))

    def reset(self):
        self.local = [m.copy() for m in self.base]

    def world(self):
        result = [None] * len(self.nodes)
        def visit(i):
            if result[i] is None:
                result[i] = (visit(self.parents[i]) @ self.local[i]) if i in self.parents else self.local[i]
            return result[i]
        for i in range(len(result)):
            visit(i)
        return result

    def position(self, name, rest=False):
        return (self.rest if rest else self.world())[self.names[name]][:3, 3].copy()

    def turn(self, name, axis, degrees):
        i = self.names[name]
        p = self.world()[self.parents[i]][:3, :3] if i in self.parents else np.eye(3)
        self.local[i][:3, :3] = p.T @ axis_rotation(axis, degrees) @ p @ self.local[i][:3, :3]

    def move(self, name, offset):
        i = self.names[name]
        p = self.world()[self.parents[i]][:3, :3] if i in self.parents else np.eye(3)
        self.local[i][:3, 3] += p.T @ np.array(offset)

    def aim(self, name, child, target):
        i, c = self.names[name], self.names[child]
        w = self.world()
        delta = between(w[c][:3, 3]-w[i][:3, 3], target-w[i][:3, 3])
        p = w[self.parents[i]][:3, :3]
        self.local[i][:3, :3] = p.T @ delta @ w[i][:3, :3]

    def leg(self, side, target, pitch=0):
        thigh, calf, foot = [side + "_" + part for part in ("Thigh", "Calf", "Foot")]
        hip = self.position(thigh)
        upper = np.linalg.norm(self.position(calf, True)-self.position(thigh, True))
        lower = np.linalg.norm(self.position(foot, True)-self.position(calf, True))
        direction = unit(target-hip)
        d = np.clip(np.linalg.norm(target-hip), abs(upper-lower)+.0001, upper+lower-.0001)
        along = (upper*upper - lower*lower + d*d) / (2*d)
        pole = np.array([0., 0., 1.])
        bend = unit(pole-direction*np.dot(pole, direction))
        knee = hip + direction*along + bend*math.sqrt(max(upper*upper-along*along, 0))
        self.aim(thigh, calf, knee)
        self.aim(calf, foot, target)
        w = self.world()
        i = self.names[foot]
        self.local[i][:3, :3] = w[self.parents[i]][:3, :3].T @ axis_rotation([1,0,0], pitch) @ self.rest[i][:3,:3]

    def skinned(self):
        w = self.world()
        matrices = np.array([w[i] for i in self.joints]) @ self.inverse_bind
        blended = (matrices[self.indices] * self.weights[:, :, None, None]).sum(axis=1)
        return np.einsum("nij,nj->ni", blended, self.vertices)[:, :3]


def smooth(t):
    t = np.clip(t, 0, 1)
    return t*t*(3-2*t)


def envelope(t, keys):
    for (a, x), (b, y) in zip(keys, keys[1:]):
        if t <= b:
            return x + (y-x)*smooth((t-a)/(b-a))
    return keys[-1][1]


CLIPS = [
    ("ButcherIdle", 3.2, True, "Visible chest breathing and shoulder sway; boots planted."),
    ("ButcherRun", .72, True, "Heavy stride, high boot clearance and broad arm counter-swing."),
    ("ButcherHook", 19/32, False, "Weighted sidearm cast; left hand braces the chain; release at 9/32 seconds."),
    ("ButcherDeath", 1.35, False, "Knees buckle, weight tips backward, settle and hold."),
    ("ButcherVictory", 2.4, True, "Chest-up laugh and a raised fist pump."),
    ("ButcherWalk", 1.12, True, "Slow patrol with longer double support."),
    ("ButcherBackpedal", .9, True, "Guarded backward steps."),
    ("ButcherStrafeLeft", .9, True, "Short lateral steps, facing the target."),
    ("ButcherStrafeRight", .9, True, "Short lateral steps, facing the target."),
    ("ButcherChop", 19/32, False, "Left-hand cleaver: high windup, committed downward cut, weighted recovery."),
    ("ButcherSlash", 19/32, False, "Left-hand cross-body slash; hips lead and blade follows through."),
]


def pose(rig, name, t, duration):
    rig.reset()
    phase = t/duration
    wave = math.sin(math.tau*phase)
    foot_targets = {side: rig.position(side+"_Foot", True) for side in ("L", "R")}
    pitches = {"L": 0, "R": 0}
    if name in ("ButcherRun", "ButcherWalk", "ButcherBackpedal", "ButcherStrafeLeft", "ButcherStrafeRight"):
        running = name == "ButcherRun"
        # Push the readable silhouette (arms and boots) harder than torso
        # roll: the broad character should still feel balanced and sturdy.
        stride = .255 if running else .19
        stance = .57 if running else .66
        direction = np.array([0., 0., 1.])
        if name == "ButcherBackpedal": direction = -direction
        if name == "ButcherStrafeLeft": direction = np.array([1., 0., 0.])
        if name == "ButcherStrafeRight": direction = np.array([-1., 0., 0.])
        rig.move("Hip", [wave*.016, -.04 + .012*math.cos(2*math.tau*phase), .012])
        rig.turn("Waist", [1,0,0], 6 if running else 3)
        rig.turn("Waist", [0,0,1], 3.4*wave)
        rig.turn("Spine01", [0,1,0], 6*wave)
        rig.turn("Head", [0,0,1], -2.0*wave)
        for side, offset, sign in (("L", 0, 1), ("R", .5, -1)):
            p = (phase+offset) % 1
            if p < stance:
                travel = .5 - p/stance
                lift = 0
            else:
                swing = (p-stance)/(1-stance)
                travel = -.5+smooth(swing)
                lift = (.06 if running else .042)*math.sin(math.pi*swing)**2
                pitches[side] = -14*math.sin(math.tau*swing)
            foot_targets[side] += direction*stride*travel + np.array([0, lift, 0])
            rig.turn(side+"_Upperarm", [1,0,0], sign*wave*(26 if running else 17))
            rig.turn(side+"_Forearm", [1,0,0], -10-sign*wave*5)
            rig.turn(side+"_Upperarm", [0,0,1], sign*5)
    elif name == "ButcherIdle":
        breath = (1-math.cos(math.tau*phase))*.5
        rig.turn("Waist", [0,0,1], 1.5*wave)
        rig.turn("Spine01", [1,0,0], -4.2*breath)
        rig.turn("Spine02", [1,0,0], -1.8*breath)
        rig.turn("Head", [1,0,0], 3.0*breath)
        rig.turn("Head", [0,0,1], -1.0*wave)
        for side, sign in (("L",1), ("R",-1)):
            rig.turn(side+"_Upperarm", [0,0,1], sign*2.6*breath)
            rig.turn(side+"_Forearm", [1,0,0], -3*breath)
    elif name == "ButcherHook":
        # The anticipation peaks before the deterministic 9/32 s release.
        wind = envelope(t, [(0,0),(.16,1),(.28125,0),(duration,0)])
        drive = envelope(t, [(0,0),(.13,0),(.255,1),(.34,.8),(duration,0)])
        throw = envelope(t, [(0,0),(.17,0),(.28125,1),(.37,.9),(duration,0)])
        brace = envelope(t, [(0,0),(.14,1),(.38,1),(duration,0)])
        # Weight and torso lead; the elbow opens at release. The free hand
        # gathers the chain at the belly instead of flinging backward.
        rig.move("Hip", [0, -.03*wind-.018*drive, -.035*wind+.047*drive])
        rig.turn("Waist", [0,1,0], -22*wind+23*drive)
        rig.turn("Spine01", [1,0,0], -6*wind+11*drive)
        rig.turn("Head", [0,1,0], 15*wind-15*drive)
        rig.turn("R_Upperarm", [1,0,0], 38*wind-68*throw)
        rig.turn("R_Upperarm", [0,0,1], -16*wind-24*throw)
        rig.turn("R_Forearm", [1,0,0], -52*wind-4*throw)
        rig.turn("L_Upperarm", [1,0,0], -30*brace)
        rig.turn("L_Upperarm", [0,0,1], -13*brace)
        rig.turn("L_Forearm", [1,0,0], -58*brace)
    elif name in ("ButcherChop", "ButcherSlash"):
        # Same 19-tick attack cadence as melee. Anticipation and follow-
        # through have distinct beats; feet stay anchored under the torso.
        wind = envelope(phase, [(0,0),(.23,1),(.43,0),(1,0)])
        cut = envelope(phase, [(0,0),(.24,0),(.49,1),(.64,.88),(1,0)])
        lift = envelope(phase, [(0,0),(.24,1),(.49,.32),(.65,.18),(1,0)])
        slash = name == "ButcherSlash"
        rig.move("Hip", [-.025*wind+.026*cut, -.025*wind-.035*cut, -.025*wind+.055*cut])
        rig.turn("Waist", [0,1,0], (12 if slash else 8)*wind-(16 if slash else 10)*cut)
        rig.turn("Spine01", [1,0,0], -8*wind+16*cut)
        rig.turn("Head", [0,1,0], -18*wind+22*cut)
        rig.turn("L_Upperarm", [1,0,0], -(104 if slash else 132)*lift)
        rig.turn("L_Upperarm", [0,0,1], (18 if slash else 6)*wind-(18 if slash else 6)*cut)
        rig.turn("L_Forearm", [1,0,0], -40*wind-10*cut)
        rig.turn("L_Hand", [0,0,1], -4*wind+4*cut)
        # The grip itself now hangs edge-down. Keep a chop in a mostly
        # vertical plane instead of rolling its broad face into the late
        # downswing. A small pronation adjustment tracks the elbow's arc.
        roll = envelope(phase, [(0,0),(.23,12),(.35,0),(.5,-6),(.64,-2),(1,0)])
        if slash:
            roll = envelope(phase, [(0,0),(.23,18),(.35,0),(.5,-14),(.64,-7),(1,0)])
        forearm_axis = rig.position("L_Hand")-rig.position("L_Forearm")
        rig.turn("L_Forearm", forearm_axis, roll*.75)
        rig.turn("L_Hand", forearm_axis, roll*.25)
        # Hook hand balances the torso, without imitating a second punch.
        rig.turn("R_Upperarm", [1,0,0], -19*wind+15*cut)
        rig.turn("R_Upperarm", [0,0,1], -12*wind-15*cut)
        rig.turn("R_Forearm", [1,0,0], -26*wind-14*cut)
    elif name == "ButcherVictory":
        pump = envelope(phase, [(0,0),(.18,1),(.3,.72),(.42,1),(.7,.7),(1,0)])
        rig.turn("Spine01", [1,0,0], -9*pump)
        rig.turn("Head", [1,0,0], -7*pump+3*math.sin(math.tau*phase*4)*pump)
        rig.turn("R_Upperarm", [1,0,0], -82*pump)
        rig.turn("R_Upperarm", [0,0,1], -26*pump)
        rig.turn("R_Forearm", [1,0,0], -58*pump)
        rig.turn("L_Upperarm", [0,0,1], 12*pump)
    elif name == "ButcherDeath":
        buckle = envelope(t, [(0,0),(.25,1),(.48,1),(duration,1)])
        fall = envelope(t, [(0,0),(.25,0),(.8,1),(.92,.94),(1.08,1),(duration,1)])
        rig.move("Hip", [0, -.085*buckle, .06*buckle])
        rig.turn("Waist", [1,0,0], -18*buckle)
        rig.turn("Head", [1,0,0], 17*buckle)
        for side, sign in (("L",1), ("R",-1)):
            rig.turn(side+"_Upperarm", [0,0,1], sign*34*fall)
            rig.turn(side+"_Upperarm", [1,0,0], -34*fall)
        for side in ("L", "R"):
            rig.leg(side, foot_targets[side])
        # Pivot the complete pose about the ground; skin geometry determines
        # the final floor contact, so the belly does not pass through it.
        root = rig.names["Armature"]
        delta = axis_rotation([1,0,0], -86*fall)
        rig.local[root][:3,:3] = delta
        vertices = rig.skinned()
        rig.local[root][1,3] += rig.floor-float(vertices[:,1].min())
        return
    if name not in ("ButcherIdle", "ButcherVictory"):
        for side in ("L", "R"):
            rig.leg(side, foot_targets[side], pitches[side])
    # Preserve actual boot contact, including vertices shared by calf/foot
    # weights. Joint height alone is not the sole height on this broad skin.
    rig.move("Root", [0, rig.floor-float(rig.skinned()[:,1].min()), 0])


def bake(glb):
    glb.doc["animations"] = []
    glb.compact()
    # The earlier retarget pass lifted Root but left the inverse bind matrices
    # untouched. Restore the mesh's actual floor before authoring motion.
    initial = Rig(glb)
    for node in glb.doc["nodes"]:
        if node["name"] == "Root":
            node["translation"][1] -= initial.floor
    rig = Rig(glb)
    report = []
    for name, duration, loop, description in CLIPS:
        count = round(duration*60)
        times = np.linspace(0, duration, count+1)
        frames, floors, feet = [], [], []
        for t in times:
            pose(rig, name, t, duration)
            frames.append([m.copy() for m in rig.local])
            floors.append(float(rig.skinned()[:,1].min()-rig.floor))
            feet.append([rig.position(side+"_Foot").tolist() for side in ("L","R")])
        if loop:
            frames[-1] = copy.deepcopy(frames[0])
        anim = {"name": name, "channels": [], "samplers": [],
                "extras": {"loop": loop, "description": description}}
        if name == "ButcherHook":
            anim["extras"]["releaseTime"] = 9/32
        time_accessor = glb.accessor(times, "SCALAR")
        for i in range(len(rig.nodes)):
            if "mesh" in rig.nodes[i]: continue
            for path, kind in (("rotation", "VEC4"), ("translation", "VEC3")):
                values = np.array([quaternion(f[i][:3,:3]) if path == "rotation" else f[i][:3,3] for f in frames])
                if path == "rotation":
                    for k in range(1,len(values)):
                        if np.dot(values[k-1], values[k]) < 0: values[k] *= -1
                assert np.isfinite(values).all(), name
                anim["channels"].append({"sampler": len(anim["samplers"]), "target": {"node": i, "path": path}})
                anim["samplers"].append({"input": time_accessor, "output": glb.accessor(values, kind), "interpolation": "LINEAR"})
        glb.doc["animations"].append(anim)
        report.append({"name": name, "duration": duration, "loop": loop, "description": description,
                       "floorRange": [min(floors), max(floors)], "samples": len(times)})
        print(name, f"{duration:.3f}s", "floor range", np.round([min(floors),max(floors)],4))
    glb.doc["asset"]["generator"] = "Pudge Wars bespoke butcher motion v5 — edge-down cuts"
    return {"rigHeight": rig.height, "rigFloor": rig.floor, "clips": report}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets", type=Path, default=ASSETS)
    parser.add_argument("--inspect", action="store_true")
    args = parser.parse_args()
    glb = Glb(args.assets / "butcher.glb")
    if args.inspect:
        rig = Rig(glb)
        for name in rig.names:
            if "Twist" not in name: print(name, np.round(rig.position(name),4))
        print("floor",rig.floor,"height",rig.height)
        return
    report = bake(glb)
    glb.write(args.assets / "butcher_game.glb")
    glb.doc["images"][0]["bufferView"] = glb.buffer((args.assets/"butcher_east_albedo.png").read_bytes())
    glb.compact()
    glb.write(args.assets / "butcher_game_east.glb")
    for source, dest in (("butcher", "butcher_game"), ("butcher_east", "butcher_game_east")):
        shutil.copyfile(args.assets / (source+".profile.png"), args.assets / (dest+".profile.png"))
    (args.assets/"butcher_motion.json").write_text(json.dumps(report, indent=2)+"\n")


if __name__ == "__main__":
    main()
