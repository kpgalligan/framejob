// logo-reveal — a bundled template (spec §11 G-44): a full card on which an
// accent bar sweeps across the centre, wiping in a logo image (or, with none,
// a text mark) that settles to size; the bar becomes a rule and a tagline fades up.
export const meta = {
  name: "Logo reveal",
  durationInFrames: 120,
};

export const schema = {
  logo:       { type: "asset",  default: null, kind: "image" },
  mark:       { type: "string", default: "FRAME JOB" },
  tagline:    { type: "string", default: "Edit at the speed of thought" },
  background: { type: "color",  default: "#0b0b10" },
  accent:     { type: "color",  default: "#ff5a36" },
};

export function render(frame, props, ctx) {
  const u = Math.min(ctx.width, ctx.height) / 1080;
  const D = ctx.durationInFrames;
  const safeW = ctx.width * 0.9;
  const safeH = ctx.height * 0.9;
  const cx = ctx.width / 2;
  const cy = ctx.height / 2;
  let markW;
  let markH;
  let content;
  const markSize = fitText(props.mark, safeW * 0.8, { family: "Montserrat", weight: 900 }, { min: 16 * u, max: 200 * u });
  if (props.logo) {
    markW = safeW * 0.5;
    markH = Math.min(safeH * 0.32, markW);
    content = `<image href="${asset(props.logo)}" x="${cx - markW / 2}" y="${cy - markH / 2}" width="${markW}"
                      height="${markH}" preserveAspectRatio="xMidYMid meet"/>`;
  } else {
    markW = measureText(props.mark, { family: "Montserrat", size: markSize, weight: 900 }).width;
    markH = markSize * 0.74;
    content = `<text x="${cx}" y="${cy + markH / 2}" text-anchor="middle" font-family="Montserrat" font-weight="900"
                     font-size="${markSize}" fill="#ffffff">${escapeXml(props.mark)}</text>`;
  }
  const barH = markH + 80 * u;
  const barW = 16 * u;
  const from = cx - markW / 2 - 50 * u;
  const to = cx + markW / 2 + 50 * u;
  const sweep = interpolate(frame, [4, 34], [0, 1], { easing: Easing.inOutCubic, clamp: true });
  const barX = from + (to - from) * sweep;
  // After its sweep the bar settles into a short rule under the mark.
  const morph = interpolate(frame, [36, 54], [0, 1], { easing: Easing.inOutCubic, clamp: true });
  const ruleY = cy + markH / 2 + 34 * u;
  const bw = barW + (150 * u - barW) * morph;
  const bh = barH + (6 * u - barH) * morph;
  const bcx = barX + (cx - barX) * morph;
  const bcy = cy + (ruleY - cy) * morph;
  const settle = interpolate(frame, [4, 54], [1.06, 1], { easing: Easing.outCubic, clamp: true });
  const out = interpolate(frame, [D - 15, D - 1], [0, 1], { easing: Easing.inCubic, clamp: true });
  const scale = settle + 0.04 * out;
  const alpha = 1 - out;
  const tagIn = interpolate(frame, [46, 68], [0, 1], { easing: Easing.outCubic, clamp: true });
  const tagSize = props.tagline ? Math.min(44 * u, fitText(props.tagline, safeW * 0.8,
    { family: "Montserrat", weight: 800 }, { min: 10 * u, max: 44 * u })) : 0;
  const tagY = ruleY + 40 * u + tagSize * 0.9 + (1 - tagIn) * 20 * u;
  const revealW = Math.max(0, barX - (from - 10 * u));
  return svg(ctx, `
    <defs>
      <clipPath id="wipe"><rect x="${from - 10 * u}" y="${cy - barH / 2}" width="${revealW}" height="${barH}"/></clipPath>
    </defs>
    <g opacity="${alpha}" transform="translate(${cx} ${cy}) scale(${scale}) translate(${-cx} ${-cy})">
      ${sweep >= 1 ? content : revealW > 0.5 ? `<g clip-path="url(#wipe)">${content}</g>` : ""}
      ${props.tagline ? `<text x="${cx}" y="${tagY}" text-anchor="middle" font-family="Montserrat" font-weight="800"
            font-size="${tagSize}" fill="#d8d8e0" fill-opacity="${tagIn}">${escapeXml(props.tagline)}</text>` : ""}
      ${sweep > 0 ? `<rect x="${bcx - bw / 2}" y="${bcy - bh / 2}" width="${bw}" height="${bh}" fill="${props.accent}"/>` : ""}
    </g>`, { background: props.background });
}
