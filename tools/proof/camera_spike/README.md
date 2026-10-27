# The camera-recording spike — road map "camera-recording", CR0

What the road map measures before any camera code is written: the device and format lists
(with and without the Continuity Camera key), the camera grant (the responsible process of a
shell-launched binary, the hardened runtime with and without `com.apple.security.device.camera`),
camera capture to a file through `AVCaptureMovieFileOutput` and through `AVAssetWriter`, the
microphone as a second file and its offset, the camera beside a running `SCStream` recording and
the screen file's start estimators, pause as a file sequence, the live preview's cost, the
virtual cameras, and what a proof can measure without a person. **The answers are not here**:
they are in `archive/camera-recording.md`'s "CR0 — the spike" record (the rows and the VERDICT
line). The rule the run is judged by is spec §11 CAM-2
(`designs/spec/11-decisions/camera-recording.md`), fixed before the run; `results.json` stores
that file's SHA-256 as `rule_sha256`, so the rule a recorded run read is pinned. What is here is
how to run it again.

```sh
python3 tools/proof/camera_spike/camera_spike.py --selftest                              # S1–S5; no build, no camera
python3 tools/proof/camera_spike/camera_spike.py --selftest --mutant writer-frames-off    # must exit 1 (S1)
python3 tools/proof/camera_spike/camera_spike.py --selftest --mutant estimator-wide       # must exit 1 (S2)
python3 tools/proof/camera_spike/camera_spike.py --selftest --mutant decode-swap          # must exit 1 (S3)
python3 tools/proof/camera_spike/camera_spike.py --selftest --mutant skip-as-fail         # must exit 1 (S4)
python3 tools/proof/camera_spike/camera_spike.py --selftest --mutant continuity-inverted  # must exit 1 (S5)
python3 tools/proof/camera_spike/camera_spike.py --ask      # once, from the terminal that will run it: asks Camera and Microphone
python3 tools/proof/camera_spike/camera_spike.py            # every group but aimed
python3 tools/proof/camera_spike/camera_spike.py --groups write,pause --runs 5 --camera FaceTime
python3 tools/proof/camera_spike/camera_spike.py --groups write,pause --camera FaceTime --format 1760x1328   # CR1a: D3 = that size
python3 tools/proof/camera_spike/camera_spike.py --aimed    # adds A1: a person points the camera at the screen
```

The probe links the core's staticlib (`swift_build.build` always does), so `make rust` comes
first; without `core/target/release/libframejob_core.a` the runner prints `NOT PERFORMED` and
exits **2**. A whole run takes a few minutes: W, M and P each run `--runs` times (default 3), the
screen group 2 runs per order per camera path, and the preview group 30 s per format.

**Exit codes.** **0**: every requested row answered or skipped by name, whatever the VERDICT.
**1**: an instrument check failed — B0 (a probe build or a codesign), a probe crash or expiry, an
`analyze` read that failed, the counter unreadable in a screen file's first 12 frames, or a
selftest row (so a mutant caught under `--mutant` exits 1). **2**: not performed. A skipped row
(no grant, no camera, no microphone matching `--mic`, no person) is never a failure.

**Grants.** A bare binary has no TCC identity of its own: its grant is its RESPONSIBLE
process's, the terminal that launched it (road map 3 R0 q1; T1 names it). No path asks for a
grant but `--ask`, which calls `AVCaptureDevice.requestAccess` for video and audio once each,
bounded at 60 s; nothing ever asks for Screen Recording (`CGPreflightScreenCaptureAccess()` is
read before any ScreenCaptureKit call, and a mode without it answers `skipped`). The camera and
microphone statuses are read before any `AVCaptureDeviceInput` exists, because that initializer
prompts on its own.

## The instruments

