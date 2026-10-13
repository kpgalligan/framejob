# The rename, round 2: the old name leaves what is not history (road map "rename-2")

- **Status:** Built and closed 2026-10-13. Worked in the worktree `~/devel/reelcut-rename2` on branch `rename2`, from `ed8f282`, each phase gated there and fast-forward merged into main alone (NM-14):
  - N0, the plan: the road map, NM-12…NM-14, the amendment paragraphs on NM-1 and NM-8 (`0c703b4`)
  - N1, the archive's names (`427b9e2`)
  - N2, the handoffs' names (`55521cb`)
  - N3, the issue rule (`def5418`)
  - N4, the prose rule (`752af19`)
  - N5, the sweep and the close: this record (the commit that moved this record to `archive/`)
- **Original:** `archive/rename-2.md` is the full record. It has no section numbers, so it is cited by section name: "orig N3" is its "N3 — the record" section.
- **Spec decisions:** NM-12..NM-14 in spec §11 (`designs/spec/11-decisions/rename.md`), with the "Amended by" paragraphs at the end of NM-1 and NM-8. They stay binding, and where the original words them differently, §11's text wins:
  - NM-12: a name-only edit of §11 decision text, its index rows or `designs/adr/` is not an amendment: it reopens nothing and adds no "Amended by" line; the link rule's rewrite, the issue rule's and the prose rule's substitution are the three exceptions to append-only, and no other edit is.
  - NM-13: the archive's 19 files drop their old prefix, the handoffs are `design_handoff_chrome/`, `design_handoff_sharp/` and `_ds/design-system-…/`, and every link follows (the link rule, exceptions (a)–(e)), the only edit archive text and designer files take.
  - NM-14: round 2's scope: the issue rule; recorded results, the safety nets (until #288, after #287) and old-tree inputs keep the old name; `name_residue.py`'s new shape; phases N0–N5.

## Context

Round 1 (NM-1…NM-11, `designs/adr/rename.md`) renamed the product and kept the old name in history on purpose: the archive's file names, the design handoffs' folders, every ADR, §11's decision text and the proof README's recorded runs. On 2026-10-13 the owner asked for the old name to leave what is not history, in five items: rename the archive's files and keep their text; replace the product name in the decision records' prose, as a new §11 decision; rename the handoffs' folders and files and keep their contents; rewrite issue citations, keep recorded results, keep the safety nets until #287 and keep the inputs that build an old tree; and sweep every other non-history line. N0's inventory counted 2,107 lines in 213 files and 72 paths at `ed8f282`. (orig "Goal", "The owner's choices", "Inventory")

## Decisions

