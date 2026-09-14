"""Semantic interventions, executable extraction and explicit rejection boundaries."""
from pathlib import Path
import unittest
from unittest.mock import patch

from coaching.symbolic import skills
from coaching.symbolic.ir import Program, Step, binding_hash, extract, generate, parse, render
from coaching.symbolic.loop import improvement_gate


def observation(tick=0, hp=800):
    def player(id, team, x, y):
        return dict(id=id, team=team, x=x, y=y, hp=hp if id==1 else 800,
                    max_hp=1000, alive=True, shield=0, hooked=False, hook_ready=True,
                    layer=team, in_river=False, home_x=20 if team==0 else 108,
                    home_y=32, upgrades=[0]*4, item_ranks=[0]*5)
    units=[player(1,0,40,32),player(2,0,20,96),player(3,1,80,32)]
    return dict(tick=tick, self=units[0], play_west_max=52, play_east_min=76,
                visible=dict(pudges=units,hooks=[],runes=[]))


def instance(program):
    namespace={}
    exec(generate(program),namespace)
    return namespace['Policy']()


def program(*steps):
    return Program('test_policy',binding_hash(),(Step('STOP UNLESS','alive'),Step('DO','observe'),*steps))


class SymbolicRoundtrip(unittest.TestCase):
    def test_improvement_loop_retains_parent_after_regression_or_inconsistent_gain(self):
        for differences in ([-2,-1,-3,-4],[20,-1,-1,-1],[0,0,0,0]):
            self.assertEqual(improvement_gate('short_lead',differences)[0],'support')
        self.assertEqual(improvement_gate('short_lead',[2,3,4,-1])[0],'short_lead')

    def test_every_authored_policy_extracts_without_documentation(self):
        for path in Path('coaching/policies/executable').glob('*.policy.md'):
            original=parse(path.read_text())
            # Remove the generated docstring and supply no original IR to extraction.
            code='\n'.join(generate(original).splitlines()[1:])
            recovered=extract(code)
            self.assertEqual(generate(recovered),generate(parse(render(recovered))))
            a,b=instance(original),instance(recovered)
            for tick in range(24):
                obs=observation(tick)
                obs['visible']['pudges'][-1]['y']+=tick/2
                self.assertEqual(a.choose_action(obs),b.choose_action(obs))
                self.assertEqual(a.state.__dict__,b.state.__dict__)

    def test_source_edit_changes_recovered_belief_use_and_aim(self):
        original=program(Step('DO','aimed_shot',(('lead',1.0),)))
        edited=generate(original).replace('lead=1.0','lead=0.5')
        recovered=extract(edited)
        self.assertIn('lead=0.5',render(recovered))
        a,b=instance(original),instance(parse(render(recovered)))
        first=observation()
        self.assertEqual(a.choose_action(first),b.choose_action(first))
        moving=observation(8)
        moving['visible']['pudges'][-1]['y']=40
        before=a.choose_action(moving)['hook_to']
        after=b.choose_action(moving)['hook_to']
        self.assertGreater(before[1],after[1])
        self.assertEqual(before[0],after[0])
        self.assertGreater(after[1],40)

    def test_text_coaching_changes_only_threshold_region(self):
        original=program(Step('DO','simple_movement'),Step('DO','reserve_when_hurt'),Step('DO','nearest_shot'))
        edited=parse(render(original).replace('DO observe\n','DO observe(retreat_percent=50)\n'))
        self.assertNotEqual(instance(original).choose_action(observation(hp=400))['walk_to'],[20,32])
        self.assertEqual(instance(edited).choose_action(observation(hp=400)),{'walk_to':[20,32]})
        for hp in (200,800):
            self.assertEqual(instance(original).choose_action(observation(hp=hp)),instance(edited).choose_action(observation(hp=hp)))

    def test_conditional_option_termination_is_executable(self):
        p=program(Step('TRY','rescue',(('coordinated',True),)),Step('DO','aimed_shot'))
        policy=instance(p);obs=observation()
        obs['visible']['pudges'][1].update(x=60,y=50,hp=500,layer=2,in_river=True)
        action=policy.choose_action(obs)
        self.assertEqual(action,{'hook_to':[60,50],'walk_to':[40,32]})
        self.assertNotIn('aimed_shot',[s['skill'] for s in policy.trace])
        # The next decision holds the rescue commitment after the triggering predicate clears.
        obs['tick']=1;obs['visible']['pudges'][1].update(layer=0,in_river=False)
        c=skills.Context(obs,policy.state);skills.observe(c)
        self.assertTrue(skills.sustain_rescue(c))

    def test_code_outside_the_grammar_is_rejected(self):
        source=generate(program(Step('DO','nearest_shot')))
        mutations=[source+"\nprint('unexpected side effect')\n",
                   source.replace("s.invoke(c, 'nearest_shot')","s.invoke(c, 'nearest_shot')\n        c.action['walk_to'] = [0, 0]"),
                   source.replace('return s.finish(c)','return {}',1)]
        for edited in mutations:
            with self.assertRaises(ValueError):extract(edited)

    def test_unsupported_intent_and_out_of_contract_parameters_fail(self):
        for step in (Step('DO','mind_read'),Step('DO','aimed_shot',(('lead',10),)),Step('DO','rescue',(('coordinated',1),))):
            with self.assertRaises(ValueError):generate(program(step))
        with self.assertRaises(ValueError):parse('Think of the game as a continuous exchange.')
        with self.assertRaises(ValueError):parse('```policy-ir\nPOLICY empty\n```')

    def test_shared_binding_is_checked_at_load_time(self):
        source=generate(program(Step('DO','nearest_shot')))
        namespace={};exec(source,namespace)
        with patch.object(skills.Path,'read_bytes',return_value=b'changed implementation'):
            with self.assertRaisesRegex(ValueError,'binding changed'):namespace['Policy']()

    def test_state_is_seat_local_and_resets_between_matches(self):
        a,b=instance(program()),instance(program())
        a.choose_action(observation(100))
        self.assertTrue(a.state.samples)
        self.assertFalse(b.state.samples)
        empty=observation(0);empty['visible']['pudges']=[]
        a.choose_action(empty)
        self.assertFalse(a.state.samples)

    def test_dead_guard_emits_no_actions(self):
        obs=observation();obs['self']['alive']=False
        policy=instance(program(Step('DO','simple_movement'),Step('DO','nearest_shot')))
        self.assertEqual(policy.choose_action(obs),{})
        self.assertEqual([s['skill'] for s in policy.trace],['alive'])


if __name__=='__main__':unittest.main()
