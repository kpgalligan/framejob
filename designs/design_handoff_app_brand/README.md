# Handoff: the Frame Job wordmark in the app

A brief for a Claude Code session in this repository. It brings the Boppa Llewyn product wordmark into the app itself, where the brand appears today: the Welcome window's lockup and the About panel. Everything here follows this repository's own rules; where this brief and a `CLAUDE.md` disagree, the `CLAUDE.md` wins.

## What changes

- **Welcome window.** The lockup keeps the drawn mark (`BrandMark`, 88 pt) and swaps the "Frame Job" label, Darker Grotesque Black at 52 pt, for the **product wordmark**. That's "Frame Job" in outlined Geist 650 at −0.04em, with the icon's coral playhead standing between the words, drawn at a 44 pt font size. The rest of the window doesn't move.
- **About panel.** The copyright line reads "Copyright © 2026 Boppa Llewyn." It's empty today. The panel keeps the drawn mark as its icon.

Nothing else changes. The mark, the app icon, the chrome's fonts and colours, and `DS.display` (the recorder's countdown still uses it) stay as they are.

The website (boppallewyn.com) and the documentation site's handoff (`designs/design_handoff_docs_theme/`) use the same wordmark artwork, so all three match.

## Before you start

- **Record the decision first.** CLAUDE.md requires a phase that needs a new decision to record it in `designs/spec/11-decisions/` before the code. Spec §11 NM-11 says "the wordmark reads 'Frame Job'". This change keeps those words but draws them as the product wordmark instead of a typeset label, so add a decision beside NM-11 that says so and cites this folder.
- **Read `app/CLAUDE.md`** for the file map, the 600-line cap (400 for a new file), the frozen files and hygiene. `BrandMark.swift` (206 lines) and `WelcomeWindowController.swift` (208 lines) are well under the cap.

## Files in this folder

| File | What it is |
|---|---|
| `frame-job-wordmark.json` | **The data the app draws.** The letters as one compound path and the playhead as a filled path, in the artwork's units: 1000 per em, y growing downward, the baseline at y = 0 (letters at negative y). The viewBox is 4844 × 1140 units with its top at y = −1100. It uses absolute M, L, C and Z commands only. |
| `frame-job-wordmark.svg` | The same artwork as an SVG, for reference and for anything outside the app. Its rendering matches the JSON's pixel for pixel (checked by rasterising both). |
| `ProductWordmark.swift` | **A reference implementation, not compiled.** `WordmarkArtwork` loads and parses the JSON; `ProductWordmarkView` draws it at a font size, reports its baseline, and reads as the name to VoiceOver. Adapt it to this repository's rules and build it. |
| `reference/welcome-after.light.webp`, `.dark.webp` | **The target**, at 2×: the Welcome window's own captures (`docs/site/src/assets/screens/01-welcome.window.*.webp`, the "before") with only the label replaced by the wordmark at its specified size and position. |

## The change, file by file

| File | Change |
|---|---|
| `designs/spec/11-decisions/…` | The new decision beside NM-11 (above), written before any code. |
| `app/Resources/Brand/frame-job-wordmark.json` | New: copied from this folder. |
| `project.yml` | A resources entry for `app/Resources/Brand` (`buildPhase: resources`, as `app/Resources/Fonts` has), and `NSHumanReadableCopyright: "Copyright © 2026 Boppa Llewyn."` in place of the empty string. Run `make project`, never a bare xcodegen. |
| `app/Sources/ProductWordmark.swift` | New: `WordmarkArtwork` and `ProductWordmarkView`, from the reference. |
| `app/Sources/BrandMark.swift` | `BrandLockupView` arranges `BrandMarkView` and a `ProductWordmarkView`, replacing the `NSTextField` (below). `wordSize`, `mockLineHeight` and `wordmarkTopOffset(_:)` go; the class comment is rewritten. `BrandMark` and `BrandMarkView` don't change. |
| `app/CLAUDE.md` | The file map gains `ProductWordmark.swift`. The entry for `BrandMark.swift` says the lockup draws the product wordmark. |
| `designs/screens/01-welcome.md` | The prose says "Frame Job" is set in its wordmark: a heavy sans with a red playhead standing between the two words. |
| `docs/site/src/assets/screens/01-welcome.window.*.webp` | Refreshed through the screen catalog (`python3 tools/proof/screens.py --out <dir>`, then `node docs/site/scripts/import-screens.mjs <dir> --used`), never by hand. |
| `docs/manual-checks.md` | A row: with VoiceOver on, the Welcome window's lockup reads "Frame Job" once, as text, not as an image. |
| `CLAUDE.md` | A "Where to look" row for this folder, as the other handoffs have. |

