// bar-chart — road map 10 §5k 4: `values` as a comma-separated string, bars
// growing in sequence, labels.
export const meta = {
  name: "Bar chart",
  durationInFrames: 150,
};

export const schema = {
  values: { type: "string", default: "12, 19, 7, 24, 15, 30" },
  labels: { type: "string", default: "Mon, Tue, Wed, Thu, Fri, Sat" },
  title:  { type: "string", default: "Sessions per day" },
  color:  { type: "color",  default: "#2d7ff9" },
};

export function render(frame, props, ctx) {
  const u = ctx.height / 1080;
  const values = props.values.split(",").map((v) => Number(v.trim())).filter((v) => isFinite(v));
  const labels = props.labels.split(",").map((l) => l.trim());
  const top = Math.max(1, ...values);
  const chartLeft = 200 * u;
  const chartRight = ctx.width - 200 * u;
  const base = ctx.height - 200 * u;
  const tall = ctx.height - 460 * u;
  const slot = (chartRight - chartLeft) / Math.max(1, values.length);
  const barWidth = slot * 0.62;
  let bars = "";
  values.forEach((v, i) => {
    const grow = spring({ frame: frame - 10 - i * 8, fps: ctx.fps, damping: 13 });
    const h = (v / top) * tall * grow;
    const x = chartLeft + slot * i + (slot - barWidth) / 2;
    const shown = Math.round(v * Math.min(1, Math.max(0, grow)));
    bars += `<rect x="${x}" y="${base - h}" width="${barWidth}" height="${h}" fill="${props.color}"/>`;
    bars += `<text x="${x + barWidth / 2}" y="${base - h - 16 * u}" text-anchor="middle" font-family="IBM Plex Mono"
                   font-size="${34 * u}" fill="#ffffff" opacity="${Math.min(1, Math.max(0, grow))}">${shown}</text>`;
    bars += `<text x="${x + barWidth / 2}" y="${base + 56 * u}" text-anchor="middle" font-family="Bebas Neue"
                   font-size="${44 * u}" fill="#c8c8d0">${escapeXml(labels[i] || "")}</text>`;
  });
  const titleIn = interpolate(frame, [0, 15], [0, 1], { clamp: true });
  return svg(ctx, `
    <text x="${chartLeft}" y="${150 * u}" font-family="Montserrat" font-weight="900" font-size="${72 * u}"
          fill="#ffffff" opacity="${titleIn}">${escapeXml(props.title)}</text>
    <line x1="${chartLeft}" y1="${base}" x2="${chartRight}" y2="${base}" stroke="#ffffff55" stroke-width="${3 * u}"/>
    ${bars}`, { background: "#15151b" });
}
