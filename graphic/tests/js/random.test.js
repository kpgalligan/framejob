// random(seed) and noise2D/noise3D: stable, and in range.
export function render(frame, props, ctx) {
  assertEqual(random(1), random(1), "stable for a number");
  assertEqual(random("a"), random("a"), "stable for a string");
  assertEqual(random(1), random("1"), "a seed is its text");
  assert(random(1) !== random(2), "seeds differ");
  for (let i = 0; i < 1000; i++) {
    const v = random(i);
    assert(v >= 0 && v < 1, `random(${i}) = ${v}`);
  }
  assertEqual(noise2D(7, 0.3, 0.8), noise2D(7, 0.3, 0.8), "noise2D stable");
  assertEqual(noise3D(7, 0.3, 0.8, 1.9), noise3D(7, 0.3, 0.8, 1.9), "noise3D stable");
  assert(noise2D(7, 0.3, 0.8) !== noise2D(8, 0.3, 0.8), "noise2D seeds differ");
  let spread2 = 0;
  let spread3 = 0;
  for (let i = 0; i < 40; i++) {
    for (let j = 0; j < 40; j++) {
      const a = noise2D("s", i * 0.37, j * 0.23);
      const b = noise3D("s", i * 0.37, j * 0.23, (i + j) * 0.11);
      assert(a >= -1 && a <= 1, `noise2D in range: ${a}`);
      assert(b >= -1 && b <= 1, `noise3D in range: ${b}`);
      spread2 = Math.max(spread2, Math.abs(a));
      spread3 = Math.max(spread3, Math.abs(b));
    }
  }
  assert(spread2 > 0.3 && spread3 > 0.3, `noise varies: ${spread2} ${spread3}`);
  return svg(ctx, "");
}
