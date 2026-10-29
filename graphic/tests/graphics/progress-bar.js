// progress-bar — a bundled template (spec §11 G-44): a labelled track on a
// plate, wiped in from the left, its fill growing to `value` with the
// percentage counting and one shine sweeping across.
export const meta = {
  name: "Progress bar",
  category: "Data & Time",
  description: "A labelled bar filling to a value, the percentage counting.",
  durationInFrames: 120,
};

export const schema = {
  value:       { type: "number",  default: 68, min: 0, max: 100, step: 1 },
  label:       { type: "string",  default: "Rendering" },
  showPercent: { type: "boolean", default: true },
  position:    { type: "enum",    default: "bottom", options: ["bottom", "center", "top"] },
  accent:      { type: "color",   default: "#2d7ff9" },
};

export function render(frame, props, ctx) {
  const u = Math.min(ctx.width, ctx.height) / 1080;
  const D = ctx.durationInFrames;
  const safeX = ctx.width * 0.05;
  const safeY = ctx.height * 0.05;
  const safeW = ctx.width * 0.9;
  const safeH = ctx.height * 0.9;
  const value = Math.max(0, Math.min(100, props.value));
  const trackW = safeW * 0.8;
  const trackH = 22 * u;
  const padX = 40 * u;
  const font = { family: "Montserrat", size: 40 * u, weight: 800 };
  const plateW = trackW + 2 * padX;
  const plateH = 150 * u;
  const plateX = (ctx.width - plateW) / 2;
  const margin = 40 * u;
  const plateY = props.position === "top" ? safeY + margin
    : props.position === "center" ? (ctx.height - plateH) / 2
    : safeY + safeH - margin - plateH;
  const trackX = plateX + padX;
  const trackY = plateY + plateH - 40 * u - trackH;
  const textY = plateY + 40 * u + font.size * 0.72;
  const fillEnd = Math.max(16, Math.round(D * 0.6));
  const grown = interpolate(frame, [8, fillEnd], [0, 1], { easing: Easing.outCubic, clamp: true });
  const fillW = (trackW * value * grown) / 100;
  const plateIn = interpolate(frame, [0, 10], [0, 1], { clamp: true });
  const wipe = interpolate(frame, [2, 20], [0, 1], { easing: Easing.outCubic, clamp: true });
  const out = interpolate(frame, [D - 15, D - 1], [1, 0], { clamp: true });
  const shine = interpolate(frame, [fillEnd - 6, fillEnd + 24], [-0.3, 1.3], { easing: Easing.inOutSine, clamp: true });
  const shineX = trackX + fillW * shine;
  const percent = `${Math.round(value * grown)}%`;
  const labelMax = trackW - (props.showPercent ? 200 * u : 0);
  const labelSize = Math.min(font.size, fitText(props.label, labelMax, font, { min: 10 * u, max: font.size }));
  return svg(ctx, `
    <defs>
      <clipPath id="wipe"><rect x="${plateX}" y="${plateY}" width="${plateW * wipe}" height="${plateH}"/></clipPath>
      <clipPath id="fill"><rect x="${trackX}" y="${trackY}" width="${fillW}" height="${trackH}" rx="${trackH / 2}"/></clipPath>
      <linearGradient id="shine" x1="0" y1="0" x2="1" y2="0">
        <stop offset="0" stop-color="#ffffff" stop-opacity="0"/>
        <stop offset="0.5" stop-color="#ffffff" stop-opacity="0.55"/>
        <stop offset="1" stop-color="#ffffff" stop-opacity="0"/>
      </linearGradient>
    </defs>
    <g opacity="${out * plateIn}">
      <rect x="${plateX}" y="${plateY}" width="${plateW}" height="${plateH}" rx="${18 * u}" fill="#101014"
            fill-opacity="0.82"/>
      <g clip-path="url(#wipe)">
        <text x="${trackX}" y="${textY}" font-family="Montserrat" font-weight="800" font-size="${labelSize}"
              fill="#ffffff">${escapeXml(props.label)}</text>
        ${props.showPercent ? `<text x="${trackX + trackW}" y="${textY}" text-anchor="end" font-family="IBM Plex Mono"
              font-weight="500" font-size="${font.size}" fill="#d8d8e0">${percent}</text>` : ""}
        <rect x="${trackX}" y="${trackY}" width="${trackW}" height="${trackH}" rx="${trackH / 2}" fill="#ffffff"
              fill-opacity="0.12"/>
        ${fillW > 0.5 ? `<rect x="${trackX}" y="${trackY}" width="${fillW}" height="${trackH}" rx="${trackH / 2}"
              fill="${props.accent}"/>
        <g clip-path="url(#fill)"><rect x="${shineX - 90 * u}" y="${trackY}" width="${180 * u}" height="${trackH}"
              fill="url(#shine)"/></g>` : ""}
      </g>
    </g>`);
}
