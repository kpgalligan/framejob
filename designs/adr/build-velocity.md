# Build velocity (issue batch B88)

- **Status:** Built and closed 2026-10-08. Each phase was one litecode pipeline with its own review:
  - 1a, `make typecheck` in batch mode and the probe builder (`edeba18`)
  - 1b, every proof through the probe builder, and its guard (`724250e`)
  - 2, the Debug app, its identity and the stale refusal (`6e74f26`)
  - 3, Debug against Release, the qualification, the default flips to Debug (`ab24de4`)
  - 4, `make gate`, the Verification rule, the close (uncommitted when this was written)
- **Original:** `archive/build-velocity.md` (623 lines) is the full record. It has no section numbers, so it is cited by section name: "orig Record ▸ Phase 2" is its "Record" section's phase 2 entry.
- **Spec decisions:** V-4 and V-5 in spec §11 (`designs/spec/11-decisions/dev-tools.md`). They stay binding, and where the original words them differently, §11's text wins:
  - V-4 (amends V-1): the edit loop and the mutant tiers drive a Debug app; the run a phase records, the gate's build and every `release_only` proof are Release. Risk accepted: an optimiser-only defect is seen only by the recorded run.
  - V-5: the Debug build is its own app, "Reelcut Debug", `com.kgalligan.Reelcut.debug`, with its own defaults domain and an Alternate `.reelcut` handler, through Debug-only settings read with `:default=`, so Release and Distribution keep identical settings and Info.plist bytes. `PRODUCT_NAME` stays `Reelcut`.
  - W-8 is why `make typecheck` has exactly four warnings, which the gate now holds it to.

## Context

Verification was slow where agents paid for it most. `make typecheck` took 81 s in one serial frontend. Each of 71 proofs and probes, and the offscreen harness, carried its own serial `swiftc` line over all of `app/Sources` (about 110 s each), judged stale by mtime, so `make test` after a one-line Swift comment took 307 s and one `graphics_inspector_proof.py` mutant 112.5 s. The only app was Release (`make app`, 73 s after a one-line edit), nothing refused a proof against an app older than its sources, and the Full tier was four commands an agent re-ran by hand. The owner's rulings: one mutant per new decision (usually 3–8; more than 10 only with a written reason), Debug while working with Release built and checked at each phase's end, no override variable for the stale refusal, and a gate that runs its steps serially. Nothing in the shipped product was to change. (orig Goal, Decisions)

## Decisions

