import * as THREE from 'three';
import { Capacitor } from '@capacitor/core';
import { createWorld } from './world.js';
import { FX, BlobShadows } from './fx.js';
import { Player } from './player.js';
import { Enemies } from './enemies.js';
import { Vehicles } from './vehicles.js';
import { Quantum } from './quantum.js';
import { Missions } from './missions.js';
import { HUD } from './hud.js';
import { initInput, initTouch, pollInput, clearInput, input } from './input.js';
import { initAudio, sfx } from './audio.js';

const $ = id => document.getElementById(id);
const canvas = $('gl'), screenEl = $('screen');
const store = {
  get: k => { try { return localStorage.getItem(k); } catch { return null; } },
  set: (k, v) => { try { localStorage.setItem(k, v); } catch { /* private mode */ } },
};

// ---- renderer / scene -------------------------------------------------------------------------
const renderer = new THREE.WebGLRenderer({ canvas, antialias: false, powerPreference: 'high-performance' });
const scene = new THREE.Scene();
scene.background = new THREE.Color(0x0b0622);
scene.fog = new THREE.Fog(0x140b33, 120, 540);
const camera = new THREE.PerspectiveCamera(72, 1, 0.15, 1800);
scene.add(new THREE.HemisphereLight(0x9a8cff, 0x1c1236, 2.6));
const sun = new THREE.DirectionalLight(0xc8e8ff, 2.4);
sun.position.set(-0.5, 1, 0.6);
scene.add(sun);

const QUAL = [{ name: 'LOW', pr: 1 }, { name: 'MEDIUM', pr: 1.5 }, { name: 'HIGH', pr: 2 }];
let qi = Math.min(2, Math.max(0, +(store.get('qt-quality') ?? 1)));
function resize() {
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, QUAL[qi].pr));
  renderer.setSize(innerWidth, innerHeight, false);
  camera.aspect = innerWidth / innerHeight;
  camera.updateProjectionMatrix();
}
addEventListener('resize', resize);
addEventListener('orientationchange', resize);
resize();

// ---- game object --------------------------------------------------------------------------------
const G = { scene, camera, renderer, time: 0, state: 'menu', heat: 0, quiet: 0, score: 0, best: +store.get('qt-best') || 0 };
G.world = createWorld(scene);
G.fx = new FX(scene);
const shadows = new BlobShadows(scene);
G.player = new Player(G);
G.enemies = new Enemies(G);
G.vehicles = new Vehicles(G);
G.quantum = new Quantum(G);
G.missions = new Missions(G);
G.hud = new HUD(G);
G.vehicles.init();
G.enemies.initPatrols();
G.missions.newRound(6);

G.addHeat = v => { G.heat = Math.min(5, G.heat + v); G.quiet = 0; };

G.explode = (x, y, z, r, o = {}) => {
  const { enemyDmg = 60, carDmg = 60, playerDmg = 30, color = 0xff8a30 } = o, P = G.player;
  G.fx.blast(x, y, z, r, color); G.fx.burst(x, y, z, 50, color, r * 1.4, 0.8, 6);
  G.fx.shake = Math.max(G.fx.shake, Math.min(1, 14 / (Math.hypot(P.pos.x - x, P.pos.z - z) + 6)));
  sfx.boom();
  if (enemyDmg > 0) for (const e of G.enemies.list) {
    if (e.dead) continue;
    const d = Math.hypot(e.pos.x - x, e.pos.z - z), reach = r + e.radius;
    if (d < reach) e.damage(enemyDmg * (1 - 0.6 * d / reach));
  }
  for (const c of G.vehicles.list.slice()) {
    if (c.dead) continue;
    const d = Math.hypot(c.pos.x - x, c.pos.z - z);
    if (d < r + 2) c.damage(carDmg * (1 - 0.6 * d / (r + 2)));
  }
  if (playerDmg > 0 && !P.inCar) {
    const d = Math.hypot(P.pos.x - x, P.pos.z - z);
    if (d < r) P.hurt(playerDmg * (1 - 0.6 * d / r));
  }
};

