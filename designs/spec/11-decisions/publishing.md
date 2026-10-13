# Spec §11 — decisions: Publishing a build

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

These were made with no road map: the pipeline is Rasterize's (`~/devel/rasterize`'s
`.github/workflows/publish.yml`), carried over on 2026-10-04, and a decision below says so
where Reelcut's differs, and why.

- **PUB-1 — A build for another person's Mac is made only by GitHub Actions, on a push to the
  `publish` branch: a Developer ID-signed, notarized, stapled `Reelcut.dmg` attached to a GitHub
  Release tagged `v<version>`.** `.github/workflows/publish.yml` is the whole pipeline. The
  certificate and the notarization key are secrets of the repository's `publish` environment,
  which only the `publish` branch may use; the team ID is one of them and is never written in
  the repository. Every local build stays ad-hoc signed (`CODE_SIGN_IDENTITY: "-"`), so `make
  app`, `make dist` and every proof need no certificate and no keychain prompt, which an agent's
  headless build could not answer. Risks accepted: the workflow does not run `make test` (its
  proofs depend on host state a runner does not have), so the tree pushed to `publish` is as
  tested as whoever pushed it left it; there is no updater, so a person re-downloads to update;
  and while the repository is private a release's DMG is downloadable only by people with access
  to it.
  **Amended by NM-3** (rename R0): `Reelcut.dmg` is now `FrameJob.dmg` (NM-2's exception: GitHub
  rewrites a space in a release asset's name to a dot); the DMG's volume name Reelcut is now
  "Frame Job", and the release's title "Reelcut <version>" is now "Frame Job <version>".
- **PUB-2 — The version is `<MAJOR.MINOR>.<run number>`, the build number is the run number, and
  the base is the `VERSION` file at the root, exactly as in Rasterize (the owner's choice,
  2026-10-04).** `make project` passes the file to xcodegen as `RC_BASE_VERSION`, `project.yml`
  sets `MARKETING_VERSION` from it, and `Info.plist` reads `$(MARKETING_VERSION)` and
  `$(CURRENT_PROJECT_VERSION)`; a local build reads "0.2 (0)". The workflow reads the file,
  refuses anything that is not two integers, and overrides both settings on its command line.
  The scheme's one trap is that a BARE `xcodegen generate` writes a blank version, so `make
  project` is the only way the project is generated: it stops when `VERSION` is missing,
  `tree_copy.py` copies the file into every proof's tree copy (whose `make app` runs `make
  project` there), and `published_check.py`'s P15 fails a bundle whose version is blank, in
  `make dist` and in the workflow. Risks accepted: the third number does not reset when the
  base is bumped (0.2.41 is followed by 0.3.42), and the run counter belongs to the workflow
  FILE, so renaming or recreating `publish.yml` restarts it and build numbers go backwards.
- **PUB-3 — What is published is the Distribution configuration (V-1), archived and then exported
  with the `developer-id` method.** The workflow names the configuration on its command line
  rather than relying on the scheme's archive action. The two helpers are signed by their own
  build steps with the identity the archive is given (`EXPANDED_CODE_SIGN_IDENTITY`), with a
  secure timestamp, before Xcode signs the app around them — the steps `make app` already runs
  with the ad-hoc identity.
- **PUB-4 — The exported app is checked by `tools/proof/published_check.py` before it is packed,
  and a failed row publishes nothing.** The export signs the app a second time, and the notary
  looks only at what it refuses (no hardened runtime, no timestamp, `get-task-allow`, a
  signature that is not Developer ID). The check holds what would otherwise ship broken inside
  a DMG that notarizes cleanly: the dev tools compiled in, the app without its microphone
  entitlement, the assistant helper without `allow-jit`, the MCP proxy or its catalog snapshot
  missing or wrong, and the two version numbers. `make dist` runs the same script over the
  local Distribution build, so it is exercised between publishes. Risk accepted: in the
  workflow the absence of the dev tools has no positive control — that is `dist_check.py`'s D4,
  which needs a Release bundle the workflow does not build.
- **PUB-5 — The DMG is what is notarized and stapled, with an App Store Connect API key.**
  Notarizing the DMG covers the app inside it, and one submission is one wait. Risk accepted:
  the ticket is stapled to the DMG and not to the app, so an app copied out of it is verified
  online on its first launch; a Mac with no network at that moment is told the app cannot be
  checked.
