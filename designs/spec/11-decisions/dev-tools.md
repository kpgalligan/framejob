# Spec §11 — decisions: Dev tools (road map 11)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The road map that made these is closed; its condensed record is
`designs/adr/roadmap-11-dev-tools.md` (the original is `archive/reelcut-roadmap-11.md`).
V-4 and V-5 come from the build-velocity road map, now closed: `designs/adr/build-velocity.md` (the original is `archive/build-velocity.md`).

- **V-1 — Dev tools are compiled only under `REELCUT_DEV_TOOLS`, and the shipping build is
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
- **V-5 — The Debug build is its own app: "Reelcut Debug", `com.kgalligan.Reelcut.debug`, its
  own defaults domain, and an Alternate handler for `.reelcut`, so a double-click opens the real
  Reelcut.** Debug-config settings only (`PRODUCT_BUNDLE_IDENTIFIER`, `RC_APP_NAME`,
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
