"""Versioned, inspectable execution bindings for textual strategy programs.

No complete-policy escape hatch: each routine has a narrow action/state contract.
Shared bindings are frozen during a round trip; strategy order lives in generated code.
"""
from __future__ import annotations

import math
import hashlib
from pathlib import Path

VERSION = 'pudge-skills-v1'


def verify_binding(expected):
    if hashlib.sha256(Path(__file__).read_bytes()).hexdigest() != expected:
        raise ValueError('Skill binding changed; regenerate and re-evaluate explicitly')


def gap(a, b):
    return math.hypot(a['x']-b['x'], a['y']-b['y'])


def point(x, y):
    return [max(8., min(119., x)), max(8., min(119., y))]


def segment(a, b, p):
    dx, dy = b[0]-a[0], b[1]-a[1]
    n = dx*dx+dy*dy
    u = max(0., min(1., ((p[0]-a[0])*dx+(p[1]-a[1])*dy)/n)) if n else 0.
    return math.hypot(p[0]-a[0]-u*dx, p[1]-a[1]-u*dy)


class State:
    def __init__(self):
        self.tick = -1
        self.samples = {}
        self.last_enemy = None
        self.last_seen = -1
        self.rescue_until = 0
        self.dodge = 0


class Context:
    def __init__(self, obs, state):
        if obs['tick'] < state.tick:
            state.__init__()
        state.tick = obs['tick']
        self.obs, self.state, self.me = obs, state, obs['self']
        self.action, self.trace = {}, []
        self.team, self.tick = self.me['team'], obs['tick']
        self.alive = self.me['alive']
        self.units = [p for p in obs['visible']['pudges'] if p['alive']]
        self.allies = [p for p in self.units if p['team']==self.team and p['id']!=self.me['id']]
        self.enemies = sorted((p for p in self.units if p['team']!=self.team and not p['shield']), key=lambda p:(gap(self.me,p),p['id']))
        self.hooks = obs['visible']['hooks']
        self.target = self.enemies[0] if self.enemies else None
        self.river = self.me.get('in_river', self.me.get('layer')==2)
        self.own_land = self.me.get('layer', self.team)==self.team
        self.home = [self.me['home_x'], self.me['home_y']]
        self.levels = list(self.me.get('upgrades',[0]*4))
        self.ranks = list(self.me.get('item_ranks',[0]*5))
        self.gold = self.me.get('gold',0)
        self.buff = self.me.get('buff',0)
        self.busy = False
        self.carried = {h['victim']:h for h in self.hooks if h.get('victim')}
        self.caught = next((p for p in self.enemies if p['id'] in self.carried and self.carried[p['id']]['team']==self.team),None)
        self.threat = min((h for h in self.hooks if h['team']!=self.team and h['flying'] and gap(self.me,h)<=22),key=lambda h:gap(self.me,h),default=None)
        self.low = False

    def velocity(self, unit):
        sample = self.state.samples.get(unit['id'])
        return sample[3:] if sample else (0.,0.)

    def throw(self, aim, rescue_id=0, conservative=False):
        if not self.me['hook_ready'] or self.me.get('hooked') or 'hook_to' in self.action:
            return False
        if any(h['owner_id']==self.me['id'] for h in self.hooks):
            return False
        start = self.action.get('blink_to',[self.me['x'],self.me['y']])
        reach = 55 if conservative else (60+4*self.levels[1])*(1.5 if self.buff==4 else 1)
        radius = 1.9 if conservative else (2.75+.125*self.levels[3])*(1.5 if self.buff==4 else 1)
        length = math.dist(start,aim)
        if length<.01 or (conservative and length>reach):
            return False
        end = [start[i]+(aim[i]-start[i])*min(1.,reach/length) for i in range(2)]
        for ally in self.allies:
            if ally['id']==rescue_id or (not conservative and ally['shield']>9):
                continue
            vx,vy = self.velocity(ally)
            positions = [[ally['x'],ally['y']]] if conservative else [[ally['x'],ally['y']],[ally['x']+vx/2,ally['y']+vy/2]]
            if any(segment(start,end,p)<5 if conservative else segment(start,end,p)<=radius+3.1 for p in positions):
                return False
        self.action['hook_to']=point(*aim)
        return True


def alive(c): return c.alive


def observe(c, retreat_percent=35):
    c.low = c.me['hp']*100 < c.me['max_hp']*retreat_percent
    for p in c.units:
        old=c.state.samples.get(p['id'])
        if old is None:
            c.state.samples[p['id']]=(c.tick,p['x'],p['y'],0.,0.)
        elif c.tick-old[0]>=8:
            scale=8/(c.tick-old[0])
            c.state.samples[p['id']]=(c.tick,p['x'],p['y'],(p['x']-old[1])*scale,(p['y']-old[2])*scale)
    if c.target:
        c.state.last_enemy=c.target.copy();c.state.last_seen=c.tick
    if c.threat is None: c.state.dodge=0
    elif not c.state.dodge:
        c.state.dodge=-1 if c.threat['y']>c.me['y'] else 1
        if c.me['y']<20:c.state.dodge=1
        if c.me['y']>108:c.state.dodge=-1
    return False


