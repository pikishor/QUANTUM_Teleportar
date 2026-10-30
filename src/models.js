import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

// Low-poly models are baked into a few merged, vertex-coloured meshes to keep draw calls down on phones.
const BOX = new THREE.BoxGeometry(1, 1, 1), SPH = new THREE.SphereGeometry(0.5, 10, 8);
const CYL = new THREE.CylinderGeometry(0.5, 0.5, 1, 10), OCT = new THREE.OctahedronGeometry(0.5);
const _m = new THREE.Matrix4(), _q = new THREE.Quaternion(), _e = new THREE.Euler(), _v = new THREE.Vector3(), _s = new THREE.Vector3(), _c = new THREE.Color();

export const MAT_LIT = new THREE.MeshLambertMaterial({ vertexColors: true });
export const MAT_GLOW = new THREE.MeshBasicMaterial({ vertexColors: true });

function part(geo, color, x = 0, y = 0, z = 0, sx = 1, sy = 1, sz = 1, rx = 0, ry = 0, rz = 0) {
  const g = geo.index ? geo.toNonIndexed() : geo.clone();
  g.applyMatrix4(_m.compose(_v.set(x, y, z), _q.setFromEuler(_e.set(rx, ry, rz)), _s.set(sx, sy, sz)));
  _c.set(color);
  const n = g.attributes.position.count, a = new Float32Array(n * 3);
  for (let i = 0; i < n; i++) { a[i * 3] = _c.r; a[i * 3 + 1] = _c.g; a[i * 3 + 2] = _c.b; }
  g.setAttribute('color', new THREE.BufferAttribute(a, 3));
  return g;
}
const B = (c, x, y, z, w, h, d, ...r) => part(BOX, c, x, y, z, w, h, d, ...r);
const S = (c, x, y, z, w, h, d) => part(SPH, c, x, y, z, w, h, d);
const C = (c, x, y, z, w, h, d, ...r) => part(CYL, c, x, y, z, w, h, d, ...r);

// ---- enemies: hovering Observer drones -------------------------------------------------------
export const ENEMY = {
  sentinel: { hp: 60, speed: 4.6, range: 22, fire: [1.0, 1.7], dmg: 7, bolt: 30, burst: 1, color: 0xff3d5e, scale: 1, score: 50, radius: 0.95, heat: 0.22 },
  striker: { hp: 34, speed: 10.5, range: 0, kamikaze: true, dmg: 30, color: 0xffa03a, scale: 0.85, score: 40, radius: 0.8, heat: 0.15 },
  heavy: { hp: 230, speed: 3.0, range: 30, fire: [1.5, 2.1], dmg: 9, bolt: 26, burst: 3, color: 0xb35cff, scale: 1.5, score: 160, radius: 1.35, heat: 0.5 },
};
const enemyCache = {};
export function enemyMesh(type) {
  const T = ENEMY[type], c = T.color;
  if (!enemyCache[type]) {
    let lit, glow;
    if (type === 'sentinel') {
      lit = [B(0x2a2a3a, 0, 0.95, 0, 0.95, 0.6, 0.95), B(0x3d3d55, 0, 1.28, 0, 1.1, 0.14, 1.1), B(0x20202c, -0.62, 0.95, -0.25, 0.16, 0.16, 0.8), B(0x20202c, 0.62, 0.95, -0.25, 0.16, 0.16, 0.8), B(0x20202c, 0, 0.95, 0.5, 0.5, 0.4, 0.2)];
      glow = [S(c, 0, 1.0, -0.5, 0.42, 0.42, 0.3), C(c, 0, 0.55, 0, 1.5, 0.05, 1.5)];
    } else if (type === 'striker') {
      lit = [part(OCT, 0x2b1b1b, 0, 0.95, 0, 1.4, 1.4, 1.4), B(0x3a2424, 0, 0.95, 0, 0.2, 1.9, 0.2), B(0x3a2424, 0, 0.95, 0, 1.9, 0.2, 0.2), B(0x3a2424, 0, 0.95, 0, 0.2, 0.2, 1.9)];
      glow = [S(c, 0, 0.95, 0, 0.7, 0.7, 0.7)];
    } else {
      lit = [B(0x2b2338, 0, 1.0, 0, 1.3, 0.9, 1.1), B(0x4a3a66, 0, 1.55, 0, 1.5, 0.2, 1.3), B(0x20182c, -0.95, 1.1, -0.4, 0.3, 0.3, 1.1), B(0x20182c, 0.95, 1.1, -0.4, 0.3, 0.3, 1.1), B(0x1e1a2b, 0, 0.55, 0, 1.1, 0.3, 1.0)];
      glow = [B(c, 0, 1.1, -0.56, 0.9, 0.14, 0.05), C(c, 0, 0.35, 0, 1.7, 0.05, 1.7)];
    }
    enemyCache[type] = { lit: mergeGeometries(lit), glow: mergeGeometries(glow) };
  }
  const g = new THREE.Group();
  g.add(new THREE.Mesh(enemyCache[type].lit, MAT_LIT), new THREE.Mesh(enemyCache[type].glow, MAT_GLOW));
  g.scale.setScalar(T.scale);
  return g;
}

