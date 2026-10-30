import * as THREE from 'three';
import { clamp, damp, dampAngle, rand } from './util.js';
import { input, consume } from './input.js';
import { carMesh, CAR_COLORS, CAR_GLOW } from './models.js';
import { sfx } from './audio.js';
import { HALF, N, PITCH, LANE, ROAD, roadCenters } from './world.js';

const SPECS = {
  sedan: { max: 34, acc: 18, brake: 40, grip: 6.5, hp: 120 },
  sport: { max: 50, acc: 28, brake: 48, grip: 5.2, hp: 100 },
};
const _p = new THREE.Vector3();
const headingFor = (axis, dir) => (axis === 0 ? (dir > 0 ? -Math.PI / 2 : Math.PI / 2) : dir > 0 ? Math.PI : 0);

class Car {
  constructor(G, kind, x, z, heading, ai) {
    this.G = G; this.kind = kind; this.spec = SPECS[kind];
    this.pos = new THREE.Vector3(x, 0, z); this.vel = new THREE.Vector3();
    this.heading = heading; this.speed = 0; this.hp = this.maxHp = this.spec.hp; this.dead = false; this.ai = ai || null;
    this.mesh = carMesh(Math.floor(Math.random() * CAR_COLORS.length), Math.floor(Math.random() * CAR_GLOW.length), kind === 'sport');
    G.scene.add(this.mesh);
    this.sync();
  }

  sync() { this.mesh.position.copy(this.pos); this.mesh.rotation.y = this.heading; }

  damage(d) {
    if (this.dead) return;
    this.hp -= d;
    if (this.hp <= 0) this.explode();
  }

  explode() {
    const G = this.G;
    this.dead = true; this.mesh.visible = false;
    if (G.player.inCar === this) G.vehicles.exit();
    G.explode(this.pos.x, 1, this.pos.z, 9, { enemyDmg: 80, carDmg: 70, playerDmg: 35, color: 0xff8a30 });
    G.addHeat(0.2);
    G.vehicles.respawn.push(G.time + 25);
  }

  // right-hand traffic on the grid; turns at intersections
  aiUpdate(dt) {
    const a = this.ai, G = this.G, P = G.player;
    const fx = a.axis === 0 ? a.dir : 0, fz = a.axis === 1 ? a.dir : 0;
    let blocked = false;
    const chk = (x, z) => {
      const rx = x - this.pos.x, rz = z - this.pos.z, ahead = rx * fx + rz * fz, side = Math.abs(rx * fz - rz * fx);
      if (ahead > 0 && ahead < 11 && side < 2.6) blocked = true;
    };
    if (!P.inCar) chk(P.pos.x, P.pos.z);
    for (const o of G.vehicles.list) if (o !== this && !o.dead) chk(o.pos.x, o.pos.z);
    a.speed = damp(a.speed, blocked ? 0 : a.cruise, blocked ? 5 : 1.5, dt);
    const ox = this.pos.x, oz = this.pos.z, prevU = a.axis === 0 ? ox : oz, step = a.dir * a.speed * dt;
    if (a.axis === 0) { this.pos.x += step; this.pos.z = damp(this.pos.z, a.line, 2.5, dt); }
    else { this.pos.z += step; this.pos.x = damp(this.pos.x, a.line, 2.5, dt); }
    a.cool -= Math.abs(step);
    const u = a.axis === 0 ? this.pos.x : this.pos.z, idx = Math.round((u + HALF) / PITCH), c = -HALF + idx * PITCH;
    if (a.cool <= 0 && idx >= 0 && idx <= N && (prevU - c) * (u - c) <= 0 && prevU !== u) this.turn(c, idx);
    const dx = this.pos.x - ox, dz = this.pos.z - oz;
    if (dx * dx + dz * dz > 1e-6) this.heading = dampAngle(this.heading, Math.atan2(-dx, -dz), 7, dt);
    this.vel.set(dx / dt, 0, dz / dt); this.speed = a.speed;
  }

