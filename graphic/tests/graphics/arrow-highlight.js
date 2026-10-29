// arrow-highlight — a bundled template (spec §11 G-44): a rounded box drawn
// on around a spot and an arrow growing toward it from the side nearer the
// frame's centre, with a label at the arrow's tail.
export const meta = {
  name: "Arrow highlight",
  category: "Screencast",
  description: "A box drawn round a spot, an arrow and a label pointing at it.",
  durationInFrames: 90,
};

export const schema = {
  x:         { type: "number", default: 0.62, min: 0, max: 1, step: 0.01 },
  y:         { type: "number", default: 0.42, min: 0, max: 1, step: 0.01 },
  boxWidth:  { type: "number", default: 0.22, min: 0.02, max: 0.8, step: 0.01 },
  boxHeight: { type: "number", default: 0.14, min: 0.02, max: 0.8, step: 0.01 },
  shape:     { type: "enum",   default: "box+arrow", options: ["box+arrow", "box", "arrow"] },
  label:     { type: "string", default: "Look here" },
  accent:    { type: "color",  default: "#ffd60a" },
};

const clamp = (v, lo, hi) => Math.max(lo, Math.min(Math.max(lo, hi), v));

export function render(frame, props, ctx) {
  const u = Math.min(ctx.width, ctx.height) / 1080;
  const D = ctx.durationInFrames;
  const W = ctx.width;
  const H = ctx.height;
  const inset = 30 * u;
  const x0 = W * 0.05 + inset;
  const y0 = H * 0.05 + inset;
  const x1 = W * 0.95 - inset;
  const y1 = H * 0.95 - inset;
  const showBox = props.shape !== "arrow";
  const showArrow = props.shape !== "box";
  const bw = showBox ? Math.min(x1 - x0, Math.max(0.02, props.boxWidth) * W) : 0;
  const bh = showBox ? Math.min(y1 - y0, Math.max(0.02, props.boxHeight) * H) : 0;
  const cx = clamp(props.x * W, x0 + bw / 2, x1 - bw / 2);
  const cy = clamp(props.y * H, y0 + bh / 2, y1 - bh / 2);
  const stroke = 8 * u;
  const out = interpolate(frame, [D - 15, D - 1], [1, 0], { clamp: true });
  const font = { family: "Montserrat", size: 56 * u, weight: 800 };
  const labelSize = props.label ? fitText(props.label, x1 - x0, font, { min: 10 * u, max: font.size }) : 0;
  const labelW = props.label ? measureText(props.label, { family: "Montserrat", size: labelSize, weight: 800 }).width : 0;

  let box = "";
  if (showBox) {
    const r = Math.min(14 * u, bw / 2, bh / 2);
    const bx = cx - bw / 2;
    const by = cy - bh / 2;
    const d = `M ${bx + r} ${by} H ${bx + bw - r} A ${r} ${r} 0 0 1 ${bx + bw} ${by + r} V ${by + bh - r}
      A ${r} ${r} 0 0 1 ${bx + bw - r} ${by + bh} H ${bx + r} A ${r} ${r} 0 0 1 ${bx} ${by + bh - r} V ${by + r}
      A ${r} ${r} 0 0 1 ${bx + r} ${by} Z`;
    const drawn = interpolate(frame, [0, 24], [0, 1], { easing: Easing.inOutCubic, clamp: true });
    const dash = evolvePath(drawn, d);
    box = drawn > 0 ? `<path d="${d}" fill="none" stroke="${props.accent}" stroke-width="${stroke}"
      stroke-linecap="round" stroke-linejoin="round" stroke-dasharray="${dash.strokeDasharray}"
      stroke-dashoffset="${dash.strokeDashoffset}" stroke-opacity="${out}"/>` : "";
  }

  // The tail lies toward the frame's centre (down and left when the spot is the centre).
  let dx = W / 2 - cx;
  let dy = H / 2 - cy;
  const len = Math.hypot(dx, dy);
  if (len < 1) {
    dx = -1;
    dy = 1;
  }
  const norm = Math.hypot(dx, dy);
  dx /= norm;
  dy /= norm;
  // Where the ray from the centre leaves the box (or the spot itself), plus a gap.
  const exit = showBox ? Math.min(bw / 2 / Math.max(1e-6, Math.abs(dx)), bh / 2 / Math.max(1e-6, Math.abs(dy))) : 0;
  const gapped = exit + 22 * u;
  const headX = cx + dx * gapped;
  const headY = cy + dy * gapped;
  const reach = 240 * u;
  const below = dy >= 0;
  const labelRoom = props.label ? labelSize * 1.3 : 0;
  const tailX = clamp(headX + dx * reach, x0 + 10 * u, x1 - 10 * u);
  const tailY = clamp(headY + dy * reach, y0 + (below ? 0 : labelRoom), y1 - (below ? labelRoom : 0));
  const grow = interpolate(frame, [18, 36], [0, 1], { easing: Easing.outBack, clamp: true });
  let arrow = "";
  if (showArrow && grow > 0) {
    const hx = tailX + (headX - tailX) * grow;
    const hy = tailY + (headY - tailY) * grow;
    const angle = Math.atan2(headY - tailY, headX - tailX);
    const head = 34 * u;
    const p1 = `${hx - head * Math.cos(angle - 0.5)},${hy - head * Math.sin(angle - 0.5)}`;
    const p2 = `${hx - head * Math.cos(angle + 0.5)},${hy - head * Math.sin(angle + 0.5)}`;
    const back = 0.8 * head;
    arrow = `<line x1="${tailX}" y1="${tailY}" x2="${hx - back * Math.cos(angle) * 0.5}" y2="${hy - back * Math.sin(angle) * 0.5}"
                   stroke="${props.accent}" stroke-opacity="${out}" stroke-width="${stroke}" stroke-linecap="round"/>
      <polygon points="${hx},${hy} ${p1} ${p2}" fill="${props.accent}" fill-opacity="${out}" stroke="${props.accent}"
               stroke-opacity="${out}" stroke-width="${3 * u}" stroke-linejoin="round"/>`;
  }
  let label = "";
  if (props.label) {
    const t = spring({ frame: frame - (showArrow ? 30 : 20), fps: ctx.fps, damping: 15 });
    let lx;
    let ly;
    if (showArrow) {
      lx = tailX;
      ly = below ? tailY + labelSize * 1.15 : tailY - labelSize * 0.45;
    } else {
      lx = cx;
      ly = cy + bh / 2 + 20 * u + labelSize;
      if (ly > y1) ly = cy - bh / 2 - 26 * u;
    }
    lx = clamp(lx, x0 + labelW / 2, x1 - labelW / 2);
    label = `<text x="${lx}" y="${ly}" text-anchor="middle" font-family="Montserrat" font-weight="800"
          font-size="${labelSize}" fill="#ffffff" stroke="#0b0b10" stroke-width="${9 * u}" stroke-linejoin="round" paint-order="stroke"
          fill-opacity="${Math.max(0, Math.min(1, t)) * out}" stroke-opacity="${Math.max(0, Math.min(1, t)) * out * 0.85}"
          >${escapeXml(props.label)}</text>`;
  }
  return svg(ctx, `${box}${arrow}${label}`);
}
