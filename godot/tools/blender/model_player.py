"""Player: tactical operative of the quantum response unit (graphite/teal armour, cyan practical lights)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from helpers import hexc  # noqa: E402
from humanoid import build  # noqa: E402

STYLE = dict(
    name="player",
    uniform="#4d6269", pants="#3f525a", carrier="#5d7279", carrier2="#465a62", glove="#2b3235", boot="#2f353a",
    plate="#6f868d", helmet="#6a838b", trim="#82989e", metal="#68737a", metal2="#3d464c",
    accent=hexc("#18d6ff"), emit=1.5,
    mark=hexc("#c6d3d6"), stripe=hexc("#d8e2e4"), patch=hexc("#9fd3df"),
    fill_color=(0.62, 0.84, 1.0), fill_energy=1.1, rim_color=(0.35, 0.85, 1.0), rim_energy=1.5,
    helmet_type="visor", backpack="core", pauldrons=False, bulk=1.0, light_glow=True, atlas=1024,
)

if __name__ == "__main__":
    build(STYLE)
