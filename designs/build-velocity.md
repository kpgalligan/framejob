# Build velocity (issue batch B88)

**Goal.** Make every Swift compile a proof pays parallel and paid once per
input state; give the loop a Debug app, "Reelcut Debug", with its own bundle
id and defaults domain, that cannot be driven stale; put one skipping gate and
a Verification rule over it. Nothing in the shipped product changes: `make
app` stays Release, Release and Distribution keep identical build settings
and Info.plist bytes, and `make dist` and `.github/workflows/publish.yml` are
untouched.

## Phases

Each phase is committed alone, in this order.

| Phase | What | Needs |
|---|---|---|
| 1a | `make typecheck` in batch mode; `tools/proof/swift_build.py` (one cached probe build); harness `build.sh`, `make test`'s two probes and `graphics_inspector_proof.py` go through it | — |
| 1b | The other 68 scripts go through the helper; add the one-swiftc-line guard. Permitted cut: two runs (alphabetical halves), with the guard in the second | 1a |
| 2 | Fix the Debug configuration and give it its own identity (spec §11 V-5); the Rust step always runs; `make app-debug`; `tools/proof/proof_app.py` (app choice, stale refusal); the defaults guard follows the app under test; launch points and tree-copy builds go through it. The default stays Release | — |
| 3 | Debug-vs-Release equivalence proof; qualification; the default flips to Debug; Release-only pins; spec §11 V-4 (amends V-1) | 2 |
| 4 | `make gate`; the Verification rule; the road map closes into an ADR | 1a, 2, 3 |

## Decisions

- **One probe build line.** A probe, a proof or the harness compiles app
  sources only through `tools/proof/swift_build.py`; its argv is spelled in
  one place (`_argv`).
- **Parallel by `-j <cores>`, not batch mode, for a linked build.** The
  serial line's machine code is what every earlier proof measured; `-j`
  keeps it byte-for-byte (phase 1a's `__text` check), while batch mode with
  an output file map does not (E1, below). `make typecheck` and
  `swift_build.py typecheck` link nothing and use batch mode.
- **Content, never mtime.** A build is reused only when a sha256 over every
  input — the helper, the toolchain and SDK, the argv less `-o`/`-j`, the
  output's file name, every
  source, the bridging header and its quoted includes, the staticlib, each
  link input, four toolchain variables and the tree's path — matches a cached
  entry whose binary still hashes to its manifest.
- **A guard, not a convention.** `swift_build.py --selftest`'s G1 fails
  `make test`, naming the file, when a `tools/proof` script outside the
  allow-list (`swift_build.py`, `reference_build*.py`, the closed spikes)
  holds a swiftc argv and the bridging header (its name,
  `-import-objc-header` or `BRIDGING`). A swiftc line that
  compiles no app source may stay, in a file that does not name the header.
- **Delivered to the caller's own path and name**, because a bare binary's
  defaults domain and `proof_defaults.py --ran` are that name; and **linked
  under that name**, because the linker makes it the ad-hoc signature's
  identifier, which LaunchServices keys a bare binary's recent documents by.
- **The harness's Fonts and Models** are recopied only when their digest
  differs, through a sibling folder renamed into place, so a reuse never
  pulls a folder out from under a launching harness.
- **The Debug build is its own app** (spec §11 V-5, phase 2): "Reelcut
  Debug", `com.kgalligan.Reelcut.debug`, its own defaults domain and an
  Alternate `.reelcut` handler, through three Debug-only settings that
  Info.plist reads with `:default=`, so Release and Distribution keep their
  settings and bytes. `PRODUCT_NAME` stays `Reelcut`.
- **A built app is judged by its `_CodeSignature/CodeResources`**, never its
  executable's mtime, against the newest input of its own tree (`*.md` but
  `docs/graphics-api.md` excluded); a running instance by its start. No
  override variable: the refusal names the file, its time and the target.
- **The defaults guard follows the app under test**: `scratch_socket()`
  records `proof_app.domain()`, and a socket it made that an instance of
  another bundle then holds is re-homed to that bundle's domain.
- Owner rulings that bind every phase: one mutant per new decision (usually
  3–8; more than 10 only with a written reason); Debug while working, Release
  built and checked once at each phase's end; no override variable for the
  stale refusal; the gate runs its steps serially.

## Record

### Phase 1a — the probe builder (2026-10-07)

