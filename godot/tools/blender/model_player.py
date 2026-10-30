"""Player: tactical operative of the quantum response unit (graphite/teal armour, cyan practical lights)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from helpers import hexc  # noqa: E402
from humanoid import build  # noqa: E402

STYLE = dict(
    name="player",
    uniform="#222c30", pants="#1c2428", carrier="#2b363a", carrier2="#232d31", glove="#15191b", boot="#14171a",
    plate="#2a3a3e", helmet="#2f4044", trim="#3b4d51", metal="#3a4146", metal2="#23282c",
    accent=hexc("#18d6ff"), accent_strength=4.0,
    helmet_type="visor", backpack="core", pauldrons=False, bulk=1.0, light_glow=True,
)

if __name__ == "__main__":
    build(STYLE)
