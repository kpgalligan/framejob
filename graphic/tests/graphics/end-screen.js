// end-screen — a bundled template (spec §11 G-44): a full card laid out for
// a video's end screen — two 16:9 placeholders where the platform's video
// elements go and a subscribe circle — the two side by side with the circle
// centred under them in landscape and square, a column in portrait, under a title.
export const meta = {
  name: "End screen",
  category: "Social & YouTube",
  description: "An end screen card with two video spaces and a subscribe circle.",
  durationInFrames: 300,
};

export const schema = {
  title:      { type: "string", default: "Watch next" },
  videoA:     { type: "string", default: "Latest video" },
  videoB:     { type: "string", default: "Best for you" },
  subscribe:  { type: "string", default: "Subscribe" },
  background: { type: "color",  default: "#0b0b10" },
  accent:     { type: "color",  default: "#ff5a36" },
};

export function render(frame, props, ctx) {
  const u = Math.min(ctx.width, ctx.height) / 1080;
  const D = ctx.durationInFrames;
  const W = ctx.width;
  const H = ctx.height;
  // A square frame takes the landscape layout: a portrait column would not fit its height.
  const landscape = W >= H;
  const safeX = W * 0.05;
  const safeY = H * 0.05;
  const safeW = W * 0.9;
  const safeH = H * 0.9;
  const out = interpolate(frame, [D - 15, D - 1], [1, 0], { clamp: true });
  const titleSize = props.title ? fitText(props.title, safeW - 120 * u, { family: "Montserrat", weight: 900 },
    { min: 16 * u, max: (landscape ? 96 : 84) * u }) : 0;
  const labelFont = { family: "Montserrat", size: (landscape ? 38 : 34) * u, weight: 800 };
  const gap = (landscape ? 64 : 48) * u;
  const labelH = 70 * u;
  let boxW;
  let boxH;
  let circleD;
  let boxes;
  let circle;
  let titleY;
  if (landscape) {
    // YouTube's "two videos and a subscribe" layout: the two videos side by side, each about a
    // third of the frame's width, and the subscribe circle centred under them at about two
    // thirds of a video's height, everything held to the safe width and height.
    const titleGap = 56 * u;
    const circleGap = 24 * u;
    const fromHeight = ((safeH - 40 * u - titleSize - titleGap - 2 * labelH - circleGap) / 1.62) * (16 / 9);
    // 20u spare at each side holds the dashed outline and the entrance spring's overshoot.
    boxW = Math.max(0, Math.min(W * (W > H ? 0.34 : 0.42), (safeW - gap - 40 * u) / 2, fromHeight));
    boxH = (boxW * 9) / 16;
    circleD = boxH * 0.62;
    const blockH = titleSize + titleGap + boxH + labelH + circleGap + circleD + labelH;
    const top = safeY + (safeH - blockH) / 2;
    titleY = top + titleSize * 0.8;
    const rowTop = top + titleSize + titleGap;
    const x = (W - 2 * boxW - gap) / 2;
    boxes = [
      { x, y: rowTop, label: props.videoA },
      { x: x + boxW + gap, y: rowTop, label: props.videoB },
    ];
    circle = { cx: W / 2, cy: rowTop + boxH + labelH + circleGap + circleD / 2 };
  } else {
    boxW = W * 0.8;
    boxH = (boxW * 9) / 16;
    circleD = 260 * u;
    const blockH = titleSize + 60 * u + 2 * (boxH + labelH) + gap + circleD + labelH;
    const top = safeY + (safeH - blockH) / 2;
    titleY = top + titleSize * 0.8;
    const x = (W - boxW) / 2;
    const first = top + titleSize + 60 * u;
    boxes = [
      { x, y: first, label: props.videoA },
      { x, y: first + boxH + labelH + gap / 2, label: props.videoB },
    ];
    circle = { cx: W / 2, cy: first + 2 * (boxH + labelH) + gap + circleD / 2 };
  }
  const titleIn = interpolate(frame, [0, 16], [0, 1], { easing: Easing.outCubic, clamp: true });
  let body = props.title ? `<text x="${W / 2}" y="${titleY + (1 - titleIn) * 20 * u}" text-anchor="middle"
    font-family="Montserrat" font-weight="900" font-size="${titleSize}" fill="#ffffff"
    fill-opacity="${titleIn * out}">${escapeXml(props.title)}</text>` : "";
  boxes.forEach((b, i) => {
    const t = spring({ frame: frame - 8 - i * 6, fps: ctx.fps, stiffness: 150, damping: 15 });
    if (t <= 0.001) return;
    const a = Math.min(1, t) * out;
    const cx = b.x + boxW / 2;
    const cy = b.y + boxH / 2;
    const s = 0.9 + 0.1 * t;
    const g = boxH * 0.2;
    const size = Math.min(labelFont.size, fitText(b.label || " ", boxW, labelFont, { min: 10 * u, max: labelFont.size }));
    body += `<g transform="translate(${cx} ${cy}) scale(${s}) translate(${-cx} ${-cy})">
      <rect x="${b.x}" y="${b.y}" width="${boxW}" height="${boxH}" rx="${14 * u}" fill="#ffffff" fill-opacity="${0.06 * a}"
            stroke="#ffffff" stroke-opacity="${0.55 * a}" stroke-width="${3 * u}" stroke-dasharray="${16 * u} ${10 * u}"/>
      <circle cx="${cx}" cy="${cy}" r="${g}" fill="${props.accent}" fill-opacity="${a}"/>
      <path d="M ${cx - g * 0.32} ${cy - g * 0.45} L ${cx + g * 0.5} ${cy} L ${cx - g * 0.32} ${cy + g * 0.45} Z"
            fill="#ffffff" fill-opacity="${a}"/>
      <text x="${cx}" y="${b.y + boxH + (landscape ? 50 : 46) * u}" text-anchor="middle" font-family="Montserrat" font-weight="800"
            font-size="${size}" fill="#d8d8e0" fill-opacity="${a}">${escapeXml(b.label)}</text></g>`;
  });
  const pop = spring({ frame: frame - 24, fps: ctx.fps, stiffness: 190, damping: 12 });
  if (pop > 0.001) {
    const r = circleD / 2;
    const pulse = interpolate(frame, [40, 70], [0, 1], { easing: Easing.outCubic, clamp: true });
    const a = out;
    const size = Math.min(labelFont.size, fitText(props.subscribe || " ", Math.max(circleD, 200 * u), labelFont,
      { min: 10 * u, max: labelFont.size }));
    const head = r * 0.3;
    body += `<g transform="translate(${circle.cx} ${circle.cy}) scale(${pop})">
      ${pulse > 0 && pulse < 1 ? `<circle cx="0" cy="0" r="${r + 26 * u * pulse}" fill="none" stroke="${props.accent}"
              stroke-width="${4 * u}" stroke-opacity="${(1 - pulse) * a}"/>` : ""}
      <circle cx="0" cy="0" r="${r}" fill="#ffffff" fill-opacity="${0.06 * a}" stroke="${props.accent}"
              stroke-opacity="${a}" stroke-width="${5 * u}" stroke-dasharray="${16 * u} ${10 * u}"/>
      <circle cx="0" cy="${-head * 0.62}" r="${head}" fill="#8a8a94" fill-opacity="${a}"/>
      <path d="M ${-r * 0.5} ${r * 0.55} C ${-r * 0.5} ${r * 0.1} ${-r * 0.25} ${r * 0.0} 0 ${r * 0.0}
               C ${r * 0.25} ${r * 0.0} ${r * 0.5} ${r * 0.1} ${r * 0.5} ${r * 0.55} Z" fill="#8a8a94" fill-opacity="${a}"/>
      <text x="0" y="${r + 46 * u}" text-anchor="middle" font-family="Montserrat" font-weight="800" font-size="${size}"
            fill="#ffffff" fill-opacity="${a}">${escapeXml(props.subscribe)}</text></g>`;
  }
  return svg(ctx, body, { background: props.background });
}
