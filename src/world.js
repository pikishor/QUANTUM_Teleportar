import * as THREE from 'three';
import { mulberry32, clamp } from './util.js';

// A neon grid city: N×N blocks separated by roads. Buildings are instanced and double as collision boxes.
export const PITCH = 80, ROAD = 20, N = 8, HALF = (N * PITCH) / 2, LANE = 5, BLOCK = PITCH - ROAD;
export const roadCenters = Array.from({ length: N + 1 }, (_, i) => -HALF + i * PITCH);
export const ROOF_TOL = 0.9;

const HEIGHTS = [16, 28, 44, 62, 88], FOOT = [18, 26], TILE = 32;
const TINTS = [0x9aa8ff, 0xb59bff, 0x7fd0ff, 0xc9a0ff, 0x8fe0d0, 0xff9fd0];
const NEON = [0x38f5ff, 0xff3df0, 0x9b6bff, 0x38ffb0];

function windowTextures() {
  const S = 256, cell = 32, rnd = mulberry32(7);
  const mk = () => { const c = document.createElement('canvas'); c.width = c.height = S; return c; };
  const a = mk(), b = mk(), ca = a.getContext('2d'), cb = b.getContext('2d');
  ca.fillStyle = '#1a1830'; ca.fillRect(0, 0, S, S);
  cb.fillStyle = '#000'; cb.fillRect(0, 0, S, S);
  const lit = ['#ffd27a', '#7ae8ff', '#ff7ad0', '#ffffff'];
  for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) {
    const px = x * cell + 6, py = y * cell + 8;
    if (rnd() < 0.42) {
      const c = lit[Math.floor(rnd() * lit.length)];
      ca.fillStyle = c; ca.fillRect(px, py, 20, 16);
      cb.fillStyle = c; cb.fillRect(px, py, 20, 16);
    } else { ca.fillStyle = '#262a4a'; ca.fillRect(px, py, 20, 16); }
  }
  const tex = c => {
    const t = new THREE.CanvasTexture(c);
    t.wrapS = t.wrapT = THREE.RepeatWrapping; t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 4;
    return t;
  };
  return { map: tex(a), emi: tex(b) };
}

function buildingGeo(w, d, h) {
  const g = new THREE.BoxGeometry(w, h, d), uv = g.attributes.uv;
  // face order: +x -x +y -y +z -z; roofs sample a dark corner of the atlas
  const sizes = [[d, h], [d, h], null, null, [w, h], [w, h]];
  for (let f = 0; f < 6; f++) for (let v = 0; v < 4; v++) {
    const i = f * 4 + v, s = sizes[f];
    if (s) uv.setXY(i, (uv.getX(i) * s[0]) / TILE, (uv.getY(i) * s[1]) / TILE);
    else uv.setXY(i, 0.01, 0.01);
  }
  g.translate(0, h / 2, 0);
  return g;
}

function instanced(scene, geo, mat, n, fn) {
  const m = new THREE.InstancedMesh(geo, mat, n), o = new THREE.Object3D(), c = new THREE.Color();
  for (let k = 0; k < n; k++) {
    o.position.set(0, 0, 0); o.scale.set(1, 1, 1); o.rotation.set(0, 0, 0);
    const col = fn(k, o);
    o.updateMatrix(); m.setMatrixAt(k, o.matrix);
    if (col !== undefined) m.setColorAt(k, c.set(col));
  }
  m.instanceMatrix.needsUpdate = true;
  if (m.instanceColor) m.instanceColor.needsUpdate = true;
  m.frustumCulled = false;
  scene.add(m);
  return m;
}

