// window-frame — a bundled template (spec §11 G-44): a window's chrome to
// sit over a screen recording on the track beneath — a title bar with three
// dots and a title (window) or an address field (browser), and a rounded
// outline. The content area stays transparent.
export const meta = {
  name: "Window frame",
  durationInFrames: 150,
};

export const schema = {
  style:  { type: "enum",    default: "browser", options: ["browser", "window"] },
  title:  { type: "string",  default: "Frame Job" },
  url:    { type: "string",  default: "example.com" },
  theme:  { type: "enum",    default: "dark", options: ["dark", "light"] },
  scale:  { type: "number",  default: 0.86, min: 0.5, max: 1, step: 0.01 },
  shadow: { type: "boolean", default: true },
  accent: { type: "color",   default: "#ff5a36" },
};

export function render(frame, props, ctx) {
  const u = Math.min(ctx.width, ctx.height) / 1080;
  const D = ctx.durationInFrames;
  const dark = props.theme !== "light";
  const bar = dark ? "#2a2a31" : "#e9e9ee";
  const edge = dark ? "#4a4a54" : "#c4c4cc";
  const field = dark ? "#1b1b20" : "#ffffff";
  const ink = dark ? "#e8e8ee" : "#2a2a31";
  const faint = dark ? "#8a8a96" : "#8a8a96";
  const scale = Math.max(0.5, Math.min(1, props.scale));
  const safeW = ctx.width * 0.9;
  const safeH = ctx.height * 0.9;
  // The outline (2u, straddling the edge) stays inside title-safe even at scale 1.
  const lw = 2 * u;
  const w = Math.min(safeW * scale, safeW - 2 * lw);
  const h = Math.min(safeH * scale, safeH - 2 * lw);
  const x = (ctx.width - w) / 2;
  const y = (ctx.height - h) / 2;
  const r = 12 * u;
  const barH = 64 * u;
  const enter = spring({ frame, fps: ctx.fps, stiffness: 120, damping: 17 });
  // The geometry never overshoots, so the window never grows past its settled size.
  const settle = Math.min(1, enter);
  const out = interpolate(frame, [D - 15, D - 1], [1, 0], { clamp: true });
  const grow = 0.96 + 0.04 * settle;
  const alpha = Math.max(0, Math.min(1, enter * 1.6)) * out;
  const cx = ctx.width / 2;
  const cy = ctx.height / 2;
  // The shadow is kept inside title-safe: it is only as wide as the margin around the window allows.
  const margin = Math.min((safeW - w) / 2, (safeH - h) / 2);
  const blur = Math.min(26 * u, margin / 2.2);
  // The rise is capped so the bottom edge, outline or shadow, never drops below title-safe while
  // the window is still scaled down: (1 − settle)(rise − 0.02h) stays within the bottom margin.
  const reach = Math.max(lw / 2, props.shadow && blur >= 1 ? blur * 1.6 : 0);
  const riseMax = Math.max(0, Math.min(30 * u, 0.02 * h + (safeH - h) / 2 - reach));
  const rise = (1 - settle) * riseMax;

  let dots = "";
  ["#ff5f57", "#febc2e", "#28c840"].forEach((colour, i) => {
    const s = spring({ frame: frame - 8 - i * 4, fps: ctx.fps, stiffness: 260, damping: 12 });
    if (s > 0.001) {
      dots += `<circle cx="${x + 32 * u + i * 26 * u}" cy="${y + barH / 2}" r="${8 * u * s}" fill="${colour}" fill-opacity="${alpha}"/>`;
    }
  });
  const uiFont = { family: "Source Sans 3", size: 26 * u, weight: 600 };
  let middle = "";
  const left = x + 130 * u;
  const room = w - 2 * 130 * u;
  if (props.style === "window") {
    const size = Math.min(uiFont.size, fitText(props.title, room, uiFont, { min: 8 * u, max: uiFont.size }));
    middle = `<text x="${cx}" y="${y + barH / 2 + size * 0.35}" text-anchor="middle" font-family="'Source Sans 3'"
                    font-weight="600" font-size="${size}" fill="${ink}" fill-opacity="${alpha}">${escapeXml(props.title)}</text>`;
  } else {
    const fieldW = Math.min(room - 90 * u, Math.max(360 * u, w * 0.5));
    const fieldH = 38 * u;
    const fx = cx - fieldW / 2;
    const fy = y + (barH - fieldH) / 2;
    const size = Math.min(uiFont.size, fitText(props.url, fieldW - 90 * u, uiFont, { min: 8 * u, max: uiFont.size }));
    const nav = (dx, dir) => {
      const nx = left + dx;
      const ny = y + barH / 2;
      const k = 8 * u * dir;
      return `<path d="M ${nx + k} ${ny - 8 * u} L ${nx - k} ${ny} L ${nx + k} ${ny + 8 * u}" fill="none" stroke="${faint}"
                    stroke-opacity="${alpha}" stroke-width="${3 * u}" stroke-linecap="round" stroke-linejoin="round"/>`;
    };
    const lx = fx + 26 * u;
    const ly = fy + fieldH / 2;
    middle = `${nav(0, 1)}${nav(36 * u, -1)}
      <rect x="${fx}" y="${fy}" width="${fieldW}" height="${fieldH}" rx="${fieldH / 2}" fill="${field}"
            fill-opacity="${alpha}" stroke="${props.accent}" stroke-opacity="${alpha}" stroke-width="${2.5 * u}"/>
      <rect x="${lx - 7 * u}" y="${ly - 3 * u}" width="${14 * u}" height="${11 * u}" rx="${2 * u}" fill="${faint}" fill-opacity="${alpha}"/>
      <path d="M ${lx - 4.5 * u} ${ly - 3 * u} v ${-3 * u} a ${4.5 * u} ${4.5 * u} 0 0 1 ${9 * u} 0 v ${3 * u}" fill="none"
            stroke="${faint}" stroke-opacity="${alpha}" stroke-width="${2 * u}"/>
      <text x="${cx}" y="${ly + size * 0.35}" text-anchor="middle" font-family="'Source Sans 3'" font-weight="600"
            font-size="${size}" fill="${ink}" fill-opacity="${alpha}">${escapeXml(props.url)}</text>`;
  }
  // A soft shadow of thin rings outside the outline, fading outward: a filter would cost ten
  // times the frame budget, and a ring never darkens the transparent content area.
  let shadow = "";
  if (props.shadow && blur >= 1) {
    const rings = 12;
    const step = (blur * 1.6) / rings;
    for (let i = 0; i < rings; i++) {
      const o = (i + 0.5) * step;
      const fall = 1 - i / rings;
      shadow += `<rect x="${x - o}" y="${y - o}" width="${w + 2 * o}" height="${h + 2 * o}" rx="${r + o}" fill="none"
                       stroke="#000000" stroke-opacity="${0.16 * fall * fall * alpha}" stroke-width="${step}"/>`;
    }
  }
  // Opacity per element, so no frame isolates a window-sized layer.
  return svg(ctx, `
    <g transform="translate(${cx} ${cy + rise}) scale(${grow}) translate(${-cx} ${-cy})">
      ${shadow}
      <path d="M ${x} ${y + barH} v ${-(barH - r)} a ${r} ${r} 0 0 1 ${r} ${-r} h ${w - 2 * r} a ${r} ${r} 0 0 1 ${r} ${r}
               v ${barH - r} Z" fill="${bar}" fill-opacity="${alpha}"/>
      <line x1="${x}" y1="${y + barH}" x2="${x + w}" y2="${y + barH}" stroke="${edge}" stroke-opacity="${alpha}" stroke-width="${1.5 * u}"/>
      <rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}" fill="none" stroke="${edge}" stroke-opacity="${alpha}" stroke-width="${lw}"/>
      ${dots}${middle}
    </g>`);
}
