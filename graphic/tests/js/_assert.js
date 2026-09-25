// Appended after each `*.test.js` by `tests/stdlib.rs`. Function
// declarations hoist, so a test's line numbers are its own file's.

function assert(condition, label) {
  if (!condition) throw new Error(`assertion failed: ${label}`);
}

function assertEqual(actual, expected, label) {
  if (actual !== expected) {
    throw new Error(`${label}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}

function assertClose(actual, expected, tolerance, label) {
  if (!(Math.abs(actual - expected) <= tolerance)) {
    throw new Error(`${label}: expected ${expected} ± ${tolerance}, got ${actual}`);
  }
}

function assertThrows(f, fragments, label) {
  let message = null;
  try {
    f();
  } catch (e) {
    message = String(e.message);
  }
  if (message === null) throw new Error(`${label}: did not throw`);
  for (const fragment of fragments) {
    if (!message.includes(fragment)) {
      throw new Error(`${label}: ${JSON.stringify(message)} does not include ${JSON.stringify(fragment)}`);
    }
  }
}
