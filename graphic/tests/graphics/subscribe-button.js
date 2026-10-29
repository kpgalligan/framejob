// subscribe-button — a bundled template (spec §11 G-44): a pill button with
// a play glyph pops in, a cursor glides to it and clicks (a squash and a
// ripple), the button turns to its done state with a check, and a bell pops
// in beside it and rings after a second click. Every glyph is a generic
// vector shape.
export const meta = {
  name: "Subscribe button",
  category: "Social & YouTube",
  description: "A subscribe button clicked by a cursor, with a bell.",
  durationInFrames: 150,
};

export const schema = {
  label:     { type: "string",  default: "SUBSCRIBE" },
  doneLabel: { type: "string",  default: "SUBSCRIBED" },
  bell:      { type: "boolean", default: true },
  position:  { type: "enum",    default: "bottom", options: ["bottom", "center", "top"] },
  accent:    { type: "color",   default: "#e5322d" },
};

const DONE = "#3a3a40";

function bellPath(g) {
  const s = (v) => v * g;
  return `M ${s(-0.36)} ${s(0.26)} C ${s(-0.26)} ${s(0.14)} ${s(-0.28)} ${s(0.02)} ${s(-0.28)} ${s(-0.12)}
    C ${s(-0.28)} ${s(-0.34)} ${s(-0.15)} ${s(-0.46)} 0 ${s(-0.46)} C ${s(0.15)} ${s(-0.46)} ${s(0.28)} ${s(-0.34)} ${s(0.28)} ${s(-0.12)}
    C ${s(0.28)} ${s(0.02)} ${s(0.26)} ${s(0.14)} ${s(0.36)} ${s(0.26)} Z`;
}

