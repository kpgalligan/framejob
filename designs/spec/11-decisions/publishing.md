# Spec §11 — decisions: Publishing a build

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

These were made with no road map: the pipeline is Rasterize's (`~/devel/rasterize`'s
`.github/workflows/publish.yml`), carried over on 2026-10-04, and a decision below says so
where Frame Job's differs, and why.

- **PUB-1 — A build for another person's Mac is made only by GitHub Actions, on a push to the
  `publish` branch: a Developer ID-signed, notarized, stapled `FrameJob.dmg` attached to a GitHub
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
  **Amended by PUB-6**: there is an updater, Sparkle 2 in the published build, so an installed
  copy updates itself; the private-repository risk ends when the owner makes the repository
  public, which comes before the first Sparkle-enabled publish.
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
- **PUB-6 — Sparkle 2 updates the published build, from `appcast.xml` on the latest GitHub
  Release, beside `FrameJob.dmg`, one item per release (the owner's choice, 2026-10-27).** This
  amends PUB-1's "there is no updater" and its private-repository risk: the owner makes the
  repository public before the first Sparkle-enabled publish, because an installed copy fetches
  the feed and the DMG without credentials. The feed URL,
  `https://github.com/kpgalligan/framejob/releases/latest/download/appcast.xml`, is fixed in every
  shipped copy, so the repository and the asset's name never change. Latest is always the
  highest run number: the workflow's create branch reads the current Latest's tag, and a re-run
  that creates a release older than it creates it with `--latest=false` (otherwise `--latest`);
  a re-run that finds its release already made replaces both assets and leaves Latest alone.
  Risk accepted: an installed copy sees only the newest release's appcast, so a release that is
  not Latest is never offered.
- **PUB-7 — Only Distribution holds an updater.** `FRAMEJOB_UPDATER` (the compilation condition),
  the feed and the public key are set in the Distribution configuration alone; Debug and Release
  read `project.yml`'s `:default=` values, which are empty (V-5's pattern), and compile no
  updater code. Sparkle.framework is embedded in every configuration, because xcodegen links a
  package per target, not per configuration, and loaded only in Distribution: Debug and Release
  link with `-dead_strip_dylibs`, and as no code of theirs references Sparkle, their binaries
  carry no load command for it. Loaded, it stops them launching: on an ad-hoc, hardened-runtime
  build dyld refuses the framework under library validation, "mapping process and mapped file
  (non-platform) have different Team IDs", though both are ad hoc (measured 2026-10-27).
  `dist_check.py`'s D32 and D34 hold a Release bundle to no feed, no key and no updater code,
  and D35 to no Sparkle load command. Risk accepted: a local, ad-hoc Distribution build loads
  Sparkle and so cannot be launched; nothing launches one (`dist_check.py`, `published_check.py`
  and the mutants only read it, and Write Agent Catalog runs the executable before the
  hardened-runtime seal), and the published build is Developer ID-signed, where the teams
  match. Frame Job ▸ Check for Updates… sits under About Frame Job in Distribution only. It has
  no MCP mirror: it edits no project, and it exists only in the build that has no dev tools.
- **PUB-8 — The EdDSA key is generated by the owner.** The private key is the `publish`
  environment's secret `SPARKLE_ED_PRIVATE_KEY`, backed up in the owner's login Keychain and
  never seen by an agent; the workflow reads it only through `env:` and writes it to a `0600`
  file that is removed after signing. The public key is `RC_SPARKLE_PUBLIC_KEY` in
  `project.yml`. Nothing can ship unsigned: the workflow's first step fails when the secret is
  absent, and `dist_check.py`'s D30/D31 and `published_check.py`'s P19/P20 refuse an empty feed
  or a key that is not 32 bytes of base64. The signature is made over the stapled DMG, after
  `stapler staple`, so the bytes signed are the bytes served. Until the owner's public key lands,
  `make dist` fails D31 and P20 by the owner's choice.
