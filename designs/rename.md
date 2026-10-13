# Road map "rename" — Reelcut becomes Frame Job

**Opened 2026-10-13** (R0, in the worktree `/Users/kevingalligan/devel/reelcut-rename` on branch
`rename`, from `ae56899`, merged into main after its gate). The request this road map answers is
the owner's of 2026-10-12; its decisions are spec §11 NM-1…NM-11, in
`designs/spec/11-decisions/rename.md`, recorded in R0 before any rename code. Every count below
was printed by the command written beside it, at the pinned commit `ae56899`. Where this file
and an older document differ about a name, this file wins until R3 brings the documents in line.

## Goal

Rename the product from Reelcut to Frame Job everywhere it is spelled — the app, its bundle and
document, its folders, its MCP surface, the Rust crates, the build, the proof tooling and the
live documents — and leave history as it was. The code, the build, the tooling and the MCP
surface move in ONE phase (R1), because every proof finds the app by its product path, socket,
defaults domain and tool names; the mark and icon (R2) and the documents (R3) follow; R4 closes
the road map, and only then, on the owner's OK, are the GitHub repository and the local folder
renamed. Nothing migrates: the owner moves what he wants kept by hand.

## The owner's choices

**2026-10-12**, verbatim (the owner: "'Reelcut' is a terrible name from a trademark perspective.
The new name will be 'Frame Job'. It's kind of a joke. But, the rename cuts very deep, as so much
of the app is leaning on the name 'Reelcut'." New logos: `designs/frame-job/`):

> 1. Scope: rename EVERYTHING that spells Reelcut/reelcut/REELCUT — user-visible
>    strings, menus, window titles, alerts, bundle ids (Release and Debug, the
>    Debug app's name), the document extension, its UTI and type name, the Swift
>    module/target/scheme (NSDocumentClass), Application Support and
>    Recordings folder names, the agent socket path, the MCP server name and
>    the `reelcut-mcp` binary, the helper's user-agent, the Rust crate
>    `reelcut_core` / `libreelcut_core.a` / `reelcut_core.h`, the bridging
>    header, the entitlements file, `REELCUT_DEV_TOOLS`, shader function names
>    `reelcut_*`, defaults keys and notification names spelled Reelcut*, the
>    `Reelcut: ` parity-log prefix, `.xcodeproj`, Makefile, publish workflow
>    CONTENTS (never the workflow FILE's name: it owns the run counter), DMG,
>    README, CLAUDE.md files, spec sections, docs/manual-checks.md,
>    docs/graphics-api.md, designs/screens, the proof tooling (proof_app.py,
>    mcp.py, gate.py, proof_defaults.py, the pgrep pattern, every proof's app
>    paths and menu paths). KEEP the generic internal names that only contain
>    "Reel" (ReelOp, ReelProject, ReelTime, ReelCore, ReelCoreError, …) and the
>    `rc_` FFI prefix and `RC_*`/`-RC*` argument names. Leave history alone:
>    archive/, designs/adr/ (except a new ADR at the close), the design
>    handoffs designs/design_handoff_reelcut*/, recorded results in
>    tools/proof/README.md, spec §11's existing decision text (append-only:
>    "Amended by" lines plus the new decision).
> 2. Spelling: display name "Frame Job"; the app bundle is "Frame Job.app"
>    (with the space; the Debug app "Frame Job Debug.app"); technical names
>    FrameJob / framejob: com.kgalligan.FrameJob, com.kgalligan.FrameJob.debug,
>    `.framejob`, com.kgalligan.framejob-project, `framejob-mcp`,
>    `framejob_core`, MCP server name `framejob`, folders
>    "~/Library/Application Support/Frame Job/" (and "Frame Job Proofs" for the
>    proofs' ledger, "Frame Job Recordings"). The designer may propose a
>    different spelling for a site where a space breaks something (executable
>    name, Swift module name — a module name cannot hold a space), and records
>    it.
> 3. Old data: NO migration code. The owner moves the old Application Support
>    folders and the proofs' budget ledger by hand; the road map lists the
>    exact commands for the orchestrator to give him. Old .reelcut projects need
>    not open (owner, 2026-10-09: no real use yet).
> 4. Timing: now, in the worktree /Users/kevingalligan/devel/reelcut-rename
>    (branch `rename`, from main ae56899), phase by phase, each phase gated and
>    ff-merged into main by the orchestrator. Main stays usable meanwhile.

## The spelling (NM-2)

| Use | Spelling | Examples |
|---|---|---|
| Display: any sentence, title, menu, alert, label, Metal debug label, log prefix, a folder a person sees | `Frame Job` | "About Frame Job", "Frame Job ▸ Settings…", `Frame Job: ` (the parity prefix), `Frame Job agent socket listening at `, `~/Library/Application Support/Frame Job/`, `~/Movies/Frame Job Recordings/`, `…/Frame Job Proofs/spend.jsonl`, UTI description "Frame Job Project" |
| Products | `Frame Job.app`, `Frame Job Debug.app`; executables `Frame Job`, `Frame Job Debug` (follow PRODUCT_NAME) | `pgrep -f "MacOS/Frame Job"` lists both |
| CamelCase identifiers | `FrameJob` | module/target/scheme/`FrameJob.xcodeproj`, `PRODUCT_MODULE_NAME: FrameJob` (pinned: a per-config PRODUCT_NAME would otherwise derive `Frame_Job`/`Frame_Job_Debug`), `NSDocumentClass: FrameJob.ProjectDocument`, `com.kgalligan.FrameJob`, `com.kgalligan.FrameJob.debug`, `app/Bridging/FrameJob-Bridging-Header.h`, `app/FrameJob.entitlements`, defaults keys `FrameJob*` (and their `-FrameJob*` launch arguments), notification names `FrameJob*DidChange`, temp folders under `NSTemporaryDirectory()` named `FrameJob` |
| lower-case identifiers | `framejob` | `.framejob`, `com.kgalligan.framejob-project`, `framejob-core`/`framejob_core`/`libframejob_core.a`/`core/include/framejob_core.h`, `framejob-mcp` (crate, lib `framejob_mcp`, bin), `framejob-agent` (helper, package, user-agent), MCP server name `framejob`, `framejob-launch.log`, `framejob.log` (a proof's log), `<framejob_context>`, `include_framejob_windows`, shader functions `framejob_*`, queue/pasteboard labels `com.kgalligan.framejob.*`, temp-file prefixes `framejob-*`, `[framejob]` |
| UPPER | `FRAMEJOB_DEV_TOOLS`, `FRAMEJOB_CORE_H`, `FRAMEJOB_BRIDGING_HEADER_H` | |
| Exception: a space breaks it | `FrameJob.dmg` (GitHub rewrites a space in a release asset name to a dot); DMG volume name and release title keep "Frame Job" | |

**Kept everywhere:** the `Reel*` internal names (`ReelOp`, `ReelProject`, `ReelTime`, `ReelCore`,
`ReelCoreError`, `ReelOps.swift`, …), `rc_`, `RC_*` and `-RC*`, the publish workflow FILE's name
(`.github/workflows/publish.yml`: it owns the run counter, PUB-2), and `RC_FORMAT_VERSION` with no
bump — the package format does not change, so a `.reelcut` renamed by hand to `.framejob` opens.

## Inventory

**The command** (run in the worktree; `f <pathspec>…` prints files and lines matching `reelcut`
case-insensitively at the pinned commit):

```sh
cd /Users/kevingalligan/devel/reelcut-rename && f(){ echo "$(git grep -l -i reelcut ae56899 -- "$@" | wc -l) files / $(git grep -h -i -c reelcut ae56899 -- "$@" | awk -F: '{s+=$NF} END{print s+0}') lines :: $*"; }
```

| Category | Pathspec given to `f` | Files | Lines | Phase |
|---|---|---|---|---|
| Archive | `archive` | 28 | 859 | kept (history) |
| Condensed records | `designs/adr` | 28 | 113 | kept (history); R4 adds `designs/adr/rename.md` |
| The design handoffs and the brief | `designs/design_handoff_reelcut designs/design_handoff_reelcut_sharp designs/design_handoff_clip_inspector designs/clip_inspector_brief` | 31 | 266 | kept (history) |
| The duplicate scan's record | `.dupscan` | 1 | 32 | kept (history) |
| Spec §11 decision files | `'designs/spec/11-decisions/*.md' ':!designs/spec/11-decisions/README.md'` | 16 | 132 | kept; R0 appends the amendments |
| Spec §11 index | `designs/spec/11-decisions/README.md` | 1 | 19 | R0 rows; the old names in kept rows stay, as the decisions' own titles |
| The rest of the spec | `designs/spec ':!designs/spec/11-decisions'` | 18 | 66 | R3 |
| The screen catalog | `designs/screens` | 11 | 47 | R1 (its front blocks are `screens.py`'s input) |
| Docs | `docs` | 3 | 69 | R1 `docs/graphics-api.md` and `docs/graphics-api.d.ts` (bundled); R3 `docs/manual-checks.md` (R1 and R2 add rows) |
| README, CONTEXT and the five CLAUDE.md | `README.md CONTEXT.md '*CLAUDE.md'` | 7 | 112 | R3 (CLAUDE.md as edits owed); R4 the issue-tracker line |
| Build files | `project.yml Makefile .gitignore .github` | 4 | 59 | R1 |
| Bridging header | `app/Bridging` | 1 | 3 | R1 |
| Swift | `app/Sources` | 143 | 398 | R1 (but `BrandMark.swift`'s mark: R2) |
| Shaders | `app/Resources` | 2 | 23 | R1 |
| Core | `core ':!core/CLAUDE.md'` | 70 | 152 | R1 |
| MCP proxy | `mcp-proxy ':!mcp-proxy/CLAUDE.md'` | 9 | 54 | R1 |
| Graphics engine | `graphic ':!graphic/CLAUDE.md'` | 3 | 3 | R1 (tests' sample text) |
| Assistant helper | `agent` | 7 | 9 | R1 (NM-10's three lines in `agent/src`) |
| The proof README | `tools/proof/README.md` | 1 | 505 | R3 the how-to; recorded results kept |
| The rest of the tools | `tools ':!tools/proof/README.md'` | 278 | 2005 | R1 |
| **Total** | `.` | **662** | **4926** | |

The twenty category rows add up to the total row (662 files, 4,926 lines); the designer's
expected counts and R0's run agree in every row.

**Sub-counts in `app/Sources`**, each printed by
`c(){ echo "$(git grep -l -E "$1" ae56899 -- app/Sources | wc -l) files / $(git grep -h -c -E "$1" ae56899 -- app/Sources | awk -F: '{s+=$NF} END{print s+0}') lines :: $1"; }`:

| Regex | Files | Lines | What it is |
|---|---|---|---|
| `REELCUT_DEV_TOOLS` | 17 | 21 | the dev-tools flag (NM-6) |
| `"Reelcut[A-Z][A-Za-z]*"` | 22 | 42 | defaults keys and other quoted identifiers (NM-6) |
| `Reelcut[A-Za-z]*DidChange` | 7 | 9 | notification names (NM-6) |
| `com\.kgalligan\.reelcut\|"reelcut\.` | 23 | 29 | queue, pasteboard and other labels (NM-5, NM-6) |
| `reelcut_[a-z_]+` | 13 | 36 | shader function names and other snake-case names (NM-6) |
| `includeReelcut\|include_reelcut` | 10 | 29 | `record_screen`'s argument and its Swift side (NM-5) |
| `NSLog\("Reelcut\|\[reelcut\]` | 7 | 10 | log lines (NM-5) |
| `reelcut-(mcp\|agent)` | 5 | 7 | the two helpers (NM-5) |

**Paths** (`git ls-tree -r --name-only ae56899 | grep -i reelcut`): outside the history folders
only two, both renamed with `git mv` in R1 — `app/Bridging/Reelcut-Bridging-Header.h` →
`app/Bridging/FrameJob-Bridging-Header.h` and `core/include/reelcut_core.h` →
`core/include/framejob_core.h`. Every other path that matches is under `archive/` or the
handoffs, and keeps its name.

**Generated or ignored** (renamed by the build, not by `git mv`): `Reelcut.xcodeproj` (xcodegen;
`/Reelcut.xcodeproj/` in `.gitignore`), `app/Reelcut.entitlements` (written by xcodegen from
`project.yml`'s `entitlements`; ignored) and `app/Info.plist` (ignored). R1 changes the
`.gitignore` lines and `project.yml`'s paths; the stale ignored copies in a tree are removed by
hand or left (they are ignored and nothing reads them).

**Regenerated:** `core/Cargo.lock` and `mcp-proxy/Cargo.lock` each name their own root package
once (`git grep -c -i reelcut ae56899 -- '*Cargo.lock'` printed 1 for each); R1 lets `cargo build`
rewrite them after renaming the packages, never by hand.

**Replaced:** `app/Assets.xcassets/AppIcon.appiconset` (`Contents.json` and seven PNGs,
`icon_16.png`…`icon_1024.png`) by `designs/frame-job/AppIcon.appiconset` (its own
`Contents.json` and ten PNGs, `icon_16x16.png`…`icon_512x512-2x.png`) in R2.

**What stays, and why:** the `Reel*` internal names, which are generic and never spell the
product; `rc_`, `RC_*` and `-RC*`, which are the FFI's and the launch arguments' own prefixes;
`RC_FORMAT_VERSION`, since nothing in the package changes; the publish workflow's file name (its
run counter); every pointer `name_residue.py`'s `KEPT_PATTERNS` names — issue citations
`kpgalligan/reelcut#N` (GitHub redirects after the repo's rename), archived file names
(`archive/reelcut-*.md`, which keep their names), and the outside paths
`~/.claude/litecode/reelcut/…` and `~/devel/reelcut…`, which are real until the owner's renames.
R1 does not rewrite those pointers.

**Files at or over the ~600-line cap that R1 edits** (`for f in $(git grep -l -i reelcut ae56899
-- app/Sources core/src graphic/src mcp-proxy/src | sed 's/^ae56899://'); do n=$(git show
ae56899:$f | wc -l); [ $n -ge 600 ] && echo "$n $f"; done | sort -rn`): 1523
`ProjectSnapshot.swift`, 1328 `ProjectDocument.swift`, 1255 `ReelOps.swift` (exempt), 1142
`EditorViewController.swift`, 989 `ReelCore.swift`, 786 `AgentServer.swift`, 648
`Controls.swift`, 636 `AgentServer+Clips.swift`, 600 `Compositor.swift`. A substitution in any
of them adds no net line: where "Frame Job" is longer than "Reelcut" and a line overflows, the
paragraph is rewrapped within the file.

**Builders of an old tree** (the trap below): `git grep -l -E 'git", *"archive"|BASE_COMMIT|build_baseline' ae56899 -- tools/proof`
printed `tools/proof/cloud_captions_probe.py tools/proof/hdr_proof.py`; `git grep -l -E
'reference_build' ae56899 -- tools/proof` printed `README.md cloud_captions_probe.py
e1_chrome.py phase5_chrome.py recording_probe.py reference_build_selftest.py swift_build.py`;
and `git grep -l -E '"archive"' ae56899 -- tools/proof` printed `assistant_spike/assistant_spike.py
editor_keys_undo_proof.py hdr_proof.py name_field_proof.py obscure_handles_probe.py
reference_build.py space_key_proof.py text_apply_proof.py text_break_proof.py
text_edit_proof.py`. R1 reads each file in the union and routes every one that compiles old
`app/Sources` or links an old core through `tree_names`.

## The traps

Each is a way R1 could build, pass `make typecheck` and still break; R1's design names its
answer to every one.

1. **The module name.** With `PRODUCT_NAME` "Frame Job" (and "Frame Job Debug" in Debug), Xcode
   derives the module `Frame_Job` / `Frame_Job_Debug`, and `NSDocumentClass:
   FrameJob.ProjectDocument` would name a class that does not exist, so no document opens.
   `PRODUCT_MODULE_NAME: FrameJob` is pinned at the target level, for every configuration.
2. **The Debug name.** `RC_APP_NAME` goes; Debug sets `PRODUCT_NAME: "Frame Job Debug"` and
   `CFBundleName` / `CFBundleDisplayName` read `$(PRODUCT_NAME)`. Release and Distribution keep
   identical settings and Info.plist bytes (V-5).
3. **The offscreen harness is compiled against old trees too.** `tools/proof/harness/main.swift`
   (45 lines matching at the pinned commit, `git grep -c -i reelcut ae56899 --
   tools/proof/harness/main.swift`) reads the document type through
   `ProjectDocument.projectTypeIdentifier` rather than a spelled UTI, and pins every defaults key
   under BOTH its `FrameJob` and its `Reelcut` name, so a paint of an old tree (the meter and
   welcome comparisons) reads the same pins.
4. **`reference_build.py` builds old trees.** It gains `tree_names(tree: Path) -> TreeNames`, a
   frozen dataclass of `module`, `bridging`, `header`, `staticlib`, `dev_tools` and
   `project_type`, answering the old set when the tree has
   `app/Bridging/Reelcut-Bridging-Header.h` and the new set otherwise, and it translates
   `FRAMEJOB_DEV_TOOLS` in `defines` to the tree's own flag. Every other builder of an old tree
   (the lists above) uses it; none spells a name itself.
5. **The defaults guard.** `proof_defaults.py` keeps `APP_DOMAIN` read-only and refuses BOTH the
   old and the new app domains (`com.kgalligan.Reelcut`, `com.kgalligan.Reelcut.debug`,
   `com.kgalligan.FrameJob`, `com.kgalligan.FrameJob.debug`), and its sweep removes
   probe domains under both the old and the new prefixes (`com.kgalligan.reelcut.`, `reelcut.`,
   `com.kgalligan.framejob.`, `framejob.`); its selftest covers each.
6. **Stale registrations.** `stale_registrations.py` matches a Launch Services entry spelled
   `reelcut` or `framejob`, so it still finds the old app's copies after R1.
7. **Which app a proof drives.** `proof_app.py` maps each configuration to its product name and
   executable (`Frame Job.app` / `MacOS/Frame Job`, `Frame Job Debug.app` / `MacOS/Frame Job
   Debug`), and its stale refusal lists the renamed inputs (`core/include/framejob_core.h`,
   `libframejob_core.a`, `app/FrameJob.entitlements`).
8. **An absolute path.** `tools/proof/graphics_playback_samples.py` sets
   `REPO = Path("/Users/kevingalligan/devel/reelcut")`; R1 makes it repo-relative, so the folder
   rename cannot break it.
9. **The file-size cap.** A substitution in a file at or over its cap adds no net line (the list
   above).
10. **`Cargo.lock`.** Regenerated by `cargo build`, never hand-edited.
11. **The proofs' ledger.** `tools/proof/budget.py` gains NM-7's guard: while
    `~/Library/Application Support/Reelcut Proofs/` exists it refuses every paid request, naming
    the guarded `mv`, before it creates the new folder, opens the new ledger or appends any event
    to it; R1's `budget_proof.py` rows score the refusal and that nothing was created, over
    scratch homes.
12. **Space in the product path.** Every shell line that names the app quotes it (`"Frame
    Job.app"`, `"$APP/Contents/MacOS/Frame Job"`); `pgrep -f "MacOS/Frame Job"` lists Debug and
    Release alike. The Makefile's `APP := FrameJob` names the project and scheme; product paths are
    spelled quoted beside it.
13. **A renamed tool argument has no alias.** `include_reelcut_windows` becomes
    `include_framejob_windows`; the argument gate refuses the old name by name (NM-5), and the
    assistant's prompt and catalog text change with it.

## Phases

### R0 — the plan (this phase)

This file; spec §11 NM-1…NM-11 (`designs/spec/11-decisions/rename.md`); the 39 amendment
paragraphs on existing decisions that name an old identifier, path or sentence; both spec
indexes; `designs/frame-job/` added to the tree. No code, no CLAUDE.md, no issue.

### R1 — the code, in one phase

- **app/**: everything but the mark and the icon — every `Reelcut` string, key, label,
  notification, log line, queue label and shader name per NM-2…NM-6; the bridging header
  (`git mv`); `project.yml`'s name, target, scheme, products, `PRODUCT_MODULE_NAME`, bundle ids,
  UTI, document types, entitlements path, linker flags and helper build steps.
- **core/**: the crate (`framejob-core`, lib `framejob_core`), the header (`git mv`, guard
  `FRAMEJOB_CORE_H`), its tests, `format.rs`'s "update Frame Job to open it", `ffi_util.rs`'s
  fallback string.
- **graphic/**: the tests' sample text.
- **mcp-proxy/**: the crate and binary `framejob-mcp`, the server name, the launch log, its
  tests.
- **agent/**: `package.json`, `bun.lock`, `build.sh`, `prices/update.py`'s agent string, and
  NM-10's three lines in `agent/src`.
- **Build:** `Makefile` (`APP := FrameJob` for the project and scheme, quoted product paths),
  `.gitignore`, `.github/workflows/publish.yml`'s CONTENTS (the file keeps its name).
- **tools/**: everything but `tools/proof/README.md`, with the traps above; the budget guard;
  the new `tools/proof/name_residue.py` (below) added to `make test`.
- **designs/screens/**: the front blocks (`screens.py`'s input) and the prose's menu paths.
- **docs/graphics-api.md** and **docs/graphics-api.d.ts** (bundled into the app).
- **docs/manual-checks.md**: a row — Finder opens a `.framejob` package with Frame Job on a
  double-click, and the Debug app stays the Alternate handler.
- **CLAUDE.md edits owed** (the orchestrator applies them): every command, path, product,
  bundle id, flag and log prefix the five files spell; and root `CLAUDE.md`'s agent/ "NOT YET"
  note, which is already stale — `diff -r agent/src ~/devel/rasterize/agent/src` exited 0 on
  2026-10-13, so the two trees are byte-identical today.

**`tools/proof/name_residue.py` (NM-8).** Stdlib only. It reads the matching lines with
`git grep -n -i --untracked reelcut` (so `KEPT_PATTERNS` can exempt a line) and `git ls-files`
for names, counts the lines left per file only for `COUNTED`, and fails on every match that is
not allowed:

- `HISTORY: tuple[str, ...]` — path prefixes kept whole: `archive/`, `designs/adr/`,
  `designs/design_handoff_reelcut/`, `designs/design_handoff_reelcut_sharp/`,
  `designs/design_handoff_clip_inspector/`, `designs/clip_inspector_brief/`, `.dupscan/`,
  `designs/rename.md`.
- `KEPT_PATTERNS: tuple[str, ...]` — regexes that exempt a matching line in any file:
  `kpgalligan/reelcut#\d+`, `archive/reelcut-[\w.-]+\.md`, `\.claude/litecode/reelcut/`,
  `devel/reelcut[\w-]*`.
- `COUNTED: dict[str, int]` — exact per-file line counts for files that must keep some old
  spellings: the §11 decision files (their original text), `tools/proof/README.md` (its recorded
  results), `designs/spec/11-decisions/README.md` (index rows that keep a decision's old
  title), old-name sites in historical instruments, `proof_defaults.py`, the harness, the check
  itself, root `CLAUDE.md` until R4 (its issue-tracker line names the bare
  `kpgalligan/reelcut`, which `kpgalligan/reelcut#\d+` does not match), and R3's temporary
  entries (the documents R3 has not yet rewritten).
- `def residue(root: str) -> list[str]` — the offending lines and paths; empty means pass.
- `--selftest` — a stray-line mutant (a new `reelcut` line in a scratch copy fails) and a count
  mutant (a counted file one line off fails).

### R2 — the mark and the icon (NM-11)

`BrandMark.swift` draws the content of `designs/frame-job/frame-job-icon.svg` without its tile
(four `#1F8564` corner brackets, the `#F2C14E` frame, the `#F4653F` playhead and its head), and
the wordmark reads "Frame Job"; `app/Assets.xcassets/AppIcon.appiconset` becomes
`designs/frame-job/AppIcon.appiconset`; the screen catalog is re-captured; a manual-checks row
for the Dock icon, the About panel and the Finder's document icon.

### R3 — the documents

`README.md`, `CONTEXT.md`, `designs/spec/` (the §11 decision text untouched; its index rows may
change), `docs/manual-checks.md`, `tools/proof/README.md`'s how-to (its recorded results kept),
the CLAUDE.md prose (as edits owed), and the residue check's temporary R3 entries removed from
`COUNTED`.

### R4 — the close

`designs/adr/rename.md` condensed from this file; `git mv designs/rename.md archive/` and its row
in `archive/INDEX.md`; each unfinished item filed as an issue, reviewed against the tree first;
the owner's hand steps handed over. Then, on the owner's OK only, the repository and folder
renames below, and root `CLAUDE.md`'s "GitHub Issues on" line.

## Verification per phase

- **Every phase:** `make gate`, in the foreground.
- **R1:** also `make dist`; then on Release (`RC_PROOF_APP=release`, after the gate's `make
  app`): `defaults_proof.py`, `debug_release_proof.py`, `mcp_proxy_proof.py`,
  `agent_socket_proof.py`, `makefile_env_proof.py`, `assistant_helper_proof.py`, `spend_proof.py`,
  `screens.py`, `recording_proof.py` (release_only; its granted tier may skip by a named host
  condition), `log_thumbs_proof.py` (the whole-app smoke), `reference_build_selftest.py`,
  `stale_registrations.py --selftest`, `python3 -m py_compile` over every changed
  `tools/**/*.py`, and `python3 tools/proof/swift_build.py typecheck` over every changed probe
  `.swift`. `grep "Frame Job: " <dir>/framejob.log` prints nothing before any MCP proof is
  trusted.
- **R2:** `screens.py`, and the harness's welcome and Settings paints.
- **R3:** `make gate` only.
- **R4:** `make gate`; after the owner's renames, `make gate GATE_ARGS=--force` in the renamed
  folder.

## The owner's hand steps

Given to the owner after R1 merges (the folder moves before any paid proof). **Every folder move
is guarded**, because a single Frame Job launch creates `~/Library/Application Support/Frame
Job/` (MC-1's socket folder), and a bare `mv` onto an existing folder nests the old one inside it:

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

`claude mcp get reelcut`, run in `~/devel/reelcut` on 2026-10-13, printed the local-scope entry
`http://127.0.0.1:4817/mcp` ("✘ Failed to connect"), road map 14's old TCP address.

**Last, only on the owner's OK** (R4):

```sh
gh repo rename framejob -R kpgalligan/reelcut
git -C ~/devel/reelcut remote set-url origin https://github.com/kpgalligan/framejob.git
mv ~/devel/reelcut ~/devel/framejob && git -C ~/devel/framejob worktree repair ~/devel/reelcut-rename ~/devel/framejob/.claude/worktrees/side-work ~/devel/framejob/.claude/worktrees/sign-publish
mv ~/.claude-personal/projects/-Users-kevingalligan-devel-reelcut ~/.claude-personal/projects/-Users-kevingalligan-devel-framejob
make gate GATE_ARGS=--force
```

The two nested worktrees' `.git` files hold the old absolute path, which is why the repair names
them; the repair is the owner's command only, and no phase's agent reads, runs in, repairs or
rebases anything under `.claude/worktrees/`. The branches `worktree-side-work` and
`worktree-sign-publish` carry the old names; the owner (or the sessions he runs in them) rebases
them onto R1, never a rename phase. Issue citations `kpgalligan/reelcut#N` stay as written:
GitHub redirects them after the rename.

## The Rasterize side (NM-10)

`agent/src` is meant to be byte-identical with `~/devel/rasterize/agent/src`, and is: `diff -r
agent/src ~/devel/rasterize/agent/src` exited 0 on 2026-10-13 (so root `CLAUDE.md`'s "NOT YET"
note is stale, an edit owed). Its old-name lines are exactly three
(`git grep -n -i reelcut ae56899 -- agent/src`), and R1 changes them so, recording the same diff
here for kpgalligan/rasterize to apply; no agent here writes `~/devel/rasterize`:

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

Rasterize already sends `reelcut-agent` as its user-agent today (the trees are identical), so
the shared user-agent becomes `framejob-agent` in both apps. Until Rasterize applies the diff,
the trees differ by those three lines.

## R0 — the record

**Landed** (2026-10-13, not committed by the implementer; the orchestrator commits):

- This file.
- `designs/spec/11-decisions/rename.md`: NM-1…NM-11.
- 39 amendment paragraphs, one per decision, each `**Amended by NM-n** (rename R0): <old> is now
  <new>…`: `dev-tools.md` V-1, V-5; `agent-connection.md` MC-1, MC-3, MC-4, MC-6, MC-7;
  `publishing.md` PUB-1; `pricing.md` P-5, P-6, P-7, P-8; `assistant.md` AI-1, AI-15, AI-18,
  AI-20; `cloud-captions.md` R6-5, R6-12; `recording.md` "The file lives in…", "A press of
  Record asks…", "A voice-over is a recording with no picture", "Include Reelcut windows";
  `foundations.md` "AVFoundation, not ffmpeg"; `deepening.md` #216-R, #228-V, #228-O, #233,
  #234; `word-captions.md` W-12, W-15; `graphics.md` G-2, G-14, G-26, G-29; `grading.md` GR-6,
  GR-7, GR-8, GR-9; `grading-3.md` GR-15. Any other mention of the old name in a decision is
  prose naming the product, and gets no line (NM-1's reading rule).
- `designs/spec/11-decisions/README.md`: `rename.md`'s Files row, NM-1…NM-11's rows, " — amended
  by NM-n" on the 39 rows, and the Lines cells; `designs/spec/README.md`'s folder cell.
- `designs/frame-job/` (14 files: `AppIcon.appiconset/` with `Contents.json` and ten PNGs,
  `frame-job-icon-1024.png`, `frame-job-icon.svg`, `frame-job.icns`), byte for byte as the owner
  supplied it.

**Measured:** the inventory above (every row as printed); `diff -r agent/src
~/devel/rasterize/agent/src` exited 0; the socket path for the owner's home is 75 bytes
(`printf '%s' "/Users/kevingalligan/Library/Application Support/Frame Job/Agent/agent.sock" | wc
-c`), against 73 today and `MAX_SOCKET_PATH_BYTES` 103 (`core/src/agent.rs`).

**Verified:** see the phase's checks (`tools/proof/spec_index_proof.py`, the amendment count,
that nothing outside `designs/` changed, and `make gate`).

## R1 — the record

**Landed** (2026-10-13, in the worktree, not committed by the implementer; the orchestrator
commits):

- **Build:** `project.yml` (project, target and scheme `FrameJob`; `PRODUCT_NAME` "Frame Job",
  Debug "Frame Job Debug"; `PRODUCT_MODULE_NAME: FrameJob` at the target; `CFBundleName` and
  `CFBundleDisplayName` read `$(PRODUCT_NAME)`, `RC_APP_NAME` gone; NM-3's UTI, extension, type
  names, entitlements path and `NSDocumentClass: FrameJob.ProjectDocument` ×6; `-lframejob_core`;
  `framejob-mcp`; the catalog step greps `Frame Job: `), the `Makefile` (`APP := FrameJob`, the
  three product paths spelled and quoted, `-D FRAMEJOB_DEV_TOOLS`, `make test`'s last two lines
  `name_residue.py --selftest` and `name_residue.py`), the publish workflow's contents
  (`FrameJob.xcarchive`, `FrameJob.dmg`, `-volname "Frame Job"`, title "Frame Job $VERSION"),
  `.gitignore` (the new generated paths, the old two kept).
- **Renamed by `git mv`:** `app/Bridging/FrameJob-Bridging-Header.h`,
  `core/include/framejob_core.h` (guards `FRAMEJOB_BRIDGING_HEADER_H`, `FRAMEJOB_CORE_H`).
- **Crates:** `framejob-core` (lib `framejob_core`), `framejob-mcp` (lib `framejob_mcp`, bin);
  both `Cargo.lock`s rewritten by `cargo build --release`; every `core/tests/*.rs` and the
  proxy's tests follow; `cargo fmt` reordered the renamed `use` lines.
- **app/:** every spelling but `BrandMark.swift` (R2): NM-4's folders and temporary root, NM-5's
  sentences, socket name, helper names, log prefixes, `include_framejob_windows` (no alias; the
  argument gate refuses the old name by name, measured), NM-6's keys, notifications, labels,
  shader entry points; `MediaRowView`'s Rewrapped test reads `AppSupport.folderName`; the
  `open -a` advice is spelled `open -a "Frame Job"`. Two lines rewrapped in files under 400
  lines; no file at or over 600 lines gained a line.
- **agent/:** `package.json`, `bun.lock`, `build.sh`, `prices/update.py` and NM-10's three lines.
- **tools/:** every file but `tools/proof/README.md`. `proof_app.py`'s `PRODUCTS` and
  `executable()` (every proof that built `Contents/MacOS/<name>` from an app path calls it; a
  copy of an app keeps its bundle's own name); `reference_build.py`'s `TreeNames`,
  `tree_names`, `tree_defines` (and `tree_shader`, below); `gate.py`'s `names` step;
  `budget.py`'s NM-7 guard (`unmoved`, `OLD_LEDGER_FOLDER`, `old_folder`) and
  `budget_proof.py` B1–B4; `proof_defaults.py`'s both-name refusals, prefixes, key prefixes and
  P10; `stale_registrations.py`'s `NAMES` and S4; the harness's pins under both names; every
  old-tree builder routed through `tree_names`; the two spikes and `grading_verdict.py` per
  the spec; the new `tools/proof/name_residue.py` (NM-8).
- **designs/screens/**, **docs/graphics-api.md** and **.d.ts**, and `docs/manual-checks.md`'s
  NAME-1.

**Deviations from the spec** (each read against what an old-tree instrument needs):

- `reference_build.tree_shader(tree, text)`: the archive builders that compile OLD
  `app/Sources` beside the CURRENT `Compositor.metal` (`editor_keys_undo_proof.py`,
  `space_key_proof.py`, `text_apply_proof.py`, `text_edit_proof.py`, and through them
  `obscure_handles_probe.py`, `text_break_proof.py`) now name the shader's entry points as the
  tree's Swift asks for them; without it an old tree's compositor finds no `reelcut_*`.
- `mcp.wait_listening` accepts the old ready and not-bound lines too: `grading_verdict.py`'s
  main tree (f407f87) is launched through `mcp.launch` and says them under its old name.
- `obscure_handles_probe.swift` and `text_break_probe.swift` pin their three defaults keys
  through `EditorViewController`'s own key constants, and every probe opens a package with
  `ProjectDocument.projectTypeIdentifier`, so one probe source reads the same against an old
  tree and the new one.
- `cloud_captions_probe.py`'s row 18 compares its baseline's `project.yml` blocks renamed
  (four replacements), so its expected diff stays the one it was.
- `budget.unmoved`'s refusal is worded "the proofs' ledger is not moved yet", and names the
  guarded `mv` with both folders; `stale_registrations.py` gains a pure S4 row for the two
  names rather than a second registered bundle.
- `name_residue.py`'s `ge-count` mutant makes the pin a ceiling (`pinned >= found`), the
  reading under which it fails S4 as the spec names; `COUNTED` also pins `mcp.py`,
  `cloud_captions_probe.py`, `phase5_chrome.py`, `phase8_chrome.py`, `sharp_chrome.py` (a
  design handoff's folder name), `graphics_spike/README.md` and `silence_spike/README.md`
  (a recorded log name and a recorded input path, both restored).

**Measured** (each printed by the command beside it; the full outputs are in the phase's
`04-checks.txt`): `make gate` PASS (names, typecheck at its four warnings, fmt, lint, test,
app); `make dist` D1–D27 and `published_check.py` 15/15 over "Frame Job.app"; on Release:
`defaults_proof.py` 11/11, `debug_release_proof.py` 10/10, `mcp_proxy_proof.py` 14/14,
`agent_socket_proof.py` 17/17, `makefile_env_proof.py` 4/4, `assistant_helper_proof.py` 6/6,
`spend_proof.py` 21/21, `screens.py` 36/36, `recording_proof.py --no-screen` 151/151 (section 5
skipped by name), `log_thumbs_proof.py` 7/8, `matte_spike.py --check --tree` all rows,
`grading_spike.py --check --tree --tree-base bde8319` all rows; `reference_build_selftest.py
--integration` all rows; mutants: `name_residue` `ge-count` S4 and `no-untracked` S2; the
budget guard removed fails B1 B2, the guard after `_open` fails B1; `tree_names` always new
fails the old-tree row; `proof_defaults` without the old prefixes fails P10; the gate's
`names` inputs without `*.md` fails M3's three `.md` rows, M4, M5 and M6.

**Owed:**

- The CLAUDE.md edits (the orchestrator's; listed verbatim in the phase's notes), and with them
  `COUNTED`'s CLAUDE.md pins: root 6, `app/` 4, `core/` 0, `mcp-proxy/` 0.
- `log_thumbs_proof.py` TH needs `tools/proof/work/i282/ctl/h0.json`, captured on the
  untouched pre-#282 tree; this worktree has none, so TH failed on that alone (its own
  comparison held: HLG, PQ and the SDR pair worst |Δ| 1).
- `grading_spike.py --check --tree` at its default base f407f87 failed R1080/R2160: the
  shader at f407f87 has no adjustment fragment (`git show` of it lists seven entry points, none
  `*_adjust_fragment`), which KA (grading-2 G2-4) asks of V0, so that base cannot pass whatever
  the names; an issue for the default.
- The owner's hand steps above, after the merge.

## R2 — the record

**Landed** (2026-10-13, in the worktree, not committed by the implementer; the orchestrator
commits):

- `app/Sources/BrandMark.swift`: `BrandMark.draw(in:)` draws `designs/frame-job/frame-job-icon.svg`
  without its tile, every coordinate as the SVG writes it (1024 viewBox, y down): `designBox`
  824 (the SVG tile's side), `tileOrigin` 100 (the tile's x and y), the context scaled by
  `side / designBox` and moved back by `-tileOrigin`; the four `DS.forest` corner brackets as
  closed polygons, the `DS.butter` frame (330, 400, 364 × 224), the `DS.coral` playhead body
  (488, 310, 48 × 424) and head (461,290)(563,290)(512,366), in the SVG's order, with no radii,
  strokes or blend mode; the cream tile `#FBF8F1` is not drawn. `overlapInk` is gone.
  `BrandMarkView`'s accessibility label and `BrandLockupView`'s wordmark read "Frame Job";
  `markSize` 88 and `wordSize` 52 are unchanged; `clearSpace` is the constant 38 (the old
  mark's 38.13, rounded), kept so the welcome column's height, and with it
  `recording_probe.py`'s `COLUMN_SHIFT` of 3 pt, does not change. No line of the file spells
  the old name.
- `app/Assets.xcassets/AppIcon.appiconset/`: the old `Contents.json` and seven `icon_16.png` …
  `icon_1024.png` deleted, and the eleven files of `designs/frame-job/AppIcon.appiconset/`
  copied in byte for byte. `app/Assets.xcassets/Contents.json` is unchanged.
- Comments: `WelcomeWindowController.swift`'s two clear-space comments say the lockup's fixed
  38 pt; `AppDelegate.showAboutPanel`'s doc cites spec §11 NM-11 (the panel shows the mark
  without its tile, the Dock the tiled icon).
- `designs/screens/01-welcome.md`: the mark and the word "Frame Job".
- `docs/manual-checks.md`: NAME-2 (the Dock icon, About in Light and Dark, the `.framejob`
  package's document icon).
- `tools/proof/name_residue.py`: the R2 `COUNTED` entries (`BrandMark.swift` 8,
  `01-welcome.md` 2) and their comment removed.
- `tools/proof/recording_probe.py`, section 6 only: the Swift `welcome` mode answers
  `lockup`, the first `BrandLockupView`'s `[minX, top, width, height]` in the buttons'
  top-left convention; 6d (v) "above the band" leaves out the render rows
  ⌊top × scale⌋ ≤ y < ⌈(top + height) × scale⌉, names why in its label (rename R2 changed the
  mark and the wordmark, spec §11 NM-11), prints how many lockup rows differ, and fails when no
  lockup frame is answered. The module docstring's Section 6 paragraph and the section's header
  line say so. Still 35 rows.

**Deviations from the spec:**

- The spec's last Full command asks to Read `icon_512x512@2x.png` from
  `iconutil -c iconset` of the Release bundle's `AppIcon.icns`. That icns holds only
  `icon_16x16`, `icon_16x16@2x`, `icon_128x128` and `icon_128x128@2x` (actool keeps the larger
  sizes in `Assets.car`), so `icon_128x128@2x.png` (256 px) was read instead; the 1024 rendition
  is `Assets.car`'s `icon_512x512-2x.png`, 1024 × 1024 at scale 2 (`assetutil --info`).
- This record was appended after `make gate` passed, and the review's fix pass edited it
  again after the fix pass's own gate. The gate's only step that reads this file is `names`,
  which runs exactly `python3 tools/proof/name_residue.py`. That command was run again on the
  final tree and exited 0. `designs/rename.md` is under `HISTORY` there.

**Measured** (each printed by the command beside it; the full outputs are in the phase's
`04-checks.txt`, and the second screens compare and its three-way analysis in fix pass 1's
notes):

- Baseline, untouched tree: `recording_probe.py --only welcome` 35/35.
- M1 (the new mark, the probe not yet edited): 33/35, failing exactly `6d light: (v) above the
  band` and `6d dark: (v) above the band`, 200 rows differing from y 221.
- The edited instrument, recorded run: `recording_probe.py --only welcome` 35/35; the lockup's
  frame `[254.5, 101, 211.5, 158]`, its rows y 202–517 of the 1440 × 1200 render, 200 of them
  differing in each appearance and none outside it. Run again on the fix pass's instrument (the
  label's range printed inclusive, the docstring re-wrapped): 35/35, the same frame and counts.
- M3 (the mark view's frame reported as `lockup`): 33/35, failing the same two rows, "62 rows
  differ outside it, first y [428, …]" (the wordmark), 138 lockup rows differing. Reverted.
- M2 (`Reelcut` put back in `BrandMark.swift`'s first comment): `name_residue.py` exit 1,
  `app/Sources/BrandMark.swift:3: /// The Reelcut mark: a viewfinder …`. Reverted; exit 0.
- `make typecheck` exit 0 at its four baseline warnings; the harness's `welcome` light and
  dark and `settings` light renders, Read: the four green brackets, the yellow frame, the coral
  playhead, no tile, and "Frame Job" on one line.
- `diff -r designs/frame-job/AppIcon.appiconset app/Assets.xcassets/AppIcon.appiconset` exit
  0.
- `xcrun assetutil --info` of the Debug and of the Release `Assets.car`: the `icon_*`
  RenditionNames are exactly `icon_16x16.png`, `icon_16x16-2x.png`, `icon_32x32.png`,
  `icon_32x32-2x.png`, `icon_128x128.png`, `icon_128x128-2x.png`, `icon_256x256.png`,
  `icon_256x256-2x.png`, `icon_512x512.png`, `icon_512x512-2x.png`, none of the old names, plus
  actool's `ZZZZPackedAsset-1.0.0-gamut0` and `-2.0.0-gamut0`.
- `iconutil -c iconset` of the Release `AppIcon.icns`, `icon_128x128@2x.png` Read: the cream
  rounded tile with the four green brackets, the yellow frame and the coral playhead.
- `make gate` PASS (names, typecheck, test, app; fmt and lint skipped as unchanged), and again
  on the fix pass's tree (the same four steps run).
- `RC_PROOF_APP=release screens.py --compare tools/proof/work/screens/2026-10-13-013442`
  (R1's capture): 36/36, 0 new problems; 89/106 byte-identical. `01-welcome.window` light and
  dark differ in [514,221,928,489] px, the lockup. The other fifteen are in the timeline's clip
  rows of the grading and matte screens (`05c`, `05d`, `05e` light, `05f`, `05g`, `05h`, and
  `10c`'s timeline and window, 4 to 14156 px each).
- A second Release capture of the same R2 tree,
  `RC_PROOF_APP=release screens.py --compare tools/proof/work/screens/2026-10-13-022226` (the
  first R2 capture): 36/36, 0 new problems; 91/106 byte-identical. `01-welcome` is
  byte-identical in both looks, so the new mark draws the same every run. Fifteen captures
  differ between the two R2 runs. They are the same fifteen screens, with `05e` dark in place of
  `05e` light. Comparing the three runs PNG by PNG (R1, R2 first, R2 second) puts every one of
  R1's fifteen differences in one of two kinds. Neither is stable, and neither is the mark:
  - **A filmstrip tile, 4764–14156 px** (one to three 34 pt tiles), in `05c`, `05d`, `05f`
    light, `05g` dark and `05h`. These differ between the two R2 runs as well. In the
    second R2 capture of `05c` dark, one tile at x 536–603 shows the lane's colour where the
    first run drew a frame. That is a thumbnail that had not arrived at capture time.
    `05d` light is byte-identical between R1 and the second R2 run, so its R1 difference was
    this run-to-run variation.
  - **A waveform column, 4–16 px**: the top and bottom pixel of one or two 1 pt columns (x 572,
    644 and 732 of the 2× capture). This is `10c`'s 8 px box, and also `05e` light, `05f` dark
    and `05g` light (byte-identical between R1 and the second R2 run, so its R1 difference
    was this run-to-run variation). Each such column takes one of two values per instance, and both builds
    produce both values. In R1, `10c`'s light timeline has (87,99,115) at (572,438) and its dark
    timeline has (71,84,101). The first R2 run has them the other way round. `05e` light's x 732
    column is (189,194,200) in R1 and (181,186,193) in both R2 runs. But R1's own `05e` dark has
    (181,186,193) there, and the second R2 run's `05f` light has (189,194,200).
    The cause is the peaks cache, not the drawing. `screens.py` rebuilds each fixture in every
    instance, so each instance computes `speech.mov`'s peaks again. After the second run, the
    eight `cache/peaks/*.bin` files the dark instance wrote for `speech.mov` (571 floats each,
    one per fixture that imports it) have five different hashes. They differ in one to three
    10 ms buckets, and only in buckets 355, 366, 435, 452, 557 and 558. Bucket 355 is 0.1151
    in one file and 0.1254 in another. Buckets 557/558 are 0.1131/0.12 in one and 0.12/0.1043
    in another, which looks like frames landing in the neighbouring bucket. In the capture, the
    clip runs from x 132 pt to 371 pt and the playhead at 1.5 s is at 195 pt, which is about
    41.9 pt a second. At that scale the three columns that change, 286, 322 and 366 pt, read
    buckets of about 367, 453 and 558: the varying 366, 452 and 557/558, within the scale's
    precision. The peaks pass (`MediaImporter.writePeaks` → `PeakBuckets.add`, which places
    frames by each decoded buffer's presentation time) does not give the same bytes twice for
    one file. That is older than R2, and it is owed as an issue (below).

**Where else the old mark's colours and shape live:**

- The About panel and Welcome are the mark's only two sites.
- The recorder panel, the status item and the empty editor draw no mark. Their coral is
  `DS.meterClip` = `coral`, unchanged.
- The three inks also colour the playhead, the marquee, the range shade, the snap guide, the
  "missing" badge and the clip labels orange, yellow and green. All unchanged, because the
  hexes are the new icon's.
- `Theme.swift:5-6,29`'s comments ("welcome motif … marquee", "used only by…") were already
  stale before R2: filed as #286, since the file is synced with Rasterize.

**Owed:**

- The CLAUDE.md edits (the orchestrator's), verbatim:
  - `app/CLAUDE.md` line 2389–2390, replace "`BrandMark.swift` is\nReelcut's own, drawn from
    `designs/design_handoff_reelcut/`." with "`BrandMark.swift` is\nFrame Job's own: the mark
    of `designs/frame-job/frame-job-icon.svg` without its tile (spec §11 NM-11)." In the same
    change, set `name_residue.py` `COUNTED["app/CLAUDE.md"]` from 4 to 3.
  - Root `CLAUDE.md` "Where to look": add the row "| `designs/frame-job/` | The owner's Frame
    Job icon and mark (spec §11 NM-11): `frame-job-icon.svg` is `BrandMark`'s geometry,
    `AppIcon.appiconset` the app's icon set. |" after the `design_handoff_reelcut/` row, and
    change that row's "The shipped chrome cleanup and identity;" to "The shipped chrome cleanup
    and the old identity;". The root pin stays 6.
- NAME-2, the owner's.
- #285 (filed by the orchestrator): `speech.mov`'s peaks cache
  is not the same from one computation to the next. One app instance, writing the same media's
  `cache/peaks/<id>.bin` into eight fixture packages, gave five different files. They differ by
  one to three 10 ms buckets, with values that look like frames landing in the neighbouring
  bucket. This makes `screens.py`'s waveform columns differ by a pixel between runs. The
  measurement is in the R2 record's second screens compare.
