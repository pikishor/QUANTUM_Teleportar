import * as THREE from 'three';
import { pickupMesh } from './models.js';
import { sfx } from './audio.js';

// Pickups dropped by drones, plus the sector objective: recover the quantum cores.
export class Missions {
  constructor(G) {
    this.G = G; this.pickups = []; this.cores = []; this.got = 0; this.total = 6; this.rounds = 0;
  }

  drop(kind, x, z) {
    const m = pickupMesh(kind);
    m.position.set(x, 0.9, z); this.G.scene.add(m);
    this.pickups.push({ kind, mesh: m, t: 40 });
  }

  makeCore() {
    const g = new THREE.Group();
    const add = (geo, c, op = 1) => new THREE.Mesh(geo, new THREE.MeshBasicMaterial({ color: c, transparent: op < 1, opacity: op, blending: op < 1 ? THREE.AdditiveBlending : THREE.NormalBlending, depthWrite: op >= 1, fog: false }));
    const core = add(new THREE.OctahedronGeometry(0.9), 0xff3df0);
    const ring = add(new THREE.TorusGeometry(1.6, 0.08, 8, 32), 0x4ff0ff, 0.9); ring.position.y = 0;
    const beam = add(new THREE.CylinderGeometry(0.5, 0.5, 160, 8, 1, true), 0xff5af0, 0.22); beam.position.y = 80;
    g.add(core, ring, beam); g.userData = { core, ring };
    return g;
  }

  newRound(total = 6) {
    const G = this.G;
    for (const c of this.cores) G.scene.remove(c.mesh);
    this.cores = []; this.got = 0; this.total = total; this.rounds++;
    const spots = G.world.intersections.filter(i => Math.hypot(i.x - G.world.spawn.x, i.z - G.world.spawn.z) > 140).sort(() => Math.random() - 0.5);
    const chosen = [];
    for (const s of spots) {
      if (chosen.length >= total) break;
      if (chosen.every(c => Math.hypot(c.x - s.x, c.z - s.z) > 110)) chosen.push(s);
    }
    for (const s of chosen) {
      const m = this.makeCore(); m.position.set(s.x, 2.2, s.z); G.scene.add(m);
      this.cores.push({ x: s.x, z: s.z, mesh: m });
    }
    this.total = this.cores.length;
  }

  clearPickups() { for (const p of this.pickups) this.G.scene.remove(p.mesh); this.pickups.length = 0; }

  update(dt) {
    const G = this.G, P = G.player;
    const ref = P.inCar ? P.inCar.pos : P.pos;
    for (const p of this.pickups) {
      p.t -= dt; p.mesh.rotation.y += dt * 2; p.mesh.position.y = 0.9 + Math.sin(G.time * 3 + p.mesh.position.x) * 0.15;
      if (Math.hypot(p.mesh.position.x - ref.x, p.mesh.position.z - ref.z) < 2.2) {
        if (p.kind === 'health') P.hp = Math.min(P.maxHp, P.hp + 30); else P.energy = Math.min(P.maxEnergy, P.energy + 35);
        sfx.pickup(); G.hud.feed(p.kind === 'health' ? '+30 INTEGRITY' : '+35 COHERENCE'); p.t = 0;
      }
    }
    this.pickups = this.pickups.filter(p => { if (p.t <= 0) { G.scene.remove(p.mesh); return false; } return true; });

    for (const c of this.cores) {
      const u = c.mesh.userData;
      u.core.rotation.y += dt * 1.6; u.ring.rotation.x += dt * 1.1; u.ring.rotation.y += dt * 0.7;
      if (Math.hypot(c.x - ref.x, c.z - ref.z) < 4) {
        c.got = true; this.got++; G.score += 250; G.player.energy = P.maxEnergy;
        G.fx.burst(c.x, 2.2, c.z, 60, 0xff5af0, 10, 1, 0); G.fx.blast(c.x, 2.2, c.z, 7, 0xff5af0, 0.6); sfx.core();
        G.hud.msg(`QUANTUM CORE RECOVERED  ${this.got}/${this.total}`, 2);
        G.scene.remove(c.mesh);
      }
    }
    this.cores = this.cores.filter(c => !c.got);
    if (this.total > 0 && this.cores.length === 0 && G.state === 'play') G.win();
  }

  nearest(pos) {
    let best = null, bd = Infinity;
    for (const c of this.cores) { const d = Math.hypot(c.x - pos.x, c.z - pos.z); if (d < bd) { bd = d; best = c; } }
    return best ? { core: best, dist: bd } : null;
  }
}
