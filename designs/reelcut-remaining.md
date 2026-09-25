# Reelcut — what is left

**Status: road map 2 is complete, and the debt it left is paid.** All ten
phases are done and `designs/reelcut-roadmap-2.md` §1 carries the commit of
each. **On the day it closed** `make test` was at 494, `make lint` and
`cargo fmt --check` were clean, `make typecheck` was at 0 errors and its four
deliberate AVFoundation warnings, the catalog was 75 tools and the parity log
empty, and every proof script passed: 66, 85, 121, 8, 84, 88, 167, 92, 79,
214 and 79 over MCP and 26, 33, 59, 81, 70, 78, 150, 48, 62 and 141
offscreen. Those counts are that day's; §3 is the part of this file that is
kept current.

This file was written as the honest remainder when the road map closed: the
debt two large phases left behind, plus the checks no script can make. §1 and
§2 were that debt and are now CLOSED; they stay here as the record of what
closed them, because each one taught something the next reader should not
have to relearn. §3, §4 and §5 are what is still open, and none of them is a
task with a diff at the end of it; §6, added 2026-09-19, was the one that
was, and its diff landed the same day.

Three rules from `designs/reelcut-roadmap-2.md` §0 governed the closing and
are not restated per item: a file at the ~600-line cap gives something up
BEFORE it takes anything on; frozen files take wiring only; and a claim about
a frame is a byte comparison or it is not a proof.

---

## 1. Two fixes that shipped without a permanent proof — CLOSED

This was the only item where the project's own standard was not met. Phase
9's fix wave produced two instruments that measured their fixes and were then
left untracked in the git-ignored `tools/proof/work/`, so the fixes were
correct and the evidence for them was not in the tree. Both instruments are
tracked now and both untracked originals are deleted.

### 1a. The marker-scope refusal — `phase9_proof.py` section 9

The lane script had **28** `check(...)` calls, not the 29 this file said —
the 29th was `def check`, counted by a bare `grep -c`. They are transcribed
with their own wording as `marker_scope_part`, section 9 of
`tools/proof/phase9_proof.py`, before the documented limits (now section
10), with one check tightened (`msg2 == msg` passed VACUOUSLY under the
refusal mutant, `None == None`) and two the fold added: the exact text of
the wrong-typed-tick refusal, and the undo of an inherited-scope
`remove_marker` restoring the marker ON THE DOCUMENT with the nest still
open. Thirty checks; the script is **214/214**.

The gate, on copies of the tree with the app built in each:
`checkDocumentLevelTicks` made a no-op scores 209/214 and takes the five
refusal checks (its own marker lands at nest-local 0, and the `set_marker`
that follows collides with it — exactly the wrong placement the refusal
exists to prevent); `scopeLanding` replaced by the old unconditional echo
scores 209/214 and takes the five `document_ops` checks.

### 1b. The breadcrumb, photographed — `phase9_chrome.py`

Route 1 was taken — a probe compiled from `app/Sources`, not two harness
arguments — and its docstring says why: a harness render is at scroll 0 and
the defect only shows scrolled, and a photograph cannot read a click count or
a validator. **62/62.** Six scenes of a bare `TimelineView` (at rest and
scrolled, with and without a trail, a rename open and a rename ENDED), the
corner byte-compared as a decoded 264×44 px crop that prints where it
differs, and the gesture half read as the `Equatable` `TimelineHit` rather
than a string.

Two things the untracked instrument got wrong, corrected in the tracked one:
its six-track fixture was NOT scrollable — six text tracks at size index 1
are 306 pt against a 324 pt pane, so its 62 pt scroll was an unclamped
over-scroll through `NSClipView.scroll(to:)`, valid for the z-order pictures
but a state the app never reaches — and the tracked script uses ten tracks
and asserts the scroll is real; and its scenes never ENDED a rename, so a
mutant deleting `endRename`'s restore line would have survived them.

The gate is a MUTANT on a copy of `app/Sources`, and it had to be: no git
commit has the old z-order WITH a breadcrumb (phase 9's app commit ships the
fix, and its parent has neither). Init order swapped back to ruler-then-
headers scores 52/62; `endRename`'s restore deleted 57/62; the double-click
guard flipped 55/62. All three named in the script's docstring and the
README.

---

## 2. Two live defects, found and deliberately left — CLOSED

### 2a. `generateCaches`'s doc was false; now it is true

The sentence "Safe to call repeatedly — a cache already on disk is not
rebuilt" was measured false: every call re-decoded every media's filmstrip
and re-read its audio, and four comments repeated the claim. This file
offered two cures and asked for a decision. **The decision was a third
shape: a completion marker keyed to the source file's identity**, because
the doc-only cure leaves every open of a saved project re-decoding a
40-minute screencast, and the plain existence check is a WRONG PICTURE, not
a behaviour change — `relink_media` keeps the media id, so `thumbs/<id>/`
already exists with the old film's frames and a relinked media would never
get new ones, and Remove Silences and Normalize would measure the old file.

What landed (spec §5.6; `MediaCacheFiles.swift`, after a pure move took the
await-free half of the cache out of `MediaImporter.swift` first and alone,
`3e5b598`): `CacheStamp` — the source's byte size and modification second
plus the record fields and generator constants that size a cache — written
LAST by a finished pass as `thumbs/<id>/complete.json` and
`peaks/<id>.complete.json`, and carrying NO path, deliberately: the reversed
cache's digest names a file in a directory shared with other sources and
must tell them apart, while a marker sits inside one media's own cache, and
leaving the path out is what lets a moved package, a consolidated copy and a
copy on another disk keep every filmstrip. `generateCaches`'s task stats the
file once and hands the stamp to both halves; `thumbnails` and `peaks`
compare it with their marker at the head and return without decoding when it
matches; a relinked, changed, partial or unmarked cache is deleted — the old
frames, or the old `.bin`, whose withdrawal is posted at once so nothing
measures the previous file's sound meanwhile — and rebuilt, and the marker
is written LAST and only for a strip the pass can vouch for: at least one
frame landed and every frame it wrote is still there when the loop ends. The
FIRST post of a replacing pass says `replaced`, which is what lets
`TimelineView.swift` (five wiring lines) drop that media's decoded tiles only
then — a relink used to leave the old film on screen until the 800-entry
drop, pre-existing. Passes for one media run one at a time in CALL ORDER
through `CacheLedger`, an `NSLock` rather than an actor, because a pass
carries the URL the media resolved to when asked and two `Task` hops from one
thread are not ordered. The false sentence is now the true one in every
place it stood, and `MediaImporter.generateCaches`'s "a cancelled import (the
document closing)" — a case that does not exist; nothing cancels the task —
names the real partial cases: a first save mid-pass, a save of a TITLED
document mid-pass (NSDocument swaps the package and the frames written
between its listing and the swap are lost — the vouching rule is what keeps
that strip unmarked), and process death.

**The first landing passed its own gate and was still wrong twice**, which
is the sentence to keep. Its review found the titled-document save (the
marker certified the holes) and the peaks half leaving the old `.bin`
readable through a rebuild, plus a reader that fails on every frame
certifying an empty strip, an image whose decode fails posting nothing, and
`replaced` on every batch post; all fixed, each with a row that a copy
without the fix fails. The size toll came due a second time mid-fix (644
against the cap) and was paid by moving the peak-bucket arithmetic to
`MediaCacheFiles.swift` as `PeakBuckets`, its `.bin` byte-identical to the
pre-move binary's; 586 and 490 after.

Measured: `tools/proof/remaining_proof.py` **79/79** over MCP, whose
instrument is `os.stat`'s inode and nanosecond mtime across a 3 s window
against a baseline read before the trigger, bounded by a positive control
whose measured rebuild latency (0.06 s here) is asserted inside that window;
`copyItem` preserves `st_mtime_ns`, so Consolidate rebuilds nothing, which
the script asserts and prints; and a relink to a file with no audio track
withdraws the `.bin`, after which `detect_silence` reports the media pending
rather than answering from the old file. `remaining_probe.py` sections 2–5
are the app side: the stamp as pure calls (a byte copy at another path is
EQUAL), the ledger as a count of posts, the stale-tile wiring as pixels (red,
then blue), and the pass's own rules — a frame deleted mid-pass earns no
marker and a retry, an unreadable file earns none, a failed image decode
still posts, one post carries `replaced`, a withdrawal posts once. Twelve
mutants, none surviving: the thumbs head check deleted 65/69, `modified`
forced to 0 59/69, a 4 s sleep after the head check 67/69, the peaks head
check deleted 75/79, `clearPeaks` back to marker-only 76/79; the ledger
removed 107/108, the hit-clearing removed 105/108, the presence check removed
138/141, its empty-set guard removed 139/141, the withdrawal's probe half
139/141, the image post moved back 140/141, `replaced` on every post
140/141. Phases 2, 3, 3-silence and 5, whose fixtures read the peaks path,
still score 85, 121, 8 and 88.

Recorded, not fixed, beside the code: `relink_media` never re-probes, so a
relink to a file of another length sizes the new strip and the bucket count
from the old `duration`; the marker rebuilds on a relink, at the old length.
The ledger's price is that a pass stuck inside one AVFoundation call (a
stalled network volume) holds every later pass for that media, a relink away
from the stalled file included; the escape does not help a stuck call and
reintroduces the interleave for a slow one, so it was argued and not built.
And `stripHolds`' listing and the marker's write are two steps, so a swap
landing between them (one directory read wide) would still certify holes.

### 2b. `CaptionExporter`'s bare `deletingPathExtension` — and two siblings

The item's premise was half wrong, and the scout caught it before a line was
written. The format popup's site wanted the `{srt, vtt}` set this file
described — it is `CaptionExporter.renamed`, `FrameWriter.renamed`'s six
lines with `rawValue` for `fileExtension`. The other site strips the
DOCUMENT's extension off a title-bar name (`displayName`, which is
`Board v1.2.reelcut` or `Board v1.2` depending on Finder), so a caption set
there would have written `Board v1.2.reelcut.srt`; its set is `{reelcut}`,
and two siblings had the identical bare strip on the same name — Save
Frame's stem and the export sheet's `suggestedName`. All three read
`ProjectDocument.displayStem` now (`ProjectDocument+DisplayStem.swift`, an
extension because the base file is over the cap).

Both sites are PANEL-only, and the MCP path was right all along —
`export_captions` goes through `destinationURL`, which strips only a
`replaceableExtensions` member and appends otherwise — so an MCP check for
`Board v1.2` passes against the unfixed build and cannot be the evidence.
The proof is `tools/proof/remaining_probe.py`'s section 1: tables over the
three helpers (and it is the first instrument to call `FrameWriter.renamed`,
whatever that function's docstring claimed since phase 7), the instance
accessor over a live document, and a STRUCTURAL read that the four sites
actually call their helpers — because an unwired site with correct helpers
beside it scored 60/60 on the behavioural rows. Three mutants: the caption
helper reverted 59/63, the stem helper reverted 60/63, one site unwired
60/63. Recorded limit, pinned rather than fixed: a caption panel name
carrying another of the app's own containers — `chart.png` under SubRip — is
`chart.png.srt` in the panel and `chart.srt` over MCP; widening the set
would be the bare strip with a longer list.

---

## 3. The size debt

Every file over the ~600-line cap as of 2026-09-20 — 27 of them, the
list regenerated row by row against `wc -l` at road map 7's D3·6, which
closed deepening D3, and regenerated again by the command below when road
map 6's C1 tolls took two files off it. `core/src/edit_track.rs` came off
it at D2·3 (674 → 522, `edit_canvas.rs` cut out of it) and nothing had
joined since until `app/Sources/Controls.swift` joined on 2026-09-23.

**What deepening D3 did to this list**, measured against `main` rather than
summed from the tickets (road map 7 §7–§9). `core/src/edit.rs` lost its
Arguments column, **895 → 838**: still over, and still exempt for the
SEMANTICS table that is the rest of it. That column is now data in two new
core modules, both under the 400-line cap for a new module and neither taking
`edit.rs`'s exemption — `core/src/op_table.rs` (**325** of 400) and
`core/src/op_schema.rs` (**173** of 400). On the app side the five catalog
files went **2251 → 2125** together as the structure they used to hand-write
moved to the core: `AgentCatalog+Clips.swift` **941 → 791**, the first time an
over-cap file here has come DOWN without anything being moved out of it;
`AgentCatalog+Files.swift` 609 → **601** (over by one line);
`AgentCatalog+Transitions.swift` 112 → **92**; `AgentCatalog.swift`
472 → **524**, which took `opTool` and ten argument descriptions the fifth
part of the parity check turned from a silence into a complaint; and
`AgentCatalog+Audio.swift` **117**, untouched, its two tools having no op
behind them. Three new app files stand against that, all under the 400-line
cap: `app/Sources/AgentCatalog+Declarations.swift` (**313** — the fourteen
rows where a tool deliberately takes more or less than its op, with a reason
each), `app/Sources/AgentServer+Parity.swift` (**183** — the fifth part and
nothing else) and `app/Sources/ReelOpSchema.swift` (**27**).
`AgentServer.swift`, frozen, is **771 → 774**: twelve lines of doc comment
taken across D3·3 and D3·4 and nine given back at D3·5, when the two
paragraphs describing the gap that part has now closed stopped being true.
Then **774 → 785** at kpgalligan/reelcut#21: the argument gate's two wiring
lines in `start()` and `dispatch`, and the comments saying that a call's keys
are now checked and that a stray `scope` is refused rather than ignored. The
gate itself is `app/Sources/AgentServer+Gate.swift` (**101** of 400);
`AgentServer+Arguments.swift` is 445 → **458** for the exact whole-number
read and `AgentServer+Parity.swift` 183 → **186** for the envelope list the
two files now share. Then 2026-09-20's frame-rate term readers:
`AgentServer+Arguments.swift` 458 → **502** for `rateTerm` and `fpsPair` and
their doc comments, while the two callers came DOWN —
`AgentServer+Tracks.swift` 243 → **240** and `AgentServer+Media.swift`
320 → **318** — none of the three on this ledger and none near the ~600 cap.
`ReelCore.swift` is **1500 → 1542** and stays where it was in this list — it
is over the cap, so only the part that had to be there went in, the function
naming `rc_op_schemas`, and the value type it answers went to
`ReelOpSchema.swift` instead.

**What road map 7 §10's phase A did to it** (2026-09-19, measured with
`wc -l` against `47db3ae`). The source-window module is a PURE MOVE, so the
test is that every file it touched came down. `core/src/model_query.rs`
**503 → 440** and the three readers, the mover, the bound and the two tail
readers are `core/src/source_window.rs` (**251** of the 400-line cap for a
new module). Every caller shrank because it stopped restating the
arithmetic: `core/src/edit_clip.rs` **1036 → 1021** (the one row of the table
below that moved, and still over the cap and still the largest Rust file),
`core/src/edit_edge.rs` 220 → **197**, `core/src/edit_split.rs` 210 → **195**,
`core/src/edit_transition.rs` 586 → **572**, `core/src/evaluate.rs`
594 → **588**, `core/src/edit_time.rs` 560 → **555**, and
`core/src/edit_canvas.rs` **241**, unchanged to the line. The one file that
grew is `core/src/lib.rs`, 83 → **84**, which is the module declaration.
`app/Sources/Transcriber.swift` stays **934**: phase A changed two of its
comments and nothing else. Nothing came off this list and nothing joined it.

**What §10's phase B did to it** (2026-09-20, `wc -l` against the tree as
phase B found it — phase A's, uncommitted). Phase B is a FEATURE, not a
move, so the test is the opposite one: no file over the cap took anything
on. `core/src/edit_clip.rs` is **1021**, unchanged to the line — the four
call sites that now read the module cost lines and `whole_media_length`'s
and `set_speed`'s own prose gave the same number back, since the module
states the arithmetic they used to restate. The catalog file
`app/Sources/AgentCatalog+Clips.swift` is **792**, unchanged to the line for
the same reason, two tool sentences rewritten inside their own wrapping.
Under the cap:
`core/src/source_window.rs` 251 → **396** of its 400-line cap, which is the
warning for the phase after this one; `core/src/edit_paste.rs` 596 →
**599**; `core/src/edit_background.rs` 468 → **479**;
`core/src/edit_nest.rs` 323 → **326**; `core/src/evaluate.rs` 588 → **591**
(a comment); `core/src/edit_canvas.rs` 241 → **236**;
`core/src/edit_transition.rs` 572 → **571**; `core/src/edit_edge.rs` and
`core/src/edit.rs` unchanged at **197** and **838**. The two new test files
are `core/tests/source_invariant.rs` (**360**) and
`core/tests/source_edges.rs` (**176**), both under the 400-line cap for a
new file. `app/Sources/ReelOps.swift` is 1131 → **1144**, a doc comment on
`setSpeed` and one on `addBackground`; it is an exempt table and the row
below is updated. Nothing came off this list and nothing joined it.

