"""Shared fixtures and module loading for the session coaching probes."""
import importlib.util
import sys


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def unit(pid, team, x, y):
    return dict(id=pid,team=team,x=x,y=y,hp=1200,max_hp=1200,alive=True,hooked=False,
                shield=0,hook_ready=True,blink_ready=True,rot=False,layer=team,gold=0,
                points=0,in_shop=False,home_x=25 if team==0 else 103,home_y=40,
                upgrades=[0,0,0,0],item_ranks=[0,0,0,0,0],ward_restock=100,buff=0)


def existing_state(policy):
    return {k:v for k,v in vars(policy).items() if k not in ('_hook_history','events')}


