import * as THREE from 'three';
import { rand, pick, damp, dampAngle } from './util.js';
import { ENEMY, enemyMesh } from './models.js';
import { sfx } from './audio.js';

const _t = new THREE.Vector3(), _a = new THREE.Vector3(), _b = new THREE.Vector3();
const boltGeo = new THREE.SphereGeometry(0.22, 8, 6);
const boltMats = {};
const barGeo = new THREE.PlaneGeometry(1, 0.12).translate(0.5, 0, 0);
const barFg = new THREE.MeshBasicMaterial({ color: 0xff4466 }), barBg = new THREE.MeshBasicMaterial({ color: 0x220a18 });

class Enemy {
  constructor(G, type, x, z, opts = {}) {
    this.G = G; this.type = type; this.T = ENEMY[type];
    this.hp = this.maxHp = this.T.hp; this.radius = this.T.radius;
    this.pos = new THREE.Vector3(x, 0, z); this.home = { x, z };
    this.yaw = rand(0, 6.28); this.t = rand(0, 10);
    this.aware = !!opts.aware; this.reinforce = !!opts.reinforce;
    this.fireT = rand(0.5, 1.5); this.retarget = 0; this.target = 'player'; this.los = false; this.losT = 0;
    this.strafe = Math.random() < 0.5 ? 1 : -1; this.strafeT = rand(1, 3); this.wanderT = 0; this.wdir = rand(0, 6.28);
    this.dead = false; this.deadT = 0; this.remove = false; this.linked = null; this.barT = 0;
    this.mesh = enemyMesh(type); G.scene.add(this.mesh);
    this.bar = new THREE.Group();
    const bg = new THREE.Mesh(barGeo, barBg), fg = new THREE.Mesh(barGeo, barFg);
    bg.scale.x = 1.4; bg.position.set(-0.7, 0, 0); fg.position.set(-0.7, 0, 0.002); fg.scale.x = 1.4;
    this.bar.add(bg, fg); this.fg = fg; this.bar.visible = false; G.scene.add(this.bar);
  }

  center(out) { return out.set(this.pos.x, this.pos.y + 0.95 * this.T.scale, this.pos.z); }

  damage(d, crit = false, mirrored = false) {
    if (this.dead) return;
    const G = this.G;
    this.hp -= d; this.aware = true; this.barT = 3;
    G.fx.burst(this.pos.x, this.pos.y + 1, this.pos.z, 4, this.T.color, 4, 0.25, 4); sfx.hit();
    if (!mirrored) {
      for (const e of G.enemies.list) if (!e.dead && e !== this && !e.aware && Math.hypot(e.pos.x - this.pos.x, e.pos.z - this.pos.z) < 35) e.aware = true;
      if (this.linked && !this.linked.dead) { this.linked.damage(d, false, true); G.fx.burst(this.linked.pos.x, this.linked.pos.y + 1, this.linked.pos.z, 8, 0x7ffaff, 6, 0.4, 2); }
    }
    if (this.hp <= 0) this.die();
  }

  die() {
    const G = this.G, T = this.T;
    this.dead = true; this.bar.visible = false; this.linked = null;
    G.fx.burst(this.pos.x, this.pos.y + 1, this.pos.z, 30, T.color, 9, 0.8, 10);
    G.fx.blast(this.pos.x, this.pos.y + 1, this.pos.z, 2.5 * T.scale, T.color, 0.35);
    sfx.boom();
    G.score += T.score; G.player.energy = Math.min(G.player.maxEnergy, G.player.energy + 8); G.addHeat(T.heat);
    G.hud.feed(`${this.type.toUpperCase()} DESTROYED  +${T.score}`);
    const r = Math.random();
    if (r < 0.3) G.missions.drop('health', this.pos.x, this.pos.z); else if (r < 0.6) G.missions.drop('energy', this.pos.x, this.pos.z);
  }

