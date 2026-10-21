# Versioned grounding for the complete E06 coaching package.
BUNDLE_COUNTS = dict(engagement_pairs=0, engagement_requests=0,
                     fountain_rejections=0, curve_starts=0, curve_steps=0,
                     curve_flying_steps=0, curve_return_steps=0)


def middle_obstacle_in_hook_path(origin, target):
    return segment_distance(origin, target, [64.5, 64.5]) <= 3.5


def coaching_engagements(me, allies, enemies, reach):
    pairs = []
    for ally in allies:
        if ally["shield"] or ally["hooked"]:
            continue
        for enemy in enemies:
            if enemy["hooked"] or ally["layer"] != enemy["layer"] or distance(ally, enemy) > 5.5:
                continue
            aim = [(ally[k] + enemy[k]) / 2 for k in ("x", "y")]
            if math.dist([me["x"], me["y"]], aim) <= reach:
                pairs.append((ally["hp"] / ally["max_hp"], distance(me, ally),
                              ally["id"], enemy["id"], aim))
    BUNDLE_COUNTS["engagement_pairs"] += len(pairs)
    return sorted(pairs)


def curve_endpoint(obs, direction):
    """Clip length along the perpendicular ray, preserving its direction."""
    me = obs["self"]
    bounds = [(8., obs["play_west_max"] - 1.) if me["team"] == 0 else
              (obs["play_east_min"] + 1., 119.), (16., 111.)]
    position = [me["x"], me["y"]]
    if any(not lo <= value <= hi for value, (lo, hi) in zip(position, bounds)):
        return None
    length = 8.
    for value, speed, (lo, hi) in zip(position, direction, bounds):
        if speed > 0:
            length = min(length, (hi - value) / speed)
        elif speed < 0:
            length = min(length, (lo - value) / speed)
    if length < .25:
        return None
    return [position[i] + direction[i] * length for i in range(2)], length


def coaching_curve(obs, action, state, recovering, rescue_until):
    me = obs["self"]
    tick = obs["tick"]
    units = [p for p in obs["visible"]["pudges"] if p["alive"]]
    hooks = obs["visible"]["hooks"]
    own = next((h for h in hooks if h["owner_id"] == me["id"]), None)
    ally_ids = {p["id"] for p in units if p["team"] == me["team"]}
    danger = any(h["team"] != me["team"] and h["flying"] and distance(me, h) <= 22 for h in hooks)
    rot_near = any(p["id"] != me["id"] and p["rot"] and distance(me, p) <= 8 for p in units)
    if (not me["alive"] or me["hooked"] or me["layer"] != me["team"] or recovering
            or "blink_to" in action or "attack_target" in action or tick < rescue_until
            or (own is not None and own["victim"] in ally_ids) or danger or rot_near):
        return action, None
    if state is not None and own is None and (state[3] or tick - state[0] > 12):
        state = None
    if state is None:
        if own is not None or "hook_to" not in action:
            return action, None
        dx, dy = action["hook_to"][0] - me["x"], action["hook_to"][1] - me["y"]
        length = math.hypot(dx, dy)
        if length < .01:
            return action, None
        normal = [-dy / length, dx / length]
        enemies = sorted((p for p in units if p["team"] != me["team"] and not p["shield"]),
                         key=lambda p: (distance(me, p), p["id"]))
        guide = [enemies[0]["x"], enemies[0]["y"]] if enemies else [me["x"], 63.5]
        options = []
        for sign in (1, -1):
            direction = [normal[0] * sign, normal[1] * sign]
            endpoint = curve_endpoint(obs, direction)
            if endpoint is not None:
                dest, step = endpoint
                options.append((-step, math.dist(dest, guide), -sign, direction))
        if not options:
            return action, None
        direction = min(options)[3]
        state = (tick, direction[0], direction[1], False)
        BUNDLE_COUNTS["curve_starts"] += 1
    direction = [state[1], state[2]]
    endpoint = curve_endpoint(obs, direction)
    if endpoint is None:
        direction = [-direction[0], -direction[1]]
        endpoint = curve_endpoint(obs, direction)
    if endpoint is None:
        return action, None
    state = (state[0], direction[0], direction[1], state[3] or own is not None)
    BUNDLE_COUNTS["curve_steps"] += 1
    if own is not None:
        BUNDLE_COUNTS["curve_flying_steps" if own["flying"] else "curve_return_steps"] += 1
    return {**action, "walk_to": endpoint[0]}, state


CoachingCorePolicy = BasePolicy


@dataclass
class BasePolicy(CoachingCorePolicy):
    curve_state: tuple | None = None

    def reset(self):
        super().reset()
        self.curve_state = None

    def choose_action(self, obs):
        action = super().choose_action(obs)
        action, self.curve_state = coaching_curve(obs, action, self.curve_state,
                                                self.recovering, self.rescue_until)
        return action
