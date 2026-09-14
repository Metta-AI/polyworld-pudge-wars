"""Coaching intent must hold independently of exact code/IR round trips."""
from copy import deepcopy
from dataclasses import replace
from pathlib import Path
import unittest

from coaching.symbolic import skills, skills_v2
from coaching.symbolic.ir import Program, Step, binding_hash, extract, generate, parse, render
from coaching.symbolic.spatial import SpatialMetrics
from coaching.symbolic.search import check_proposal, propose


ROOT = Path(__file__).resolve().parents[1]


def observation(team=0, tick=0):
    players = [dict(id=i+1, team=0, x=x, y=y, home_x=20, home_y=home,
                    hp=800, max_hp=1000, alive=True, shield=0, hooked=False,
                    layer=0, in_river=False, hook_ready=True, blink_ready=False,
                    upgrades=[0]*4, item_ranks=[0]*5, gold=0, rot=False)
               for i, (x,y,home) in enumerate([(20,40,40),(20,46,64),(26,43,88)])]
    if team:
        for p in players:
            p.update(team=1, layer=1, x=128-p['x'], home_x=108)
    return dict(tick=tick, self=players[0], play_west_max=52, play_east_min=76,
                visible=dict(pudges=players, hooks=[], runes=[]), rune_next=dict(soon=120,x=64,y=16))


def instance(program):
    namespace={}
    exec(generate(program), namespace)
    return namespace['Policy']()


def candidate():
    return parse((ROOT/'coaching/policies/executable/spatial.policy.md').read_text())