**What §10's phase C did to it** (2026-09-20, `wc -l` against the tree as
phase C found it — phases A and B's, uncommitted). Two files over the cap
took nothing on: `app/Sources/ReverseRenderer.swift` is **1311**, unchanged
to the line — its two subtractions now call `ReverseMirror` and the prose in
its type doc and in `walkBackwards` that used to restate the mirror gave the
three lines back — and `app/Sources/Transcriber.swift` is **934**, one
`private` removed so a probe can pin `project(_:in:)`.
`app/Sources/ReelOps.swift` is 1144 → **1143** (one sentence deleted from
`setSpeed`, which is no longer true). The FROZEN
`app/Sources/TimelineView.swift` is 1644 → **1652**: `sourceTime` gained the
`in media:` parameter, the reversed arm and the five lines saying why, which
is the dispatch that file holds. The new file is
`app/Sources/ReverseMirror.swift` (**88** of the 400-line cap for a new one).
`app/Sources/SpeedSheetController.swift` is 219 → **246** and
`app/Sources/MediaPeaks.swift` 236 → **228**, both well under. Nothing came
off this list and nothing joined it.

**What the E1 reader review did to it** (2026-09-20, road map 5 §12). **Toll
T was paid**, a pure move landed and gated alone by `make test` and
`make lint` before any fix touched the file: `add_transition_by_shift` and
its doc comment left `core/src/edit_transition.rs` for a new
`core/src/edit_transition_shift.rs` (**114** of the 400-line cap for a new
file), taking the three `edit_time.rs` imports with them, and the file went
571 → 477. The review's three `add_transition` fixes then took it to
**530**, still 70 under. `app/Sources/EditorViewController+Inspector.swift`
is 340 → **381**, under the cap: `shiftingOps` and its doc. Two new test
files at or under the 400-line cap:
`core/tests/add_transition_edges.rs` (**400**, AT the cap after the review's
fix pass added the short-pair rows — it gives something up before it takes
anything on) and `core/tests/crossfade_edges.rs` (**337**). Nothing came off this list and
nothing joined it.

**What road map 6's C1 tolls did to it** (2026-09-20, `wc -l` against the
tree as C1's first pipeline found it, `cfcd0959`; road map 6 §10). Three
pure moves, each gated and tree-snapshotted alone, and **two files came OFF
this list** — the first time two have in one pipeline.
`app/Sources/Transcriber.swift` **934 → 553** (the language block, the
extractor and the job builder out to `app/Sources/Transcriber+Languages.swift`
(**172**), `app/Sources/Transcriber+Extract.swift` (**143**) and
`app/Sources/Transcriber+Jobs.swift` (**117**), all well under the 400-line
cap a new file gets) and `app/Sources/AgentCatalog+Files.swift`, over by one
line at **601 → 487** (the three caption rows out to
`app/Sources/AgentCatalog+Captions.swift`, **165**, and spliced back where
they were). Both rows are struck from the table below, which is what the
regenerate command now prints. Under the cap already and still under it:
`app/Sources/TranscribeSheetController.swift` **505 → 380** (the run's one
exit and the menu command to `app/Sources/TranscribeSheetController+Commit.swift`,
**145**), which was the toll §5h asked for against the ~150 lines C1's later
pipelines will add. Two files grew by a pointer and nothing else:
`app/Sources/AgentCatalog.swift` 524 → **525**, one line of doc naming the
new file, and the FROZEN `app/Sources/EditorViewController.swift` **1123,
unchanged to the line** — two comments, both naming a file that moved. It
stays on the list, having taken nothing on.

**What road map 6's C1 RUN did to it** (2026-09-20, `wc -l`; road map 6
§10.10). Nothing: not one file on this list was touched, and no file it
touched came near the ~600 cap. The nine Swift files it changed or made are
`CloudTranscriber.swift` 102 → **296**, `CloudTranscriber+Media.swift`
(**183**, new), `CloudProgress.swift` (**141**, new),
`AgentServer+CloudCaptions.swift` (**247**, new),
`AgentServer+Captions.swift` 409 → **439**, `AgentCatalog+Captions.swift`
165 → **215**, `Transcriber+Jobs.swift` 117 → **178**,
`MediaTranscript.swift` 379 → **383** and `Transcriber.swift` 584 → **583**,
which came back one line UNDER where it was. Every new file is inside the
400-line cap; `MediaTranscript.swift` at **383** is the closest to it and is
the one to watch.

**What road map 8's W3 did to it** (2026-09-22, `wc -l`; road map 8
§10.7). Three tolls, each a pure move gated alone before the word-caption
picture took anything on: `LayerRenderersText.swift` **577 → 408** (its three
reveal routines to `LayerRenderersReveal.swift`, **186**, new), then **440**
with the feature; `ProjectSnapshot.swift` **2516 → 2289** (the text group
and `RecipeReveal` to `TextProps.swift`, **241**, new), then **2293** —
`RecipeSourceRef`'s four lines for `word` / `word_pop`, the only growth; and
`ReelCore.swift` **1542 → 1440** (`TextPatch` to `TextPatch.swift`, **113**,
new), unchanged by the feature. `AgentCatalog+Clips.swift` grew **792 →
799**, `set_text`'s three new keys in `textPatchDescription`'s prose, which
cannot move purely; `TextPane.swift` **513 → 530**. New and inside the cap:
`WordProps.swift` **215**, `LayerRenderersWords.swift` **247**, and
`TextProps.swift` / `TextPatch.swift` at **274** / **133** with the feature.

**What road map 10's G1a did to it** (2026-09-24, `wc -l` against
`c5f3265`; road map 10 §10.4). One toll, a pure move gated alone before
G1d's graphics wrappers take anything on: `ReelCore.swift` **1440 → 1309**
(`RecipeSource`, the compositor's recipe registry, to `RecipeSource.swift`,
**135**, new — a 133-line block and the blank before it out, 3 header lines
in). It frees 131 lines against G1d's ~110; if the wrappers measure more,
the next seam is road map 10 §5e's own candidate, the media helpers (~94).

**What road map 10's G1d did to it** (2026-09-25, `wc -l` against
`cea2ddf`; road map 10 §10.4). The graphics wrappers — `GraphicDiagnostic`,
`GraphicFailure`, `GraphicRaster`, `GraphicLibrary`, `GraphicModule` and a
private diag-taker, plus the header's type list — took `ReelCore.swift`
**1309 → 1440**, 131 lines net, exactly the room G1a made; no second move.
The file is back at its pre-G1a count and the next thing it takes on pays a
toll first: the media helpers (~94) are still the named seam, then the
`dictionary` extensions. In the core, `ffi_graphic.rs` is new at **397** and
`recipe.rs` grew **582 → 594** (`content_hash`'s sort).

**What road map 10's G2a did to it** (2026-09-25, `wc -l` against
`fe16e94`; road map 10 §10.5). The graphic clip and its two ops, with no
toll: every new line that could go in a new module did. In the core,
`model_graphic.rs` (**399** of 400) and `edit_graphic.rs` (**283**) are
new; `edit_clip.rs` **751 → 757** (`Described` and `add_described_clip`
made `pub(crate)` for `edit_graphic.rs`, the `graphic` field and its three
`None`s), `edit.rs` **843 → 893** (two variants, two dispatch arms, two
semantics rows — its standing exemption), `recipe.rs` **594 → 596** (the
`Source::Graphic` placeholder arm G2b replaces; 4 lines under the cap) and
`op_table.rs` **331 → 338** of 400. In the app, `ProjectSnapshot.swift`
**2293 → 2305** (`ClipSource.graphic` and its arms), `AgentServer.swift`
(frozen) **785 → 790** (the two `opsWithoutTools` entries G3 deletes) and
`ReelOps.swift` **1163 → 1191** (the two raw factories; a table row per op,
exempt).

**What road map 10's G2b did to it** (2026-09-25, `wc -l` against
`986cf5a`; road map 10 §10.5). The graphic's timeline rules and its layer,
core only, with no toll: the arithmetic went into a new
`recipe_graphic.rs` (**129**) because both natural homes are at their caps
(`model_graphic.rs` **399**, a comment reworded in place;
`source_window.rs` **396**, untouched). `recipe.rs` **596 → 596** (the
placeholder's two lines out, one arm and one `use` in — still 4 under the
cap); `edit.rs` **893 → 893** (six row clauses, no new lines);
`edit_split.rs` **218 → 233**, `edit_clip_timing.rs` **177 → 182**,
`edit_edge.rs` **203 → 207**, `edit_action.rs` **451 → 469**, `lib.rs`
**95 → 96**. Nothing in the app moved.

Regenerate the list with
`wc -l app/Sources/*.swift core/src/*.rs | awk '$1>600 && $2!="total"' | sort -rn`
rather than trusting the numbers here; the standing exemptions are
`core/src/edit.rs` and `app/Sources/ReelOps.swift`, which are TABLES with one
row per op.

