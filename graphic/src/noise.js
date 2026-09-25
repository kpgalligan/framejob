// Simplex noise for the graphics standard library — road map 10 §5c.
// Written from scratch after the published simplex construction (skewed
// simplex grid, gradient table, radial falloff). Evaluated as a SCRIPT after
// `stdlib.js`, so `noise2D` and `noise3D` are globals. Each answers a value
// in [-1, 1] that depends only on its arguments.

const __noise = (() => {
  const GRAD3 = [
    [1, 1, 0], [-1, 1, 0], [1, -1, 0], [-1, -1, 0],
    [1, 0, 1], [-1, 0, 1], [1, 0, -1], [-1, 0, -1],
    [0, 1, 1], [0, -1, 1], [0, 1, -1], [0, -1, -1],
  ];
  const tables = new Map();

  // The seed's permutation of 0–255, doubled to 512 entries: a Fisher–Yates
  // shuffle driven by splitmix32 from an FNV-1a hash of `String(seed)` (the
  // hash `random` uses). Cached per seed; a cache changes no answer.
  function permutation(seed) {
    const key = String(seed);
    let perm = tables.get(key);
    if (perm) return perm;
    let h = 0x811c9dc5;
    for (let i = 0; i < key.length; i++) {
      h ^= key.charCodeAt(i);
      h = Math.imul(h, 0x01000193);
    }
    let state = h | 0;
    const next = () => {
      state = (state + 0x9e3779b9) | 0;
      let t = state ^ (state >>> 16);
      t = Math.imul(t, 0x21f0aaad);
      t ^= t >>> 15;
      t = Math.imul(t, 0x735a2d97);
      t ^= t >>> 15;
      return t >>> 0;
    };
    const p = [];
    for (let i = 0; i < 256; i++) p.push(i);
    for (let i = 255; i > 0; i--) {
      const j = next() % (i + 1);
      const swap = p[i];
      p[i] = p[j];
      p[j] = swap;
    }
    perm = new Uint8Array(512);
    for (let i = 0; i < 512; i++) perm[i] = p[i & 255];
    if (tables.size >= 64) tables.clear();
    tables.set(key, perm);
    return perm;
  }

  const clamp = (v) => Math.max(-1, Math.min(1, v));

  function noise2D(seed, x, y) {
    const perm = permutation(seed);
    const F2 = 0.5 * (Math.sqrt(3) - 1);
    const G2 = (3 - Math.sqrt(3)) / 6;
    const s = (x + y) * F2;
    const i = Math.floor(x + s);
    const j = Math.floor(y + s);
    const t = (i + j) * G2;
    const x0 = x - (i - t);
    const y0 = y - (j - t);
    const i1 = x0 > y0 ? 1 : 0;
    const j1 = x0 > y0 ? 0 : 1;
    const corners = [
      [x0, y0, 0, 0],
      [x0 - i1 + G2, y0 - j1 + G2, i1, j1],
      [x0 - 1 + 2 * G2, y0 - 1 + 2 * G2, 1, 1],
    ];
    const ii = i & 255;
    const jj = j & 255;
    let sum = 0;
    for (const [cx, cy, di, dj] of corners) {
      const falloff = 0.5 - cx * cx - cy * cy;
      if (falloff <= 0) continue;
      const g = GRAD3[perm[ii + di + perm[jj + dj]] % 12];
      const f2 = falloff * falloff;
      sum += f2 * f2 * (g[0] * cx + g[1] * cy);
    }
    return clamp(70 * sum);
  }

  function noise3D(seed, x, y, z) {
    const perm = permutation(seed);
    const F3 = 1 / 3;
    const G3 = 1 / 6;
    const s = (x + y + z) * F3;
    const i = Math.floor(x + s);
    const j = Math.floor(y + s);
    const k = Math.floor(z + s);
    const t = (i + j + k) * G3;
    const x0 = x - (i - t);
    const y0 = y - (j - t);
    const z0 = z - (k - t);
    let o1;
    let o2;
    if (x0 >= y0) {
      if (y0 >= z0) { o1 = [1, 0, 0]; o2 = [1, 1, 0]; }
      else if (x0 >= z0) { o1 = [1, 0, 0]; o2 = [1, 0, 1]; }
      else { o1 = [0, 0, 1]; o2 = [1, 0, 1]; }
    } else if (y0 < z0) { o1 = [0, 0, 1]; o2 = [0, 1, 1]; }
    else if (x0 < z0) { o1 = [0, 1, 0]; o2 = [0, 1, 1]; }
    else { o1 = [0, 1, 0]; o2 = [1, 1, 0]; }
    const offsets = [[0, 0, 0], o1, o2, [1, 1, 1]];
    const ii = i & 255;
    const jj = j & 255;
    const kk = k & 255;
    let sum = 0;
    offsets.forEach(([di, dj, dk], n) => {
      const cx = x0 - di + n * G3;
      const cy = y0 - dj + n * G3;
      const cz = z0 - dk + n * G3;
      const falloff = 0.6 - cx * cx - cy * cy - cz * cz;
      if (falloff <= 0) return;
      const g = GRAD3[perm[ii + di + perm[jj + dj + perm[kk + dk]]] % 12];
      const f2 = falloff * falloff;
      sum += f2 * f2 * (g[0] * cx + g[1] * cy + g[2] * cz);
    });
    return clamp(32 * sum);
  }

  return { noise2D, noise3D };
})();

function noise2D(seed, x, y) {
  return __noise.noise2D(seed, x, y);
}

function noise3D(seed, x, y, z) {
  return __noise.noise3D(seed, x, y, z);
}
