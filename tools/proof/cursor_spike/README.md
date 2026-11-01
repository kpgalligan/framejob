# The cursor spikes — road map "creator-jobs", CU0b

What the road map measures before any cursor code is written:
- **CU-S1:** the capture APIs, the grants, the event clock and the cursor's image.
- **CU-S2:** the mapping from global points to movie pixels, and the time anchor.
- **CU-S3:** whether ScreenCaptureKit's dirty rects locate typing.
- **CU-S4:** the cursor file's size and speed, measured on a reader prototype.

**The answers are not here.** They are in `designs/creator-jobs.md`'s "CU0b's record" (the VERDICT lines and the rows) and in spec §11 CU-6's "Settled at CU0b" line. Each rule is the road map's own entry under "Every spike, with its rule", fixed at CJ0a. R0 hashes each entry by CJ-7's definition: the line `- **<ID> —` and every following line that begins with two spaces. It compares the hash with CJ0a's pinned value (`deciders.PINNED`) and refuses to run a changed rule (`RULE CHANGED <id>`, exit 1, nothing written). Each `results.json` stores its value as `rule_sha256`. What is here is how to run them again.

```sh
python3 tools/proof/cursor_spike/cursor_spike.py --selftest                     # R0, S1a–S4a, T1, R4a; builds only the reader
python3 tools/proof/cursor_spike/cursor_spike.py --selftest --mutant body-or    # each of the ten must exit 1
python3 tools/proof/cursor_spike/cursor_spike.py --build-only                   # R0 and B0
python3 tools/proof/cursor_spike/cursor_spike.py --only s4                      # one group; each fits 600 s
python3 tools/proof/cursor_spike/cursor_spike.py --only s1,s2,s3                # the auto and posted tiers
python3 tools/proof/cursor_spike/cursor_spike.py --only s1,s2 --person          # the person tier (JOB-29), merged in
```

The mutants are `rule-unchecked`, `clicks-95`, `keys-accessibility-ok`, `grant-iohid-first`, `skipped-as-measured`, `inherited-grant-counted`, `caret-unflipped`, `odd-window-ignored`, `dirty-128` and `body-or`. Each is switched in-process through `deciders.MUTANT`.

**The runs touch the machine.** They warp the pointer (restoring it after each row), show full-screen grey windows above everything (`.statusBar + 1`), open small helper windows, and set the instrument's own cursor. Keep your hands off the mouse and keyboard, except where the person tier asks for them. Frame Job itself is never launched.

