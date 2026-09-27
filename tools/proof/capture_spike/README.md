# The capture spike — road map 11, V1 (2026-09-26)

Four questions V2's `snapshot_ui` and `perform_menu_item` cannot be designed
without, and the instrument that measures them. **The answers are not here**:
they are in `designs/reelcut-roadmap-11.md`'s V1 record, which also lists
what they changed in V2's text. What is here is how to run it again.

- **q1** — the preview well of a live, on-screen editor under `cacheDisplay`,
  and which way of putting a still under the canvas overlay for a capture
  keeps the overlay on top and leaves the view tree as it was;
- **q2** — a sheet put up by a menu item with the main run loop still free,
  captured and closed; and the inventory of which menu items reach a sheet, a
  window, or a modal run loop;
- **q3** — switching a live window's appearance, capturing and restoring;
- **q4** — `hasAmbiguousLayout` and "intrinsic width > frame width" in an
  `-O`, whole-module build.

```sh
python3 tools/proof/capture_spike/capture_spike.py                  # all four
python3 tools/proof/capture_spike/capture_spike.py --only q2,q4     # a subset; other rows carry forward
python3 tools/proof/capture_spike/capture_spike.py --rebuild        # rebuild the probe regardless
```

Needs `swiftc`, `xcrun metal` and `core/target/release/libreelcut_core.a`
(`cd core && cargo build --release`). No port, no ffmpeg, no MCP.

**Run it with the terminal frontmost, the display on, a backing-scale-2
(built-in) screen attached, and nobody at the machine.** The W, S and A rows
need the probe's window on screen and not occluded, and the S1–S3 and A1–A7
rows need the probe to become the active app with the editor key
(`NSApp.activate()`, then `makeKeyAndOrderFront`, a ≤ 3 s poll). W4a–c's
answer depends on the display scale — the recorded digest is scale 2's; on a
scale-1 screen the M-core is ~300 px and W4a–c pass — so the probe puts every
window it opens on the first scale-2 screen (`ProbeSupport.place`), whichever
screen is key. When it cannot, those rows are skipped BY NAME —
`host: console locked`, `host: no display`, `host: window occluded`,
`host: probe not active`, `host: no scale-2 screen` (W4a–c) — and a run with
such a skip has not answered the questions those rows cover. A W4 window
that lands at another scale while a scale-2 screen exists is a failure, not
a skip.

## The instruments

| File | What it is |
|---|---|
| `capture_spike.py` | the runner: host facts, the two fixtures, the shader and the probe build (B0), one bounded child per mode, scoring, `answers.json`, the digest, the exit code |
| `rows.py` | the row table (ID, question, kind, mode) and one pure predicate per row over the probe's JSON; `host_skip` |
| `inventory.py` | the site grep over `app/Sources`, the I1–I4 checks, the printed menu table |
| `inventory.json` | the hand-read inventory: every live menu selector's verdict (`none`, `sheet`, `window`, `modal`, `framework`) with the lines that present, and every grep site traced to the selectors that reach it — `reached_from` (inside the action), `reached_after` (a completion, an async hop or a delegate callback, with its `via` line and `gate`) |
| `capture_probe.swift` | the probe's entry, copied to `work/capture_spike/probe/main.swift`: arguments, mode dispatch, the one `ANSWER` line |
| `probe_support.swift` | boot (`.regular`, `finishLaunching`, the argument-domain pins, the app's fonts), `ProbeEditor` (a package opened as the app opens one, 1440 × 862), activation, the settle capture, capture-pixel mapping, masks and statistics |
| `probe_well.swift` | `well` — W0–W6 |
| `probe_sheets.swift` | `sheets` (S0–S3), `modal` (S4) and `menu` (I1's leaves) |
| `probe_appearance.swift` | `appearance` — A0–A7 |
| `probe_layout.swift` | `layout` — L1–L7 |

The probe is `capture_probe.swift` compiled LAST with every file in
`app/Sources` but `main.swift` and the five `probe_*.swift`, over
`harness/build.sh`'s swiftc line plus Release's two settings:

```sh
swiftc -O -wmo -D REELCUT_DEV_TOOLS -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
    -target arm64-apple-macos26.0 -module-name Reelcut \
    -import-objc-header app/Bridging/Reelcut-Bridging-Header.h \
    -L core/target/release -lreelcut_core <app/Sources/*.swift but main.swift> \
    tools/proof/capture_spike/probe_*.swift <probe>/main.swift -o <probe>/capture_probe
```

with `Fonts/`, `Blank.mp4`, a `default.metallib` of `Compositor.metal`,
`GraphicTemplates/*.js` and `GraphicsAPI.md` beside it. By hand:
`capture_probe <well|sheets|modal|menu|appearance|layout> <fixtures-dir> <png-dir>`
prints exactly one stdout line, `ANSWER <json>`.

## Rows

I instrument, C control, A answer. An answer row's `fail` is a measured
"no"; an instrument's or a control's is the spike failing.

| Rows | Mode | What |
|---|---|---|
| B0 I | — | the shader and the probe built (scored in every run) |
| W0 I, W1 A, W2–W3 C, W4a–c A, W5–W6 C | `well` | the live well classified; M, the overlay's marks (selected vs unselected); the quadrant classifier; three techniques scored (i) quadrants 4/4, (ii) ≥ 99 % of M-core within 3/255, (iii) nothing changed outside the well ∪ M+2, (iv) tree restored and the next capture byte-identical; the two controls that make (ii) and (iv) fail |
| S0 I, S1a–c A, S2a–c A, S3 C | `sheets` | File ▸ Export…, Track ▸ Remove Track, File ▸ Add Media… through `performActionForItem(at:)` then `NSApp.sendAction`; the sheet captured and closed; the parent's capture does not hold the sheet |
| S4 C | `modal` | a probe item running `NSAlert().runModal()`: the call blocks and the main queue is serviced inside it |
| I1–I3 I, I4 C | `menu` + `inventory.py` | the inventory against `buildMainMenu()`'s leaves and the site grep; the checker's own control |
| A0 I, A1–A2 C, A3–A6 A, A7 C | `appearance` | fresh windows (the harness's method) against a live window switched and restored, `window.appearance` and `contentView.appearance` |
| L1–L2 C, L3 A, L4–L5 C, L6–L7 A | `layout` | `hasAmbiguousLayout` on controls and the editor tree; the truncation heuristic on controls, a wrapping label and #70's note |

## Output and exit

One line per row, `<ID> <pass|fail|skip> <I|C|A> — <reason with the
numbers>`, the Q2(c) menu table, `scores: …`, `digest: <sha256 of the sorted
"ID=state\n" lines>`. Exit `0`: every row has a state and no instrument or
control row failed; `1`: one did; `2`: a row has no state
(`SPIKE INCOMPLETE: <ids>`).

`work/capture_spike/` is untracked: `probe/` (the binary, its `main.swift`,
the resources, the `sources.txt` stamp), `fixtures/{well,note}.reelcut`
(written every run at format version 10), `png/<mode>/*.png` (every capture a
row read) and `answers.json` (host, build, rows with their measurements, the
inventory table, the digest).

## What it never does

It never uses `screencapture` or ScreenCaptureKit (spec §11 V-3), never
launches Reelcut.app or an MCP server, never changes anything under `app/`,
`core/` or the build, and never kills a process it did not start: every child
runs in its own process group under `graphics_spike/bounded.py` and only that
group is killed on expiry (the build 1200 s, a mode 180 s, `modal` 60 s). It
performs no AppKit-owned action (Open…, Save As…, Revert, Close, Quit): those
are `framework` rows, read and not run.
