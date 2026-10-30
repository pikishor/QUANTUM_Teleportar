import * as THREE from 'three';

const UP = new THREE.Vector3(0, 1, 0), _d = new THREE.Vector3(), _c = new THREE.Color();

export function makeBeam(color, r = 0.06, opacity = 0.9) {
  const m = new THREE.Mesh(
    new THREE.CylinderGeometry(r, r, 1, 6, 1, true),
    new THREE.MeshBasicMaterial({ color, transparent: true, opacity, blending: THREE.AdditiveBlending, depthWrite: false })
  );
  m.frustumCulled = false; m.visible = false;
  return m;
}

export function setBeam(m, a, b) {
  _d.subVectors(b, a);
  const len = _d.length();
  if (len < 1e-4) { m.visible = false; return; }
  m.visible = true;
  m.position.addVectors(a, b).multiplyScalar(0.5);
  m.scale.set(1, len, 1);
  m.quaternion.setFromUnitVectors(UP, _d.multiplyScalar(1 / len));
}

// One instanced draw call for every soft contact shadow in the scene.
export class BlobShadows {
  constructor(scene, cap = 96) {
    const c = document.createElement('canvas'); c.width = c.height = 64;
    const x = c.getContext('2d'), g = x.createRadialGradient(32, 32, 0, 32, 32, 32);
    g.addColorStop(0, 'rgba(0,0,0,0.65)'); g.addColorStop(1, 'rgba(0,0,0,0)');
    x.fillStyle = g; x.fillRect(0, 0, 64, 64);
    const tex = new THREE.CanvasTexture(c);
    const geo = new THREE.PlaneGeometry(1, 1).rotateX(-Math.PI / 2);
    this.mesh = new THREE.InstancedMesh(geo, new THREE.MeshBasicMaterial({ map: tex, transparent: true, depthWrite: false }), cap);
    this.mesh.frustumCulled = false; this.mesh.renderOrder = 1; this.cap = cap; this.n = 0;
    this.o = new THREE.Object3D();
    scene.add(this.mesh);
  }
  begin() { this.n = 0; }
  add(x, y, z, sx, sz = sx, rot = 0) {
    if (this.n >= this.cap) return;
    const o = this.o; o.position.set(x, y + 0.12, z); o.scale.set(sx, 1, sz); o.rotation.set(0, rot, 0); o.updateMatrix();
    this.mesh.setMatrixAt(this.n++, o.matrix);
  }
  end() { this.mesh.count = this.n; this.mesh.instanceMatrix.needsUpdate = true; }
}

// Pooled particles (one draw call), tracers and expanding blasts.
export class FX {
  constructor(scene) {
    const M = this.M = 900;
    this.i = 0; this.shake = 0;
    this.pos = new Float32Array(M * 3); this.col = new Float32Array(M * 3); this.base = new Float32Array(M * 3);
    this.vel = new Float32Array(M * 3); this.life = new Float32Array(M); this.max = new Float32Array(M).fill(1); this.grav = new Float32Array(M);
    for (let i = 0; i < M; i++) this.pos[i * 3 + 1] = -999;
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(this.pos, 3).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('color', new THREE.BufferAttribute(this.col, 3).setUsage(THREE.DynamicDrawUsage));
    this.pts = new THREE.Points(g, new THREE.PointsMaterial({ size: 0.45, vertexColors: true, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false }));
    this.pts.frustumCulled = false;
    scene.add(this.pts);

    this.tracers = Array.from({ length: 20 }, () => { const m = makeBeam(0xffffff, 0.03, 1); scene.add(m); return { m, t: 0 }; });
    this.ti = 0;
    this.blasts = Array.from({ length: 6 }, () => {
      const m = new THREE.Mesh(new THREE.SphereGeometry(1, 16, 12), new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0, blending: THREE.AdditiveBlending, depthWrite: false }));
      m.visible = false; scene.add(m);
      return { m, t: 0, dur: 0.5, r: 5 };
    });
    this.bi = 0;
  }

  burst(x, y, z, n, color, speed = 6, life = 0.6, grav = 8) {
    _c.set(color);
    for (let k = 0; k < n; k++) {
      const i = this.i; this.i = (this.i + 1) % this.M;
      const a = Math.random() * 6.283, b = Math.acos(2 * Math.random() - 1), s = speed * (0.3 + Math.random() * 0.7);
      const j = i * 3;
      this.pos[j] = x; this.pos[j + 1] = y; this.pos[j + 2] = z;
      this.vel[j] = Math.sin(b) * Math.cos(a) * s; this.vel[j + 1] = Math.cos(b) * s; this.vel[j + 2] = Math.sin(b) * Math.sin(a) * s;
      this.base[j] = _c.r; this.base[j + 1] = _c.g; this.base[j + 2] = _c.b;
      this.life[i] = this.max[i] = life * (0.6 + Math.random() * 0.4); this.grav[i] = grav;
    }
  }

  tracer(a, b, color = 0xfff1a8) {
    const t = this.tracers[this.ti]; this.ti = (this.ti + 1) % this.tracers.length;
    setBeam(t.m, a, b); t.m.material.color.set(color); t.m.material.opacity = 1; t.t = 0.08;
  }

  blast(x, y, z, r, color = 0xff8a30, dur = 0.5) {
    const b = this.blasts[this.bi]; this.bi = (this.bi + 1) % this.blasts.length;
    b.m.position.set(x, y, z); b.m.material.color.set(color); b.m.visible = true; b.t = b.dur = dur; b.r = r;
  }

  update(dt) {
    const { pos, col, base, vel, life, max, grav } = this;
    for (let i = 0; i < this.M; i++) {
      if (life[i] <= 0) continue;
      const j = i * 3;
      life[i] -= dt;
      if (life[i] <= 0) { pos[j + 1] = -999; col[j] = col[j + 1] = col[j + 2] = 0; continue; }
      vel[j + 1] -= grav[i] * dt;
      pos[j] += vel[j] * dt; pos[j + 1] += vel[j + 1] * dt; pos[j + 2] += vel[j + 2] * dt;
      const f = life[i] / max[i];
      col[j] = base[j] * f; col[j + 1] = base[j + 1] * f; col[j + 2] = base[j + 2] * f;
    }
    this.pts.geometry.attributes.position.needsUpdate = true;
    this.pts.geometry.attributes.color.needsUpdate = true;
    for (const t of this.tracers) if (t.t > 0) { t.t -= dt; t.m.material.opacity = Math.max(0, t.t / 0.08); if (t.t <= 0) t.m.visible = false; }
    for (const b of this.blasts) {
      if (b.t <= 0) continue;
      b.t -= dt;
      const k = 1 - Math.max(0, b.t) / b.dur;
      b.m.scale.setScalar(0.3 + (b.r - 0.3) * Math.sqrt(k)); b.m.material.opacity = 0.55 * (1 - k);
      if (b.t <= 0) b.m.visible = false;
    }
    this.shake = Math.max(0, this.shake - dt * 2.5);
  }
}
