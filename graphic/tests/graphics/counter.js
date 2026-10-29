// counter — road map 10 §5k 3: a number counting from `from` to `to` with a
// thousands separator, in IBM Plex Mono.
export const meta = {
  name: "Counter",
  category: "Data & Time",
  description: "A number counting up, with a prefix and a label.",
  durationInFrames: 90,
};

export const schema = {
  from:   { type: "number", default: 0 },
  to:     { type: "number", default: 1284093 },
  prefix: { type: "string", default: "$" },
  label:  { type: "string", default: "raised this year" },
  color:  { type: "color",  default: "#f5f5f0" },
};

export function render(frame, props, ctx) {
  const u = ctx.height / 1080;
  const end = Math.max(1, Math.round(ctx.durationInFrames * 0.7));
  const value = interpolate(frame, [0, end], [props.from, props.to], { easing: Easing.outExpo, clamp: true });
  const text = props.prefix + formatNumber(value);
  const size = 150 * u;
  const pop = spring({ frame, fps: ctx.fps, stiffness: 180, damping: 18 });
  return svg(ctx, `
    <g transform="translate(${ctx.width / 2} ${ctx.height / 2}) scale(${0.8 + 0.2 * pop})">
      <text x="0" y="${size * 0.3}" text-anchor="middle" font-family="IBM Plex Mono" font-weight="500"
            font-size="${size}" fill="${props.color}">${escapeXml(text)}</text>
      <text x="0" y="${size * 0.3 + 80 * u}" text-anchor="middle" font-family="IBM Plex Mono"
            font-weight="400" font-size="${40 * u}" fill="${props.color}" opacity="0.7">${escapeXml(props.label)}</text>
    </g>`);
}
