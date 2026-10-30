import { HALF, ROAD, roadCenters } from './world.js';
import { touchButton, input } from './input.js';

const $ = id => document.getElementById(id);

export class HUD {
  constructor(G) {
    this.G = G;
    this.e = Object.fromEntries(['hp', 'en', 'hpl', 'ammo', 'heat', 'credits', 'obj', 'msg', 'hint', 'hitm', 'vig', 'feed', 'mini', 'xhair', 'ak', 'al', 'as'].map(k => [k, $(k)]));
    this.ctx = this.e.mini.getContext('2d');
    this.msgT = 0; this.hitT = 0; this.vig = 0; this.mapT = 0; this.slow = 0;
  }

  msg(text, dur = 2) { this.e.msg.textContent = text; this.msgT = dur; this.e.msg.style.opacity = 1; }

  feed(text) {
    const d = document.createElement('div');
    d.textContent = text; this.e.feed.prepend(d);
    while (this.e.feed.children.length > 4) this.e.feed.lastChild.remove();
    setTimeout(() => d.remove(), 3200);
  }

  hitMarker(kill) { this.e.hitm.className = kill ? 'kill' : ''; this.e.hitm.style.opacity = 1; this.hitT = 0.16; }
  damage(a) { this.vig = Math.min(1, this.vig + a); }

  update(dt) {
    const G = this.G, P = G.player, e = this.e, car = P.inCar;
    if (this.msgT > 0) { this.msgT -= dt; if (this.msgT < 0.5) e.msg.style.opacity = Math.max(0, this.msgT * 2); }
    if (this.hitT > 0) { this.hitT -= dt; if (this.hitT <= 0) e.hitm.style.opacity = 0; }
    if (this.vig > 0 || e.vig.style.opacity !== '0') { this.vig = Math.max(0, this.vig - dt * 1.4); e.vig.style.opacity = this.vig + (P.hp < 30 && !car ? 0.25 + 0.15 * Math.sin(G.time * 6) : 0); }

    this.slow -= dt;
    if (this.slow <= 0) {
      this.slow = 0.05;
      e.hp.style.width = (car ? car.hp / car.maxHp : P.hp / P.maxHp) * 100 + '%';
      e.hpl.textContent = car ? 'VEHICLE' : 'INTEGRITY';
      e.en.style.width = (P.energy / P.maxEnergy) * 100 + '%';
      e.ammo.textContent = car ? `${Math.round(Math.abs(car.speed) * 3.6)} km/h` : P.reload > 0 ? 'RELOADING' : `${P.ammo} / ∞`;
      const s = Math.ceil(G.heat - 0.001);
      e.heat.textContent = '★'.repeat(s) + '☆'.repeat(5 - s);
      e.heat.className = s > 0 ? 'on' : '';
      e.credits.textContent = `CREDITS ${Math.floor(G.score)}`;
      const n = G.missions.nearest(car ? car.pos : P.pos);
      e.obj.textContent = n ? `RECOVER QUANTUM CORES  ${G.missions.got}/${G.missions.total}\nNEAREST ${Math.round(n.dist)} m` : 'SECTOR CLEAR';
      const near = !car && P.pos.y < 2 && G.vehicles.nearest(P.pos);
      e.hint.textContent = car ? (input.touch ? '' : 'F — EXIT VEHICLE') : near ? (input.touch ? '' : 'F — ENTER VEHICLE') : '';
      touchButton('use', !!car || !!near);
      const Q = G.quantum;
      e.ak.className = Q.beacon ? 'act' : P.energy >= 15 && Q.cd.blink <= 0 ? 'rdy' : '';
      e.ak.textContent = Q.beacon ? '[Q] TELEPORT' : '[Q] BLINK';
      e.al.className = P.energy >= 25 && Q.cd.link <= 0 ? 'rdy' : '';
      e.as.className = Q.clone ? 'act' : P.energy >= 35 && Q.cd.super <= 0 ? 'rdy' : '';
      e.as.textContent = Q.clone ? '[G] COLLAPSE' : '[G] SUPERPOSE';
      e.xhair.style.display = car ? 'none' : 'block';
      e.xhair.style.setProperty('--s', 1 + (P.spread * 40 + (P.aiming ? 0 : 0.6)) * (P.aiming ? 0.5 : 1));
    }
    this.mapT -= dt;
    if (this.mapT <= 0) { this.mapT = 1 / 14; this.drawMap(); }
  }

