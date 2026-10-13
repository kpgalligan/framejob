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

**Landed** (2026-10-13, commit `0c703b4`, from `ed8f282` in the worktree):

- `designs/rename-2.md` (new): this road map — the owner's choices verbatim, the inventory at
  `ed8f282` (213 files / 2,107 lines, 72 paths), the two name maps, the rules, the traps, the
  phases N0–N5 and these record headings.
- `designs/spec/11-decisions/rename.md`: NM-12, NM-13 and NM-14 appended; an "Amended by NM-12
  and NM-13" paragraph at the end of NM-1 and an "Amended by NM-14" paragraph at the end of NM-8
  (158 → 241 lines).
- `designs/spec/11-decisions/README.md`: the `rename.md` row (241 lines, NM-1..NM-14), the two
  "amended by" notes, rows for NM-12..NM-14 (311 → 314 lines); `designs/spec/README.md`'s total
  7583 → 7669.
- `tools/proof/name_residue.py`: `designs/rename-2.md` in `HISTORY`; the pins
  `designs/spec/11-decisions/rename.md` 15 → 33 and `designs/spec/11-decisions/README.md`
  18 → 19, every newly counted line read first. No path moved.

**Measured:** `make gate` PASS in 348 s with every step run (names 1 s, typecheck 7 s, fmt 2 s,
lint 24 s, test 209 s, app 105 s); `name_residue.py` exit 0, silent; its selftest 7/7 and
`PASS`; `spec_index_proof.py` 159/159. Every count in the inventory and the phases was checked
against `ed8f282` and matched.

**Review:** pass, with four nits, all applied by the orchestrator before the commit: "four"
handoff pathspecs (not six), the `.gitignore` row's class (o) named in words, and two
`name_residue.py` comments (the §11 block's header names NM-12's exception; the `rename.md` pin
is re-pinned by N2 first, then N4). The nit pass re-ran `names` and `test`.

**Deviations:** none in substance. NM-12..NM-14 carry their rules' kept classes and exceptions
in the decision text, and "The owner's choices" says why NM-12 names three name-only edits
where request item 2 asked for one exception.

**Owed:** phases N1..N5.

## N1 — the record

**Landed** (2026-10-13, in the worktree, not committed by the implementer; the orchestrator
commits):

- `archive/`: the 19 `git mv`s of "The archive's names" (`reelcut-roadmap.md` →
  `roadmap-1.md`, `reelcut-roadmap-N.md` → `roadmap-N.md`, the five others without the prefix).
  `git ls-files archive | grep -ic reelcut` prints 0. Links rewritten inside nine of them:
  `app-notes.md` (2 lines), `milestones.md` (3), `roadmap-1.md` (4), `roadmap-2.md` (2),
  `roadmap-3.md` (8), `roadmap-4.md` (1), `roadmap-6.md` (4), `roadmap-7.md` (5),
  `roadmap-14.md` (2); every other hit in the archive is a `designs/reelcut-*.md` path, kept
  (exception (a)). `archive/svg-motion-components-plan.md` and `archive/rename.md` untouched.
- `archive/INDEX.md`: each of the 19 first-column cells is `` `<new>` (old name `<old>`) ``,
  and the intro gains the sentence that the `reelcut-` files lost that prefix in N1, so a stale
  `designs/reelcut-*.md` path still resolves.
- The link rewrite, one line in place for each link: `README.md` (1 line), `app/CLAUDE.md` (2),
  `graphic/CLAUDE.md` (1); ten `app/Sources` files (15 comment lines) and
  `core/src/source_window.rs` (1); `designs/adr/` (21 files, 24 lines; `remaining-closed.md`'s
  line 3 `designs/reelcut-remaining.md` kept, (a)); `designs/spec/09-keys-and-menus.md` (1) and
  six §11 files (12 lines); `tools/proof/` (28 files, 67 lines), among them the live readers
  `assistant_spike.py`'s `ROADMAP`, the `--leakcheck` lines of `cloud_spike/README.md`,
  `words_spike/README.md` and `tools/proof/README.md`, and `recording_spike.py:2292`. No spec
  file changed length. `designs/spec/11-decisions/rename.md`'s map (lines 195–198) keeps the
  old names, (e).
