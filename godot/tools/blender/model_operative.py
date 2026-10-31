"""Operative: Observer Corp rifleman (charcoal armour, crimson trim, full-face mask with a red optic slit)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from helpers import hexc  # noqa: E402
from humanoid import build  # noqa: E402

STYLE = dict(
    name="operative",
    uniform="#474d54", pants="#3b4147", carrier="#575e66", carrier2="#474d55", glove="#2b2f33", boot="#2e3134",
    plate="#6d747d", helmet="#626a74", trim="#b1424e", mask="#454b53", metal="#62666d", metal2="#3a3d42",
    accent=hexc("#ff2038"), emit=1.5,
    mark=hexc("#b9bec2"), stripe=hexc("#b1424e"), patch=hexc("#b1424e"),
    fill_color=(0.72, 0.8, 1.0), fill_energy=1.1, rim_color=(1.0, 0.45, 0.5), rim_energy=1.3,
    helmet_type="full", backpack="plain", pauldrons=True, bulk=1.15, heavy=True, light_glow=False, atlas=1024, bright=1.6,
)

if __name__ == "__main__":
    build(STYLE)
