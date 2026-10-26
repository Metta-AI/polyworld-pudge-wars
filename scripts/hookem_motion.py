"""Author cowboy rope handling on the shared Polyworld skeleton."""
import copy
import math
import numpy as np
from build_butcher import quaternion, pose, smooth, unit


def arm(rig, side, target, pole):
    """Two-bone IK with a stable elbow pole; preserve actual limb lengths."""
    shoulder, elbow, wrist = [side + '_' + x for x in ('Upperarm', 'Forearm', 'Hand')]
    origin = rig.position(shoulder)
    upper = np.linalg.norm(rig.position(elbow, True) - rig.position(shoulder, True))
    lower = np.linalg.norm(rig.position(wrist, True) - rig.position(elbow, True))
    direction = unit(target - origin)
    distance = np.clip(np.linalg.norm(target - origin), abs(upper-lower)+.001, upper+lower-.001)
    along = (upper*upper-lower*lower+distance*distance)/(2*distance)
    bend = unit(pole - direction * np.dot(pole, direction))
    joint = origin + direction*along + bend*math.sqrt(max(0, upper*upper-along*along))
    rig.aim(shoulder, elbow, joint)
    rig.aim(elbow, wrist, origin + direction*distance)


def bake_cowboy_motion(glb, rig):
    clips = [('ButcherIdle',1.2,True),('ButcherRun',.72,True),
             ('ButcherHook',19/32,False),('WranglerReel',1.2,True),
             ('WranglerRunReel',.72,True)]
    names = {c[0] for c in clips}
    glb.doc['animations'] = [a for a in glb.doc['animations'] if a['name'] not in names]
    for name, duration, loop in clips:
        times = np.linspace(0,duration,round(duration*60)+1)
        frames = []
        for t in times:
            running = name in ('ButcherRun','WranglerRunReel')
            reeling = name in ('WranglerReel','WranglerRunReel')
            phase = t/duration * math.tau
            pose(rig, 'ButcherRun' if running else 'ButcherIdle', t, duration)
            # Relaxed shoulders and a little torso counterrotation, with planted
            # feet at idle. The right wrist circles above the shoulder.
            rig.turn('Spine02',[0,1,0],4*math.sin(phase))
            rig.turn('Head',[0,1,0],-3*math.sin(phase))
            ready = np.array([-.30+.035*math.cos(phase), .93+.018*math.sin(phase), .035+.04*math.sin(phase)])
            left = np.array([.18,.40,.13])
            right = ready
            if name == 'ButcherHook':
                # Actual game releases at 9/32s. Cock overhead, reach forward,
                # then gather the line back against the chest.
                release = 9/32
                reach = np.array([-.20,.57,.34])
                gather = np.array([-.20,.44,.17])
                if t < release:
                    w = smooth(max(0,t-.09)/(release-.09))
                    right = ready*(1-w)+reach*w
                    rig.turn('Waist',[0,1,0],-12*(1-w)+16*w)
                else:
                    w = smooth((t-release)/(duration-release))
                    right = reach*(1-w)+gather*w
                rig.turn('Spine01',[1,0,0],6*math.sin(math.pi*t/duration))
            elif reeling:
                pull = .5-.5*math.cos(phase)
                right = np.array([-.20,.44+.035*pull,.24-.13*pull])
                left = np.array([.15,.40,.15+.055*pull])
                rig.turn('Spine01',[1,0,0],-3*pull)
            arm(rig,'R',right,np.array([-1.,0.,-.2]))
            arm(rig,'L',left,np.array([1.,0.,0.]))
            frames.append([m.copy() for m in rig.local])
        if loop: frames[-1] = copy.deepcopy(frames[0])
        anim = {'name':name,'channels':[],'samplers':[], 'extras':{'loop':loop,'author':'hookem'}}
        if name == 'ButcherHook': anim['extras']['releaseTime']=9/32
        time_accessor = glb.accessor(times,'SCALAR')
        for i,node in enumerate(rig.nodes):
            if 'mesh' in node: continue
            for path,kind in [('rotation','VEC4'),('translation','VEC3')]:
                values = np.array([quaternion(f[i][:3,:3]) if path=='rotation' else f[i][:3,3] for f in frames])
                if path=='rotation':
                    for k in range(1,len(values)):
                        if np.dot(values[k-1],values[k])<0: values[k]*=-1
                assert np.isfinite(values).all(), name
                anim['channels'].append({'sampler':len(anim['samplers']),'target':{'node':i,'path':path}})
                anim['samplers'].append({'input':time_accessor,'output':glb.accessor(values,kind),'interpolation':'LINEAR'})
        glb.doc['animations'].append(anim)
        print(name, len(times), 'motion samples')
