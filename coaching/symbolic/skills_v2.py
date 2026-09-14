"""Formation and occupied-route concepts, extending the frozen v1 bindings.

The old library remains byte-identical so archived controls still execute. The
v2 digest covers BOTH files. These additions own only routine walking; urgent
movement and every other action channel remain the responsibility of v1 skills.
"""
from __future__ import annotations

import hashlib
import math
from pathlib import Path

from . import skills as base

VERSION = 'pudge-skills-v2'
Context = base.Context
finish = base.finish
CONTRACTS = {
    'remember_roster': ('Stable team roles',
        'Remember every observed teammate, including dead seats, ordered by home_y then ID. '
        'Death does not renumber lanes. Missing roster members remain remembered until the match resets.'),
    'spread_formation': ('Space for teammates and shared resource ownership',
        'Only routine fishing/ward approach is changed. Assign stable, symmetric lanes, bounded to y=24..104. '
        'For an announced rune within rune_window ticks, elect one healthy unhooked teammate on our bank '
        'whose assigned lane is nearest the rune (ID breaks ties). Reserve its rune lane; other seats choose '
        'distinct lanes at least lane_spacing apart when space permits. A bounded two-tile juke stays inside '
        'each lane. Survival, rescue, melee, caught-enemy approach and shop travel retain priority.'),
    'clear_occupied_route': ('Personal space and progress along the bank',
        'For nonurgent own-bank walking, test the next lookahead tiles against visible living bodies. '
        'A body ahead within clearance affords a short unobstructed detour, not repeated walking through it. '
        'Choose a progress-making eight-tile waypoint with body clearance inside the conservative bank '
        'rectangle x=18..west_lip-4 or east_lip+4..110, y=20..107. Retain a safe waypoint for up to 24 ticks '
        'to avoid alternating sides. Already-close bodies may be escaped but not approached. If no safe '
        'waypoint exists, hold this tick and retry. Blink, river escape, incoming-hook dodge, low-health '
        'retreat, rescue, melee and caught-enemy approach bypass this skill. Terrain pathfinding still '
        'belongs to the engine; unseen obstacles are not inferred.'),
}
CONTRACTS['formation_positioning'] = ('Survival, information and team space',
    'Resolve the existing tactical movement priorities, then ward placement/approach, then '
    'spread_formation in one skill, avoiding computing an idle lane that will be replaced. '
    'Priority: foreign rot, hook dodge, river exit, melee, caught target, low/unfavorable retreat, '
    'shop, then fishing. ' + CONTRACTS['spread_formation'][1] + ' '
    'Confirmed ward stock is placed across the river within 32 tiles; routine travel may approach '
    'that range. bank_margin controls normal fishing distance behind the bank lip.')


def binding_hash():
    return hashlib.sha256(Path(base.__file__).read_bytes() + b'\0' + Path(__file__).read_bytes()).hexdigest()


def verify_binding(expected):
    if binding_hash() != expected:
        raise ValueError('Skill binding changed; regenerate and re-evaluate explicitly')


def __getattr__(name):
    return getattr(base, name)


class State(base.State):
    def __init__(self):
        super().__init__()
        self.roster = {}
        self.roster_order = ()
        self.detour = None
        self.formation_key = None
        self.lanes = {}
        self.collector = None


def remember_roster(c):
    changed = False
    for p in c.obs['visible']['pudges']:
        if p['team'] == c.team and p['id'] not in c.state.roster:
            c.state.roster[p['id']] = p.get('home_y', p['y'])
            changed = True
    if c.me['id'] not in c.state.roster:
        c.state.roster[c.me['id']] = c.home[1]
        changed = True
    if changed:
        c.state.roster_order = tuple(sorted(c.state.roster, key=lambda i: (c.state.roster[i], i)))
    return False


