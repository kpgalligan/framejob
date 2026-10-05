// Path helpers for the graphics standard library — spec §11 G-31. Written
// from scratch (G-2): the three names and their argument orders follow
// Remotion's, none of its code, nor any other library's, is here. Evaluated
// as a SCRIPT after `noise.js` and before the sandbox, so `getLength`,
// `getPointAtLength` and `evolvePath` are globals. A path is measured as its
// flattening: a line exactly, a `C S Q T` as __PATH_CHORDS chords at uniform
// parameter, an arc as chords of at most __PATH_ARC_STEP of sweep.

const __PATH_CHORDS = 64;
const __PATH_ARC_STEP = Math.PI / 128;
// `evolvePath`'s dash is this much longer than the measure, so a closed
// outline closes at progress 1.
const __PATH_PAD = 1.001;
// The memo's two bounds: paths, and chords plus characters in all.
const __PATH_MEMO = 32;
const __PATH_MEMO_COST = 50000;

const __path = (() => {
  // The measured paths by their `d` text. In this closure so that no module
  // can read or change what is held (G-5); a cache changes no answer.
  const memo = new Map();
  let held = 0;
  const ARGS = { M: 2, L: 2, H: 1, V: 1, C: 6, S: 4, Q: 4, T: 2, A: 7, Z: 0 };
  const digit = (c) => c >= 48 && c <= 57;
  // Every number read, every move, every arc's centre form, every running
  // length and every point answered is held to this, so that no helper
  // answers Infinity or NaN: the path is refused at the number or command.
  const finite = (...values) => values.every(Number.isFinite);

  function refuse(d, who, i) {
    throw new Error(`${who}: cannot parse the path at character ${i}: "${d.slice(i, i + 12)}"`);
  }

  // `d` as absolute segments in drawing order: `{kind, n, p, sub, at, src}` —
  // kind 0 a line, 1 a quadratic, 2 a cubic, 3 an arc in centre form; `n` its
  // chords, `p` its points, `sub` its subpath, `at` its first chord, `src`
  // the character its command (or its repeat of one) begins at.
  function parse(d, who) {
    const fail = (i) => refuse(d, who, i);
    const end = d.length;
    const segs = [];
    let i = 0;
    let src = 0;               // where the command being read begins
    let chords = 0;
    let x = 0, y = 0;          // the current point
    let sx = 0, sy = 0;        // the subpath's start
    let mx = 0, my = 0;        // the last move
    let cx = 0, cy = 0;        // the last curve's last control point
    let family = "";           // "C" or "Q" while the last segment was that curve
    let sub = -1;
    let closed = false;

    const skip = () => {
      for (;;) {
        const c = d.charCodeAt(i);
        if (c === 32 || c === 44 || c === 9 || c === 10 || c === 12 || c === 13) i++;
        else return;
      }
    };
    const wanted = () => {
      skip();
      if (i >= end) throw new Error(`${who}: the path ends inside a command`);
    };
    const number = () => {
      wanted();
      const from = i;
      let c = d.charCodeAt(i);
      if (c === 43 || c === 45) c = d.charCodeAt(++i);
      let digits = 0;
      while (digit(c)) { digits++; c = d.charCodeAt(++i); }
      if (c === 46) {
        c = d.charCodeAt(++i);
        while (digit(c)) { digits++; c = d.charCodeAt(++i); }
      }
      if (digits === 0) fail(from);
      if (c === 101 || c === 69) {
        let k = i + 1;
        const sign = d.charCodeAt(k);
        if (sign === 43 || sign === 45) k++;
        if (digit(d.charCodeAt(k))) {
          while (digit(d.charCodeAt(k))) k++;
          i = k;
        }
      }
      const value = Number(d.slice(from, i));
      if (!finite(value)) fail(from);
      return value;
    };
    const flag = () => {
      wanted();
      const c = d.charCodeAt(i);
      if (c !== 48 && c !== 49) fail(i);
      i++;
      return c === 49;
    };

    const add = (seg) => {
      if (closed) { sub++; closed = false; }
      seg.sub = sub;
      seg.src = src;
      seg.at = chords;
      chords += seg.n;
      segs.push(seg);
    };
    const line = (x1, y1) => {
      add({ kind: 0, n: 1, p: [x, y, x1, y1] });
      x = x1; y = y1; family = "";
    };
    const quad = (x1, y1, x2, y2) => {
      add({ kind: 1, n: __PATH_CHORDS, p: [x, y, x1, y1, x2, y2] });
      cx = x1; cy = y1; x = x2; y = y2; family = "Q";
    };
    const cubic = (x1, y1, x2, y2, x3, y3) => {
      add({ kind: 2, n: __PATH_CHORDS, p: [x, y, x1, y1, x2, y2, x3, y3] });
      cx = x2; cy = y2; x = x3; y = y3; family = "C";
    };
    // SVG's end-point to centre conversion: radii too small for the chord
    // are scaled up, and the radicand is clamped at 0 so no length is NaN.
    const arc = (rx0, ry0, rotation, large, sweep, x1, y1) => {
      let rx = Math.abs(rx0);
      let ry = Math.abs(ry0);
      if (rx === 0 || ry === 0 || (x === x1 && y === y1)) return line(x1, y1);
      const phi = rotation * Math.PI / 180;
      const cos = Math.cos(phi);
      const sin = Math.sin(phi);
      const hx = (x - x1) / 2;
      const hy = (y - y1) / 2;
      const px = cos * hx + sin * hy;
      const py = cos * hy - sin * hx;
      const lambda = (px * px) / (rx * rx) + (py * py) / (ry * ry);
      if (lambda > 1) { rx *= Math.sqrt(lambda); ry *= Math.sqrt(lambda); }
      const spread = rx * rx * py * py + ry * ry * px * px;
      const k = (large === sweep ? -1 : 1) * Math.sqrt(Math.max(0, (rx * rx * ry * ry - spread) / spread));
      const qx = k * rx * py / ry;
      const qy = -k * ry * px / rx;
      const t1 = Math.atan2((py - qy) / ry, (px - qx) / rx);
      let dt = Math.atan2((-py - qy) / ry, (-px - qx) / rx) - t1;
      if (sweep && dt < 0) dt += 2 * Math.PI;
      if (!sweep && dt > 0) dt -= 2 * Math.PI;
      const seg = {
        kind: 3, n: Math.max(1, Math.ceil(Math.abs(dt) / __PATH_ARC_STEP)), p: [x, y, x1, y1],
        cx: cos * qx - sin * qy + (x + x1) / 2, cy: sin * qx + cos * qy + (y + y1) / 2,
        rx, ry, cos, sin, t1, dt,
      };
      // Radii or a chord past what a double's arithmetic holds leave no centre.
      if (!finite(seg.n, seg.cx, seg.cy, rx, ry)) fail(src);
      add(seg);
      x = x1; y = y1; family = "";
    };

    skip();
    while (i < end) {
      const ch = d[i];
      const upper = ch >= "a" && ch <= "z" ? ch.toUpperCase() : ch;
      if (ARGS[upper] === undefined || (sub < 0 && upper !== "M")) fail(i);
      const rel = ch !== upper;
      src = i++;
      if (upper === "Z") {
        line(sx, sy);
        closed = true;
        skip();
        continue;
      }
      let command = upper;
      for (;;) {
        const ox = rel ? x : 0;
        const oy = rel ? y : 0;
        if (command === "M") {
          x = ox + number(); y = oy + number();
          if (!finite(x, y)) fail(src);
          sx = x; sy = y; mx = x; my = y;
          sub++; closed = false; family = "";
          command = "L";       // the pairs after a move are lines
        } else if (command === "L") {
          const px = number();
          line(ox + px, oy + number());
        } else if (command === "H") {
          line(ox + number(), y);
        } else if (command === "V") {
          line(x, oy + number());
        } else if (command === "C") {
          const a = [number(), number(), number(), number(), number(), number()];
          cubic(ox + a[0], oy + a[1], ox + a[2], oy + a[3], ox + a[4], oy + a[5]);
        } else if (command === "S") {
          const a = [number(), number(), number(), number()];
          const same = family === "C";
          cubic(same ? 2 * x - cx : x, same ? 2 * y - cy : y, ox + a[0], oy + a[1], ox + a[2], oy + a[3]);
        } else if (command === "Q") {
          const a = [number(), number(), number(), number()];
          quad(ox + a[0], oy + a[1], ox + a[2], oy + a[3]);
        } else if (command === "T") {
          const a = [number(), number()];
          const same = family === "Q";
          quad(same ? 2 * x - cx : x, same ? 2 * y - cy : y, ox + a[0], oy + a[1]);
        } else {
          const a = [number(), number(), number(), flag(), flag(), number(), number()];
          arc(a[0], a[1], a[2], a[3], a[4], ox + a[5], oy + a[6]);
        }
        skip();
        const c = d.charCodeAt(i);
        if (!(digit(c) || c === 43 || c === 45 || c === 46)) break;
        src = i;
      }
    }
    return { segs, chords, move: [mx, my] };
  }

  // The point of `seg` at parameter `t` and the derivative there, into
  // `out` as x, y, dx, dy. Exact at both ends.
  function evaluate(seg, t, out) {
    const p = seg.p;
    const u = 1 - t;
    if (seg.kind === 0) {
      out[0] = u * p[0] + t * p[2];
      out[1] = u * p[1] + t * p[3];
      out[2] = p[2] - p[0];
      out[3] = p[3] - p[1];
    } else if (seg.kind === 1) {
      out[0] = u * u * p[0] + 2 * u * t * p[2] + t * t * p[4];
      out[1] = u * u * p[1] + 2 * u * t * p[3] + t * t * p[5];
      out[2] = 2 * (u * (p[2] - p[0]) + t * (p[4] - p[2]));
      out[3] = 2 * (u * (p[3] - p[1]) + t * (p[5] - p[3]));
    } else if (seg.kind === 2) {
      const a = u * u * u;
      const b = 3 * u * u * t;
      const c = 3 * u * t * t;
      const e = t * t * t;
      out[0] = a * p[0] + b * p[2] + c * p[4] + e * p[6];
      out[1] = a * p[1] + b * p[3] + c * p[5] + e * p[7];
      out[2] = 3 * (u * u * (p[2] - p[0]) + 2 * u * t * (p[4] - p[2]) + t * t * (p[6] - p[4]));
      out[3] = 3 * (u * u * (p[3] - p[1]) + 2 * u * t * (p[5] - p[3]) + t * t * (p[7] - p[5]));
    } else {
      const theta = seg.t1 + t * seg.dt;
      const c = Math.cos(theta);
      const s = Math.sin(theta);
      const turn = seg.dt < 0 ? -1 : 1;
      if (t === 0 || t === 1) {
        out[0] = p[2 * t];
        out[1] = p[2 * t + 1];
      } else {
        out[0] = seg.cx + seg.rx * c * seg.cos - seg.ry * s * seg.sin;
        out[1] = seg.cy + seg.rx * c * seg.sin + seg.ry * s * seg.cos;
      }
      out[2] = turn * (-seg.rx * s * seg.cos - seg.ry * c * seg.sin);
      out[3] = turn * (-seg.rx * s * seg.sin + seg.ry * c * seg.cos);
    }
  }

  // The tangent's limit where a curve's derivative is (0, 0): at its start
  // the direction to the first later point that differs from it, at its end
  // the direction from the last earlier point that differs, and inside (a
  // cusp) the direction of chord `j`, which the point lies on.
  function limit(seg, j, t) {
    const p = seg.p;
    const last = p.length - 2;
    if (t === 0) {
      for (let k = 2; k <= last; k += 2) {
        if (p[k] !== p[0] || p[k + 1] !== p[1]) return [p[k] - p[0], p[k + 1] - p[1]];
      }
    }
    if (t === 1) {
      for (let k = last - 2; k >= 0; k -= 2) {
        if (p[k] !== p[last] || p[k + 1] !== p[last + 1]) return [p[last] - p[k], p[last + 1] - p[k + 1]];
      }
    }
    const a = [0, 0, 0, 0];
    const b = [0, 0, 0, 0];
    evaluate(seg, j / seg.n, a);
    evaluate(seg, (j + 1) / seg.n, b);
    return [b[0] - a[0], b[1] - a[1]];
  }

  // The flattening: `cum[i]` is the length up to the end of chord `i`,
  // `longest` the longest subpath's length.
  function measure(d, who) {
    const { segs, chords, move } = parse(d, who);
    const cum = new Float64Array(chords);
    const out = [0, 0, 0, 0];
    let total = 0;
    let longest = 0;
    let sub = -1;
    let before = 0;
    for (const seg of segs) {
      if (seg.sub !== sub) {
        longest = Math.max(longest, total - before);
        before = total;
        sub = seg.sub;
      }
      let px = seg.p[0];
      let py = seg.p[1];
      for (let j = 1; j <= seg.n; j++) {
        evaluate(seg, j / seg.n, out);
        total += Math.sqrt((out[0] - px) * (out[0] - px) + (out[1] - py) * (out[1] - py));
        cum[seg.at + j - 1] = total;
        px = out[0];
        py = out[1];
      }
      // A point or a chord's square past a double's range lands here. The
      // total is padded so that `evolvePath`'s dash is finite when it is.
      if (!finite(total * __PATH_PAD)) refuse(d, who, seg.src);
    }
    longest = Math.max(longest, total - before);
    return { segs, cum, total, longest, move, cost: chords + d.length };
  }

  // `d` measured, from the memo when it holds it. Before an insert that
  // would pass either bound the memo is cleared whole, and the new path is
  // then kept — so a path over the cost bound alone is not measured twice
  // by the calls that follow it.
  function measured(d, who) {
    const key = String(d);
    let path = memo.get(key);
    if (path) return path;
    path = measure(key, who);
    if (memo.size >= __PATH_MEMO || held + path.cost > __PATH_MEMO_COST) {
      memo.clear();
      held = 0;
    }
    memo.set(key, path);
    held += path.cost;
    return path;
  }

  function getLength(d) {
    return measured(d, "getLength").total;
  }

  function getPointAtLength(d, length) {
    const { segs, cum, total, move } = measured(d, "getPointAtLength");
    if (!(total > 0)) return { x: move[0], y: move[1], angle: 0 };
    let at = Number(length);
    if (!(at > 0)) at = 0;
    if (at > total) at = total;
    // The first chord of non-zero length that ends at or after `at`.
    let lo = 0;
    let hi = cum.length - 1;
    while (lo < hi) {
      const mid = (lo + hi) >> 1;
      if (cum[mid] >= at && cum[mid] > 0) hi = mid;
      else lo = mid + 1;
    }
    const start = lo > 0 ? cum[lo - 1] : 0;
    const within = (at - start) / (cum[lo] - start);
    let first = 0;
    let past = segs.length - 1;
    while (first < past) {
      const mid = (first + past + 1) >> 1;
      if (segs[mid].at <= lo) first = mid;
      else past = mid - 1;
    }
    const seg = segs[first];
    const j = lo - seg.at;
    const t = (j + within) / seg.n;
    const out = [0, 0, 0, 0];
    evaluate(seg, t, out);
    const heading = out[2] === 0 && out[3] === 0 ? limit(seg, j, t) : [out[2], out[3]];
    const angle = Math.atan2(heading[1], heading[0]) * 180 / Math.PI;
    if (!finite(out[0], out[1], angle)) refuse(String(d), "getPointAtLength", seg.src);
    return { x: out[0], y: out[1], angle };
  }

  function evolvePath(progress, d) {
    const longest = measured(d, "evolvePath").longest;
    let p = Number(progress);
    if (!(p > 0)) p = 0;
    if (p > 1) p = 1;
    if (!(longest > 0)) return { strokeDasharray: "none", strokeDashoffset: 0 };
    const dash = longest * __PATH_PAD;
    return { strokeDasharray: `${dash} ${dash}`, strokeDashoffset: dash * (1 - p) };
  }

  return { getLength, getPointAtLength, evolvePath };
})();

function getLength(d) {
  return __path.getLength(d);
}

function getPointAtLength(d, length) {
  return __path.getPointAtLength(d, length);
}

function evolvePath(progress, d) {
  return __path.evolvePath(progress, d);
}
