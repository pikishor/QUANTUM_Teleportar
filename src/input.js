// One input state for keyboard+mouse and touch. Look deltas are returned in radians.
export const input = { mx: 0, my: 0, fire: false, aim: false, sprint: false, jumpHeld: false, touch: false, locked: false };

const keys = new Set(), pressed = new Set();
const stick = { id: -1, ox: 0, oy: 0, x: 0, y: 0 };
let lookX = 0, lookY = 0, touchJump = false, lockedAt = 0;
let onLock = () => {};

const KEYMAP = { Space: 'jump', KeyQ: 'blink', KeyE: 'entangle', KeyG: 'superpos', KeyR: 'reload', KeyF: 'interact' };

export const consume = name => pressed.delete(name);
export function takeLook() { const r = { x: lookX, y: lookY }; lookX = lookY = 0; return r; }
export function press(name) { pressed.add(name); }
export function clearInput() {
  keys.clear(); pressed.clear();
  input.fire = input.aim = input.sprint = input.jumpHeld = touchJump = false;
  stick.id = -1; stick.x = stick.y = 0; lookX = lookY = 0;
}

export function pollInput() {
  const k = c => keys.has(c);
  let mx = (k('KeyD') || k('ArrowRight') ? 1 : 0) - (k('KeyA') || k('ArrowLeft') ? 1 : 0) + stick.x;
  let my = (k('KeyW') || k('ArrowUp') ? 1 : 0) - (k('KeyS') || k('ArrowDown') ? 1 : 0) + stick.y;
  const m = Math.hypot(mx, my);
  if (m > 1) { mx /= m; my /= m; }
  input.mx = mx; input.my = my;
  input.sprint = k('ShiftLeft') || k('ShiftRight') || Math.hypot(stick.x, stick.y) > 0.92;
  input.jumpHeld = k('Space') || touchJump;
}

export function initInput(canvas, onLockChange) {
  onLock = onLockChange;
  addEventListener('keydown', e => {
    if (['Space', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(e.code)) e.preventDefault();
    if (e.repeat) return;
    keys.add(e.code);
    if (KEYMAP[e.code]) pressed.add(KEYMAP[e.code]);
  });
  addEventListener('keyup', e => keys.delete(e.code));
  addEventListener('blur', clearInput);
  canvas.addEventListener('mousedown', e => {
    if (!input.locked) return;
    if (e.button === 0) input.fire = true;
    if (e.button === 2) input.aim = true;
  });
  addEventListener('mouseup', e => {
    if (e.button === 0) input.fire = false;
    if (e.button === 2) input.aim = false;
  });
  // Chromium can report a huge movementX on the first event after the lock engages: drop that burst and clamp spikes.
  addEventListener('mousemove', e => {
    if (!input.locked || performance.now() - lockedAt < 200) return;
    lookX += Math.max(-120, Math.min(120, e.movementX)) * 0.0022;
    lookY += Math.max(-120, Math.min(120, e.movementY)) * 0.0022;
  });
  addEventListener('contextmenu', e => e.preventDefault());
  document.addEventListener('pointerlockchange', () => {
    input.locked = document.pointerLockElement === canvas;
    lockedAt = performance.now(); lookX = lookY = 0;
    onLock(input.locked);
  });
}

const BUTTONS = [
  { id: 'fire', label: 'FIRE', hold: 'fire' },
  { id: 'jump', label: 'JUMP', press: 'jump', hold: 'jump' },
  { id: 'blink', label: 'BLINK', press: 'blink' },
  { id: 'link', label: 'LINK', press: 'entangle' },
  { id: 'super', label: 'SUPER', press: 'superpos' },
  { id: 'reload', label: '↻', press: 'reload' },
  { id: 'aim', label: 'AIM', toggle: 'aim' },
  { id: 'use', label: 'USE', press: 'interact' },
];

export function initTouch(root) {
  input.touch = true;
  root.classList.add('on');
  root.innerHTML = '<div class="zone" id="zl"></div><div class="zone" id="zr"></div><div id="stick"><i></i></div>' +
    BUTTONS.map(b => `<button class="tb" id="b-${b.id}">${b.label}</button>`).join('');
  const knob = root.querySelector('#stick'), dot = knob.firstChild;

  const zl = root.querySelector('#zl');
  zl.addEventListener('pointerdown', e => {
    if (stick.id >= 0) return;
    stick.id = e.pointerId; stick.ox = e.clientX; stick.oy = e.clientY;
    zl.setPointerCapture(e.pointerId);
    knob.style.cssText = `display:block;left:${e.clientX - 55}px;top:${e.clientY - 55}px`;
    dot.style.transform = '';
  });
  zl.addEventListener('pointermove', e => {
    if (e.pointerId !== stick.id) return;
    let dx = (e.clientX - stick.ox) / 55, dy = (e.clientY - stick.oy) / 55;
    const m = Math.hypot(dx, dy); if (m > 1) { dx /= m; dy /= m; }
    stick.x = dx; stick.y = -dy;
    dot.style.transform = `translate(${dx * 38}px,${dy * 38}px)`;
  });
  const endStick = e => {
    if (e.pointerId !== stick.id) return;
    stick.id = -1; stick.x = stick.y = 0; knob.style.display = 'none';
  };
  zl.addEventListener('pointerup', endStick); zl.addEventListener('pointercancel', endStick);

  const zr = root.querySelector('#zr');
  let lid = -1, lx = 0, ly = 0;
  zr.addEventListener('pointerdown', e => { if (lid >= 0) return; lid = e.pointerId; lx = e.clientX; ly = e.clientY; zr.setPointerCapture(e.pointerId); });
  zr.addEventListener('pointermove', e => {
    if (e.pointerId !== lid) return;
    lookX += (e.clientX - lx) * 0.0055; lookY += (e.clientY - ly) * 0.0055; lx = e.clientX; ly = e.clientY;
  });
  const endLook = e => { if (e.pointerId === lid) lid = -1; };
  zr.addEventListener('pointerup', endLook); zr.addEventListener('pointercancel', endLook);

  for (const b of BUTTONS) {
    const el = root.querySelector('#b-' + b.id);
    const down = e => {
      e.preventDefault(); el.setPointerCapture(e.pointerId); el.classList.add('down');
      if (b.press) pressed.add(b.press);
      if (b.hold === 'fire') input.fire = true;
      if (b.hold === 'jump') touchJump = true;
      if (b.toggle) { input.aim = !input.aim; el.classList.toggle('on', input.aim); }
    };
    const up = () => {
      el.classList.remove('down');
      if (b.hold === 'fire') input.fire = false;
      if (b.hold === 'jump') touchJump = false;
    };
    el.addEventListener('pointerdown', down);
    el.addEventListener('pointerup', up); el.addEventListener('pointercancel', up);
  }
}

export const touchButton = (id, show) => document.getElementById('b-' + id)?.classList.toggle('hide', !show);