def spread_formation(c, lane_spacing=24, rune_window=256):
    if c.busy or not c.own_land or 'blink_to' in c.action or 'walk_to' not in c.action:
        return False
    roster = c.state.roster_order
    if len(roster) < 2:
        return False
    upcoming = c.obs.get('rune_next', {})
    rune_y = upcoming['y'] if 0 < upcoming.get('soon', 0) <= rune_window else None
    eligible = tuple(p['id'] for p in c.units if p['id'] in c.state.roster and not p.get('hooked')
                    and p.get('layer', p['team']) == c.team
                    and p['hp'] * 100 >= p['max_hp'] * 40) if rune_y is not None else ()
    key = (roster, lane_spacing, rune_y, eligible)
    if key != c.state.formation_key:
        lanes, collector = allocate_lanes(roster, lane_spacing, rune_y, eligible)
        c.state.formation_key, c.state.lanes, c.state.collector = key, lanes, collector
    lanes, collector = c.state.lanes, c.state.collector
    phase = (c.tick//6+c.me['id']*7) % 24
    juke = phase//3-2 if phase < 12 else 6-phase//3
    if juke > 2:juke = 2
    if juke < -2:juke = -2
    c.action['walk_to'][1] = lanes[c.me['id']] + (0 if c.me['id']==collector else juke)
    c.formation = {'lane': lanes[c.me['id']], 'rune_collector': collector}
    return True


def allocate_lanes(roster, lane_spacing, rune_y, eligible):
    """Recompute only when roles, availability or the shared objective changes."""
    spacing = min(lane_spacing, 80 / (len(roster)-1))
    lanes = {i: 64 + (rank-(len(roster)-1)/2)*spacing for rank, i in enumerate(roster)}
    collector = None
    if rune_y is not None:
        if eligible:
            collector = min(eligible, key=lambda i: (abs(lanes[i]-rune_y), i))
            reserved = {collector: max(24, min(104, rune_y))}
            for i in roster:
                if i == collector:
                    continue
                # Maximize separation if the reserved rune makes the requested
                # spacing geometrically impossible (e.g. five seats).
                choices = list(range(24, 105, 2))
                clear = [y for y in choices if all(abs(y-v) >= spacing for v in reserved.values())]
                y = min(clear, key=lambda y: (abs(y-lanes[i]), y)) if clear else max(
                    choices, key=lambda y: (min(abs(y-v) for v in reserved.values()), -abs(y-lanes[i]), -y))
                reserved[i] = y
            lanes = reserved
    return lanes, collector


def formation_positioning(c, bank_margin=16, lane_spacing=24, rune_window=256):
    routine = (c.own_land and len(c.state.roster_order)>1 and 'blink_to' not in c.action
               and not getattr(c,'flee_rot',False) and not c.threat and not c.river
               and 'attack_target' not in c.action and not c.caught and not c.low
               and not (c.target and base.gap(c.me,c.target)<=12 and not getattr(c,'brawl',False))
               and not (not c.me.get('in_shop') and c.gold>=12 and (c.ranks[0]<5 or c.ranks[1]<5)))
    if routine:
        c.busy = False
        hold = c.obs['play_west_max']-bank_margin if c.team==0 else c.obs['play_east_min']+bank_margin
        c.action['walk_to'] = base.point(hold,c.me['y'])
    else:
        base.tactical_movement(c,bank_margin=bank_margin,lane_spacing=lane_spacing)
    base.ward(c)
    return spread_formation(c,lane_spacing=lane_spacing,rune_window=rune_window)


DIRECTIONS = tuple((math.cos(i*math.pi/8), math.sin(i*math.pi/8)) for i in range(16))


def clear_occupied_route(c, clearance=7, lookahead=12):
    goal = c.action.get('walk_to')
    if (goal is None or not c.own_land or c.river or c.low or c.threat or c.caught
            or c.me.get('hooked') or getattr(c, 'flee_rot', False)
            or 'blink_to' in c.action or 'attack_target' in c.action):
        c.state.detour = None
        return False
    start = (c.me['x'], c.me['y'])
    bodies = [(p['x'], p['y']) for p in c.units if p['id'] != c.me['id']
              and (start[0]-p['x'])**2+(start[1]-p['y'])**2 < (lookahead+clearance)**2]
    if not bodies:
        c.state.detour = None
        return False
    length = math.dist(start, goal)
    if length < 1:
        c.state.detour = None
        return False

    def unobstructed(end):
        dx, dy = end[0]-start[0], end[1]-start[1]
        for p in bodies:
            distance = math.dist(start, p)
            dot = (p[0]-start[0])*dx + (p[1]-start[1])*dy
            if distance < clearance:
                # Let already touching players separate without demanding
                # impossible clearance at the beginning of their path.
                if dot > .01 or math.dist(end, p) < distance+.1:
                    return False
            elif base.segment(start, end, p) < clearance:
                return False
        return True

    direct = tuple(start[i]+(goal[i]-start[i])*min(1, lookahead/length) for i in range(2))
    held = c.state.detour
    if held and c.tick < held['until'] and math.dist(goal, held['goal']) < 4:
        if math.dist(start, held['point']) > 2 and unobstructed(held['point']):
            c.action['walk_to'] = held['point'].copy()
            return True
    c.state.detour = None
    if unobstructed(direct):
        return False
    x_low, x_high = (18, c.obs['play_west_max']-4) if c.team == 0 else (c.obs['play_east_min']+4, 110)
    options = []
    for dx, dy in DIRECTIONS:
        end = [max(x_low, min(x_high, start[0]+8*dx)), max(20, min(107, start[1]+8*dy))]
        if math.dist(start, end) < 6 or not unobstructed(end):
            continue
        # Permit a short step away to get around a blocker. The small space
        # bonus prefers the open side when two detours make equal progress.
        separation = min(clearance*2, min(math.dist(end, p) for p in bodies))
        options.append((math.dist(end, goal)-.15*separation, end))
    if options:
        end = min(options, key=lambda item: (item[0], item[1]))[1]
        c.state.detour = {'point': end, 'goal': list(goal), 'until': c.tick+24}
        c.action['walk_to'] = end.copy()
    else:
        c.action['walk_to'] = list(start)
    return True


def invoke(c, name, **arguments):
    result = _FUNCTIONS[name](c, **arguments)
    # **arguments is already a fresh dict owned by this invocation. Keeping it
    # does not alias the caller's kwargs or a later decision's trace.
    c.trace.append({'skill': name, 'result': bool(result), 'arguments': arguments})
    return result


_FUNCTIONS = {**vars(base), **globals()}
