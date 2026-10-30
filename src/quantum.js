import * as THREE from 'three';
import { consume } from './input.js';
import { sfx } from './audio.js';
import { buildPlayerModel } from './models.js';
import { makeBeam, setBeam } from './fx.js';
import { raySphere } from './util.js';

const _d = new THREE.Vector3(), _p = new THREE.Vector3(), _a = new THREE.Vector3(), _b = new THREE.Vector3();

function makeBeacon() {
  const g = new THREE.Group();
  const mat = c => new THREE.MeshBasicMaterial({ color: c, transparent: true, opacity: 0.8, blending: THREE.AdditiveBlending, depthWrite: false });
  const ring = new THREE.Mesh(new THREE.TorusGeometry(0.9, 0.07, 8, 32), mat(0x4ff0ff)); ring.rotation.x = Math.PI / 2; ring.position.y = 0.2;
  const ring2 = new THREE.Mesh(new THREE.TorusGeometry(1.4, 0.05, 8, 32), mat(0xff3df0)); ring2.rotation.x = Math.PI / 2; ring2.position.y = 0.2;
  const pillar = new THREE.Mesh(new THREE.CylinderGeometry(0.06, 0.06, 7, 6, 1, true), mat(0x9ffaff)); pillar.position.y = 3.5;
  const core = new THREE.Mesh(new THREE.OctahedronGeometry(0.35), mat(0xffffff)); core.position.y = 1.2;
  g.add(ring, ring2, pillar, core); g.userData = { ring, ring2, core };
  g.visible = false;
  return g;
}

// Quantum toolkit: Blink (teleport to a thrown Bell-pair beacon), Entangle (shared damage), Superposition (decoy → collapse blast).
export class Quantum {
  constructor(G) {
    this.G = G;
    this.beacon = null; this.beaconMesh = makeBeacon(); G.scene.add(this.beaconMesh);
    this.clone = null; this.links = [];
    this.cd = { blink: 0, link: 0, super: 0 };
  }

  reset() {
    this.removeBeacon();
    if (this.clone) { this.G.scene.remove(this.clone.mesh); this.clone = null; }
    for (const l of this.links) this.dropLink(l);
    this.links.length = 0;
    this.cd.blink = this.cd.link = this.cd.super = 0;
  }

  removeBeacon() { this.beacon = null; this.beaconMesh.visible = false; }

  update(dt) {
    const G = this.G, P = G.player;
    for (const k in this.cd) this.cd[k] = Math.max(0, this.cd[k] - dt);
    if (consume('blink')) this.blink();
    if (consume('entangle')) this.entangle();
    if (consume('superpos')) this.superpose();

    if (this.beacon) {
      this.beacon.t -= dt;
      const u = this.beaconMesh.userData, t = G.time;
      this.beaconMesh.position.set(this.beacon.pos.x, this.beacon.pos.y, this.beacon.pos.z);
      u.ring.rotation.z = t * 2; u.ring2.rotation.z = -t * 1.4; u.core.rotation.y = t * 3; u.core.position.y = 1.2 + Math.sin(t * 3) * 0.2;
      this.beaconMesh.visible = this.beacon.t > 1.5 || Math.floor(t * 8) % 2 === 0;
      if (this.beacon.t <= 0) this.removeBeacon();
    }

    const c = this.clone;
    if (c) {
      c.t -= dt;
      c.mesh.position.set(c.pos.x, c.pos.y + Math.sin(G.time * 3) * 0.05, c.pos.z);
      c.mesh.visible = c.t > 1 || Math.floor(G.time * 10) % 2 === 0;
      if (c.t <= 0) this.collapse();
    }

    for (const l of this.links) {
      l.t -= dt;
      if (l.t <= 0 || l.a.dead || l.b.dead) { l.expired = true; continue; }
      l.a.center(_a); l.b.center(_b);
      setBeam(l.b1, _a, _b); setBeam(l.b2, _a, _b);
      const pulse = 0.6 + 0.4 * Math.sin(G.time * 12);
      l.b1.material.opacity = pulse; l.b2.material.opacity = 1 - pulse * 0.5;
    }
    this.links = this.links.filter(l => { if (l.expired) { this.dropLink(l); return false; } return true; });
  }

  dropLink(l) {
    if (l.a.linked === l.b) l.a.linked = null;
    if (l.b.linked === l.a) l.b.linked = null;
    this.G.scene.remove(l.b1, l.b2);
  }

  aim(maxD) {
    const cam = this.G.camera;
    _d.set(0, 0, -1).applyQuaternion(cam.quaternion);
    const t = Math.min(this.G.world.ray(cam.position.x, cam.position.y, cam.position.z, _d.x, _d.y, _d.z, maxD), maxD);
    return { o: cam.position, d: _d, t };
  }