export function render(frame, props, ctx) {
  const u = Math.min(ctx.width, ctx.height) / 1080;
  const D = ctx.durationInFrames;
  const safeY = ctx.height * 0.05;
  const safeW = ctx.width * 0.9;
  const safeH = ctx.height * 0.9;
  const click = Math.round(D * 0.4);
  const done = frame >= click + 3;
  const btnH = 96 * u;
  const font = { family: "Montserrat", size: 38 * u, weight: 900, letterSpacing: 2 * u };
  const room = safeW - 2 * 60 * u - (props.bell ? btnH + 24 * u : 0) - btnH * 1.1;
  const sizeOf = (t) => Math.min(font.size, fitText(t, room, font, { min: 10 * u, max: font.size }));
  const widthOf = (t, size) => measureText(t, Object.assign({}, font, { size })).width;
  const sizeA = sizeOf(props.label);
  const sizeB = sizeOf(props.doneLabel);
  const wA = btnH * 0.95 + widthOf(props.label, sizeA) + 44 * u;
  const wB = btnH * 0.95 + widthOf(props.doneLabel, sizeB) + 44 * u;
  const morph = interpolate(frame, [click + 2, click + 12], [0, 1], { easing: Easing.inOutCubic, clamp: true });
  const btnW = wA + (wB - wA) * morph;
  const bellD = btnH;
  const groupW = Math.max(wA, wB) + (props.bell ? 24 * u + bellD : 0);
  const margin = 70 * u;
  const cy = props.position === "top" ? safeY + margin + btnH / 2
    : props.position === "center" ? ctx.height / 2
    : safeY + safeH - margin - btnH / 2 - 40 * u;
  const gx = ctx.width / 2 - groupW / 2;
  const bx = gx;
  const bcx = bx + btnW / 2;
  const pop = spring({ frame, fps: ctx.fps, stiffness: 180, damping: 12 });
  const squash = interpolate(frame, [click - 2, click + 1, click + 7], [1, 0.94, 1], { clamp: true });
  const out = interpolate(frame, [D - 15, D - 1], [0, 1], { easing: Easing.inCubic, clamp: true });
  const fill = done ? DONE : props.accent;
  const label = done ? props.doneLabel : props.label;
  const size = done ? sizeB : sizeA;
  const ix = bx + btnH * 0.55;
  const g = btnH * 0.42;
  const icon = done
    ? `<path d="M ${ix - g * 0.38} ${cy} L ${ix - g * 0.1} ${cy + g * 0.28} L ${ix + g * 0.4} ${cy - g * 0.3}" fill="none"
             stroke="#ffffff" stroke-width="${7 * u}" stroke-linecap="round" stroke-linejoin="round"/>`
    : `<path d="M ${ix - g * 0.3} ${cy - g * 0.42} L ${ix + g * 0.45} ${cy} L ${ix - g * 0.3} ${cy + g * 0.42} Z" fill="#ffffff"
             stroke="#ffffff" stroke-width="${4 * u}" stroke-linejoin="round"/>`;
  // The click lands on the button's right end, past the label's last letter in either state, so
  // the cursor never covers the label; it rides that end as the button grows to its done label.
  const target1x = bx + btnW - btnH * 0.3;
  const ripple = interpolate(frame, [click, click + 16], [0, 1], { easing: Easing.outCubic, clamp: true });
  const rippleOn = frame >= click && ripple < 1;
  const button = `
    <clipPath id="pill"><rect x="${bx}" y="${cy - btnH / 2}" width="${btnW}" height="${btnH}" rx="${btnH / 2}"/></clipPath>
    <g transform="translate(${bcx} ${cy}) scale(${squash}) translate(${-bcx} ${-cy})">
      <rect x="${bx}" y="${cy - btnH / 2}" width="${btnW}" height="${btnH}" rx="${btnH / 2}" fill="${fill}"/>
      ${rippleOn ? `<g clip-path="url(#pill)"><circle cx="${target1x}" cy="${cy}" r="${btnW * ripple}"
          fill="#ffffff" fill-opacity="${0.35 * (1 - ripple)}"/></g>` : ""}
      ${icon}
      <text x="${bx + btnH * 0.95}" y="${cy + size * 0.36}" font-family="Montserrat" font-weight="900" font-size="${size}"
            letter-spacing="${2 * u}" fill="#ffffff">${escapeXml(label)}</text>
    </g>`;

  // The bell pops in after the first click, the cursor clicks it, and it rings.
  const bellX = bx + Math.max(wA, wB) + 24 * u + bellD / 2;
  const click2 = click + 26;
  let bell = "";
  if (props.bell) {
    const bpop = spring({ frame: frame - click - 8, fps: ctx.fps, stiffness: 200, damping: 11 });
    const t = (frame - click2) / ctx.fps;
    const ring = frame >= click2 ? 18 * Math.exp(-3 * t) * Math.sin(t * 2 * Math.PI * 3.2) : 0;
    const on = frame >= click2;
    if (bpop > 0.001) {
      const bg = bellD * 0.62;
      bell = `<g transform="translate(${bellX} ${cy}) scale(${bpop})">
        <circle cx="0" cy="0" r="${bellD / 2}" fill="${on ? props.accent : DONE}"/>
        <g transform="translate(0 ${-bg * 0.08}) rotate(${ring} 0 ${-bg * 0.46})">
          <path d="${bellPath(bg)}" fill="#ffffff"/>
          <circle cx="0" cy="${bg * 0.36}" r="${bg * 0.1}" fill="#ffffff"/>
          <circle cx="0" cy="${-bg * 0.5}" r="${bg * 0.07}" fill="#ffffff"/>
        </g></g>`;
    }
  }

  // The cursor: from the lower right inside title-safe, to the button's right end, then the bell.
  const target2x = bellX + bellD * 0.1;
  const tipY = cy + btnH * 0.12;
  const startX = Math.min(ctx.width * 0.95 - 120 * u, bx + wA - btnH * 0.3 + 380 * u);
  const startY = Math.min(ctx.height * 0.95 - 120 * u, cy + 150 * u);
  const glide = interpolate(frame, [10, click - 4], [0, 1], { easing: Easing.inOutCubic, clamp: true });
  const hop = interpolate(frame, [click + 10, click2 - 4], [0, 1], { easing: Easing.inOutCubic, clamp: true });
  let curX = startX + (target1x - startX) * glide;
  let curY = startY + (tipY - startY) * glide;
  if (props.bell) {
    curX += (target2x - target1x) * hop;
    curY += -12 * u * Math.sin(Math.PI * hop);
  }
  const press = frame >= click - 2 && frame < click + 4 ? 0.88
    : props.bell && frame >= click2 - 2 && frame < click2 + 4 ? 0.88 : 1;
  const curIn = interpolate(frame, [8, 16], [0, 1], { clamp: true });
  const k = 46 * u;
  const cursor = curIn > 0 ? `<g transform="translate(${curX} ${curY}) scale(${press})" opacity="${curIn}">
      <path d="M 0 0 L 0 ${k} L ${k * 0.25} ${k * 0.77} L ${k * 0.42} ${k * 1.12} L ${k * 0.56} ${k * 1.05}
               L ${k * 0.4} ${k * 0.71} L ${k * 0.72} ${k * 0.71} Z" fill="#ffffff" stroke="#111114"
            stroke-width="${3 * u}" stroke-linejoin="round"/>
    </g>` : "";
  const gcx = ctx.width / 2;
  const scale = pop * (1 - 0.15 * out);
  return svg(ctx, `
    <g opacity="${1 - out}" transform="translate(${gcx} ${cy}) scale(${scale}) translate(${-gcx} ${-cy})">
      ${button}${bell}${cursor}
    </g>`);
}
