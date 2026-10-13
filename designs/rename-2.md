# Road map "rename-2" — the old name leaves what is not history

**Opened 2026-10-13** (N0, in the worktree `/Users/kevingalligan/devel/reelcut-rename2` on branch
`rename2`, from `ed8f282`, each phase merged into main after its gate). The request this road map
answers is the owner's of 2026-10-13; its decisions are spec §11 NM-12…NM-14, in
`designs/spec/11-decisions/rename.md`, recorded in N0 before any rename. Every count below was
printed by the command written beside it, at the pinned commit `ed8f282`.

## Goal

Round 1 (spec §11 NM-1…NM-11, `designs/adr/rename.md`, `archive/rename.md`) renamed the product
and kept the old name in history on purpose. Round 2 takes the old name out of what is not
history: the archived road maps' file names and the design handoffs' folder and file names
(their text stays as it was, but for links), the issue citations, and the product name in the
decision records' prose. Recorded results, the old-name safety nets and the inputs for building
an old tree keep it. Every phase leaves `tools/proof/name_residue.py` holding the new, smaller
allow-list exactly.

## The owner's choices

**2026-10-13**, verbatim:

> 1. Archive (archive/reelcut-*.md, 19 files): RENAME THE FILES (new names without "reelcut"),
>    update every link to them everywhere (inside archive/ too, so no link breaks), but KEEP THE
>    TEXT verbatim otherwise.
> 2. Decision records (designs/adr/*.md and spec §11 decision text in
>    designs/spec/11-decisions/): REPLACE the product name in prose ("Reelcut" -> "Frame Job", and
>    technical spellings per NM's spelling table). Keep quoted output (recorded log lines,
>    commands' printed output) and old file paths/identifiers that refer to things as they
>    really were named then. Record this as a NEW spec §11 decision (NM-12 or next free id): a
>    name-only edit of a decision's prose does not reopen or re-litigate the decision; it is the
>    one exception to the append-only rule.
> 3. Design handoffs (designs/design_handoff_reelcut/, designs/design_handoff_reelcut_sharp/,
>    designs/design_handoff_clip_inspector/_ds/reelcut-design-system-…/, and files inside named
>    reelcut-*): RENAME FOLDER AND FILE NAMES, update every link to them (CLAUDE.md table, spec,
>    ADRs, code comments, proofs). The designer's file CONTENTS stay as delivered.
> 4. Proof scripts (tools/proof/), the owner's OK of my recommendations:
>    a. Links/citations: `kpgalligan/reelcut#N` -> `kpgalligan/framejob#N` (GitHub redirects).
>       Do this repo-wide (app/, core/, graphic/, tools/, designs/ incl. ADRs and spec), EXCEPT
>       inside archive/ text (verbatim) and inside quoted recorded output.
>    b. Recorded past results (mostly tools/proof/README.md's quoted output): KEEP.
>    c. Old-name safety nets that deliberately match both names (proof_defaults.py, mcp.py's
>       app-name match, harness/main.swift's pinned-key mapping, budget.py's NM-7 guard,
>       grading_verdict.py's dual log prefix etc.): KEEP for now — they can only go after the
>       owner finishes his hand steps in issue #287 (still OPEN). Do NOT remove them; the
>       orchestrator files a follow-up issue for that.
>    d. Instruments that build pre-rename commits (reference_build.py
>       tree_names/tree_shader/tree_defines, grading_verdict.py, cloud_captions_probe.py, …):
>       KEEP the old names they need to build those commits.
> 5. Also in scope: any other remaining non-history prose in app/, core/, graphic/, CLAUDE.md
>    files, README, docs/ that names Reelcut where it is not a quote, an old-tree build input,
>    or a safety net.

NM-12 records item 2's rule with the two other name-only rewrites (the link rule and the issue
rule) beside it, so that it is not the ONE exception but one of three: N1's and N3's rewrites
touch §11 text too (for example `deepening.md`'s six `archive/reelcut-roadmap-7.md` links).

## Inventory

**The command** (run in the worktree; `f <pathspec>…` prints files and lines matching `reelcut`
case-insensitively at the pinned commit; round 1's `f()`, re-pointed at `ed8f282`):

```sh
cd /Users/kevingalligan/devel/reelcut-rename2 && f(){ echo "$(git grep -l -i reelcut ed8f282 -- "$@" | wc -l) files / $(git grep -h -i -c reelcut ed8f282 -- "$@" | awk -F: '{s+=$NF} END{print s+0}') lines :: $*"; }
```

The whole tree: `git grep -I -i -c reelcut ed8f282` finds 2,107 lines in 213 files (`f .` prints
the same), and `git ls-tree -r --name-only ed8f282 | grep -ic reelcut` finds 72 paths: 19 archive
files and 53 handoff files (16 under `designs/design_handoff_reelcut/`, 20 under
`designs/design_handoff_reelcut_sharp/`, 17 under `designs/design_handoff_clip_inspector/`).

| Category | Pathspec given to `f` | Files | Lines | Phase |
|---|---|---|---|---|
| Archive | `archive` | 29 | 960 | N1 its 19 names and the links inside it; N2 the handoff links inside it; the text otherwise kept |
| Condensed records | `designs/adr` | 29 | 150 | N1, N2 links; N3 issues; N4 prose |
| The spec | `designs/spec` | 22 | 233 | N1 links (the 6 §11 files, `09-keys-and-menus.md`); N2 links (`03-window-layout.md`, NM-1's text); N3 issues; N4 the §11 prose and index rows |
| The design handoffs and the brief | `designs/design_handoff_reelcut designs/design_handoff_reelcut_sharp designs/design_handoff_clip_inspector designs/clip_inspector_brief` | 31 | 266 | N2 names and links; contents otherwise kept |
| The duplicate scan's record | `.dupscan` | 1 | 32 | N2 its `path` keys and `contextDocs` entries; `evidence`, `repo` and `source` kept |
| The proof README | `tools/proof/README.md` | 1 | 236 | N1, N2 links; N3 issues (each of 12 lines classified); recorded results kept; N5 the sweep |
| The rest of the proof tooling | `tools/proof ':!tools/proof/README.md'` | 66 | 170 | N1 links (28 files with the README); N2 links; N3 issues; safety nets and old-tree inputs kept; N5 the sweep |
| The app | `app` | 17 | 36 | N1 links (10 files in `app/Sources`, `app/CLAUDE.md`); N3 issues |
| The core | `core` | 13 | 17 | N1 `core/src/source_window.rs`'s link; N3 issues |
| The graphics engine | `graphic` | 1 | 1 | N1 `graphic/CLAUDE.md`'s link |
| Root `CLAUDE.md` | `CLAUDE.md` | 1 | 3 | N2 lines 43 and 45; line 260 (NM-7's old ledger folder) kept |
| Ignore file | `.gitignore` | 1 | 2 | kept: old generated paths, (o), the class N5 defines |
| README | `README.md` | 1 | 1 | N1 its link |
| **Total** | `.` | **213** | **2107** | |

The thirteen category rows add up to the total row (213 files, 2,107 lines). The four handoff
pathspecs, printed one by one, are 5 files / 22 lines (`designs/design_handoff_reelcut`), 12 / 42
(`designs/design_handoff_reelcut_sharp`), 12 / 197 (`designs/design_handoff_clip_inspector`) and
2 / 5 (`designs/clip_inspector_brief`). `docs`, `agent`, `mcp-proxy`, `CONTEXT.md`, `project.yml`,
`Makefile` and `.github` print 0 files / 0 lines.

## The archive's names (NM-13)

Each name drops `reelcut-`; the first road map takes its number. None of the new names collides
with `build-velocity.md`, `grading.md`, `grading-2.md`, `grading-3.md`, `mattes.md`,
`precision.md`, `precision-2.md`, `rename.md`, `svg-motion-components-plan.md` or `INDEX.md`.

| Old name (`archive/`) | New name (`archive/`) |
|---|---|
| `reelcut-roadmap.md` | `roadmap-1.md` |
| `reelcut-roadmap-2.md` | `roadmap-2.md` |
| `reelcut-roadmap-3.md` | `roadmap-3.md` |
| `reelcut-roadmap-4.md` | `roadmap-4.md` |
| `reelcut-roadmap-5.md` | `roadmap-5.md` |
| `reelcut-roadmap-6.md` | `roadmap-6.md` |
| `reelcut-roadmap-7.md` | `roadmap-7.md` |
| `reelcut-roadmap-8.md` | `roadmap-8.md` |
| `reelcut-roadmap-9.md` | `roadmap-9.md` |
| `reelcut-roadmap-10.md` | `roadmap-10.md` |
| `reelcut-roadmap-11.md` | `roadmap-11.md` |
| `reelcut-roadmap-12.md` | `roadmap-12.md` |
| `reelcut-roadmap-13.md` | `roadmap-13.md` |
| `reelcut-roadmap-14.md` | `roadmap-14.md` |
| `reelcut-milestones.md` | `milestones.md` |
| `reelcut-effects-survey.md` | `effects-survey.md` |
| `reelcut-app-notes.md` | `app-notes.md` |
| `reelcut-core-notes.md` | `core-notes.md` |
| `reelcut-remaining.md` | `remaining.md` |

## The handoffs' names (NM-13)

| Old path | New path |
|---|---|
| `designs/design_handoff_reelcut/` | `designs/design_handoff_chrome/` |
| `designs/design_handoff_reelcut/Reelcut Editor.dc.html` | `designs/design_handoff_chrome/Editor.dc.html` |
| `designs/design_handoff_reelcut/Reelcut Logo.dc.html` | `designs/design_handoff_chrome/Logo.dc.html` |
| `designs/design_handoff_reelcut/logo/reelcut-icon.svg` | `designs/design_handoff_chrome/logo/reel-icon.svg` |
| `designs/design_handoff_reelcut/logo/reelcut-mark.svg` | `designs/design_handoff_chrome/logo/reel-mark.svg` |
| `designs/design_handoff_reelcut/logo/reelcut-mark-mono.svg` | `designs/design_handoff_chrome/logo/reel-mark-mono.svg` |
| `designs/design_handoff_reelcut_sharp/` | `designs/design_handoff_sharp/` |
| `designs/design_handoff_reelcut_sharp/design/assets/logo/reelcut-icon.svg` | `designs/design_handoff_sharp/design/assets/logo/reel-icon.svg` |
| `designs/design_handoff_reelcut_sharp/design/assets/logo/reelcut-mark.svg` | `designs/design_handoff_sharp/design/assets/logo/reel-mark.svg` |
| `designs/design_handoff_reelcut_sharp/design/assets/logo/reelcut-mark-mono.svg` | `designs/design_handoff_sharp/design/assets/logo/reel-mark-mono.svg` |
| `designs/design_handoff_clip_inspector/_ds/reelcut-design-system-2b6440ca-3b4a-4f1b-a40b-66a71401af03/` | `designs/design_handoff_clip_inspector/_ds/design-system-2b6440ca-3b4a-4f1b-a40b-66a71401af03/` |

Every other file in the three folders keeps its own name and moves with its folder.

## The rules

Each phase applies these as written.

**Link rule (NM-13).** Every reference to a renamed path is rewritten wherever it appears:
archive text, decision text, ADRs and designer files included. A reference is the full path,
the path from `designs/`, or the bare name. The rewrite is the only edit those files take.
Exceptions:

- (a) a path already stale at `ed8f282`, which is kept: `designs/reelcut-*.md` (the road maps
  before the archive) and `designs/reelcut-design.md`. `archive/INDEX.md` gains each file's old
  name so these still resolve.
- (b) a command, pathspec or path that runs against an old commit or tree, such as
  `archive/rename.md`'s inventory at `ae56899`.
- (c) the generated bundles, manifests and lint configs inside designer folders
  (`_ds_bundle.js`, `_ds_manifest.json`, `_adherence.oxlintrc.json`,
  `design/runtime/ds_bundle.js`).
- (d) recorded output.
- (e) a renaming map's old-name column, which keeps the old path: NM-13's two maps, this road
  map's mapping tables (the archive's names, the handoffs' names) and `archive/INDEX.md`'s "old
  name" notes.

Wildcards and regexes such as `archive/reelcut-*.md` are not references.

**Issue rule (NM-14).** `kpgalligan/reelcut#N` → `kpgalligan/framejob#N` everywhere except
archive text, recorded output and designer files.

**Prose rule (NM-12).** In the decision text and ADRs, an old spelling becomes NM-2's spelling
where it names the product, or a thing that exists today under the new name, and the
substitution keeps the sentence true. The kept classes, each with its letter:

- (q) recorded output or a quote from a dated run;
- (p) a stale or past path;
- (x) an outside path that is real until the owner renames it (`~/devel/reelcut*`,
  `~/.claude/litecode/reelcut/`);
- (s) an NM-7 safety net or old app domain or folder;
- (r) the rename's own record: the text of NM-1…NM-11, every "Amended by NM-n" paragraph, and
  `designs/adr/rename.md` where the old name is its subject;
- (f) a sentence the substitution would make false, because its amendment changed more than the
  spelling (for example V-5's "`PRODUCT_NAME` stays `Reelcut`").

**Kept everywhere until the follow-up issue:** request items 4b, 4c and 4d. These are recorded
results, the safety nets (until #287 closes) and the inputs for building old trees.

## The traps

- `gate.py`'s `EXCLUDED` drops `archive/` from every step's hash. A fix that touches only
  `archive/` therefore skips `names`. Such a fix also edits `name_residue.py`, or runs
  `make gate GATE_ARGS=--force`.
- Whole-basename matching: `reelcut-roadmap.md` must not match `reelcut-roadmap-10.md`.
- Folders and files with spaces need `git mv` with quoted names.
- Live readers of archive paths: `tools/proof/assistant_spike/assistant_spike.py:70`
  (`ROADMAP`), the `--leakcheck` command lines in `tools/proof/cloud_spike/README.md`,
  `tools/proof/words_spike/README.md` and `tools/proof/README.md`, and
  `tools/proof/recording_spike.py:2292`.
- The twelve `href`/`src` lines in the six `designs/design_handoff_clip_inspector/*.dc.html`
  files.
- `.dupscan/scan.json`'s `path` keys and `contextDocs` entries. Its `evidence`, `repo` and
  `source` strings are kept.
- Any spec file whose length changes moves a Lines cell, which `spec_index_proof.py` checks.
- `COUNTED` pins are exact. Re-pin by running the check and reading every counted line.

## Phases

Each phase is gated in the worktree and fast-forward merged into main on its own. The
`CLAUDE.md` edits a phase owes are applied by the orchestrator, as in round 1.

### N0 — the plan (this phase)

This file; spec §11 NM-12…NM-14 and the amendment paragraphs at the end of NM-1 and NM-8
(`designs/spec/11-decisions/rename.md`); both spec indexes; `name_residue.py`'s `HISTORY` gains
`designs/rename-2.md`, and the two §11 `COUNTED` pins move to their exact new counts. Nothing is
renamed and no code moves.

### N1 — the archive's names

`git mv` the 19 archive files (the table above). Rewrite every link to them: `archive/` text
incl. `INDEX.md` (new names plus an "old name" note); `designs/adr`; the 6 §11 files;
`designs/spec/09-keys-and-menus.md`; `README.md`; `app/CLAUDE.md`; `graphic/CLAUDE.md`;
`app/Sources` (10 files); `core/src/source_window.rs`; and `tools/proof` (28 files). The full
list comes from `git grep -l -E 'reelcut-(roadmap(-[0-9]+)?|milestones|effects-survey|app-notes|core-notes|remaining)\.md'`
(88 files at `ed8f282`), with each hit in a file read against exception (e).

`name_residue.py` takes, verbatim:

- `TEXT_HISTORY: tuple[str, ...] = ("archive/",)` — prefixes whose LINES are kept but whose
  PATHS are still checked. `"archive/"` leaves `HISTORY`.
- `residue(root: str, *, history=HISTORY, text_history=TEXT_HISTORY, kept=KEPT_PATTERNS, counted=COUNTED) -> list[str]`
- The selftest gains `S7`: a tracked path that holds the name under a `text_history` prefix
  fails. The `S6` CONTROL also covers a `text_history` line, which passes. The new mutant
  `text-history-paths` (such paths exempted) must fail exactly `S7`. `main()`'s `--mutant`
  choices gain it.

It also drops the `archive/reelcut-…` `KEPT_PATTERNS` entry and re-pins.

### N2 — the handoffs' names

`git mv` the handoff folders and files (the table above). Rewrite links in every file
`git grep -l -E 'design_handoff_reelcut|reelcut-design-system|Reelcut (Editor|Logo)\.dc\.html|reelcut-(icon|mark|mark-mono)\.svg'`
lists, less exception (c)'s files and each hit read against exceptions (a), (b), (d) and (e). At
`ed8f282` it lists 28 files, 26 after exception (c) (`_ds_bundle.js` and
`_adherence.oxlintrc.json` out): root `CLAUDE.md` (lines 43 and 45),
`designs/spec/03-window-layout.md`, NM-1's text, five archive files
(`reelcut-app-notes.md`, `reelcut-milestones.md`, `reelcut-roadmap-12.md`,
`reelcut-roadmap.md` — by then N1's names — and `rename.md`), the six
`designs/design_handoff_clip_inspector/*.dc.html`, the `_ds` README and `tokens/colors.css`, the
handoff READMEs and `tokens.css` files (`designs/design_handoff_reelcut/README.md`,
`designs/design_handoff_reelcut_sharp/README.md`,
`designs/design_handoff_reelcut_sharp/design/tokens.css`), the brief's `tokens.css`,
`.dupscan/scan.json`, `tools/proof/{phase5_chrome,phase8_chrome,sharp_chrome}.py` and
`README.md`, and `name_residue.py`. `HISTORY` takes the new folder names. Re-pin.

### N3 — the issue rule

The issue rule over the 55 files `git grep -l -E 'kpgalligan/reelcut#[0-9]+' -- ':!archive'`
lists at `ed8f282`. Each of `tools/proof/README.md`'s 12 such lines is classified as recorded
output or not. Drop that `KEPT_PATTERNS` entry and re-pin.

### N4 — the prose rule

The prose rule over `designs/adr/*.md` and `designs/spec/11-decisions/*.md`, the index rows
included. `designs/adr/` leaves `HISTORY`. Each ADR that still holds the name gets a `COUNTED`
pin. Re-pin §11 and fix the Lines cells.

### N5 — the sweep and the close

- **The sweep:** classify every remaining line outside `HISTORY` by keep-class (q/p/x/s/r/f, or
  (o) an input for building an old tree) in a table in this road map. Rename any line that fits
  no class.
- **The close:** `designs/adr/rename-2.md`, `git mv` of this road map to `archive/rename-2.md`,
  its `archive/INDEX.md` row, the root `CLAUDE.md` ADR list, `HISTORY` without
  `designs/rename-2.md`, and the follow-up issue's number. The orchestrator files that issue:
  the safety nets come out after #287.

## Verification per phase

Every phase runs, in the worktree:

```sh
cd /Users/kevingalligan/devel/reelcut-rename2 && python3 tools/proof/name_residue.py
cd /Users/kevingalligan/devel/reelcut-rename2 && python3 tools/proof/name_residue.py --selftest
cd /Users/kevingalligan/devel/reelcut-rename2 && python3 tools/proof/spec_index_proof.py
cd /Users/kevingalligan/devel/reelcut-rename2 && make gate
```

`name_residue.py` exits 0 and prints nothing; the selftest prints every row passing and `PASS`;
`spec_index_proof.py` exits 0; `make gate` exits 0 with `names` and `test` run, not skipped (a
phase that touches only `archive/` forces it, the first trap). N1 also runs
`python3 tools/proof/name_residue.py --mutant text-history-paths`, which must fail exactly `S7`.

## N0 — the record

## N1 — the record

## N2 — the record

## N3 — the record

## N4 — the record

## N5 — the record