  update(dt) {
    const G = this.G, T = this.T, P = G.player;
    if (this.dead) {
      this.deadT += dt;
      this.mesh.rotation.z += dt * 4; this.mesh.position.y -= dt * 2.5; this.mesh.scale.multiplyScalar(1 - dt * 1.2);
      if (this.deadT > 0.7) this.remove = true;
      return;
    }
    this.t += dt;
    this.retarget -= dt;
    if (this.retarget <= 0) { this.retarget = rand(0.6, 1.4); this.target = G.quantum.clone && Math.random() < 0.5 ? 'clone' : 'player'; }
    const clone = this.target === 'clone' ? G.quantum.clone : null;
    if (clone) _t.set(clone.pos.x, clone.pos.y + 1, clone.pos.z); else P.chest(_t);
    const dx = _t.x - this.pos.x, dz = _t.z - this.pos.z, d = Math.hypot(dx, dz) || 1e-3;
    if (!this.aware && (d < 32 || (G.heat > 0 && d < 80))) this.aware = true;

    let mx = 0, mz = 0, speed = 0;
    if (!this.aware) {
      this.wanderT -= dt;
      if (this.wanderT <= 0) { this.wanderT = rand(2, 5); this.wdir = Math.random() < 0.4 ? rand(0, 6.28) : Math.atan2(this.home.x - this.pos.x, this.home.z - this.pos.z) - Math.PI; }
      const hd = Math.hypot(this.home.x - this.pos.x, this.home.z - this.pos.z);
      if (hd < 14) { mx = -Math.sin(this.wdir); mz = -Math.cos(this.wdir); speed = 1.4; } else { mx = (this.home.x - this.pos.x) / hd; mz = (this.home.z - this.pos.z) / hd; speed = 2.5; }
      this.yaw = dampAngle(this.yaw, Math.atan2(-mx, -mz), 3, dt);
    } else {
      this.losT -= dt;
      if (this.losT <= 0) { this.losT = rand(0.25, 0.4); this.los = d < 90 && G.world.los(this.center(_a), _t); }
      this.yaw = dampAngle(this.yaw, Math.atan2(-dx, -dz), 9, dt);
      const ux = dx / d, uz = dz / d;
      if (T.kamikaze) { mx = ux; mz = uz; speed = T.speed; }
      else if (d > T.range * 0.95 || !this.los) { mx = ux; mz = uz; speed = T.speed; }
      else if (d < T.range * 0.45) { mx = -ux; mz = -uz; speed = T.speed * 0.8; }
      else {
        this.strafeT -= dt; if (this.strafeT <= 0) { this.strafeT = rand(1.2, 3); this.strafe *= -1; }
        mx = -uz * this.strafe; mz = ux * this.strafe; speed = T.speed * 0.6;
      }
      if (T.kamikaze && d < 2.4) {
        G.explode(this.pos.x, this.pos.y + 1, this.pos.z, 4.5, { enemyDmg: 0, carDmg: 30, playerDmg: T.dmg, color: T.color });
        this.hp = 0; this.die(); return;
      }
      this.fireT -= dt;
      if (!T.kamikaze && this.los && d < T.range * 1.15 && this.fireT <= 0) {
        this.fireT = rand(T.fire[0], T.fire[1]);
        this.center(_a);
        for (let i = 0; i < T.burst; i++) G.enemies.bolt(_a, _t, this.type, i * 0.12);
        sfx.enemyShot();
      }
    }
    // separation from other drones
    for (const e of G.enemies.list) {
      if (e === this || e.dead) continue;
      const ex = this.pos.x - e.pos.x, ez = this.pos.z - e.pos.z, ed = Math.hypot(ex, ez);
      if (ed < 2 && ed > 1e-3) { mx += (ex / ed) * 0.8; mz += (ez / ed) * 0.8; }
    }
    this.pos.x += mx * speed * dt; this.pos.z += mz * speed * dt;
    this.pos.y = 0;
    G.world.collide(this.pos, 0.7 * T.scale);
    this.pos.y = 0.55 + Math.sin(this.t * 2.2) * 0.12;
    this.mesh.position.copy(this.pos); this.mesh.rotation.set(0, this.yaw, 0);
    this.mesh.rotation.z = damp(this.mesh.rotation.z, -mx * 0.15, 5, dt);

    if (this.barT > 0 && !this.dead) {
      this.barT -= dt;
      this.bar.visible = this.barT > 0;
      this.bar.position.set(this.pos.x, this.pos.y + 2.1 * T.scale, this.pos.z);
      this.bar.quaternion.copy(G.camera.quaternion);
      this.fg.scale.x = Math.max(0.001, 1.4 * this.hp / this.maxHp);
    }
  }

  dispose() { this.G.scene.remove(this.mesh, this.bar); }
}

export class Enemies {
  constructor(G) {
    this.G = G; this.list = []; this.bolts = []; this.spawnT = 0;
    for (const k in ENEMY) boltMats[k] = new THREE.MeshBasicMaterial({ color: ENEMY[k].color });
  }

  spawn(type, x, z, opts) { const e = new Enemy(this.G, type, x, z, opts); this.list.push(e); return e; }