def economy(c):
    buys=[]
    for _ in range(c.me.get('points',0)):
        k=next((i for i in (1,2,0,3) if c.levels[i]<10),None)
        if k is None:break
        c.levels[k]+=1;buys.append(k)
    if buys:c.action['buy_upgrade']=buys
    buys=[]
    if c.me.get('in_shop'):
        if 'ward_restock' in c.me and not c.ranks[4] and c.me['ward_restock']==0:
            buys.append(9);c.ranks[4]=1
        if c.me['hp']*2<c.me['max_hp'] and c.gold>=5:
            buys.append(0);c.gold-=5
        while True:
            count=len(buys)
            for item,index,price in [(6,1,12),(5,0,10)]:
                if c.ranks[index]<5 and c.gold>=price:
                    buys.append(item);c.ranks[index]+=1;c.gold-=price
            if len(buys)==count:break
        if c.ranks[1] and c.buff==0 and c.gold>=6:
            buys.append(3);c.buff=4;c.gold-=6
    if buys:c.action['buy_power']=buys
    return False


def reserve_when_hurt(c):
    # A hook-channel claim, independent of movement selection.
    if c.low:c.action['_reserve']=True;return True
    return False


def rescue(c, coordinated=False):
    if c.action.get('_reserve'):return False
    danger=[]
    for p in c.allies:
        h=c.carried.get(p['id'])
        if (h is not None and h['team']!=c.team) or (h is None and p.get('in_river',p.get('layer')==2) and p['hp']*100<=p['max_hp']*60):danger.append(p)
    danger.sort(key=lambda p:(gap(c.me,p),p['id']))
    if not danger:return False
    p=danger[0]
    if coordinated:
        if not c.own_land or c.low or c.threat is not None:return False
        eligible=[u for u in [c.me,*c.allies] if u['id']!=p['id'] and u['hook_ready'] and not u.get('hooked') and u.get('layer',c.team)==c.team and u['hp']*100>=u['max_hp']*40]
        owner=min(eligible,key=lambda u:(gap(u,p),u['id']),default=None)
        if owner is None or owner['id']!=c.me['id']:return False
    if c.throw([p['x'],p['y']],p['id'],conservative=not coordinated):
        if coordinated:c.state.rescue_until=c.tick+10;c.action['walk_to']=[c.me['x'],c.me['y']]
        return True
    return False


def sustain_rescue(c):
    active=any(h['owner_id']==c.me['id'] and any(a['id']==h.get('victim') for a in c.allies) for h in c.hooks)
    if c.own_land and not c.low and c.threat is None and not c.me.get('hooked') and (active or c.tick<c.state.rescue_until):
        c.action['walk_to']=[c.me['x'],c.me['y']];return True
    return False


def blink_defense(c):
    if not c.me.get('blink_ready'):return False
    if c.river:c.action['blink_to']=point(c.obs['play_west_max'] if c.team==0 else c.obs['play_east_min'],c.me['y'])
    elif c.threat:
        x,y=point(c.me['x']+(-16 if c.team==0 else 16),c.me['y']+16*c.state.dodge)
        scale=min(1.,20/math.hypot(x-c.me['x'],y-c.me['y']))
        c.action['blink_to']=[c.me['x']+(x-c.me['x'])*scale,c.me['y']+(y-c.me['y'])*scale]
    return False


def hooked(c):return bool(c.me.get('hooked'))


def follow_up(c):
    if c.caught and not c.action.get('_reserve'):
        h=c.carried[c.caught['id']];owner=next((p for p in c.units if p['id']==h['owner_id']),c.caught)
        return c.throw([(c.caught['x']+owner['x'])/2,(c.caught['y']+owner['y'])/2])
    return False


def close_shot(c):
    return bool(c.target and not c.river and not c.action.get('_reserve') and gap(c.me,c.target)<=20 and c.throw([c.target['x'],c.target['y']]))


def intercept_hook(c):
    return bool(c.threat and not c.action.get('_reserve') and gap(c.me,c.threat)<=14 and c.throw([c.threat['x'],c.threat['y']]))


def swimming_shot(c):
    p=next((p for p in c.enemies if p.get('layer')==2),None)
    return bool(p and not c.action.get('_reserve') and c.throw([p['x'],p['y']]))


def aimed_shot(c, lead=1.0):
    if c.target is None or c.action.get('_reserve'):return False
    reach=(60+4*c.levels[1])*(1.5 if c.buff==4 else 1)
    if gap(c.me,c.target)>reach+5:return False
    vx,vy=c.velocity(c.target);span=max(abs(c.me['x']-c.target['x']),abs(c.me['y']-c.target['y']))
    aim=point(c.target['x']+lead*vx*span/(30+c.levels[2]),c.target['y']+lead*vy*span/(30+c.levels[2]))
    if segment([c.me['x'],c.me['y']],aim,[64,64])<=5:return False
    return c.throw(aim)