// ---- screens / state ----------------------------------------------------------------------------
const setState = s => { G.state = s; document.body.dataset.state = s; };
function screen(html) { screenEl.innerHTML = html; screenEl.style.display = html ? 'flex' : 'none'; }
function lockPointer() {
  if (input.touch || !canvas.requestPointerLock) return;
  try { const p = canvas.requestPointerLock(); if (p && p.catch) p.catch(() => {}); } catch { /* unsupported */ }
}

const KEYS = `
  <div class="desk"><div><b>W A S D</b> move · <b>MOUSE</b> aim · <b>CLICK</b> fire · <b>RMB</b> zoom · <b>SHIFT</b> sprint · <b>SPACE</b> jump</div>
  <div><b>Q</b> blink beacon / teleport · <b>E</b> entangle · <b>G</b> superposition · <b>F</b> enter / exit car · <b>R</b> reload</div></div>
  <div class="mob"><div>LEFT thumb: move · RIGHT thumb: aim · <b>FIRE</b> to shoot</div>
  <div><b>BLINK</b> teleport · <b>LINK</b> entangle · <b>SUPER</b> superposition · <b>USE</b> car</div></div>`;

function showMenu() {
  setState('menu');
  screen(`<div class="card"><h1>QUANTUM<br>TELEPORTAR</h1><div class="tag">OPEN-WORLD QUANTUM COMBAT</div>
    <p class="lore">The Observer Corp collapses everything it watches. Stay uncertain. Recover the quantum cores.</p>
    <div class="keys">${KEYS}</div>
    <div><button class="big" id="go">DEPLOY</button></div>
    <div><button class="small" id="gfx">GRAPHICS: ${QUAL[qi].name}</button></div></div>`);
}

function newGame() {
  G.score = 0; G.heat = 0; G.quiet = 0;
  G.player.reset(G.world.spawn.x, G.world.spawn.z);
  G.quantum.reset(); G.enemies.clear(); G.enemies.initPatrols();
  G.missions.clearPickups(); G.missions.newRound(6);
  clearInput(); setState('play'); screen('');
  G.hud.msg('RECOVER THE QUANTUM CORES · FOLLOW THE MAGENTA BEAMS', 4);
}

function respawn() {
  G.player.reset(G.world.spawn.x, G.world.spawn.z);
  G.quantum.reset(); G.enemies.clear(true); G.heat = 0; G.quiet = 0;
  clearInput(); lockPointer(); setState('play'); screen('');
}

function nextSector() {
  G.heat = 0; G.quiet = 0;
  G.player.reset(G.world.spawn.x, G.world.spawn.z);
  G.quantum.reset(); G.enemies.clear(); G.enemies.initPatrols();
  G.missions.clearPickups(); G.missions.newRound(Math.min(9, 6 + G.missions.rounds));
  clearInput(); lockPointer(); setState('play'); screen('');
}

function pause() {
  if (G.state !== 'play') return;
  clearInput(); setState('paused');
  screen('<div class="card"><h1>PAUSED</h1><div><button class="big" id="resume">RESUME</button></div></div>');
  try { document.exitPointerLock?.(); } catch { /* ignore */ }
}
function resume() { lockPointer(); clearInput(); setState('play'); screen(''); }

G.die = () => {
  if (G.state !== 'play') return;
  if (G.score > G.best) { G.best = Math.floor(G.score); store.set('qt-best', G.best); }
  clearInput(); setState('dead');
  try { document.exitPointerLock?.(); } catch { /* ignore */ }
  screen(`<div class="card"><h1 class="bad">DECOHERED</h1><div class="tag">YOU WERE OBSERVED</div>
    <div class="stat">CREDITS ${Math.floor(G.score)} · BEST ${G.best}</div>
    <div><button class="big" id="again">RESPAWN</button></div></div>`);
};