function rayBox(ox, oy, oz, dx, dy, dz, b) {
  let t0 = 0, t1 = Infinity, a, c, s;
  if (dx > -1e-9 && dx < 1e-9) { if (ox < b.x0 || ox > b.x1) return Infinity; }
  else { a = (b.x0 - ox) / dx; c = (b.x1 - ox) / dx; if (a > c) { s = a; a = c; c = s; } if (a > t0) t0 = a; if (c < t1) t1 = c; if (t0 > t1) return Infinity; }
  if (dy > -1e-9 && dy < 1e-9) { if (oy < 0 || oy > b.h) return Infinity; }
  else { a = -oy / dy; c = (b.h - oy) / dy; if (a > c) { s = a; a = c; c = s; } if (a > t0) t0 = a; if (c < t1) t1 = c; if (t0 > t1) return Infinity; }
  if (dz > -1e-9 && dz < 1e-9) { if (oz < b.z0 || oz > b.z1) return Infinity; }
  else { a = (b.z0 - oz) / dz; c = (b.z1 - oz) / dz; if (a > c) { s = a; a = c; c = s; } if (a > t0) t0 = a; if (c < t1) t1 = c; if (t0 > t1) return Infinity; }
  return t0;
}

export function createWorld(scene) {
  const rnd = mulberry32(2025);
  const boxes = [], buckets = Array.from({ length: N * N }, () => []);
  const classes = new Map(), trims = [];
  const { map, emi } = windowTextures();
  const bmat = new THREE.MeshLambertMaterial({ map, emissiveMap: emi, emissive: 0xffffff });

  for (let i = 0; i < N; i++) for (let j = 0; j < N; j++) {
    const bx = -HALF + (i + 0.5) * PITCH, bz = -HALF + (j + 0.5) * PITCH;
    const central = 1 - Math.min(1, Math.hypot(bx, bz) / (HALF * 1.1));
    for (const sx of [-1, 1]) for (const sz of [-1, 1]) {
      if (rnd() < 0.1) continue;                               // plaza
      const w = FOOT[rnd() < 0.5 ? 0 : 1], d = FOOT[rnd() < 0.5 ? 0 : 1];
      const h = HEIGHTS[clamp(Math.floor(rnd() * 2 + central * 3.4), 0, 4)];
      const cx = bx + sx * 15, cz = bz + sz * 15;
      const b = { x0: cx - w / 2, x1: cx + w / 2, z0: cz - d / 2, z1: cz + d / 2, h };
      boxes.push(b); buckets[i * N + j].push(b);
      const key = `${w}x${d}x${h}`;
      if (!classes.has(key)) classes.set(key, { w, d, h, items: [] });
      classes.get(key).items.push({ cx, cz, tint: TINTS[Math.floor(rnd() * TINTS.length)] });
      trims.push({ cx, cz, w, d, h, c: NEON[Math.floor(rnd() * NEON.length)] });
    }
  }
  for (const c of classes.values()) {
    instanced(scene, buildingGeo(c.w, c.d, c.h), bmat, c.items.length, (k, o) => { o.position.set(c.items[k].cx, 0, c.items[k].cz); return c.items[k].tint; });
  }
  const unit = new THREE.BoxGeometry(1, 1, 1);
  const basic = new THREE.MeshBasicMaterial({ color: 0xffffff });
  instanced(scene, unit, basic, trims.length, (k, o) => { const t = trims[k]; o.position.set(t.cx, t.h + 0.3, t.cz); o.scale.set(t.w + 0.6, 0.6, t.d + 0.6); return t.c; });

  const ground = new THREE.Mesh(new THREE.PlaneGeometry(2600, 2600), new THREE.MeshLambertMaterial({ color: 0x15122a }));
  ground.rotation.x = -Math.PI / 2;
  scene.add(ground);

  const L = 2 * HALF + ROAD;
  instanced(scene, unit, new THREE.MeshLambertMaterial({ color: 0x201d36 }), 2 * (N + 1), (k, o) => {
    const c = roadCenters[k >> 1];
    if (k & 1) { o.position.set(c, 0.04, 0); o.scale.set(ROAD, 0.08, L); } else { o.position.set(0, 0.04, c); o.scale.set(L, 0.08, ROAD); }
  });

  const dashes = [];
  for (const c of roadCenters) for (let u = -HALF + 5; u < HALF; u += 10) {
    if (roadCenters.some(ic => Math.abs(u - ic) < ROAD / 2 + 1.5)) continue;
    dashes.push([u, c, 0], [c, u, 1]);
  }
  instanced(scene, unit, new THREE.MeshBasicMaterial({ color: 0xc9c2ff }), dashes.length, (k, o) => {
    const [x, z, v] = dashes[k]; o.position.set(x, 0.09, z); o.scale.set(v ? 0.35 : 4.5, 0.03, v ? 4.5 : 0.35);
  });

  instanced(scene, unit, new THREE.MeshBasicMaterial({ color: 0xffffff }), N * N * 4, (k, o) => {
    const b = k >> 2, i = Math.floor(b / N), j = b % N, s = k & 3;
    const bx = -HALF + (i + 0.5) * PITCH, bz = -HALF + (j + 0.5) * PITCH, e = BLOCK / 2 - 0.2;
    if (s < 2) { o.position.set(bx, 0.05, bz + (s ? e : -e)); o.scale.set(BLOCK, 0.1, 0.4); }
    else { o.position.set(bx + (s & 1 ? e : -e), 0.05, bz); o.scale.set(0.4, 0.1, BLOCK); }
    return NEON[(i + j) % NEON.length];
  });

  const lamps = [];
  for (const x of roadCenters) for (const z of roadCenters) lamps.push([x + 10.6, z + 10.6], [x - 10.6, z - 10.6]);
  instanced(scene, unit, new THREE.MeshLambertMaterial({ color: 0x2a2840 }), lamps.length, (k, o) => { o.position.set(lamps[k][0], 3.5, lamps[k][1]); o.scale.set(0.25, 7, 0.25); });
  instanced(scene, unit, new THREE.MeshBasicMaterial({ color: 0xffd9a0 }), lamps.length, (k, o) => { o.position.set(lamps[k][0], 7.1, lamps[k][1]); o.scale.set(1.2, 0.3, 1.2); });

  // sky dressing
  const sp = new Float32Array(600 * 3);
  for (let i = 0; i < 600; i++) {
    const a = rnd() * Math.PI * 2, e = Math.asin(0.05 + rnd() * 0.95);
    sp[i * 3] = Math.cos(a) * Math.cos(e) * 1100; sp[i * 3 + 1] = Math.sin(e) * 1100; sp[i * 3 + 2] = Math.sin(a) * Math.cos(e) * 1100;
  }
  const sg = new THREE.BufferGeometry(); sg.setAttribute('position', new THREE.BufferAttribute(sp, 3));
  scene.add(new THREE.Points(sg, new THREE.PointsMaterial({ color: 0xffffff, size: 2, sizeAttenuation: false, fog: false })));
  const moon = new THREE.Mesh(new THREE.SphereGeometry(80, 24, 16), new THREE.MeshBasicMaterial({ color: 0x7c5cff, fog: false }));
  moon.position.set(-420, 320, -820);
  const ring = new THREE.Mesh(new THREE.TorusGeometry(135, 3, 6, 64), new THREE.MeshBasicMaterial({ color: 0xff7af0, fog: false }));
  ring.rotation.set(1.2, 0.2, 0.3); moon.add(ring);
  scene.add(moon);

  const tmp = [];
  const near = (x, z) => {
    tmp.length = 0;
    const i = Math.floor((x + HALF) / PITCH), j = Math.floor((z + HALF) / PITCH);
    for (let a = i - 1; a <= i + 1; a++) for (let b = j - 1; b <= j + 1; b++) {
      if (a < 0 || b < 0 || a >= N || b >= N) continue;
      for (const q of buckets[a * N + b]) tmp.push(q);
    }
    return tmp;
  };

  const intersections = [];
  for (let i = 1; i < N; i++) for (let j = 1; j < N; j++) intersections.push({ x: roadCenters[i], z: roadCenters[j] });

  return {
    boxes, intersections, nx: 0, nz: 0,
    spawn: { x: -30, z: 4 },
    // push a feet-position circle out of buildings; roofs are walkable when feet are above them
    collide(p, r) {
      let hit = false;
      for (const b of near(p.x, p.z)) {
        if (p.y >= b.h - ROOF_TOL) continue;
        const cx = clamp(p.x, b.x0, b.x1), cz = clamp(p.z, b.z0, b.z1);
        let dx = p.x - cx, dz = p.z - cz;
        const d2 = dx * dx + dz * dz;
        if (d2 >= r * r) continue;
        if (d2 > 1e-9) { const d = Math.sqrt(d2); dx /= d; dz /= d; p.x += dx * (r - d); p.z += dz * (r - d); }
        else {
          const l = p.x - b.x0, rr = b.x1 - p.x, t = p.z - b.z0, bt = b.z1 - p.z, m = Math.min(l, rr, t, bt);
          if (m === l) { dx = -1; dz = 0; p.x = b.x0 - r; } else if (m === rr) { dx = 1; dz = 0; p.x = b.x1 + r; }
          else if (m === t) { dx = 0; dz = -1; p.z = b.z0 - r; } else { dx = 0; dz = 1; p.z = b.z1 + r; }
        }
        this.nx = dx; this.nz = dz; hit = true;
      }
      p.x = clamp(p.x, -HALF - 30, HALF + 30); p.z = clamp(p.z, -HALF - 30, HALF + 30);
      return hit;
    },
    groundAt(x, z, y) {
      let g = 0;
      for (const b of near(x, z)) if (b.h > g && x >= b.x0 && x <= b.x1 && z >= b.z0 && z <= b.z1 && y >= b.h - ROOF_TOL) g = b.h;
      return g;
    },
    inside(x, y, z) {
      if (y < 0) return true;
      for (const b of near(x, z)) if (y < b.h && x > b.x0 && x < b.x1 && z > b.z0 && z < b.z1) return true;
      return false;
    },
    // distance along a unit ray to the first building/ground hit, or Infinity beyond maxD
    ray(ox, oy, oz, dx, dy, dz, maxD) {
      let t = Infinity;
      for (const b of boxes) { const r = rayBox(ox, oy, oz, dx, dy, dz, b); if (r < t) t = r; }
      if (dy < -1e-6) { const g = -oy / dy; if (g > 0 && g < t) t = g; }
      return t <= maxD ? t : Infinity;
    },
    los(a, b) {
      const dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z, d = Math.hypot(dx, dy, dz);
      return d < 1e-3 || this.ray(a.x, a.y, a.z, dx / d, dy / d, dz / d, d) === Infinity;
    },
    // a random road position between rmin and rmax metres from (x, z): snap a point on that ring onto the nearest road line
    roadPointNear(x, z, rmin, rmax) {
      for (let t = 0; t < 10; t++) {
        const a = Math.random() * Math.PI * 2, r = rmin + Math.random() * (rmax - rmin);
        let px = x + Math.cos(a) * r, pz = z + Math.sin(a) * r;
        const snap = v => roadCenters.reduce((b, c) => (Math.abs(c - v) < Math.abs(b - v) ? c : b), roadCenters[0]) + (Math.random() * 2 - 1) * 7;
        if (Math.random() < 0.5) px = snap(px); else pz = snap(pz);
        const d = Math.hypot(px - x, pz - z);
        if (d >= rmin && d <= rmax && Math.abs(px) < HALF - 8 && Math.abs(pz) < HALF - 8) return { x: px, z: pz };
      }
      return null;
    },
    roadPoint() {
      const c = roadCenters[Math.floor(Math.random() * (N + 1))], u = (Math.random() * 2 - 1) * (HALF - 12), o = (Math.random() * 2 - 1) * 7;
      return Math.random() < 0.5 ? { x: u, z: c + o } : { x: c + o, z: u };
    },
  };
}
