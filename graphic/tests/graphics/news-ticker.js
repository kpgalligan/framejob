// news-ticker — a bundled template (spec §11 G-44): a band along the foot of
// title-safe with an accent headline box and items crawling right to left,
// separated by accent bullets.
export const meta = {
  name: "News ticker",
  durationInFrames: 300,
};

export const schema = {
  headline:   { type: "string", default: "BREAKING" },
  items:      { type: "string", default: "Frame Job adds 17 graphic templates | Charts, timers and social pop-ups | Every one drawn by code", animate: false },
  speed:      { type: "number", default: 160, min: 40, max: 600, step: 10 },
  background: { type: "color",  default: "#101014" },
  accent:     { type: "color",  default: "#e5322d" },
};

export function render(frame, props, ctx) {
  const u = Math.min(ctx.width, ctx.height) / 1080;
  const D = ctx.durationInFrames;
  const x0 = ctx.width * 0.05;
  const bandW = ctx.width * 0.9;
  const bandH = 84 * u;
  const y = ctx.height * 0.95 - bandH;
  const headFont = { family: "Montserrat", size: 38 * u, weight: 900 };
  const itemFont = { family: "Montserrat", size: 36 * u, weight: 800 };
  const headSize = props.headline ? Math.min(headFont.size, fitText(props.headline, bandW * 0.4,
    { family: "Montserrat", weight: 900, letterSpacing: 2 * u }, { min: 10 * u, max: headFont.size })) : 0;
  const headW = props.headline
    ? measureText(props.headline, { family: "Montserrat", size: headSize, weight: 900, letterSpacing: 2 * u }).width + 56 * u
    : 0;
  const wipeIn = interpolate(frame, [0, 16], [0, 1], { easing: Easing.outCubic, clamp: true });
  const wipeOut = interpolate(frame, [D - 15, D - 1], [0, 1], { easing: Easing.inCubic, clamp: true });
  const clipLeft = x0 + bandW * wipeOut;
  const clipRight = x0 + bandW * wipeIn;
  const pop = spring({ frame: frame - 8, fps: ctx.fps, stiffness: 200, damping: 13 });
  const items = props.items.split("|").map((s) => s.trim()).filter((s) => s.length > 0);
  const bulletGap = 34 * u;
  const bulletR = 7 * u;
  const widths = items.map((s) => measureText(s, itemFont).width);
  const cycle = widths.reduce((a, w) => a + w + 2 * bulletGap, 0);
  const crawlLeft = x0 + headW;
  const crawlRight = x0 + bandW;
  const baseline = y + bandH / 2 + itemFont.size * 0.36;
  let crawl = "";
  if (items.length > 0 && cycle > 0) {
    const offset = props.speed * u * Math.max(0, ctx.time);
    let start = crawlRight - offset;
    if (start < crawlLeft - cycle) start += Math.floor((crawlLeft - start) / cycle - 1) * cycle;
    for (let k = 0; start + k * cycle < crawlRight; k++) {
      let x = start + k * cycle;
      items.forEach((s, i) => {
        if (x < crawlRight && x + widths[i] > crawlLeft) {
          crawl += `<text x="${x}" y="${baseline}" font-family="Montserrat" font-weight="800" font-size="${itemFont.size}"
                          fill="#ffffff">${escapeXml(s)}</text>`;
        }
        x += widths[i] + bulletGap;
        crawl += `<circle cx="${x}" cy="${y + bandH / 2}" r="${bulletR}" fill="${props.accent}"/>`;
        x += bulletGap;
      });
    }
  }
  const hx = x0 + headW / 2;
  const hy = y + bandH / 2;
  const headBox = props.headline && pop > 0.001
    ? `<g transform="translate(${hx} ${hy}) scale(${Math.min(1.06, pop)}) translate(${-hx} ${-hy})">
        <rect x="${x0}" y="${y}" width="${headW}" height="${bandH}" fill="${props.accent}"/>
        <text x="${hx}" y="${hy + headSize * 0.36}" text-anchor="middle" font-family="Montserrat" font-weight="900"
              font-size="${headSize}" letter-spacing="${2 * u}" fill="#ffffff">${escapeXml(props.headline)}</text>
      </g>`
    : "";
  return svg(ctx, `
    <defs>
      <clipPath id="band"><rect x="${clipLeft}" y="${y}" width="${Math.max(0, clipRight - clipLeft)}" height="${bandH}"/></clipPath>
      <clipPath id="crawl"><rect x="${crawlLeft}" y="${y}" width="${Math.max(0, crawlRight - crawlLeft)}" height="${bandH}"/></clipPath>
    </defs>
    ${clipRight - clipLeft > 0.5 ? `<g clip-path="url(#band)">
      <rect x="${x0}" y="${y}" width="${bandW}" height="${bandH}" fill="${props.background}" fill-opacity="0.92"/>
      <rect x="${x0}" y="${y}" width="${bandW}" height="${4 * u}" fill="${props.accent}"/>
      <g clip-path="url(#crawl)">${crawl}</g>
      ${headBox}
    </g>` : ""}`);
}