  clear(onlyReinforcements = false) {
    this.list = this.list.filter(e => { if (!onlyReinforcements || e.reinforce) { e.dispose(); return false; } return true; });
    for (const b of this.bolts) this.G.scene.remove(b.mesh);
    this.bolts.length = 0;
  }

  initPatrols() {
    const G = this.G, s = G.world.spawn;
    for (let g = 0; g < 7; g++) {
      let p; do { p = G.world.roadPoint(); } while (Math.hypot(p.x - s.x, p.z - s.z) < 110);
      const far = Math.hypot(p.x, p.z) > 200;
      for (let i = 0; i < 2 + (g % 2); i++) this.spawn(far && i === 0 && g % 3 === 0 ? 'heavy' : 'sentinel', p.x + rand(-4, 4), p.z + rand(-4, 4));
    }
  }

  bolt(from, to, type, delay = 0) {
    const G = this.G, T = ENEMY[type];
    _b.subVectors(to, from);
    const len = _b.length() || 1;
    _b.multiplyScalar(1 / len);
    _b.x += rand(-0.035, 0.035); _b.y += rand(-0.02, 0.02); _b.z += rand(-0.035, 0.035); _b.normalize();
    let b = this.bolts.find(q => q.life <= 0);
    if (!b) {
      if (this.bolts.length > 80) return;
      b = { mesh: new THREE.Mesh(boltGeo, boltMats.sentinel), pos: new THREE.Vector3(), vel: new THREE.Vector3(), life: 0, dmg: 0, wait: 0 };
      G.scene.add(b.mesh); this.bolts.push(b);
    }
    b.mesh.material = boltMats[type];
    b.pos.copy(from); b.vel.copy(_b).multiplyScalar(T.bolt); b.life = 3; b.dmg = T.dmg; b.wait = delay; b.mesh.visible = delay <= 0; b.mesh.position.copy(from);
  }

  update(dt) {
    const G = this.G, P = G.player;
    for (const e of this.list) e.update(dt);
    this.list = this.list.filter(e => { if (e.remove) { e.dispose(); return false; } return true; });

    // reinforcements scale with the Observation level
    this.spawnT -= dt;
    const want = G.heat >= 1 ? Math.floor(2 + G.heat * 2.6) : 0;
    if (this.spawnT <= 0 && want > 0) {
      this.spawnT = 1.4;
      const near = this.list.filter(e => !e.dead && Math.hypot(e.pos.x - P.pos.x, e.pos.z - P.pos.z) < 110).length;
      if (near < want) {
        const p = G.world.roadPointNear(P.pos.x, P.pos.z, 38, 75);
        if (p) {
          const r = Math.random();
          const type = G.heat >= 3 && r < 0.25 ? 'heavy' : r < 0.35 ? 'striker' : 'sentinel';
          this.spawn(type, p.x, p.z, { aware: true, reinforce: true });
          G.fx.burst(p.x, 1, p.z, 25, ENEMY[type].color, 6, 0.6, 0);
        }
      }
    }
    for (const e of this.list) if (e.reinforce && !e.dead && Math.hypot(e.pos.x - P.pos.x, e.pos.z - P.pos.z) > 170) e.remove = true;

    // bolts
    for (const b of this.bolts) {
      if (b.life <= 0) continue;
      if (b.wait > 0) { b.wait -= dt; if (b.wait <= 0) b.mesh.visible = true; continue; }
      b.life -= dt;
      b.pos.addScaledVector(b.vel, dt); b.mesh.position.copy(b.pos);
      let gone = b.life <= 0 || G.world.inside(b.pos.x, b.pos.y, b.pos.z);
      if (!gone) {
        const c = G.quantum.clone;
        if (c && Math.hypot(b.pos.x - c.pos.x, b.pos.z - c.pos.z) < 0.9 && b.pos.y < c.pos.y + 1.9) { gone = true; G.quantum.collapse(); }
        else if (P.inCar) { if (Math.hypot(b.pos.x - P.inCar.pos.x, b.pos.z - P.inCar.pos.z) < 2.1 && b.pos.y < 2) { gone = true; P.hurt(b.dmg); } }
        else if (Math.hypot(b.pos.x - P.pos.x, b.pos.z - P.pos.z) < 0.6 && b.pos.y > P.pos.y && b.pos.y < P.pos.y + 1.9) { gone = true; P.hurt(b.dmg); }
      }
      if (gone) { b.life = 0; b.mesh.visible = false; G.fx.burst(b.pos.x, b.pos.y, b.pos.z, 4, 0xff7090, 3, 0.2, 4); }
    }
  }
}
