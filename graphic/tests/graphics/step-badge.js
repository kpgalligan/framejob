// step-badge — a bundled template (spec §11 G-44): a numbered accent circle
// popping in at a corner, with a label panel wiping out from behind it.
export const meta = {
  name: "Step badge",
  category: "Screencast",
  description: "A numbered badge at a corner, with a label panel.",
  durationInFrames: 90,
};

export const schema = {
  number:   { type: "number", default: 1, min: 0, max: 99, step: 1, animate: false },
  label:    { type: "string", default: "Open the export sheet" },
  position: { type: "enum",   default: "top-left", options: ["top-left", "top-right", "bottom-left", "bottom-right"] },
  accent:   { type: "color",  default: "#ff5a36" },
};

export function render(frame, props, ctx) {
  const u = Math.min(ctx.width, ctx.height) / 1080;
  const D = ctx.durationInFrames;
  const safeX = ctx.width * 0.05;
  const safeY = ctx.height * 0.05;
  const safeW = ctx.width * 0.9;
  const safeH = ctx.height * 0.9;
  const R = 60 * u;
  const margin = 40 * u;
  const right = props.position.endsWith("right");
  const bottom = props.position.startsWith("bottom");
  const cx = right ? safeX + safeW - margin - R : safeX + margin + R;
  const cy = bottom ? safeY + safeH - margin - R : safeY + margin + R;
  const n = String(Math.max(0, Math.min(99, Math.round(props.number))));
  const numberSize = n.length > 1 ? 58 * u : 68 * u;
  const panelH = 88 * u;
  const font = { family: "Montserrat", size: 42 * u, weight: 800 };
  const maxText = safeW - 2 * margin - 2 * R - 90 * u;
  const size = props.label ? Math.min(font.size, fitText(props.label, maxText, font, { min: 10 * u, max: font.size })) : font.size;
  const textW = props.label ? measureText(props.label, { family: "Montserrat", size, weight: 800 }).width : 0;
  const panelW = R + 34 * u + textW + 40 * u;
  const pop = spring({ frame, fps: ctx.fps, stiffness: 190, damping: 10 });
  const open = interpolate(frame, [8, 26], [0, 1], { easing: Easing.outCubic, clamp: true });
  const close = interpolate(frame, [D - 15, D - 8], [0, 1], { easing: Easing.inCubic, clamp: true });
  const shrink = interpolate(frame, [D - 8, D - 1], [1, 0], { easing: Easing.inBack, clamp: true });
  const wipe = Math.max(0, open - close);
  const scale = Math.max(0, pop * shrink);
  const px = right ? cx - panelW : cx;
  const py = cy - panelH / 2;
  const shown = panelW * wipe;
  const clipX = right ? cx - shown : cx;
  const textX = right ? cx - R - 34 * u : cx + R + 34 * u;
  const slide = (1 - wipe) * 30 * u * (right ? 1 : -1);
  const panel = shown > 0.5 && props.label
    ? `<clipPath id="wipe"><rect x="${clipX}" y="${py}" width="${shown}" height="${panelH}" rx="${Math.min(shown / 2, panelH / 2)}"/></clipPath>
      <g clip-path="url(#wipe)">
        <rect x="${px}" y="${py}" width="${panelW}" height="${panelH}" rx="${panelH / 2}" fill="#101014" fill-opacity="0.82"/>
        <text x="${textX + slide}" y="${cy + size * 0.36}" text-anchor="${right ? "end" : "start"}" font-family="Montserrat"
              font-weight="800" font-size="${size}" fill="#ffffff">${escapeXml(props.label)}</text>
      </g>`
    : "";
  const badge = scale > 0.001
    ? `<g transform="translate(${cx} ${cy}) scale(${scale})">
        <circle cx="0" cy="0" r="${R}" fill="${props.accent}"/>
        <circle cx="0" cy="0" r="${R - 7 * u}" fill="none" stroke="#ffffff" stroke-opacity="0.35" stroke-width="${3 * u}"/>
        <text x="0" y="${numberSize * 0.36}" text-anchor="middle" font-family="Montserrat" font-weight="900"
              font-size="${numberSize}" fill="#ffffff">${n}</text>
      </g>`
    : "";
  return svg(ctx, `${panel}${badge}`);
}
