// countdown — a bundled template (spec §11 G-44): a timer counting from
// `from` to `to` one step a second (up when `to` is greater), its digits
// pulsing on each tick inside a ring that empties or fills, and a flash at
// the end.
export const meta = {
  name: "Countdown",
  category: "Data & Time",
  description: "A timer counting down or up inside a ring, flashing at the end.",
  durationInFrames: 330,
};

export const schema = {
  from:   { type: "number",  default: 10 },
  to:     { type: "number",  default: 0 },
  format: { type: "enum",    default: "m:ss", options: ["seconds", "m:ss", "h:mm:ss"] },
  label:  { type: "string",  default: "Starting in" },
  ring:   { type: "boolean", default: true },
  accent: { type: "color",   default: "#ff5a36" },
};

function clock(n, format) {
  const sign = n < 0 ? "-" : "";
  const s = Math.abs(n);
  const two = (v) => String(v).padStart(2, "0");
  if (format === "seconds") return sign + s;
  if (format === "h:mm:ss") return `${sign}${Math.floor(s / 3600)}:${two(Math.floor(s / 60) % 60)}:${two(s % 60)}`;
  return `${sign}${Math.floor(s / 60)}:${two(s % 60)}`;
}

export function render(frame, props, ctx) {
  const u = Math.min(ctx.width, ctx.height) / 1080;
  const D = ctx.durationInFrames;
  const from = Math.round(props.from);
  const to = Math.round(props.to);
  const steps = Math.abs(to - from);
  const t = Math.max(0, ctx.time);
  const ticked = Math.min(steps, Math.floor(t));
  const n = to < from ? from - ticked : from + ticked;
  const done = t >= steps;
  const cx = ctx.width / 2;
  const cy = ctx.height / 2;
  const R = 300 * u;
  const thick = 22 * u;
  const enter = spring({ frame, fps: ctx.fps, stiffness: 140, damping: 15 });
  const out = interpolate(frame, [D - 15, D - 1], [1, 0], { clamp: true });
  const local = t - Math.floor(t);
  const pulse = done && t - steps > 0.3 ? 1 : interpolate(local, [0, 0.3], [1.08, 1], { easing: Easing.outCubic, clamp: true });
  // From equal to `to` there is nothing to count: the ring stands at its end state and nothing flashes.
  const left = steps === 0 ? 0 : Math.max(0, Math.min(1, 1 - t / steps));
  const ringShown = to < from ? left : 1 - left;
  const text = clock(n, props.format);
  const widest = clock(from, props.format).length >= clock(to, props.format).length
    ? clock(from, props.format) : clock(to, props.format);
  const digitSize = fitText(widest.replace(/[0-9]/g, "0"), R * 1.45, { family: "IBM Plex Mono", weight: 500 },
    { min: 12 * u, max: 190 * u });
  const flash = done && steps > 0 ? interpolate(t - steps, [0, 0.6], [0.85, 0], { easing: Easing.outCubic, clamp: true }) : 0;
  const labelText = props.label.toUpperCase();
  const labelSize = fitText(labelText, R * 1.3, { family: "Montserrat", weight: 800, letterSpacing: 5 * u },
    { min: 10 * u, max: 34 * u });
  const circumference = 2 * Math.PI * R;
  return svg(ctx, `
    <g opacity="${out * Math.min(1, enter * 1.4)}"
       transform="translate(${cx} ${cy}) scale(${0.85 + 0.15 * enter}) translate(${-cx} ${-cy})">
      <circle cx="${cx}" cy="${cy}" r="${R + thick / 2 + 8 * u}" fill="#101014" fill-opacity="0.82"/>
      ${flash > 0 ? `<circle cx="${cx}" cy="${cy}" r="${R + thick / 2 + 8 * u}" fill="${props.accent}" fill-opacity="${flash}"/>` : ""}
      ${props.ring ? `
      <circle cx="${cx}" cy="${cy}" r="${R}" fill="none" stroke="#ffffff" stroke-opacity="0.12" stroke-width="${thick}"/>
      ${ringShown > 0.0005 ? `<circle cx="${cx}" cy="${cy}" r="${R}" fill="none" stroke="${props.accent}"
              stroke-width="${thick}" stroke-linecap="round" stroke-dasharray="${circumference * ringShown} ${circumference}"
              transform="rotate(-90 ${cx} ${cy})"/>` : ""}` : ""}
      <text x="${cx}" y="${cy - digitSize * 0.62}" text-anchor="middle" font-family="Montserrat" font-weight="800"
            font-size="${labelSize}" letter-spacing="${5 * u}" fill="#d8d8e0">${escapeXml(labelText)}</text>
      <g transform="translate(${cx} ${cy + digitSize * 0.12}) scale(${pulse})">
        <text x="0" y="${digitSize * 0.35}" text-anchor="middle" font-family="IBM Plex Mono" font-weight="500"
              font-size="${digitSize}" fill="#ffffff">${escapeXml(text)}</text>
      </g>
    </g>`);
}