def nearest_shot(c):
    return bool(c.target and not c.action.get('_reserve') and c.throw([c.target['x'],c.target['y']],conservative=True))


def rune_shot(c):
    if c.river or c.action.get('_reserve'):return False
    for rune in c.obs['visible'].get('runes',[]):
        if abs(c.me['x']-rune['x'])<=36 and abs(c.me['y']-rune['y'])<=36 and c.throw([rune['x'],rune['y']]):return True
    return False


def fog_shot(c):
    if c.target or c.river or c.tick<=8 or c.action.get('_reserve'):return False
    west,east=c.obs['play_west_max'],c.obs['play_east_min']
    x,y=(east+8 if c.team==0 else west-8),c.me['y']
    if c.state.last_enemy:
        p=c.state.last_enemy;age=c.tick-c.state.last_seen;vx,vy=c.velocity(p)
        y=p['y']+vy*age/8
        x=p['x']+vx*age/8 if age<=96 else east+2 if c.team==0 else west-2
    x=max(east+1,min(113,x)) if c.team==0 else min(west-1,max(14,x))
    return c.throw(point(x,max(16,min(111,y))))


def combat(c):
    p=c.target
    brawl=bool(p and (c.me['hp']+40>=p['hp'] or p['hp']<=120 or (not c.own_land and not c.river)))
    rot=bool(p and any(gap(c.me,e)<=8 for e in c.enemies) and brawl and not c.river and not c.low and c.me['hp']>96)
    if rot!=c.me.get('rot',False):c.action['rot']=rot
    c.foreign_rot=any(p.get('rot') and gap(c.me,p)<=8 for p in c.units if p['id']!=c.me['id'])
    c.flee_rot=c.foreign_rot and not rot;c.brawl=brawl
    if p and gap(c.me,p)<=5.5 and brawl and not c.flee_rot:c.action['attack_target']=p['id']
    return False


def simple_movement(c):
    if c.river or c.low:c.action['walk_to']=c.home
    else:
        coach=min(c.allies,key=lambda p:p['id'],default=c.me)
        lip=c.obs['play_west_max']-5 if c.team==0 else c.obs['play_east_min']+5
        c.action['walk_to']=point(lip,coach['y']+(8 if coach['y']<64 else -8))
    return False


def tactical_movement(c, bank_margin=16, lane_spacing=24):
    if 'blink_to' in c.action:return False
    hold=c.obs['play_west_max']-bank_margin if c.team==0 else c.obs['play_east_min']+bank_margin
    c.busy=True
    if getattr(c,'flee_rot',False):c.action['walk_to']=point(c.home[0],c.me['y']+(((c.tick//12)%2)*2-1)*8)
    elif c.threat:c.action['walk_to']=point(c.me['x']+(-2 if c.team==0 else 2),c.me['y']+c.state.dodge*10)
    elif c.river:c.action['walk_to']=[hold,c.me['y']]
    elif 'attack_target' in c.action:pass
    elif c.caught and not c.low:c.action['walk_to']=point(min(c.caught['x'],hold) if c.team==0 else max(c.caught['x'],hold),c.caught['y'])
    elif c.low or (c.target and gap(c.me,c.target)<=12 and not getattr(c,'brawl',False)):c.action['walk_to']=c.home
    elif not c.me.get('in_shop') and c.gold>=12 and (c.ranks[0]<5 or c.ranks[1]<5):c.action['walk_to']=[22 if c.team==0 else 106,64]
    else:
        c.busy=False
        rank=sum(p['id']<c.me['id'] for p in c.allies)
        phase=(c.tick//6+c.me['id']*7)%24;juke=phase//3-2 if phase<12 else 6-phase//3
        n=len(c.allies)+1
        y=64+(rank-(n-1)/2)*lane_spacing+juke if c.allies else (c.target['y'] if c.target else c.me['y'])+juke*1.5
        upcoming=c.obs.get('rune_next',{'soon':0})
        if 0<upcoming['soon']<=256:y=upcoming['y']
        c.action['walk_to']=point(hold,y)
    return False


def ward(c):
    if 'blink_to' in c.action:return False
    if 'ward_restock' not in c.me or c.me.get('item_ranks',[0]*5)[4]<=0 or not c.own_land:return False
    x=c.obs['play_east_min']+3 if c.team==0 else c.obs['play_west_max']-3
    y=50 if 54<c.me['y']<74 else c.me['y']
    if math.hypot(x-c.me['x'],y-c.me['y'])<=32:c.action['place_ward']=[x,y]
    elif not c.busy:c.action['walk_to']=[c.obs['play_west_max']-5 if c.team==0 else c.obs['play_east_min']+5,y]
    return False


def finish(c):
    return {k:v for k,v in c.action.items() if not k.startswith('_')}


def invoke(c, name, **arguments):
    result=globals()[name](c,**arguments)
    c.trace.append({'skill':name,'result':bool(result),'arguments':arguments.copy()})
    return result