**Exit codes.**
- **0:** every requested row was answered or skipped by name, whatever the verdict.
- **1:** an instrument failure. That is B0 (a build, the bundle's codesign or the reader), a probe crash or expiry, a still frame with fewer red pixels than half the crosshair's (or Separate's marker's) expected count, R4a's bodies disagreeing, a selftest row (so a mutant caught under `--mutant` exits 1), or `RULE CHANGED`.
- **2:** not performed: `core/target/release/libframejob_core.a` or `build/codecs/stamp.json` is missing (`swift_build.build` links both).

A skipped row is never a failure. A row skipped before its field's value is settled makes that field `owed`. A row the rule makes conditional and the host lacks, such as a second display, is `absent`, which is not a skip.

## The tiers

- **auto:**
  - A4: the poll's cost over 10,000 calls, and ten warps read back.
  - A5: `NSCursor.currentSystem` over the probe's own cursors, with its cost and nils. A second process calls it from a background queue: the safe thread, where a crash is the answer.
  - A9: a helper's `NSCursor.hide()` on a shared wall-clock schedule.
  - A10: two 64 × 64 pt streams around the pointer, differenced, and their IoU against the cursor's image.
  - CU-S2's source rows and its ten still starts.
  - CU-S3's ten bursts.
  - CU-S4.
- **posted:** A1–A3, A6 and A7. They run only when `CGPreflightPostEventAccess()` is true in the terminal-run poster (`post` mode); otherwise each is skipped by name. The listener is always the scratch bundle (`listen` mode), never a terminal-run process: a terminal-run listener holds the terminal's grants, not its own.
  - The bundle reports its own grants first. A row whose grant differs from the one it tests is skipped as `scratch bundle holds <grant>`, because TCC is reset only under `--person`. A7 (a key tap under secure input) runs only when the bundle holds Input Monitoring, since a key tap sees no keys without it.
  - The listener bundle is opened before the poster runs, and its answer's `ready_wall` must precede the plan's `start_wall`, or the row is an instrument failure. A poster answering `skipped` skips the row by name.
  - The truth is each window's own count of the events it received. Half go to the bundle's window (the rule's "Frame Job's own windows"), half to a `target` helper's.
- **person** (`--person`: prompts on stderr, waits on Return, and merges its rows into the existing `results.json`):
  - A4's real moves.
  - A5 over TextEdit text, a Safari link and a resize edge.
  - A9 with TextEdit's hide-until-moved.
  - A1–A3 by hand, three times: with no grant, with Input Monitoring only, and with Accessibility only.
  - A8 and A11: each grant pair from a clean state. Before each pair the runner runs `tccutil reset ListenEvent com.kgalligan.FrameJob.cursorspike`, the only `tccutil` call, on that id only. The owner answers y/n for "prompt shown" and "listed in the pane"; the runner opens `Privacy_ListenEvent`. The key count window opens on a go file the runner writes when the owner presses Return to start typing (or on the grant, if that comes later), not when the grant alone is detected: the tap made before the grant and the one made after it then count keys side by side over the same 8 s.
  - CU-S2's picked window, through `SCContentSharingPicker`.

**A locked console.** The `host` mode reads `CGSessionScreenIsLocked`. While the console is locked, every row that needs the screen or an active window is skipped by name. ScreenCaptureKit then records the lock screen, with no window and no menu bar, and nothing activates. CU0b's first runs, made before this check existed, measured the lock screen's animated wallpaper: every frame was dirty edge to edge. The probe's In the picture rows are skipped as `probe not active` when the probe cannot activate within 2 s. Separate's rows do not need it.

**Grants.** No mode asks for a grant except `grant`, which runs only under `--person`. The other modes only read them: `CGPreflightScreenCaptureAccess`, `CGPreflightPostEventAccess`, `CGPreflightListenEventAccess`, `AXIsProcessTrusted` (no prompt option) and `IOHIDCheckAccess`. Every ScreenCaptureKit mode reads Screen Recording first and answers `skipped` without it.

## The instruments

| File | What it is |
|---|---|
| `cursor_spike.py` | the runner: R0, the host facts, B0 (the probe, the scratch bundle and the reader), the groups `s1`–`s4`, the person tier, the CU-S2 errors (each mapping's tip error over still frames; each anchor's time error over moving frames, from the movie decoded to BGRA), the red floor, `results.json`, the VERDICT lines, the selftest and its mutants |
| `deciders.py` | pure, importing nothing from the runner: `PINNED`, `rule_sha256`, `FIELD_ROWS` (each field's rows in the rule's order), `decide_s1`…`decide_s4`, `dirty_centre_pt` and `caret_centre_pt` (CU-S3's two coordinate frames), `verdict_line` |
| `cursor_spike_probe.swift` | compiled AS `main.swift` with `cursor_spike_capture.swift` through `swift_build.build` (optimized), with a `-sectcreate __TEXT __info_plist` plist and nothing from `app/Sources`; every type is `CursorSpike…` and every function `cursorSpike…`. Modes: `host`, `a4`, `a5`, `a5thread`, `a9`, `target`, `post`, `listen`, `grant`. `cursor-spike-probe <mode> <work-dir> <job.json>` prints one JSON line |
| `cursor_spike_capture.swift` | the ScreenCaptureKit modes `a10`, `s2`, `still` and `s3` |
| `reader/` | CU-S4's scratch crate (its own `[workspace]`): `cursor-spike-reader generate --out DIR` writes `worst.json` and `worst.bin`; `measure --body json\|binary --file F --runs 5` prints `bytes`, `parse_ms[]`, `state_us_raw_median`, `state_us_prepared_median` and `prepare_ms[]`; `selftest --dir DIR` is R4a |

**The scratch bundle** is `tools/proof/work/cursor_spike/bundle/Cursor Spike.app` (`com.kgalligan.FrameJob.cursorspike`). Its executable is the probe. It is signed `codesign --force --sign - -o runtime` and opened with `open -n -a … --args <job.json>`. With one `.json` argument the probe takes its mode from the job's `mode` (`listen` or `grant`) and writes its one answer to the job's `out` path, which the runner waits on with a bound: stdout does not reach the runner through `open`.

**CU-S2.**
- **In the picture:** the probe sets its own crosshair cursor, a pure-red 3 × 3 pt centre at the hot spot (7.5, 7.5) of a 15 × 15 pt image, after each warp. The tip is the red centroid (R ≥ 200, G ≤ 60, B ≤ 60) inside a ±64 pt window of each complete frame, converted to BGRA.
- **Separate** (`showsCursor` off, `showMouseClicks` off, 420v): the truth is a 24 pt red marker moved to each warped point.
- **The rows:** eight still holds per row; the moved window moves and shrinks after the fourth. Then a 400 pt/s horizontal sweep, warped at 120 Hz, is recorded with `SCRecordingOutput`. A ticker in a corner keeps the frames complete.
- **The mappings:** M1, M2 and M3 are computed in `cursor_spike.py` from each frame's `SCStreamFrameInfo` (`screenRect`, `contentRect`, `contentScale`, `scaleFactor`) and the shareable content's frame.
- **The anchors:** E1 is `recordingOutputDidStartRecording`'s arrival, E2 the first complete frame's PTS at or after E1, and DisplayTime the first complete frame's `displayTime`. Each is checked on the decoded movie through the row's best mapping, as position error ÷ speed.
- **The still start:** a full-screen flip after 2 s of pointer motion over a still screen (Separate). The error is the flip's movie time plus each anchor, less the flip's logged host time.

**CU-S3.** A display stream at 2× over the probe's `NSTextView`, with a spinning `NSProgressIndicator` and a `CABasicAnimation` as distractors. There are ten bursts of 12 characters, each at a different line and column. Each frame's bounding box is the union of that frame's `dirtyRects` (pixels). A burst's median box centre and its caret's `firstRect` are converted by `deciders.py` alone and compared against 64 pt. The flags `distractors`, `color_space` and `cover` exist for diagnosis; the rule's run never sets them.

**CU-S4.** The worst case is generated with LCG seed 1: 432,000 moves at 120 Hz over an hour, 3,600 clicks (a down and an up each), 20,000 time-only key marks, 40 opaque 4,096-byte images (base64 in the JSON body), 3,600 image changes and one geometry entry.
- **The JSON body** is columnar, with integer µs and points × 100.
- **The binary body** is a magic, the header's length, the JSON header with the array lengths, then twelve little-endian i64 columns and the image blobs.
- **Parse** is bytes in memory → a validated track: equal column lengths, non-decreasing times, ids in range, the caps.
- **Smoothing's prototype:** pins at every down click; iterative Ramer–Douglas–Peucker at 12 pt × smoothing between pins; centripetal Catmull–Rom in time over the kept points. Smoothing 0, and any smoothing not prepared, answer the raw samples linearly interpolated.
- **Queries:** each `state` and `prepare` is a JSON request string answered by a JSON string.
- **Units:** MB is 10^6 bytes.

**`CGCursorIsVisible()`** is imported by Swift as unavailable in the macOS 26.2 SDK, an error rather than the warning the road map expected. The probe reaches it through `dlsym`, records its answer in A9's samples, and never decides `hidden` by it alone.