- **One probe build line, parallel by `-j`.** A probe, a proof or the harness compiles app sources only through `tools/proof/swift_build.py`, whose argv is spelled once (`_argv`), with `-j <cores>`. `-j` keeps the serial line's `__TEXT,__text` byte-for-byte; batch mode with an output file map (E1) linked in 0.66× the time but changed the machine code, so it was not adopted. `make typecheck` and `swift_build.py typecheck` link nothing and use batch mode. (orig Decisions; Record ▸ Phase 1a "Machine code", "E1")
- **Content, never mtime.** A build is reused only when a sha256 over every input matches a cached entry whose binary still hashes to its manifest. The inputs are the helper, the toolchain and SDK, the argv less `-o`/`-j`, the output's file name, every source, the bridging header and its quoted includes, the staticlib, each link input, four toolchain variables and the tree's path. (orig Decisions)
- **Linked under the caller's own file name.** The linker makes the file name the ad-hoc signature's identifier, and LaunchServices keys a bare binary's recent documents by it. Phase 1a linked every binary as `binary`, so they shared one recents list, which moved the welcome window's lockup by 93 px in `recording_probe.py` 6d. Selftest row B6 guards it. (orig Record ▸ Phase 1b "Fix pass")
- **A guard, not a convention.** `swift_build.py --selftest` G1 fails `make test`, naming the file, when a `tools/proof` script outside the allow-list (`swift_build.py`, `reference_build*.py`, the closed spikes) holds a swiftc argv and the bridging header. It caught phase 4's own `gate.py` on the gate's first run. (orig Record ▸ Phase 1b, ▸ Phase 4 "Deviations")
- **A built app is judged by its `_CodeSignature/CodeResources`**, never its executable's mtime, against the newest input of its own tree (a `*.md` but `docs/graphics-api.md` is not an input). A running instance is judged by its start. The refusal names the file, its time and the `make` target, and there is no override. Write Agent Catalog's `codesign -s - -f` re-seals the bundle before the catalog writer runs, so that step removes the marker on any failure after it starts (an `EXIT` trap). (V-5's companion; orig Record ▸ Phase 2 "Finding: the marker…")
- **The defaults guard follows the app under test.** `scratch_socket()` records `proof_app.domain()`. A socket it made that an instance of another bundle then holds is re-homed to that bundle's domain (`defaults_proof.py` G6). (orig Record ▸ Phase 2)
- **Write Agent Catalog signs the bundle as Xcode does.** A no-op build skipped Xcode's CodeSign and shipped the step's ad-hoc signature: no entitlements, so no microphone, and a seal broken by the catalog written after it. This was pre-existing and found in phase 2. The step now re-signs with the processed `.xcent`, the runtime flag and the identity Xcode would use. dist_check D25–D27 (phase 3) read Release's entitlements as an exact set and both seals. (orig Record ▸ Phase 2 "Finding: a no-op build…", ▸ Phase 3)
- **Debug in the loop, Release for the record** (V-4). An unset `RC_PROOF_APP` means Debug. `debug_release_proof.py` shows the two builds answer alike (parsed), render byte-for-byte alike and export alike but for the movie header's times. A proof that needs a TCC grant or measures time is `release_only`: `recording_proof.py` and `graphics_proof.py`. The 18 app-driving proofs changed since B80 each kept their full score on Debug. (orig Record ▸ Phase 3)
- **One gate over the Full tier.** `make gate` runs typecheck, fmt, lint, test and app serially and stops at the first failure. It skips a step whose files' content and tools are byte-identical to its last pass, and stamps a pass only when the hash after the step equals the hash before it. Its typecheck passes only with exactly the four baseline warnings, by file and message. Its app step also runs dist_check's D25 and D26 over the Release app, so the gate's own build is checked for the no-op-signing defect without the Distribution build. (orig Record ▸ Phase 4)
- **The Verification rule is the root `CLAUDE.md`'s "Verification" section.** The loop is targeted. The Full tier is `make gate`, once, in the foreground. The recorded run is on Release. Mutants number one per new decision, and a fix pass re-runs only what it touched. That the recorded run is on Release is a RULE, not a mechanism: nothing can see which build a recorded run drove. (orig Record ▸ Phase 4 "V-4 against the code")

## What it built — where it lives now

- The builder: `tools/proof/swift_build.py` (469; selftest K0, K1, B1–B6, G0, G1), its cache `tools/proof/work/swift-build/`, and `harness/build.sh` (81) over it. 71 proofs call `swift_build.build`.
- The app choice and the refusal: `tools/proof/proof_app.py` (400; `launch`, `check`, selftest F1–F6, R1–R3, T1, E1, E2, D1, D2, C1, three mutants).
  - Wired through `mcp.py` (568): `launch`, `MCP()`, `scratch_socket`, `_rehome`.
  - Copies build through `tree_copy.build_app` (`tree_copy.py`, 336).
  - `defaults_proof.py` (725) has G6 and `no-rehome`; `proof_defaults.py` P3 refuses the Debug domain.
- The Debug identity: `project.yml` (311), the Debug config's four settings, `:default=` in Info.plist, Build Rust Core on every build, and Write Agent Catalog's trap and signing. `Makefile`: `make app-debug`.
- The equivalence: `tools/proof/debug_release_proof.py` (266; T1–T6, C0, C1, Z1, Z2). `dist_check.py` (517) D25–D27 and `dist_check_mutants.py` (279) cover the signing.
- The gate: `tools/proof/gate.py` (400; selftest H0, M1–M7, H2–H4, W0–W4, four mutants), `make gate`, and state under `build/gate/`.
- Docs: `tools/proof/README.md`'s "The probe builder", "Which app a proof drives" and "The gate"; `app/CLAUDE.md`'s "Debug and Release" paragraph; the root `CLAUDE.md`'s Commands and "Verification".

**Headline numbers** (before → after, final tree, 2026-10-08):

| Command | Before | After |
|---|---|---|
| `make typecheck` | 81 s | 3.7 s |
| `make test` after a one-line Swift comment | 307 s | 94 s |
| `make test`, nothing changed | — | 63 s |
| the edit loop's build after a one-line Swift comment | `make app` 73 s | `make app-debug` 5.3 s |
| one `graphics_inspector_proof.py` mutant | 112.5 s | 21 s |
| `make gate`, nothing changed | — | 0.4 s |
| `make gate` after a one-line Swift comment | ≈ 461 s as three commands | 173 s |

## Known limits

- **An input another session edits during a build that then succeeds is older than the marker**, so the app passes as fresh until the next edit. (accepted in the spec)
- **Debug shares `~/Library/Application Support/Reelcut/` with the real app**: the keys, the spend ledger, presets and the default socket path, where a second instance binds none. Separating them would change the product. It was offered to the owner as a choice and not taken.
- **An optimiser-only defect is seen only by the recorded Release run** (V-4's accepted risk). Recording that run on Release is a rule, not a mechanism.
- **D27 (Distribution's seal) and the rest of dist_check run only in `make dist`**, which is not a gate step. The gate's app step reads D25 and D26 alone.
- **The gate keeps one stamp per step.** Restoring an edit re-runs the steps the edit ran, even though the restored hashes equal an earlier pass's.
- **The typecheck baseline is exact.** Fixing one of the four deprecations fails the gate until `TYPECHECK_BASELINE` loses that row.
- **The app-driving proofs outside phase 3's qualification switched to Debug unchecked** (owner's ruling), e.g. the assistant_* proofs, cloud_captions_proof, phase1–6 and phase8 proofs, e1/e2, clip_inspector*. One that later fails only on Debug is pinned `release_only="<reason>"` in the change that finds it, unless the failure is an assert trap, which is a defect to fix (app/CLAUDE.md).
- **Write Agent Catalog's Developer ID branch is not run locally** (there is no certificate). The publish workflow's archive is where it runs.

## Open items

- None. Every limit above is accepted, including the unchecked proofs (owner's ruling, Known limits).

## Where to look in the original

- Goal, Phases: the five phases as planned, and the owner's rulings.
- Decisions: the bullets condensed above, as each phase left them.
- Record ▸ Phase 1a: the builder; before and after timings with load; the `__text` comparison and its control; E1's measurement.
- Record ▸ Phase 1b: the 68 scripts by name; what was not converted and why; the build shapes (`-O` WMO, `-sectcreate`); the throwaway driver over the 56; the fix pass (G1's widened markers, the `binary` signing identifier and the 93 px welcome finding).
- Record ▸ Phase 2: the three unproven Xcode facts (`:default=` expands, the JXA LaunchServices query, the no-op re-seal); the marker-before-writer finding; the no-op-build entitlements finding and its fix; `make app-debug` timings; the launcher and defaults_proof rows.
- Record ▸ Phase 3: `debug_release_proof.py`'s rows and numbers; the Q qualification table; the two `release_only` pins and graphics_proof's E2 seconds; dist_check D25–D27 and the exact-set evidence.
- Record ▸ Phase 4: the gate; phase 3's gap closed in the app step (with the scratch-copy checks); V-4 against the code; the deviations; every gate scenario; the headline timings with load.