class SpatialCoaching(unittest.TestCase):
    def test_old_binding_and_archived_control_stay_valid(self):
        self.assertEqual(binding_hash(), 'f7cea6a0203afec157813d7a385f95af862e8240113dfcf1445b851402dd96ae')
        old = parse((ROOT/'coaching/policies/executable/support.policy.md').read_text())
        self.assertEqual(extract(generate(old)).binding_version, skills.VERSION)

    def test_code_to_ir_to_code_keeps_new_concepts_and_actual_decisions(self):
        p=candidate()
        recovered=extract(generate(p))
        a,b=instance(p),instance(parse(render(recovered)))
        self.assertIn('clear_occupied_route', [s.skill for s in recovered.steps])
        for tick in range(100):
            obs=observation(tick=tick)
            self.assertEqual(a.choose_action(obs),b.choose_action(obs))
            self.assertEqual(a.state.__dict__,b.state.__dict__)

    def test_rune_has_one_owner_and_teammates_keep_distinct_lanes(self):
        for team in (0,1):
            obs=observation(team)
            destinations=[]
            collectors=[]
            for me in obs['visible']['pudges']:
                obs['self']=me
                c=skills.Context(obs,skills_v2.State())
                skills.observe(c)
                skills_v2.remember_roster(c)
                c.action={'walk_to':[36 if not team else 92,16]}
                skills_v2.spread_formation(c)
                destinations.append(c.action['walk_to'][1])
                collectors.append(c.formation['rune_collector'])
            self.assertEqual(len(set(collectors)),1)
            self.assertEqual(sum(y==24 for y in destinations),1)
            self.assertGreaterEqual(min(abs(a-b) for i,a in enumerate(destinations) for b in destinations[i+1:]),20)

    def test_death_does_not_renumber_the_remaining_lanes(self):
        obs=observation();obs['rune_next']['soon']=0
        state=skills_v2.State()
        def lane():
            c=skills.Context(obs,state);skills_v2.remember_roster(c)
            c.action={'walk_to':[36,64]};skills_v2.spread_formation(c)
            return c.formation['lane']
        before=lane()
        obs['visible']['pudges'][1]['alive']=False
        self.assertEqual(before,lane())
        obs['visible']['pudges'].pop(1)
        self.assertEqual(before,lane())

    def test_body_directly_ahead_affords_an_inland_detour_on_either_bank(self):
        for team in (0,1):
            obs=observation(team)
            obs['visible']['pudges']=obs['visible']['pudges'][:2]
            c=skills.Context(obs,skills_v2.State());skills.observe(c)
            c.action={'walk_to':[obs['self']['x'],88], 'hook_to':[80,32]}
            before=deepcopy(c.action)
            self.assertTrue(skills_v2.clear_occupied_route(c))
            self.assertGreater((c.action['walk_to'][0]-obs['self']['x'])*(-1 if team else 1),0)
            self.assertEqual(c.action['hook_to'],before['hook_to'])
            self.assertGreaterEqual(skills.segment((obs['self']['x'],obs['self']['y']),c.action['walk_to'],(obs['visible']['pudges'][1]['x'],46)),5.2)

    def test_moving_away_from_a_close_body_does_not_trigger_detour(self):
        obs=observation();obs['visible']['pudges']=obs['visible']['pudges'][:2]
        c=skills.Context(obs,skills_v2.State());c.action={'walk_to':[20,24]}
        self.assertFalse(skills_v2.clear_occupied_route(c))
        self.assertEqual(c.action['walk_to'],[20,24])

    def test_urgent_movement_and_nonwalk_channels_are_preserved(self):
        original=parse((ROOT/'coaching/policies/executable/support.policy.md').read_text())
        for condition in ('dead','hurt','hooked','river','incoming','rescue','melee'):
            obs=observation()
            if condition=='dead':obs['self']['alive']=False
            elif condition=='hurt':obs['self']['hp']=200
            elif condition=='hooked':obs['self']['hooked']=True
            elif condition=='river':obs['self'].update(layer=2,in_river=True)
            elif condition=='incoming':obs['visible']['hooks']=[dict(id=30,team=1,owner_id=8,victim=0,x=30,y=45,flying=True)]
            elif condition=='rescue':
                obs['visible']['pudges'][1].update(layer=2,in_river=True,hp=200,x=60,y=60)
                obs['visible']['pudges'][2].update(x=20,y=100)
            else:
                enemy=deepcopy(obs['self']);enemy.update(id=8,team=1,x=24,hp=100,shield=0)
                obs['visible']['pudges'].append(enemy)
            self.assertEqual(instance(original).choose_action(obs),instance(candidate()).choose_action(obs),condition)

    def test_metrics_detect_contact_and_an_occupied_route_without_policy_traces(self):
        obs=observation();obs['visible']['pudges'][1]['y']=45.3
        m=SpatialMetrics();m.observe(obs,{'walk_to':[20,88]})
        r=m.report()
        self.assertEqual(r['contact_fraction'],1)
        self.assertEqual(r['occupied_route_fraction'],1)
        self.assertEqual(r['wall_contact_fraction'],1)

    def test_v1_cannot_silently_use_v2_skills(self):
        p=candidate()
        with self.assertRaisesRegex(ValueError,'unavailable'):
            generate(replace(p,binding_version=skills.VERSION,binding_hash=binding_hash()))

    def test_positioning_optimization_preserves_the_composed_skill_semantics(self):
        for team in (0,1):
            for kind in ('routine','shop','ward','foreign_bank','hurt','solo'):
                obs=observation(team)
                if kind=='shop':obs['self']['gold']=15
                if kind=='ward':obs['self'].update(ward_restock=0,item_ranks=[0,0,0,0,1])
                if kind=='foreign_bank':obs['self']['layer']=1-team
                if kind=='hurt':obs['self']['hp']=100
                if kind=='solo':obs['visible']['pudges']=[obs['self']]
                a,b=[skills.Context(deepcopy(obs),skills_v2.State()) for _ in range(2)]
                for c in (a,b):
                    skills.observe(c);skills.combat(c);skills_v2.remember_roster(c)
                skills.tactical_movement(a);skills.ward(a);skills_v2.spread_formation(a)
                skills_v2.formation_positioning(b)
                self.assertEqual(a.action,b.action,(team,kind))

    def test_future_search_can_edit_the_new_movement_ir(self):
        choices=propose(candidate(),set(),10)
        self.assertIn('wider_lanes',[p.name for p in choices])
        self.assertIn('closer_bank',[p.name for p in choices])
        for proposal in choices:
            self.assertTrue(check_proposal(candidate(),proposal)['passed'])


if __name__=='__main__':unittest.main()
