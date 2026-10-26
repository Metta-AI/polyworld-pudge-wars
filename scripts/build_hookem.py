#!/usr/bin/env python3
"""Build hookem's original low-poly cowboy on Polyworld's existing animated rig.

The generated mesh is authored here from geometry, not a recolored butcher.
The shared motion clips and hand sockets keep gameplay animation timing stable.
Requires numpy. Generated GLBs are checked in beside the game.
"""
import copy
import math
from pathlib import Path
import numpy as np
from build_butcher import Glb, Rig, unit
from hookem_motion import bake_cowboy_motion

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT.parent / 'polyworld_data/characters/butcher/butcher_game.glb'
OUT = ROOT / 'examples/pudge_wars/assets/hookem'


def build(team):
    glb = Glb(SOURCE)
    rig = Rig(glb)
    groups = {}
    colors = {
        'shirt': (0.79, .69, .48), 'vest': (.34, .19, .09),
        'leather': (.22, .12, .065), 'hat': (.53, .32, .14),
        'hat_top': (.64, .41, .20), 'denim': (.15, .23, .29),
        'skin': (.78, .45, .26), 'skin_light': (.96, .65, .40),
        'hair': (.12, .065, .035), 'ivory': (.95, .88, .68),
        'black': (.035, .04, .04), 'brass': (.84, .59, .22),
        'team': ((.78, .20, .10) if team == 'west' else (.13, .39, .65)),
    }
    joint_for = {glb.doc['nodes'][n]['name']: i for i, n in enumerate(rig.joints)}
    bind = [np.linalg.inv(rig.rest[n] @ rig.inverse_bind[i]) for i, n in enumerate(rig.joints)]

    def face(points, bone, material):
        points = np.array(points, dtype=float)
        normal = np.cross(points[1]-points[0], points[2]-points[0])
        if np.linalg.norm(normal) < 1e-10:
            return
        normal = unit(normal)
        j = joint_for[bone]
        positions, normals, joints = groups.setdefault(material, ([], [], []))
        for i in range(1, len(points)-1):
            for p in [points[0], points[i], points[i+1]]:
                positions.append((bind[j] @ np.r_[p, 1])[:3])
                normals.append(unit(bind[j][:3, :3] @ normal))
                joints.append([j, 0, 0, 0])

    def ellipsoid(center, size, bone, material, rings=6, sides=12):
        center, size = np.array(center), np.array(size)
        def point(a, b):
            return center + size * [math.sin(a)*math.cos(b), math.cos(a), math.sin(a)*math.sin(b)]
        for i in range(rings):
            for j in range(sides):
                a,b=i*math.pi/rings,j*math.tau/sides
                c,d=(i+1)*math.pi/rings,(j+1)*math.tau/sides
                face([point(a,b),point(a,d),point(c,d),point(c,b)],bone,material)

    def tube(a,b,r0,r1,bone,material,sides=10):
        a,b=np.array(a),np.array(b);axis=unit(b-a)
        side=unit(np.cross(axis,[0,0,1] if abs(axis[2])<.9 else [1,0,0]));up=np.cross(axis,side)
        p=[a+r0*(side*math.cos(j*math.tau/sides)+up*math.sin(j*math.tau/sides)) for j in range(sides)]
        q=[b+r1*(side*math.cos(j*math.tau/sides)+up*math.sin(j*math.tau/sides)) for j in range(sides)]
        for j in range(sides):
            k=(j+1)%sides;face([p[j],p[k],q[k],q[j]],bone,material)
        face(p[::-1],bone,material);face(q,bone,material)

    def box(c,s,bone,material):
        c,s=np.array(c),np.array(s)
        p=[c+s*np.array(v) for v in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
        for f in [(0,3,2,1),(4,5,6,7),(0,4,7,3),(1,2,6,5),(3,7,6,2),(0,1,5,4)]:face([p[i] for i in f],bone,material)

    # Boots, jeans, rolled sleeves and gloves follow the existing skeletal sockets.
    for side in ['L','R']:
        hip,knee,foot,arm,elbow,hand=[rig.position(side+'_'+n) for n in ['Thigh','Calf','Foot','Upperarm','Forearm','Hand']]
        tube(hip,knee,.078,.066,side+'_Thigh','denim')
        tube(knee,foot,.063,.052,side+'_Calf','denim')
        ellipsoid(foot+[0,-.022,.034],[.075,.047,.12],side+'_Foot','leather')
        tube(foot,foot+[0,.095,0],.067,.073,side+'_Calf','leather')
        tube(arm,elbow,.085,.066,side+'_Upperarm','shirt')
        tube(elbow,hand,.062,.044,side+'_Forearm','skin_light')
        tube(elbow,elbow+(hand-elbow)*.28,.069,.065,side+'_Forearm','shirt')
        ellipsoid(hand,[.060,.066,.053],side+'_Hand','leather')
        ellipsoid(hip,[.081,.08,.072],side+'_Thigh','denim')
    ellipsoid([-.07,.32,-.02],[.175,.105,.12],'Pelvis','denim')
    ellipsoid([-.065,.49,-.04],[.22,.18,.145],'Spine01','shirt')
    # Two vest panels and broad lapels; cream shirt remains visible down the middle.
    for x,sign in [(-.17,-1),(.04,1)]:
        ellipsoid([x,.49,-.015],[.105,.165,.14],'Spine02','vest')
        face([[x-sign*.07,.64,.085],[x+sign*.035,.59,.12],[x-sign*.04,.47,.14]],'Spine02','hat')
    ellipsoid([-.07,.34,-.02],[.183,.027,.128],'Pelvis','leather')
    box([-.07,.345,.112],[.038,.026,.014],'Pelvis','brass')
    for y in [.42,.48,.54]:ellipsoid([-.065,y,.110],[.009,.009,.007],'Spine02','brass',4,8)
    # A team-colored neckerchief has a visible triangular tail on the chest.
    ellipsoid([-.061,.65,-.047],[.112,.039,.105],'Spine02','team')
    face([[-.155,.654,.06],[.035,.654,.06],[-.055,.535,.13]],'Spine02','team')
    ellipsoid([-.06,.645,.064],[.025,.025,.025],'Spine02','team')
    head=rig.position('Head')
    ellipsoid(head+[0,.085,0],[.105,.135,.10],'Head','skin_light')
    for sign in [-1,1]:ellipsoid(head+[sign*.104,.082,0],[.025,.038,.024],'Head','skin')
    ellipsoid(head+[0,.105,.105],[.031,.028,.03],'Head','skin_light')
    for sign in [-1,1]:
        ellipsoid(head+[sign*.043,.13,.087],[.023,.018,.015],'Head','ivory')
        ellipsoid(head+[sign*.041,.13,.101],[.009,.012,.006],'Head','black')
        box(head+[sign*.043,.155,.091],[.026,.009,.008],'Head','hair')
        ellipsoid(head+[sign*.026,.067,.096],[.038,.014,.017],'Head','hair')
    ellipsoid(head+[0,.034,.07],[.046,.012,.022],'Head','hair')
    # Broad curled brim, pinched crown and hatband form the top-down silhouette.
    ellipsoid(head+[0,.225,0],[.225,.024,.174],'Head','hat',4,20)
    for sign in [-1,1]:ellipsoid(head+[sign*.185,.237,0],[.04,.025,.14],'Head','hat',4,10)
    ellipsoid(head+[0,.285,-.012],[.128,.095,.106],'Head','hat_top',5,14)
    ellipsoid(head+[0,.245,-.008],[.133,.018,.11],'Head','leather',4,14)
    box(head+[0,.246,.103],[.02,.015,.007],'Head','brass')

    bake_cowboy_motion(glb, rig)
    glb.doc['materials']=[];primitives=[]
    for name,(positions,normals,joints) in groups.items():
        count=len(positions);m=len(glb.doc['materials'])
        glb.doc['materials'].append({'name':name,'doubleSided':True,'pbrMetallicRoughness':{'baseColorFactor':[*colors[name],1],'roughnessFactor':.9,'metallicFactor':0}})
        joint_accessor=len(glb.doc['accessors'])
        glb.doc['accessors'].append({'bufferView':glb.buffer(np.asarray(joints,dtype='<u2').tobytes()),'componentType':5123,'count':count,'type':'VEC4'})
        index_accessor=len(glb.doc['accessors'])
        glb.doc['accessors'].append({'bufferView':glb.buffer(np.arange(count,dtype='<u2').tobytes()),'componentType':5123,'count':count,'type':'SCALAR'})
        primitives.append({'material':m,'indices':index_accessor,'attributes':{
            'POSITION':glb.accessor(positions,'VEC3'),'NORMAL':glb.accessor(normals,'VEC3'),
            'TEXCOORD_0':glb.accessor(np.zeros((count,2)),'VEC2'),'JOINTS_0':joint_accessor,
            'WEIGHTS_0':glb.accessor(np.tile([1,0,0,0],(count,1)),'VEC4')}})
    glb.doc['meshes']=[{'name':'hookem_cowboy','primitives':primitives}]
    glb.doc['images']=[];glb.doc['textures']=[];glb.doc['samplers']=[]
    glb.doc['asset']['generator']='Polyworld hookem procedural cowboy'
    glb.compact();OUT.mkdir(parents=True,exist_ok=True)
    glb.write(OUT/f'cowboy_{team}.glb')
    print(team,sum(len(g[0]) for g in groups.values())//3,'triangles')

if __name__=='__main__':
    for team in ['west','east']:build(team)
