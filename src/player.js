import * as THREE from 'three';
import { clamp, damp, dampAngle, raySphere } from './util.js';
import { consume, takeLook, input } from './input.js';
import { sfx } from './audio.js';
import { buildPlayerModel } from './models.js';

const _d = new THREE.Vector3(), _mz = new THREE.Vector3(), _o = new THREE.Vector3(), _e = new THREE.Vector3(), _w = new THREE.Vector3(), _p = new THREE.Vector3();

export class Player {
  constructor(G) {
    this.G = G;
    this.pos = new THREE.Vector3(); this.vel = new THREE.Vector3();
    this.yaw = 0; this.camYaw = 0; this.camPitch = -0.12; this.fov = 72;
    this.maxHp = 100; this.maxEnergy = 100;
    const m = buildPlayerModel();
    this.mesh = m.group; this.legL = m.legL; this.legR = m.legR; this.muzzle = m.muzzle;
    G.scene.add(this.mesh);
    this.reset(G.world.spawn.x, G.world.spawn.z);
  }

  reset(x, z) {
    this.pos.set(x, 0, z); this.vel.set(0, 0, 0);
    this.hp = this.maxHp; this.energy = this.maxEnergy; this.mag = 30; this.ammo = 30; this.reload = 0; this.fireT = 0; this.fireGlow = 0; this.spread = 0;
    this.grounded = true; this.inCar = null; this.aiming = false; this.lastHurt = -99; this.invuln = 1.5; this.anim = 0; this.freeLook = 0;
    this.camYaw = Math.PI / 2 * -1; this.camPitch = -0.12; this.yaw = this.camYaw;
    this.mesh.visible = true;
  }

  // chest height position used as the aim point for enemies
  chest(out) {
    return this.inCar ? out.set(this.inCar.pos.x, 1.1, this.inCar.pos.z) : out.set(this.pos.x, this.pos.y + 1.2, this.pos.z);
  }

  hurt(d) {
    const G = this.G;
    if (this.invuln > 0 || G.state !== 'play') return;
    if (this.inCar) { this.inCar.damage(d * 0.6); G.hud.damage(0.5); return; }
    this.hp -= d; this.lastHurt = G.time;
    G.hud.damage(Math.min(1, d / 25)); G.fx.shake = Math.max(G.fx.shake, 0.3); sfx.hurt();
    if (this.hp <= 0) G.die();
  }

  update(dt) {
    const G = this.G, car = this.inCar;
    const look = takeLook();
    this.camYaw -= look.x; this.camPitch = clamp(this.camPitch - look.y, -1.0, 0.85);
    if (look.x || look.y) this.freeLook = 1.5;
    this.freeLook = Math.max(0, this.freeLook - dt); this.fireGlow = Math.max(0, this.fireGlow - dt);
    this.invuln = Math.max(0, this.invuln - dt);
    if (G.time - this.lastHurt > 5) this.hp = Math.min(this.maxHp, this.hp + 14 * dt);
    this.energy = Math.min(this.maxEnergy, this.energy + (car ? 3 : 8) * dt);
    this.spread = Math.max(0, this.spread - 0.08 * dt);

    if (consume('interact')) G.vehicles.toggle();
    if (this.inCar) { this.pos.set(this.inCar.pos.x, 0, this.inCar.pos.z); this.mesh.visible = false; this.aiming = false; }
    else { this.walk(dt); this.combat(dt); }
    this.updateCamera(dt);
  }

  walk(dt) {
    const G = this.G, I = input;
    this.mesh.visible = true;
    this.aiming = I.aim;
    const sy = Math.sin(this.camYaw), cy = Math.cos(this.camYaw);
    const wx = -sy * I.my + cy * I.mx, wz = -cy * I.my - sy * I.mx, mag = Math.hypot(wx, wz);
    const sprint = I.sprint && !this.aiming && I.my > 0.3;
    const sp = (this.aiming ? 3.4 : 6.2) * (sprint ? 1.6 : 1) * (G.quantum.clone ? 1.3 : 1);
    const k = this.grounded ? 14 : 4;
    this.vel.x = damp(this.vel.x, wx * sp, k, dt); this.vel.z = damp(this.vel.z, wz * sp, k, dt);
    if (this.grounded && consume('jump')) { this.vel.y = 7.6; this.grounded = false; }
    this.vel.y = Math.max(-40, this.vel.y - 22 * dt);
    this.pos.addScaledVector(this.vel, dt);
    const gy = G.world.groundAt(this.pos.x, this.pos.z, this.pos.y);
    if (this.pos.y <= gy) { this.pos.y = gy; if (this.vel.y < 0) this.vel.y = 0; this.grounded = true; } else this.grounded = false;
    G.world.collide(this.pos, 0.45);

    let ty = this.yaw;
    if (this.aiming || input.fire || this.fireGlow > 0) ty = this.camYaw; else if (mag > 0.1) ty = Math.atan2(-wx, -wz);
    this.yaw = dampAngle(this.yaw, ty, 14, dt);
    const spd = Math.hypot(this.vel.x, this.vel.z);
    this.anim += dt * spd * 1.6;
    const sw = this.grounded ? Math.min(1, spd / 5) * 0.9 : 0.3;
    this.legL.rotation.x = Math.sin(this.anim) * sw; this.legR.rotation.x = -Math.sin(this.anim) * sw;
    this.mesh.position.copy(this.pos); this.mesh.rotation.y = this.yaw;
  }

