# The capture spike — road map 11, V1 (2026-09-26)

Four questions V2's `snapshot_ui` and `perform_menu_item` cannot be designed
without, and the instrument that measures them. **The answers are not here**:
they are in `archive/reelcut-roadmap-11.md`'s V1 record (condensed in
`designs/adr/roadmap-11-dev-tools.md`), which also lists
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
| `inventory.py` | the site grep over `app/Sources`, the I1–I4 checks, the printed menu table; `--check` (a line of `make test`, no app) runs I2 and I3 over the tree as K1 with four CONTROLs, K2 (three lines put above every file holding a site or cited by an anchor), K3 (one rewritten site blanked), K4 (a site moved into a new `func b13Swap` at the file's end: the swap is reported) and K5 (one anchor given an invisible U+2063: reported) |
| `inventory.json` | the hand-read inventory: every live menu selector's verdict (`none`, `sheet`, `window`, `modal`, `framework`) with the lines that present, and every grep site, with its enclosing `func`, traced to the selectors that reach it — `reached_from` (inside the action), `reached_after` (a completion, an async hop or a delegate callback, with its `via` and `gate`). Every citation is a SITE ref, `app/Sources/<F>.swift:<N>` naming a key of `sites`, or an ANCHORED ref, ``app/Sources/<F>.swift `<anchor>` ``, whose anchor is a piece of the line meant (a method's declaration, `func name(`, for a method) occurring exactly once in `<F>`; `baseline` is the tree (`git rev-parse HEAD^{tree}`) it was last read against |
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
| I1–I3 I, I4 C | `menu` + `inventory.py` | the inventory against `buildMainMenu()`'s leaves and the site grep; the checker's own control. A site is found by its token and its enclosing function, not its line (#166, #168): `resolve` pairs the inventory's sites with the grep's per (file, token, func), in line order, when the two counts agree; a cited site is read at its resolved line and an anchored citation at the one line holding its anchor, and every citation in `code`, `note`, `via`, `gate` and `other_caller` is checked for content |
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

## Runs

**B58, 2026-10-01**, over HEAD `69fa216` with the three bare run-loop waits
(`probe_sheets.swift` :160 and :185, `probe_well.swift` :132) changed to
`ProbeSupport.pump()`, run once as
`perl -e 'alarm shift; exec @ARGV' 2700 python3 tools/proof/capture_spike/capture_spike.py --rebuild`
from an agent's shell (the terminal was not known to be frontmost). It took
about 3 minutes, and the probe build took 102 s.

```
host: macOS 26.5.1 (25F80), Mac14,6, console locked False
scores: 18 pass, 6 fail, 14 skip of 38
digest: db2236a5a71c6c23fe4d14ca14434a718afc2811507e39ebc6210748190f942e
mode seconds: layout 4.5, well 7.2, sheets 23.7, modal 2.1, menu 0.1, appearance 48.6
```

Exit 1. V1's last run was 33 pass, 5 fail (W4a, W4b, W4c, S2c, L3) and
0 skip of 38, with digest `3a35537e…d8587`. These rows changed state:

| Row | V1 | B58 | Printed reason |
|---|---|---|---|
| S1a, S1b, S1c, S2a, S2b | pass | skip | `host: probe not active` |
| S2c | fail | skip | `host: probe not active` |
| S3 | pass | skip | `host: probe not active` |
| A1–A7 | pass | skip | `host: probe not active` |
| I4 | pass | **fail** (C) | `removed addActionAtPlayhead: and app/Sources/AppDelegate.swift:121; the checker reported [('I1', 'addActionAtPlayhead:'), ('I2', 'app/Sources/AppDelegate.swift:121'), ('I3', 'terminate:')]` |
| L7 | pass | fail (A) | `note intrinsic 194.5 vs frame 271; 0 visible field(s) wider than their frame:` |

S0 printed `active False in None ms, key False, main False`, and A0 printed
`active False in None ms, key False`. The probe never became the active app,
so the rows that need activation did not answer, and this run does not show
whether `pump()` fixes activation (#132). I1–I3 passed: `I2 pass I — 0
problem(s); 46 sites: beginSheetModal 25, popUp 2, presentAsSheet 8,
presentError 5, runModal 6`.

I4 was a control failure, and the checker was not at fault. `i4` removed
the first site in sorted order, `app/Sources/AppDelegate.swift:121`, and
expected exactly one I1 report and one I2 report. But `terminate:`'s `note`
cites that same site by its SITE ref (added in `c5504fe`, after V1's run), so
I3 also reported, correctly, that the citation now dangled.

**The I rows brought up to the grown inventory, 2026-10-01.** `i4` now
removes the first site in sorted order that no `code`, `note`, `via`, `gate`
or `other_caller` cites by its line. Only the I family was re-run, by driving
the built probe's `menu` mode through `capture_spike.run_mode` (its 180 s
bound) and `inventory.run` over its leaves. No other mode ran,
`answers.json` was not rewritten, and the scores and digest above are still
this run's.

| Row | Before | After |
|---|---|---|
| I1 | pass — `0 problem(s); 147 leaves, 95 live selectors, 95 rows` | the same |
| I2 | pass — `0 problem(s); 46 sites: beginSheetModal 25, popUp 2, presentAsSheet 8, presentError 5, runModal 6` | the same |
| I3 | pass — `0 problem(s); verdicts framework 16, modal 2, none 57, sheet 15, window 5` | the same |
| I4 | fail C — `removed addActionAtPlayhead: and app/Sources/AppDelegate.swift:121; the checker reported [('I1', 'addActionAtPlayhead:'), ('I2', 'app/Sources/AppDelegate.swift:121'), ('I3', 'terminate:')]` | pass C — `removed addActionAtPlayhead: and app/Sources/CaptionExporter.swift:534; the checker reported [('I1', 'addActionAtPlayhead:'), ('I2', 'app/Sources/CaptionExporter.swift:534')]` |

After the change, `inventory.py --check` prints 5/5 and exits 0.

**#132's foreground run, 2026-10-02**, over HEAD `7faf625`, run once as
`perl -e 'alarm shift; exec @ARGV' 900 python3 tools/proof/capture_spike/capture_spike.py --rebuild`
from the agent's shell, with the owner away from the Mac, the display on and
the terminal running the agent session left in front.

```
host: macOS 26.5.1 (25F80), Mac14,6, console locked False
scores: 19 pass, 5 fail, 14 skip of 38
digest: 087f333be1afc9b66b9cdc0af5ec51df60fe1301dc2e581e2d3bd2cb97d15337
mode seconds: layout 4.5, well 7.1, sheets 23.8, modal 2.1, menu 0.1, appearance 48.4
```

The runner exited 0. The fails are W4a, W4b, W4c, L3 and L7, the same rows
for the same reasons as B58's run. I4 now passes in a full run. S1a–S3 and
A1–A7 still skip with `host: probe not active`: S0 printed `active False in
None ms, key False, main False`, and A0 printed `active False in None ms,
key False`. **So nobody at the machine is not enough, and `pump()` does not
fix activation.** `ProbeSupport.activate` calls `NSApp.activate()` and polls
for 3 s, and the probe never became the active app. One explanation fits but
is unmeasured: since macOS 14, `NSApp.activate()` is a request that the
frontmost app must yield to (`yieldActivation`), and a child process of a
terminal's shell is not handed activation the way V1's runs were.
