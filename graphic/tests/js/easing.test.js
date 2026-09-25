// Every easing starts at 0 and ends at 1; bezier too.
export function render(frame, props, ctx) {
  const names = ["linear"];
  for (const curve of ["Quad", "Cubic", "Quart", "Expo", "Sine", "Back", "Elastic"]) {
    names.push("in" + curve, "out" + curve, "inOut" + curve);
  }
  assertEqual(names.length, 22, "the easings");
  for (const name of names) {
    const f = Easing[name];
    assertEqual(typeof f, "function", name);
    assertEqual(f(0), 0, `${name}(0)`);
    assertEqual(f(1), 1, `${name}(1)`);
  }
  assertEqual(Easing.inQuad(0.5), 0.25, "inQuad(0.5)");
  assertEqual(Easing.outQuad(0.5), 0.75, "outQuad(0.5)");
  assertEqual(Easing.inOutCubic(0.5), 0.5, "inOutCubic(0.5)");
  const ease = Easing.bezier(0.25, 0.1, 0.25, 1);
  assertEqual(ease(0), 0, "bezier(0)");
  assertEqual(ease(1), 1, "bezier(1)");
  let last = 0;
  for (let i = 1; i < 20; i++) {
    const v = ease(i / 20);
    assert(v > last && v < 1, `bezier rises at ${i / 20}`);
    last = v;
  }
  const straight = Easing.bezier(0, 0, 1, 1);
  assertClose(straight(0.3), 0.3, 1e-6, "a straight bezier is linear");
  assert(Object.isFrozen(Easing), "Easing is frozen");
  return svg(ctx, "");
}
