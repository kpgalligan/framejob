# Spec §11 — decisions: Dev tools (road map 11)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The road map that made these is closed; its condensed record is
`designs/adr/roadmap-11-dev-tools.md` (the original is `archive/roadmap-11.md`).
V-4 and V-5 come from the build-velocity road map, now closed: `designs/adr/build-velocity.md` (the original is `archive/build-velocity.md`).

- **V-1 — Dev tools are compiled only under `FRAMEJOB_DEV_TOOLS`, and the shipping build is
  the Distribution configuration, which does not set it.** Debug and Release set the flag;
  `make app` builds Release, so every proof and agent session has the tools, and the binary
  that is verified is the optimised one rather than a Debug build that only resembles it. A
  compile-time flag rather than a launch flag, because the user does not want the code shipped
  at all, not merely switched off. `make dist` checks that the tools' names are absent from the
  Distribution binary and present in the Release one, and fails otherwise. The agent server
  itself (§7.9) is a product feature and stays in every build; only the dev tools go. Risk
  accepted: the flag-off path is compiled by `make dist` alone, not by `make typecheck`.
  **Amended by NM-6** (rename R0): `REELCUT_DEV_TOOLS` is now `FRAMEJOB_DEV_TOOLS`.
- **V-2 — A dev tool is not an op and not a user-visible edit, but it is an ordinary tool.** It
  has no UI path to mirror, so the agent-parity rule asks nothing of it; it goes through the same
  catalog, handler table, argument gate and startup parity check as every product tool, merged
  in from `AgentServer+DevTools.swift` so the frozen `AgentServer.swift` takes wiring only.
- **V-3 — Screens are captured with `cacheDisplay(in:to:)`, never ScreenCaptureKit or
  `screencapture`.** No Screen Recording grant — which an ad-hoc-signed rebuild may lose, and
  which the agent's terminal does not have — so a capture never waits on a person. What that
  path cannot draw (the player layer, Metal) is filled from `render_frame`'s picture and the
  result says so; the capture is a picture of the chrome, and pixel claims about the VIDEO stay
  with `render_frame`.
- **V-4 — The edit loop and mutant tiers drive a Debug app; the run a phase records, the gate's
  build and every `release_only` proof are Release.** Amends V-1's 'the binary that is verified
  is the optimised one': `debug_release_proof.py` shows the two answer alike (`tools/list`,
  `get_project` and the catalog snapshot, compared parsed), render byte-for-byte alike, and
  export alike but for the movie header's creation and modification times; Debug is used for its
  rebuild time. Risk accepted: an optimiser-only defect is seen only by the recorded run.
- **V-5 — The Debug build is its own app: "Frame Job Debug", `com.kgalligan.FrameJob.debug`, its
  own defaults domain, and an Alternate handler for `.framejob`, so a double-click opens the real
  Frame Job.** Debug-config settings only (`PRODUCT_BUNDLE_IDENTIFIER`, `RC_APP_NAME`,
  `RC_PROJECT_HANDLER_RANK`, read through `:default=` so Release and Distribution keep identical
  settings and Info.plist bytes). `PRODUCT_NAME` stays `Reelcut` (bundle, executable, module).
  The Application Support folder, its default socket and its keys stay shared; TCC grants are
  per id, so a TCC-dependent proof is Release-only.
  **Amended by NM-3** (rename R0): "Reelcut Debug" is now "Frame Job Debug"
  (`Frame Job Debug.app`, executable `Frame Job Debug`); `com.kgalligan.Reelcut.debug` is now
  `com.kgalligan.FrameJob.debug`; `.reelcut` is now `.framejob`; the real Reelcut is now the
  real Frame Job (`com.kgalligan.FrameJob`); `RC_APP_NAME` is now gone: Debug sets
  `PRODUCT_NAME` to "Frame Job Debug", `CFBundleName` and `CFBundleDisplayName` read
  `$(PRODUCT_NAME)`, and `RC_PROJECT_HANDLER_RANK` stays, read through `:default=`;
  "`PRODUCT_NAME` stays `Reelcut` (bundle, executable, module)" is now `PRODUCT_NAME`
  `Frame Job` in Release and Distribution, the bundle and executable following it in every
  configuration, and the module `FrameJob` in every configuration through `PRODUCT_MODULE_NAME`.