- **Two name maps, both in §11 and in the original.** The archive: `reelcut-roadmap.md` is `roadmap-1.md`, `reelcut-roadmap-N.md` is `roadmap-N.md`, and the five others drop only the `reelcut-` prefix. The handoffs: `designs/design_handoff_reelcut/` is `designs/design_handoff_chrome/` (its two `.dc.html` files and three logo SVGs renamed inside it), `designs/design_handoff_reelcut_sharp/` is `designs/design_handoff_sharp/`, and the clip inspector's `_ds/reelcut-design-system-…/` is `_ds/design-system-…/`. No new name collides with an existing archive file. (NM-13; orig "The archive's names (NM-13)", "The handoffs' names (NM-13)")
- **The link rule.** Every reference to a renamed path (the full path, the path from `designs/`, or the bare name) is rewritten wherever it appears, archive text and designer files included, and it is the only edit those files take. Kept: (a) a path already stale at `ed8f282` (`designs/reelcut-*.md`, `designs/reelcut-design.md`), which `archive/INDEX.md`'s old-name notes still resolve; (b) a command, pathspec or path run against an old commit or tree; (c) the generated bundles, manifests and lint configs inside designer folders; (d) recorded output; (e) a renaming map's old-name column. A wildcard or regex is not a reference. (NM-13; orig "The rules")
- **The issue rule.** `kpgalligan/reelcut#N` becomes `kpgalligan/framejob#N` everywhere except archive text, recorded output and designer files; GitHub redirects the old repository's citations. (NM-14; orig "The rules", "N3 — the record")
- **The prose rule and its kept classes.** In the decision text and the ADRs, an old spelling becomes NM-2's where it names the product, or a thing that exists today under the new name, and the substitution keeps the sentence true. Kept: (q) recorded output or a quote from a dated run; (p) a stale or past path or identifier; (x) an outside path real until the owner renames it; (s) an NM-7 safety net or an old app domain or folder; (r) the rename's own record; (f) a sentence the substitution would make false. A line holding both kinds takes the substitution and counts as kept. NM-12 makes it, with the link and issue rules, one of exactly three exceptions to §11's append-only rule. (NM-12; orig "The rules", "N4 — the record")
- **`TEXT_HISTORY`: lines kept, paths checked.** `name_residue.py` gained a second kind of history (N1): a prefix whose lines are allowed but whose paths still fail if they hold the old name. `archive/` moved there from `HISTORY` in N1, and the three handoff folders went there in N2 under their new names, rather than into `HISTORY` as N2's text said, so a handoff path holding the old name fails. Selftest row S7 and the mutant `text-history-paths` guard it. (NM-14; orig "N1 — the record", "N2 — the record" Deviations)
- **The sweep, with (o).** N5 read every old-name line outside `HISTORY` and `TEXT_HISTORY` and kept each by a class or renamed it. It added (o), an input for building or running an old tree (`reference_build*.py`, `grading_verdict.py`, the spikes' header rewrites, `.gitignore`'s old generated paths, the e1 reference build's lines in the proof README). The proof README's dated runs keep their quotes, commands, paths, keys and domains; their prose now names the product Frame Job, and its "**Names in records.**" paragraph says so. (orig "N5 — the record", "The sweep's table")

## What it built — where it lives now

- **N0** (`0c703b4`): the road map; NM-12…NM-14 and the "Amended by" paragraphs at the end of NM-1 and NM-8; both spec indexes; the road map in `HISTORY` while it was open. Measured: `make gate` PASS in 348 s.
- **N1** (`427b9e2`): the 19 archive `git mv`s and every link to them (88 files listed at `ed8f282`), among them the live readers `assistant_spike.py`'s `ROADMAP`, the `--leakcheck` lines and `recording_spike.py`; `archive/INDEX.md`'s first column now `` `<new>` (old name `<old>`) ``; `name_residue.py`'s `TEXT_HISTORY`, `residue()`'s `text_history`, S7 and the `text-history-paths` mutant. Measured: `make gate` PASS in 230 s; each mutant failed exactly its row.
- **N2** (`55521cb`): the 53 handoff `git mv`s and every link to them, 26 designer lines among them, each a link; `.dupscan/scan.json`'s `path` keys and `contextDocs`; the handoff folders into `TEXT_HISTORY`. Measured: `make gate` PASS in 74 s.
- **N3** (`def5418`): the issue rule over 55 files, 112 lines, each of the proof README's 12 read as prose, not recorded output; the citation pattern out of `KEPT_PATTERNS`. Measured: `make gate` PASS in 310 s.
- **N4** (`752af19`): the prose rule over `designs/adr/` and `designs/spec/11-decisions/`: 355 lines read, 196 substituted in 38 files, no file changing length; `designs/adr/` out of `HISTORY`, each ADR still holding the name pinned in `COUNTED`. Measured: `make gate` PASS in 106 s.
- **N5** (the commit that moved this record to `archive/`): the sweep of 432 lines in 47 files; 16 lines renamed (14 in the proof README, one in each of two spike READMEs) and the README's "**Names in records.**" paragraph rewritten; `name_residue.py`'s `HISTORY` down to `designs/clip_inspector_brief/` and `.dupscan/`, its road map entry gone, the proof README re-pinned, the two spike pins dropped, this record pinned; §11's intro sentence for this road map and its two citations of the original repointed to `archive/rename-2.md`; this record, the `git mv` and its `archive/INDEX.md` row; the root `CLAUDE.md`'s entry for this record, applied by the orchestrator.

What `name_residue.py` holds now: `HISTORY` (the brief and `.dupscan/`, kept whole); `TEXT_HISTORY` (`archive/` and the three handoff folders, lines kept, paths checked); `KEPT_PATTERNS` (the two outside paths, `.claude/litecode/reelcut/` and `devel/reelcut…`); `COUNTED`, exact pins for §11's and the ADRs' kept lines, the proof README's recorded results, root `CLAUDE.md`'s NM-7 folder, `.gitignore`, the safety nets, the old-tree inputs and one spike README's past input path. `git ls-files -co --exclude-standard` lists no path holding the old name.

## Known limits

- **An outside link to an old path breaks**: a bookmark or another repository's link to an archive file or a handoff folder by its old name.
- **Generated designer files keep stale paths** (exception (c)): `_ds_bundle.js`, `_ds_manifest.json`, `_adherence.oxlintrc.json` and `design/runtime/ds_bundle.js` name folders that no longer exist.
- **A citation's redirect depends on GitHub** keeping the old repository name free; archive text and recorded output still cite `kpgalligan/reelcut#N`.
- **A pin can hide a swapped line** (NM-8): a counted file that loses one old-name line and gains another passes.
- **A dated record's prose was substituted but its quotes were not**, so a paragraph of the proof README or a decision can name Frame Job beside a quoted log line or path that names the old product.

## Open items

- #288 (`ai-drafted`, `low-priority`, blocked by #287): drop the proofs' old-name safety nets (`proof_defaults.py`, `mcp.py`'s app-name match, `harness/main.swift`'s key mapping, `budget.py`'s NM-7 guard, `budget_proof.py`, `grading_verdict.py`'s dual prefix, `stale_registrations.py`) once the hand steps are done. Done: spec §11 NM-15.
- #287 (`ready-for-human`): the owner's hand steps from round 1, which #288 waits on.

## Where to look in the original

- "Goal" and "The owner's choices": the owner's five items, verbatim, and why NM-12 names three exceptions where item 2 asked for one.
- "Inventory": the command, the thirteen category rows at `ed8f282`, the paths.
- "The archive's names (NM-13)" and "The handoffs' names (NM-13)": the two maps, row by row.
- "The rules": the link rule and (a)–(e), the issue rule, the prose rule and its classes.
- "The traps": `gate.py`'s `archive/` exclusion, whole-basename matching, the live readers of archive paths, the designer `href`/`src` lines, `.dupscan/`, the Lines cells, exact pins.
- "Phases" and "Verification per phase": what each phase was to do and how it was checked.
- "N0 — the record" … "N5 — the record": what landed, the measured rows (with each command), the deviations and what each phase owed; N4's "Kept lines" classify every ADR and §11 line that keeps the name, and N5's "The sweep's table" every other file's.