**Landed.** `Makefile`'s `typecheck` line gains `-enable-batch-mode -j
"$$(sysctl -n hw.logicalcpu)"`, and `test` runs `python3
tools/proof/swift_build.py --selftest` before `proof_defaults.py`.
`tools/proof/swift_build.py` (new): `build`, `typecheck`, `app_sources`,
`cache_key`, the cache under `tools/proof/work/swift-build/`, the CLI and the
selftest (K0, K1, B1–B5). `tools/proof/harness/build.sh` builds through it
(same CLI, output path and docs copies; Fonts/Models by digest). The
`build_probe` of `assistant_lane_proof.py`, `assistant_prompt_proof.py` and
`graphics_inspector_proof.py` calls `swift_build.build`, with their mtime and
`sources.txt` staleness checks removed. `tools/proof/README.md` has the
section "The probe builder (swift_build.py)".

**Timings** (one session, 12 logical cores; the 1-minute load average at
start → end; another session shared the machine throughout):

| command | before (HEAD fe22fac) | after | load |
|---|---|---|---|
| `make typecheck`, clean | 81 s (tsc ≈ 1 s of it) | 3.4 s, the same four warnings | 3.7 → 3.1; 2.1 → 2.6 |
| typecheck line over a scratch copy with one type error | 17 s, exit 1, the error named | 3.2 s, exit 1, the error named | 3.3 → 3.0; 2.7 |
| harness cold, serial (`build.sh --force` at HEAD) | 124 s; again 112 s (the control) | — | 3.0 → 8.0; 3.2 → 4.6 |
| harness cold, helper (`build.sh --force`) | — | 15.1 s; 16.0 s; 24.0 s | 2.8 → 4.1; 4.0 → 6.1; 16.8 |
| harness reused (`build.sh`) | 0.02 s (mtime skip) | 0.37 s, 0.34 s (digest checked) | 17.0 |
| lane proof, cold | 130 s whole (probe 110 s) | 37.5 s whole (probe 17.2 s) | 6.5 → 4.1; 8.9 → 12.1 |
| lane proof, reused | 19.6 s | 21.1 s | 3.9; 12.1 |
| prompt probe (`--probe`), cold / reused | probe 108 s (inside `make test`) | 18.4 s (probe 15.2 s) / 2.3 s | 8.5; 9.7 |
| `make test` after a one-line Swift comment | 307 s (each probe 108 s) | 109 s (probes 18.3 s and 27.2 s) | 3.0 → 6.2; 9.9 → 31.4 |
| `graphics_inspector_proof.py`, whole | 17.2 s (probe and harness current by mtime) | 33.4 s with its probe cold (15.9 s); 17.2 s reused | 4.1 → 3.7; 8.6; 9.8 |
| `graphics_inspector_proof.py --mutant popup-fixed-width` | 112.5 s (probe 110 s) | 19.7 s (probe 16.9 s) | 3.6 → 1.7; 7.9 → 12.1 |

The "before" `make test` row made both probes stale by removing their
binaries; the "after" row by a one-line comment appended to
`app/Sources/ReelOpSchema.swift`, restored byte-for-byte straight after. Both
are one full compile of each probe.

**Machine code.** `segedit <bin> -extract __TEXT __text <out>` and `cmp`:
the serial line's and the helper's `__text` are byte-equal for the harness
(15 767 764 bytes) and for the lane probe (15 781 920 bytes). CONTROL: two
serial harness builds are equal. Sensitivity: two helper builds over a copy of
`app/Sources`, the second with `AppSupport.swift`'s `0o700` changed to
`0o755`, differ. `-j` is adopted.

**E1, measured once.** The helper's non-WMO line as `-enable-batch-mode -j 12
-output-file-map <a map naming every object in the tmp dir>`: it links the
harness, in 10.2 s against the `-j` build's 15.5 s in the same session
(0.66×, under the 0.7× bar), but its `__text` differs from the `-j` build's
(15 767 756 bytes against 15 767 764). One of the four conditions fails, so
E1 is not adopted and the line keeps `-j`.

**Verified.** `swift_build.py --selftest` 6/6 and `PASS` (its first run
failed B3: a rebuild after a failed digest landed beside the tampered entry
and the tampered binary was still delivered; the build now sets the old
entry aside first). `make typecheck` 0 errors, the four baseline warnings.
`assistant_lane_proof.py` 18/18 cold and reused; `assistant_prompt_proof.py
--probe` 14/14 cold and reused; `harness/build.sh --force` then
`phase2_chrome.py` 26/26; `build.sh` twice more reused with the Fonts and
Models inodes unchanged (and a stray file put in the harness's Fonts made one
recopy, a new inode, the stray gone); `graphics_inspector_proof.py` 91/91,
and `--mutant popup-fixed-width` `MUTANT PASS` (exactly its three rows,
through the cache). The Full gate's numbers are in this phase's checks file.

**Owed to phase 1b.** The other 68 scripts, the G0/G1 guard rows, and room
for them in `swift_build.py` (399 of its 400 lines are used).

### Phase 1b — every proof through the probe builder (2026-10-08)

**Landed.** The 68 scripts that carried their own app swiftc line call
`swift_build.build`, each with its own sources, entry and extra files,
defines, optimisation, link arguments, output path and name and failure
strings, and without its mtime or `sources.txt` staleness check (the key is
the staleness rule). They were counted as the files `git grep -l '"swiftc"'
-- tools/proof/` finds that also name `Reelcut-Bridging-Header` (77), less the
six not converted and 1a's three: agent_open_proof, agent_socket_proof,
assistant_tab_proof, cache_pass_probe, clip_catalog_proof,
clip_inspector4_proof, clip_inspector_proof, cloud_captions_probe,
container_rewrap_probe, e1_chrome, e2_chrome, editor_keys_undo_proof,
export_cancel_proof, ffmpeg_rewrap_proof, formats_probe, graphics_ffi_probe,
graphics_menu_proof, graphics_prefetch_proof, graphics_proof,
graphics_store_probe, harness_playhead_proof, marquee_probe,
media_less_playback_probe, menu_undo_probe, mixed_audio_probe,
name_field_proof, obscure_handles_probe, op_argument_proof, op_catalog_proof,
op_schema_probe, paste_graphic_probe, peaks_probe, phase5_chrome,
phase6_chrome, phase7_chrome, phase8_chrome, phase8_proof (its
bridging-header call), phase9_chrome, phase9_probe, playback_audio_proof,
playhead_echo_probe, preview_refresh_probe, preview_validity_probe,
recording_probe (both calls), refusal_probe, relink_sheet_probe,
remaining_probe, scope_playhead_probe, settings_layout_probe,
sheet_queue_probe, silence2_probe, source_mirror_probe, space_key_proof,
speech_engine_proof, speed_audio_probe, speed_limits_probe,
speed_sheet_probe, text_apply_proof, text_break_proof, text_edit_proof,
track_menu_probe, transition_sheet_probe, v2_menu, v2_snapshot,
video_configuration_proof, word_captions_chrome, word_captions_probe and
words_picture_probe. `swift_build.py` gains the guard (`own_line`,
`own_lines`) and selftest rows G0 (CONTROL) and G1, so `make test` fails,
naming the file, when a proof carries its own app swiftc line.
`tools/proof/README.md`'s probe-builder section says who goes through it and
what does not.

**Not converted, by design.** `reference_build.py` and
`reference_build_selftest.py` (historical trees, their own key and module
caches), the closed spikes (`assistant_spike/`, `capture_spike/`,
`speed_spike/`, `words_spike/text_rows.py`; `recording_spike.py` carries no
app line), and two swiftc lines that compile no app source:
`phase8_proof.py`'s extracted `PreviewQuality.swift` and `v2_snapshot.py`'s
`v2_cover`. G1's allow-list is `swift_build.py`, `reference_build*.py`,
`*_spike/*` and `recording_spike.py`; the two non-app lines pass because
their files no longer name the bridging header. G1 skips `tools/proof/work/`.

**Shapes worth naming.** `speed_limits_probe.py`: `optimize=True, wmo=True`
and `library=<lib_dir>/libreelcut_core.a` (a mutant's scratch core).
`recording_probe.py`'s voice-over probe: `link_args` `-Xlinker -sectcreate
-Xlinker __TEXT -Xlinker __info_plist -Xlinker <plist>`, the plist also in
`link_inputs`. The word-caption builders keep their support file before the
entry. `phase5_chrome.py`'s `Loudness.swift` probe had no bridging header or
staticlib; the one line gives it both. `clip_inspector4_proof.build_harness`
recopies Fonts/Models after a fresh build, or when a reused build's folder
lacks them. `swift_build.py` is 445 lines with the guard (1a's spec held it
to 400; CLAUDE.md holds proof instruments to neither cap).

**Verified.** `swift_build.py --selftest` 9/9 `PASS` (G1 lists nothing;
over HEAD edeba18's `tools/proof`, the same scan names exactly the 68).

- **The 56 not run whole**, by a throwaway driver (`work/b88/build_each.py`,
  not committed) that imports each script in a child of its own and calls its
  converted build function once: 55 binaries landed at the path the function
  computes with HEAD's file name; every import was side-effect free.
  `marquee_probe.py`'s probe no longer compiles (`switch must be exhaustive`
  over `TimelineHit`), and HEAD's own `build_probe`, run from a `git
  archive` of HEAD, fails the same way: an old failure, not this phase's.
  Each cold build took 14–22 s at load 6–29; `speed_limits_probe.py`'s `-O`
  whole-module build 99 s (that line was already serial: 108 s recorded on
  2026-10-01).
- **The 12 changed since 7da4b1c, whole**, once, against the Release build:
  agent_open_proof 15/15; cloud_captions_probe 863/865 with 3 skipped by
  name, exit 1, as recorded on 2026-10-06 (SP3, SP4·off and row W's
  baseline: historical trees that no longer build against today's header);
  container_rewrap_probe 61/61; export_cancel_proof `--runs 3` 7/7;
  ffmpeg_rewrap_proof 23/23; graphics_menu_proof 27/27; graphics_store_probe
  45/45; paste_graphic_probe 9/9; phase7_chrome 79/79; word_captions_chrome
  49/49; words_picture_probe 21/21; recording_probe 1208/1220, its granted
  tiers run (screen and microphone authorized; the voice-over probe, built
  with `-sectcreate`, passes 15g). Its 12 failures are all section 6d's
  welcome-window pixel rows, and HEAD's own script fails the same 12
  (`--only welcome`, 23/35): old failures. No `DEFAULTS MOVED`; the two
  launched instances' logs hold no `Reelcut: ` line.
- **Mutants, one per build shape**, each caught: `graphics_store_probe.py
  --mutant whitelist-removed` (sources in a temporary folder) `MUTANT PASS`,
  31 s; `recording_probe.py --mutant voice-front-track --only
  voiceover,voiceover_granted` (the `-sectcreate` build over the mutant
  copy) V3's two rows and V6 fail, and V9b, a control the mutant's missing
  forward also breaks — HEAD's script gives the same 45/49;
  `name_field_proof.py --mutant
  frame-insets` caught, 22 s; `speed_limits_probe.py --mutant ceiling-16`
  (`-O` whole-module against the mutant's scratch core) CAUGHT, 281 s (348 s
  recorded); `text_break_proof.py --mutant pre-fix-width` (defines) caught,
  38 s.
- **Full:** `make test` exit 0 in 97 s at load 6.7 → 9.2 (both probes
  compiled once, the helper's bytes having changed: 16 s and 15 s): cargo
  all ok; lane 18/18; prompt 14/14; prices 27/27; budget 23/23; inventory
  5/5; spec index 141/141; `swift_build.py --selftest` 9/9 `PASS`;
  proof_defaults 10/10. `make typecheck` was not re-run: no Swift or
  TypeScript file changed.

**Fix pass (2026-10-08).** The review's should-fix: G1 missed a Python argv
naming the header through `swift_build.BRIDGING`, one starting
`"/usr/bin/swiftc"`, and a shell `xcrun -sdk macosx swiftc …` or `cd x &&
swiftc …` line. The markers were widened and the header test takes
`-import-objc-header` or `BRIDGING`. G0 flags the `BRIDGING` argv and the
`xcrun -sdk macosx` line, and its "no bridging header" control is now a
swiftc argv with no header at all, because the old text carried
`-import-objc-header`. Over HEAD's `tools/proof` the scan still names
exactly the 68, and over this tree it names none. The nit:
`harness_playhead_proof.py`'s mutant note says "reused" on a cache hit.

`marquee_probe.py`'s `kind(_:)` names `TimelineHit`'s two newer cases
(`.action`, `.actionEdge`) as themselves. The fixture's text clips carry no
actions, so no row expects either. Whole: 28/28.

Section 6d's 12 failures were not old. They came from phase 1a. The builder
linked every binary as `<entry>/binary`, so the linker's ad-hoc signature
gave every proof binary the identifier `binary`. LaunchServices keys a bare
binary's recent documents by that identifier, and proofs that open packages
had left four recents under it. Today's harness therefore drew the welcome
window's Recent rows, while the reference (linked `-o harness`) drew none,
and the vertically centred column moved 93 px instead of 6. Measured on a
scratch copy: the same binary re-signed `-i harness` lists no recents, and
its lockup sits exactly 6 rows below the reference's. Now `build()` links
under the caller's file name, the key includes that name, and the new
selftest row B6 checks that the delivered binary's identifier is its file
name. Selftest 10/10. `recording_probe.py --only welcome` 35/35, recents
listed 0. `marquee_probe.py` re-run on the fixed builder, 28/28. `make test`
exit 0 in 98 s (powermode 0 before and after): cargo 100 `ok`, 0 failed;
lane 18/18; prompt 14/14; prices 27/27; budget 23/23; inventory 5/5; spec
index 141/141; selftest 10/10; proof_defaults 10/10. `make lint` and `make
typecheck` were not re-run, because no Rust, Swift or TypeScript file changed.

### Phase 2 — the Debug app, its identity and the stale refusal (2026-10-08)

**Landed.** Spec §11 V-5 first (`designs/spec/11-decisions/dev-tools.md`,
its index row and Lines cell, and `designs/spec/README.md`'s 11-decisions
total, which `spec_index_proof.py` checks). `project.yml`: the Debug config
gains `ENABLE_DEBUG_DYLIB: NO` (Write Agent Catalog's `codesign -s - -f
"$exe"` fails on Xcode 26's split `__preview.dylib`),
`PRODUCT_BUNDLE_IDENTIFIER: com.kgalligan.Reelcut.debug`, `RC_APP_NAME:
"Reelcut Debug"` and `RC_PROJECT_HANDLER_RANK: Alternate`; `CFBundleName`
and `CFBundleDisplayName` read `$(RC_APP_NAME:default=Reelcut)` and the
Reelcut Project type's `LSHandlerRank` `$(RC_PROJECT_HANDLER_RANK:default=Owner)`;
"Build Rust Core" runs every build (`basedOnDependencyAnalysis: false`).
Release and Distribution are untouched. `Makefile`: `DEBUG_APP_PATH`, `make
app-debug` (`rust project`, then `xcodebuild -configuration Debug …
COMPILER_INDEX_STORE_ENABLE=NO build`), and `proof_app.py --selftest` in
`make test` before `proof_defaults.py`. `tools/proof/proof_app.py` (400
lines): `RC_PROOF_APP`, `config`, `bundle`, `binary`, `domain`,
`require_fresh`, `require_running_fresh`, `running_verdict`, `inputs`, the
`launch` and `check` commands, the selftest and three mutants. `mcp.py`:
`launch` checks the binary first (and stops its child if the new client is
refused), `MCP()` checks the instance once per socket and pid,
`scratch_socket()` records `proof_app.domain()`, and `_rehome`.
`defaults_proof.py`: `--app` defaults to `proof_app.bundle()`, R1 and R2
guard and name the app's own domain, row G6 (child `write-rehomed` under
`RC_PROOF_APP=release`) and mutant `no-rehome`; `no-compare` and `no-exit`
now also fail G6, which their mechanism reaches. `proof_defaults.py`: the
docstring and P3's `com.kgalligan.Reelcut.debug`. `phase8_proof.py`'s
`BUNDLE_ID` reads its binary's bundle. `tree_copy.build_app`. The 32
scripts' default app comes from `proof_app` (agent_socket_proof,
assistant_session_proof's `APP_PATH` and so the seven that read it,
clip_catalog_proof, clip_inspector6_proof, cloud_captions_proof,
codec_import_proof, container_import_proof, defaults_proof,
export_cancel_proof, extreme_time_proof, frame_grid_proof,
graphic_prop_action_proof, graphics_files_proof, graphics_inspector_proof,
graphics_menu_proof, graphics_path_proof, graphics_playback_samples,
graphics_prefetch_proof, graphics_proof, graphics_store_proof,
hevc_alpha_proof (its build-tree check accepts Debug), mcp_proxy_proof,
op_argument_proof, op_catalog_proof, paste_graphic_proof, phase8_proof,
recording_proof, screens, word_captions_proof, word_looks_proof,
word_looks_sheet_proof; clip_catalog, op_argument and op_catalog take a
socket, so theirs is the docstring recipe, now `proof_app.py launch`;
mixed_audio_proof takes a socket too), and the 17 tree-copy builders go
through `tree_copy.build_app`, which prints the target and its seconds.
The default stays Release.

**The three unproven Xcode facts.**
- `:default=` in Info.plist EXPANDS. The Debug bundle reads
  `com.kgalligan.Reelcut.debug`, "Reelcut Debug" twice and the Reelcut
  Project type's `LSHandlerRank` `Alternate` (the five media types stay
  Alternate). Release's and Distribution's built `Info.plist` are
  byte-identical to the copies taken from HEAD's builds before the edit
  (`cmp`, after `make app` and again after the final `make dist`), and
  `-showBuildSettings` for Release and Distribution is identical to HEAD's
  but for xcodebuild's own timestamped log lines; Debug's differs by exactly
  `ENABLE_DEBUG_DYLIB`, `PRODUCT_BUNDLE_IDENTIFIER` and the two `RC_` settings.
- The JXA LaunchServices query answers without launching anything:
  `NSWorkspace.URLForApplicationToOpenURL` for `work/b88/x.reelcut` is
  `/Applications/Reelcut.app` while the Debug bundle is among the registered
  candidates (`URLsForApplicationsToOpenURL`). No manual-checks row is owed.
- A no-op `make app-debug` DOES rewrite CodeResources: after `touch
  core/Cargo.toml` the app was refused naming that file, and the next `make
  app-debug` (2.3 s) advanced the marker and `check --app debug` passed. The
  writer is Write Agent Catalog's `codesign -s - -f "$exe"`, which re-seals
  the bundle (measured on a scratch copy: signing the executable alone
  rewrote CodeResources); a no-op build runs no Xcode CodeSign step.

**Finding: the marker is written before the catalog writer runs.** The spec
took CodeResources to be written only by Xcode's CodeSign after every
script phase. In fact Write Agent Catalog signs the executable, which
re-seals the bundle, and only then runs the writer. So a build that fails in
the catalog writer (its exit, or a `Reelcut: ` parity line) leaves a fresh
marker, and `proof_app` would pass it. Failures in Swift, the link, Build
Agent Helper and Build MCP Proxy all happen before that step, so they leave
the marker old (selftest F4). A proof's own instance still logs the parity
lines, which every proof checks. The same re-seal is what makes the no-op
rebuild advance the marker, so signing a copy of the executable instead
would turn `touch` into a refusal that never clears. Closed in this phase:
the step removes the marker on any failure after it starts (an `EXIT` trap
in `project.yml`); a tree copy whose writer was forced to fail was refused
as `no complete build`, and the no-op `make app-debug` after `touch
core/Cargo.toml` still cleared the refusal.

**Finding: a no-op build shipped an app without its entitlements
(pre-existing, fixed in this phase).** After the review's fixes a second
`make dist` with nothing changed failed dist_check D14 ("the entitlements
do not parse"). Xcode's CodeSign task does not see Write Agent Catalog
re-sign the executable and rewrite `agent-catalog.json`, so a build where
nothing else changed skips it, and the bundle kept the step's ad-hoc
signature: no entitlements (no `audio-input`, so no microphone) and a seal
that `codesign --verify --deep --strict` rejects (`file modified:
…/agent-catalog.json`). It is HEAD's: a `tree_copy` copy of 724250e with
HEAD's `project.yml`, `Makefile` and `VERSION` passed its first `make dist`
(161 s, 24/24 and 16/16), and the second (5 s) failed D14 with both apps
unverifiable. The implementer's two `make dist` runs passed only because
each relinked Distribution; in both, the Release build had run no CodeSign
task. Fixed in `project.yml`: after the writer succeeds the step signs the
bundle as Xcode's task does (`$EXPANDED_CODE_SIGN_IDENTITY`, `-o runtime`
when `ENABLE_HARDENED_RUNTIME`, the processed `$TARGET_TEMP_DIR/
$FULL_PRODUCT_NAME.xcent`, `--generate-entitlement-der`, `--timestamp=none`
ad hoc and `--timestamp` otherwise, as Build MCP Proxy does), and it
declares that `.xcent` and the built `Info.plist` as inputs, only to
order it after them. Measured: `make dist` twice (6 s, 5 s, no CodeSign
task) 24/24 and 16/16 each; `make app` twice, Release entitlements
`audio-input` plus `get-task-allow` as Xcode signs them; all three apps
pass `codesign --verify --deep --strict`; a cold `make dist` in a copy of
the fixed tree (160 s) and an `xcodebuild archive` of it as the publish
workflow runs it, ad hoc (77 s, published_check 16/16), where Xcode's own
CodeSign still signs last. The Developer ID branch of the step is not run
here (no certificate); Build MCP Proxy signs the same way in that workflow.

**Measured** (load in brackets): `make app-debug` cold 18 s (12.8 → 13.3);
no-op 2.6 s (4.9); a one-line Swift comment 6.5 s (4.3; one SwiftCompile
batch); a top-level `func` added to `ReelOps.swift` 7.2 s (4.3; 14 batches);
a comment in `reelcut_core.h` 10.5 s (4.2 → 4.7); a bare `xcodebuild
-configuration Debug` after a `core/src` comment 11.2 s, cargo compiled
`reelcut-core` (1.1 s) and the `.a` and the executable were newer than the
edit. `make app` after the same one-line Swift comment 73.0 s (4.7 → 4.1);
`make app` 75 s and 73 s; `make dist` 79 s and 74 s. A tree-copy mutant,
`graphics_files_proof.py --mutant rename-unreconciled`: 87 s whole with
`make app` (85 s build, load 4.5 → 11.4) against 20 s with `RC_PROOF_APP=debug`
(`make app-debug` 17 s, load 11.4 → 13.4). `proof_app.py check` 0.05 s over
504 inputs; `MCP()` 0.27 s with its two `lsof` reads and the `ps`
(`socket_pid` plus `require_running_fresh` 0.15 s).

**Verified.**
- `proof_app.py --selftest` 15/15 `PASS`; `--mutant exe-marker` (F3 F4),
  `md-counted` (F5) and `exe-mtime-running` (R1 R2) each `MUTANT PASS`.
- The launcher: `launch --app debug` came up in 1.2 s with no `Reelcut: `
  line, guarded `com.kgalligan.Reelcut.debug`, and its `tools/list` (95
  tools) is byte-equal to the Release instance's that `RC_PROOF_APP=release
  … launch` started. After `touch app/Sources/ActionBands.swift`,
  `mcp.launch` and the launcher refused naming that file, its mtime and `make
  app-debug`; `MCP()` on the running instance refused with "relaunch pid …
  after `make app-debug`", and still did after the rebuild.
- `defaults_proof.py` 11/11 on Release (G6 status 3, the re-home line, and
  `DEFAULTS MOVED in com.kgalligan.reelcut.defaults-proof` last); `--app
  build/Build/Products/Debug/Reelcut.app --only C0,G1,G6,R1` 4/4, R1
  guarding `com.kgalligan.Reelcut.debug`; `--mutant no-rehome` `MUTANT PASS`
  (G6 alone); `no-compare` and `no-exit` re-run on the new expected sets,
  each `MUTANT PASS`. `proof_defaults.py --selftest` 10/10 (P3 with seven
  names). `tree_copy.py --selftest` 5/5.
- `graphics_files_proof.py --mutant rename-unreconciled` through
  `build_app`: `MUTANT PASS` on `make app` and on `make app-debug`.
- **Full:** `make test` exit 0 in 122 s (load 8.1 → 19.3, powermode 0):
  cargo 100 `ok`, 0 failed; lane 18/18; prompt 14/14; prices 27/27; budget
  23/23; inventory 5/5; spec index 141/141; `swift_build.py --selftest`
  10/10; `proof_app.py --selftest` 15/15; proof_defaults 10/10. `make app`
  exit 0 (Release fresh by `check`); `make dist` exit 0, dist_check 24/24,
  published_check 16/16. `make lint` and `make typecheck` were not re-run:
  no Rust, Swift or TypeScript file is changed (the timing rows' edits were
  restored byte for byte).

**Owed to phase 3.** The flip of `DEFAULT`, `release_only` pins, and the
descriptive "`make app`" sentences in the converted proofs' docstrings and
instrument messages (a copy's build is `build_app`'s choice); the README's
launch recipe under "Building".

