// lower-third — road map 10 §5k 1: a slide-in bar and title on a spring, a
// staggered subtitle, and an outro keyed to durationInFrames.
export const meta = {
  name: "Lower third",
  category: "Titles & Text",
  description: "A name and a subtitle sliding in on a bar.",
  durationInFrames: 150,
};

export const schema = {
  title:    { type: "string",  default: "Jane Doe", label: "Title" },
  subtitle: { type: "string",  default: "Director of Photography" },
  accent:   { type: "color",   default: "#ff5a36" },
  size:     { type: "number",  default: 64, min: 12, max: 200, step: 1 },
  boxed:    { type: "boolean", default: true },
  align:    { type: "enum",    default: "left", options: ["left", "center", "right"] },
};

export function render(frame, props, ctx) {
  const u = ctx.height / 1080;
  const size = props.size * u;
  const sub = size * 0.5;
  const titleFont = { family: "Montserrat", size, weight: 800 };
  const subFont = { family: "Montserrat", size: sub, weight: 800 };
  const titleWidth = measureText(props.title, titleFont).width;
  const subWidth = measureText(props.subtitle, subFont).width;
  const boxWidth = Math.max(titleWidth, subWidth) + 80 * u;
  const boxHeight = size + sub + 70 * u;
  const margin = 96 * u;
  const left = props.align === "left" ? margin
    : props.align === "right" ? ctx.width - margin - boxWidth
    : (ctx.width - boxWidth) / 2;
  const top = ctx.height - margin - boxHeight;
  const slide = interpolate(frame, [0, 20], [-boxWidth - margin, 0], { easing: Easing.outCubic, clamp: true });
  const grow = spring({ frame: frame - 4, fps: ctx.fps, damping: 14 });
  const subIn = spring({ frame: frame - 12, fps: ctx.fps, damping: 16 });
  const out = interpolate(frame, [ctx.durationInFrames - 15, ctx.durationInFrames - 1], [1, 0], { clamp: true });
  const x = left + slide;
  const box = props.boxed
    ? `<rect x="${x}" y="${top}" width="${boxWidth * grow}" height="${boxHeight}" fill="#101014" fill-opacity="0.82"/>`
    : "";
  return svg(ctx, `
    <g opacity="${out}">
      ${box}
      <rect x="${x}" y="${top}" width="${12 * u}" height="${boxHeight}" fill="${props.accent}"/>
      <text x="${x + 40 * u}" y="${top + 26 * u + size * 0.9}" font-family="Montserrat" font-weight="800"
            font-size="${size}" fill="#ffffff">${escapeXml(props.title)}</text>
      <text x="${x + 40 * u + (1 - subIn) * 40 * u}" y="${top + 40 * u + size + sub * 0.9}"
            font-family="Montserrat" font-weight="800" font-size="${sub}" fill="#d8d8e0"
            opacity="${Math.max(0, Math.min(1, subIn))}">${escapeXml(props.subtitle)}</text>
    </g>`);
}
