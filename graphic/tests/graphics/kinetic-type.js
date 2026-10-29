// kinetic-type — road map 10 §5k 5: a sentence shown word by word, each word
// scaled in by a spring, wrapped with wrapText.
export const meta = {
  name: "Kinetic type",
  category: "Titles & Text",
  description: "A sentence shown word by word, each word springing in.",
  durationInFrames: 150,
};

export const schema = {
  text:    { type: "string", default: "Make something people want to watch twice, then cut it in half" },
  stagger: { type: "number", default: 4, min: 1, max: 30, step: 1 },
  color:   { type: "color",  default: "#ffffff" },
  accent:  { type: "color",  default: "#ffd60a" },
};

export function render(frame, props, ctx) {
  const u = ctx.height / 1080;
  const font = { family: "Montserrat", size: 110 * u, weight: 900 };
  const lines = wrapText(props.text, ctx.width * 0.8, font);
  const space = measureText("a a", font).width - measureText("aa", font).width;
  const lineHeight = font.size * 1.15;
  const firstBaseline = ctx.height / 2 - ((lines.length - 1) * lineHeight) / 2 + font.size * 0.35;
  let body = "";
  let index = 0;
  lines.forEach((line, row) => {
    const words = line.split(" ");
    const widths = words.map((w) => measureText(w, font).width);
    const total = widths.reduce((a, b) => a + b, 0) + space * (words.length - 1);
    let x = (ctx.width - total) / 2;
    const y = firstBaseline + row * lineHeight;
    words.forEach((word, i) => {
      const s = spring({ frame: frame - index * props.stagger, fps: ctx.fps, stiffness: 160, damping: 12 });
      const cx = x + widths[i] / 2;
      const fill = index % 5 === 3 ? props.accent : props.color;
      if (s > 0.001) {
        body += `<g transform="translate(${cx} ${y}) scale(${s}) translate(${-cx} ${-y})">` +
          `<text x="${x}" y="${y}" font-family="Montserrat" font-weight="900" font-size="${font.size}"` +
          ` fill="${fill}">${escapeXml(word)}</text></g>`;
      }
      x += widths[i] + space;
      index++;
    });
  });
  return svg(ctx, body, { background: "#0b0b10" });
}
