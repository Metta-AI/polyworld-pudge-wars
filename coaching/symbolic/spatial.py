"""Policy-independent spatial measurements from fog-filtered game observations.

Measured every eight ticks (4 Hz), including deaths in the elapsed-time context.
Body contact is a distance proxy, not an authoritative engine collision event.
"""
from collections import Counter
import math


class SpatialMetrics:
    def __init__(self):
        self.counts = Counter()
        self.previous = {}

    def observe(self, obs, action):
        if obs['tick'] % 8:
            return
        me = obs['self']
        identity = me['id']
        point = (me['x'], me['y'])
        old = self.previous.get(identity)
        self.previous[identity] = (obs['tick'], point, me['alive'], action.get('walk_to'))
        if not me['alive'] or me.get('hooked') or me.get('in_river') or me.get('layer') != me['team']:
            return
        allies = [p for p in obs['visible']['pudges'] if p['alive'] and p['team']==me['team'] and p['id']!=identity]
        if not allies:
            return
        nearest = min(math.hypot(p['x']-point[0], p['y']-point[1]) for p in allies)
        count = self.counts
        count['samples'] += 1
        count['nearest_ally_distance_sum'] += nearest
        count['clustered_samples'] += nearest < 10
        count['contact_samples'] += nearest < 5.7  # native body diameter: 5.2 tiles
        near_wall = min(point[0]-14, 114-point[0], point[1]-16, 111-point[1]) < 8
        count['wall_samples'] += near_wall
        count['wall_contact_samples'] += near_wall and nearest < 5.7
        goal = action.get('walk_to')
        if goal is None or math.dist(point, goal) < 2:
            return
        count['walking_samples'] += 1
        dx, dy = goal[0]-point[0], goal[1]-point[1]
        length = math.hypot(dx, dy)
        blocked = False
        for ally in allies:
            ax, ay = ally['x']-point[0], ally['y']-point[1]
            ahead = (ax*dx+ay*dy)/length
            lateral = abs(ax*dy-ay*dx)/length
            if 0 < ahead < min(10, length) and lateral < 5.2:
                blocked = True
        count['occupied_route_samples'] += blocked
        # A full quarter-second of <0.5 tile progress despite a continuing
        # distant walking order. Combat windup can also cause this proxy.
        stalled = bool(old and old[0] == obs['tick']-8 and old[2] and old[3]
                       and math.dist(old[1], old[3]) >= 2 and math.dist(point, old[1]) < .5)
        count['stalled_samples'] += stalled
        count['wall_stalled_samples'] += near_wall and stalled

    def report(self):
        c = self.counts
        def rate(key, denominator='samples'):
            return c[key]/c[denominator] if c[denominator] else None
        return dict(counts=dict(c),
                    clustered_fraction=rate('clustered_samples'),
                    contact_fraction=rate('contact_samples'),
                    mean_nearest_ally_distance=rate('nearest_ally_distance_sum'),
                    occupied_route_fraction=rate('occupied_route_samples', 'walking_samples'),
                    stalled_fraction=rate('stalled_samples', 'walking_samples'),
                    wall_contact_fraction=rate('wall_contact_samples', 'wall_samples'),
                    wall_stalled_fraction=rate('wall_stalled_samples', 'wall_samples'))
