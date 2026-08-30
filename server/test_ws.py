import asyncio
import json
import websockets


async def main():

    async with websockets.connect(
        "ws://localhost:8000/ws/chat"
    ) as ws:

        print("Connected")

        await ws.send(
            json.dumps({
                "query": "what is stock"
            })
        )

        while True:

            try:
                msg = await ws.recv()

                print(msg)

                if '"done"' in msg:
                    break

            except:
                break


asyncio.run(main())