  turn(c, idx) {
    const a = this.ai, edge = (idx === 0 && a.dir < 0) || (idx === N && a.dir > 0);
    if (!edge && Math.random() < 0.55) return;
    const p = a.axis === 0 ? this.pos.z : this.pos.x;
    let d2 = Math.random() < 0.5 ? 1 : -1;
    if (p > HALF - 14) d2 = -1; else if (p < -HALF + 14) d2 = 1;
    a.axis = 1 - a.axis; a.dir = d2; a.line = c + LANE * d2; a.speed *= 0.7; a.cool = 14;
  }
}

export class Vehicles {
  constructor(G) { this.G = G; this.list = []; this.respawn = []; }

  init() {
    const s = this.G.world.spawn;
    this.add(new Car(this.G, 'sport', s.x + 9, s.z + 8.3, -Math.PI / 2));          // starter car
    for (let i = 0; i < 13; i++) this.spawnParked();
    for (let i = 0; i < 10; i++) this.spawnTraffic();
  }

  add(c) { this.list.push(c); return c; }

  spawnParked() {
    const P = this.G.player;
    for (let t = 0; t < 20; t++) {
      const axis = Math.random() < 0.5 ? 0 : 1, c = roadCenters[Math.floor(Math.random() * (N + 1))], u = (Math.random() * 2 - 1) * (HALF - 20);
      if (roadCenters.some(ic => Math.abs(u - ic) < ROAD / 2 + 5)) continue;
      const side = Math.random() < 0.5 ? 1 : -1, o = 8.3 * side;
      const x = axis === 0 ? u : c + o, z = axis === 0 ? c + o : u;
      if (Math.hypot(x - P.pos.x, z - P.pos.z) < 20) continue;
      return this.add(new Car(this.G, Math.random() < 0.3 ? 'sport' : 'sedan', x, z, headingFor(axis, side)));
    }
  }

  spawnTraffic() {
    const P = this.G.player;
    for (let t = 0; t < 20; t++) {
      const axis = Math.random() < 0.5 ? 0 : 1, dir = Math.random() < 0.5 ? 1 : -1, c = roadCenters[Math.floor(Math.random() * (N + 1))], u = (Math.random() * 2 - 1) * (HALF - 30);
      const line = c + LANE * dir, x = axis === 0 ? u : line, z = axis === 0 ? line : u;
      if (Math.hypot(x - P.pos.x, z - P.pos.z) < 50) continue;
      return this.add(new Car(this.G, Math.random() < 0.25 ? 'sport' : 'sedan', x, z, headingFor(axis, dir), { axis, dir, line, speed: 0, cruise: rand(9, 14), cool: 0 }));
    }
  }

  nearest(pos, r = 4.2) {
    let best = null;
    for (const c of this.list) {
      if (c.dead) continue;
      const d = Math.hypot(c.pos.x - pos.x, c.pos.z - pos.z);
      if (d < r) { r = d; best = c; }
    }
    return best;
  }

  toggle() {
    const G = this.G, P = G.player;
    if (P.inCar) return this.exit();
    const car = P.pos.y < 2 ? this.nearest(P.pos) : null;
    if (!car) return;
    if (car.ai) { car.ai = null; G.addHeat(0.2); G.hud.msg('VEHICLE COMMANDEERED', 1.4); }
    P.inCar = car; sfx.pickup();
  }

  exit() {
    const G = this.G, P = G.player, car = P.inCar;
    if (!car) return;
    const h = car.heading;
    P.pos.set(car.pos.x + Math.cos(h) * 2.8, 0, car.pos.z - Math.sin(h) * 2.8);
    P.vel.set(0, 0, 0); P.grounded = true; P.inCar = null; P.yaw = h; P.mesh.visible = true;
    G.world.collide(P.pos, 0.45);
    consume('jump'); consume('reload');
  }

