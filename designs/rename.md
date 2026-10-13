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
