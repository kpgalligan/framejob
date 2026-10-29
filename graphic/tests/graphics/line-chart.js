// line-chart — a bundled template (spec §11 G-44): `values` as a
// comma-separated string, a line drawn on through its points, a dot popping
// at each, an area fill behind and the last value called out.
export const meta = {
  name: "Line chart",
  category: "Data & Time",
  description: "A line drawn through its points, the last value called out.",
  durationInFrames: 150,
};

export const schema = {
  values: { type: "string",  default: "12, 18, 15, 26, 22, 34, 41", animate: false },
  labels: { type: "string",  default: "Jan, Feb, Mar, Apr, May, Jun, Jul", animate: false },
  title:  { type: "string",  default: "Monthly active users" },
  area:   { type: "boolean", default: true },
  accent: { type: "color",   default: "#2d7ff9" },
};

export function render(frame, props, ctx) {
  const u = Math.min(ctx.width, ctx.height) / 1080;
  const D = ctx.durationInFrames;
  const values = props.values.split(",").map((v) => Number(v.trim())).filter((v) => isFinite(v));
  const labels = props.labels.split(",").map((l) => l.trim());
  const n = values.length;
  const safeX = ctx.width * 0.05;
  const safeY = ctx.height * 0.05;
  const safeW = ctx.width * 0.9;
  const safeH = ctx.height * 0.9;
  const pad = 60 * u;
  const innerW = safeW - 2 * pad;
  const blockH = Math.min(safeH - 2 * pad, innerW * 1.35);
  const top = safeY + (safeH - blockH) / 2;
  const titleFont = { family: "Montserrat", weight: 900 };
  const titleSize = fitText(props.title, innerW, titleFont, { min: 12 * u, max: 64 * u });
  const left = safeX + pad;
  const right = left + innerW;
  const plotTop = top + titleSize + 110 * u;
  const base = top + blockH - 64 * u;
  const lo = Math.min(0, ...values);
  const hi = Math.max(lo + 1, ...values);
  const span = Math.max(1e-9, hi - lo);
  const labelFont = { family: "Montserrat", size: 28 * u, weight: 800 };
  const inset = Math.max(24 * u, ...labels.slice(0, n).map((l) => measureText(l, labelFont).width / 2 + 4 * u));
  const points = values.map((v, i) => ({
    x: n === 1 ? (left + right) / 2 : left + inset + ((innerW - 2 * inset) * i) / Math.max(1, n - 1),
    y: base - ((v - lo) / span) * (base - plotTop),
  }));
  const fade = interpolate(frame, [0, 15], [0, 1], { clamp: true });
  const out = interpolate(frame, [D - 15, D - 1], [1, 0], { clamp: true });
  const ease = (f) => interpolate(f, [10, 70], [0, 1], { easing: Easing.inOutCubic, clamp: true });
  const drawn = ease(frame);
  // Opacity per element (fill- and stroke-opacity), so no frame isolates a layer.
  const shown = fade * out;

  let grid = "";
  for (let i = 0; i <= 4; i++) {
    const y = base - ((base - plotTop) * i) / 4;
    grid += `<line x1="${left}" y1="${y}" x2="${right}" y2="${y}" stroke="#ffffff"
                   stroke-opacity="${(i === 0 ? 0.35 : 0.08) * shown}" stroke-width="${(i === 0 ? 3 : 2) * u}"/>`;
  }
  let axisLabels = "";
  points.forEach((p, i) => {
    axisLabels += `<text x="${p.x}" y="${base + 46 * u}" text-anchor="middle" font-family="Montserrat"
                         font-weight="800" font-size="${labelFont.size}" fill="#c8c8d0" fill-opacity="${shown}">${escapeXml(labels[i] || "")}</text>`;
  });

  let line = "";
  let areaFill = "";
  const reach = [0];
  if (n > 1) {
    let d = `M ${points[0].x} ${points[0].y}`;
    let total = 0;
    for (let i = 1; i < n; i++) {
      const a = points[i - 1];
      const b = points[i];
      const mid = (a.x + b.x) / 2;
      const seg = `C ${mid} ${a.y} ${mid} ${b.y} ${b.x} ${b.y}`;
      total += getLength(`M ${a.x} ${a.y} ${seg}`);
      reach.push(total);
      d += ` ${seg}`;
    }
    const dash = evolvePath(drawn, d);
    line = `<path d="${d}" fill="none" stroke="${props.accent}" stroke-opacity="${out}" stroke-width="${7 * u}" stroke-linecap="round"
                  stroke-linejoin="round" stroke-dasharray="${dash.strokeDasharray}"
                  stroke-dashoffset="${dash.strokeDashoffset}"/>`;
    if (props.area) {
      const areaIn = interpolate(frame, [30, 80], [0, 0.25], { easing: Easing.inOutSine, clamp: true });
      areaFill = `<path d="${d} L ${points[n - 1].x} ${base} L ${points[0].x} ${base} Z" fill="${props.accent}"
                        fill-opacity="${areaIn * out}"/>`;
    }
    for (let i = 0; i < n; i++) reach[i] = reach[i] / Math.max(1e-9, total);
  }
  // The frame at which the line reaches point i: the first frame whose eased progress passes it.
  const reachFrame = (fraction) => {
    for (let f = 10; f <= 70; f++) if (ease(f) >= fraction - 1e-6) return f;
    return 70;
  };
  let dots = "";
  points.forEach((p, i) => {
    const at = n > 1 ? reachFrame(reach[i]) : 14;
    const s = spring({ frame: frame - at, fps: ctx.fps, stiffness: 220, damping: 11 });
    if (s <= 0.001) return;
    dots += `<circle cx="${p.x}" cy="${p.y}" r="${11 * u * s}" fill="#15151b" fill-opacity="${out}"
                     stroke="${props.accent}" stroke-opacity="${out}" stroke-width="${5 * u}"/>`;
  });
  let callout = "";
  if (n > 0) {
    const last = points[n - 1];
    const at = (n > 1 ? reachFrame(1) : 14) + 4;
    const s = spring({ frame: frame - at, fps: ctx.fps, stiffness: 180, damping: 12 });
    const text = formatNumber(values[n - 1], { decimals: Number.isInteger(values[n - 1]) ? 0 : 1 });
    const font = { family: "Montserrat", size: 34 * u, weight: 800 };
    const w = measureText(text, font).width + 36 * u;
    const h = 54 * u;
    const cx = Math.min(right - w / 2, Math.max(left + w / 2, last.x));
    const cy = last.y - 30 * u - h / 2;
    if (s > 0.001) {
      callout = `<g transform="translate(${cx} ${cy}) scale(${s})">
        <rect x="${-w / 2}" y="${-h / 2}" width="${w}" height="${h}" rx="${h / 2}" fill="${props.accent}" fill-opacity="${out}"/>
        <text x="0" y="${12 * u}" text-anchor="middle" font-family="Montserrat" font-weight="800"
              font-size="${font.size}" fill="#ffffff" fill-opacity="${out}">${escapeXml(text)}</text></g>`;
    }
  }
  return svg(ctx, `
    <text x="${left}" y="${top + titleSize * 0.8}" font-family="Montserrat" font-weight="900"
          font-size="${titleSize}" fill="#ffffff" fill-opacity="${shown}">${escapeXml(props.title)}</text>
    ${grid}${axisLabels}${areaFill}${line}${dots}${callout}`, { background: "#15151b" });
}
