// callout — road map 10 §5k 6: a circle drawing itself on (a
// stroke-dasharray draw-on) and an arrow, over a transparent background.
export const meta = {
  name: "Callout",
  category: "Screencast",
  description: "A circle drawing itself round a spot, with an arrow and a label.",
  durationInFrames: 90,
};

export const schema = {
  x:     { type: "number", default: 0.62, min: 0, max: 1, step: 0.01 },
  y:     { type: "number", default: 0.4,  min: 0, max: 1, step: 0.01 },
  label: { type: "string", default: "Click here first" },
  color: { type: "color",  default: "#ff3b30" },
};

export function render(frame, props, ctx) {
  const u = ctx.height / 1080;
  const cx = props.x * ctx.width;
  const cy = props.y * ctx.height;
  const r = 110 * u;
  const circumference = 2 * Math.PI * r;
  const draw = interpolate(frame, [0, 24], [0, 1], { easing: Easing.inOutCubic, clamp: true });
  const arrow = interpolate(frame, [18, 36], [0, 1], { easing: Easing.outBack, clamp: true });
  const labelIn = spring({ frame: frame - 30, fps: ctx.fps, damping: 15 });
  const ax = cx - r * 0.75;
  const ay = cy + r * 0.75;
  const tailX = ax - 260 * u;
  const tailY = ay + 200 * u;
  const hx = tailX + (ax - tailX) * arrow;
  const hy = tailY + (ay - tailY) * arrow;
  const angle = Math.atan2(ay - tailY, ax - tailX);
  const head = 34 * u;
  const p1 = `${hx - head * Math.cos(angle - 0.45)},${hy - head * Math.sin(angle - 0.45)}`;
  const p2 = `${hx - head * Math.cos(angle + 0.45)},${hy - head * Math.sin(angle + 0.45)}`;
  const stroke = 10 * u;
  return svg(ctx, `
    <circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="${props.color}" stroke-width="${stroke}"
            stroke-linecap="round" stroke-dasharray="${circumference}"
            stroke-dashoffset="${circumference * (1 - draw)}" transform="rotate(-90 ${cx} ${cy})"/>
    <g opacity="${arrow > 0 ? 1 : 0}">
      <line x1="${tailX}" y1="${tailY}" x2="${hx}" y2="${hy}" stroke="${props.color}" stroke-width="${stroke}"
            stroke-linecap="round"/>
      <polygon points="${hx},${hy} ${p1} ${p2}" fill="${props.color}"/>
    </g>
    <text x="${tailX}" y="${tailY + 70 * u}" text-anchor="middle" font-family="Darker Grotesque" font-weight="800"
          font-size="${64 * u}" fill="#ffffff" stroke="#000000" stroke-width="${2 * u}"
          opacity="${Math.max(0, Math.min(1, labelIn))}">${escapeXml(props.label)}</text>`);
}
