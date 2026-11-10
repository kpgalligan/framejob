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
