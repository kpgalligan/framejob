// measureText, wrapText, fitText and textLines.
export function render(frame, props, ctx) {
  const font = { family: "Montserrat", size: 64, weight: 800 };
  const m = measureText("Hello", font);
  assertEqual(Object.keys(m).join(","), "width,ascent,descent,lineHeight,inkX,inkWidth", "the keys");
  assert(m.width > 0 && m.ascent > 0 && m.inkWidth > 0, "a word has a size");
  assertEqual(measureText("Hello", font).width, m.width, "stable");
  assert(measureText("Hello", Object.assign({}, font, { letterSpacing: 10 })).width > m.width,
    "letter-spacing widens");
  assertEqual(measureText("Hello").width, measureText("Hello", { family: "Montserrat", size: 16 }).width,
    "the defaults");
  assertThrows(() => measureText("Hi", { family: "Nope" }),
    ["Nope", "Anton", "Bebas Neue", "Darker Grotesque", "IBM Plex Mono", "Montserrat", "Source Sans 3",
      "Source Serif 4"],
    "a family the set lacks");

  // G-6: a generic keyword measures in the face it maps to, and is written bare.
  const sans = { family: "sans-serif", size: 64, weight: 600 };
  assertEqual(JSON.stringify(measureText("Hamburg", sans)),
    JSON.stringify(measureText("Hamburg", Object.assign({}, sans, { family: "Source Sans 3" }))),
    "sans-serif is Source Sans 3");
  const generic = textLines(["x"], { font: sans });
  assert(generic.includes(`font-family="sans-serif"`), `a generic is unquoted: ${generic}`);

  // G-22: xmlSpace.
  const plain = { family: "Source Sans 3", size: 64 };
  const preserved = Object.assign({}, plain, { xmlSpace: "preserve" });
  assert(measureText("a  b", preserved).width > measureText("a  b", plain).width,
    "preserve keeps the second space");
  assertEqual(measureText("a  b", Object.assign({}, plain, { xmlSpace: "default" })).width,
    measureText("a b", plain).width, "default collapses");
  const kept = textLines(["a  b"], { font: preserved });
  assert(kept.includes(`xml:space="preserve"`), `textLines writes xml:space: ${kept}`);
  assert(!textLines(["a  b"], { font: plain }).includes("xml:space"), "and only when asked");
  assertThrows(() => measureText("a", Object.assign({}, plain, { xmlSpace: "keep" })),
    ['measureText: xmlSpace must be "default" or "preserve", not "keep"'], "a bad xmlSpace");

  const word = "Supercalifragilisticexpialidocious";
  const lines = wrapText(word, 200, font);
  assert(lines.length > 1, `split by characters: ${JSON.stringify(lines)}`);
  assertEqual(lines.join(""), word, "no character lost");
  for (const line of lines) assert(measureText(line, font).width <= 200, `fits: ${line}`);
  const words = wrapText("one two three four five six", 300, font);
  assert(words.length > 1, "wrapped at spaces");
  assertEqual(words.join(" "), "one two three four five six", "no word lost");

  assertEqual(fitText("Hello", 1e6, font, { min: 10, max: 50 }), 50, "capped at max");
  assertEqual(fitText("Hello", 1, font, { min: 10, max: 50 }), 10, "floored at min");
  const size = fitText("Hello", 500, font);
  assert(size >= 8 && size <= 400, "the default bounds");
  assert(measureText("Hello", Object.assign({}, font, { size })).width <= 500 + 1, "the size fits");

  const markup = textLines(["a < b", "c"], { x: 10, y: 20, font: { family: "Source Sans 3", size: 40 } });
  assert(markup.includes(`font-family="'Source Sans 3'"`), `quoted: ${markup}`);
  assert(markup.includes("a &lt; b"), "escaped lines");
  assertEqual((markup.match(/<tspan/g) || []).length, 2, "one tspan per line");
  assert(markup.includes('dy="48"'), "lineHeight defaults to 1.2 × size");
  const quoted = textLines(["x"], { font: { family: "O'Brien" } });
  assert(quoted.includes(`font-family="'OBrien'"`), `the family's own quote stripped: ${quoted}`);
  return svg(ctx, "");
}
