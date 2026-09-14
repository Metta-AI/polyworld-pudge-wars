"""Play alongside a generated textual-IR policy in the native Coworld engine.

python3 -m coaching.symbolic.play --port 8790
Uses the existing WASM renderer; no policy is silently substituted in the voice demo.
"""
import argparse
import asyncio
import json
import os
from pathlib import Path
import secrets
import socket
from urllib.parse import urlencode

from aiohttp import ClientSession, ClientTimeout, WSMsgType, web

from .evaluate import load, prepare

ROOT=Path(__file__).resolve().parents[2]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--policy',type=Path,default=ROOT/'coaching/policies/executable/spatial.policy.md')
    parser.add_argument('--runner',type=Path,default=ROOT/'tmp/coaching/pwcoworld')
    parser.add_argument('--opponent',type=Path,default=ROOT/'coworld/player/base.py')
    parser.add_argument('--port',type=int,default=8790)
    parser.add_argument('--seed',type=int,default=2026)
    parser.add_argument('--n',type=int,choices=range(2,6),default=3)
    parser.add_argument('--autopilot',action='store_true',help='Run every seat; join as spectator.')
    parser.add_argument('--ticks',type=int,default=38400)
    args=parser.parse_args()
    if not args.runner.is_file():parser.error('Build the native host with scripts/coach_demo.sh first.')
    run=ROOT/'tmp/coaching'/('spatial-live-'+secrets.token_hex(5));run.mkdir(parents=True)
    generated,_=prepare(args.policy,run/'artifacts')
    policy_class=load(generated,'live_semantic_policy').Policy
    opponent_class=load(args.opponent,'live_opponent').BasePolicy
    tokens=[secrets.token_urlsafe(24) for _ in range(args.n*2)]
    with socket.socket() as reservation:
        reservation.bind(('127.0.0.1',0));engine_port=reservation.getsockname()[1]
    names=[('You' if i==0 and not args.autopilot else f'IR {i+1}') if i<args.n else f'Red {i-args.n+1}' for i in range(args.n*2)]
    config=dict(tokens=tokens,players=[dict(name=n) for n in names],max_ticks=args.ticks,
                kill_goal=30,seed=args.seed,fog=True,player_connect_timeout_seconds=180)
    config_path=run/'config.json';config_path.write_text(json.dumps(config));config_path.chmod(0o600)
    params=dict(join=f'ws://127.0.0.1:{args.port}/engine/ws',name='You')
    if not args.autopilot:params.update(token=tokens[0],slot='0')
    game_url='/play/pw.html?'+urlencode(params)
    state=dict(phase='starting',tick=0,score=None,policy=str(args.policy),evidence=str(run),errors=[])
    app=web.Application()

    async def lifecycle(app):
        async with ClientSession(timeout=ClientTimeout(total=10)) as client:
            app['client']=client
            env={k:v for k,v in os.environ.items() if not k.startswith(('OPENAI_','COGAME_'))}
            env.update(COGAME_HOST='127.0.0.1',COGAME_PORT=str(engine_port),
                       COGAME_CONFIG_URI=config_path.as_uri(),COGAME_RESULTS_URI=(run/'results.json').as_uri(),
                       COGAME_SAVE_REPLAY_URI=(run/'replay.pwr').as_uri())
            with (run/'engine.log').open('w') as log:
                process=await asyncio.create_subprocess_exec(str(args.runner.resolve()),env=env,cwd=ROOT,stdout=log,stderr=log)
            tasks=[]
            try:
                for _ in range(100):
                    if process.returncode is not None:raise RuntimeError('Native host exited; inspect '+str(run/'engine.log'))
                    try:
                        async with client.get(f'http://127.0.0.1:{engine_port}/healthz') as response:
                            if response.status==200:break
                    except OSError:pass
                    await asyncio.sleep(.05)
                else:raise RuntimeError('Native host did not start')

                async def drive(slot):
                    controller=policy_class() if slot<args.n else opponent_class()
                    query=urlencode(dict(slot=slot,token=tokens[slot]))
                    try:
                        async with client.ws_connect(f'http://127.0.0.1:{engine_port}/player?'+query,heartbeat=20) as ws:
                            async for msg in ws:
                                if msg.type!=WSMsgType.TEXT:continue
                                obs=json.loads(msg.data)
                                if obs.get('done') or obs.get('type')=='final':
                                    state.update(phase='finished',score=obs.get('score'));return
                                if obs.get('type')!='observation':continue
                                state.update(phase='playing',tick=obs['tick'],score=obs.get('score'))
                                await ws.send_json(controller.choose_action(obs))
                    except Exception as error:
                        state['errors'].append(str(error));state['phase']='error'
                        raise

                tasks=[asyncio.create_task(drive(i)) for i in range(0 if args.autopilot else 1,args.n*2)]
                print(f'Game: http://127.0.0.1:{args.port}{game_url}',flush=True)
                print(f'IR and generated policy: http://127.0.0.1:{args.port}/policy',flush=True)
                yield
            finally:
                for task in tasks:task.cancel()
                await asyncio.gather(*tasks,return_exceptions=True)
                if process.returncode is None:
                    process.terminate()
                    try:await asyncio.wait_for(process.wait(),5)
                    except asyncio.TimeoutError:process.kill();await process.wait()

    async def index(request):raise web.HTTPFound(game_url)
    async def status(request):return web.json_response(state)
    async def policy(request):return web.Response(text=(run/'artifacts/input.policy.md').read_text(),content_type='text/plain')
    async def code(request):return web.Response(text=generated.read_text(),content_type='text/plain')
    async def relay_socket(request):
        if request.headers.get('Origin')!=f'http://127.0.0.1:{args.port}':raise web.HTTPForbidden()
        downstream=web.WebSocketResponse(max_msg_size=8*1024*1024);await downstream.prepare(request)
        async with app['client'].ws_connect(f'http://127.0.0.1:{engine_port}/ws',max_msg_size=8*1024*1024) as upstream:
            async def relay(source,destination):
                async for msg in source:
                    if msg.type==WSMsgType.BINARY:await destination.send_bytes(msg.data)
                    elif msg.type==WSMsgType.TEXT:await destination.send_str(msg.data)
                await destination.close()
            tasks=[asyncio.create_task(relay(downstream,upstream)),asyncio.create_task(relay(upstream,downstream))]
            try:await asyncio.wait(tasks,return_when=asyncio.FIRST_COMPLETED)
            finally:
                for task in tasks:task.cancel()
                await asyncio.gather(*tasks,return_exceptions=True)
        return downstream
    app.cleanup_ctx.append(lifecycle)
    app.router.add_get('/',index);app.router.add_get('/api/state',status)
    app.router.add_get('/policy',policy);app.router.add_get('/generated.py',code)
    app.router.add_get('/engine/ws',relay_socket)
    app.router.add_static('/play',ROOT/'examples/pudge_wars/emscripten',show_index=False)
    web.run_app(app,host='127.0.0.1',port=args.port)


if __name__=='__main__':main()