| File | What it is |
|---|---|
| `camera_spike.py` | the runner: the build (B0) and the hardened copies, the groups in order, the deciders for CAM-2 as pure functions, the counter decode, Q0, the table, the VERDICT, `results.json`, the selftest and its mutants |
| `camera_spike_probe.swift` | compiled AS `main.swift` through `swift_build.build` with NOTHING from `app/Sources` (every type `Spike…`, every function `spike…`, so `swift_build.py typecheck` beside the app's files has no clash); `camera-spike-probe <mode> <work-dir> <job.json>` prints one JSON line |

**The probe** is built twice with `-sectcreate __TEXT __info_plist` (`recording_probe.py`'s
`build_voice_probe` line without the app sources): `camera-spike-probe`, whose plist has
`NSCameraUsageDescription`, `NSMicrophoneUsageDescription` and
`NSCameraUseContinuityCameraDeviceType` true, and `camera-spike-probe-nokey` without the
Continuity key. Two hardened copies of the first are signed `codesign --force --sign - -o
runtime`, one with an entitlements plist holding `com.apple.security.device.camera`
(`build/hardened-ent/`), one without (`build/hardened-noent/`). Its modes:

- `devices` — `AVCaptureDevice.DiscoverySession` over `.builtInWideAngleCamera`, `.external` and
  (job `continuity`) `.continuityCamera`; per device its identity, type, transport, state, active
  format and every format (subtype, dimensions, rate ranges, `supportedColorSpaces`);
  `systemPreferredCamera`; the microphones.
- `grant` — the responsible process (`responsibility_get_pid_responsible_for_pid` through
  `dlsym`), the video and audio status, `CGPreflightScreenCaptureAccess()`; `"ask": true` asks.
- `session` — 2 s of an `AVCaptureVideoDataOutput` (BGRA): frames delivered and each one's mean
  Rec. 709 luma.
- `write` — `AVCaptureMovieFileOutput` (HEVC set on its connection when an `AVAssetWriter` can
  apply HEVC at the format, else H.264: `availableVideoCodecTypes` is unavailable on macOS) or an
  `AVAssetWriter` fed by an `AVCaptureVideoDataOutput` (`420v`), its session started at the first
  buffer's PTS; at a format index and with both frame durations locked to its maximum rate when
  asked. A requested format is held under the device's configuration lock from building the
  session to stopping it: macOS has no `.inputPriority` preset, and without the lock a movie
  output's `startRecording` re-takes the device's format. It reports the call-to-did-start time, `startPTS` and its host conversion
  (`CMSyncConvertTime` from `synchronizationClock`), the read-back frame durations mid-recording,
  drops, the codec asked, the process CPU and the bytes.
- `mic` — M1 (one session: camera, microphone, a movie output with its audio connection off, an
  `AVCaptureAudioFileOutput`, `canAddOutput` reported) or M2 (the camera session plus today's
  separate microphone session); both started in one turn; the offset by host `startPTS` and by
  callback arrival.
- `screen` — a 128-point counter window (a 4 × 4 block code: 8 bits MSB first, then their
  complement; redrawn on every callback of `NSView.displayLink(target:selector:)`, each code
  logged with that callback's `targetTimestamp`), the camera (movie output at the default
  format, or the writer at D3's format locked) and an `SCStream` on the main display at 60 fps
  with an `SCRecordingOutput` and a `.screen` output (its frames' PTS, arrival and status), the
  two started in one run-loop turn in the job's order; E1 is `recordingOutputDidStartRecording`'s
  arrival.
- `pause` — 3 segments of 2 s with 1.5 s pauses: P1 `stopRecording` and a new
  `startRecording(to:)` on the running session; P2 the writer finished and a new one started at
  the next buffer; the microphone (M2's shape) paused the same way when granted and present.
- `preview` — 10 s each of a running session with no output, then plus an
  `AVCaptureVideoPreviewLayer` in a 320 × 180 window, then plus a movie output recording: process
  CPU %, RSS, and the CPU % of every process whose name contains "camera" (`cameracaptured`) from
  a bounded `ps`.
- `virtual` — the cameras whose transport is `virt` or whose name says "Virtual", whether each
  delivers frames (camera grant needed), and whether an OBS process runs.
- `aimed` — a full-screen window flashes black to white while `afplay` plays a 1 kHz tone, with
  the camera, the microphone and the screen recording.
- `analyze` — `AVAssetReader` (no ffmpeg): frames and every PTS (compressed samples), the
  nominal rate, the codec, dimensions, transform, colour primaries/transfer/matrix; for the first
  12 frames the mean luma of each rect in `blocks`; with `allLuma` every frame's mean luma; for
  an audio track its format, span and (with `audioOnset`) the first sample at |x| ≥ 0.1.

**The runner** works in `tools/proof/work/camera-spike/` (untracked): `build/`, `recordings/`
(every file captured), `answers/` (each probe's job, answer and stderr) and `results.json`.
Every child runs under `graphics_spike/bounded.py` in its own process group: the build 900 s, a
capture mode 120 s, `analyze` 60 s. `--camera` picks a device by name or unique id (default: the
built-in wide-angle, non-Continuity device named "FaceTime", else the first); `--mic` by name
(default `"MacBook"`: a Bluetooth input switches profiles and poisons the file, R0's lesson). A
camera group asked without `devices` runs `devices` first (the camera and D3 come from D1).
`--format WxH` (CR1a, spec §11 CAM-3's step 2) sets D3 to the chosen camera's first format of
that size whose maximum rate is ≥ 30, so W2, W3, P1 and P2 run there rather than at CAM-2's
best; `results.json` records it as `formatOverride` (`{asked, index}`, null without the flag),
D3's row still lists CAM-2's picks, and a size the camera lacks prints `NOT PERFORMED` and exits
**2** once D1 has listed it. The selftest is unchanged.

## The rows

H0 the host (model, macOS build, load, power, any Frame Job running) at the start and after each
group; B0 the builds and the hardened copies' flags; D1 discovery with the key; D2 with the
no-key build, with and without `.continuityCamera` (a refusal of the first is recorded as its
answer); D3 each device's best format by CAM-2; T1 the responsible process and the statuses; T2
and T3 the session on the hardened copy without and with the entitlement; W1 the movie output at
the default format, W2 at D3's format locked, W3 the writer on W2's configuration — per run the
frames against span × rate (span = last − first PTS + one frame, rate the locked or read-back
maximum), the nominal and average rate, the start time, `startPTS` and its host conversion, drops,
bytes/s, the codec and its colour tags and transform, CPU, the read-back frame durations and
format (a W2 run whose format read back while recording is not D3's is marked `offFormat` and is
not CAM-2 evidence; P1's runs likewise, by each segment's read-back); M1, M2
the microphone offsets; S1 (camera first), S2 (stream first) — per run the truth (the logged
`targetTimestamp` of the first readable code in the screen file's first 12 frames, less that
frame's offset from the first), E1 and E2 (the first `.screen` frame's PTS at or after E1;
`e2_arrival` the first arriving at or after E1, reported) against it, camera − screen by
`startPTS` and by callbacks, each file's frames and rate; P1, P2 per segment the start and close
latency, `startPTS`, file span − segment span, the microphone's offset, the data output's rate
through the pauses; V1 the preview's cost at the default and D3's format; X1 the virtual cameras;
A1 the aimed offsets; Q0 what each row needs (nothing, Screen Recording, a grant, a camera, a
person) and what this run did. Then the table and the VERDICT line (stderr's last line):
`VERDICT writer=… screen_start=… continuity_key=… camera_entitlement=… best_format=…`, or
`VERDICT NOT MEASURED: <reason>` when every `write` row was skipped. `writer` reads
`NOT MEASURED` when no W2 run counts (none ran, or every one was off-format), and `screen_start`
reads `unmeasured` when no S run was made.

**`--selftest`** (no build, no camera): S1 the writer rule — clauses (a)–(d) each pick the writer,
(d) under one frame does not, neither path at 98 % is STOP; S2 the screen-start rule at 16.6 and
16.8 ms, and STOP; S3 the counter: all 256 codes round-trip (full and video range), the 0x0F/0x10
frame torn at row 2 reads unreadable, every n/n+1 tear at any row reads unreadable or exactly
the code its pixels show, a grey block reads unreadable; S4 a skipped row scores 0, a failed one
1; S5 the Continuity key (`unmeasured` with no Continuity Camera in D1, `needed`, `not-needed`)
and the entitlement (`unmeasured` when T3 has no frame or T2 and T3 are both black, `needed`,
`not-needed`). The mutants: `writer-frames-off` (clause (a) ignored: S1), `estimator-wide` (the
tolerance 50 ms: S2), `decode-swap` (the block bit order reversed: S3), `skip-as-fail` (a skipped
row scores as failed: S4), `continuity-inverted` (needed and not-needed swapped: S5).
