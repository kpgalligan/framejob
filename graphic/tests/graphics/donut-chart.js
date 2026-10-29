// donut-chart — a bundled template (spec §11 G-44): `values` as a
// comma-separated string, slices sweeping clockwise in turn, the first
// slice's share counting up in the centre and a staggered legend.
export const meta = {
  name: "Donut chart",
  durationInFrames: 150,
};

export const schema = {
  values: { type: "string", default: "45, 30, 15, 10", animate: false },
  labels: { type: "string", default: "Video, Audio, Graphics, Other", animate: false },
  title:  { type: "string", default: "Where the time goes" },
  accent: { type: "color",  default: "#ff5a36" },
};

const PALETTE = ["#2d7ff9", "#ffd60a", "#34c759", "#af52de", "#ff9f0a", "#5ac8fa"];

// An arc of the circle (cx, cy, r) from angle a0 to a1, in degrees clockwise
// from twelve o'clock; a full turn is two half arcs.
function arc(cx, cy, r, a0, a1) {
  const at = (a) => {
    const t = ((a - 90) * Math.PI) / 180;
    return `${cx + r * Math.cos(t)} ${cy + r * Math.sin(t)}`;
  };
  if (a1 - a0 >= 359.99) {
    return `M ${at(a0)} A ${r} ${r} 0 1 1 ${at(a0 + 180)} A ${r} ${r} 0 1 1 ${at(a0 + 359.99)}`;
  }
  return `M ${at(a0)} A ${r} ${r} 0 ${a1 - a0 > 180 ? 1 : 0} 1 ${at(a1)}`;
}

