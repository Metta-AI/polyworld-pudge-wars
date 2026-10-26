"""Local session transport for the frozen league policy, with explicit round resets."""
import asyncio
import json
import os

import websockets
from coworld.player import player


async def main():
    round_id = None
    async with websockets.connect(os.environ['COWORLD_PLAYER_WS_URL'], ping_timeout=None) as ws:
        async for raw in ws:
            observation = json.loads(raw)
            if observation.get('type') != 'observation':
                continue
            current = observation.get('coaching_round')
            if current != round_id:
                player.reset_memory()
                round_id = current
            if observation.get('done'):
                continue
            action = player.choose_action(observation)
            if current is not None:
                action['coaching_round'] = current
            await ws.send(json.dumps(action))


if __name__ == '__main__':
    asyncio.run(main())
