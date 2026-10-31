"""Player: tactical operative of the quantum response unit (graphite/teal armour, cyan practical lights)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from helpers import hexc  # noqa: E402
from humanoid import build  # noqa: E402

STYLE = dict(
    name="player",
    uniform="#59666c", pants="#45515a", carrier="#6a777d", carrier2="#4f5c63", glove="#2d3336", boot="#31373b",
    plate="#7c8a91", helmet="#76868d", trim="#8e9da3", metal="#6c767c", metal2="#40484d",
    accent=hexc("#18d6ff"), emit=1.5,
    mark=hexc("#c6d3d6"), stripe=hexc("#d8e2e4"), patch=hexc("#9fd3df"),
    fill_color=(0.62, 0.84, 1.0), fill_energy=1.1, rim_color=(0.35, 0.85, 1.0), rim_energy=1.5,
    helmet_type="visor", backpack="core", pauldrons=False, bulk=1.08, light_glow=True, atlas=1024, bright=1.7,
)

if __name__ == "__main__":
    build(STYLE)
