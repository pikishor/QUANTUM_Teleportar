"""Player: tactical operative of the quantum response unit (graphite/teal armour, cyan practical lights)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from helpers import hexc  # noqa: E402
from humanoid import build  # noqa: E402

STYLE = dict(
    name="player",
    uniform="#42565d", pants="#364a52", carrier="#52666d", carrier2="#3c4f56", glove="#242a2d", boot="#272c30",
    plate="#5d737a", helmet="#5a747c", trim="#6d868d", metal="#5a636a", metal2="#343b41",
    accent=hexc("#18d6ff"), accent_strength=4.0,
    helmet_type="visor", backpack="core", pauldrons=False, bulk=1.0, light_glow=True,
)

if __name__ == "__main__":
    build(STYLE)
