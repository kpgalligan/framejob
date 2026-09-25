// formatNumber, escapeXml, svg() and asset().
export function render(frame, props, ctx) {
  assertEqual(formatNumber(1284093.5, { decimals: 1 }), "1,284,093.5", "decimals");
  assertEqual(formatNumber(-1000), "-1,000", "negative");
  assertEqual(formatNumber(12, { separator: "." }), "12", "short");
  assertEqual(formatNumber(1234567, { separator: "." }), "1.234.567", "separator");
  assertEqual(formatNumber(999.6), "1,000", "rounds");
  assertEqual(formatNumber(0), "0", "zero");
  assertEqual(formatNumber(NaN), "NaN", "not a number");
  assertEqual(formatNumber(-Infinity), "-Infinity", "infinite");
  assertEqual(formatNumber(1e21), "1e+21", "exponent form, ungrouped");

  assertEqual(escapeXml(`<a & "b" 'c'>`), "&lt;a &amp; &quot;b&quot; &apos;c&apos;&gt;", "five entities");
  assertEqual(escapeXml(5), "5", "a number");

  const root = svg(ctx, "<g/>", { background: "#123456" });
  assert(root.startsWith("<svg"), "the root");
  assert(root.includes('width="1920"') && root.includes('height="1080"'), "the size");
  assert(root.includes('viewBox="0 0 1920 1080"'), "the viewBox");
  assert(root.includes('<rect x="0" y="0" width="1920" height="1080" fill="#123456"/><g/></svg>'),
    "the background rect, then the body");
  assert(!svg(ctx, "").includes("<rect"), "no background, no rect");
  assert(svg(ctx, "", { background: 'a"b' }).includes('fill="a&quot;b"'), "the background escaped");

  assertEqual(asset("red.png"), "red.png", "a known asset");
  return svg(ctx, "");
}
