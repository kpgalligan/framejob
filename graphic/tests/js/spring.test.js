// spring settles to `to`, starts at `from`, and a frame's value does not
// depend on which frames were asked before it.
export function render(frame, props, ctx) {
  assertEqual(spring({ frame: 0, fps: 30 }), 0, "frame 0 is from");
  assertEqual(spring({ frame: -5, fps: 30, from: 2 }), 2, "before frame 0 is from");
  assertClose(spring({ frame: 300, fps: 30 }), 1, 1e-3, "settles to 1");
  assertClose(spring({ frame: 300, fps: 30, from: 2, to: 5, damping: 14 }), 5, 1e-3, "settles to 5");
  assertClose(spring({ frame: 600, fps: 60, stiffness: 180, damping: 18, mass: 2 }), 1, 1e-3, "heavier");
  const first = spring({ frame: 40, fps: 30, damping: 12 });
  spring({ frame: 5, fps: 30, damping: 12 });
  spring({ frame: 90, fps: 30, damping: 12 });
  assertEqual(spring({ frame: 40, fps: 30, damping: 12 }), first, "frame 40 after 5 and 90");
  assert(spring({ frame: 10, fps: 30, damping: 8 }) > 1, "an underdamped spring overshoots");
  return svg(ctx, "");
}
