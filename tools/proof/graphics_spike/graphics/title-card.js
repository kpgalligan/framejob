// title-card — road map 10 §5k 2: fitText on a long title over a gradient,
// with a fade in and out.
export const meta = {
  name: "Title card",
  durationInFrames: 120,
};

export const schema = {
  title:  { type: "string", default: "The Long Road to a Motion Graphic" },
  kicker: { type: "string", default: "CHAPTER ONE" },
  from:   { type: "color",  default: "#1b2a6b" },
  to:     { type: "color",  default: "#c2185b" },
};

export function render(frame, props, ctx) {
  const u = ctx.height / 1080;
  const width = ctx.width * 0.8;
  const size = fitText(props.title, width, { family: "Anton", weight: 400 }, { min: 24 * u, max: 220 * u });
  const fadeIn = interpolate(frame, [0, 18], [0, 1], { easing: Easing.inOutSine, clamp: true });
  const fadeOut = interpolate(frame, [ctx.durationInFrames - 18, ctx.durationInFrames - 1], [1, 0], { clamp: true });
  const rise = interpolate(frame, [0, 30], [40 * u, 0], { easing: Easing.outQuart, clamp: true });
  const cy = ctx.height / 2;
  return svg(ctx, `
    <defs>
      <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stop-color="${props.from}"/>
        <stop offset="1" stop-color="${props.to}"/>
      </linearGradient>
    </defs>
    <rect x="0" y="0" width="${ctx.width}" height="${ctx.height}" fill="url(#bg)"/>
    <g opacity="${fadeIn * fadeOut}" transform="translate(0 ${rise})">
      <text x="${ctx.width / 2}" y="${cy - size * 0.35 - 30 * u}" text-anchor="middle" font-family="Bebas Neue"
            font-size="${48 * u}" letter-spacing="${6 * u}" fill="#ffffffcc">${escapeXml(props.kicker)}</text>
      <text x="${ctx.width / 2}" y="${cy + size * 0.45}" text-anchor="middle" font-family="Anton"
            font-size="${size}" fill="#ffffff">${escapeXml(props.title)}</text>
    </g>`);
}