  drive(car, dt) {
    const G = this.G, T = car.spec, I = input, hb = I.jumpHeld;
    let h = car.heading, fx = -Math.sin(h), fz = -Math.cos(h), rx = Math.cos(h), rz = -Math.sin(h);
    let vf = car.vel.x * fx + car.vel.z * fz, vl = car.vel.x * rx + car.vel.z * rz;
    const thr = I.my;
    if (thr > 0.05) vf += T.acc * thr * (1 - Math.max(0, vf) / T.max) * dt;
    else if (thr < -0.05) vf += (vf > 0.5 ? -T.brake : -T.acc * 0.45) * -thr * dt;
    else vf *= Math.exp(-0.5 * dt);
    if (hb) vf *= Math.exp(-1.2 * dt);
    vf = clamp(vf, -T.max * 0.35, T.max);
    const auth = clamp(Math.abs(vf) / 5, 0, 1) / (1 + Math.abs(vf) / 38);
    h -= I.mx * 2.3 * auth * (vf >= 0 ? 1 : -1) * dt;
    vl *= Math.exp(-(hb ? 1.4 : T.grip) * dt);
    fx = -Math.sin(h); fz = -Math.cos(h); rx = Math.cos(h); rz = -Math.sin(h);
    car.vel.set(fx * vf + rx * vl, 0, fz * vf + rz * vl);
    car.heading = h; car.speed = vf;
    car.pos.addScaledVector(car.vel, dt);

    for (const off of [-1.4, 1.4]) {                              // nose and tail collision circles
      _p.set(car.pos.x + fx * off, 0, car.pos.z + fz * off);
      const ox = _p.x, oz = _p.z;
      if (G.world.collide(_p, 1.05)) {
        car.pos.x += _p.x - ox; car.pos.z += _p.z - oz;
        const nx = G.world.nx, nz = G.world.nz, vn = car.vel.x * nx + car.vel.z * nz;
        if (vn < 0) {
          car.vel.x -= 1.4 * vn * nx; car.vel.z -= 1.4 * vn * nz;
          if (-vn > 5) { car.damage(-vn * 2.2); G.fx.shake = Math.max(G.fx.shake, Math.min(1, -vn / 25)); G.fx.burst(_p.x, 0.8, _p.z, 8, 0xffc060, 5, 0.3, 8); }
        }
      }
    }
    for (const o of this.list) {                                  // bump other cars
      if (o === car || o.dead) continue;
      const dx = car.pos.x - o.pos.x, dz = car.pos.z - o.pos.z, d = Math.hypot(dx, dz);
      if (d < 3.6 && d > 1e-3) {
        const nx = dx / d, nz = dz / d, imp = Math.abs((car.vel.x - o.vel.x) * nx + (car.vel.z - o.vel.z) * nz);
        car.pos.x += nx * (3.6 - d) * 0.6; car.pos.z += nz * (3.6 - d) * 0.6; o.pos.x -= nx * (3.6 - d) * 0.4; o.pos.z -= nz * (3.6 - d) * 0.4;
        car.vel.multiplyScalar(0.8); o.vel.set(-nx * imp * 0.8, 0, -nz * imp * 0.8); o.ai = null;
        if (imp > 6) { car.damage(imp * 1.2); o.damage(imp * 2); G.fx.shake = Math.max(G.fx.shake, 0.4); sfx.hit(); }
      }
    }
    if (Math.abs(vf) > 8) {                                       // run drones over
      for (const e of G.enemies.list) {
        if (e.dead || (G.time - (e.runT || -9)) < 0.6) continue;
        if (Math.hypot(e.pos.x - car.pos.x, e.pos.z - car.pos.z) < 2.4) { e.runT = G.time; e.damage(Math.abs(vf) * 3.5, true); G.addHeat(0.05); }
      }
    }
  }

  update(dt) {
    const G = this.G, P = G.player;
    for (const c of this.list) {
      if (c.dead) continue;
      if (c === P.inCar) this.drive(c, dt);
      else if (c.ai) c.aiUpdate(dt);
      else if (c.vel.lengthSq() > 0.01) {
        c.vel.multiplyScalar(Math.exp(-3 * dt)); c.pos.addScaledVector(c.vel, dt); G.world.collide(c.pos, 1.6); c.speed = c.vel.length();
      }
      c.sync();
    }
    this.list = this.list.filter(c => { if (c.dead) { G.scene.remove(c.mesh); return false; } return true; });
    if (this.respawn.length && G.time > this.respawn[0]) { this.respawn.shift(); this.spawnParked(); }
  }
}