## The lockup

`BrandLockupView` stays a vertical, centred `NSStackView`:

1. `BrandMarkView(size: 88)`, unchanged.
2. `ProductWordmarkView(artwork:name:fontSize:textColor:)` with the artwork loaded from `frame-job-wordmark`, `name: "Frame Job"`, `fontSize: 44` and `textColor: DS.textStrong`.

| Measure | Value | Why |
|---|---|---|
| Font size | 44 pt | Caps 31.2 pt tall (0.71em) and 213 pt wide: the old label's size (caps 29 pt, 206 pt wide in the capture), so the window's layout holds. |
| View size | 213.1 × 50.2 pt | 4844 × 1140 units at 0.044 pt per unit. |
| Baseline | 48.4 pt below the view's top | 1100 units. `ProductWordmarkView` reports it as `firstBaselineOffsetFromTop`. |
| Mark to wordmark | the wordmark's cap line 36 pt below the mark's ink, as now | The stack spacing that gives it is about 9 pt: 36, less the mark view's 9.6 pt inset below its ink (90 of the design box's 824 units at 88 pt), less the wordmark view's 17.2 pt above its caps (390 units at 44 pt). Set it from those named quantities, not as a bare 9, as `wordmarkTopOffset` did. |
| Clear space | 38 pt (`clearSpace`), unchanged | The Welcome column keeps its spacing after the lockup. |
| Colours | letters `DS.textStrong`; playhead `DS.coral` (`#f4653f`) | The letters follow the appearance; the playhead is brand coral in both. |

- **Fallback.** If the artwork fails to load, show the name as before in an `NSTextField` (`DS.display(52)` at −0.015em). A missing resource is a build mistake, so also `assertionFailure` in Debug.
- **Accessibility.** The mark stays hidden from accessibility, as now. The wordmark view is one static-text element whose label and value are "Frame Job". VoiceOver reads the name once.
- **Window.** It stays 720 × 600; the lockup is no taller than it was.

## How `ProductWordmarkView` draws

- It parses the JSON once into two `NSBezierPath`s, in units.
- `isFlipped` is true, because the data is y-down as the SVG writes it.
- It draws with one matrix: x' = s·x, y' = s·y + 1100·s, where s = font size ÷ 1000. The letters fill with the text colour and the playhead fills with coral. Doctored's pulse is a stroke, so the same view strokes a motif whose `mode` is `stroke`, at `lineWidth × s` with round caps and joins.
- Its intrinsic size is the viewBox times s, and it redraws on `viewDidChangeEffectiveAppearance`.
- The letters use the nonzero winding rule. The glyphs overlap at −0.04em tracking, and nonzero fills the overlaps; even-odd would punch holes.
- No blend modes and no hairlines, the same rules as `BrandMark`.

## Checking it

- In the loop: `make typecheck` (exactly its four baseline warnings), then `make app-debug`.
- Drive the Debug app: `python3 tools/proof/proof_app.py launch`, `perform_menu_item` to put the Welcome window up if it isn't, and `snapshot_ui` on Welcome in light and dark (`-RCDevAppearance light|dark` at launch). Compare each capture with `reference/welcome-after.*.webp` at 2×. The wordmark's caps, width and position should match, and nothing else in the window should move against the "before" captures. Check that `grep "Frame Job: " <dir>/framejob.log` prints nothing.
- Then `python3 tools/proof/screens.py` for the Welcome screen, and refresh the docs site's captures from it.
- Once, when the code is complete: `make gate`.
- The manual check above, by a person with VoiceOver.

## Out of scope

- The app icon and the drawn mark.
- The editor's chrome, its fonts and its colours.
- The documentation site and the website, which have their own handoffs.
