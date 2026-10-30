"""Operative: Observer Corp rifleman (charcoal armour, crimson trim, full-face mask with a red optic slit)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from helpers import hexc  # noqa: E402
from humanoid import build  # noqa: E402

STYLE = dict(
    name="operative",
    uniform="#40454b", pants="#353a3f", carrier="#4f555c", carrier2="#41464c", glove="#25282b", boot="#2a2c2f",
    plate="#646b74", helmet="#58606a", trim="#a63b46", mask="#3c4148", metal="#555960", metal2="#33363b",
    accent=hexc("#ff1f33"), accent_strength=4.5,
    helmet_type="full", backpack="plain", pauldrons=True, bulk=1.07, light_glow=False,
)

if __name__ == "__main__":
    build(STYLE)
