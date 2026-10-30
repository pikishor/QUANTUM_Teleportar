"""Player: tactical operative of the quantum response unit (graphite/teal armour, cyan practical lights)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from helpers import hexc  # noqa: E402
from humanoid import build  # noqa: E402

STYLE = dict(
    name="player",
    uniform="#34444a", pants="#2b3a40", carrier="#3d4d52", carrier2="#2f3f45", glove="#1b2022", boot="#1d2124",
    plate="#4a5d63", helmet="#4a6168", trim="#5a6f75", metal="#50585e", metal2="#2e3439",
    accent=hexc("#18d6ff"), accent_strength=4.0,
    helmet_type="visor", backpack="core", pauldrons=False, bulk=1.0, light_glow=True,
)

if __name__ == "__main__":
    build(STYLE)
