# The rename: Reelcut becomes Frame Job (road map "rename")

- **Status:** Built and closed 2026-10-13. Worked in `~/devel/reelcut-rename` on branch `rename`, each phase gated there and merged into main alone (NM-9):
  - R0, the plan: the road map, NM-1…NM-11, the 39 amendments, `designs/frame-job/` (`869b5e2`)
  - R1, the code in one phase: the app, the build, the crates, the MCP surface, the proof tooling and the residue check (`5f7f1d3`)
  - R2, the mark and the icon (NM-11) (`9dfbf63`)
  - R3, the documents (`4df3128`)
  - R4, the close: the repository's name in the documents, this record (the commit that moved this record to `archive/`)
- **Original:** `archive/rename.md` is the full record. It has no section numbers, so it is cited by section name: "orig R1" is its "R1 — the record" section.
- **Spec decisions:** NM-1..NM-11 in spec §11 (`designs/spec/11-decisions/rename.md`). They stay binding, and where the original words them differently, §11's text wins:
  - NM-1: the product is Frame Job; every spelling of the old name in the product, the build, the tooling and the live documents changes, history does not; "Reelcut" in an existing decision's prose names the product.
  - NM-2: the spelling: "Frame Job" for people, `FrameJob` and `framejob` for identifiers, `FRAMEJOB_*` macros, `FrameJob.dmg` where a space breaks; the generic `Reel*` names, `rc_`, `RC_*`, the workflow file's name and `RC_FORMAT_VERSION` kept.
  - NM-3: the bundle and the document: `Frame Job.app` / `com.kgalligan.FrameJob`, `Frame Job Debug.app` / `com.kgalligan.FrameJob.debug` (Debug's own `PRODUCT_NAME`, `RC_APP_NAME` removed), module `FrameJob` pinned, `.framejob` and `com.kgalligan.framejob-project`, the entitlements file, the DMG.
  - NM-4: the folders and paths: `~/Library/Application Support/Frame Job/` (its `Rewrapped/`, presets, spend files, keys and `Agent/agent.sock`), `~/Movies/Frame Job Recordings/`, the proofs' `Frame Job Proofs/` ledger, the temporary `FrameJob/` root.
  - NM-5: what other programs and people read: the MCP server `framejob`, the helpers `framejob-mcp` and `framejob-agent`, the user-agent, the launch log, `<framejob_context>`, `include_framejob_windows`, log lines, quoted sentences, pasteboard types.
  - NM-6: the internal names: the crates, the header and bridging header, `FRAMEJOB_DEV_TOOLS`, the `framejob_*` shaders, `FrameJob*` defaults keys and notifications, queue, thread and Metal labels.
  - NM-7: no migration code; two guards only: `budget.py` refuses every paid request while the old `Reelcut Proofs/` folder exists, before writing anything under the new one, and the proof tooling never touches the old or new app domains while it sweeps both probe prefixes.
  - NM-8: the residue check, `tools/proof/name_residue.py` in `make test`: every `reelcut` line or path outside the kept history, the kept pointers and the pinned per-file counts fails.
  - NM-9: five phases, R0–R4, the code in one (R1); each gated in the `rename` worktree and merged into main alone; the repository and folder renames last, on the owner's OK.
  - NM-10: the Rasterize side: `agent/src` changes exactly three lines, the shared user-agent becomes `framejob-agent`, and the same diff is recorded for kpgalligan/rasterize, never written from here.
  - NM-11: the mark and the icon: the AppIcon set becomes `designs/frame-job/`'s; `BrandMark` draws `frame-job-icon.svg` without its tile, and the wordmark reads "Frame Job".

## Context

On 2026-10-12 the owner said "'Reelcut' is a terrible name from a trademark perspective. The new name will be 'Frame Job'", and that the rename cuts very deep. He chose four things: rename everything that spells the old name in any case and keep the generic `Reel*` names, `rc_` and `RC_*`; the spelling "Frame Job" for people and `FrameJob` / `framejob` for machines; no migration code, the old folders moved by hand; and the work now, phase by phase, in a worktree, each phase gated and merged into main alone. He supplied the new icon and mark (`designs/frame-job/`). R0's inventory counted 4,926 lines in 662 files spelling the old name at `98f0ee3`. The GitHub repository was renamed `kpgalligan/framejob` on 2026-10-13, on the owner's OK. (orig "Goal", "The owner's choices", "Inventory")

## Decisions

- **The code, the build, the tooling and the MCP surface in one phase (R1).** Every proof finds the app by its product path, socket, defaults domain and tool names, so any split leaves every proof broken between the halves. The mark (R2) and the documents (R3) could follow because nothing drives the app through them. (NM-9; orig "Goal", "R1 — the code, in one phase")
- **One spelling exception: `FrameJob.dmg`.** GitHub rewrites a space in a release asset's name to a dot, so the asset is spelled without it; the DMG's volume and the release's title keep "Frame Job". (NM-2; orig "The spelling (NM-2)")
- **`PRODUCT_MODULE_NAME: FrameJob` pinned at the target.** With `PRODUCT_NAME` "Frame Job" (and "Frame Job Debug"), Xcode derives `Frame_Job` / `Frame_Job_Debug`, and `NSDocumentClass: FrameJob.ProjectDocument` would name a class that does not exist, so no document would open. Debug's name is now its own `PRODUCT_NAME`; `RC_APP_NAME` is gone. (NM-3; orig "The traps" 1, 2)
- **No migration, and one guard where a silent new start costs money.** Nothing reads an old folder, key, domain or the `.reelcut` extension. `budget.py`'s `unmoved` refuses every paid request while `~/Library/Application Support/Reelcut Proofs/` exists, naming the guarded `mv`, before it makes a folder, opens the ledger or writes an event, because a folder it made would make the owner's `mv` nest the old one inside it and the month would restart at $0. The proof tooling refuses both the old and the new app domains and sweeps both probe prefixes. (NM-7; orig "The traps" 5, 11)
- **The residue check, with exact pins.** `tools/proof/name_residue.py` runs in `make test` and as `make gate`'s `names` step. A file that must keep old spellings is pinned at its EXACT count of matching lines, so one line over or under fails; the `ge-count` mutant (the pin a ceiling) fails S4, and `no-untracked` fails S2. History is kept whole by `HISTORY`, and the pointers that stay true by `KEPT_PATTERNS` (issue citations `kpgalligan/reelcut#N`, archived files' names, the two outside paths). (NM-8; orig "R1 — the code, in one phase", "R1 — the record" Deviations)
- **History keeps the old name.** `archive/`, `designs/adr/`, the design handoffs and the brief, `.dupscan/`, §11's decision text (amended only by appended "Amended by NM-n" paragraphs, 39 of them) and the proof README's recorded results. R3 kept 200 of the proof README's 469 counted lines byte for byte by six rules: (a) a result table's row, (b) a block or quotation of what a run printed, (c) a past run's artefact, (d) a sentence reporting what a past run printed or measured, (e) an old tree's path, (f) a pre-MC4 launch line, plus one line naming a handoff folder. (NM-1; orig "R0 — the record", "R3 — the record" "The proof README's kept lines, by rule")
- **Old-tree instruments ask the tree for its names.** The proofs that build old `app/Sources` (the meter and welcome comparisons, the cloud captions baselines, the archive builders) call `reference_build.tree_names(tree)`, which answers the old set when the tree has the old bridging header and the new set otherwise, and translate `FRAMEJOB_DEV_TOOLS` to the tree's own flag. `tree_shader(tree, text)` names the current `Compositor.metal`'s entry points as an old tree's Swift asks for them. The harness pins every defaults key under both names, and `mcp.wait_listening` accepts the old ready lines for `grading_verdict.py`'s main tree. (orig "The traps" 3, 4; "R1 — the record" Deviations)

