// gauge — a bundled template (spec §11 G-44): a 270° dial with ticks, an
// accent arc and a needle that swing from `min` to `value` on a spring, and
// the value counting in the dial's open foot.
export const meta = {
  name: "Gauge",
  durationInFrames: 120,
};

export const schema = {
  value:  { type: "number", default: 72 },
  min:    { type: "number", default: 0 },
  max:    { type: "number", default: 100 },
  label:  { type: "string", default: "Speed" },
  units:  { type: "string", default: "km/h" },
  accent: { type: "color",  default: "#ff5a36" },
};

// The point at `r` from (cx, cy) at `deg` clockwise from twelve o'clock.
function polar(cx, cy, r, deg) {
  const t = ((deg - 90) * Math.PI) / 180;
  return { x: cx + r * Math.cos(t), y: cy + r * Math.sin(t) };
}

function arc(cx, cy, r, a0, a1) {
  const p = polar(cx, cy, r, a0);
  const q = polar(cx, cy, r, a1);
  return `M ${p.x} ${p.y} A ${r} ${r} 0 ${a1 - a0 > 180 ? 1 : 0} 1 ${q.x} ${q.y}`;
}

export function render(frame, props, ctx) {
  const u = Math.min(ctx.width, ctx.height) / 1080;
  const D = ctx.durationInFrames;
  const min = props.min;
  const max = props.max > min ? props.max : min + 1;
  const value = Math.min(max, Math.max(min, props.value));
  const cx = ctx.width / 2;
  const cy = ctx.height / 2;
  const R = 300 * u;
  const disc = R * 1.22;
  const thick = 30 * u;
  const enter = spring({ frame, fps: ctx.fps, stiffness: 140, damping: 16 });
  const out = interpolate(frame, [D - 15, D - 1], [0, 1], { easing: Easing.inCubic, clamp: true });
  const scale = (0.9 + 0.1 * Math.min(1, enter)) * (1 - 0.1 * out);
  const opacity = Math.min(1, enter * 1.4) * (1 - out);
  const swing = spring({ frame: frame - 10, fps: ctx.fps, stiffness: 55, damping: 8 });
  const fraction = (value - min) / (max - min);
  const shown = Math.max(0, Math.min(1.04, fraction * swing));
  const angle = -135 + 270 * shown;

  let ticks = "";
  for (let i = 0; i <= 40; i++) {
    const a = -135 + (270 * i) / 40;
    const major = i % 4 === 0;
    const p = polar(cx, cy, R - thick / 2 - 18 * u, a);
    const q = polar(cx, cy, R - thick / 2 - (major ? 48 : 30) * u, a);
    ticks += `<line x1="${p.x}" y1="${p.y}" x2="${q.x}" y2="${q.y}" stroke="#ffffff"
                    stroke-opacity="${major ? 0.75 : 0.3}" stroke-width="${(major ? 5 : 3) * u}" stroke-linecap="round"/>`;
  }
  const decimals = Number.isInteger(props.value) ? 0 : 1;
  const counted = min + (value - min) * Math.max(0, Math.min(1, swing));
  const text = formatNumber(counted, { decimals });
  const valueSize = fitText(text, R * 0.95, { family: "IBM Plex Mono", weight: 500 }, { min: 12 * u, max: 128 * u });
  const tip = polar(cx, cy, R - thick / 2 - 6 * u, angle);
  const left = polar(cx, cy, 16 * u, angle - 90);
  const right = polar(cx, cy, 16 * u, angle + 90);
  const tail = polar(cx, cy, 40 * u, angle + 180);
  const labelSize = fitText(props.label.toUpperCase(), R, { family: "Montserrat", weight: 800, letterSpacing: 4 * u },
    { min: 10 * u, max: 34 * u });
  return svg(ctx, `
    <g opacity="${opacity}" transform="translate(${cx} ${cy}) scale(${scale}) translate(${-cx} ${-cy})">
      <circle cx="${cx}" cy="${cy}" r="${disc}" fill="#101014" fill-opacity="0.82"/>
      <path d="${arc(cx, cy, R, -135, 135)}" fill="none" stroke="#ffffff" stroke-opacity="0.12"
            stroke-width="${thick}" stroke-linecap="round"/>
      ${shown > 0.001 ? `<path d="${arc(cx, cy, R, -135, -135 + 270 * Math.min(1, shown))}" fill="none"
            stroke="${props.accent}" stroke-width="${thick}" stroke-linecap="round"/>` : ""}
      ${ticks}
      <text x="${cx}" y="${cy - R * 0.38}" text-anchor="middle" font-family="Montserrat" font-weight="800"
            font-size="${labelSize}" letter-spacing="${4 * u}" fill="#d8d8e0">${escapeXml(props.label.toUpperCase())}</text>
      <polygon points="${tip.x},${tip.y} ${left.x},${left.y} ${tail.x},${tail.y} ${right.x},${right.y}"
               fill="${props.accent}"/>
      <circle cx="${cx}" cy="${cy}" r="${24 * u}" fill="#ffffff"/>
      <circle cx="${cx}" cy="${cy}" r="${9 * u}" fill="#101014"/>
      <text x="${cx}" y="${cy + R * 0.66}" text-anchor="middle" font-family="IBM Plex Mono" font-weight="500"
            font-size="${valueSize}" fill="#ffffff">${escapeXml(text)}</text>
      <text x="${cx}" y="${cy + R * 0.66 + 54 * u}" text-anchor="middle" font-family="Montserrat" font-weight="800"
            font-size="${34 * u}" fill="#d8d8e0">${escapeXml(props.units)}</text>
    </g>`);
}