| File | Lines |
|---|---|
| `app/Sources/ProjectSnapshot.swift` | 2313 after road map 10's G3b (2309 after G3a; 2305 after G2a; 2293 before it; 2516 before road map 8's W3) |
| `app/Sources/InspectorPane.swift` | 1665 |
| `app/Sources/TimelineView.swift` | 1652 |
| `app/Sources/ReelCore.swift` | 1440 (1309 after road map 10's G1a, then G1d's wrappers; 1542 before road map 8's W3) |
| `app/Sources/VideoPane.swift` | 1411 |
| `app/Sources/Compositor.swift` | 1396 after road map 10's G3b (1391 before it) |
| `app/Sources/ProjectDocument.swift` | 1335 after road map 10's G3b (1336 after G3a; 1380 before it; its media-import block moved out first and alone) |
| `app/Sources/ReverseRenderer.swift` | 1311 |
| `app/Sources/ReelOps.swift` | 1191 after road map 10's G2a (1163 before it) |
| `app/Sources/EditorViewController.swift` | 1127 after road map 10's G3b (1124 before it) |
| `app/Sources/ExporterWriter.swift` | 1096 after road map 10's G3c (1114 before it) |
| `app/Sources/PreviewCanvasView.swift` | 1104 |
| `app/Sources/CanvasSessions.swift` | 1088 |
| `app/Sources/OptionControls.swift` | 1081 |
| `core/src/edit_clip.rs` | 757 after road map 10's G2a; 751 after road map 7 part 3; 1021 before its pure move |
| `app/Sources/AudioDSP.swift` | 890 |
| `app/Sources/AgentServer+Clips.swift` | 847 |
| `core/src/edit.rs` | 893 after road map 10's G2a (843 before it) |
| `app/Sources/AgentCatalog+Clips.swift` | 799 (792 before road map 8's W3) |
| `app/Sources/AgentServer.swift` | 788 after road map 10's G3b (790 after G2a; 785 before it) |
| `app/Sources/FFmpegRewrap.swift` | 768 |
| `app/Sources/Loudness.swift` | 742 |
| `app/Sources/Controls.swift` | 651 (567 before the sharp pass; Rasterize's own copy is 624 — the sync rule, app/CLAUDE.md "Shared chrome", is why it took `BlockSlider` verbatim and shed nothing; the seven lines over the verbatim block are the SH-2 fork of `drawBar`) |
| `app/Sources/ExportSheetController.swift` | 639 |
| `app/Sources/ClipPane.swift` | 609 |
| `app/Sources/MediaImporter.swift` | 604 at the pre-#23 baseline; 580 after its separately gated move |
| `app/Sources/CompositionBuilder.swift` | 601 at the pre-#34 baseline; 577 after its separately gated move to `CompositionBuilder+AudioTracks.swift` |

Road map 7 part 1 did not pay a size toll on those capped files. At this
gate `edit_transition.rs` is 537 lines, `edit_transition_shift.rs` 119,
and the new `transition_search.rs` and `time_bounds.rs` are 108 and 71;
`edit_clip.rs` remains 1021, `edit.rs` 838 under its semantics-table
exemption, and `edit_paste.rs` 599. Recount before a later part edits one.

The notes below are from road map 3's close and name each file's SEAM, which
is what a phase needs before it pays; the counts in them are as of that day.
Road map 3 paid three tolls — `AgentCatalog.swift` first and alone (R1·toll),
then `MediaImporter.swift` and `AgentServer+Recording.swift` mid-fix-wave
when a fix took each over its line — and left two files AT the cap:

| File | Now | Note |
|---|---|---|
| `AgentServer+Scope.swift` | 592 | ON the cap. Seam: the envelope rule (`checkCallScope`, `effectiveScope`, `idScope`, `addressed`, `checkDocumentLevelTicks`, `scopeLanding`, `scopeFailure`) against `set_scope` THE TOOL and its path arithmetic (`setScope`, `nestScopePath`, `pathToClip`, `applyNestScope`, `commonPrefix`, `scopeReport`) |
| `MediaImporter.swift` | 580 after #23's pure move | Went to 619 when road map 3's held tail landed in it, and paid mid-wave: the await-free half — `ImportError`, `isImage`/`probeImage`, the rate table — to `MediaImporter+Probe.swift` (121), a pure move. #23's separate move takes the synchronous reader and writer to `MediaImporter+Peaks.swift` (39) and the buckets from `MediaCacheFiles.swift` (556 → 478) to `MediaPeakBuckets.swift` (82); the asset and track awaits stay here. |
| `AgentCatalog.swift` | 454 | Was cut to 665 in `b410125`, phase 9 put it back over at 807, and road map 3's R1·toll paid the cut the file's own header had named, first and alone: the FILE groups — Media, Captions, Rendering and export — are `AgentCatalog+Files.swift` (**609** with `record_screen`'s entry — over the cap since R2 hoisted the entry's pause and result paragraphs into two locals for the type checker's budget; the cut it owes is that entry's sentences, whose description is the longest in the catalog; the cut it will owe is that entry's sentences), spliced after the Canvas group as the clip rows are. The header's "sharing no hoisted local" was false by ONE, `ticks`, which `fileTools(ticks:)` takes as an argument |
| `CompositionBuilder.swift` | 577 after #34's pure move | Was AT the cap (601) since road map 3's held tail (+83); #34 paid first and alone — the audio loop of `build` and `fill`'s source resolution moved to `CompositionBuilder+AudioTracks.swift` (159 with the format families), a pure move gated before the families landed. `audioParameters` stays here; it is the next cut |
| `ReelOps.swift` | 925 | Created by `b410125` at 853. It is a TABLE — one factory per row of `edit.rs`'s op table — so it has the same standing exemption `edit.rs` has on the Rust side |
| `ProjectDocument.swift` | 1348 | Stored properties cannot move to an extension; the natural cut is the media/reverse machinery, NOT the scope. `ProjectDocument+DisplayStem.swift` is the shape a pure addition takes meanwhile; road map 3 added ONE internal method (`adoptImported`, +12 lines) so `ProjectDocument+Recording.swift` could build the untitled document by File ▸ Open's own spelling |
| `TimelineView.swift` | 1652 | Frozen. Of the five lines the cache marker added, one is behaviour (the hit-clearing under `replaced`); the marquee's `.outside` case and `beginMarquee` added fourteen net on 2026-09-19, and road map 7 §10's phase C eight more for `sourceTime`'s reversed arm on 2026-09-20 — the dispatch the file says it holds |
| `ExporterWriter.swift` | 1096 after road map 10's G3c | Over since phase 7; its seam — the settings/encoder half — is still unpaid |
| `AgentServer+Clips.swift` | 1196 | Over since phase 6. Road map 7's D1·3, D1·4 and D1·5 took it to **847** by deleting what the agent door used to check by hand — the last of it `checkActionPatch`, `checkVideoEnums`, `checkTextEnums`, the three per-group key sets and the region reader. D1·6 took the shared launder out of `AgentServer+Arguments.swift` (562 → **445**, under the cap and not in the list above), so the whole `AgentServer*` family is **617 lines smaller than before D1**. The seam still unpaid here is the clip-placement handlers against the property doors |

**What the E2 reader review did to it** (2026-09-20, `wc -l`; road map 5
§12). Six product files were touched and NONE joined the list. In the core,
`motion.rs` **456 → 483** (nine lines of module doc and four of arithmetic
for the reduction's own 360, then fourteen more when the fix pass widened
that reduction to a chosen band under a whole turn — chosen, NOT a
consumer's precision; road map 5 §12's closing block — then **491** when the
residue run restated the reason) and `edit_props.rs` **328 → 356** (the
`normalise_and_check_group` the paste side has no room to hold), then
**363** when the residue run restated its doc comments; the paste
side itself paid nothing, because the fix was a one-line call swap and
`edit_paste.rs` is **599, unchanged** — the "one line of room" file stayed
at one line of room, which is the whole point of putting the body next to
`check_group`. In the app, `EditorViewController+Motion.swift` **151 →
176**, `EditorViewController+ZoomRegion.swift` **482 → 502** and
`TimelineClipDrawing.swift` **450 → 454**, all well under. One new test
file, `core/tests/motion_edges.rs` (**285**, then **370** for the fix pass's
seventh test, then **375** when the residue run restated the reason, of the
400-line cap a new file gets), and `tools/proof/e2_chrome.py` **901 →
1138**, then **1233** when the residue run added N·1's two extremes rows,
which is a proof script and not held to the cap
(`designs/reelcut-roadmap-7.md` §2.4).

**What road map 6's c1-chrome did to it** (2026-09-20, `wc -l`; road map 6
§10.11). **Nothing joined this list**, and three files ended a line under a
cap rather than over one. Three new files, all under the 400-line cap a new
file gets: `app/Sources/CloudEstimate.swift` (**328**),
`app/Sources/SettingsWindowController.swift` (**376**, with
`extension AppDelegate { showSettings }` at its foot, so `AppDelegate.swift`
was not touched at all) and
`app/Sources/TranscribeSheetController+Cloud.swift` (**313**).
`TranscribeSheetController.swift` is 380 → **540** against the ~600 cap —
toll 3 paid for that room before the feature, which is what that toll was
for — and `TranscribeSheetController+Commit.swift` 145 → **215**.
`MediaTranscript.swift` 383 → **399** and `AssemblyAITranscript.swift`
374 → **399**, each a line under its own 400: the first went to **411** mid-
build and its doc comment was cut until it fitted, and the second took
`keyterms` as a pure move from `AgentServer+CloudCaptions.swift`, which came
DOWN 247 → **243**. `AppDelegate+Menus.swift` 544 → **549** for one item and
one separator; `CloudTranscriber.swift` 296 → **317** for `verify`. The two
instruments are not held to a cap (`designs/reelcut-roadmap-7.md` §2.4):
`tools/proof/cloud_captions_probe.py` 3280 → **4753** (4640 before c1-chrome's
fix pass added six rows and three mutants),
`tools/proof/harness/main.swift` 901 → **954**,
`tools/proof/cloud_captions_proof.py` 1479 → **1643** (revised 2026-09-21:
**1494** is what `wc -l` gave at c1-chrome's own tree
`5cc64c21215641e7a99cd3e7d95ace8c6f03a13d`, and c1-close then took the file
to 1643, which is what the tree this sentence describes,
`f03ebcc6e4769f7195812d51d562518a2e4d9b67`, holds — the C1 reader review's
fix pass measured both).

**What the C1 reader review did to it** (2026-09-21, road map 6 §10.13,
`wc -l` against the tree it leaves). Nothing came ON to this list and nothing
came off: the review's seven product fixes landed in files that all have room,
and no file over the ~600 cap took anything on. The numbers, every one of them
under its own 400-line cap:
`app/Sources/AssemblyAIClient.swift` 338 → **395** — the biggest single
growth, `withoutCredential(_:)`, `isPlainIdentifier(_:)` and `DeleteAnswer`
with their arguments, and **five lines from its cap**, which is the one to
watch;
`app/Sources/CloudTranscriber.swift` 317 → **321**;
`app/Sources/CloudTranscriber+Media.swift` 183 → **216**;
`app/Sources/AgentServer+CloudCaptions.swift` 243 → **289**;
`app/Sources/SecretStore.swift` 212 → **229**;
`app/Sources/AssemblyAIClient+Session.swift` 179 → **187**;
`app/Sources/AgentCatalog+Captions.swift` 215 → **216**;
`app/Sources/MediaTranscript.swift` **399**, unchanged to the line, still one
under its own cap; and `app/Sources/ProjectDocument.swift` **1352**, unchanged
to the line — a file over the cap, whose one false comment was corrected five
lines in and five out. On the instrument side `cloud_captions_live.py` is back
at exactly **399** because `reachable` moved to `cloud_live_ledger.py`
(312 → **327**), `cloud_live_selftest.py` is 219 → **272**,
`assemblyai_fake.py` 501 → **580**, `cloud_captions_probe.py` 4753 → **5202**,
`cloud_captions_proof.py` 1643 → **1982**, and the new
`tools/proof/makefile_env_proof.py` is **203** — none of which the 400-line
cap has ever covered, which is the correction §10.13 made to §10.10 and
§10.11's twin sentences. (Revised 2026-09-21 by the review's own fix pass:
the two "before" numbers read **288** and **1494**, neither of which is what
the baseline tree `f03ebcc6…` holds — `wc -l` there gives 312 and 1643 — and
the probe and the proof grew again in that pass, 5182 → 5202 and 1934 →
1982.)

**None of this is work on its own.** It is the list a feature phase consults
so it pays the toll first and alone, the way `d69de99`, `b410125` and
`3e5b598` did.

---

**R6-14, lost-submit recovery (#28, 2026-09-21).** The touched app files
remain under their own 400-line caps: `AssemblyAIClient.swift` **397**,
`AssemblyAIClient+Submission.swift` **73**, and `CloudTranscriber.swift`
**327**. The client gained room by moving `submit` alone before behavior was
added; the initial pure-move typecheck passed. The proof instruments are
exempt from the app cap.

**Part-2 frame-grid ledger (2026-09-21; final review passed).** The pure
move cut `edit_paste.rs` from 599 to 580 before behavior was added; it is
**574** after implementation. New `frame_grid.rs` is **40** of 400 lines.
`edit_canvas.rs` is **232**, `edit_nest.rs` **320**, and `edit_props.rs`
**376**. The new FFI suites were **190** and **245** at implementation and
**192** and **247** after review; their shared fixture is
**53**, and the owned-app MCP proof **203**, all under their 400-line caps.
The exempt `edit.rs` semantics table was **838** lines at this gate. These
are historical gate readings; measure current sizes before another edit.

**R6-15, transcript identity (#30, 2026-09-22).** The separately gated pure
move took `AssemblyAITranscript.swift` from 399 to 344 lines and put the old
53-line marker block in `TranscriptStamp.swift`; typecheck and the existing
131-row stamp/estimate/verbatim probe passed before behavior changed. After
the four-field source projection, touched product files measure:
`AssemblyAITranscript.swift` **344**, `TranscriptStamp.swift` **68**,
`MediaTranscript.swift` **399** and `CloudEstimate.swift` **328** (`wc -l`).
`MediaTranscript.swift` grew no lines. The proof scripts are exempt from the
product cap.

**R6-16 size toll (#32, 2026-09-22).** Before behavior, the complete `Report` declaration moved from `CloudTranscriber.swift` (356 lines) into `CloudTranscriber+Report.swift` as a pure move. Typecheck passed with the four established warnings; the existing `run,cache_write,chrome` probe passed 143/143. The isolated move patch is in the issue handoff. Final product sizes are coordinator **325**, +Report **85**, +Media **220**, estimate **333**, sheet +Cloud **334**, agent +Cloud **279**, and catalog +Captions **221** lines, all under 400; proof scripts remain exempt. Road map 6 §10.20 records the final checks. Existing modification-second/recorded-duration identity limits, unreadable malformed files whose deletion IDs cannot be recovered by the reader, and the need for the originating account/region key to retry a safe ID remain.

**Road map 9's phase 1, the selected action (2026-09-23, `wc -l`; road map
9 §2).** Four over-cap files paid or took the tolls the phase's spec set,
each measured against `87aa425`: `app/Sources/ProjectDocument.swift`
1352 → **1368** (+16 of the +20 allowed: the two stored properties of the
sixth piece of view state, `selection`'s new `didSet`, the sync call in
`playhead`'s, and the two clamp lines above `clampViewState`'s playhead
write — stored properties cannot live in an extension, which is
`+DisplayStem`'s precedent; the queries and the entry rule went to the new
`ProjectDocument+SelectedAction.swift`, **63**);
`app/Sources/InspectorPane.swift` 1664 → **1679** (+15 of +40:
`action(_:)` rewired, `actionNote` deleted, `selectedAction`,
`selectAction(_:)` and `structural(audio:for:)` added);
`app/Sources/ClipPane.swift` 609 → **608** (the Actions section's line
gone, `makeHeader()` rewired); and `app/Sources/VideoPane.swift`
1411 → **1248**, DOWN 163 — the Actions section, its two row builders,
`summary(of:)` and `addAction` deleted, and the ten `actionNote` lines with
them. The frozen files took wiring only: `TimelineView.swift` 1651 →
**1663** (twelve lines) and `EditorViewController.swift` 1123 → **1124**
(esc). Four more new files, all under the 400-line cap:
`ActionLaneView.swift` **378** (the one to watch), `ActionBands.swift`
**133**, `TimelineActionBands.swift` **107** and
`EditorViewController+Actions.swift` **84**. `TimelineClipDrawing.swift`
454 → **439**. The instruments, exempt: `tools/proof/clip_inspector_probe.swift`
**395**, `tools/proof/clip_inspector_proof.py` **384**,
`tools/proof/harness/main.swift` 1116 → **1132**.

**Road map 9's phase 2, the sub-tabs and the pinned block (2026-09-23,
`wc -l`; road map 9 §4).** `app/Sources/ClipPane.swift`, over the cap at
608, gave up first: `ClipSelectionHeaderView` moved verbatim to the new
`ClipSelectionHeader.swift` (**235**) and `ClipHeaderBlock` out of
`ActionLaneView.swift` to the new `ClipPinnedBlock.swift` (**190**, with
`ClipSubTab` and `ClipSubTabsView`), the two moves typechecked at the
baseline alone before anything else landed. Then `ClipPane.swift`
608 → **400** (the sub-tab state and the per-tab `makeSections()`, which
came out shorter than the list it replaced); `ActionLaneView.swift`
378 → **330**; `InspectorPane.swift` 1679 → **1679**, net 0 of the +8
allowed (`pinnedBlock`, the protocol member, `InspectorSection.title`, the
header no longer stacked, the knob's draw shorter by one line);
`InspectorViewController.swift` (frozen) 296 → **332**, 36 of the 40
wiring lines allowed; `OptionControls.swift` untouched at 1082, the typed
popup init going to the new `OptionControls+Choices.swift` (**24**).
`VideoPane+Motion.swift` 242, `TextPane.swift` 528 and
`EditorViewController+Actions.swift` 87 changed in place. The instruments,
exempt: `tools/proof/clip_inspector2_proof.py` **393** and
`clip_inspector2_probe.swift` **263** (new), `tools/proof/harness/main.swift`
1132 → **1154**, `e2_chrome.py` 1481 → **1493**, `phase3_chrome.py`
768 → **768**, `clip_inspector_proof.py` 385 → **393**.

**Road map 9's phase 3a, the row marks (2026-09-23, `wc -l`; road map 9
§6).** `app/Sources/InspectorPane.swift`, over the cap at 1679, gave up
first, in two pure moves typechecked at the baseline alone: `InspectorSection`
and `InspectorSectionHeader` to the new `InspectorSection.swift` (268 as
moved) and the binding's writes to the new `InspectorBinding+Writes.swift`
(**219**, `inspector` no longer `private`), which left it at 1196. Then
`InspectorPane.swift` 1196 → **1292** (the metric, the gutter in
`inspectorRow`, the slider's segment and tick, the "now" tag, `ReadMode`
and `at(_:_:)`, `editsAction` deleted) — net 1679 → 1292, DOWN 387, inside
the spec's 1300; `InspectorSection.swift` 268 → **368** (the fold, the
header marks, the ⊘ note, `reveal()`, `didToggle`, `KeyedReveal`); the new
`InspectorMarks.swift` **244**. **Two tolls, paid on purpose:**
`ClipPane.swift`, at its 400 cap, 400 → **403** (the `KeyedReveal` property
with its comment and the one call — `KeyedReveal` itself lives in
`InspectorSection.swift` for this reason — and In/Out's `writes:` inside
their existing lines), and `VideoPane.swift` 1248 → **1253** (+5 of the
+6 allowed: the `writes:` arguments of Blend, the filter row, the Region
row, Center and Size). `TextPane.swift` 528 → **536** (+8 of +8: a `font`
and a `text` local and the `writes:` arguments), `AudioPane.swift` 444 →
**445** (Gain's `follows:`), `VideoPane+Motion.swift` 242 → **237** (the
note deleted). `InspectorViewController.swift` (frozen) untouched at 332.
The instruments, exempt: `tools/proof/clip_inspector3_proof.py` **306** and
`clip_inspector3_probe.swift` **331** (new); `e1_chrome.py` and
`clip_inspector_proof.py` changed in comments only, `e2_chrome.py` in
comments and one row (road map 9 §6).

**Road map 9's phase 3b, Reset/Clear, the row menus and the refusal strip
(2026-09-23, `wc -l`; road map 9 §8).** Three pure moves first, each
typechecked at the baseline alone (0 errors, 7 warnings):
`InspectorSectionHeader` out of `InspectorSection.swift` (368 → 199) into
the new `InspectorSectionHeader.swift` (170 as moved);
`InspectorSliderControl` out of `InspectorPane.swift` (1292 → 1132) into
the new `InspectorSlider.swift` (**161**, unchanged after); and Obscure's
section out of `VideoPane.swift` (1253 → 996) into the new
`VideoPane+Obscure.swift` (260 as moved, an extension). Then
`InspectorPane.swift` 1132 → **1151** (the builders' `default:` and
`resets:`, `ReadMode.defaults` and the readers' short-circuit; inside the
spec's 1170), `InspectorSection.swift` 199 → **220** (`differs:`,
`clear()`, the fold; inside 260), `InspectorSectionHeader.swift` 170 →
**211** (Clear, `buttonTitle`, `summaryInk`), `VideoPane.swift` 996 →
**1001** (inside 1010), `VideoPane+Obscure.swift` 260 → **261**,
`InspectorMarks.swift` 244 → **359** (`InspectorRowDefault`, the hover and
the ×, `clearOps`), and two new files, `InspectorRowMenu.swift` **110** and
`InspectorRefusalStrip.swift` **114** (102 before the review's fix, which
pins the strip's width on each show). `InspectorViewController.swift`
(frozen) 332 → **346** (+14 of the +15 allowed: the foot container, the
strip and one line in `refresh(isLive:)`). `ClipPane.swift` 403 → **403**
(In/Out's dead `writes:` deleted inside their lines, Reverse's `resets:`
inside its own), `VideoPane+Transition.swift` 113 → **113**,
`TextPane.swift` 536 → **543** (+7 of +9), `ShapePane.swift` 416 → **418**,
`DocumentPane.swift` 506 → **511**, `ProjectDocument.swift` 1368 → **1380**
(+12 of +14), `EditorViewController+Inspector.swift` 383 → **395**,
`ReelEdit.swift` 122 → **123**, `AgentServer+Clips.swift` 848 → **851**
(comments). `EditorViewController.swift` and `TimelineView.swift` took 0
lines. The instruments, exempt: `tools/proof/clip_inspector4_proof.py`
**323** and `clip_inspector4_probe.swift` **437** (new), `e1_chrome.py`
943 → **1001**, and the rows re-measured in place for a phase-2 or 3b reason
(road map 9 §8): `clip_inspector3_probe.swift` 331 → **340**,
`phase3_chrome.py` 768 → **780**, `phase4_chrome.py` 1222 → **1228**,
`phase6_chrome.py` 1592 → **1659**, `phase7_chrome.py` 2214 → **2226**.

**Road map 9's phase 4, retiming by drag (2026-09-24, `wc -l`; road map 9
§10).** Four new files, each under the 400 cap and the spec's 250 aim:
`ActionDragSession.swift` **173** (the session, the mode, the hover value,
and the HUD and ghost painters both lanes call), `TimelineActionDrag.swift`
**135**, `ActionLaneView+Drag.swift` **145** and `ActionLaneDecor.swift`
**163** (the decor, `Curve.laneName`, `CurveGlyphView`). Then
`ActionLaneView.swift` 330 → **364** (inside its 400: the three stored
properties, the forwarding overrides, the decor and overlay calls, the
glyph), `ActionBands.swift` 133 → **158** (`grip`, `gripEdge`, the hover arm
and grips, `curvePath` made internal), `TimelineActionBands.swift` 107 →
**126** (`actionHit`, `hovered:`), `TimelineSessions.swift` 438 → **442**
(the `.actionEdge` case), `AgentServer+Clips.swift` 851 → **853** (comment
only). `TimelineView.swift` (frozen) 1663 → **1682**: 22 lines in, 3 out,
all wiring — the two stored properties, `hit(at:)`'s one line, the
`.actionEdge` arm and one line in the `.action` arm, one arm each in
`continueGesture` and `endGesture`, one call each in `drawOverlays` and
`resetCursorRects`, and three one-line overrides on `TimelineContentView`.
`EditorViewController.swift` and `InspectorViewController.swift` took 0
lines. The instruments, exempt: `tools/proof/clip_inspector5_proof.py` and
`clip_inspector5_probe.swift` (new).

**Road map 9's phase 5, the rest of the mode (2026-09-24, `wc -l`; road map
9 §12).** One new file, `CanvasEditTarget.swift` **89** (under the spec's
130). The four files over the cap took what the spec allowed and no pure
move: `CanvasSessions.swift` 1088 → **1090** (the four `to:` forms, the
`.box` arm's comment, the doc comments), `InspectorPane.swift` 1151 →
**1156** (`decode` loses `private`; Shadow's five sub-rows gain `mixed:`),
`AgentServer+Clips.swift` 853 → **856** (`off` read through `stringsArg`,
`setVideo`'s comment), `AgentCatalog+Clips.swift` 799 → **801** (`off`'s
description). `PreviewCanvasView.swift` (frozen) 1104 → **1112**: 27 lines
in, 19 out, all wiring — `editTarget`, `update(…target:)`, the four
`begin*` reads, the four session calls and the nudge. `ReelOps.swift` 1143
→ **1163** (the raw `off` and the typed lift; `edit.rs`'s table exemption).
Inside their caps: `ActionLaneView.swift` 364 → **375** (the cursor key),
`ActionDragSession.swift` 173 → **174**, `InspectorSection.swift` 220 →
**225**, `InspectorMarks.swift` 359 → **360**, `AudioPane.swift` 445 →
**453**, `TextPane.swift` 543 → **549**, `ShapePane.swift` 418 → **422**;
`EditorViewController+Canvas.swift` **161** unchanged. The core:
`edit_action.rs` 369 → **451** (`not_a_target`, `check_off`, `key_off`),
`edit.rs` 840 → **843**, `op_table.rs` 328 → **331**, `op_schema.rs` 173 →
**174**, `edit_zoom.rs` **467** (one argument), and `core/tests/action_off.rs`
**187** new; `op_table.rs`, `op_schemas.rs` and `op_nullability.rs` in
`core/tests/` +2, +1, +1. The instruments, exempt:
`tools/proof/clip_inspector6_proof.py` **342** and
`clip_inspector6_probe.swift` **441** (new), `clip_inspector4_probe.swift`
437 → **470**, `clip_inspector5_probe.swift` 480 → **500**,
`clip_inspector5_proof.py` 292 → **295**. The review-2 fix pass (road map 9
§12, the target captured at mouse-down) grew `PreviewCanvasView.swift`
(frozen) 1112 → **1121**, wiring only — the `gestureTarget` property and
its doc comment, four one-line captures in the `begin*` methods, four reads
swapped in `continueGesture` — and `CanvasEditTarget.swift` 89 → **92** (its
header), with the instruments, exempt, `clip_inspector6_probe.swift` 481 →
**532** and `clip_inspector6_proof.py` 345 → **373**. The open-work pass
(road map 9 §12): `ActionLaneView.swift` 375 → **375**, and the
instruments, exempt, `clip_inspector6_proof.py` 373 → **390**,
`phase6_proof.py` 1783 → **1794**.

**The canvas text editor grows as you type (#36, 2026-09-24).**
`PreviewCanvasView.swift` (frozen) 1121 → **1133**, wiring only: the
editor's one-line `onChange` forward and its clearing, the `didChangeText`
override and `onChange` property on `CanvasTextView`, a fit at begin, and
`refitTextEditor()` (the live editor to its box and its font to the
canvas's scale, called from `onChange` and from `layoutCanvas`) in place of `editorFrame(for:)`, which is gone
with the fixed `textContainerInset` line. The sizing is the new
`PreviewCanvasView+TextEditFrame.swift` **62**. The instruments, exempt:
`tools/proof/text_edit_probe.swift` and `text_edit_proof.py`, new.

**Return applies in the canvas text editor (#37, 2026-09-24).**
`PreviewCanvasView.swift` (frozen) 1133 → **1132**, wiring only:
`textEditor` `private(set)`, the `onGroupedEdit` closure beside `onEdit`,
`CanvasTextView.onCancel` renamed `onEscape` and wired to
`escapeTextEditing()`, `keyDown` a four-arm switch over `TextEditKey.route`
(four lines shorter than the two `if`s it replaced), the class doc
restated. The route and the Esc sheet are the new
`PreviewCanvasView+TextEditKeys.swift` **73**. `EditorViewController+Canvas.swift`
+1, the forward. The instruments, exempt: `tools/proof/text_apply_probe.swift`
and `text_apply_proof.py`, new.

**The package's `graphics/` store (road map 10's G3a, 2026-09-25).**
`ProjectDocument.swift` **1380 → 1329 → 1336**: first, alone and gated
(`make typecheck` 0 errors and the 7 baseline warnings, `make app`
succeeded), a pure move of `importMedia`, `probeNext` and `commitImport` to
the new `ProjectDocument+Import.swift` **63** (`present(_:)` lost
`private`); then seven lines in — the stored `graphicStore` and its doc
line, one call each in the `fileURL` setter, `makeWindowControllers()` and
`close()` (two), and the whitelist line in `fileWrapper(ofType:)`.
`ProjectSnapshot.swift` **2305 → 2309** (`ClipSnapshot.graphic`: the field,
the memberwise parameter, its assignment and its decode; `ClipSource.graphic`'s
stale "not decoded yet" comment reworded inside its two lines). New:
`GraphicStore.swift` **399**, `ProjectDocument+Graphics.swift` **71**,
`ProjectSnapshot+Graphic.swift` **88**. `ReelCore.swift` 1440, untouched.
The instruments, exempt: `tools/proof/graphics_store_probe.swift` **415**,
`graphics_store_probe.py` **317** and `graphics_store_proof.py` **281**, new.

**A graphic clip drawn (road map 10's G3b, 2026-09-25, `wc -l` against
`7bf518c`).** No toll: every ledger file took only the lines the spec
allowed it. `ProjectSnapshot.swift` **2309 → 2313** (`case graphic`, its
decode and encode dispatch lines, its `cacheHash` arm; the bodies are in
`ProjectSnapshot+Graphic.swift` **88 → 130**). `Compositor.swift` **1391 →
1396** (the `case .graphic` in `MetalRenderer.source(for:…)`, five lines).
`ProjectDocument.swift` **1336 → 1335** (`close()`'s two store lines became
`stopGraphicStore()`; the rest is in `ProjectDocument+Graphics.swift` **71 →
111**). The FROZEN `EditorViewController.swift` **1124 → 1127** (one
`addObserver`, three lines; the selector is `EditorViewController+Graphics.swift`
**16**) and the FROZEN `AgentServer.swift` **790 → 788** (two `handlers`
rows in, `opsWithoutTools`' two entries and their comments out, its doc
sentence reworded). Under the cap: `LayerRenderers.swift` **467 → 492** (two
members made internal, one `measuredSize` case, and the review's fix: the
cache as a `Pool` struct, with graphics given their own six-entry pool),
`AgentCatalog.swift`
**525 → 529**, `AgentCatalog+Declarations.swift` **313 → 335**,
`AgentServer+Parity.swift` **186 → 193**; in the core `recipe_graphic.rs`
**129 → 133**. New: `GraphicRegistry.swift` **183**,
`LayerRenderersGraphic.swift` **78**, `AgentServer+Graphics.swift` **138**,
`AgentCatalog+Graphics.swift` **60**. `ReelCore.swift` 1440 and
`ReelOps.swift` 1191, untouched. The instruments, exempt:
`tools/proof/graphics_proof.py` **565**, new; `op_argument_proof.py` **949
→ 1016** and `op_catalog_proof.py` **500 → 505**.

**A failing graphic, its export gate and pin (road map 10's G3c,
2026-09-25, `wc -l` against `b29d981`).** One toll, a pure move landed and
gated alone first (`make typecheck` 0 errors and the 7 baseline warnings,
`make app` succeeded): `Exporter.ExportError` from `Exporter.swift` to the
new `ExporterErrors.swift`, **609 → 539** and **74**. Then the feature:
`Exporter.swift` **539 → 581**, which takes it OFF this list (its row is
gone); `ExporterErrors.swift` **74 → 91** (the two graphic cases). The
cancel fix needed no toll because it made its file SMALLER:
`ExporterWriter.swift` **1114 → 1096** (`cancel()` sets the flag and
nothing else; the reader is cancelled in `allInputsFinished`; `started` and
its paragraph went). Under the cap: `AgentServer+Render.swift` **563 →
589**, `ExporterImageSequence.swift` **492 → 504**,
`ExportQueueController.swift` **482 → 487**, `LayerRenderers.swift` **493
→ 494**, `AgentCatalog+Files.swift` **487 → 491**,
`ExportProgressSheetController.swift` **191 → 196**,
`EditorViewController+Export.swift` **137 → 139**, `+SaveFrame` **387 →
388**, `+Eyedropper` **318 → 319**, `GraphicRegistry.swift` **183 → 263**,
`LayerRenderersGraphic.swift` **78 → 195**. New: `ExporterGraphics.swift`
**95**. `Compositor.swift` 1396, untouched. The instruments, exempt:
`tools/proof/graphics_proof.py` **565 → 848** and
`tools/proof/graphics_pin_probe.swift` **146**, new.

## 4. What only a person at the machine can check

These are not tasks so much as a list to run through at the machine once. The
first two have been owed since M1 and spec §10 records them; phases 8 and 9
and the closing above added the rest.

- **Graphics playing, WATCHED (road map 10's G3, §9a item 5,
  2026-09-25)** — in the running app, which no proof here can do: every
  graphics row is a `render_frame` or an export. Worth judging: the
  fixtures `lower-third` and `kinetic-type` (`graphic/tests/graphics/`) on a
  1080p30 canvas with View ▸ Preview Quality ▸ Full, played through, with
  no visible stutter; a 4K canvas with `title-card` (G0's q3 measured
  26 ms p95 per frame there, inside a 33 ms frame at 30 fps); and Activity
  Monitor's memory for Reelcut while `kinetic-type` plays at 4K — the
  six-entry graphic texture pool (`LayerRenderers.graphicCacheLimit`) was
  sized without that number (~33 MB a texture at 4K). If either canvas
  stutters, G6 (road map 10 §9, the per-frame cost) is owed. The error card
  in the preview is worth one look too: a module that throws draws dark red
  with the message in white, never the last good frame.

- **The rest of the mode, FELT (road map 9's phase 5, 2026-09-24)** — in
  the running app. The probe drives the canvas sessions, the nudge and the
  inspector rows through their own entry points; no real pointer moved.
  Worth judging: with an action selected, a canvas drag (move, scale,
  rotate, crop) and an arrow-key nudge landing on the action's END state
  while the box on screen is the frame at the playhead — the drag starts
  from the end state and moves it by the pointer's travel, so a playhead
  away from the action's end shows the box offset from what is being
  written (spec §11 CI-13); a TEXT clip's width drag inside an action
  starting from the action's end width rather than jumping to it; a shape's
  box drag inside an action still resizing the shape itself; unchecking
  Drop shadow (or an outline, a backdrop, a stroke) inside an action
  showing ◆ "at end" and switching off only at the action's end; and a
  section's header click with System Settings ▸ Accessibility ▸ Display ▸
  Reduce motion ON (the collapse snaps) and OFF (it animates at 0.22 s),
  an action's auto-open staying instant either way.

- **Retiming by drag, FELT (road map 9's phase 4, 2026-09-24)** — in both
  appearances, in the running app, on the timeline and in the Clip tab's
  lane. The probe drives both gestures through their own entry points and
  the harness photographs the lane's decor and an unhovered selected band;
  no real pointer moved, so hover, cursors and the drag's feel are unseen.
  Worth judging: the hover's 62 % fill and the grips appearing under the
  pointer (white 80 %, black 45 % on the selected band) and leaving with
  it; `.openHand` over a body and `.resizeLeftRight` over a grip, and none
  on a band too narrow to resize; the band stopping flush against its
  neighbour and the clip's ends; the dashed ghost and the HUD ("start →
  end  +s:ff", "len +Nf") — on the timeline 18 pt above the clip, in the
  lane in place of ACTIONS; the drop re-selecting the action and parking
  the playhead at its new end; one ⌘Z undoing the whole drag; a lane click
  selecting on RELEASE without the pane jumping; the lane's hatch, fade
  triangles and wedges against the timeline's for the same clip; and the
  curve glyph beside "In Out", including at the panel's narrowest.

- **Reset, Clear, the ×, the row menus and the refusal strip, LOOKED AT
  (road map 9's phase 3b, 2026-09-23)** — in both appearances, in the
  running app. The harness photographs one header in the dark with and
  without a button (`clip_inspector4_proof.py`), and the probe reads the
  rest as state; nothing was hovered, right-clicked or refused on screen.
  Worth judging: that Reset appears the moment a section leaves its
  default and goes when it returns; that Clear replaces it in the same slot
  with an action selected, and that the summary's middle tier
  (`DS.textMuted`) reads as different from the faint one in light; the ×
  under the pointer over a keyed row's gutter (it needs a KEY window) and
  its tooltip; a right-click on a row's label, slider and empty space
  opening the row's menu, and on a field or a popup opening THEIR own;
  "Go to action M" landing on that action; and the refusal strip — press
  ⌥⌘K inside an existing action: the beep, then "Refused: …" under the
  panel, wrapped to at most three lines, gone on the next edit, undo or
  click and kept across a playhead move.

- **The Clip tab's row marks, LOOKED AT (road map 9's phase 3a,
  2026-09-23)** — in both appearances, in the running app. The harness
  photographs one state in the dark (`clip_inspector3_proof.py`: the ◆ in
  the gutter, the mint segment and the coral tick on Opacity's rail); the
  light appearance and everything that moves were not photographed. Worth
  judging: ◆ ◇ ○ ⊘ in the gutter and in the section headers in both
  appearances (⊘ and ◇ are `DS.textFaint`, which may be too quiet in
  light); the keyed field's and popup's 1 pt border; the mint segment and
  the coral tick while the playhead is scrubbed through a span; the "now"
  tag on a field-only row (Position X inside another action's span); "at
  end" on a keyed popup; and the AUTO-OPEN in the running app — selecting
  an action opens the sections it keys on the showing sub-tab, a section
  closed by hand stays closed while that action is selected, and leaving
  the action returns the panel to the person's own layout.

- **The Clip tab's sub-tabs and pinned block, LOOKED AT (road map 9's
  phase 2, 2026-09-23)** — in both appearances, in the running app. The
  harness photographs the strip, the `◆1` badge and the inspector sliders'
  block knob at rest (`clip_inspector2_proof.py`); it cannot scroll, click
  or drag. Worth judging: that the block stays put while the sections
  scroll under it; that a click on a sub-tab switches at once and the
  panel comes back to the top; that the choice survives picking an action
  and resets on picking another clip; whether the active cell's selection
  fill reads in light; whether the mint `◆N` reads beside a muted label;
  and dragging a slider's block knob, whose fill should meet it on a pixel
  edge at every value. Phase 1's own checks (the lane and bands in both
  appearances, a real band click and esc) are road map 9 §2's and still
  stand.

- **The sharp chrome, LOOKED AT (2026-09-23)** — in both appearances, in the
  running app. `sharp_chrome.py` photographs the resting chrome offscreen and
  reads its corners, but the harness cannot show hover (a `GhostButton` draws
  only when hovered, so its now-square hover fill has never been rendered),
  press, a disabled `BlockSlider`, dragging the zoom knob, or the Metal well.
  Worth judging: whether the zoom slider's grey track and white (dark) or
  black (light) block read well beside the accent fill (spec §11 SH-2), and
  whether the square Export button, S/M/L, Snap box and fields sit well
  beside the sheets' still-pill `StickerButton`s (SH-1).

- **The cloud captions parts, road map 6's c1-parts (2026-09-20)** — what no
  instrument in that pipeline could reach. Every one of them needs a real
  AssemblyAI key, which no proof may ever use:
  - that `AssemblyAIClient.verify()` answers "Key accepted" against the real
    `api.assemblyai.com` with a key that works, and the key sentence with one
    that does not. The stand-in proves the STATUS mapping; only the service
    proves the round trip.
  - that a real 402 carries the balance sentence the `.account` arm relays.
    The fake serves a sentence of the proof's own choosing; nobody has seen
    AssemblyAI's.
  - that the `eu` region's base URL reaches an account that has the EU
    enabled. Road map 6 §5j already owed this; the client makes it testable.
  - whether `FileStore`'s `0600` file is what the person expects to find in
    `~/Library/Application Support/Reelcut/`, and whether Remove leaves them
    confident it is gone. No probe may look in that folder.

- **The cloud captions chrome, road map 6's c1-chrome (2026-09-20)** — what
  no instrument in that pipeline could reach:
  - **the Settings window, LOOKED AT** in both appearances. It is
    photographed (`cloud_captions_probe.py`'s `chrome` section, two processes
    per appearance, byte-identical) and nobody has judged the picture: the
    button row's balance, whether the explanation paragraph is too long at
    460 points, whether `Verify` reads as a third affirmative button beside
    Save and Remove.
  - **the Generate Captions sheet, LOOKED AT.** A sheet cannot be put up
    offscreen at all, so every claim about it is structural. Nobody has seen
    the card with the three cloud rows showing, or watched them appear and
    disappear as the Engine popup moves.
  - **the reasons tooltip.** `CloudEstimate.reasons` is shown as the summary
    label's `toolTip` (road map 6 §5e's dated revision); nobody has hovered
    it, and a four-line tooltip may be the wrong home for it.
  - **Verify against the REAL service**, both answers. The stand-in proves
    the status mapping; c1-parts already owed this and the button now makes
    it a thing a person can press.
  - **the phases' feel on a real recording** — whether the bar's four bands
    read as progress over minutes of somebody else's compute rather than as
    four stalls, and whether the detail line's megabytes move often enough.
  - **the fallback's report card**: R6-8's "transcribed with universal-2"
    line has only ever been built from a `Report` a probe wrote.
  - **⌘, in a document window**, and that it does not displace the bare `,`
    nudge while a clip is selected or an inline rename is open.

- **A clip plays with audio** (spec §10 step 4) and **the preview holds 60 fps**
  (step 5). No still frame can answer either.
- **The recorder, road map 3** — what no headless proof can see: the
  picker's window mode presenting from the non-activating panel and the
  choice arriving (`didUpdateWith`, a nil stream); the countdown's look;
  that a recording of a display does NOT contain the panel (the programmatic
  filter excludes Reelcut — measured at 99 % of an excluded app's pixels)
  and whether a PICKER-made recording does (R0 q3 is unmeasured and, since
  R2's decision 7, moot for the panel — it is off screen for every source);
  that the timeline's own playback is absent from the
  file (`excludesCurrentProcessAudio`); the menu bar's own screen-recording
  indicator naming Reelcut, and its Stop landing the file; the popups and
  switches working on a `.nonactivatingPanel` while another app is
  frontmost; the microphone grant prompt from the signed bundle (the
  entitlement and the usage key together); and the first shareable-content
  call of a fresh instance, which held the main thread ~37 s on a locked
  console when made through `onMain` and now runs off it. **R2's pause
  (2026-09-12)**, on the same terms: the status item's menu reading Pause
  Recording / Stop Recording, then Resume Recording / Stop Recording once
  paused, and the label switching between the coral dot and the pause
  glyph with the time FROZEN; that the system's own screen-recording
  indicator stays up through a pause (the stream keeps capturing — R0 q7
  measured 57 fps while paused, but no headless proof can see the menu
  bar); that the panel is gone from the moment the recording starts for a
  DISPLAY source too, and comes back only when the landing has a note; that
  ⌘Q while paused opens the item's menu; and
  a paused recording played back across its segment boundary in the
  timeline, where the cut between two touching clips should be invisible
  but for the paused span.
- **The two preview windows show the same frame.** Phase 8 measured that two
  `AVPlayerLayer`s on one `AVPlayer` both display, and that they hand back
  byte-identical `displayedPixelBuffer`s — but nothing has ever opened the
  preview window in the running app and LOOKED at the two pictures together.
  Note before reaching for an instrument: `isReadyForDisplay` and `videoRect`
  are useless here, since a detached layer and a layer in a never-shown window
  both report `true` with a plausible rect.
- **⇧⌘P, ⌘↓ and ⌘↑ from a real keyboard.** The probes drive
  `validateNestScopeAction` and synthesise `NSMenuItem`s; nothing goes through
  AppKit's menu dispatch from a real key event.
- **A nest PLAYS once open** — the scoped composition's audio and its frame
  rate. `render_frame` is a still.
- **Whether Preview Quality is actually FASTER.** Section 5 of
  `phase8_proof.py` proves the player is asked for a smaller buffer
  (`phase8_proof.py` **79/79**, 2026-09-24); a render
  size is not a frame rate, and nobody has measured a frame time at any
  quality. Note the shadow passes do NOT get cheaper — `shadowSilhouette`
  allocates at canvas size — so the saving is not a clean 4×.
- **Opening a saved project is now quick.** The marker's whole point is
  that a second open decodes nothing; the proofs show the inodes do not move,
  and nobody has yet felt the difference on a long recording.
- **A relinked clip's filmstrip changes on screen.** `remaining_probe.py`
  section 4 shows the tile turn blue offscreen; the Relink… sheet in the
  running app has not been watched doing it.
- **`phase8_chrome.py` needs an unlocked console** for section 4's six dispatch
  checks — the only rows in this suite that need a KEY WINDOW, and a process on
  a locked console cannot activate to have one. The script no longer fails them
  there: it reads `IOConsoleLocked` and SKIPS the six by name, so the score
  reads **150/150** unlocked and **144/144 with 6 skipped by name** locked
  rather than 144/150 and six failures that looked like a regression. The skip
  is honest and not a pass — those six are simply UNMEASURED on a locked
  machine, which is why they are listed here: only a run at an unlocked screen
  asks them at all.
- **Remove Silences judged by VOICE, listened to** — road map 4 §4h's three,
  now that §4g's instruments have landed and the reader review has widened
  them (`silence2_proof.py` 91/91, `silence2_probe.py` 76/76, 2026-09-20,
  after the second sceptic pass's residue was closed; 83/83 and 65/65 after
  the sceptic's pass over that review, 79/79 and 65/65 at the review's close,
  and 61/61 and 61/61 when they landed on 2026-09-19): a narrated screencast recorded by
  the app's own recorder with the microphone on, run through Voice mode with
  the truth marked BY EAR and the spans compared, which q7 is the reason for
  — the one real mixed recording in hand defeats both VADs and nobody has
  listened to it; a cut heard across a voice-mode boundary, to say whether
  60–100 ms of offset lag plus 0.1 s of padding is breathing room or a
  clipped word, and whether the padding default should drop to 0.05 s; and
  the sheet's note when one file is PENDING while another is judged by
  level. The probe reads that note's two halves separately and scores each,
  but it has never put both on screen at once and nobody has looked at the
  sentence they make together.
- **The band from below the lanes, with a real mouse.** `marquee_probe.py`
  (2026-09-19) drives `TimelineView`'s three gesture entry points with
  synthetic points and shows the room below the lanes is inside the
  content view's frame, so a real press there reaches the same hit test;
  nobody has yet pressed a mouse there in the running app and watched the
  band draw and the selection block count up.
- **Transitions and motion, watched and heard** — road map 5 §4g's and
  §6g's checks, now that §4e's and §6e's instruments have landed
  (`e1_proof.py` 99/99 on 2026-09-24, reading `RC_FORMAT_VERSION` off
  the header, and `e2_proof.py` 61/61; `e1_chrome.py` 21/21 and
  `e2_chrome.py` 52/52 as re-run through road map 9, whose sub-tabs
  re-measured `e1_chrome.py` (road map 9 §8). The post-review counts of
  2026-09-20 are road map 5 §12 — E1's review moved `e1_proof.py` and
  `e1_chrome.py`, E2's took `e2_chrome.py` from 24/24 to 33/33 and its
  residue run of 2026-09-20 to 35/35, with the four N·1 rows, the two N·2
  rows, the two N·3 rows, the per-clip write and its undo control, and the
  strip's `hasPixels` gate — and `transition_sheet_probe.py` is 39/39).
  §4g: a crossfade across a Remove
  Silences cut sounding even rather than dipped or bumped; an eased push
  FEELING better than the linear one; the Transition submenu at a hard cut
  doing what a person expects; and the three wipes reading as the direction
  their names say — the proof measures which SIDE the incoming colour is on
  and where the boundary sits, which is not the same as "it reads as up".
  §6g: whether each preset's numbers look right at ordinary clip lengths
  (the tables in §5b are starting points, not measurements); whether `pop`'s
  overshoot reads as a pop; that the Preview button loops the clip; whether
  a drag begun mid-motion is tolerable, since the inspector and the canvas
  see the clip UN-MOVED while the picture moves; and that the wedges read at
  S, M and L track heights — `e2_chrome.py` measures them at M only. Two more
  since the E2 reader review measured what no row reaches (road map 5 §12,
  R4·1 and R4·2): whether a `spin` turns the way the table says it does on
  screen — no MCP row can see the DIRECTION, because a card's bounding box is
  the same at +45° and −45° — and whether a slide on a clip INSIDE a nest
  leaves by the nest's own edge rather than the project canvas's.
- **The cloud captions RUN, road map 6's c1-run (2026-09-20)** — what no
  instrument in that pipeline could reach, and what nobody has looked at:
  - **the progress bar as an experience.** Its arithmetic is measured (63
    values over a two-media run, non-decreasing, holding at 0.95); whether
    "Waiting for AssemblyAI · 34 s" reads as patience or as a hang on a real
    twenty-minute recording, over a home upstream, is a question for a person
    with a stopwatch and their own patience. Road map 6 §5j owed this and
    still does.
  - **a real media over ten hours.** The refusal is proved against a package
    whose `duration` was rewritten by hand; nobody has pointed the app at a
    ten-hour file, which would also be the first time the extractor was asked
    for 550 MB of FLAC.
  - **what a held media feels like** (R6-11). If AssemblyAI's DELETE is down,
    every already-transcribed media is held: cached words still come back,
    `refresh` is refused in R6-11's sentence, and only a person can say
    whether that sentence is the right thing to read at that moment. The
    `no-delete` mutant is what that state looks like.
  - **the cue timings against the speech, by eye**, on a real recording with
    the cloud engine. Row 3's oracle proves the mapping against the SERVED
    words; nothing proves AssemblyAI's own word times feel right on screen.
- **The Keychain prompt road map 6's spike met and could not read**
  (`designs/reelcut-roadmap-6.md` §3 q7, run 2026-09-20). A login-keychain
  item added by one ad-hoc-signed build and read by the NEXT one — a
  different cdhash, which is what every `make app` produces — blocked on a
  `SecurityAgent` modal for the whole twenty-second bound, with
  `kSecUseAuthenticationUIFail` set and not honoured, and its DELETE answered
  `errSecInvalidOwnerEdit`. Nobody was at the machine to read the dialog. A
  person can: what does it say, does "Always Allow" survive a rebuild, and
  does a build signed with a stable Developer ID identity avoid it entirely?
  The answer decides whether C1's `0600` file (§5d) can ever go back to being
  a Keychain item. The spike left NOTHING in the Keychain —
  `com.reelcut.spike.q7` was deleted and verified gone on both keychains, and
  `com.kgalligan.reelcut.assemblyai` was never touched — so there is nothing
  to clean up, only something to look at.

- **`recording_proof.py`'s microphone rows want a WIRED or BUILT-IN input**,
  found by c1-close's re-run on 2026-09-21. With this Mac's default INPUT
  device set to a Bluetooth headset (`system_profiler SPAudioDataType` names
  "Kevin's AirPods Max" as both the default output and the default input),
  the capture session's first sample lands AFTER the screen stream's, so
  `mic_offset` is negative where R0 measured +66 and +70 ms, and the
  microphone file comes out SHORTER than the movie — measured twice, −81.9
  and −213.3 ms, against a two-frame (67 ms) bound. The script already skips
  its TONE rows by name for a Bluetooth OUTPUT and has no such arm for a
  Bluetooth INPUT, so the row FAILS rather than skipping. Nothing in the
  recorder changed (road map 6's C1 touched no recording file), and what a
  person can do is re-run it with a wired or built-in input selected and say
  whether the row passes — and, if it does, whether the script should skip
  that row by name the way it skips the tone rows.

- **Road map 6 §5j's list, WHOLE, carried here by c1-close (2026-09-21)** —
  the five things C1 always knew only a person could answer. Three of them
  are also owed by a bullet above, from the pipeline that met them; they are
  repeated rather than cross-referenced only, so this list is 5j's list and
  not a summary of it:
  - **What q7's prompt actually says**, and whether "Always Allow" survives a
    rebuild. C0 measured that a rebuilt ad-hoc-signed binary BLOCKS on a
    `SecurityAgent` modal for the whole twenty-second bound (road map 6 §3
    q7); nobody was at the machine to read it. That is why the key is a file
    (§5d), and it is the one q7 question a person can still answer. Also the
    Keychain bullet above.
  - **The Settings window's look in both appearances, and Verify's two
    answers.** The window is photographed and the STATUS mapping is proved
    against the stand-in; c1-close's live rows never open it. Also the
    c1-chrome and c1-parts bullets above.
  - **A real recording of twenty minutes, home upstream**: the phases' feel,
    whether "Waiting for AssemblyAI · 34 s" reads as patience or as a hang,
    and the captions' timing by eye against the speech. The live rows upload
    eleven synthetic seconds over a fast link and nothing else, ever. Also
    the c1-run bullet above.
  - **The EU region with an account that has it enabled.** The live rows pin
    `-ReelcutAssemblyAIRegion us`, which is the only region this account is
    known to answer in.
  - **The report card when the FALLBACK ran**, on a Korean or Polish
    recording. `speech_model_used` is read from the service's own answer and
    was `universal-3-5-pro` on every live call C1 made; no run in this tree
    has ever seen Universal-2 answer for a language the newer model declines,
    so the sentence the card would print has been proved only against the
    stand-in.

- **The word-captions spike, road map 8's W0 (2026-09-22)** — what that run
  could not reach on this host. Its record is
  `designs/reelcut-roadmap-8.md` §10.1, and §10.3 names what did not run:
  - **(W2 owes these two since it built the Download row, 2026-09-22; road
    map 8 §10.6.)** **`AssetInventory` with no network.** W0 q3 read
    `supportedLocales`, `installedLocales`, `reservedLocales`,
    `status(forModules:)` and the progress an installation request reports,
    and W2 read them again from the app, but nobody has measured any of them
    with the network gone: that would change this host's network state.
    What the sheet's Download row says, and what `transcribe` refuses with,
    when there is no network is a person's check.
  - **The model download on a Mac that has never had one — W2's Download
    row, pressed.** `downloadAndInstall()` has never been called on this
    host — a download is a person's decision, R6-12's argument, and
    `speech_engine_proof.py` drives the row by hand without pressing it — so
    nobody has watched one run. W0 measured what the row can show BEFORE it
    starts, and it is nothing: the request's `Progress` reports
    `totalUnitCount` 0, `fractionCompleted` 0 and `isIndeterminate` true.
    Whether the bar turns determinate and fills in once the download begins,
    whether the label's percentage moves, and whether the downloaded row is
    then selected, marked installed and Generate becomes live, is unmeasured.
  - **The Download row LOOKED AT.** No offscreen photograph or person has
    seen the row: its placement under Language, the indeterminate bar, the
    "Downloading French (France)… 42%" label, and the "— not installed"
    popup titles. `speech_engine_probe.swift`'s P5 reads the controls'
    STATE, not the picture.
  - **`Progress.cancel()` during a real download.** Cancel calls the
    request's own `Progress.cancel()`; whether `downloadAndInstall()` then
    throws promptly, leaves nothing half-installed, and the row returns to
    "Download" with no note (a cancel is not reported) has not been run.
  - **The popups' lock, seen mid-download.** P5 sets `downloading` by hand
    and reads `isEnabled` off both popups; a person has not watched Language
    and Engine stay disabled for the length of a real download and come back
    at its end, or closed the sheet mid-download (a decision: the download
    runs on in the framework). A consequence of that decision nobody has
    seen: reopening the sheet mid-download shows the same locale
    "— not installed" with Download ENABLED, so a person can start a second
    request for a locale already downloading; what the framework does with
    it is unmeasured.
  - **A downloaded model SURVIVES.** `SpeechEngine.download` releases the
    locale right after `downloadAndInstall()`, so the app holds no
    reservation for a model a person has just downloaded. Whether that
    locale is still installed — listed by `installedLocales`, and
    transcribing — straight after, after a relaunch, and days later, is a
    person's check after a real download (road map 8 §10.6's review).
  - **Whether the four bundled display faces resolve on a Mac that does not
    already have them installed.** This host carries Montserrat, Anton and
    Bebas Neue in `/Library/Fonts`, so W0 q6's five byte-distinct
    `render_frame` PNGs and five byte-distinct export frames prove the faces
    DRAW and differ from each other and from a control name — not that the
    app BUNDLE is what supplied them. A Mac without those families is the
    only place that claim can be made.
  - **Whether the highlight feels in sync.** W0 q2 measured the bias — the
    on-device engine starts a word a median 270 ms EARLY against a known
    start, AssemblyAI 62 ms late — and road map 8 §8 turned those into two
    `lead` defaults. Whether either reads as in time with the voice is a
    person watching a real recording.
  - **(W3 owes these three since it drew the page, 2026-09-22; road map 8
    §10.7.)** **The look on real footage.** `words_picture_proof.py` proves
    frames differ and hold byte for byte where they should, and the probe
    that no ink leaves the box — not that a highlighted, popped, pilled
    page reads well over a real picture, on 9:16 and 16:9.
  - **60 fps with a pop on every word.** A pop re-rasterizes the page for
    the 0.12 s `WORD_POP` after each word start (W0 q5 measured about half a
    millisecond a raster at 1080×1920); nobody has played a dense page
    through the preview at 60 fps and watched for a dropped frame.
  - **The BUNDLE on a Mac without the families.** W3's probe row P5 found
    that with the app's `Fonts/` registered at process scope, CoreText
    resolves each of the four faces to the BUNDLED file (the pinned sha256
    at `kCTFontURLAttribute`) even on this host, whose `/Library/Fonts`
    copies are different files. That is the probe's registration, not the
    app's `ATSApplicationFontsPath`; the app itself on a Mac with none of
    the families is still a person's check.
  - **(W4a owes these three since it generates pages, 2026-09-23; road map
    8 §10.9.)** **Sync by eye, per engine.** `CaptionPages.lead(for:)`
    shifts every on-device word +270 ms and every AssemblyAI word −60 ms
    (W0 q2's medians); the probe proves the shift is applied and confined to
    the clip, not that a generated Highlight page lights each word as it is
    heard. A person watching a real recording through each engine is the
    only judge, and the two constants are where a correction goes.
  - **Each style on real footage, 9:16 and 16:9.** `word_captions_proof.py`
    reads a generated Highlight track's ink off `render_frame` pixels and
    finds it inside the budget's columns on a 1080×1920 canvas; nobody has
    looked at Highlight, Pill, Karaoke, Build and One Word pages over a real
    talking head at either aspect, at their §5h sizes and heights.
  - **60 fps with generated pages.** W3's pop owes the same check for one
    hand-written page; a generated track is a page every second or two,
    each re-rasterizing for `WORD_POP` after every word — played through the
    preview at 60 fps and watched for a dropped frame.
  - **(W4b owes these two since it built the sheet's Style row, 2026-09-23;
    road map 8 §10.10.)** **The sheet's preview, LOOKED AT.** The harness
    photographs the card as a window's content and the probe proves six
    byte-distinct previews, a different picture per canvas and a transcript's
    own words when one is cached — not that a 258 × 80 pt preview of two
    stacked frames reads as "this is the style, and this is the second word
    lit", nor that the dark plate is a fair stand-in for footage. A person
    looking at the running sheet on 9:16 and 16:9 projects is the judge.
  - **The sheet's Style row seen in the app.** A sheet cannot be put up
    offscreen, so nobody has seen File ▸ Generate Captions… present the
    three new rows as a SHEET: the card's new height, the popup opening on
    the style chosen before a relaunch, and the Replace list on a real
    project with two caption tracks, checked, then Generate, then one ⌘Z.

- **The track context menu (2026-09-23)** — `track_menu_probe.py` sends
  synthetic right-mouse-downs through the content view's `menu(for:)` and
  performs the items; what it cannot reach:
  - **⌃-click.** AppKit routes a control-click to `menu(for:)` before any
    `mouseDown`, the same path `MediaRowView`'s menu relies on; nobody has
    pressed one on a header or a lane and seen the menu rather than a drag.
  - **The menu, LOOKED AT**: that it pops up at the pointer over a header
    and over an empty lane, and that the checkmarks read at a glance.

- **Space from anywhere (#35, 2026-09-24)** — `space_key_proof.py` proves
  the route and that play toggles; it cannot hear. At the machine: commit
  an inspector number field with Return, press Space, and hear NO beep as
  play starts; then turn Full Keyboard Access on, Tab to a checkbox or a
  button, and press Space — the control presses and play does not start.

- **The text editor grows as you type (#36, 2026-09-24)** —
  `text_edit_proof.py` measures the editor's frame and line count against
  the applied box; it cannot watch. At the machine: double-click a centred
  auto-sized text on the canvas and type — the field widens about its
  centre with no wrap, and committing the edit moves nothing on screen but
  the editor's grey plate going away; then the same on a fixed-width text, where the field
  keeps its width and grows downward line by line. Also unmeasured: a
  composition through an input method (marked text), which may not refit
  until the composition is committed.

- **Return applies in the canvas text editor; Esc asks (#37, 2026-09-24)** —
  `text_apply_proof.py` drives Return, the modified Returns and Esc into the
  editor, but presses the sheet's buttons with `performClick`: offscreen the
  sheet never becomes key, so which button Return and Esc press there is
  READ (Apply the default button cell, Cancel's Esc key equivalent), not
  driven. At the machine: double-click a text on the canvas, type, press
  Return — the edit applies and ⌘Z takes it back; ⇧Return starts a new line.
  Type again and press Esc — a sheet asks; Esc on it goes back to typing
  with the text kept, Return on it applies. Also unmeasured: Return and Esc
  while an input method is composing (marked text), which the route leaves
  to the input method.

---

## 5. Where a third road map would start

**Road map 10, graphics (EXPERIMENTAL on the branch `svg-motion`; G0 spiked 2026-09-24, G1 the engine BUILT 2026-09-24/25; G2 the model BUILT 2026-09-25; G3 the picture BUILT 2026-09-25; G4 next).** The user asked for Remotion-style motion graphics: a clip whose JavaScript module, in the package's `graphics/` folder, returns SVG per frame, written mostly by an agent over MCP. `designs/reelcut-roadmap-10.md` is the design, reviewing the user's input plan `designs/svg-motion-components-plan.md` in its §1. **Its spike G0 ran complete** (§10.1, instruments in `tools/proof/graphics_spike/`, all nine rows `run`, `core/` and `app/` back at `c874069`): `rquickjs` 0.14 vendors quickjs-ng 0.16.2 and takes §5c's module verbatim; the engine builds into the one staticlib with `make test` only 1.12× slower warm (no cargo feature), at +18 s per cold build, +11.8 MB of staticlib and +7.2 MB of app binary that the linker keeps even with nothing calling it; the six sample graphics cost a worst p95 of 7.62 ms per frame at 1080p (so G6 is not owed; 4K full-frame fills reach 26 ms); 864 renders across 8 threads in shuffled orders matched byte for byte, and the on-purpose module-level-counter mutant was caught (137 mismatches); eighteen sandbox cases each answered in words with the process alive (four of them, `constructor` routes back to the wall clock and to compiling code from strings, added and closed after G0's review); `measureText` must answer the INK box as well as the advance, a font family the set lacks draws nothing, and `Source Sans 3` must be quoted; a directory `DispatchSource` raises `.write` (never `.rename`) and misses in-place saves, and only CREATING a folder inside an open package trips "changed by another application". §3a lists every section a row rewrote. **G1 (the engine) starts from road map 10 §9a**, which lists what each later phase must carry from G0, and from those rewritten sections: `raster-images` on, `serde_json` with `preserve_order`, the `ReelCore.swift` toll first (§5e), and the spike's `src/runtime.rs`, `raster.rs` and `stdlib.js` as the working reference for `graphic/`. Its decisions G-1 to G-13 are proposals until the phase that needs each copies it into spec §11; G-1 and G-2 amend spec §1's plugin non-goal and §7's pixel rule. **G1 is BUILT** (road map 10 §10.4, G1a–G1d): the `graphic/` crate (resvg drawing, QuickJS runtime, sandbox, standard library), linked into the core through `core/src/ffi_graphic.rs` alone, with nine `rc_graphic_*` exports, their `ReelCore.swift` wrappers, `docs/graphics-api.md` evaluated by a test, and `tools/proof/graphics_ffi_probe.py` (9/9); the app binary grew 12 661 536 → 20 596 752 bytes; spec §11 holds G-1, G-2 and G-5. Linking `graphic` unified `serde_json`'s `preserve_order` into the core, so `content_hash` now sorts before it hashes. Nothing a person sees exists yet. **G2 (the model, format version 10) is next**, from road map 10 §5g and §4. **G2a is BUILT** (road map 10 §10.5): `Source::Graphic`, `Clip.graphic` and format version 10, the ops `add_graphic_clip` and `set_graphic` in the core (props checked against the schema the op carries, a colour normalised to hex, the 64-key limit on the stored map, the props order kept), the app decoding a graphic clip, and spec §11 G-3, G-4, G-12 and G-13; the two ops sit in `AgentServer.opsWithoutTools` until G3 writes their tools. Owed from it: `tools/proof/op_catalog_proof.py:282` (`len(ops) == 57 and ops <= tools`) FAILS from G2a until G3 adds the two tools; `tools/proof/words_core_proof.py` hard-codes the format version (moved 9/10 → 10/11 by G2a) where it should read the header's `RC_FORMAT_VERSION` as `phase9_proof.py:168-173` does; named CSS colours and `hsl()` in a `color` prop. **G2b is BUILT, and G2 is closed** (road map 10 §10.5): `split` gives a graphic's second half `in + cut` and pins both halves' `length` to the original's effective length, `trim_start` and `roll` advance `in` with no head bound, `trim_end` leaves `length` alone, `set_action_end` refuses `graphic` in G-10's sentence, and the recipe publishes a graphic layer (`recipe_graphic.rs`: `frame`, the engine's `ctx`, the stored props and a hash over all of them); spec §11 now holds G-6 to G-11, G-9 with G2b's three decisions G-9·a/b/c. Owed from G2b: `add_transition`'s handle form extends a graphic's head without moving `graphic.in`; a canvas rate change does not re-snap `in`/`length`. **G3 (the picture) is BUILT** (road map 10 §10.6, G3a–G3c): the package's `graphics/` folder with its store and watcher; a graphic clip drawn from the registry's compiled set, with `add_graphic_clip` and `set_graphic` as tools; and failure and export — a graphic that fails draws its error card, `render_frame` names every graphic that warned or failed in the frame, an export refuses a module that does not compile before it starts and stops at the first frame that fails with no file left, and every export and offline frame PINS the document's compiled set as it was when asked (queued jobs included). G3c also fixed a crash the export's Cancel button had since phase 7 (`ExportWriter.cancel` cancelled the reader under a running pump; road map 10 §10.6 G3c). Owed from G3: the playback check (§4 above); a nest inside a nest is not reached by the export gate; the loudness measurement's own cancel still cancels its reader from main (`Exporter.cancel`); and G3b's list (the frozen `AgentServer.swift`'s numerals, `words_core_proof.py`'s version literal, `add_transition`'s handle form). **G4 (the six app-state tools, road map 10 §5h) is next.** Nothing merges to `main` until the user decides, after G4.

**Road map 9, the clip inspector redesign, is COMPLETE (phases 1, 2, 3a
and 3b 2026-09-23, phases 4 and 5 2026-09-24; road map 9 §2, §4, §6, §8,
§10 and §12).** The selected action is the sixth piece of view state (spec
§11 CI-1 to CI-4): the timeline and the Clip tab's action lane highlight it,
the inspector's fields show and write its END state, esc and the Clip chip
leave it, ⌫ removes it. The Clip tab is sub-tabs by kind under a block
pinned above the scroll view (CI-5), with `◆N` key counts and the block knob
(CI-6); its rows carry marks (3a, CI-7, CI-8); and Reset shows only when a
section differs, Clear takes a section's keys out of the selected action, a
keyed row's ◆ is a × on hover, every row has a context menu, and a person's
refusal is shown at the inspector's foot (3b, CI-9, CI-10). A band is
dragged in the lane and on the timeline with the HUD and the ghost, and the
lane carries the hatch, fades and wedges (4, CI-11, CI-12); the canvas's
handles follow the mode, a switch inside an action keys the property off,
every sub-row carries `mixed` and the collapse honours Reduce Motion (5,
CI-13 to CI-15). **Nothing in it is scheduled next.** What is left of it is
a person's — §4's checks per phase — and the handoff items road map 9 §6
lists as not built (the 64 pt label, the dashed ⊘ border, the boxed "clip"
tag, a "now" readout on ○ and on colour and popup rows, a keyed border on
colour wells, `DS.textDim`, hover states, the 8/10 body padding; Reduce
Motion is built), each a decision to take up rather than a phase owed, and
the deviations each record keeps, which stand.

**Road map 8, word captions, is BUILT (2026-09-23; road map 8 §10, W0 to
W4b).** Both engines page a run's words into width-measured, word-timed
pages in five styles besides Subtitles; each page is an ordinary text clip
carrying `words`, `word_style` and `case` (format version 9), drawn by a
fourth text routine; File ▸ Generate Captions… chooses the style with a
preview drawn by the renderer and can Replace the caption tracks it made,
and `transcribe` takes the same `style` and `replace`. **Next work on word
captions starts at road map 8 §7's not-built list** — AI emphasis and emoji,
a sliding pill, a karaoke fill within a word and "dim during silence",
restyling in place, WebVTT inline timestamps, filler words, per-word
confidence styling — each with the reason it was left there. **One residue
W4b found and did not fix**: `cloud_captions_probe.py` leaves its
`cloudprobe-*` `UserDefaults` suites in `~/Library/Preferences` (1 619 files
after W4b's run of it) — `removePersistentDomain(forName:)` cannot win
against cfprefsd's late write, and the harness's `MemoryDefaults` is the
shape that does (road map 8 §10.10). The 1 619 files were deleted by hand
on 2026-09-23 at the user's request; the probe still writes new ones on
every run until it moves to `MemoryDefaults`. **Detector
pauses are NOT owed**: W4a's P10 measured the pangram's two pauses breaking
by sentence punctuation alone, and road map 4's detector intervals injected
as forced breaks changed no page; a recording whose pauses carry no
punctuation is where that measurement would have to be taken again.

**Word captions, road map 8 (designed 2026-09-22; W0 SPIKED the same day; BUILT 2026-09-23 — the paragraph above).** The user asked for social-video captions: one row of large styled text, each word shown or highlighted as it is spoken, from either engine, with a style chosen at generation and pages filled to the measured width rather than a word count. `designs/reelcut-roadmap-8.md` holds the research, the design and the user's answers (§6), including the move to a macOS 26 minimum with `SpeechTranscriber` as the on-device engine. **Its spike W0 has run: all seven rows of §3 measured, §10.1 the record, §3a the list of design sections a row overturned, `tools/proof/words_spike/` the instruments.** **W1a, the macOS 26 bump, LANDED 2026-09-22** (road map 8 §10.4): `make typecheck` 0 errors / 7 warnings, `make app` rc 0, the same three frames byte for byte out of the 15.0 and 26.0 builds, 40 proof files moved off `arm64-apple-macos15.0`; the root `CLAUDE.md` baseline sentence is owed by hand.

**Road map 7 continuation:** all six §12.2 items were implemented in sequence
and passed independent review: structural-time and bounded-transition work
(§12.6), frame-grid normalization (§12.7), placement commit extraction
(§12.8), historical proof comparisons (§12.9), the Speed sheet explanation
(§12.10) and argument-contract coverage (§12.11). The capped
`edit_clip.rs` still has 751 lines after part 3's separately gated pure move
and caller deletion; no other size debt was paid here.

**Review closeout (2026-09-22).** The four-issue set (#23, #27, #30 and #32)
passed its latest independent reviews with
no unresolved implementation review findings. Their records are road map 4
§9, road map 5 §13, and road map 6 §§10.19–10.20. This review status does
not discharge the live-provider, source-identity or hands-on acceptance
limits below.

**Waveform peaks #23:** the level half of road map 4's partial-decode bug is
implemented in road map 4 §9. Its peaks-only versioned marker and strict
reader/PCM coverage keep a failed decode pending and distinguish real silence.
The shared `CacheStamp` remains byte-for-byte the same type for thumbnails,
speech and transcripts. The separately gated pure move paid both Swift size
tolls; the final files are `MediaImporter.swift` **576**,
`MediaCacheFiles.swift` **486**, `MediaImporter+Peaks.swift` **116** and
`MediaPeakBuckets.swift` **161** lines. A real-user listen and visual waveform
judgment are still part of §4's acceptance rather than an automated claim.

**Mixed audio formats on one track #34 (2026-09-24):** an AAC clip then a
WAV on one timeline track previewed silent — the preview's tapped item stalls
over a composition track that changes format. `CompositionBuilder` now makes
one composition audio track per source format (spec §11 R2-1); the record,
the baseline's failing rows and what is owed are road map 2 §2, Phase 5,
"#34 — mixed audio formats on one track" (kpgalligan/reelcut#34). A listen
at the machine, and section 4 on the built-in speakers, are still owed.

**Space beeped off a committed inspector field #35 (2026-09-24):** an
inspector number field's commit left the WINDOW first responder, and a bare
Space beeped instead of playing. `EditorWindow` now routes a bare Space
before dispatch (spec §11 K-1); the record, the baseline's failing rows and
what is owed are road map 2 §2, Phase 8, "#35 — Space toggles play wherever
nothing is typing" (kpgalligan/reelcut#35). The proof is 28/28 and its
baseline fails exactly S2a and S2b; its S2e row scores that the window hands
an `NSButton` the Space, not the press, which needs Full Keyboard Access and
is §4's hands-on check. Owed and NOT fixed there: every OTHER bare key
(J/K/L, W/E, I/O …) is still dead after an inspector field commit until a click
(`OptionControls.swift:244`'s `makeFirstResponder(nil)`), and
`handleEditorKey` refuses every bare key while Caps Lock is on
(`flags.subtracting(.shift)` at `EditorViewController.swift:716` leaves
`.capsLock`), where the new Space route allows it.

**The canvas text editor did not grow as you typed #36 (2026-09-24):** the
in-canvas editor kept the frame the box had when editing began, so typed
text wrapped inside it and the box jumped to its real size on commit. The
editor is now sized, after every change, from the same measurement that
sizes the applied box; the record, the baseline's failing rows and the
limits left are road map 2 §2, Phase 4, "#36 — the canvas text editor grows
as you type" (kpgalligan/reelcut#36). A look at the machine is §4's.

**Return did not apply in the canvas text editor, and Esc dropped a change
#37 (2026-09-24):** a plain Return inserted a newline (only ⌘Return
applied), and Esc discarded a changed string without asking. A bare Return
now applies, a modified Return is a new line, and Esc on a changed string
asks Cancel / Revert / Apply (spec §11 K-2); the record, the baseline's
failing rows and the limits left are road map 2 §2, Phase 4, "#37 — Return
applies in the canvas text editor; Esc asks" (kpgalligan/reelcut#37). The
Text tab's `InspectorTextArea` keeps its own keys by decision; a look at
the machine is §4's.

**Bounded recovery after a lost AssemblyAI submit reply (#28).** R6-14 reads
only the newest page of 200 transcripts at most three times. An outage,
visibility lag beyond those looks, more than 200 intervening account
transcripts, multiple exact URL matches or a crash can leave a remote
transcript that Reelcut cannot identify or delete. The run tells the person
to check their AssemblyAI dashboard before retrying and makes no later
automatic cleanup claim. A durable pending-submission journal and an
account-wide janitor remain outside this fix.

**Where the next work starts, after C1 (2026-09-21).** C1 — captions from
the cloud — is BUILT, over five pipelines whose record is road map 6 §10.
Two things are deferred, neither a next phase to start
(C1's reader review was run on 2026-09-21 and its record
is road map 6 §10.13 — including the independent sceptic pass over it and the
fix pass that answered that pass's six findings, both the same day):

- **C2, the relay, is deferred by the user (2026-09-21).** The current plan
  is C1's user-supplied AssemblyAI key; an integrated AI offering for Reelcut
  users has not been designed. Road map 6 §6 remains a future design
  reference, and §10.18 records the decision. If C2 is resumed, §6b's
  identity prerequisite still needs an answer.
- **`KeychainStore` waits for a stable signing identity.** The key is a
  `0600` file because a rebuilt ad-hoc-signed binary cannot read its own
  Keychain item without a modal and cannot delete it at all (road map 6 §3
  q7). A Developer ID build can have the Keychain back; nothing else has to
  change.

**Residue from road map 6's c1-chrome, 2026-09-20.** Two things that pipeline
left, neither blocking anything. Its two INHERITED nits — c1-run's reader
review's — are CLOSED: `CloudTranscriber`'s per-media closing publish now
sends `CloudProgress.detail(.saving, file:)` instead of an empty string that
would have blanked the sheet's detail label between media (the probe's `run`
section gained a row and an `empty-closing-detail` mutant), and
`MediaTranscript`'s `ms × 600` now goes through
`sourceTicks(milliseconds:)`, clamped in `Int` first, which spec §11's
R6-10 was extended to cover before the code (nine mapping rows, one child per
millisecond, and a `no-ms-clamp` mutant that fails four of them by TRAP).

- **`transcribe`'s result says WHERE it spoke, and nothing does.** Spec §11's
  R6-12 declined a `region` key: every proof instance runs under
  `-RCAssemblyAIEndpoint`, so the region is not where the run spoke and the
  key could be proved only on the one host where it is false. The honest
  shape, if a later phase wants one, is the base URL's **HOST** under a key
  named `endpoint` — true under the override and under either region, and
  measurable by every existing instrument. It is a new result key, so it is a
  tool change with a catalog row and a parity consequence, and it belongs in
  a phase that is changing the tool anyway.
- **The estimate and the run classify a media in two places on purpose.**
  `CloudEstimate.fate` answers what a run WOULD do and
  `CloudTranscriber.transcribe` answers what it DID, and c1-chrome
  deliberately did not merge them: one is a readout a person reads before
  agreeing to spend money, the other is the run's own record. A `chrome` row
  compares the two over two rounds so the day they drift is a scored failure.
  A later phase that wants one spelling has to keep that row and make it
  compare the merged code against something else.

**Residue from road map 6's c1-parts, 2026-09-20.** **NINE** things, which is
this block's own `- ` lines counted on 2026-09-21 by the reader review
(H·9): it opened saying FIVE and had been added to four times since — by
c1-parts' own reader review's two nits, by c1-chrome's order-dependent probe
row, and by the `speed` bullet that opened the moment the one above it
closed. Three of the nine are now struck through: the two nits are judged
(H·1 refuted, H·3 fixed) and the probe row is fixed (H·5); the rest stand.
None of them blocks anything.

- **This Mac's 16 kHz audio extract is not bit-deterministic.** Measured over
  ten processes of one binary over one fixture and five trials of three
  decodes inside one process: a decode lands on one of exactly two byte
  strings differing in ONE byte — one 16-bit sample's low bit, at offset
  132 098 of a 336 532-byte WAV — about one decode in five, in either
  direction, independent of the range asked for, the binary and the order
  within a process. It is recorded here because it is the second
  non-determinism this project has measured in AVFoundation's audio (the
  first is the export's 8 ms duck-ramp window, app/CLAUDE.md) and because any
  future row that wants byte-identity from an extract has to be written the
  way `cloud_captions_probe.py`'s rows W and Q are: a population, not a
  comparison. Nothing in the product depends on the flip — one sample's low
  bit changes no word's timing — and it is not worth chasing.
- **`AssemblyAIClient.swift` needed a second file and `MediaTranscript.swift`
  a third home for its stamp**, both to stay under the 400-line cap on a new
  file. Neither is on §3's ledger; both are recorded in road map 6 §10.9 and
  in the files' own headers. A reader who thinks the client belongs in one
  file has a size toll to pay first.
- **`app/CLAUDE.md`'s Hygiene paragraph lists the permitted `DispatchQueue`
  seams, and c1-parts left that list one short** — it added
  `AssemblyAIClient`'s delegate `OperationQueue` and `CloudTranscriber`'s
  serial queue, both R6-7's carried-over shape, wrote map entries only, and
  left the RULE paragraph alone because no pipeline stage may amend a rule.
  CLOSED the same day by the session's orchestrator, by hand and outside any
  pipeline: the clause now sits beside `Transcriber`'s two and cites R6-7.
  It is the one rule C1 changed; the user was told, and it is theirs to
  reword or revert.
- **`MediaTranscript.project`'s speed guard had a hole its twin
  `Transcriber.project` shared** (c1-parts' second review, a nit): a FINITE
  but tiny positive `speed` passed the guard and could still overflow
  `Ticks(_:)`. **CLOSED 2026-09-20 by c1-run, for the CAPTION PATH and for
  nothing else.** Spec §11's R6-10 records the answer: the ops bound a
  clip's `speed` to 0.1–10 and the READER does not, so such a file reaches
  the app and both twins clamp — in `Double`, before the conversion, through
  the one door `Transcriber.placed`, with `Transcriber.contentLength` and
  `Job.sourceIn` bounded to `maxSourceTicks` = 1e15 at the other end.
  `cloud_captions_probe.py`'s `jobs` section drives `1e300`,
  `greatestFiniteMagnitude`, `1e-300` and `leastNonzeroMagnitude` through the
  CORE's own reader and then through `Transcriber.jobs` and both mappings,
  one child process per speed, and two mutants (`no-speed-clamp`,
  `no-length-clamp`) fail it on purpose. What is closed is
  `Transcriber.jobs`, `MediaTranscript.project` and `Transcriber.project`,
  and nothing else.
- **The REST of the app against a hand-written `speed`: NARROWED
  2026-09-21 by the reader review (road map 6 §10.13, H·4), not closed.**
  What IS now driven, at `speed` **1e300** and **1e-300**, on its own
  instance and with no trap and no expiry: `open_project`, `get_project`,
  `render_frame` at `t: 0`, `transcribe engine: "assemblyai"`, and the
  offscreen harness rendering the whole editor including the timeline. What
  is still unasked is everything else, and the reader review also found that
  the neighbouring input is WORSE than the speed: a hand-written clip
  `"duration": 9223372036854775807` kills the app during `open_project`
  (kpgalligan/reelcut#31, `spec`), where 2^62 and 1e18 open and draw.
  `app/Sources/CompositionBuilder.swift:386` sums
  `segment.sourceIn + segment.sourceDuration` off a core length that
  SATURATES at `i64::MAX`, which is a sum this pipeline chose 1e15 precisely
  to avoid on its own path; the timeline, the peaks window, the reversed
  mirror, the plan and the exporter have not been asked either. Whether any
  of them traps, and whether the answer is a bound in each of them or one in
  `Project::validate` (declined by R6-10 for the reader's own reason), is
  nobody's yet.
- **`tools/proof/cloud_captions_proof.py` EXISTS.** CLOSED 2026-09-20 by
  c1-run: 115 rows over three instances, 5i's rows 1–11 plus H, T, K and X,
  nine mutants each built in a tree copy and each named with its score (road
  map 6 §10.10). Rows 14 and 18 landed 2026-09-20 in c1-chrome as the
  probe's `estimate` and `chrome` sections (road map 6 §10.11); the live
  rows 20–21 are CLOSED 2026-09-21 by c1-close — `--live` (off by default)
  runs them through `cloud_captions_live.py` against `api.assemblyai.com`
  under a ledger with a $0.25 ceiling, and the whole of C1's live spend is
  TWO transcriptions of the eleven-second `say` fixture — one per live run,
  22 billed seconds at $0.21 an hour, **$0.00128** — each deleted and proved
  gone by C0's q6 sentinel (road map 6 §10.12, and
  `work/cloudlive/ledger.json`'s own six reservations).
- **`media/speech.mov`'s 16 kHz extract is not repeatable at all**, which is
  a SECOND and larger non-determinism than the one-sample flip above.
  Measured by c1-run: four extracts, four distinct byte strings of ONE length
  (167 930 bytes), spans 105–228 bytes — about 60 to 115 samples. The `say`
  AIFF over the identical code path is the two-string population above, so
  the difference is the AAC decode and not the resampler. Any future row
  wanting bytes out of an extract should use an uncompressed fixture; road
  map 6 §5i·2 was revised, dated, to say so and to say what it replaces.
- ~~**Two nits from c1-parts' reader review were left unfixed**~~ — both
  JUDGED 2026-09-21 by the reader review (road map 6 §10.13, H·1 and H·3).
  `AssemblyAIClient+Session.swift`'s `sink(_:)?.progress?(…)` is **REFUTED
  as a race**: `progress` is written once, before the sink is published under
  the lock, and every reader reaches it through the same lock, so there is a
  happens-before edge and no row that could fail; the field is left a `var`.
  `SecretStore.swift`'s `writeAll` is **FIXED**: it retries `EINTR` and
  nothing else, through an injected-writer seam whose default IS `write(2)`,
  with three rows in the probe's section 17 and an `eintr-unwritable` mutant
  that fails the retry row and neither of the other two.
- ~~**One probe row of c1-chrome's leans on the ORDER of its section**~~ —
  **FIXED** 2026-09-21 by the reader review (road map 6 §10.13, H·5). The
  row takes the fake's request count before the child runs and asserts that
  nothing NEW arrived across the click. Made to fail in a COPY of the probe
  outside the tree with one request sent into the shared fake above the
  block: **76/77**, the old assertion failing and the new one holding.

**Residue from road map 6's reader review, 2026-09-21.** Three nits from its
second sceptic pass, none fixed (litecode runs no second fix pass, and none
is a wrong answer a person would meet with AssemblyAI's real service):

- **"The next run retries it" is false for an id that cannot be sent.** When
  a server's body echoes a transcript id that is not a plain identifier,
  `fetch` gets `notSent` and records `remote_deleted: false`, and the tool's
  `note` (`AgentServer+CloudCaptions.swift`) and the report card
  (`TranscribeSheetController+Commit.swift`) both promise a retry the janitor
  will refuse in silence for ever. The true sentence would say the id could
  not be sent.
- **Two probe rows count five and assert six.** `cloud_captions_probe.py`'s
  two new row-I checks say "none of the FIVE" and assert over all SIX planted
  ids, the well-formed CONTROL included; they pass only because the fake
  answers that one DELETE 404.
- **A stale comment.** `cloud_captions_proof.py`'s comment beside its row-5
  helper still says the split is at 2.5 s; the reader review moved it to
  3.0 s.

**Residue from road map 6's c1-close, 2026-09-21.** Three things the live rows
measured and deliberately did not fix:

- **`print` is BLOCK-buffered under a file redirect, so every instance log
  under-reports the client's lines.** `AssemblyAIClient+Session.swift:98`'s
  `note` prints one line per request; with stdout redirected to a file (which
  is how every proof instance is launched) Darwin buffers it 4096 bytes at a
  time and the last line in the buffer is cut in half. MEASURED by c1-close:
  `/tmp/reelcut-4960.log` holds exactly 4096 bytes of client lines and
  4970–4972 hold NONE, and road map 6 §10.10's row K read such a log. The
  live rows answer it in the INSTRUMENT — a `pty` per live instance, drained
  by a thread that never raises — rather than in the app, because a
  `setvbuf` or a `FileHandle` in the product would be a change no product
  behaviour needs. Anything that wants to COUNT an instance's client lines
  has to use the pty; a log is a lower bound.
- **`xcodebuild` writes every task's ENVIRONMENT into its build database**,
  so `make app` run from a shell that exports `RC_ASSEMBLYAI_KEY` leaves the
  key in `build/Build/Intermediates.noindex/XCBuildData/<hash>.xcbuilddata/`
  — measured by c1-close's own sweep on 2026-09-21, which found it in two of
  that folder's four databases (both from builds made before this pipeline)
  and in six Xcode build trees under a scratch directory. `/build/` is
  gitignored and nothing under it is tracked, so none of it can reach a
  commit, and every mutant build the proofs make goes through
  `cloud_captions_probe.child_env()`, which is why `tools/proof/work/` holds
  none. The rule this asks for is the one the proofs already follow and a
  person at a terminal does not: **build with the variable removed** —
  `env -u RC_ASSEMBLYAI_KEY make app` — and delete those databases (they are
  a cache; the next build remakes them) on a machine where the key has ever
  been exported. **What was done about it on 2026-09-21:** the session's
  orchestrator located the tainted `.xcbuilddata` directories with an
  in-process comparison that printed paths only, and deleted EIGHT — the
  repo's two and six under the session's scratch directory; a second pass
  found TWO more under that scratch directory's `e2rev/copy/build/`, the
  command that would have removed them was declined, and they were left for
  the user with their paths. A sweep of the repo, the handoff directories,
  the memory folder and `/tmp/reelcut-*.log` after the first deletion found
  the key nowhere else. ~~NOT done, and worth a decision: the `Makefile`'s
  `app` target could remove the variable itself~~ — **DONE 2026-09-21** by
  the reader review (road map 6 §10.13, H·2): one directive, `unexport
  RC_ASSEMBLYAI_KEY`, above `.PHONY`, which covers every recipe in the file,
  so a person's ordinary `make app` cannot write the key either. It is
  measured by `tools/proof/makefile_env_proof.py`, which builds a tree COPY
  with a recognisable dummy exported and searches every file under the copy's
  `build/` and `Reelcut.xcodeproj/` IN PROCESS: **2/2**, no file of 448
  holding the dummy, and **1/2** under `--mutant no-unexport`, where it lands
  in that folder's `task-store.msgpack` and one attachment beside it — which
  is this bullet's own measurement, reproduced and then closed. **It measures
  the `app` recipe only**, which is the one that runs `xcodebuild`. The
  person's own value is never read, printed or searched for; the dummy is
  `RCDUMMY-makefile-env-proof-5d1c`.
- **A submit whose transcript id never surfaces cannot be recovered by this
  tree.** `cloud_spike/aai.py`'s `find_own` matches a transcript by the
  UPLOAD URL the spike recorded, and the app never exposes its upload URL —
  `AssemblyAIClient+Session.swift`'s `note` prints a method, a path and a
  status and deliberately no URL — so `find_own` has no caller in the live
  rows and one page of the account's transcript list is never fetched. A
  `POST /v2/transcript` with no id in the lines that followed it therefore
  closes `unresolved` in the ledger, named for a person, rather than being
  chased. Nothing has ever printed such a row: C1's live spend is two
  submits and two ids, one of each per live run, and the ledger wrote no
  `extra` reservation at all.



`designs/reelcut-roadmap-2.md` §4 is the list of what was deliberately left
out, and it stands. One of its conditions has now been met and the bullet
should be read in that light: **"a left-hand media browser with bins — phase
8's search and sort come first"** — they have landed, so spec §11's trigger (a
library that has outgrown the pane) is the only thing still gating it.

**Screen recording is BUILT, and pausable** (road map 3's R1 and R2; the record is in that file) — the
sentence below is kept as the pointer it was: `designs/reelcut-roadmap-3.md`
reverses spec §1's non-goal by a recorded decision and lays out the spike
and the one phase that builds it — built, reviewed and fixed since; its
record is in that file.

The others, unchanged: voice-over recording (one session, and the user's call
since spec §1 excludes capture); speed ramps (feasible, unasked — `speed` is
not an action target and the model, the plan and the audio envelopes would all
have to learn); and the explicit non-goals — LUTs, motion blur, stabilisation,
optical-flow retiming, auto-reframe, multicam, plugins, other platforms.

**One pre-existing defect a caller CAN reach, filed and not fixed** —
kpgalligan/reelcut#24, found by the sceptic's second pass over road map 4's
reader review and outside that diff entirely
(`designs/reelcut-roadmap-4.md` §8). A clip's `start` is bounded at ±9.0e15
**per call** (`snappedTick`, `app/Sources/AgentServer+Arguments.swift:370`)
and never cumulatively, so about 1020 successive maximum-delta `move_clip`s
walk a clip's start toward `Int64.max`. The core SATURATES and says nothing
(`core/src/edit_clip.rs:557`, `clip_end` :95); the app then TRAPS on the
same sum, `ClipSnapshot.end` being `start + duration`
(`app/Sources/ProjectSnapshot.swift:1700`), during
`TimelineView.rebuildLayout`, and the process dies. Reproduced once, by the
sceptic, 2026-09-20. It is labelled `bug` and deliberately NOT
`ready-for-agent`: **where the bound belongs is a spec §11 decision** — a
ceiling on `start` in the core's own op, refused in the rule's own sentence,
or overflow-safe arithmetic in the app, which changes nothing a caller can
see. A person picks one and records it before any code.

**Two findings of the E2 reader review, filed and not fixed**
(`designs/reelcut-roadmap-5.md` §12, R2·3 and R3·2; 2026-09-20).
**kpgalligan/reelcut#26** — `set_canvas {"fps": [24,1]}` on a 30 fps project
re-snaps every clip, action and marker time and leaves `video.motion`'s
`duration` and `period`, and `text.animation`'s two timings, exactly where
they were: on a 25,000-tick grid a stored 20,000 is sub-frame, against
`core/CLAUDE.md`'s Times rule. `paste`'s re-snap from another rate has the
same hole. Nothing renders wrong — `motion::apply` interpolates continuously
and never reads the grid — so what is broken is the invariant and what an
inspector shows. Not fixed here because the root, `core/src/edit_canvas.rs`,
was outside that review's file list and because text's timings are in the
same position; labelled `bug`.
**kpgalligan/reelcut#27 — resolved in spec §11's E2-27 and road map 5 §13.**
Zero-duration In/Out remains legal, stored, editable and inactive. The
timeline omits its wedge; the Motion inspector and Clip ▸ Motion menu name
the inactive configured edge, with Duration available to reactivate it and
None/Reset available to clear it. The core contract and format stay unchanged.
Current author-file sizes after #27 (`wc -l`): `MotionProps.swift` 230,
`TimelineClipDrawing.swift` 454, `VideoPane+Motion.swift` 243,
`EditorViewController+Motion.swift` 184; the new `motion_zero.rs` is 89.

**kpgalligan/reelcut#30 — resolved by R6-15 and road map 6's #30 record.**
Transcript identity now ignores display-cache metadata and reads legacy wide
markers without rewriting them. The remaining limits are the existing
modification-second/recorded-duration identity without a content hash or
path, and that an older build requiring ten source keys cannot read a new
four-key marker. #32/R6-16 admits an unrefreshed, all-current-cache batch
without a key; cloud work and deletion retry still require a key. Live
AssemblyAI verification remains a separate
person-authorized check; the #30 proof uses only dummy loopback credentials.

**One pre-existing defect nothing can reach**, found by the probe deepening
D2·2 built and named here because that ticket said it belonged in this
document: `ProjectDocument.performGroupedEdit` opens an undo group and
balances it whatever the edit answered, so an edit that changes nothing
leaves an EMPTY group behind — a step a person would press ⌘Z twice past. It
has been true since an identity has been possible and no caller reaches it:
the agent refuses at its own trial first and the menu path does not use that
entry point. `tools/proof/refusal_probe.py` prints it as a note rather than
scoring it, so the day a caller does reach it the probe already says so.

**A second op whose tick argument is bounded only by `i64`, filed and not
fixed** — kpgalligan/reelcut#25, found by the E1 reader review
(`designs/reelcut-roadmap-5.md` §12, R1·3 and R1·6; the limit is §3j's).
`add_transition`'s step-down and `add_transition_by_shift`'s both remove ONE
frame per pass. The handle form used to walk the caller's `duration` — 4.5e11
passes and about 36 hours at the 9.0e15 the argument gate allows, from a
measured ladder — and that is fixed: the request is held to
`(A.duration + B.duration) / 3·frame`, the most the overlap rule can pass at
any split. **What is left is that the CLIPS are the caller's too.** One
ordinary `add_text_clip {duration: 9000000000000000}` makes a clip that long,
and a lopsided split over two of them walks ~6.7 hours, extrapolated from
0.181 / 1.607 / 16.134 s at d = 6e10 / 6e11 / 6e12; the run at the full value
**expired at 120 s (pid 61383 killed)**, which is its measured answer. It is
#24's family — a per-call bound with nothing cumulative behind it — and what
would close it is either a bound on a clip's DURATION at the door or a closed
form for the step-down, which needs a decision: the loop's own doc calls the
predicate "not monotone in an obvious direction", so a binary search would be
relying on the opposite. Labelled `bug`, not `ready-for-agent`.

**One HOST limit with a cost at export**, measured by `e1_proof.py` §5 and
recorded in `designs/reelcut-roadmap-5.md` §12 (2026-09-19): AVFoundation does
not apply a mix input's first volume point for some twelve milliseconds, so
the first 25 ms of an incoming clip come out at about half full scale whatever
the ramp asks for — and the same burst is there at a hard cut with the clip
MUTED, which is where the proof scores it, so nothing in Reelcut is what puts
it there. It is bigger than road map 5 §4e's own sentence expects ("one LSB
within 8 ms of a ramp edge") and it is in the exported file, not only in
preview. Nothing is filed for it and no fix is attempted here: what a later
road map could try is giving the first breakpoint a lead-in — a ramp that
starts before the clip does — and re-measuring with `e1_proof.py`'s §5 rows,
whose window 0 is printed and whose hard-cut row is what would move.

**The commit tail is implemented, not waiting.** Road map 7 §12.3's counts
are the dated inventory before part 3. Part 3 separately gated the pure move
and then moved candidate placement checks, storage and transition finalization
into `edit_commit.rs`; §12.8 holds the measured deletion, exact behavior
proof and independent review. The extreme-time and frame-grid work in parts
1–2, historical comparison repair in part 4, Speed sheet explanation in
part 5 and argument-contract coverage in part 6 are recorded in §12.6–§12.11.
The separate product choices in §12.4 and human checks in §4 remain open.

Three small things the closing turned up that a third road map would pick up
on its way past, none worth a phase: `relink_media` could re-probe the file
it is pointed at (§2a's recorded limit); the panel and MCP spellings of a
caption name carrying another of the app's containers could be made to agree
by a decision in spec §11 (§2b's); and `SilenceSheetController.cacheChanged` re-read on a
peaks or speech post only while something was pending, so spans an open sheet
measured from a file that an MCP `relink_media` then swapped away (the sheet
is modal, so nothing else can) stayed until the sheet was reopened — left as
a one-line guard on the belief that no proof could drive the sheet.
**Closed 2026-09-20** by road map 4's reader review (§8, R2·2): the belief was
wrong, `silence2_probe.py`'s claim 17 drives the sheet through a real document
and posts at it, the guard is gone, and two rows there swap the `.bin` under
an open sheet with nothing pending and watch the readout follow. A copy with
the guard restored scores 64/65, taking the first of the two.

Two more, found 2026-09-19, **both closed 2026-09-20**:

- **The triage labels the document names and the repository lacked.**
  `docs/agents/triage-labels.md` maps five roles to five label strings and
  only `ready-for-agent` and `wontfix` existed, so `gh issue create --label
  needs-triage` failed — observed 2026-09-19 when kpgalligan/reelcut#22 was
  filed: `gh` answered that the label `needs-triage` was not found, and #22
  went in with `bug` alone. The three missing ones — `needs-triage`,
  `needs-info`, `ready-for-human` — were CREATED with
  `gh label create`, each described in the document's own Meaning column;
  `gh label list` now prints all five roles plus `spec` and GitHub's
  defaults. Nothing else on GitHub changed: `spec` keeps its empty
  description, and issues **#23–#27**, filed 2026-09-20 with `bug` alone
  (#27 with `spec` too) because `needs-triage` did not exist, PREDATE the
  label and were deliberately NOT relabelled. The document gained a note that
  this repo carries a sixth label, `spec`, which never takes
  `ready-for-agent`.
- **The two frame-rate pair readers on `intValue`.** `fpsArg`
  (`AgentServer+Tracks.swift`) and `mediaDescriptor`
  (`AgentServer+Media.swift`) read each half of a `[numerator, denominator]`
  pair with `NSNumber.intValue` after the argument gate (road map 7 §11's
  named residue), so `set_canvas {fps: [29.97, 1]}` was 29 fps in silence.
  Both now read through `rateTerm`/`fpsPair` in
  `AgentServer+Arguments.swift`, which refuses a term by its own path —
  `fps[0]`, `fps[1]`, `descriptor.fps[0]` — and the bare-number path lost
  the `Int(number)` that TRAPPED on `set_canvas {fps: 1e30}`, a live crash
  READ from Swift's `Int(Double)` precondition at the removed line rather
  than reproduced (the mutant's `intValue` saturates instead of trapping).
  `designs/reelcut-app-notes.md`'s "Two frame-rate pair readers, 2026-09-20"
  has what each refused before and refuses now; the 17 proof rows are
  `tools/proof/op_argument_proof.py`'s term group (133/133, and 126/133 with
  the read put back).

**Two more, found by road map 7 §10's phase B (2026-09-20) and deliberately
left there**, both recorded in §10.8 as well:

- **`set_canvas`'s `resnap` does not re-snap clips INSIDE nests.**
  `core/src/edit_canvas.rs`'s `resnap` walks `project.clips` only, so a rate
  change leaves every nested clip on the OLD frame grid; the document is
  then a mixture, and nothing says so. Phase B's `unnest` vector is how it
  shows: a nest made at 30 fps and opened at 24 gives back clips whose
  stored times were never on the 24 fps grid, which is why `unnest` now
  re-snaps and bounds each one (spec §11, D4-4). Not fixed there because a
  rate change reaching inside nests is a document-wide edit with its own
  overlap question, and because the markers rule (`resnap` drops the second
  of two markers a coarser grid lands on one tick) would need an answer per
  nest. Found by phase B's scout and recorded nowhere before this.

  Road map 7 §12.7 now records the frame-grid implementation, including
  stored nests, property timings, paste, attributes and unnest. This bullet
  remains the historical discovery; disposition and issue closure await
  review of the part-2 gate.
- ~~**`SpeedSheetController.syncReadout`'s "→ duration" is the UN-HELD
  number.**~~ **CLOSED by §10's phase C** (2026-09-20, spec §11's D4-6).
  The readout is now the CORE's answer: `SpeedSheetController.lengths`
  applies the sheet's own `set_speed` ops to the immutable handle and reads
  the durations back, so it says the held number, the overlap rule's
  refusals and a mixed selection's sum without a second copy of the
  arithmetic in Swift and without a new `rc_*` export. Phase C left the
  sheet's hint describing only gaps; road map 7 part 5 (§12.10) corrected it
  to describe gaps, allowed overlap with a possible cross dissolve, and a
  refused clip staying unchanged while other selected clips can change.
  The readout still shows a length rather than the dissolve a neighbour
  gains; richer transition or per-clip presentation remains separate.

---

## 6. The Rust build settings, measured 2026-09-19

`core/Cargo.toml`'s one profile line, `[profile.release] lto = true`, does
NOT reach the shipped staticlib and DOES reach every test binary — the
reverse of what it is there for. Cargo passes no `-C lto` to a unit whose
crate types include `rlib` (rustc cannot LTO an rlib, so cargo skips the
whole unit), and the lib is `["staticlib", "rlib"]`; the `-v` line for the
lib carries `--crate-type staticlib --crate-type rlib -C opt-level=3
-C strip=debuginfo` and nothing else, and `libreelcut_core.a` has 437
members, 17 of them the crate's own codegen units, at 32 MB. With
`crate-type = ["staticlib"]` alone cargo does pass `-C lto=fat`, the build
takes 29.5 s instead of 11.6 s and the archive is 8 MB — and every
integration test then fails to compile (`error[E0433]: failed to resolve:
use of unresolved module or unlinked crate reelcut_core`), because a test
links the rlib. Product LTO would therefore cost a crate split (a shim crate
that is `["staticlib"]` only, over the lib crate) and eighteen seconds per
`make app`; nothing measured says the core's JSON, arithmetic and plan work
would repay it. The parent `~/devel/rasterize/core/Cargo.toml` has the same
line over the same two crate types, unmeasured there.

What the line does do is give each of the 31 integration-test binaries, and
the lib's own empty harness, a fat LTO over the whole crate graph from
bitcode, so one edit re-optimises the crate 32 times. Measured on the M2 Max
(8P+4E, 12 jobs — cargo's default `-j` and the right one), in a copy of
`core/` with one target directory per variant, wall clock in seconds:

| `[profile.release]` | cold build | build after edit | test build after edit | test run |
|---|---|---|---|---|
| `lto = true` (today; fat) | 17.4 | 11.7 | 166.3 | 6.8 |
| `lto = "thin"` | 17.4 | 11.2 | 172.0 | 6.8 |
| `lto = false` (thin-local, the default) | 16.9 | 11.6 | 26.2 | 6.7 |
| `lto = false`, `incremental = true` | 16.2 | 1.0 | 3.0 | 6.6 |
| dev profile, no `--release` | 12.1 | 1.1 | 3.2 | 9.9 |

The "after edit" columns above are a comment inserted at the top of
`outcome.rs`, which incremental hashing all but skips; with a real statement
added to `time.rs::snap_to_frame`, which the crate inlines everywhere,
`lto = false` + `incremental = true` measures 4.5 s to rebuild the staticlib,
6.1 s to rebuild every test binary and 8.7 s for the whole of
`cargo test --release`. A touched but unchanged file is the floor at 0.9 s
and 3.1 s. The other levers do not move: rust-lld through `-fuse-ld=lld`
against Apple ld-prime 1230.1 is 27.2 s against 26.2 s for the test build
(noise), and the `.a` itself is never linked on the Rust side at all;
`opt-level = 1` in dev is slower cold (19.4 s) and no faster warm;
`cargo test --doc` is 0.4 s and `[lib] test = false` saves 0.2 s; the deps
are some five seconds of a cold build, so sccache has nothing to save; the
671 tests run in under seven seconds across 31 binaries, so nextest has
nothing to parallelise yet. `panic = "abort"` is not available: `ffi_agent.rs`
catches unwinds. `make test` stays `--release`, as the rule says: the dev
profile is no faster to build and 3 s slower to run, and it would test a
configuration the app does not ship.

**LANDED 2026-09-19, uncommitted: two lines in `core/Cargo.toml`** — in
`[profile.release]` itself,
because `make rust`, `make test`, the Xcode pre-build script and
`LIBRARY_SEARCH_PATHS` all hard-code `release`, so a custom profile would
have to be threaded through four places:

```toml
[profile.release]
# No LTO: cargo skips it for a staticlib+rlib unit anyway, and asking for it
# fat-LTOs each of the 32 test binaries (166 s per edit; §6 of remaining).
incremental = true
```

That is `lto = true` deleted and `incremental = true` added; the shipped
`.a` is then codegen'd in up to 256 units instead of 16 (583 archive
members, 163 of them the crate's, 22 MB), and
`CARGO_INCREMENTAL=0 cargo build --release` is the one-off way back to 16
when a product build should be.

Measured in place after it landed: the first `make test`, a full rebuild
and run, 28.9 s, 671 passed; then with a comment line inserted at the top
of `outcome.rs` and removed again, `cargo build --release` 0.8 s and
`make test` 6.5 s and 8.6 s on two successive edits (the run itself is
~6.5 s of that), against ~12 s and ~173 s before; `make lint` clean in
2.9 s; `make app` BUILD SUCCEEDED; the built app launched on its own port
with an empty parity log, published 77 tools, and answered `new_project`
and `get_project` through the core, and the argument gate refused a
stranger key by name. The cold build is unchanged. The expectation written
above the table before the change (first run 40–50 s, then ~9 s and
1–5 s) held, and the first run was faster than expected.

---

## What is left, in order

1. **§4** whenever there is a person at the machine; it is the only list here
   that cannot be closed by writing code.
2. **§3** is consulted, not done.
3. **§5** is a decision, and the user's.
4. **§6** landed 2026-09-19, committed as `2d69fa4`.