  blink() {
    const G = this.G, P = G.player;
    if (P.inCar) return G.hud.msg('BLINK OFFLINE IN VEHICLE', 1.2);
    if (this.beacon) return this.teleport();
    if (this.cd.blink > 0) return;
    if (P.energy < 15) return G.hud.msg('NOT ENOUGH COHERENCE', 1);
    const { o, d, t } = this.aim(48);
    _p.copy(o).addScaledVector(d, t < 48 ? Math.max(0, t - 0.6) : t);
    const down = G.world.ray(_p.x, _p.y, _p.z, 0, -1, 0, 150);
    const y = down === Infinity ? 0 : Math.max(0, _p.y - down);
    this.beacon = { pos: { x: _p.x, y, z: _p.z }, t: 8 };
    P.energy -= 15; this.cd.blink = 0.3;
    G.fx.burst(_p.x, y + 0.5, _p.z, 14, 0x4ff0ff, 4, 0.5, 0);
    sfx.link();
    G.hud.msg('BELL-PAIR BEACON PLACED · BLINK AGAIN TO TELEPORT', 1.6);
  }

  teleport() {
    const G = this.G, P = G.player, b = this.beacon;
    _a.set(P.pos.x, P.pos.y + 1, P.pos.z); _b.set(b.pos.x, b.pos.y + 1, b.pos.z);
    G.fx.tracer(_a, _b, 0x4ff0ff);
    G.fx.burst(_a.x, _a.y, _a.z, 40, 0x4ff0ff, 7, 0.6, 0);
    P.pos.set(b.pos.x, b.pos.y, b.pos.z); P.vel.set(0, 0, 0); P.grounded = false;
    G.fx.burst(_b.x, _b.y, _b.z, 40, 0xff3df0, 7, 0.6, 0);
    G.fx.shake = Math.max(G.fx.shake, 0.35); sfx.blink();
    // the real protocol: Alice's two classical bits tell Bob which corrections to apply
    const m0 = Math.random() < 0.5 ? 0 : 1, m1 = Math.random() < 0.5 ? 0 : 1;
    const fix = m1 || m0 ? [m1 ? 'X' : null, m0 ? 'Z' : null].filter(Boolean).join(' then ') : 'nothing';
    G.hud.msg(`TELEPORTED · ALICE BITS ${m0}${m1} → BOB APPLIES ${fix.toUpperCase()}`, 2);
    this.removeBeacon(); this.cd.blink = 0.4;
  }

  entangle() {
    const G = this.G, P = G.player;
    if (this.cd.link > 0) return;
    if (P.energy < 25) return G.hud.msg('NOT ENOUGH COHERENCE', 1);
    const { o, d, t } = this.aim(70);
    let a = null, best = t;
    for (const e of G.enemies.list) {
      if (e.dead || e.linked) continue;
      e.center(_p);
      const r = raySphere(o, d, _p, e.radius * 1.7);
      if (r < best) { best = r; a = e; }
    }
    if (!a) return G.hud.msg('NO TARGET IN SIGHT', 1);
    let b = null, bd = 45;
    for (const e of G.enemies.list) {
      if (e === a || e.dead || e.linked) continue;
      const dd = Math.hypot(e.pos.x - a.pos.x, e.pos.z - a.pos.z);
      if (dd < bd) { bd = dd; b = e; }
    }
    if (!b) return G.hud.msg('NEED A SECOND TARGET WITHIN 45 m', 1.4);
    P.energy -= 25; this.cd.link = 0.8;
    a.linked = b; b.linked = a; a.aware = b.aware = true;
    const b1 = makeBeam(0x7ffaff, 0.07), b2 = makeBeam(0xff6af0, 0.04);
    G.scene.add(b1, b2);
    this.links.push({ a, b, t: 9, b1, b2 });
    for (const e of [a, b]) G.fx.burst(e.pos.x, e.pos.y + 1, e.pos.z, 18, 0x7ffaff, 5, 0.5, 0);
    sfx.link();
    G.hud.msg('ENTANGLED · DAMAGE IS SHARED ACROSS DISTANCE', 1.8);
  }

  superpose() {
    const G = this.G, P = G.player;
    if (this.clone) return this.collapse();
    if (P.inCar) return G.hud.msg('SUPERPOSITION OFFLINE IN VEHICLE', 1.2);
    if (this.cd.super > 0) return;
    if (P.energy < 35) return G.hud.msg('NOT ENOUGH COHERENCE', 1);
    P.energy -= 35;
    const m = buildPlayerModel(true);
    m.group.rotation.y = P.yaw; G.scene.add(m.group);
    this.clone = { pos: P.pos.clone(), t: 6, mesh: m.group };
    G.fx.burst(P.pos.x, P.pos.y + 1, P.pos.z, 30, 0x66ffee, 5, 0.6, 0);
    sfx.superpos();
    G.hud.msg('SUPERPOSITION · ENEMIES SEE TWO OF YOU · BE FAST', 1.8);
  }

  collapse() {
    const G = this.G, c = this.clone;
    if (!c) return;
    G.explode(c.pos.x, c.pos.y + 1, c.pos.z, 9, { enemyDmg: 70, carDmg: 40, playerDmg: 0, color: 0x66ffee });
    G.scene.remove(c.mesh); this.clone = null; this.cd.super = 1.5;
    G.hud.msg('WAVEFUNCTION COLLAPSE', 1.4);
  }
}