  drawMap() {
    const G = this.G, P = G.player, c = this.ctx, S = 150, k = 0.85, W = G.world;
    const cy = Math.cos(P.camYaw), sy = Math.sin(P.camYaw);
    const sx = (x, z) => S / 2 + ((x - P.pos.x) * cy - (z - P.pos.z) * sy) * k;
    const sz = (x, z) => S / 2 + ((x - P.pos.x) * sy + (z - P.pos.z) * cy) * k;
    c.clearRect(0, 0, S, S);
    c.save();
    c.beginPath(); c.arc(S / 2, S / 2, S / 2 - 1, 0, 7); c.clip();
    c.fillStyle = 'rgba(6,4,18,.88)'; c.fillRect(0, 0, S, S);
    c.translate(S / 2, S / 2); c.scale(k, k); c.rotate(P.camYaw); c.translate(-P.pos.x, -P.pos.z);
    c.fillStyle = '#2b2650';
    for (const r of roadCenters) { c.fillRect(-HALF - ROAD / 2, r - ROAD / 2, 2 * HALF + ROAD, ROAD); c.fillRect(r - ROAD / 2, -HALF - ROAD / 2, ROAD, 2 * HALF + ROAD); }
    c.fillStyle = '#120f26';
    for (const b of W.boxes) c.fillRect(b.x0, b.z0, b.x1 - b.x0, b.z1 - b.z0);
    c.restore();

    c.save();
    c.beginPath(); c.arc(S / 2, S / 2, S / 2 - 1, 0, 7); c.clip();
    const dot = (x, z, r, col) => { c.fillStyle = col; c.beginPath(); c.arc(sx(x, z), sz(x, z), r, 0, 7); c.fill(); };
    for (const v of G.vehicles.list) if (!v.dead && v !== P.inCar) dot(v.pos.x, v.pos.z, 2, 'rgba(100,170,255,.8)');
    for (const p of G.missions.pickups) dot(p.mesh.position.x, p.mesh.position.z, 2.2, p.kind === 'health' ? '#44ff88' : '#4ff0ff');
    for (const e of G.enemies.list) if (!e.dead && e.aware) dot(e.pos.x, e.pos.z, 3, '#ff4466'); else if (!e.dead) dot(e.pos.x, e.pos.z, 2, '#a04058');
    if (G.quantum.beacon) dot(G.quantum.beacon.pos.x, G.quantum.beacon.pos.z, 3.5, '#4ff0ff');
    if (G.quantum.clone) dot(G.quantum.clone.pos.x, G.quantum.clone.pos.z, 3.5, '#66ffee');
    for (const core of G.missions.cores) {          // clamp to the rim so they always point the way
      let x = sx(core.x, core.z) - S / 2, y = sz(core.x, core.z) - S / 2;
      const d = Math.hypot(x, y), m = S / 2 - 8;
      if (d > m) { x *= m / d; y *= m / d; }
      c.fillStyle = '#ff5af0'; c.save(); c.translate(S / 2 + x, S / 2 + y); c.rotate(Math.PI / 4); c.fillRect(-3.5, -3.5, 7, 7); c.restore();
    }
    c.fillStyle = '#fff'; c.beginPath(); c.moveTo(S / 2, S / 2 - 7); c.lineTo(S / 2 + 5, S / 2 + 5); c.lineTo(S / 2, S / 2 + 2); c.lineTo(S / 2 - 5, S / 2 + 5); c.closePath(); c.fill();
    c.restore();
  }
}
