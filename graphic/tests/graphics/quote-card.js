// quote-card — a bundled template (spec §11 G-44): a full card with an
// accent opening quote mark drawn as a vector shape, the quote's lines
// fading up in turn, and a rule and attribution sliding in.
export const meta = {
  name: "Quote card",
  durationInFrames: 150,
};

export const schema = {
  quote:       { type: "string", default: "Good editing is invisible. All anyone should notice is the story.", multiline: true },
  attribution: { type: "string", default: "The Editor" },
  background:  { type: "color",  default: "#101014" },
  accent:      { type: "color",  default: "#ffd60a" },
};

// One “6”-shaped quote half: a ball with a tail rising to the upper right, `s` tall.
function mark(x, y, s) {
  const r = s * 0.3;
  const cx = x + r;
  const cy = y + s - r;
  return `<circle cx="${cx}" cy="${cy}" r="${r}"/>
    <path d="M ${cx - r} ${cy} C ${cx - r} ${cy - r * 2.2} ${cx + r * 0.2} ${y + s * 0.08} ${cx + r * 1.25} ${y}
             L ${cx + r * 1.25} ${y + s * 0.18} C ${cx + r * 0.25} ${y + s * 0.3} ${cx - r * 0.15} ${cy - r * 1.3} ${cx + r * 0.2} ${cy - r * 0.95} Z"/>`;
}

export function render(frame, props, ctx) {
  const u = Math.min(ctx.width, ctx.height) / 1080;
  const D = ctx.durationInFrames;
  const safeY = ctx.height * 0.05;
  const safeW = ctx.width * 0.9;
  const safeH = ctx.height * 0.9;
  const textW = safeW * 0.8;
  const left = (ctx.width - textW) / 2;
  const markH = 110 * u;
  const attrSize = 40 * u;
  const reserved = markH + 50 * u + 100 * u + attrSize + 2 * 60 * u;
  let size = 84 * u;
  let lines = [];
  for (; size > 28 * u; size -= 4 * u) {
    lines = wrapText(props.quote, textW, { family: "Montserrat", size, weight: 800 });
    if (lines.length * size * 1.25 <= safeH - reserved) break;
  }
  if (size <= 28 * u) {
    size = 28 * u;
    lines = wrapText(props.quote, textW, { family: "Montserrat", size, weight: 800 });
  }
  const lineH = size * 1.25;
  const blockH = markH + 50 * u + lines.length * lineH + 100 * u + attrSize;
  const top = safeY + Math.max(60 * u, (safeH - blockH) / 2);
  const out = interpolate(frame, [D - 15, D - 1], [1, 0], { clamp: true });
  const markIn = spring({ frame, fps: ctx.fps, stiffness: 160, damping: 12 });
  const mx = left;
  const my = top;
  const mcx = mx + markH * 0.6;
  const mcy = my + markH / 2;
  let body = "";
  lines.forEach((line, i) => {
    const t = interpolate(frame, [10 + i * 6, 28 + i * 6], [0, 1], { easing: Easing.outCubic, clamp: true });
    const y = top + markH + 50 * u + size * 0.9 + i * lineH + (1 - t) * 24 * u;
    body += `<text x="${left}" y="${y}" font-family="Montserrat" font-weight="800" font-size="${size}" fill="#ffffff"
                   fill-opacity="${t * out}">${escapeXml(line)}</text>`;
  });
  const endLines = 28 + lines.length * 6;
  const attrIn = interpolate(frame, [endLines - 6, endLines + 14], [0, 1], { easing: Easing.outCubic, clamp: true });
  const attrY = top + markH + 50 * u + lines.length * lineH + 60 * u + 40 * u;
  const slide = (1 - attrIn) * -40 * u;
  const attrText = props.attribution.trim() ? `— ${props.attribution}` : "";
  const attrFit = attrText ? Math.min(attrSize, fitText(attrText, textW,
    { family: "Montserrat", weight: 800 }, { min: 10 * u, max: attrSize })) : attrSize;
  return svg(ctx, `
    ${markIn > 0.001 ? `<g fill="${props.accent}" fill-opacity="${out}"
       transform="translate(${mcx} ${mcy}) scale(${markIn}) translate(${-mcx} ${-mcy})">
      ${mark(mx, my, markH)}${mark(mx + markH * 0.72, my, markH)}
    </g>` : ""}
    ${body}
    ${attrIn > 0 ? `<rect x="${left + slide}" y="${attrY - attrSize - 34 * u}" width="${80 * u}" height="${6 * u}"
          fill="${props.accent}" fill-opacity="${attrIn * out}"/>
    <text x="${left + slide}" y="${attrY}" font-family="Montserrat" font-weight="800"
          font-size="${attrFit}" fill="#d8d8e0" fill-opacity="${attrIn * out}">${escapeXml(attrText)}</text>` : ""}`,
    { background: props.background });
}
