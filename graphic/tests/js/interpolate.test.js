// interpolate: extrapolation (extend, clamp, identity) and multi-segment
// ranges; interpolateColors: OKLab, lowercase hex, exact endpoints.
export function render(frame, props, ctx) {
  assertEqual(interpolate(5, [0, 10], [0, 100]), 50, "inside");
  assertEqual(interpolate(20, [0, 10], [0, 100]), 200, "extend right");
  assertEqual(interpolate(-10, [0, 10], [0, 100]), -100, "extend left");
  assertEqual(interpolate(20, [0, 10], [0, 100], { clamp: true }), 100, "clamp right");
  assertEqual(interpolate(-10, [0, 10], [0, 100], { clamp: true }), 0, "clamp left");
  assertEqual(interpolate(20, [0, 10], [0, 100], { extrapolateRight: "identity" }), 20, "identity right");
  assertEqual(interpolate(-10, [0, 10], [0, 100], { extrapolateLeft: "identity" }), -10, "identity left");
  assertEqual(interpolate(-10, [0, 10], [0, 100], { extrapolateLeft: "clamp" }), 0, "clamp left only");
  assertEqual(interpolate(20, [0, 10], [0, 100], { extrapolateLeft: "clamp" }), 200, "right still extends");
  assertEqual(interpolate(5, [0, 10], [0, 100], { easing: Easing.inQuad }), 25, "eased");

  const input = [0, 10, 20, 30];
  const output = [0, 100, 50, 80];
  assertEqual(interpolate(5, input, output), 50, "segment 1");
  assertEqual(interpolate(10, input, output), 100, "the joint");
  assertEqual(interpolate(15, input, output), 75, "segment 2");
  assertEqual(interpolate(25, input, output), 65, "segment 3");
  assertEqual(interpolate(30, input, output), 80, "the end");
  assertEqual(interpolate(40, input, output), 110, "extends the last segment");
  assertEqual(interpolate(-10, input, output), -100, "extends the first segment");
  assertThrows(() => interpolate(1, [0], [0]), ["at least 2"], "one point");

  const mid = interpolateColors(0.5, [0, 1], ["#000000", "#ffffff"]);
  assert(/^#[0-9a-f]{6}$/.test(mid), `a 7-char lowercase hex: ${mid}`);
  assert(mid !== "#000000" && mid !== "#ffffff", "between the ends");
  assertEqual(interpolateColors(0, [0, 1], ["#000000", "#ffffff"]), "#000000", "left end");
  assertEqual(interpolateColors(1, [0, 1], ["#000000", "#ffffff"]), "#ffffff", "right end");
  assertEqual(interpolateColors(-5, [0, 1], ["#FF5A36", "#fff"]), "#ff5a36", "clamped left, lowercased");
  assertEqual(interpolateColors(5, [0, 1], ["#000", "#fff"]), "#ffffff", "clamped right, 3 digits");
  assertEqual(interpolateColors(1, [0, 1, 2], ["#000", "rgb(10, 20, 30)", "#fff"]), "#0a141e", "rgb() at a joint");
  assertEqual(interpolateColors(0, [0, 1], ["rgba(255, 0, 0, 0.5)", "#00ff00"]), "#ff000080", "alpha kept");
  assertEqual(interpolateColors(1, [0, 1], ["#ff000080", "#00ff00"]), "#00ff00ff", "alpha on every answer");
  assertEqual(interpolateColors(0.5, [0, 1], ["#abc", "#abc"]), "#aabbcc", "one colour stays itself");
  assertThrows(() => interpolateColors(0, [0, 1], ["bluish", "#000"]), ['cannot parse colour "bluish"'], "not a name");
  assertThrows(() => interpolateColors(0, [0, 1], ["rgb(300, 0, 0)", "#000"]),
    ['cannot parse colour "rgb(300, 0, 0)"'], "refused, never clamped");
  return svg(ctx, "");
}
