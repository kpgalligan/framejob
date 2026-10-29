// chapter-card — a bundled template (spec §11 G-44): a full card with a
// large outlined chapter numeral, a kicker whose spacing settles, an accent
// rule drawing across and the title revealed upward.
export const meta = {
  name: "Chapter card",
  category: "Titles & Text",
  description: "A full card with a large chapter number and a title.",
  durationInFrames: 120,
};

export const schema = {
  number:     { type: "number", default: 1, min: 0, max: 99, step: 1, animate: false },
  kicker:     { type: "string", default: "CHAPTER" },
  title:      { type: "string", default: "Getting started" },
  background: { type: "color",  default: "#0b0b10" },
  accent:     { type: "color",  default: "#ff5a36" },
};

export function render(frame, props, ctx) {
  const u = Math.min(ctx.width, ctx.height) / 1080;
  const D = ctx.durationInFrames;
  const safeX = ctx.width * 0.05;
  const safeW = ctx.width * 0.9;
  const pad = 70 * u;
  const left = safeX + pad;
  const width = safeW - 2 * pad;
  const numeral = String(Math.max(0, Math.min(99, Math.round(props.number)))).padStart(2, "0");
  const numSize = 300 * u;
  const numFont = { family: "Montserrat", size: numSize, weight: 900 };
  const numW = measureText(numeral, numFont).width;
  const titleSize = fitText(props.title, width, { family: "Montserrat", weight: 900 }, { min: 16 * u, max: 150 * u });
  const kickerSize = 44 * u;
  const blockH = numSize * 0.74 + 60 * u + titleSize * 0.74 + 40 * u;
  const top = (ctx.height - blockH) / 2;
  const numBase = top + numSize * 0.74;
  const ruleY = numBase + 46 * u;
  const titleBase = ruleY + 34 * u + titleSize * 0.74;
  const out = interpolate(frame, [D - 15, D - 1], [1, 0], { clamp: true });
  const lift = interpolate(frame, [D - 15, D - 1], [0, -24 * u], { easing: Easing.inCubic, clamp: true });
  const numIn = interpolate(frame, [0, 22], [0, 1], { easing: Easing.outCubic, clamp: true });
  const numScale = 1.15 - 0.15 * numIn;
  const kickIn = interpolate(frame, [8, 30], [0, 1], { easing: Easing.outCubic, clamp: true });
  const rule = interpolate(frame, [14, 38], [0, 1], { easing: Easing.inOutCubic, clamp: true });
  const reveal = interpolate(frame, [22, 46], [0, 1], { easing: Easing.outCubic, clamp: true });
  const kickerX = left + numW + 40 * u;
  const kickerMax = left + width - kickerX;
  // The kicker wraps beside the numeral, at most three lines at its widest spacing, shrinking (its
  // spacing in proportion) until it does and until every word fits its room, so a line only ever
  // breaks between words.
  const kickerWords = props.kicker.split(/\s+/).filter((word) => word);
  let kickerFit = kickerSize;
  let kickerLines = [];
  for (;;) {
    const font = { family: "Montserrat", size: kickerFit, weight: 800, letterSpacing: (22 * u * kickerFit) / kickerSize };
    kickerLines = kickerWords.length ? wrapText(props.kicker, kickerMax, font) : [];
    const wordsFit = kickerWords.every((word) => measureText(word, font).width <= kickerMax);
    if ((kickerLines.length <= 3 && wordsFit) || kickerFit <= 10 * u) break;
    kickerFit = Math.max(10 * u, kickerFit * 0.9);
  }
  const spacing = ((22 - 14 * kickIn) * u * kickerFit) / kickerSize;
  const kickerLead = kickerFit * 1.2;
  const kickerTop = numBase - numSize * 0.37 + kickerFit * 0.36 - ((kickerLines.length - 1) * kickerLead) / 2;
  const ncx = left + numW / 2;
  const ncy = numBase - numSize * 0.37;
  const ruleW = width * rule;
  const rise = (1 - reveal) * titleSize * 1.15;
  return svg(ctx, `
    <defs>
      <clipPath id="title"><rect x="${safeX}" y="${ruleY + 10 * u}" width="${safeW}" height="${titleBase - ruleY - 10 * u + titleSize * 0.26}"/></clipPath>
    </defs>
    <g transform="translate(0 ${lift})">
      <g transform="translate(${ncx} ${ncy}) scale(${numScale}) translate(${-ncx} ${-ncy})">
        <text x="${left}" y="${numBase}" font-family="Montserrat" font-weight="900" font-size="${numSize}" fill="none"
              stroke="${props.accent}" stroke-width="${4 * u}" stroke-opacity="${numIn * out}">${numeral}</text>
      </g>
      <text x="${kickerX}" y="${kickerTop}" font-family="Montserrat" font-weight="800"
            font-size="${kickerFit}" letter-spacing="${spacing}" fill="#d8d8e0"
            fill-opacity="${kickIn * out}">${kickerLines.map((line, i) =>
              `<tspan x="${kickerX}" y="${kickerTop + i * kickerLead}">${escapeXml(line)}</tspan>`).join("")}</text>
      ${ruleW > 0.5 ? `<rect x="${left}" y="${ruleY}" width="${ruleW}" height="${6 * u}" fill="${props.accent}"
            fill-opacity="${out}"/>` : ""}
      <g clip-path="url(#title)">
        <text x="${left}" y="${titleBase + rise}" font-family="Montserrat" font-weight="900" font-size="${titleSize}"
              fill="#ffffff" fill-opacity="${out}">${escapeXml(props.title)}</text>
      </g>
    </g>`, { background: props.background });
}
