"""Generated symbolic policy support_spatial_12."""
from coaching.symbolic import skills_v2 as s
POLICY_NAME = 'support_spatial_12'
BINDING_HASH = 'b8321385c799af309e2163793d8fea3d3108b762446f49ffdeed748cdbce5fed'

class Policy:
    def __init__(self):
        s.verify_binding(BINDING_HASH)
        self.state = s.State()
        self.trace = []

    def choose_action(self, observation):
        c = s.Context(observation, self.state)
        self.trace = c.trace
        if not s.invoke(c, 'alive'):
            return s.finish(c)
        s.invoke(c, 'observe', retreat_percent=40)
        s.invoke(c, 'remember_roster')
        s.invoke(c, 'economy')
        s.invoke(c, 'combat')
        if s.invoke(c, 'sustain_rescue'):
            return s.finish(c)
        if s.invoke(c, 'rescue', coordinated=True):
            return s.finish(c)
        s.invoke(c, 'blink_defense')
        if s.invoke(c, 'hooked'):
            return s.finish(c)
        s.invoke(c, 'follow_up')
        s.invoke(c, 'close_shot')
        s.invoke(c, 'intercept_hook')
        s.invoke(c, 'swimming_shot')
        s.invoke(c, 'aimed_shot', lead=1.0)
        s.invoke(c, 'rune_shot')
        s.invoke(c, 'fog_shot')
        s.invoke(c, 'formation_positioning', bank_margin=16, lane_spacing=12, rune_window=256)
        s.invoke(c, 'clear_occupied_route', clearance=7, lookahead=12)
        return s.finish(c)
