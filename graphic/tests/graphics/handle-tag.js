// handle-tag — a bundled template (spec §11 G-44): an accent tile holding a
// generic vector glyph pops in at a corner, and a pill with the @handle
// expands from behind it. No platform's own mark is drawn.
export const meta = {
  name: "Handle tag",
  category: "Social & YouTube",
  description: "An @handle in a pill beside a glyph tile, at a corner.",
  durationInFrames: 120,
};

export const schema = {
  handle:   { type: "string", default: "@framejob" },
  glyph:    { type: "enum",   default: "play", options: ["play", "camera", "bubble", "note", "globe"] },
  position: { type: "enum",   default: "bottom-left", options: ["bottom-left", "bottom-right", "top-left", "top-right"] },
  accent:   { type: "color",  default: "#ff5a36" },
};

// A glyph centred on (0, 0), `g` across, in white.
function glyph(kind, g) {
  const s = (v) => v * g;
  const line = `fill="none" stroke="#ffffff" stroke-width="${0.09 * g}" stroke-linecap="round" stroke-linejoin="round"`;
  if (kind === "camera") {
    return `<path d="M ${s(-0.46)} ${s(-0.2)} Q ${s(-0.46)} ${s(-0.28)} ${s(-0.38)} ${s(-0.28)} L ${s(-0.18)} ${s(-0.28)}
        L ${s(-0.1)} ${s(-0.4)} L ${s(0.1)} ${s(-0.4)} L ${s(0.18)} ${s(-0.28)} L ${s(0.38)} ${s(-0.28)}
        Q ${s(0.46)} ${s(-0.28)} ${s(0.46)} ${s(-0.2)} L ${s(0.46)} ${s(0.3)} Q ${s(0.46)} ${s(0.38)} ${s(0.38)} ${s(0.38)}
        L ${s(-0.38)} ${s(0.38)} Q ${s(-0.46)} ${s(0.38)} ${s(-0.46)} ${s(0.3)} Z" ${line}/>
      <circle cx="0" cy="${s(0.05)}" r="${s(0.17)}" ${line}/>`;
  }
  if (kind === "bubble") {
    return `<path d="M ${s(-0.34)} ${s(-0.36)} L ${s(0.34)} ${s(-0.36)} Q ${s(0.46)} ${s(-0.36)} ${s(0.46)} ${s(-0.24)}
        L ${s(0.46)} ${s(0.12)} Q ${s(0.46)} ${s(0.24)} ${s(0.34)} ${s(0.24)} L ${s(-0.06)} ${s(0.24)} L ${s(-0.26)} ${s(0.42)}
        L ${s(-0.24)} ${s(0.24)} L ${s(-0.34)} ${s(0.24)} Q ${s(-0.46)} ${s(0.24)} ${s(-0.46)} ${s(0.12)}
        L ${s(-0.46)} ${s(-0.24)} Q ${s(-0.46)} ${s(-0.36)} ${s(-0.34)} ${s(-0.36)} Z" ${line}/>`;
  }
  if (kind === "note") {
    return `<path d="M ${s(-0.14)} ${s(0.28)} L ${s(-0.14)} ${s(-0.3)} L ${s(0.36)} ${s(-0.42)} L ${s(0.36)} ${s(0.16)}" ${line}/>
      <ellipse cx="${s(-0.25)}" cy="${s(0.3)}" rx="${s(0.14)}" ry="${s(0.11)}" fill="#ffffff"/>
      <ellipse cx="${s(0.25)}" cy="${s(0.18)}" rx="${s(0.14)}" ry="${s(0.11)}" fill="#ffffff"/>`;
  }
  if (kind === "globe") {
    return `<circle cx="0" cy="0" r="${s(0.42)}" ${line}/>
      <ellipse cx="0" cy="0" rx="${s(0.18)}" ry="${s(0.42)}" ${line}/>
      <path d="M ${s(-0.42)} 0 L ${s(0.42)} 0 M ${s(-0.36)} ${s(-0.2)} L ${s(0.36)} ${s(-0.2)} M ${s(-0.36)} ${s(0.2)} L ${s(0.36)} ${s(0.2)}" ${line}/>`;
  }
  return `<path d="M ${s(-0.24)} ${s(-0.36)} L ${s(0.38)} 0 L ${s(-0.24)} ${s(0.36)} Z" fill="#ffffff" stroke="#ffffff"
    stroke-width="${0.08 * g}" stroke-linejoin="round"/>`;
}

export function render(frame, props, ctx) {
  const u = Math.min(ctx.width, ctx.height) / 1080;
  const D = ctx.durationInFrames;
  const safeX = ctx.width * 0.05;
  const safeY = ctx.height * 0.05;
  const safeW = ctx.width * 0.9;
  const safeH = ctx.height * 0.9;
  const tile = 96 * u;
  const pillH = 76 * u;
  const margin = 50 * u;
  const right = props.position.endsWith("right");
  const bottom = props.position.startsWith("bottom");
  const tx = right ? safeX + safeW - margin - tile : safeX + margin;
  const ty = bottom ? safeY + safeH - margin - tile : safeY + margin;
  const tcx = tx + tile / 2;
  const tcy = ty + tile / 2;
  const font = { family: "Montserrat", size: 42 * u, weight: 800 };
  const maxText = safeW - 2 * margin - tile - 80 * u;
  const size = props.handle ? Math.min(font.size, fitText(props.handle, maxText, font, { min: 10 * u, max: font.size })) : font.size;
  const textW = props.handle ? measureText(props.handle, { family: "Montserrat", size, weight: 800 }).width : 0;
  const pillW = tile / 2 + 30 * u + textW + 36 * u;
  const pop = spring({ frame, fps: ctx.fps, stiffness: 200, damping: 11 });
  const open = interpolate(frame, [8, 26], [0, 1], { easing: Easing.outCubic, clamp: true });
  const close = interpolate(frame, [D - 15, D - 8], [0, 1], { easing: Easing.inCubic, clamp: true });
  const shrink = interpolate(frame, [D - 8, D - 1], [1, 0], { easing: Easing.inBack, clamp: true });
  const wipe = Math.max(0, open - close);
  const shown = pillW * wipe;
  const px = right ? tcx - pillW : tcx;
  const py = tcy - pillH / 2;
  const clipX = right ? tcx - shown : tcx;
  const textX = right ? tx - 30 * u : tx + tile + 30 * u;
  const slide = (1 - wipe) * 36 * u * (right ? 1 : -1);
  const pill = shown > 0.5 && props.handle
    ? `<clipPath id="wipe"><rect x="${clipX}" y="${py}" width="${shown}" height="${pillH}" rx="${Math.min(shown / 2, pillH / 2)}"/></clipPath>
      <g clip-path="url(#wipe)">
        <rect x="${px}" y="${py}" width="${pillW}" height="${pillH}" rx="${pillH / 2}" fill="#101014" fill-opacity="0.82"/>
        <text x="${textX + slide}" y="${tcy + size * 0.36}" text-anchor="${right ? "end" : "start"}" font-family="Montserrat"
              font-weight="800" font-size="${size}" fill="#ffffff">${escapeXml(props.handle)}</text>
      </g>`
    : "";
  const scale = Math.max(0, pop * shrink);
  const badge = scale > 0.001
    ? `<g transform="translate(${tcx} ${tcy}) scale(${scale})">
        <rect x="${-tile / 2}" y="${-tile / 2}" width="${tile}" height="${tile}" rx="${10 * u}" fill="${props.accent}"/>
        ${glyph(props.glyph, tile * 0.56)}
      </g>`
    : "";
  return svg(ctx, `${pill}${badge}`);
}