// ---- cars ------------------------------------------------------------------------------------
export const CAR_COLORS = [0xd8264a, 0x2a6df4, 0xf0b429, 0x2ecf9a, 0x8a4bff, 0xe9e9f5, 0xff6a2b, 0x1a1f33];
export const CAR_GLOW = [0x38f5ff, 0xff3df0, 0x38ffb0, 0x9b6bff];
const carCache = {};
export function carMesh(colorIdx, glowIdx, sport) {
  const key = `${colorIdx}_${glowIdx}_${sport}`;
  if (!carCache[key]) {
    const body = CAR_COLORS[colorIdx], glass = 0x0e1830;
    const lit = [B(body, 0, 0.58, 0, 2.0, 0.6, 4.4), B(glass, 0, 1.1, 0.2, 1.7, 0.55, 2.1), B(body, 0, 1.4, 0.2, 1.6, 0.08, 1.8)];
    for (const x of [-1.0, 1.0]) for (const z of [-1.4, 1.4]) lit.push(C(0x0b0b12, x, 0.42, z, 0.84, 0.3, 0.84, 0, 0, Math.PI / 2));
    if (sport) lit.push(B(body, 0, 1.45, 1.95, 1.9, 0.08, 0.5), B(0x15151f, -0.8, 1.2, 1.95, 0.08, 0.5, 0.3), B(0x15151f, 0.8, 1.2, 1.95, 0.08, 0.5, 0.3));
    const g = CAR_GLOW[glowIdx];
    const glow = [B(0xfff2b0, -0.7, 0.62, -2.21, 0.45, 0.18, 0.08), B(0xfff2b0, 0.7, 0.62, -2.21, 0.45, 0.18, 0.08),
      B(0xff2244, -0.7, 0.68, 2.21, 0.45, 0.14, 0.08), B(0xff2244, 0.7, 0.68, 2.21, 0.45, 0.14, 0.08), B(g, 0, 0.16, 0, 2.1, 0.06, 4.5)];
    carCache[key] = { lit: mergeGeometries(lit), glow: mergeGeometries(glow) };
  }
  const grp = new THREE.Group();
  grp.add(new THREE.Mesh(carCache[key].lit, MAT_LIT), new THREE.Mesh(carCache[key].glow, MAT_GLOW));
  return grp;
}

// ---- player / hologram -----------------------------------------------------------------------
export function buildPlayerModel(holo = false) {
  const mk = (c, emissive) => holo
    ? new THREE.MeshBasicMaterial({ color: 0x66ffee, transparent: true, opacity: 0.4, depthWrite: false, blending: THREE.AdditiveBlending })
    : emissive ? new THREE.MeshBasicMaterial({ color: c }) : new THREE.MeshLambertMaterial({ color: c });
  const g = new THREE.Group(), suit = mk(0x232b52), armor = mk(0x3c4d8a), glow = mk(0x4ff0ff, true), dark = mk(0x15171f);
  const add = (geo, mat, x, y, z) => { const m = new THREE.Mesh(geo, mat); m.position.set(x, y, z); g.add(m); return m; };
  const legGeo = new THREE.BoxGeometry(0.26, 0.85, 0.3).translate(0, -0.425, 0);
  const legL = add(legGeo, suit, -0.17, 0.85, 0), legR = add(legGeo, suit, 0.17, 0.85, 0);
  add(new THREE.BoxGeometry(0.62, 0.7, 0.38), armor, 0, 1.2, 0);
  add(new THREE.BoxGeometry(0.3, 0.3, 0.3), suit, 0, 1.72, 0);
  add(new THREE.BoxGeometry(0.26, 0.09, 0.05), glow, 0, 1.74, -0.16);
  add(new THREE.BoxGeometry(0.14, 0.5, 0.14), suit, -0.4, 1.25, 0);
  add(new THREE.BoxGeometry(0.14, 0.14, 0.6), suit, 0.34, 1.25, -0.3);
  add(new THREE.BoxGeometry(0.1, 0.14, 0.85), dark, 0.3, 1.2, -0.6);
  add(new THREE.BoxGeometry(0.03, 0.03, 0.25), glow, 0.3, 1.28, -0.55);
  add(new THREE.BoxGeometry(0.4, 0.5, 0.18), armor, 0, 1.25, 0.28);
  add(new THREE.BoxGeometry(0.3, 0.08, 0.05), glow, 0, 1.4, 0.38);
  const muzzle = new THREE.Object3D(); muzzle.position.set(0.3, 1.22, -1.05); g.add(muzzle);
  return { group: g, legL, legR, muzzle };
}

// ---- pickups ---------------------------------------------------------------------------------
export function pickupMesh(kind) {
  const col = kind === 'health' ? 0x44ff88 : 0x4ff0ff;
  const g = new THREE.Group();
  g.add(new THREE.Mesh(new THREE.OctahedronGeometry(0.45), new THREE.MeshBasicMaterial({ color: col })));
  const ring = new THREE.Mesh(new THREE.TorusGeometry(0.7, 0.05, 6, 20), new THREE.MeshBasicMaterial({ color: col, transparent: true, opacity: 0.6, blending: THREE.AdditiveBlending, depthWrite: false }));
  ring.rotation.x = Math.PI / 2; g.add(ring);
  return g;
}