G.win = () => {
  if (G.state !== 'play') return;
  if (G.score > G.best) { G.best = Math.floor(G.score); store.set('qt-best', G.best); }
  clearInput(); setState('win');
  try { document.exitPointerLock?.(); } catch { /* ignore */ }
  screen(`<div class="card"><h1>SECTOR<br>STABILIZED</h1><div class="tag">ALL QUANTUM CORES RECOVERED</div>
    <div class="stat">CREDITS ${Math.floor(G.score)} · BEST ${G.best}</div>
    <div><button class="big" id="next">NEXT SECTOR</button></div></div>`);
};

screenEl.addEventListener('click', e => {
  const id = e.target.id;
  if (id === 'go') { initAudio(); lockPointer(); newGame(); }
  else if (id === 'gfx') { qi = (qi + 1) % QUAL.length; store.set('qt-quality', qi); resize(); e.target.textContent = 'GRAPHICS: ' + QUAL[qi].name; }
  else if (id === 'resume') resume();
  else if (id === 'again') respawn();
  else if (id === 'next') nextSector();
});

// ---- input --------------------------------------------------------------------------------------
initInput(canvas, locked => { if (!locked && G.state === 'play' && !input.touch) pause(); });
if (matchMedia('(pointer: coarse)').matches || Capacitor.isNativePlatform()) {
  initTouch($('touch'));
  document.body.classList.add('touch');
}
document.addEventListener('visibilitychange', () => { if (document.hidden) pause(); });

if (Capacitor.isNativePlatform()) {
  import('@capacitor/screen-orientation').then(m => m.ScreenOrientation.lock({ orientation: 'landscape' })).catch(() => {});
  import('@capacitor/status-bar').then(m => m.StatusBar.hide()).catch(() => {});
}

// ---- loop ---------------------------------------------------------------------------------------
let menuAngle = 0;
function menuCamera(dt) {
  menuAngle += dt * 0.08;
  camera.fov = 62; camera.updateProjectionMatrix();
  camera.position.set(Math.cos(menuAngle) * 130, 48, Math.sin(menuAngle) * 130);
  camera.lookAt(0, 22, 0);
}

function heatTick(dt) {
  const P = G.player;
  const aware = G.enemies.list.some(e => !e.dead && e.aware && Math.hypot(e.pos.x - P.pos.x, e.pos.z - P.pos.z) < 70);
  G.quiet = aware ? 0 : G.quiet + dt;
  if (G.quiet > 7 && G.heat > 0) G.heat = Math.max(0, G.heat - 0.12 * dt);
}

function step(dt) {
  G.time += dt;
  pollInput();
  if (G.state === 'play') {
    G.player.update(dt);
    G.vehicles.update(dt);
    G.quantum.update(dt);
    G.enemies.update(dt);
    G.missions.update(dt);
    heatTick(dt);
    G.hud.update(dt);
  } else if (G.state === 'menu') {
    menuCamera(dt);
    G.vehicles.update(dt);
  }
  G.fx.update(dt);
}

function render() {
  shadows.begin();
  const P = G.player;
  if (P.mesh.visible) shadows.add(P.pos.x, P.pos.y, P.pos.z, 1.3);
  for (const c of G.vehicles.list) if (!c.dead) shadows.add(c.pos.x, 0, c.pos.z, 2.6, 5, c.heading);
  for (const e of G.enemies.list) if (!e.dead) shadows.add(e.pos.x, 0, e.pos.z, 1.7 * e.T.scale);
  shadows.end();
  renderer.render(scene, camera);
}

let last = performance.now();
function frame(now) {
  const dt = Math.min(0.05, Math.max(0, (now - last) / 1000));
  last = now;
  step(dt);
  render();
  requestAnimationFrame(frame);
}

showMenu();
requestAnimationFrame(frame);

if (import.meta.env.DEV || location.hash.includes('debug')) window.__qt = { G, step, render, input, THREE };
