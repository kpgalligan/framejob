# Developing Frame Job

Frame Job is a Swift/AppKit app over a Rust staticlib core. This page is for
someone building it from source or changing it: what you need, the `make`
targets, how the repository is laid out, the shape of the architecture,
publishing a release, and driving a build over MCP to check it. The rules a
change must follow live in the `CLAUDE.md` files next to the code they govern;
this page points to them rather than repeating them.

## Requirements

- **Xcode 26 or later** (the macOS 26 SDK). The build compiles a Metal shader;
  if `xcrun metal --version` fails, install the Metal toolchain with
  `xcodebuild -downloadComponent MetalToolchain`.
- **Rust** (stable, through `rustup`/`cargo`).
- **[xcodegen](https://github.com/yonaskolb/XcodeGen)**, which generates the
  Xcode project.
- **[bun](https://bun.sh)**, which builds and tests the assistant helper in
  `agent/`. Every `make app` builds it, `make typecheck` typechecks it and
  `make test` runs its tests; without bun they fail with
  `error: bun is not installed` rather than skipping.
- **[cmake](https://cmake.org)** (`brew install cmake`), which builds the
  bundled AV1 and VP9 encoders (SVT-AV1 and libvpx, spec §11 CX-5) with the
  system's `/usr/bin/perl` and Xcode's clang; no nasm, yasm, meson or ninja.
  `make app`, `make app-debug`, `make typecheck` and `make test` build them
  first; without cmake they fail, naming `brew install cmake`.
- **Python 3** for the scripts in `tools/proof/` and `tools/codecs/`, and `ffmpeg` for the proofs
  that compare exported sound sample for sample (proof time only — the product
  has no ffmpeg dependency).
- **Network access for the first build.** The app links
  [Sparkle](https://sparkle-project.org) 2 (the published build's updater,
  spec §11 PUB-6..PUB-9) as a Swift package, pinned in `project.yml`; the
  first `make app`, `make app-debug` or `make dist` fetches it into
  `build/SourcePackages/`, and later builds reuse that copy. The first
  `make codecs` (which those targets and `make typecheck` and `make test` run)
  likewise fetches the encoders' two pinned tarballs, about 17 MB, into
  `build/codecs-downloads/`, checks each by SHA-256, and builds them into
  `build/codecs/` in about a minute; later builds reuse them by their stamp.

## Make targets

| Target | What it does |
|---|---|
| `make app` | Builds the Rust core (release) and the bundled encoders (`make codecs`), generates the Xcode project, and builds the Release app into `build/Build/Products/Release/Frame Job.app` (about 90 s). |
| `make codecs` | Builds the bundled encoders, SVT-AV1 v4.2.0 and libvpx v1.17.0 (spec §11 CX-2..CX-5), with `tools/codecs/build_codecs.py`: each pinned tarball fetched and checked by SHA-256 (a mismatch fails, naming both digests), built arm64, static and encoder-only, and installed with its headers and licence texts into `build/codecs/`. A stamp keyed on the script, the pins and the tool versions makes a repeat a no-op; Xcode's "Build Codecs" step runs the same script. `tools/codecs/PROVENANCE.md` records the pins. |
| `make app-debug` | The same (the Rust core and `make codecs` first) with the Debug configuration: `build/Build/Products/Debug/Frame Job Debug.app`, an app called "Frame Job Debug" with its own bundle id (`com.kgalligan.FrameJob.debug`) and settings. Unoptimised, so it rebuilds in seconds after a one-file edit. |
| `make run` | `make app`, then opens it. |
| `make typecheck` | `make codecs` first (the bridging header includes the encoders' headers, found with `-Xcc -Ibuild/codecs/include`), then typechecks every Swift file in `app/Sources` with `swiftc` (with the dev tools compiled in), then the helper's TypeScript with `tsc --noEmit`. Seconds. It is the only authoritative Swift check, but it stops before code generation, so only `make app` proves the app builds. |
| `make test` | `make codecs` first, then the Rust tests of `core/`, `graphic/` and `mcp-proxy/`, then the scripted checks that need no app: the assistant's agent lane and prompt texts, the price function and the proofs' spend budgets (no network), the menu inventory and spec index against the tree, the self-tests of the encoder build, the acknowledgements' generator, the probe build, app-choice, gate and appcast scripts, the defaults clean-up, and the old-name residue check. |
| `make lint` | `cargo clippy --all-targets -- -D warnings` in `core/`, `graphic/` and `mcp-proxy/`. |
| `make fmt` | `cargo fmt` in the same three crates. |
| `make gate` | The one full verification: the name residue check, typecheck (held to exactly its known warnings), `cargo fmt --check`, lint, test, then `make app` with the Release app's entitlements and signature checked. Serial, stops at the first failure, and skips a step whose inputs and tools are byte-identical to its last pass (its state is in `build/gate/`). `make gate GATE_ARGS=--force` runs every step. |
| `make dist` | `make app`, then the Distribution configuration — Release without the dev tools — into `build/Build/Products/Distribution/Frame Job.app`, then the binary and signature checks (`tools/proof/dist_check.py`) and the check the publish workflow runs on what it ships (`tools/proof/published_check.py`); both run, and it fails if either does. Only this target compiles the updater (Sparkle, `FRAMEJOB_UPDATER`), so only its build loads Sparkle.framework, and, signed ad hoc, it cannot be launched: library validation refuses the framework (spec §11 PUB-7). It is only ever checked, never run. Until the owner's EdDSA public key is in `project.yml`, the key rows (D31 and P20) fail, by design. |
| `make project` | `xcodegen generate`, with the base version from `VERSION`. |
| `make prices` | **Network.** Regenerates `agent/prices/anthropic.json` from LiteLLM's price table; the file's only writer, never run by another target. |
| `make clean` | Removes `build/` (the built encoders and their downloaded tarballs with it, so the next build fetches them again), the generated project and `app/Info.plist`, and runs `cargo clean` in the three crates. |

A single Rust test runs as `cd core && cargo test --release --test edge slip`
(the test file's name, then a name filter). Finish Rust work with `make fmt`
and a clean `make lint`.

There are no Swift unit tests. The app is checked with `make typecheck`, by
driving the built app over MCP, and with the probes in `tools/proof/` (see
[Verifying a build](#verifying-a-build)).

### The Xcode project is generated

`FrameJob.xcodeproj` is generated from `project.yml`, the source of truth.
Never commit it. Run `make project` after editing `project.yml`, never a bare
`xcodegen generate`: `make project` feeds the base version from `VERSION` into
the project, and a bare run leaves the version blank. Both xcodegen and
`make typecheck` glob `app/Sources/`, so a new Swift file needs no
registration.

## Repository layout

```
core/            Rust staticlib: the project model, every edit, the composition
  include/         plan, the per-frame recipe, export settings, the MCP server,
  src/             the WebM/Matroska index. include/framejob_core.h is the
  tests/           hand-maintained C header, the FFI contract. Tests are
                   black-box, through the FFI.
graphic/         Rust crate (a path dependency of core): the graphics engine —
  src/ tests/      a JavaScript module in sandboxed QuickJS returns SVG per
                   frame, rasterized to BGRA.
mcp-proxy/       Rust crate: framejob-mcp, the stdio MCP server bundled in
  src/ tests/      Contents/Helpers, which forwards to the app's socket and
                   launches the app on a tool call.
agent/           The assistant helper: Bun and the Anthropic SDK's Tool Runner,
  src/             built into Contents/Helpers/framejob-agent by build.sh.
  prices/          The Anthropic price table and the fixtures its readers run.
app/
  Sources/         The AppKit app, programmatic UI (no storyboards).
  Resources/       Shaders/Compositor.metal, Models/ (the voice model),
                   Fonts/ (the bundled typefaces), and bundled media.
  Bridging/        The bridging header importing framejob_core.h and the
                   encoders' headers.
designs/         spec/ (the normative spec, one file per section), adr/
                 (condensed decision records), the design handoffs, screens/
                 (the screen catalog).
docs/            guide/ (the user guide), graphics-api.md, manual-checks.md,
                 agents/ (what the engineering skills read), this file.
tools/codecs/    build_codecs.py (`make codecs`: the bundled encoders' pins, their
                 fetch, digest check, build and stamp) and PROVENANCE.md.
tools/licenses/  acknowledgements.py (every build's third-party notices,
                 Contents/Resources/Acknowledgements.txt) and its selftest
                 (acknowledgements_selftest.py), the vendored texts it needs
                 (bun/LICENSE.txt, spdx/MIT.txt) and PROVENANCE.md.
tools/proof/     The verification scripts: mcp.py (the MCP client), the
                 per-feature proofs and probes, harness/ (the offscreen chrome
                 capture), swift_build.py, proof_app.py, gate.py.
archive/         Closed road maps and histories, verbatim; INDEX.md.
.github/         workflows/publish.yml and ExportOptions.plist.
project.yml      The xcodegen definition.
Makefile         Build orchestration.
VERSION          The base version, MAJOR.MINOR.
```

## Architecture

**Rust decides, AVFoundation and Metal do.** The core holds the project (as
JSON), every edit, the composition plan and the per-frame recipe, and reads a
WebM or Matroska file's index for the import's copy. Swift owns the windows,
gestures, undo, AVFoundation playback and export, the Metal compositor, media
import and its caches, and agent dispatch. There is no pixel or sample work in
Rust and no ffmpeg dependency in the product. The preview and the export share
one description of the movie, so a frame that differs between them is a bug in
the compositor or the builder, never in a second rendering path.

**The FFI contract.** `core/include/framejob_core.h` is a hand-maintained C
header and the single contract between the two worlds. It is three files in
lockstep: a Rust `#[no_mangle]` export, its entry in the header, and its
wrapper in `app/Sources/ReelCore.swift`, the only Swift file that calls `rc_*`.

- A project handle is **immutable**. Every edit is pure and returns a new
  handle, so undo is a stack of handles and publishing a handle to the
  compositor's queue is safe. Complex data crosses as UTF-8 JSON, which also
  gives an MCP agent the same vocabulary the app has.
- Edits are JSON ops through `rc_project_apply`, which answers one of three
  ways: applied (a new project, the only one that makes an undo step), an
  identity (NULL with no message: nothing needed to change), or a refusal
  (NULL with `reason_out` set: the rule's own sentence). NULL with `err_out`
  set means the input could not be read, and only that is an error.
- What an op means is the module doc of `core/src/edit.rs`; what it takes is
  `core/src/op_table.rs`, published as JSON Schema. The Swift builders, the
  MCP tool catalog and spec §6 mirror them.
- A change to persisted state bumps `RC_FORMAT_VERSION` in
  `core/src/format.rs` and in the header.

**Where the maps are.** The module map, file sizes and per-side rules are in
the `CLAUDE.md` beside each side's code: [`core/CLAUDE.md`](../core/CLAUDE.md),
[`app/CLAUDE.md`](../app/CLAUDE.md) (which also has the Swift file map),
[`graphic/CLAUDE.md`](../graphic/CLAUDE.md) and
[`mcp-proxy/CLAUDE.md`](../mcp-proxy/CLAUDE.md). The spec's
[§7](../designs/spec/07-architecture.md) is the architecture, with the Swift
file map in [§7.4](../designs/spec/07.4-swift-file-map.md) and the Rust module
map in [§7.10](../designs/spec/07.10-rust-module-map.md). The root
[`CLAUDE.md`](../CLAUDE.md) has the standard recipe for where each part of a new
feature lands, and the rules every change follows (an MCP mirror for every
user-visible edit, the per-file line caps, the decisions in spec §11 that are
not re-opened).

## Publishing a release

A build for another Mac comes only from a push to the `publish` branch, which
runs `.github/workflows/publish.yml`. Pushing there publishes, so it is the
owner's call. The workflow:

1. stops at once when the `SPARKLE_ED_PRIVATE_KEY` secret is missing, so
   nothing ships without an update signature;
2. archives the Distribution configuration signed with Developer ID and
   exports it;
3. checks the exported app with `tools/proof/published_check.py`;
4. packs it, with an Applications link, into `FrameJob.dmg`, signs the DMG,
   notarizes and staples it;
5. signs the stapled DMG with the EdDSA key (Sparkle's `sign_update`, from the
   package the archive resolved) and writes a one-item `appcast.xml` for it
   (`tools/proof/appcast.py`);
6. attaches both to a GitHub Release tagged `v<version>`, creating the release
   or replacing both files on a re-run. A new release is made Latest unless
   the current Latest has a higher run number (an old run re-run), because
   every installed copy reads its updates from
   `https://github.com/kpgalligan/framejob/releases/latest/download/appcast.xml`
   (spec §11 PUB-6). The repository must be public for that feed and the DMG
   to download.

The version is the `VERSION` file (MAJOR.MINOR) plus the workflow's run
number, and the build number is the run number, so bump `VERSION` for a new
minor line. The run counter belongs to the workflow file's name; never rename
it. The newest build is always at
`https://github.com/kpgalligan/framejob/releases/latest/download/FrameJob.dmg`.

The workflow runs no tests: run `make gate` and `make dist` on what you push.
The runner builds the bundled encoders itself: the workflow installs cmake
when the image lacks it, and the archive's "Build Codecs" step fetches the
pinned tarballs and builds them, as a local build does.

**The encoders' cache (spec §11 PUB-12).** A "Read the pins" step computes
`tools/codecs/build_codecs.py --print-key` under the "Build Codecs" step's
PATH prefix (`/usr/bin:/opt/homebrew/bin:/usr/local/bin`), so cmake and
`python3` resolve as they do inside Xcode, and `build/codecs` is restored from
the Actions cache under `codecs-<key>`, with no `restore-keys`. After the
Archive, whatever its outcome, a step compares `build/codecs/stamp.json`'s key
with that key: a missing stamp or another key is a `::warning::` naming both,
and the folder is not saved; on a cache miss with equal keys it is saved, so a
later failed step does not lose the build. The stamp, not the cache, decides
whether Build Codecs reuses the folder, so a stale cache can never ship. A
change to the script, the pins, cmake or the SDK changes the key and builds
the encoders again once.

**The acknowledgements (spec §11 PUB-10, PUB-11).** Every build writes
`Contents/Resources/Acknowledgements.txt` (project.yml's "Write
Acknowledgements", `tools/licenses/acknowledgements.py`): each shipped crate
(`cargo metadata` over every non-dev edge of `core/` and `mcp-proxy/`), each npm
package the helper bundles (`agent/bun.lock`, a nested version read from its
own `node_modules/<parent>/node_modules/` folder), Bun, Sparkle, the encoders, the
voice-activity model and each font, each with its full licence text. A crate
or package with no licence file gets the canonical SPDX text from
`tools/licenses/spdx/` under its authors, and the build fails naming it when
that text is not vendored; a licence file nested in a package must be listed
in the generator's `NESTED`, or the build fails naming it. `make dist`'s
`dist_check.py` D42/D43 and the workflow's `published_check.py` P25 hold the
file to every shipped component; P22–P24 hold the encoders (each one's own
string in the binary, which the archive's strip keeps; the load commands; the
licence texts).

**The Bun pin.** The helper is compiled by Bun, whose own licence
(`tools/licenses/bun/LICENSE.txt`) is vendored at `BUN_LICENSE_VERSION` in
`acknowledgements.py`. A Distribution build whose `bun --version` differs
fails, and Debug and Release builds write a note into the file instead, so the
workflow's setup-bun installs exactly that version
(`acknowledgements.py --print-bun-version`). After upgrading Bun locally,
re-vendor its licence as `tools/licenses/PROVENANCE.md` says.

What only a real publish shows: a cache save on its first run, and on the
second a hit, `codecs: reused <key>` in the Archive's log and no stamp
warning; the Developer ID export keeping `Acknowledgements.txt` (P25 over the
exported app); and setup-bun installing the pinned Bun.

The signing and notarization credentials are secrets in the repository's
`publish` environment (Settings ▸ Environments), whose deployment branches are
restricted to `publish`:

| Secret | What it is |
|---|---|
| `DEVELOPER_ID_P12_BASE64` | The Developer ID Application certificate with its private key, exported as a `.p12` and base64-encoded. |
| `DEVELOPER_ID_P12_PASSWORD` | That `.p12`'s export password. |
| `KEYCHAIN_PASSWORD` | Any random string, for the temporary signing keychain. |
| `APPLE_TEAM_ID` | The Apple Developer team id. |
| `ASC_KEY_ID`, `ASC_ISSUER_ID` | An App Store Connect API key's id and issuer, for notarization. |
| `ASC_KEY_P8_BASE64` | That key's `.p8`, base64-encoded. |
| `SPARKLE_ED_PRIVATE_KEY` | Sparkle's EdDSA private key, as `generate_keys -x` exports it (spec §11 PUB-8). Its public half is `RC_SPARKLE_PUBLIC_KEY` in `project.yml`. |

Every local build stays ad-hoc signed and needs none of them.

The update key is the owner's to make, once, and no agent ever handles it:

1. Run Sparkle's `generate_keys`, from the Sparkle 2.10.1 release's `bin/`
   or from `build/SourcePackages/artifacts/sparkle/Sparkle/bin/` after a
   `make app`. It keeps the private key in your login Keychain, which is its
   backup, and prints the public key.
2. Export the private key to a scratch file and store it as the secret, then
   delete the file:

   ```sh
   generate_keys -x <tmpfile>
   gh secret set SPARKLE_ED_PRIVATE_KEY --env publish --repo kpgalligan/framejob < <tmpfile>
   rm <tmpfile>
   ```
3. Put the printed public key in `project.yml`'s Distribution
   `RC_SPARKLE_PUBLIC_KEY` and commit it. Until then `make dist` fails D31 and
   P20, and the workflow's `published_check.py` refuses to publish.

Losing the private key means installed copies can no longer be updated: keep
the Keychain item.

## Verifying a build

The app is verified by driving the built binary over MCP and comparing what it
renders, not by reading code. Launch your own instance on its own socket, and
only ever stop that one (another session may have one running):

```sh
make app-debug
python3 tools/proof/proof_app.py launch   # prints folder, socket, log, pid
```

The launcher gives the instance a scratch socket (`RC_AGENT_SOCKET`) and a
scratch home folder, launches "Frame Job Debug" unless told `--app release`
(or `RC_PROOF_APP=release`), and refuses a build older than its sources,
naming the file and the `make` target. Point `tools/proof/mcp.py`'s
`mcp.MCP("<folder>/agent.sock")`, or `framejob-mcp` with `RC_AGENT_SOCKET` set
to the same path, at the socket it prints, and stop it by the printed pid.

Before trusting any run, `grep "Frame Job: " <folder>/framejob.log` must print
nothing: that prefix is the startup check that the tool catalog matches the
core's op table. On a Debug build the same mismatch traps instead.

The instance still shares its bundle's settings domain, so never perform a
menu item that persists a setting (the View menu's Snapping, Safe Areas, Hide
Inspector, Timeline Track Height, Preview Quality) from a script.

A Debug or Release build, never Distribution, also has dev-only tools over
MCP: `snapshot_ui` (a capture of the editor, a sheet, Settings, Welcome or the
recorder panel, with a layout dump), `perform_menu_item`, `cancel_sheet`,
`select_inspector_tab`, `play_preview` (plays a preview and answers the frames
composed), `graphic_memory` (the graphic rasters' memory budget, and a
simulated memory-pressure event) and `assistant_send` / `assistant_answer` (an
assistant turn against a stand-in server). To look at the chrome without a
running app or a Screen Recording grant, use the offscreen harness in
`tools/proof/harness/`.

The root [`CLAUDE.md`](../CLAUDE.md) ("Verifying a build", "Verification",
"Seeing the chrome") has the full rules: what a proof may claim, which build a
recorded run drives, and the dev-only launch defaults.
[`tools/proof/README.md`](../tools/proof/README.md) lists the proofs, says how
to make their test media, and describes the MCP client and the harness. What no
script can confirm is a row in [`docs/manual-checks.md`](manual-checks.md),
which the owner runs before each release.