- **PUB-9 — Sparkle's own defaults apply.** Sparkle asks on the second launch whether to check
  automatically; `SUEnableAutomaticChecks` is not set, because no Settings toggle exists to turn
  checks off, and `SUAutomaticallyUpdate` is not set. The interval is Sparkle's default of a day.
  No delta updates. Release notes are only a `sparkle:fullReleaseNotesLink` to the release page.
- **PUB-10 — Every configuration carries `Contents/Resources/Acknowledgements.txt`, the
  third-party notices, written each build by `tools/licenses/acknowledgements.py` (#376).**
  Project.yml's "Write Acknowledgements" step runs it after "Build MCP Proxy" and before "Write
  Agent Catalog", which reseals the bundle. Crates come from `cargo metadata --format-version 1
  --locked --offline --filter-platform aarch64-apple-darwin` in `core/` and `mcp-proxy/`, over
  every non-dev edge (build dependencies and proc macros included), Frame Job's own three crates
  left out. npm packages come from `agent/bun.lock`, from the workspace's `dependencies` through
  each package's own (never `devDependencies` or an optional peer), each version confirmed
  against `agent/node_modules/<name>/package.json`. Each package gets its root licence files;
  without one, the canonical SPDX text of its declared licence under its declared authors, and
  the build fails naming the package when no canonical text is vendored. A licence file nested
  inside a package must be listed in the generator's `NESTED` (to include or to exclude), or the
  build fails naming it. Sparkle gets its own `LICENSE` from the resolved package. Bun's
  `LICENSE.md` is vendored at `BUN_LICENSE_VERSION` (`tools/licenses/bun/LICENSE.txt`): a
  different `bun --version` fails a Distribution build (`--strict-bun`) and is a note in the
  file in the others. The encoders' texts come from `build/codecs/licenses/` (CX-5 (4), which
  this amends with SVT-AV1's `vector.c-LICENSE`); the voice-activity model and each bundled font
  are listed too, the fonts with their OFL text. The file is byte-identical for identical inputs
  (no timestamp). It has no About-panel entry, so no §9 row and no guide line. `dist_check.py`'s
  D42/D43 hold the Release and Distribution bundles to a header for every shipped crate and npm
  package, each pin, Sparkle at `project.yml`'s version, Bun, the model and each bundled font,
  with readers of their own (no code shared with the generator, so the check is not
  tautological). Risk accepted: Bun's notice names the libraries it embeds, JavaScriptCore
  (LGPL-2) among them, by link and not by full text, as Bun publishes it.
- **PUB-11 — `published_check.py` carries the encoders' rows P22–P24 and the
  acknowledgements' P25.** P22 looks for each encoder's own string literal (`SVT-AV1 Encoder
  Lib`, `WebM Project VP9 Encoder`) in the app binary's bytes, not D37's `nm -j`, because
  `xcodebuild archive` strips the symbol table D37 reads, and the bytes survive the strip. P23
  is D39 (every load command a system library or Sparkle's), P24 D41 (the pins' licence texts,
  byte-identical to the checkout's `build/codecs/licenses/`) and P25 D43. No P row reads `nm`.
- **PUB-12 — The publish workflow restores `build/codecs` from the Actions cache under
  `codecs-<build_codecs.py --print-key>`, with no `restore-keys`.** The key is computed under the
  "Build Codecs" step's PATH prefix, because `find_cmake()` follows the caller's PATH and cmake's
  version is in the key. After Archive, whatever its outcome, a step compares
  `build/codecs/stamp.json`'s key with that key: a mismatch or a missing stamp is a `::warning::`
  naming both keys, and the folder is then never saved. On a cache miss with equal keys the
  folder is saved, so a later failed step does not lose the build. The stamp, not the cache,
  still decides reuse. `oven-sh/setup-bun` installs `BUN_LICENSE_VERSION`, the Bun whose licence
  is vendored. Risk accepted: the first run after a change to the script, the pins, cmake or the
  SDK builds the encoders from source again.
