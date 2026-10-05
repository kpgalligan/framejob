// getLength, getPointAtLength and evolvePath (spec §11 G-31). Each row runs
// in its own `try`, and one Error at the end names every row that failed.
const CIRCLE = "M 500 0 A 500 500 0 1 1 -500 0 A 500 500 0 1 1 500 0";
const ELLIPSE = 968.8448220547675;   // 4a·E(e) for a = 200, b = 100
const PARABOLA = 100 * (Math.sqrt(5) + Math.asinh(2) / 2);
const CUSP = 100 * (13 * Math.sqrt(13) - 8) / 27;

// A length within 0.01 % of its closed form.
function measures(d, expected, label) {
  assertClose(getLength(d), expected, expected * 1e-4, label);
}

// The difference of two headings, in degrees, whichever way round they are written.
function turn(a, b) {
  return Math.abs(((a - b) % 360 + 540) % 360 - 180);
}

function pointIs(p, x, y, angle, label) {
  assertClose(p.x, x, 1e-9, `${label}: x`);
  assertClose(p.y, y, 1e-9, `${label}: y`);
  assert(turn(p.angle, angle) <= 1e-9, `${label}: angle ${p.angle}, expected ${angle}`);
}

const ROWS = {
  T1() {
    assertClose(getLength("M 0 0 L 3 4"), 5, 1e-9, "a 3-4-5 line");
    assertClose(getLength("M 0 0 H 10 V 10 H 0 Z"), 40, 1e-9, "a closed square");
    assertClose(getLength("m 0 0 h 10 v 10 h -10 z"), 40, 1e-9, "its relative spelling");
    assertClose(getLength("M 0 0 10 0 10 10"), 20, 1e-9, "pairs after M are lines");
    assertClose(getLength("M 0 0 L 3 4 M 10 10 L 13 14"), 10, 1e-9, "two subpaths add");
    assertClose(getLength("M0,0L.5.5-1-1"), Math.sqrt(0.5) + Math.sqrt(4.5), 1e-9,
      "four numbers written without separators");
    assertClose(getLength("M 0 0 L 1e2 0"), 100, 1e-9, "an exponent");
    assertClose(getLength("M 0 0 H 10 Z H 10"), 30, 1e-9, "a command after Z starts at the subpath's start");
  },
  T2() {
    measures(CIRCLE, 2 * Math.PI * 500, "a circle of radius 500");
    measures("M 500 0 A 500 500 0 0 1 0 500", 250 * Math.PI, "a quarter arc of radius 500");
    measures("M 200 0 A 200 100 0 1 1 -200 0 A 200 100 0 1 1 200 0", ELLIPSE, "an ellipse");
    const a = 200 * Math.cos(Math.PI / 6);
    const b = 200 * Math.sin(Math.PI / 6);
    measures(`M ${a} ${b} A 200 100 30 1 1 ${-a} ${-b} A 200 100 30 1 1 ${a} ${b}`, ELLIPSE,
      "the ellipse turned 30 degrees");
    measures("M 0 0 A 1 1 0 0 1 100 0", 50 * Math.PI, "radii scaled up to reach the end point");
    assertClose(getLength("M 0 0 A 0 50 0 0 1 30 40"), 50, 1e-9, "a zero-radius arc is its chord");
    measures("M0 0a50 50 0 01100 0", 50 * Math.PI, "flags written without separators");
  },
  T3() {
    measures("M -100 100 Q 0 -100 100 100", PARABOLA, "the parabola as a Q");
    const third = 100 / 3;
    const cubic = `M -100 100 C ${-third} ${-third} ${third} ${-third} 100 100`;
    measures(cubic, PARABOLA, "the parabola as a C");
    assertClose(getLength(cubic), getLength("M -100 100 Q 0 -100 100 100"), 1e-9, "the Q and the C agree");
    assertEqual(getLength("M 0 0 Q 50 100 100 0 T 200 0"), getLength("M 0 0 Q 50 100 100 0 Q 150 -100 200 0"),
      "a T is its explicit Q");
    assertEqual(getLength("M 0 0 C 0 50 50 100 100 100 S 200 50 200 0"),
      getLength("M 0 0 C 0 50 50 100 100 100 C 150 100 200 50 200 0"), "an S is its explicit C");
    assertClose(getLength("M 0 0 L 100 0 T 200 0"), 200, 1e-9,
      "a T after a line has its control at the current point");
  },
  T4() {
    measures("M 0 0 C 0 0 33.333333333333336 0 100 100", CUSP, "the cusp x = t², y = t³");
  },
  T5() {
    const total = getLength(CIRCLE);
    const want = [[0.25, 0, 500, 180], [0.5, -500, 0, -90], [0.75, 0, -500, 0]];
    for (const [part, x, y, angle] of want) {
      const p = getPointAtLength(CIRCLE, total * part);
      assertEqual(Object.keys(p).join(","), "x,y,angle", "the keys");
      assertClose(p.x, x, 0.01, `the circle at ${part}: x`);
      assertClose(p.y, y, 0.01, `the circle at ${part}: y`);
      assert(turn(p.angle, angle) <= 0.05, `the circle at ${part}: angle ${p.angle}, expected ${angle}`);
    }
    const bend = "M 0 0 H 10 V 10";
    pointIs(getPointAtLength(bend, 0), 0, 0, 0, "length 0 is the start");
    pointIs(getPointAtLength(bend, getLength(bend)), 10, 10, 90, "the total is the end");
    pointIs(getPointAtLength(bend, -5), 0, 0, 0, "a negative length clamps");
    pointIs(getPointAtLength(bend, 1e9), 10, 10, 90, "a length past the end clamps");
    pointIs(getPointAtLength(bend, NaN), 0, 0, 0, "NaN reads as 0");
    pointIs(getPointAtLength(bend, 10), 10, 0, 0, "at a corner the heading is the segment ending there");
    pointIs(getPointAtLength(bend, 10.5), 10, 0.5, 90, "past the corner");
    pointIs(getPointAtLength("M 0 0 H 100 M 0 50 H 60", 130), 30, 50, 0, "a length on the second subpath");
    pointIs(getPointAtLength("M 0 0 L 0 0 L 0 10", 0), 0, 0, 90, "a zero-length segment gives no heading");
    // Sweep 0: the heading turns with the way the arc is drawn.
    const back = "M 500 0 A 500 500 0 0 0 -500 0";
    const mid = getPointAtLength(back, getLength(back) / 2);
    assertClose(mid.x, 0, 0.01, "an arc drawn the other way: x");
    assertClose(mid.y, -500, 0.01, "an arc drawn the other way: y");
    assert(turn(mid.angle, 180) <= 0.05, `an arc drawn the other way: angle ${mid.angle}, expected 180`);
  },
  // The tangent's limit where the derivative is (0, 0), a row for each end.
  "T5 the limit at a start"() {
    assertClose(getPointAtLength("M 0 0 S 0 100 100 100", 0).angle, 90, 1e-9, "the heading");
  },
  "T5 the limit at an end"() {
    const d = "M 0 0 C 100 0 100 100 100 100";
    pointIs(getPointAtLength(d, getLength(d)), 100, 100, 90, "the point");
  },
  T6() {
    assertEqual(getLength(""), 0, "an empty path measures 0");
    assertEqual(JSON.stringify(getPointAtLength("", 5)), '{"x":0,"y":0,"angle":0}', "an empty path's point");
    assertEqual(getLength("M 10 20"), 0, "a move draws nothing");
    assertEqual(JSON.stringify(getPointAtLength("M 10 20", 5)), '{"x":10,"y":20,"angle":0}', "a move's point");
  },
  T7() {
    const d = "M 0 0 C 0 50 50 100 100 100";
    const D = getLength(d) * 1.001;
    const at = (progress) => evolvePath(progress, d);
    assertEqual(Object.keys(at(0)).join(","), "strokeDasharray,strokeDashoffset", "the keys");
    assertEqual(at(0).strokeDasharray, `${D} ${D}`, "the dash is the padded length, twice");
    assertEqual(at(0).strokeDashoffset, D, "the offset at 0");
    assertEqual(at(0.5).strokeDashoffset, D / 2, "the offset at 0.5");
    assertEqual(at(1).strokeDashoffset, 0, "the offset at 1");
    assertEqual(at(-1).strokeDashoffset, D, "a negative progress clamps");
    assertEqual(at(2).strokeDashoffset, 0, "a progress past 1 clamps");
    assertEqual(at(NaN).strokeDashoffset, D, "NaN reads as 0");
    assertEqual(JSON.stringify(evolvePath(0.5, "M 10 20")), '{"strokeDasharray":"none","strokeDashoffset":0}',
      "a path with no length");
    const two = "M 0 0 H 100 M 0 50 H 60";
    assertEqual(getLength(two), 160, "two subpaths measure their sum");
    assertEqual(evolvePath(0, two).strokeDashoffset, 100 * 1.001, "and are dashed by the longest");
    const closed = "M 0 0 H 30 M 0 50 H 20 V 70 H 0 Z";
    assertEqual(getLength(closed), 110, "a closed second subpath");
    assertEqual(evolvePath(0, closed).strokeDashoffset, 80 * 1.001, "is the longest with its closing line");
  },
  T8() {
    assertThrows(() => getLength("M 0 0 X 5 5"),
      ['getLength: cannot parse the path at character 6: "X 5 5"'], "an unknown command");
    assertThrows(() => getPointAtLength("L 0 0", 1),
      ['getPointAtLength: cannot parse the path at character 0: "L 0 0"'], "a path that does not begin with M");
    assertThrows(() => evolvePath(0.5, "M 0 0 A 1 1 0 2 0 5 5"),
      ['evolvePath: cannot parse the path at character 14: "2 0 5 5"'], "an arc flag that is not 0 or 1");
    assertThrows(() => getLength("M 0 0 L 5 Z"),
      ['getLength: cannot parse the path at character 10: "Z"'], "a number where none can be read");
    assertThrows(() => getLength("M 0 0 L 5"), ["getLength: the path ends inside a command"], "the data ran out");
    assertThrows(() => evolvePath(0.5, "M 0 0 L"), ["evolvePath: the path ends inside a command"],
      "a command with no numbers");
    for (const [f, message] of [
      [() => getLength("M 0 0 X 5 5"), 'getLength: cannot parse the path at character 6: "X 5 5"'],
      [() => getLength("M 0 0 L 5"), "getLength: the path ends inside a command"],
    ]) {
      let thrown = null;
      try { f(); } catch (e) { thrown = e.message; }
      assertEqual(thrown, message, "the whole sentence");
    }
  },
  // No helper answers Infinity or NaN: the path is refused in the same
  // sentence, at the number or at the command. A case for each of path.js's
  // five checks — the number read, the move, the arc's centre form, the
  // running length, the point answered — and every case runs though another
  // failed, so one message names each check that is gone.
  "T8 a number that is not finite"() {
    // One step under the largest number: its 64 measured points are finite
    // and a point between two of them is not.
    const edge = "M 1.7976931348623155e308 0 Q 1.7976931348623155e308 5 1.7976931348623155e308 10";
    const refused = (who, i, text) => `${who}: cannot parse the path at character ${i}: "${text}"`;
    const cases = [
      ["a number that reads as Infinity", () => getLength("M 0 0 L 1e999 0"), refused("getLength", 8, "1e999 0")],
      ["and the path going on after it", () => getLength("M 0 0 L 1e999 0 L 0 0"),
        refused("getLength", 8, "1e999 0 L 0 ")],
      ["a move past the largest number", () => getPointAtLength("M 1e308 0 m 1e308 0", 0),
        refused("getPointAtLength", 10, "m 1e308 0")],
      ["an arc whose radii overflow", () => getLength("M 0 0 A 1e300 1e300 0 0 1 1 0"),
        refused("getLength", 6, "A 1e300 1e30")],
      ["an arc whose chord underflows", () => getPointAtLength("M 0 0 A 1 1 0 0 1 1e-200 0", 0),
        refused("getPointAtLength", 6, "A 1 1 0 0 1 ")],
      ["a line whose square overflows", () => getLength("M 0 0 H 1e200"), refused("getLength", 6, "H 1e200")],
      ["the same as a pair after M", () => getPointAtLength("M 0 0 1e200 0", 1),
        refused("getPointAtLength", 6, "1e200 0")],
      ["a relative line past the largest number", () => evolvePath(0.5, "M 1e308 0 h 1e308"),
        refused("evolvePath", 10, "h 1e308")],
      ["a closing line whose square overflows", () => evolvePath(0.5, "M 0 0 H 1.2e154 V 1.2e154 Z"),
        refused("evolvePath", 26, "Z")],
      ["the curve under the largest number measures", () => getLength(edge), "answered 10"],
      ["and a point of it that overflows is refused", () => getPointAtLength(edge, 0.005),
        refused("getPointAtLength", 27, "Q 1.79769313")],
      ["a large path that stays finite is answered", () => getLength("M 0 0 H 1e153 V 1e153 Z") > 3.4e153,
        "answered true"],
    ];
    const wrong = [];
    for (const [label, call, expected] of cases) {
      let got;
      try {
        got = `answered ${JSON.stringify(call(), (key, v) => (typeof v === "number" && !isFinite(v) ? String(v) : v))}`;
      } catch (e) {
        got = e.message;
      }
      if (got !== expected) wrong.push(`${label}: ${got}`);
    }
    assert(wrong.length === 0, wrong.join(" / "));
  },
  T9() {
    const path = (i) => `M 0 0 Q ${i + 1} 50 100 0`;
    const first = getLength(path(0));
    const point = JSON.stringify(getPointAtLength(path(0), first / 3));
    for (let i = 1; i < 40; i++) getLength(path(i));
    assertEqual(getLength(path(0)), first, "the first path after 40 others");
    assertEqual(JSON.stringify(getPointAtLength(path(0), first / 3)), point, "and its point");
  },
};

export function render(frame, props, ctx) {
  const failed = [];
  for (const [row, run] of Object.entries(ROWS)) {
    try {
      run();
    } catch (e) {
      failed.push(`${row}: ${e.message}`);
    }
  }
  if (failed.length) throw new Error(failed.join("; "));
  return svg(ctx, "");
}