## What it built — where it lives now

- **R0** (`869b5e2`): spec §11 NM-1…NM-11 (`designs/spec/11-decisions/rename.md`); 39 amendment paragraphs on existing decisions that name an old identifier, path or sentence; both spec indexes; `designs/frame-job/` (14 files: `AppIcon.appiconset/` with `Contents.json` and ten PNGs, `frame-job-icon-1024.png`, `frame-job-icon.svg`, `frame-job.icns`), byte for byte as the owner supplied it. Measured: the socket path for the owner's home is 75 bytes, against `MAX_SOCKET_PATH_BYTES` 103.
- **R1** (`5f7f1d3`): `project.yml` (project, target and scheme `FrameJob`, the products, `PRODUCT_MODULE_NAME`, NM-3's UTI and document types, `-lframejob_core`, `framejob-mcp`), the `Makefile` (`APP := FrameJob`, quoted product paths, `-D FRAMEJOB_DEV_TOOLS`, `name_residue.py --selftest` and `name_residue.py` last in `make test`), the publish workflow's contents, `.gitignore`; `app/Bridging/FrameJob-Bridging-Header.h` and `core/include/framejob_core.h` by `git mv`; the crates `framejob-core` and `framejob-mcp` (both `Cargo.lock`s rewritten by `cargo build`); every spelling in `app/Sources` but `BrandMark.swift`; `agent/`'s package, lock, build script, `update.py` and NM-10's three lines; every file in `tools/` but the proof README (`proof_app.py`'s `PRODUCTS` and `executable()`, `reference_build.py`'s `TreeNames`, `tree_names`, `tree_defines`, `tree_shader`, `gate.py`'s `names` step, `budget.py`'s `unmoved`, `proof_defaults.py`'s both-name refusals, `stale_registrations.py`'s S4, the new `name_residue.py`); `designs/screens/`; `docs/graphics-api.md` and `.d.ts`; NAME-1 in `docs/manual-checks.md`. Measured: `make gate` PASS; `make dist` D1–D27 and `published_check.py` 15/15 over "Frame Job.app"; on Release `defaults_proof.py` 11/11, `debug_release_proof.py` 10/10, `mcp_proxy_proof.py` 14/14, `agent_socket_proof.py` 17/17, `spend_proof.py` 21/21, `screens.py` 36/36, `recording_proof.py --no-screen` 151/151; the argument gate refuses `include_reelcut_windows` by name.
- **R2** (`9dfbf63`): `BrandMark.draw(in:)` draws `frame-job-icon.svg` without its tile, every coordinate as the SVG writes it (`designBox` 824, `tileOrigin` 100); the wordmark "Frame Job", `clearSpace` the constant 38 so the welcome column's height does not move; the icon set copied in byte for byte; `01-welcome.md`; NAME-2; `recording_probe.py`'s section 6 leaves the lockup's rows out of "above the band". Measured: `recording_probe.py --only welcome` 35/35; `screens.py --compare` against R1 36/36 with `01-welcome` differing only in the lockup; the Release `Assets.car` holds exactly the ten new `icon_*` renditions.
- **R3** (`4df3128`): `README.md` (37 lines), `CONTEXT.md`, `designs/spec/` (every file kept its line count), `11-decisions/README.md`'s Files table, `docs/manual-checks.md` (65 lines), the proof README's how-to (269 lines rewritten, 200 kept) and its "**Names in records.**" paragraph; the CLAUDE.md prose as an edit script the orchestrator applied. Measured: `make gate` PASS in 73 s.
- **R4** (the commit that moved this record to `archive/`): `README.md`'s release URL (`kpgalligan/framejob/releases/latest/download/FrameJob.dmg`) and `08-repo-layout.md`'s root folder `framejob/`; the §11 file's intro rewritten for the closed road map and its four citations of it repointed to this record and `archive/rename.md`; `budget.py`'s refusal and docstring cite this record's hand steps; `name_residue.py`'s R4 pins and its `designs/rename.md` history entry gone; this record, the `git mv` and its `archive/INDEX.md` row; the root `CLAUDE.md` edits (the issue-tracker line, the agent note's citation, this record's entry in "Where to look") as a script the orchestrator applies.

## The Rasterize side (NM-10)

The three lines R1 changed in `agent/src`, recorded for kpgalligan/rasterize to apply (orig "The Rasterize side (NM-10)"):

```diff
--- a/agent/src/main.ts
+++ b/agent/src/main.ts
@@ -6 +6 @@
-// and Reelcut: a change is one diff applied to both, and whatever differs
+// and Frame Job: a change is one diff applied to both, and whatever differs
--- a/agent/src/priceTable.test.ts
+++ b/agent/src/priceTable.test.ts
@@ -29 +29 @@
-const scratch = mkdtempSync(join(tmpdir(), "reelcut-prices-"));
+const scratch = mkdtempSync(join(tmpdir(), "framejob-prices-"));
--- a/agent/src/priceTable.ts
+++ b/agent/src/priceTable.ts
@@ -213 +213 @@
-        headers: { "user-agent": "reelcut-agent" },
+        headers: { "user-agent": "framejob-agent" },
```

## Known limits

- **No migration.** Old preferences, Screen Recording and Microphone grants, Launch Services registrations, the support folder, the proofs' ledger, recordings and `.reelcut` packages look gone until the owner's hand steps move or remove them; a `.reelcut` opens only renamed to `.framejob` (the format is unchanged, no `RC_FORMAT_VERSION` bump).
- **The README's download link answers only after the next publish.** The newest release, v0.2.5, has the asset `Reelcut.dmg`; `FrameJob.dmg` exists from the next push to `publish`.
- **Rasterize differs by NM-10's three lines** until it takes them.
- **A pin can hide a swapped line** (NM-8): a counted file that loses one old-name line and gains another passes.
- **Issue citations `kpgalligan/reelcut#N` rely on GitHub's redirect** from the old repository name.
- **The branches `worktree-side-work` and `worktree-sign-publish` carry the old names**; rebasing them onto R1 is the owner's (or the sessions he runs in them).

## Open items

Filed, each `ai-drafted` and `low-priority`:
- #284: `grading_spike --check --tree` fails KA at its default base 5d04e47 (orig "R1 — the record" Owed).
- #285: the peaks cache is not deterministic: the same media gives different peaks files (orig "R2 — the record" Measured).
- #286: `Theme.swift`'s brand inks' comments are stale.

Drafted at the close and filed at the close by the orchestrator:
- kpgalligan/rasterize#654: take Frame Job's three `agent/src` lines (NM-10).
- #287 (`ready-for-human`): the owner's hand steps below, and the two old-named branches.

Person checks: NAME-1 (Finder opens a `.framejob` with Frame Job; the Debug app stays the Alternate) and NAME-2 (the Dock icon, the About panel and the document icon) in `docs/manual-checks.md`.

## Owner's hand steps

Done 2026-10-13:

```sh
gh repo rename framejob -R kpgalligan/reelcut
git -C ~/devel/reelcut remote set-url origin https://github.com/kpgalligan/framejob.git
```

Steps 1–10, the original's, verbatim and with its numbering (`budget.py`'s refusal cites step 3). Run them BEFORE step 11: step 6 `cd`s into `~/devel/reelcut`, whose local-scope Claude Code entry is keyed by that path. **Every folder move is guarded**, because a single Frame Job launch creates `~/Library/Application Support/Frame Job/` (MC-1's socket folder), and a bare `mv` onto an existing folder nests the old one inside it:

```sh
# 1. Quit every Reelcut and every Frame Job (Debug and Release).

# 2. The support folder (keys, spend ledger, price cache, presets, Rewrapped copies).
[ -e "$HOME/Library/Application Support/Frame Job" ] && echo "$HOME/Library/Application Support/Frame Job exists: merge by hand" || mv "$HOME/Library/Application Support/Reelcut" "$HOME/Library/Application Support/Frame Job"

# 3. The proofs' ledger — before any paid proof; budget.py refuses until it is done (NM-7).
[ -e "$HOME/Library/Application Support/Frame Job Proofs" ] && echo "$HOME/Library/Application Support/Frame Job Proofs exists: merge by hand" || mv "$HOME/Library/Application Support/Reelcut Proofs" "$HOME/Library/Application Support/Frame Job Proofs"

# 4. Optional: the recordings.
[ -e "$HOME/Movies/Frame Job Recordings" ] && echo "$HOME/Movies/Frame Job Recordings exists: merge by hand" || mv "$HOME/Movies/Reelcut Recordings" "$HOME/Movies/Frame Job Recordings"

# 5. Optional, per project to keep: rename the package (the format is unchanged).
mv X.reelcut X.framejob

# 6. Claude Code: remove the stale entries, add the new one.
cd ~/devel/reelcut && claude mcp remove reelcut -s local   # road map 14's stale http://127.0.0.1:4817/mcp
claude mcp remove reelcut -s user                          # only if present
claude mcp add --scope user framejob -- '/Applications/Frame Job.app/Contents/Helpers/framejob-mcp'

# 7. Grants: forget the old app's, then grant Frame Job on first use.
tccutil reset ScreenCapture com.kgalligan.Reelcut
tccutil reset Microphone com.kgalligan.Reelcut
tccutil reset ScreenCapture com.kgalligan.Reelcut.debug
tccutil reset Microphone com.kgalligan.Reelcut.debug

# 8. The old installed app, if present.
rm -rf /Applications/Reelcut.app

# 9. Old Launch Services registrations: list them, then unregister if wanted.
python3 tools/proof/stale_registrations.py
python3 tools/proof/stale_registrations.py --unregister

# 10. Optional: old preferences (not carried: the keys were renamed, NM-6).
defaults delete com.kgalligan.Reelcut
defaults delete com.kgalligan.Reelcut.debug
```

Then, guarded like steps 2–4, from a plain terminal: first quit every Claude Code session
running in `~/devel/reelcut`, its `.claude/worktrees/` or `core/` (a live session would lose
its folder and recreate the old memory folder, splitting the memory). The rename worktree
`~/devel/reelcut-rename` was removed at the close, so step 11 repairs the two worktrees left;
repair only those `git worktree list` still shows.

```sh
# 11. The repository's folder, and the worktrees whose .git files hold the old path.
[ -e "$HOME/devel/framejob" ] && echo "$HOME/devel/framejob exists: stop" || { mv "$HOME/devel/reelcut" "$HOME/devel/framejob" && git -C "$HOME/devel/framejob" worktree repair "$HOME/devel/framejob/.claude/worktrees/side-work" "$HOME/devel/framejob/.claude/worktrees/sign-publish"; }
git -C "$HOME/devel/framejob" worktree list   # three rows, none prunable

# 12. Claude Code's memory folder for the repository (and, optional, the one for sessions started in core/).
[ -e "$HOME/.claude-personal/projects/-Users-kevingalligan-devel-framejob" ] && echo "$HOME/.claude-personal/projects/-Users-kevingalligan-devel-framejob exists: stop" || mv "$HOME/.claude-personal/projects/-Users-kevingalligan-devel-reelcut" "$HOME/.claude-personal/projects/-Users-kevingalligan-devel-framejob"
[ -e "$HOME/.claude-personal/projects/-Users-kevingalligan-devel-framejob-core" ] && echo "$HOME/.claude-personal/projects/-Users-kevingalligan-devel-framejob-core exists: stop" || mv "$HOME/.claude-personal/projects/-Users-kevingalligan-devel-reelcut-core" "$HOME/.claude-personal/projects/-Users-kevingalligan-devel-framejob-core"

# 13. The gate in the new folder, forced: every stamp was taken under the old path.
cd "$HOME/devel/framejob" && make gate GATE_ARGS=--force
```

Also the owner's: rebase or delete the branches `worktree-side-work` and `worktree-sign-publish`, which carry the old names.

## Where to look in the original

- "Goal" and "The owner's choices": the owner's words and his four choices, verbatim.
- "The spelling (NM-2)": the spelling table and what is kept everywhere.
- "Inventory": the command, the twenty category rows at `98f0ee3`, the sub-counts in `app/Sources`, the paths, the generated and regenerated files, the files at the cap, the builders of an old tree.
- "The traps": the thirteen ways R1 could build and still break, and each answer.
- "Phases" and "Verification per phase": what each phase was to do and how it was to be checked.
- "The owner's hand steps": the steps as given after R1, and the renames as planned for R4.
- "The Rasterize side (NM-10)": the diff and why the user-agent is shared.
- "R0 — the record" … "R4 — the record": what landed, the deviations, the measured rows (with each command), the mutants, and what each phase owed.
