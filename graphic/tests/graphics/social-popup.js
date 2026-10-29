// social-popup — a bundled template (spec §11 G-44): a notification card
// with a generic avatar and a handle (and, for a comment, its text) rising
// in at a corner, and the kind's glyph — a heart, a speech bubble or a share
// arrow — popping as its count ticks up by one.
export const meta = {
  name: "Social popup",
  category: "Social & YouTube",
  description: "A like, comment or share notification rising in at a corner.",
  durationInFrames: 120,
};

export const schema = {
  kind:     { type: "enum",   default: "like", options: ["like", "comment", "share"] },
  handle:   { type: "string", default: "@framejob" },
  text:     { type: "string", default: "Loved this edit!" },
  count:    { type: "number", default: 1280, min: 0, step: 1, animate: false },
  position: { type: "enum",   default: "bottom-right", options: ["bottom-right", "bottom-left", "top-right", "top-left"] },
  accent:   { type: "color",  default: "#ff3b30" },
};

// The kind's glyph centred on (0, 0), `g` across.
function glyph(kind, g, colour) {
  const s = (v) => v * g;
  if (kind === "comment") {
    return `<path d="M ${s(-0.32)} ${s(-0.38)} L ${s(0.32)} ${s(-0.38)} Q ${s(0.46)} ${s(-0.38)} ${s(0.46)} ${s(-0.24)}
      L ${s(0.46)} ${s(0.1)} Q ${s(0.46)} ${s(0.24)} ${s(0.32)} ${s(0.24)} L ${s(-0.04)} ${s(0.24)} L ${s(-0.28)} ${s(0.44)}
      L ${s(-0.24)} ${s(0.24)} L ${s(-0.32)} ${s(0.24)} Q ${s(-0.46)} ${s(0.24)} ${s(-0.46)} ${s(0.1)}
      L ${s(-0.46)} ${s(-0.24)} Q ${s(-0.46)} ${s(-0.38)} ${s(-0.32)} ${s(-0.38)} Z" fill="${colour}"/>`;
  }
  if (kind === "share") {
    return `<path d="M ${s(0.08)} ${s(-0.42)} L ${s(0.48)} ${s(-0.04)} L ${s(0.08)} ${s(0.34)} L ${s(0.08)} ${s(0.12)}
      C ${s(-0.2)} ${s(0.1)} ${s(-0.36)} ${s(0.2)} ${s(-0.48)} ${s(0.4)} C ${s(-0.44)} ${s(0.04)} ${s(-0.22)} ${s(-0.18)} ${s(0.08)} ${s(-0.2)} Z"
      fill="${colour}" stroke="${colour}" stroke-width="${0.04 * g}" stroke-linejoin="round"/>`;
  }
  return `<path d="M 0 ${s(0.4)} C ${s(-0.3)} ${s(0.18)} ${s(-0.5)} ${s(0.0)} ${s(-0.5)} ${s(-0.18)}
    C ${s(-0.5)} ${s(-0.36)} ${s(-0.36)} ${s(-0.46)} ${s(-0.24)} ${s(-0.46)} C ${s(-0.12)} ${s(-0.46)} ${s(-0.03)} ${s(-0.39)} 0 ${s(-0.3)}
    C ${s(0.03)} ${s(-0.39)} ${s(0.12)} ${s(-0.46)} ${s(0.24)} ${s(-0.46)} C ${s(0.36)} ${s(-0.46)} ${s(0.5)} ${s(-0.36)} ${s(0.5)} ${s(-0.18)}
    C ${s(0.5)} ${s(0.0)} ${s(0.3)} ${s(0.18)} 0 ${s(0.4)} Z" fill="${colour}"/>`;
}

