"""Operative: Observer Corp rifleman (charcoal armour, crimson trim, full-face mask with a red optic slit)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from helpers import hexc  # noqa: E402
from humanoid import build  # noqa: E402

STYLE = dict(
    name="operative",
    uniform="#32363b", pants="#2a2d31", carrier="#3e4349", carrier2="#33373c", glove="#1a1c1e", boot="#1c1d1f",
    plate="#4e545c", helmet="#464b53", trim="#8a3039", mask="#30343a", metal="#4a4d52", metal2="#2a2c30",
    accent=hexc("#ff1f33"), accent_strength=4.5,
    helmet_type="full", backpack="plain", pauldrons=True, bulk=1.07, light_glow=False,
)

if __name__ == "__main__":
    build(STYLE)