- `tools/proof/name_residue.py`: `"archive/"` out of `HISTORY` and into the new
  `TEXT_HISTORY` (its lines kept, its paths checked); `residue()` takes `text_history`; the
  `archive/reelcut-…` `KEPT_PATTERNS` entry and its comment clause gone; selftest S6 also holds
  a `TEXT_HISTORY` line, new row S7 (a path holding the name under a `TEXT_HISTORY` prefix
  fails), new mutant `text-history-paths`; docstring and `--mutant` choices name both; its own
  pin 6 → 5 (the lines `NAME`, the two handoff `HISTORY` entries, the issue pattern and the
  selftest's `kept`, each read). No other pin moved.

**Measured** (each printed by the command beside it; the full outputs are in the phase's
`04-checks.txt`):

- The link check, `git grep -n -o -E '[A-Za-z0-9_./-]*reelcut-(roadmap(-[0-9]+)?|milestones|effects-survey|app-notes|core-notes|remaining)\.md' -- ':!designs/rename-2.md' | grep -v -E ':designs/reelcut-'`:
  exactly 25 matches — 19 in `archive/INDEX.md` (the old-name notes) and 6 on
  `designs/spec/11-decisions/rename.md` lines 195, 197 and 198 (NM-13's map).
- `name_residue.py`: exit 0, silent. `--selftest`: `8/8 rows pass`, `PASS`.
- Mutants: `text-history-paths` failed exactly `['S7']`, `ge-count` exactly `['S4']`,
  `no-untracked` exactly `['S2']` — each `MUTANT PASS`.
- `spec_index_proof.py` 159/159; `py_compile` of the five edited Python files clean.
- `make gate` PASS in 230 s with every step run: names 1 s, typecheck 5 s, fmt 2 s, lint 5 s,
  test 130 s, app 87 s.

**Deviations:** none. `archive/INDEX.md`'s added sentence is wrapped over three lines to the
paragraph's width.

**Landed after the gate** (the orchestrator, root `CLAUDE.md`): in the `make test` line,
`HISTORY, KEPT_PATTERNS and the exact COUNTED pins` → `HISTORY, TEXT_HISTORY, KEPT_PATTERNS
and the exact COUNTED pins`; the review (pass, two nits applied before the commit).

**Owed:** phases N2..N5.

## N2 — the record

**Landed** (2026-10-13, in the worktree, not committed by the implementer; the orchestrator
commits):

- The 53 `git mv`s of "The handoffs' names": `designs/design_handoff_reelcut/` →
  `designs/design_handoff_chrome/` (16 files; inside it `Reelcut Editor.dc.html` →
  `Editor.dc.html`, `Reelcut Logo.dc.html` → `Logo.dc.html`, `logo/reelcut-{icon,mark,mark-mono}.svg`
  → `logo/reel-{icon,mark,mark-mono}.svg`), `designs/design_handoff_reelcut_sharp/` →
  `designs/design_handoff_sharp/` (20 files; `design/assets/logo/reelcut-*.svg` → `reel-*.svg`),
  and `designs/design_handoff_clip_inspector/_ds/reelcut-design-system-2b6440ca-…/` →
  `_ds/design-system-2b6440ca-…/` (17 files). `git ls-files -co --exclude-standard | grep -ic
  reelcut` prints 0.
- The link rewrite, one line in place for each link, no file changing length: the chrome
  handoff's `README.md` (9 lines: 27, 28, 60, 61, 62, 67, 273, 281, 282), the sharp handoff's
  `README.md` (line 9) and `design/tokens.css` (line 8), the brief's `tokens.css` (line 8), the
  `_ds` folder's `tokens/colors.css` (line 1) and `README.md` (line 16; its `ui_kits/reelcut/`
  is no path in this repository, kept), the six clip inspector `.dc.html` files (12 `href`/`src`
  lines); `.dupscan/scan.json` (the `path` keys at 31 and 45, the `contextDocs` entries at 91,
  92 and 95); `archive/app-notes.md` (1900, 2613), `archive/milestones.md` (133),
  `archive/roadmap-1.md` (55, 56), `archive/roadmap-12.md` (142);
  `designs/spec/03-window-layout.md` (4, 8); NM-1's history list in
  `designs/spec/11-decisions/rename.md` (line 27, a name-only edit under NM-12, no "Amended by"
  line); `tools/proof/README.md` (3712), `phase5_chrome.py` (318), `phase8_chrome.py` (3010),
  `sharp_chrome.py` (2). The "Reelcut dark chrome" words leading the three `tokens.css`-style
  comments are the designers' text, kept.
- Kept, each read: `archive/rename.md`'s six hits — 44 (a wildcard inside the owner's verbatim
  quote), 94 (the inventory pathspec at `ae56899`, (b)), 274 (the literal `HISTORY` tuple R1
  ran against its tree, (b)), 673 and 678 (edit instructions matched against the R2 tree, (b)),
  757 (what the proof README's line 3705 held at `6fa50c8`, (b)/(d)); the `_ds` folder's
  `_adherence.oxlintrc.json`, `_ds_bundle.js` and `_ds_manifest.json` and the sharp handoff's
  `design/runtime/ds_bundle.js`, (c); NM-13's map in `designs/spec/11-decisions/rename.md`
  (lines 199, 200, 202, 204), (e). Root `CLAUDE.md` lines 43 and 45 were kept for the
  orchestrator's edit after the gate, which cleared them (below).
- `tools/proof/name_residue.py` (data only): the three handoff folders out of `HISTORY` and
  into `TEXT_HISTORY` under their new names (their designers' lines kept, their paths checked);
  pins `designs/spec/11-decisions/rename.md` 33 → 32, `tools/proof/README.md` 200 → 199, its
  own 5 → 3 (`NAME`, the issue pattern and the selftest's `kept`, each read);
  `designs/spec/03-window-layout.md`, `phase5_chrome.py`, `phase8_chrome.py` and
  `sharp_chrome.py` unpinned (now 0 lines). Three comments lose their handoff clauses.

**Measured** (each printed by the command beside it; the full outputs are in the phase's
`04-checks.txt`):

- `name_residue.py`: exit 0, silent. `--selftest`: `8/8 rows pass`, `PASS`.
- `spec_index_proof.py`: `159/159 checks passed`, exit 0.
- The path count, `git ls-files -co --exclude-standard | grep -ic reelcut`: `0`.
- The link grep, `git grep -n -E 'design_handoff_reelcut|reelcut-design-system|Reelcut
  (Editor|Logo)\.dc\.html|reelcut-(icon|mark|mark-mono)\.svg' -- ':!designs/rename-2.md'`,
  per file: `6 archive/rename.md`, `2 CLAUDE.md`, `2 …/_adherence.oxlintrc.json`,
  `15 …/_ds_bundle.js`, `4 designs/spec/11-decisions/rename.md` (199, 200, 202, 204). The
  `CLAUDE.md` row was the two lines the orchestrator's edit after the gate cleared; the grep
  now prints no `CLAUDE.md` row.
- The designer diff, `git diff -M -U0 HEAD` over the old and new handoff folders and the
  brief: 26 removed lines and 26 added, each a link line (9 chrome README, 1 sharp README,
  1 sharp `tokens.css`, 1 brief `tokens.css`, 12 `.dc.html`, 1 `_ds` README, 1 `colors.css`).
  The planned `grep -c '^-[^-]'` prints 23: the chrome README's lines 27, 28 and 67 are
  Markdown bullets, so their removed form begins `--`; `grep -v '^--- ' | grep -c '^-'`
  prints 26.
- `py_compile` of the four edited Python files: silent.
- `make gate` PASS in 74 s: names 1 s, test 72 s run; typecheck, fmt, lint and app skipped
  (their inputs unchanged).

**Deviations:**

- The handoff folders went into `TEXT_HISTORY`, not `HISTORY` as N2's text above says: their
  paths are now checked, the mechanism N1 built for `archive/`, so a handoff path holding the
  old name fails.
- `archive/rename.md` takes no rewrite, though N2's text lists it among the archive files:
  each of its six hits is (a) or (b).

**Landed after the gate** (the orchestrator): root `CLAUDE.md` line 43
`` | `designs/design_handoff_reelcut/` | `` → `` | `designs/design_handoff_chrome/` | `` and
line 45 `` | `designs/design_handoff_reelcut_sharp/` | `` → `` | `designs/design_handoff_sharp/` | ``
(the rest of each row unchanged); in `tools/proof/name_residue.py`, `"CLAUDE.md": 3,` →
`"CLAUDE.md": 1,` and its comment now names only line 260, the old proofs' ledger folder
`budget.py` guards (NM-7). `make gate` after the edit: PASS in 70 s, names 1 s and test 69 s
run; typecheck, fmt, lint and app skipped (their inputs unchanged). The review (one
should-fix, this record; one nit, the pin comment's width) was applied in fix pass 1, and
`make gate` after it: PASS in 69 s, names 1 s and test 68 s run, the rest skipped. The
re-review passed.

**Owed:** phases N3..N5.

## N3 — the record

**Landed** (2026-10-13, in the worktree, not committed by the implementer; the orchestrator
commits):

- The issue rule (NM-14), one substitution in place, `kpgalligan/reelcut#<digits>` →
  `kpgalligan/framejob#<digits>`, over every file outside `archive/` that held one: 55 files,
  112 lines, no file changing length and no line reflowed. `app/CLAUDE.md` (4 lines); ten
  `app/Sources` files (16 `///` comment lines); `core/src/op_schema.rs` and `outcome.rs` (1
  each) and ten `core/tests` files (14 lines), comments only, no Rust line past 79 characters;
  `designs/spec/07.9a-agent-tools.md` (1); `designs/spec/11-decisions/chrome-inspector-keys.md`
  (6), `deepening.md` (1) and `foundations.md` (1), name-only edits under NM-12 with no
  "Amended by" line; `tools/proof/README.md` (12: lines 2937, 3179, 3259, 3301, 3388, 3512,
  3900, 4034, 6696, 6746, 6783 and 8620, each read and classified as section prose, not
  recorded output: an even count of fence lines before each, outside any code block); and 27
  other `tools/proof/` files (55 lines of comments and docstrings, and `phase9_proof.py:1339`,
  a string in a row's printed detail that nothing compares).
- `tools/proof/name_residue.py`: the `r"kpgalligan/reelcut#\d+"` entry out of `KEPT_PATTERNS`,
  which keeps `\.claude/litecode/reelcut/` and `devel/reelcut[\w-]*`; the comment above it and
  the module docstring lose their issue-citation clauses (the comment rewrapped over its own
  three lines); its own pin 3 → 2 (`NAME = "reelcut"` and the selftest's
  `kept = (r"issues/reelcut#\d+",)`, each read; the dropped line was the third). The selftest's
  `issues/reelcut#\d+` and S6's `see issues/{old}#12` stay: they exercise the mechanism in a
  scratch repository. No other pin moved: with the citations masked, no rewritten line holds a
  second old-name match, so `tools/proof/README.md` (199), `chrome-inspector-keys.md` (2),
  `deepening.md` (18) and `foundations.md` (2) keep theirs.
- Not touched: `designs/spec/11-decisions/rename.md` and `README.md` (their `kpgalligan/reelcut#N`
  is rule text with a literal `N`, already in their pins, never matched by `\d+`),
  `designs/adr/`, the handoffs and the brief (no `#<digits>` citation), `archive/`
  (`TEXT_HISTORY`). No root `CLAUDE.md` edit is owed by this phase: it holds no citation, and
  its `make test` line names `KEPT_PATTERNS`, which keeps two entries.

**Measured** (each printed by the command beside it; the full outputs are in the phase's
`04-checks.txt`):

- `git grep -n -E 'kpgalligan/reelcut#[0-9]+' -- ':!archive'`: nothing.
- `git grep -h -c -E 'kpgalligan/framejob#[0-9]+' | awk '{s+=$1}END{print s}'`: `112`; with
  `-l`, 55 files.
- `git diff --numstat`: added equals removed on every row; 112 and 112 over the 55 files.
- The second-match check, the rewritten citations masked as `<CIT>` and grepped for the old
  name: `0`.
- `name_residue.py`: exit 0, silent. `--selftest`: `8/8 rows pass`, `PASS`.
- `spec_index_proof.py`: `159/159 checks passed`, exit 0.
- `make gate` PASS in 310 s with every step run: names 1 s, typecheck 7 s, fmt 3 s, lint 10 s,
  test 178 s, app 111 s, over this record with this line as a placeholder. `make gate` ran
  again after the line was filled in; its output is in `04-checks.txt`.

**Deviations:** the comment above `KEPT_PATTERNS` is rewrapped over its same three lines (and,
at the review's nit, the docstring bullet beside it). The review passed with two nits, both
applied before the commit.

**Owed:** phases N4..N5.

## N4 — the record

**Landed** (2026-10-13, in the worktree, not committed by the implementer; the orchestrator
commits):

- The prose rule (NM-12) over `designs/adr/*.md` and `designs/spec/11-decisions/*.md`, each of
  the 355 old-name lines at `def5418` (126 ADR, 229 §11) read in its paragraph and either
  substituted in place or kept with its class: 196 lines substituted in 38 files, no file
  changing length, no line reflowed, no "Amended by" line added. Two lines are partly
  substituted and count as kept (`build-velocity.md` 12, `roadmap-10-graphics.md` 981).
  ADRs, 79 lines in 21 files: `app-file-history.md` 1, `build-velocity.md` 2,
  `effects-survey.md` 8, `grading-2.md` 1, `grading-3.md` 6, `grading.md` 5, `mattes.md` 2,
  `precision-2.md` 1, `precision.md` 1, `remaining-closed.md` 1,
  `roadmap-03-screen-recording.md` 6, `roadmap-06-cloud-captions.md` 8,
  `roadmap-07-deepening.md` 1, `roadmap-08-word-captions.md` 1, `roadmap-09-clip-inspector.md`
  1, `roadmap-10-graphics.md` 8, `roadmap-11-dev-tools.md` 6, `roadmap-12-assistant.md` 6,
  `roadmap-13-pricing.md` 3, `roadmap-14-agent-socket.md` 10, `svg-motion-plan.md` 1. §11,
  117 lines in 17 files: `README.md` 15 (the index rows of V-1, V-5, P-4, P-6, MC-1, MC-3, MC-4,
  MC-6, R6-5, #228-P, G-33, GR-11 and three `recording.md` rows, each following its body),
  `agent-connection.md` 11, `assistant.md` 5, `chrome-inspector-keys.md` 2,
  `cloud-captions.md` 8, `deepening.md` 9, `dev-tools.md` 4, `foundations.md` 1,
  `grading-2.md` 2, `grading-3.md` 11, `grading.md` 10, `graphics.md` 8, `precision.md` 3,
  `pricing.md` 7, `publishing.md` 2, `recording.md` 17, `word-captions.md` 2.
  `designs/spec/11-decisions/rename.md` and `designs/adr/rename.md`: no line substituted.
- `tools/proof/name_residue.py`, data and comments only: `"designs/adr/"` out of `HISTORY`
  (its comment: "the rename's open road map among it"); the §11 block's comment says its lines
  are NM-12's kept classes after rename-2 N4, and the `rename.md` comment drops "N4 re-pins it
  next"; §11 pins: `README.md` 19 → 4, `agent-connection.md` 18 → 7, `assistant.md` 11 → 6,
  `chrome-inspector-keys.md` 2 → no entry, `cloud-captions.md` 11 → 3, `deepening.md` 18 → 9,
  `dev-tools.md` 10 → 6, `foundations.md` 2 → 1, `grading-2.md` 2 → no entry, `grading-3.md`
  12 → 1, `grading.md` 16 → 6, `graphics.md` 13 → 5, `precision.md` 3 → no entry,
  `pricing.md` 12 → 5, `publishing.md` 5 → 3, `recording.md` 24 → 7, `rename.md` 32 → 32,
  `word-captions.md` 6 → 4; a new ADR block, each pin new: `build-velocity.md` 1,
  `grading-3.md` 1, `remaining-closed.md` 1, `rename.md` 30, `roadmap-08-word-captions.md` 1,
  `roadmap-10-graphics.md` 2, `roadmap-11-dev-tools.md` 1. No other pin moved;
  `KEPT_PATTERNS`, `TEXT_HISTORY`, the selftest and the mutants are unchanged.

**Kept lines** (every line in both folders that still holds the old name; the letters are "The
rules"' classes; (x) lines are the ones `KEPT_PATTERNS` already allows):

- `designs/adr/build-velocity.md` 12 (f: "`PRODUCT_NAME` stays `Reelcut`"; its other three
  names substituted). `grading-2.md` 3 (x). `grading-3.md` 3 (x); 8 (f: it quotes
  `archive/grading-3.md`'s heading "T3-1 — honest sources and Reelcut's HDR→SDR at step 0",
  which keeps the old name). `precision-2.md` 3, 17 (x). `precision.md` 19 (x).
  `remaining-closed.md` 3 (p). `rename.md`, all (r): 1, 11, 17, 18, 25, 32, 33, 40, 53, 58, 63,
  69, 70, 73, 94, 101, 104, 107, 110, 113, 117, 121–124, 127, 134, 135, 150, 151; and 3, 95,
  98, 116, 139, 141, 146 (r, x). `roadmap-08-word-captions.md` 459 (q: screen 16's footnote as
  the dated run read it). `roadmap-10-graphics.md` 865 (q); 981 (q: `/Applications/Reelcut.app`;
  its "another Reelcut" substituted). `roadmap-11-dev-tools.md` 14 (f: the 29-byte marker,
  kept whole).
- `designs/spec/11-decisions/README.md` 301, 307, 308 (r); 313 (p); 314 (f, x).
  `agent-connection.md` 18, 31, 43, 61, 75, 76, 78 (r). `assistant.md` 16, 126, 174, 207–209
  (r). `cloud-captions.md` 60, 211, 212 (r). `deepening.md` 666, 669 (r; 669 is also the
  "where it was" quote, (f)), 775, 829, 831, 984, 1287 (r); 977, 1283 (q: measured runs, which
  the NM-5 amendments at 984 and 1287 say are quoted as they printed). `dev-tools.md` 19, 43,
  44, 45, 49 (r); 40 (f). `foundations.md` 27 (r). `grading-2.md` 172 (x). `grading-3.md` 14,
  371 (x); 219 (r). `grading.md` 236, 339, 340, 449, 466, 467 (r). `graphics.md` 35, 302, 614,
  820 (r); 1708 (q: the owner's words of 2026-10-09, quoted). `precision.md` 10, 17, 179 (x).
  `pricing.md` 44, 71, 91, 108 (r); 73 (s, inside NM-4 and NM-7's amendment).
  `publishing.md` 22–24 (r). `recording.md` 23, 73, 251, 253, 272, 274, 275 (r). `rename.md`
  10, 12, 30, 36, 63, 108, 110, 116, 122, 124, 129, 133, 137, 148, 149, 166 (r); 14, 139, 140,
  157 (r, x); 185 (x); 189 (f); 195–204, 209, 210, 216 (p); 222, 234 (f); 237 (x).
  `word-captions.md` 143, 292–294 (r).

**Measured** (each printed by the command beside it; the full outputs are in the phase's
`04-checks.txt`):

- `git grep -n -i reelcut -- designs/adr designs/spec/11-decisions | wc -l`: `355` at
  `def5418`, `161` after (136 counted, 25 (x)).
- The same grep less `\.claude/litecode/reelcut/|devel/reelcut`: `136`, the sum of the new pins
  in both folders (37 ADR, 99 §11); every line it prints is in the classification above.
- `git diff --numstat -- designs/adr designs/spec`: 38 rows, added equals removed on each, 196
  and 196.
- `name_residue.py`: exit 0, silent. `--selftest`: `8/8 rows pass`, `PASS`.
- `spec_index_proof.py`: `159/159 checks passed`, exit 0. `py_compile` of `name_residue.py`
  clean.
- `make gate` PASS in 106 s: names pass 1 s, test pass 104 s; typecheck, fmt, lint and app
  skipped (inputs unchanged since their last pass), over this record with this line as a
  placeholder. `make gate` ran again after the line was filled in; its output is in
  `04-checks.txt`.

**Deviations:** none from the spec's rules. Calls worth a reader's check: `graphics.md` 1708 is
the owner's quoted sentence, kept as (q) rather than edited inside its quotation marks;
`roadmap-10-graphics.md` 959's `-ReelcutExportChoice` became `-FrameJobExportChoice`, because
the sentence states how the argument domain treats that launch argument, which today's proof
passes as `FrameJobExportChoice`; §11's `rename.md` and the ADR `rename.md` were read line by
line and none of their lines substituted. No root `CLAUDE.md`
edit is owed: its `make test` line names `HISTORY` without its members.

**Owed:** phase N5.

## N5 — the record
