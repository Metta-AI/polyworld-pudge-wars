"""Execution library for s-hook-corridor and b-hook-motion, version 2.

The semantic interface lives in blink-candidate.md. This library only decides
whether nearby observed projectiles still justify the existing Blink skill.
"""

def measured_blink_threat(observation, history):
    me = observation['self']
    tick = observation['tick']
    next_history = {}
    need_blink = bool(me['hooked'])
    for hook in observation['visible']['hooks']:
        if not hook['flying']:
            continue
        owner = hook['owner_id']
        old = history.get(owner)
        next_history[owner] = (tick, hook['x'], hook['y'])
        dx, dy = me['x'] - hook['x'], me['y'] - hook['y']
        if hook['team'] == me['team'] or dx * dx + dy * dy > 22 * 22:
            continue
        if old is None or old[0] != tick - 1:
            need_blink = True
            continue
        vx, vy = hook['x'] - old[1], hook['y'] - old[2]
        speed2 = vx * vx + vy * vy
        if not 0.0001 < speed2 < 64:
            need_blink = True
            continue
        dot = dx * vx + dy * vy
        if dot <= 0:
            continue
        time_to_closest = dot / speed2
        miss2 = (dx - vx * time_to_closest) ** 2 + (dy - vy * time_to_closest) ** 2
        if miss2 <= 10 * 10 + 1e-9:
            need_blink = True
    history.clear()
    history.update(next_history)
    return need_blink