export function render(frame, props, ctx) {
  const u = Math.min(ctx.width, ctx.height) / 1080;
  const D = ctx.durationInFrames;
  const values = props.values.split(",").map((v) => Number(v.trim())).filter((v) => isFinite(v))
    .map((v) => Math.max(0, v));
  const labels = props.labels.split(",").map((l) => l.trim());
  const n = values.length;
  const total = values.reduce((a, b) => a + b, 0);
  // A square frame takes the side-by-side layout: a column would not fit its height.
  const landscape = ctx.width >= ctx.height;
  const safeX = ctx.width * 0.05;
  const safeY = ctx.height * 0.05;
  const safeW = ctx.width * 0.9;
  const safeH = ctx.height * 0.9;
  const pad = 60 * u;
  const innerW = safeW - 2 * pad;
  const titleSize = fitText(props.title, innerW, { family: "Montserrat", weight: 900 }, { min: 12 * u, max: 64 * u });
  const rowH = Math.min(78 * u, (landscape ? safeH - 300 * u : 560 * u) / Math.max(1, n));
  const legendH = rowH * n;
  const thick = 64 * u;
  let legendW = Math.min(620 * u, innerW);
  let R;
  let cx;
  let cy;
  let legendX;
  let legendY;
  let blockTop;
  if (landscape) {
    // The donut leaves the legend at least 360u beside it (a square frame's narrow width).
    const gapL = Math.min(140 * u, innerW * 0.1);
    R = Math.min((safeH - 2 * pad - titleSize - 100 * u) / 2 - thick / 2, innerW * 0.22,
      (innerW - thick - gapL - 360 * u) / 2);
    legendW = Math.min(620 * u, innerW - 2 * R - thick - gapL);
    blockTop = safeY + Math.max(pad, (safeH - (titleSize + 70 * u + 2 * R + thick)) / 2);
    const blockW = 2 * R + thick + gapL + legendW;
    cx = Math.max(safeX + pad, (ctx.width - blockW) / 2) + thick / 2 + R;
    cy = blockTop + titleSize + 70 * u + thick / 2 + R;
    legendX = cx + R + thick / 2 + gapL;
    legendY = cy - legendH / 2;
  } else {
    R = innerW * 0.3;
    const blockH = titleSize + 80 * u + 2 * R + thick + 90 * u + legendH;
    blockTop = safeY + Math.max(pad, (safeH - blockH) / 2);
    cx = ctx.width / 2;
    cy = blockTop + titleSize + 80 * u + thick / 2 + R;
    legendX = (ctx.width - legendW) / 2;
    legendY = cy + R + thick / 2 + 90 * u;
  }
  const titleX = landscape ? cx - R - thick / 2 : ctx.width / 2;
  const titleFits = landscape
    ? Math.min(titleSize, fitText(props.title, safeX + safeW - pad - titleX, { family: "Montserrat", weight: 900 },
      { min: 12 * u, max: 64 * u }))
    : titleSize;
  const fade = interpolate(frame, [0, 15], [0, 1], { clamp: true });
  const out = interpolate(frame, [D - 15, D - 1], [1, 0], { clamp: true });
  const sweep = interpolate(frame, [8, 70], [0, 360], { easing: Easing.inOutCubic, clamp: true });
  const gap = n > 1 ? 1.6 : 0;

  let slices = `<circle cx="${cx}" cy="${cy}" r="${R}" fill="none" stroke="#ffffff" stroke-opacity="0.08"
                        stroke-width="${thick}"/>`;
  let start = 0;
  values.forEach((v, i) => {
    const size = total > 0 ? (v / total) * 360 : 0;
    const shown = Math.min(sweep, start + size) - start;
    if (size > 0 && shown > gap) {
      const colour = i === 0 ? props.accent : PALETTE[(i - 1) % PALETTE.length];
      slices += `<path d="${arc(cx, cy, R, start + gap / 2, start + shown - gap / 2)}" fill="none"
                       stroke="${colour}" stroke-width="${thick}"/>`;
    }
    start += size;
  });

  const share = total > 0 ? (values[0] / total) * 100 : 0;
  const counted = share * interpolate(frame, [8, 70], [0, 1], { easing: Easing.inOutCubic, clamp: true });
  const percentSize = Math.min(120 * u, R * 0.62);
  const centreLabel = labels[0] || "";
  const centreSize = centreLabel ? fitText(centreLabel, (2 * R - thick) * 0.8, { family: "Montserrat", weight: 800 },
    { min: 8 * u, max: 28 * u }) : 28 * u;
  const centre = `
    <text x="${cx}" y="${cy + percentSize * 0.3}" text-anchor="middle" font-family="IBM Plex Mono"
          font-weight="500" font-size="${percentSize}" fill="#ffffff">${Math.round(counted)}%</text>
    <text x="${cx}" y="${cy + percentSize * 0.3 + 52 * u}" text-anchor="middle" font-family="Montserrat"
          font-weight="800" font-size="${centreSize}" fill="#c8c8d0" opacity="${fade}">${escapeXml(centreLabel)}</text>`;

  let legend = "";
  // One size for every row's label, the smallest any needs to clear the widest percentage.
  const rowSize = Math.min(36 * u, rowH * 0.5);
  const sq = rowSize * 0.8;
  const pcts = values.map((v) => (total > 0 ? `${Math.round((v / total) * 100)}%` : "0%"));
  const pctW = Math.max(0, ...pcts.map((p) => measureText(p, { family: "IBM Plex Mono", size: rowSize, weight: 500 }).width));
  const labelRoom = legendW - sq - 22 * u - pctW - 24 * u;
  const labelSize = Math.min(rowSize, ...labels.slice(0, n).filter((l) => l).map((l) =>
    fitText(l, labelRoom, { family: "Montserrat", weight: 800 }, { min: 8 * u, max: rowSize })));
  values.forEach((v, i) => {
    const t = spring({ frame: frame - 24 - i * 6, fps: ctx.fps, damping: 16 });
    if (t <= 0.001) return;
    const colour = i === 0 ? props.accent : PALETTE[(i - 1) % PALETTE.length];
    const y = legendY + rowH * i + rowH / 2;
    legend += `<g opacity="${Math.min(1, t)}" transform="translate(${(1 - Math.min(1, t)) * 30 * u} 0)">
      <rect x="${legendX}" y="${y - sq / 2}" width="${sq}" height="${sq}" rx="${sq * 0.2}" fill="${colour}"/>
      <text x="${legendX + sq + 22 * u}" y="${y + labelSize * 0.36}" font-family="Montserrat" font-weight="800"
            font-size="${labelSize}" fill="#ffffff">${escapeXml(labels[i] || "")}</text>
      <text x="${legendX + legendW}" y="${y + rowSize * 0.36}" text-anchor="end" font-family="IBM Plex Mono"
            font-weight="500" font-size="${rowSize}" fill="#c8c8d0">${pcts[i]}</text></g>`;
  });

  return svg(ctx, `
    <g opacity="${out}">
      <text x="${titleX}" y="${blockTop + titleSize * 0.8}" text-anchor="${landscape ? "start" : "middle"}"
            font-family="Montserrat" font-weight="900" font-size="${titleFits}" fill="#ffffff"
            opacity="${fade}">${escapeXml(props.title)}</text>
      ${slices}${centre}${legend}
    </g>`, { background: "#15151b" });
}