- **#539 — `-RCDevCaptureScale 1|2|3` draws every `snapshot_ui` capture at that many pixels per
  point, whatever screen its window is on.** `DevCaptureScale.forced` is 1, 2 or 3 when the
  instance was launched with one of those and nil otherwise; any other value prints one stderr
  line, `RCDevCaptureScale must be 1, 2 or 3 (got "<raw>"); captures keep the window's scale.`,
  and is ignored. The capture's scale is `forced ?? window.backingScaleFactor`. When it equals the
  window's `backingScaleFactor`, `UISnapshot.pass` keeps `bitmapImageRepForCachingDisplay(in:)`,
  so a 2× host captures exactly as before; otherwise it makes an `NSBitmapImageRep` of that rep's
  format at `round(bounds × scale)` pixels, `size` = `bounds.size`, retagged to its colour space,
  and `cacheDisplay`s into it. In the `snapshot_ui` answer, `scale` and the dump's `scale` are the
  capture's (`width_px == round(points.w × scale)`); `window_facts.scale` and the listing's
  `scale` stay the window's. `screens.py` pins 2 and fails a screen whose capture answers another
  scale, so the catalog and the site's pictures are 2× on a 1× display with no window moved.
  **Accepted:** in a forced capture, a bitmap a view makes at its window's `backingScaleFactor`
  (`ColorWheelControl`'s disc, `CurvePlotDecor.drawHueStrip`) is drawn at the window's scale and
  scaled up; HS-5 is where a person compares the two.
- **#368 — `play_preview {await_start: true}` times the play from the playhead's first move.**
  `play_preview` notes `from`, sets the rate and sleeps `seconds` from that instant, so `to − from`
  is the play less the player's start-up: about 0.5 s on a timeline with sound (#537), and more
  under host load (0.74 s and 0.92 s measured under three lanes' builds, 2026-11-09).
  `missing_audio_proof.py`'s P1 scored `to − from ≥ 900 000` for a 2 s play and so scored that
  start-up, with 0.5 % of margin on an idle host. With `await_start: true` the tool polls the
  playhead after `setRate`, every 10 ms and a main hop each, until it is past `from`; it answers
  that position as `playing_from` and the seconds it took as `start_seconds` (both after
  `wall_seconds`, and only when asked), and sleeps `seconds` from the instant of that read, so
  `to − playing_from` is at least `seconds` of play at the transport's rate whatever the load: a
  late final read only adds ticks. Refused with `seek_to`, before anything moves ("await_start
  cannot be used with seek_to: a seek's two halves are timed from the seek."). A playhead that has
  not moved 30 s after the rate was set (`AgentServer.awaitStartLimit`) pauses the preview, ends
  the trial and is refused: "The preview did not start: its playhead had not moved 30 s after
  play_preview set the rate." Without the argument nothing changes, so every other proof's
  numbers stand. P1 passes `await_start` and scores `to − playing_from ≥ 900 000`, the floor
  unchanged; a preview that never starts is the refusal, and one that plays at half speed after
  starting moves about 600 000 ticks and fails the floor (both seen, by hand mutants in
  `Playback.setRate`).
- **#429 — `-RCDevSaveHold <s>` holds each save of a package after it is written and before it
  is swapped in, so a proof can publish a cache file during one.** Dev tools only
  (`FRAMEJOB_DEV_TOOLS`; Distribution compiles no override). `ProjectDocument+CacheSaves.swift`
  overrides `write(to:ofType:for:originalContentsURL:)`: it calls `super` and then, when the
  launch default is above 0, sleeps the main thread that many seconds. Every save of that
  instance is held (⌘S, autosave, `save_project`), inside the cache ledger's `saveBegan` …
  `saveEnded`. Nothing in the product reads it.
  - **Why there, and not before `super.save`** (where the issue proposed it): a cache file
    written before the save lists `cache/` is carried by that save, so nothing is lost and a
    write outside the ledger could be told only by its time. After the new package is written
    and before the swap is the window the ledger exists for: a file written into the old
    package then goes with it.
  - **What a proof reads.** `CacheLedger.publish` takes an optional `waited` out-parameter, set
    to whether a save of that folder was in flight when the call came. `AnalysisStore.publishFile`
    passes it and, under dev tools, counts the publishes that waited per (cache folder, kind,
    media id); `analysis_job` answers the count as each job row's `save_waits`. So a row says
    that its publish met a save from a fact of that run, not from two clocks.
    *Amended by #552:* the count is the ledger's own, keyed by the writer's name; `waited` and
    the store's count are gone, and `analysis_job`'s `save_waits` reads the ledger's under the
    store's name, `analysis/<kind>/<media>`, meaning what it meant.
  - **Its row.** `analysis_proof.py` A14: a document made and saved on a plain launch is
    opened on a launch of its own (`-RCDevAnalysisHold 3 -RCDevSaveHold 25`, so the row's is
    the one save held); a job over the fixture's first 100 frames is wanted, then
    `save_project`; the row passes when the job landed, its `save_waits` rose by one, the
    marker and `frames.bin` are in the package after the save, and `get_media_analysis` then
    answers `cached: true` with that window's cut. A
    run in which the publish did not meet the save fails by name (`save_waits` unchanged)
    rather than passing having shown nothing. Mutants, each an app build:
    `write-outside-publish-app` (the store writes without the ledger) and `save-not-announced`
    (`saveBegan` not called).
  - **Not covered.** The other writers through `CacheLedger.publish` (the media passes'
    markers and waveforms, ramp audio, isolation and voice files, device transcripts) have no
    MCP row against a held save; the hold is what such a row needs. *Covered since #552.*
- **#552 — The cache ledger counts, per writer, the publishes that waited a save out, and can
  hold a named writer's next publish until a save is in its hold; the dev tool `cache_ledger`
  answers the counts and arms the gates.** Dev tools only: `CacheLedgerDev.swift` is compiled
  under `FRAMEJOB_DEV_TOOLS` alone, and Distribution's `publish` reads the name nowhere.
  - **(a) Every publish names its writer.** `CacheLedger.publish(in:for:as:_:)`: `as` is
    required, so a new writer that names nothing does not compile. The names: `thumbs` (a
    strip's marker, both sites), `peaks`, `loudness`, `sync-features`, `speech`,
    `device-transcript`, an offline audio render's folder (`ramp-audio`, `isolated`, which a mix
    lands in too, `voiced`), and `analysis/<kind>/<media>` for the analysis store. The `waited`
    out-parameter of #429 is removed.
  - **(b) The count.** A publish that finds a save of its folder in flight when it takes the
    ledger's lock is counted under (cache folder, writer) after the lock is released, whatever
    the publish then answers. No writer keeps a count of its own.
  - **(c) The gate.** A writer armed for a folder is held at `publish`'s first line, before the
    ledger's lock, until a save of that folder is inside its `-RCDevSaveHold` sleep (the `write`
    override tells the gate when the sleep begins and ends), its gate is disarmed, or its bound
    passes; it then goes on into `publish`'s ordinary wait. One-shot. A writer at its gate is
    not a publication, so `saveBegan` does not wait for it.
  - **(d) The tool.** `cache_ledger {project?, gate?: [string], seconds?}`, on main, answering
    at once `{ok, cache, save_waits: {writer: n}, gate: {writer: armed | waiting | save |
    timeout | disarmed}}`. `gate` replaces the folder's armed set (`[]` disarms and releases);
    `seconds` (above 0, at most 600, default 60, only with `gate`) bounds each wait.
  - **Why a gate, and not the clock hold the issue expected** (a `-RCDev…Hold` before each
    media pass's publish): the five media passes publish one after another inside one task, so
    the first to meet a held save waits it out and the next arrives after it has ended. A clock
    would put one writer per save into the hold, and which one would turn on decode times. The
    gate makes each writer's meeting a fact a proof arranges, and adds no launch default.
  - **Its rows.** `save_hold_proof.py`, on one launch with `-RCDevSaveHold 3`, each document made
    on a plain launch first: M1–M5 the media passes from one `import_media`, D1 the device
    transcript from the Transcript tab's fill (a Mac with no on-device model is a named skip),
    O1–O3 `ramp-audio`, `isolated` and `voiced`. A row passes when its gate ended `save`, its
    `save_waits` rose by one and its files are in the package afterwards. R1 (#553) reads the
    same count. Mutants, each an app build that keeps the site's gate and drops the ledger, so
    the write falls inside the held save: `thumbs-outside`, `peaks-outside`,
    `loudness-outside`, `sync-outside`, `speech-outside`, `transcript-outside`,
    `render-move-outside`.
  - **Not covered.** A thumbnail's frames are written outside the ledger on purpose
    (`stripHolds` then writes no marker); the reverse render and `AudioRateCopy`'s copy are not
    ledger writers.