export function render(frame, props, ctx) {
  const u = Math.min(ctx.width, ctx.height) / 1080;
  const D = ctx.durationInFrames;
  const safeX = ctx.width * 0.05;
  const safeY = ctx.height * 0.05;
  const safeW = ctx.width * 0.9;
  const safeH = ctx.height * 0.9;
  const comment = props.kind === "comment";
  const margin = 50 * u;
  const pad = 26 * u;
  const avatar = 84 * u;
  const handleFont = { family: "Montserrat", size: 36 * u, weight: 800 };
  const textFont = { family: "Montserrat", size: 32 * u, weight: 800 };
  const count = Math.max(0, Math.round(props.count));
  const countSize = fitText(formatNumber(count + 1), 220 * u, { family: "IBM Plex Mono", weight: 500 },
    { min: 10 * u, max: 34 * u });
  const countFont = { family: "IBM Plex Mono", size: countSize, weight: 500 };
  const cardMax = Math.min(safeW - 2 * margin, 760 * u);
  const g = 48 * u;
  const countW = measureText(formatNumber(count + 1), countFont).width;
  const sideW = g + 14 * u + countW;
  const gapW = 56 * u;
  const textMax = Math.max(60 * u, cardMax - 2 * pad - avatar - 24 * u - gapW - sideW);
  const handleSize = props.handle ? Math.min(handleFont.size, fitText(props.handle, textMax, handleFont,
    { min: 10 * u, max: handleFont.size })) : handleFont.size;
  const lines = comment && props.text.trim() ? wrapText(props.text, textMax, textFont).slice(0, 3) : [];
  const handleW = measureText(props.handle, { family: "Montserrat", size: handleSize, weight: 800 }).width;
  const linesW = Math.max(0, ...lines.map((l) => measureText(l, textFont).width));
  const textW = Math.max(handleW, linesW, 160 * u);
  const cardW = 2 * pad + avatar + 24 * u + textW + gapW + sideW;
  const cardH = Math.max(avatar + 2 * pad, 2 * pad + handleSize + (lines.length ? 14 * u + lines.length * textFont.size * 1.25 : 0));
  const right = props.position.endsWith("right");
  const bottom = props.position.startsWith("bottom");
  const x = right ? safeX + safeW - margin - cardW : safeX + margin;
  const y0 = bottom ? safeY + safeH - margin - cardH : safeY + margin;
  const enter = spring({ frame, fps: ctx.fps, stiffness: 150, damping: 16 });
  const leave = interpolate(frame, [D - 15, D - 1], [0, 1], { easing: Easing.inCubic, clamp: true });
  const y = y0 + (1 - Math.min(1, enter)) * 30 * u + leave * 30 * u;
  const a = Math.max(0, Math.min(1, enter * 1.5)) * (1 - leave);
  const popAt = 18;
  const pop = interpolate(frame, [popAt, popAt + 6, popAt + 14], [0, 1.3, 1], { easing: Easing.outCubic, clamp: true });
  const ticked = frame >= popAt + 6 ? count + 1 : count;
  const ax = x + pad + avatar / 2;
  const ay = y + cardH / 2;
  const tx = x + pad + avatar + 24 * u;
  const textBlock = handleSize + (lines.length ? 14 * u + lines.length * textFont.size * 1.25 : 0);
  const handleY = y + (cardH - textBlock) / 2 + handleSize * 0.8;
  let body = `<text x="${tx}" y="${handleY}" font-family="Montserrat" font-weight="800" font-size="${handleSize}"
    fill="#ffffff" fill-opacity="${a}">${escapeXml(props.handle)}</text>`;
  lines.forEach((line, i) => {
    body += `<text x="${tx}" y="${handleY + 14 * u + (i + 1) * textFont.size * 1.25}" font-family="Montserrat"
      font-weight="800" font-size="${textFont.size}" fill="#d8d8e0" fill-opacity="${a}">${escapeXml(line)}</text>`;
  });
  const gx = x + cardW - pad - sideW + g / 2;
  const gy = y + cardH / 2;
  const divX = tx + textW + gapW / 2;
  return svg(ctx, `
    <rect x="${x}" y="${y}" width="${cardW}" height="${cardH}" rx="${18 * u}" fill="#101014" fill-opacity="${0.9 * a}"/>
    <circle cx="${ax}" cy="${ay}" r="${avatar / 2}" fill="#3a3a44" fill-opacity="${a}"/>
    <circle cx="${ax}" cy="${ay - avatar * 0.1}" r="${avatar * 0.17}" fill="#9a9aa6" fill-opacity="${a}"/>
    <path d="M ${ax - avatar * 0.3} ${ay + avatar * 0.33} C ${ax - avatar * 0.3} ${ay + avatar * 0.12} ${ax - avatar * 0.14} ${ay + avatar * 0.08}
             ${ax} ${ay + avatar * 0.08} C ${ax + avatar * 0.14} ${ay + avatar * 0.08} ${ax + avatar * 0.3} ${ay + avatar * 0.12}
             ${ax + avatar * 0.3} ${ay + avatar * 0.33} Z" fill="#9a9aa6" fill-opacity="${a}"/>
    ${body}
    <line x1="${divX}" y1="${y + 22 * u}" x2="${divX}" y2="${y + cardH - 22 * u}" stroke="#ffffff"
          stroke-opacity="${0.12 * a}" stroke-width="${2 * u}"/>
    ${pop > 0.001 ? `<g transform="translate(${gx} ${gy}) scale(${pop})" fill-opacity="${a}" stroke-opacity="${a}">${glyph(props.kind, g, props.accent)}</g>` : ""}
    <text x="${gx + g / 2 + 14 * u}" y="${gy + countFont.size * 0.36}" font-family="IBM Plex Mono" font-weight="500"
          font-size="${countFont.size}" fill="#ffffff" fill-opacity="${a}">${formatNumber(ticked)}</text>`);
}
