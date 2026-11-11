# Spec §11 — decisions: Graphics, Rename, Delete and Restore Graphic onward (road map 10)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the G- series of [`graphics.md`](graphics.md), so a citation never has to say which
file. This file holds G-30…G-32. G-33 is in [`graphics-4.md`](graphics-4.md). It is new because
`graphics.md` had passed the spec's ~500-line split rule (#548, 2026-11-11); the entries moved here
unchanged, and an "above" or "below" in one may now point into a sibling file.

- **G-30 — File ▸ Rename Graphic…, Delete Graphic… and Restore Graphic
  Version… are one small sheet over G-27..G-29's three bodies; a refusal
  is the body's own sentence, shown in the sheet** (issue #103,
  2026-10-04, issue batch B84, phase 2).
  (a) **The items.** In the File menu, in a separator group of their own
  straight under Add Image to Graphics…, in the order Rename Graphic…,
  Delete Graphic…, Restore Graphic Version…, with no key equivalents (the
  caption items' reason, §9). Each is a nil-target selector the editor
  implements: `renameGraphic(_:)`, `deleteGraphic(_:)`,
  `restoreGraphicVersion(_:)`.
  (b) **The one sheet** (`GraphicFileSheetController`). Its title is the
  item's without the "…"; under it a hint ((c)), a `Graphic:` pop-up of
  the project's graphics, Cancel, and a button reading Rename, Delete or
  Restore. Rename adds a `New name:` field, filled with the chosen
  graphic's name, and the footnote `lowercase letters, digits and -`; its
  button is dimmed until the name is filled in and differs from the
  chosen one. Restore adds one line under the pop-up, `1 version kept` or
  `<n> versions kept`, and lists no version: it restores the newest
  (G-29 (d)), and there is no history browser. Rename and Delete list the
  folder's modules by name. Restore lists every name that has a kept
  text, a deleted module (G-27 (f)) reading `<name> (deleted)` — which is
  how a delete is taken back.
  (c) **The hints, word for word.** Rename: `Every clip that uses the
  graphic follows its new name, on the timeline and inside nests. Undo
  renames it back when a clip uses it; a graphic no clip uses is renamed
  back by renaming it again.` Delete: `A graphic that clips still use
  cannot be deleted. Its code is kept with its earlier versions, so
  Restore Graphic Version… brings it back. Deleting is not an Undo step.`
  Restore: `Puts back the newest kept version of the graphic's code. If
  the graphic has code now, that code is kept in its place, so restoring
  again returns to where you were. Restoring is not an Undo step.` They
  promise only what holds: a rename of a graphic no clip uses makes no
  edit (G-28 (b)) and so no undo step, and a restored DELETED graphic
  replaced nothing, so nothing is kept in its place.
  (d) **Where a sheet opens.** Rename and Restore open on the graphic of
  the selected clip when exactly one clip is selected and its graphic is
  a row — a deleted one included, which is how a clip showing the error
  card gets its code back; otherwise on the first row by name. Delete
  always opens on the first: a selected clip's graphic is in use and
  could not be deleted.
  (e) **A refusal shows in the sheet, which stays up.** The body's
  sentence is shown word for word, with a beep, in a label at the foot of
  the sheet's content, so the person can fix the name or pick another
  graphic; no alert sheet is put up. It is the sentence an agent reads,
  the hint `(set_graphic {name})` included (the owner's choice,
  2026-10-04). The sheet owns two guards, both about the CALL (D2-1): a
  new name that is empty or unchanged (the dimmed button), and an item
  with nothing to list ((f)). The name goes to the body as typed, neither
  trimmed nor lowercased. **There is no second confirmation**: the
  sheet's Delete button is the confirmation, because the code is kept and
  Restore brings it back (G-27 (c)). After a success the sheet closes and
  says nothing; a restored text that does not compile shows the error
  card as any broken graphic does (G-8).
  (f) **When an item is greyed.** Rename and Delete in a project whose
  folder holds no module; Restore when no name has a kept text; Rename
  also while a nest is open (G-28 (g)); all three before the document's
  graphics store exists, and while a sheet is attached.
  (g) **One implementation.** Each act is one call of the body the tool
  calls — `ProjectDocument.renameGraphic(named:to:apply:)`, its `apply`
  the document's `performGroupedEdit("Rename Graphic", …)`,
  `deleteGraphic(named:)`, `restoreGraphic(named:revision:)` with no
  revision — and the sheet reaches no store writer, no op and no undo
  registration of its own.
  **Risk accepted:** a person reads a tool's hint in a refusal. A second
  wording for people would be a second spelling of every sentence to keep
  in step with the first.
- **G-31 — The standard library measures a path: `getLength`,
  `getPointAtLength` and `evolvePath`, in JavaScript, a curve as 64
  chords, a draw-on dashed by the longest subpath** (issue #103,
  2026-10-05, issue batch B85, phase 1).
  (a) **The names.** `getLength(d)` answers a number, `getPointAtLength(d,
  length)` answers `{x, y, angle}` and `evolvePath(progress, d)` answers
  `{strokeDasharray, strokeDashoffset}`. The three names and their
  argument orders are Remotion's, which an agent already knows, as the
  rest of the library's are (G-2); none of its code, nor any other
  library's, is carried over. The heading comes with the point, in
  degrees as SVG's `rotate()` takes them, rather than from a fourth
  function.
  (b) **What is measured.** `d` is read as `String(d)`: `M L H V C S Q T A
  Z` in both cases, implicit repeats (the pairs after an `M` are `L`),
  SVG's number grammar (`.5.5`, `1e2`, `-1-1`, commas optional) and arc
  flags written without separators (`a50 50 0 01100 0`). `S` and `T`
  reflect the previous control point only after a curve of their own
  family, else the current point. An arc with a zero radius is a line;
  radii too small for the chord are scaled up, and the centre
  conversion's radicand is clamped at 0, so a length is never NaN. A
  SUBPATH begins at each `M`/`m` and at the first drawing command after a
  `Z`/`z`, from that subpath's start point. `getLength` is the sum over
  every subpath, a `Z` adding its closing line and a move adding nothing;
  an empty string is 0.
  (c) **The point and the heading.** `length` is `Number(length)`, NaN
  read as 0, clamped to 0…total. The point is on the true curve, not on a
  chord. `angle` is `Math.atan2(dy, dx) * 180 / Math.PI` of the curve's
  own derivative there (y down); at a joint it is the segment ending
  there, at 0 the first drawn segment's start, and a zero-length segment
  gives no heading. Where the derivative is (0, 0) on a segment of
  non-zero length the heading is the tangent's LIMIT: at the segment's
  start, the direction from the start to the first later control point
  (or end) that differs from it; at its end, the direction to the end
  from the last earlier control point (or start) that differs from it; at
  an interior parameter (a cubic's cusp), the direction of the chord the
  point lies on. A path with no drawn length answers its last `M` point
  (or 0, 0) with `angle: 0`.
  (d) **The draw-on.** `progress` is `Number(progress)`, NaN read as 0,
  clamped to 0…1. With `D = L × 1.001`, `L` being the length of the
  LONGEST subpath, the answer is `{strokeDasharray: "D D",
  strokeDashoffset: D × (1 − progress)}`, and `{strokeDasharray: "none",
  strokeDashoffset: 0}` when `L` is 0. The pad is there so a closed
  outline always closes at progress 1 although the measure is a
  flattening; mid-way the tip is at most 0.1 % ahead. The longest subpath
  and not the total, because the rasterizer restarts the dash on each
  subpath (`tiny-skia-path` 0.12.0's `dash.rs` walks the contours, each
  from the pattern's first interval): a dash as long as the total would
  draw a short subpath too slowly, and no single dash can draw the
  subpaths one after another. So every subpath draws from its own start
  at once and at the same speed, the longest ending at progress 1; pieces
  drawn in turn are one `<path>` each, which the reference says.
  (e) **The two errors**, thrown as `Error`s, `<fn>` being the function
  the module called: `<fn>: cannot parse the path at character <i>:
  "<d.slice(i, i + 12)>"` — an unknown command, a path that does not
  begin with `M`/`m`, a number where none can be read, an arc flag that
  is not `0` or `1`, a number that is not finite, `<i>` the 0-based index
  — and `<fn>: the path ends inside a command`, when the data ran out
  while a command still wanted numbers. A path that cannot be read is
  never a silent zero.
  **Not finite is a refusal, not an answer**: no helper ever answers
  `Infinity` or NaN, and a path that would make one do so is refused in
  the first sentence. Five checks in `path.js` hold it, each with a case
  in `path.test.js`'s row `T8 a number that is not finite`. At the
  number's own character: a number that reads as `Infinity` (`1e999`). At
  the character where its command, or its repeat of one, begins: a move
  to a point that is not finite (`M 1e308 0 m 1e308 0`); an arc whose
  centre form is not, which is radii whose squares overflow (`A 1e300
  1e300 …`) or end points so close that theirs underflow (`M 0 0 A 1 1 0
  0 1 1e-200 0`) — unchecked, each was answered as a path with nothing
  drawn, the silent zero; a segment that takes the running length out of
  a double's range, which is a point past the largest number or a chord
  whose square is (`H 1e200`, or the diagonal that closes `M 0 0 H 1.2e154
  V 1.2e154 Z`, while the same path at 1e153 measures); and, asked of
  `getPointAtLength` alone, a point that is not finite between two
  measured points that are — a curve one step under the largest double,
  whose length `getLength` answers. The length is checked padded, so
  `evolvePath`'s dash is finite whenever the length is. The sentence says
  "cannot parse" of a number that was read: one sentence for every path
  the helpers will not answer was preferred to a third.
  (f) **The tolerance.** A path is measured as its flattening: a line
  exactly, each `C S Q T` as 64 chords at uniform parameter, each arc as
  chords of at most π/128 rad of sweep. That is within 0.01 % (1e-4
  relative) on the reference shapes, whose lengths are closed forms: a
  circle of radius 500 (2π·500), the ellipse of radii 200 and 100
  (4a·E(e), 968.8448220547675) plain and rotated 30°, the parabola
  y = x² from −1 to 1 (√5 + asinh(2)/2) as a `Q` and as a `C`, and the
  cusp x = t², y = t³ ((13√13 − 8)/27). Exact formulas exist only for
  some curves and would cost much more code.
  (g) **The memo.** The last paths measured are kept per engine, keyed by
  the `d` string. A path's cost is its chord count plus `d.length`;
  before an insert that would take the memo past 32 paths or past a total
  cost of 50,000 the memo is cleared whole, and the new path is then kept
  — so a path over the cost bound on its own is kept alone until the next
  insert, and its own calls in a render do not re-measure it. An engine's
  heap is 64 MB and outlives a render (G-5's limit); the cost bound keeps
  what the memo holds to a few MB of it, except a single path over the
  bound, which is held whole until the next insert and is limited only by
  what one render's budget can measure. It breaks no G-5 purity: an
  answer never depends on what the memo holds, and the memo's state is
  reachable by no module — the Map sits in a closure, as `noise.js`'s
  permutation tables do, because the library's `__` functions and
  top-level `const`s are visible to a module.
  (h) **Pure JavaScript, not a host function.** `graphic/src/path.js`,
  evaluated as a script after `stdlib.js` and `noise.js` and before the
  sandbox, uses only `Math`, `Map`, `Float64Array`, `String`, `Number`
  and `Error`: nothing crosses into Rust, and nothing the sandbox removes
  is used. A path the memo still holds costs a lookup per call; paths
  that together pass a bound are measured again in turn; a path rebuilt
  every frame is re-measured, and a fresh path of 200 cubic segments with
  1,000 points taken along it stays inside the preview's 250 ms
  (`graphic/tests/path.rs` prints the figure).
  **Risks accepted:** a curve tighter than the references can exceed the
  tolerance, and the pad covers 0.1 %. No row measures the memo's held
  bytes, because reading them would make the memo's state visible to a
  module, which is the G-5 hole the closure prevents.
- **G-32 — `paste_attributes` takes a fifth group, `graphic`, that copies
  a clip's props whole onto clips drawn by the same module; it is never in
  the default set; `skip_missing` skips what cannot take a named group;
  Edit ▸ Paste Graphic Properties is the person's door** (issue #103,
  2026-10-05, issue batch B85, phase 2). It amends G-10's sentence "Nor is
  `graphic` a `paste_attributes` group": `graphic` is now a group a caller
  may NAME, and G-10's sentence still describes a paste that names none.
  "The owner's choice N" below is one of this phase's seven, each accepted
  as recommended (2026-10-05); batch B85's own choice 7 is named as such.
  (a) **No `groups`: unchanged.** With `groups` absent the op copies the
  four groups in `patch::GROUPS` (`video`, `audio`, `text`, `shape`), each
  where both sides have it, exactly as before this entry. `graphic` is
  never in that set, and `skip_missing` changes nothing there: with no
  `groups`, the answer with the flag is the answer without it. **Why
  `graphic` is not in the default set** (batch B85's choice 7, answered
  (c) by the owner on 2026-10-04): a graphic's props hold its WORDS as
  well as its look, and ⌥⌘V has no picker, so a default that carried them
  would overwrite one lower third's name with another's on a paste that
  was asked for the position and the opacity.
  (b) **Who has it, who can take it.** A side HAS `graphic` when its
  source is `Source::Graphic` and `clip.graphic` is set, which is
  `set_graphic`'s test. A target can TAKE it when it has it and its
  `graphic.name` equals the payload clip's. The payload clip is the
  EARLIEST (then the front-most, then the lower id), as for every group.
  (c) **Named, `skip_missing` false (the default): all or nothing**, as
  the four groups are. The exact errors: `payload clip has no graphic
  properties`; `clip {id} has no graphic properties`; and `clip {id} is
  drawn by "{its name}" and the payload clip by "{payload's name}";
  graphic props are pasted only between clips of one module` (the owner's
  choice 6). The four existing groups keep their sentences. Targets are
  visited in `selected_clips`' order and the first error met is the
  answer.
  (d) **Named, `skip_missing` true.** A named group the payload clip
  lacks is dropped, and a target that lacks a named group (for `graphic`:
  one that cannot take it) is skipped for that group. A missing group is
  never an error, and the answer is an identity when nothing changed. The
  flag applies to all five groups, so an agent can ask for exactly what
  the menu item does (the owner's choice 5).
  (e) **What travels: `props`, whole.** The target keeps `name`, `width`,
  `height`, `in`, `length` and everything outside `graphic`. A target key
  the payload lacks is removed with `shift_remove`; a key both have keeps
  its slot (`insert`); new keys are appended in the payload's order —
  `model_graphic.rs`'s insert-and-`shift_remove` rule, so the written
  text moves no key it did not have to. (Amended by G-34 (d): a target
  key that an action on the target names is kept.)
  (f) **When the copied map is read.** The map is checked for shape only,
  once, the first time a target TAKES it, before anything is written to
  that target: `model_graphic::check_props(_, None)`, its `null`s
  dropped, then `check_count`, each in its own sentence, unprefixed. No
  schema is read and no colour is normalised (the core has no module to
  ask, G-4). **A paste in which no target takes `graphic` never reads
  the map**: with `skip_missing` it is an identity however the map is
  shaped, and without it it is (c)'s error, not the map's. A malformed
  map and at least one target that takes it is the map's error in both
  modes, and nothing changes. So the menu item BEEPS and shows no alert
  whenever no selected clip takes the props, however the copied map is
  shaped, and a malformed map onto a matching clip is the core's sentence
  in an alert (the owner's choice 7). **Why**: the owner's choice 3
  ("choosing it beeps and changes nothing … when nothing matches") then
  holds without exception, and the four groups already check a copied
  group only after it has landed on a target (`normalise_and_check_group`
  follows `copy_group`).
  A malformed map can reach the MENU only from a project file written by
  hand or from an agent's `paste` of a hand-written payload, neither of
  which checks a graphic's props for shape (`validate` in
  `model_query.rs` reads only its name, `normalise_and_check_pasted` only
  the four groups); an agent can also hand one to the tool directly.
  (g) **The door.** Edit ▸ Paste Graphic Properties, directly under Paste
  Attributes, with no key equivalent (the owner's choices 1 and 2). It
  sends ONE op — `paste_attributes` over the selection with `groups:
  ["graphic"]` and `skip_missing: true` — as the undo step "Paste Graphic
  Properties", and interprets nothing about the payload: an identity is
  the edit path's beep, and an error is its alert sheet with the core's
  sentence and no undo step. It is enabled when Frame Job clips are on the
  clipboard and at least one selected clip is a graphic (the owner's
  choice 3); greying it exactly would mean reading the clipboard's bytes
  every time a menu opens. When several clips were copied the props come
  from the earliest, and if that clip is not a graphic nothing is pasted
  (the owner's choice 4). An agent's step is still named "Paste
  Attributes": it calls the same tool with the group named.
  (h) **A paste-only enum, not a fifth `patch::Group`.** `patch::Group`
  is the four groups a PATCH can address, and it is matched exhaustively
  where a patch is read: `patch.rs` (`name`, `subject`, `template`),
  `edit_props.rs` (`normalise_and_check_group`, `check_group`,
  `patch_clips`) and `edit_action.rs` (`check_end_patch`'s probe). A
  `Graphic` variant there would need a template that means nothing — a
  graphic's keys are its module's, not the vocabulary's — and would make
  `graphic` look like a group an action's `end` could carry, which G-10
  refuses. So `paste_attributes` takes its own `PasteGroup` (the four and
  `Graphic`), whose first four map onto `patch::Group` and still go
  through `normalise_and_check_group` after each copy.
  **Not done, and why:** the props are not checked against the module's
  schema and their colours are not normalised, because the op carries no
  schema and the payload's props were stored through one already; a
  subset of props, or the look without the words, would need the module's
  schema sent with the edit. **Risks accepted:** a target written before
  its module dropped a key receives the payload's keys as they are,
  stale ones included, as `set_graphic` without a schema would store
  them; the item can be enabled when choosing it only beeps ((g)).