  combat(dt) {
    this.fireT -= dt;
    if (this.reload > 0) { this.reload -= dt; if (this.reload <= 0) this.ammo = this.mag; }
    if (consume('reload') && this.reload <= 0 && this.ammo < this.mag) { this.reload = 1.3; sfx.reload(); }
    if (input.fire && this.reload <= 0) {
      if (this.ammo <= 0) { this.reload = 1.3; sfx.reload(); }
      else if (this.fireT <= 0) this.shoot();
    }
  }

  shoot() {
    const G = this.G, cam = G.camera;
    this.fireT = 0.11; this.ammo--; this.fireGlow = 0.5; sfx.shot();
    const moving = Math.hypot(this.vel.x, this.vel.z) > 1;
    const sp = (this.aiming ? 0.004 : 0.014) + this.spread + (moving ? 0.01 : 0);
    _d.set(0, 0, -1).applyQuaternion(cam.quaternion);
    _d.x += (Math.random() - 0.5) * sp * 2; _d.y += (Math.random() - 0.5) * sp * 2; _d.z += (Math.random() - 0.5) * sp * 2; _d.normalize();
    _o.copy(cam.position);
    let best = Math.min(G.world.ray(_o.x, _o.y, _o.z, _d.x, _d.y, _d.z, 220), 220), hitE = null, hitC = null, crit = false;
    for (const e of G.enemies.list) {
      if (e.dead) continue;
      e.center(_e);
      const t = raySphere(_o, _d, _e, e.radius);
      if (t < best) { best = t; hitE = e; hitC = null; crit = _o.y + _d.y * t > _e.y + e.radius * 0.35; }
    }
    for (const c of G.vehicles.list) {
      if (c.dead || c === this.inCar) continue;
      const t = raySphere(_o, _d, _e.set(c.pos.x, 1, c.pos.z), 2.2);
      if (t < best) { best = t; hitC = c; hitE = null; }
    }
    this.mesh.updateMatrixWorld(true); this.muzzle.getWorldPosition(_mz);
    _w.copy(_d).multiplyScalar(best).add(_o);
    G.fx.tracer(_mz, _w); G.fx.burst(_mz.x, _mz.y, _mz.z, 3, 0xffe08a, 3, 0.07, 0);
    if (hitE) { hitE.damage(crit ? 30 : 14, crit); G.hud.hitMarker(hitE.dead); G.fx.burst(_w.x, _w.y, _w.z, 6, 0xff7a7a, 4, 0.3, 6); }
    else if (hitC) { hitC.damage(9); G.hud.hitMarker(false); G.fx.burst(_w.x, _w.y, _w.z, 6, 0xffc07a, 4, 0.3, 6); }
    else if (best < 220) G.fx.burst(_w.x, _w.y, _w.z, 5, 0xbfc8ff, 4, 0.25, 8);
    this.camPitch += 0.004 + Math.random() * 0.004; this.camYaw += (Math.random() - 0.5) * 0.006;
    this.spread = Math.min(0.03, this.spread + 0.003);
  }

  updateCamera(dt) {
    const G = this.G, cam = G.camera, car = this.inCar;
    let dist, shoulder, height, fovT;
    if (car) {
      if (this.freeLook <= 0) {
        this.camYaw = dampAngle(this.camYaw, car.heading, Math.abs(car.speed) > 2 ? 3 : 0.8, dt);
        this.camPitch = damp(this.camPitch, -0.2, 3, dt);
      }
      dist = 7.5; shoulder = 0; height = 1.6; fovT = 72 + Math.min(18, Math.abs(car.speed) * 0.5);
    } else {
      const sprinting = input.sprint && input.my > 0.3 && !this.aiming;
      dist = this.aiming ? 2.0 : 3.6; shoulder = this.aiming ? 0.55 : 0.8; height = 1.55; fovT = this.aiming ? 50 : sprinting ? 78 : 72;
    }
    this.fov = damp(this.fov, fovT, 10, dt);
    if (Math.abs(cam.fov - this.fov) > 0.05) { cam.fov = this.fov; cam.updateProjectionMatrix(); }
    const cp = Math.cos(this.camPitch), sp = Math.sin(this.camPitch), sy = Math.sin(this.camYaw), cy = Math.cos(this.camYaw);
    const base = car ? car.pos : this.pos;
    _p.set(base.x, (car ? 0 : this.pos.y) + height, base.z);
    _w.set(-sy * cp * -dist + cy * shoulder, sp * -dist, -cy * cp * -dist - sy * shoulder);   // pivot → camera offset
    const len = _w.length();
    _w.multiplyScalar(1 / len);
    const t = G.world.ray(_p.x, _p.y, _p.z, _w.x, _w.y, _w.z, len + 0.3);
    const use = t === Infinity ? len : Math.max(0.5, t - 0.3);
    cam.position.copy(_p).addScaledVector(_w, use);
    if (cam.position.y < 0.3) cam.position.y = 0.3;
    const s = G.fx.shake * 0.25;
    if (s > 0) cam.position.add(_e.set((Math.random() - 0.5) * s, (Math.random() - 0.5) * s, (Math.random() - 0.5) * s));
    cam.rotation.set(this.camPitch, this.camYaw, 0, 'YXZ');
  }
}
