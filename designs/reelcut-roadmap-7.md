# Reelcut — road map 7: deepening

**Status: D1 IN PROGRESS — D1·1 built (§2.1); D1·2 to D1·6 not started.**

Road maps 2 to 6 each added something a person using the app can see. This
one does not. A **deepening** takes knowledge that is spread across callers
(a check repeated at every door, a rule the rulebook has to warn people to
repeat) and moves it behind one module's interface. The callers shrink, and
the tests move to that interface. Success means a person editing in the app
notices nothing, and an agent calling over MCP gets one set of rules with
one wording.

Each candidate is designed in a grilling session with the user. Its spec is
a GitHub issue labelled `spec`, and its tickets are issues labelled
`ready-for-agent` (`docs/agents/issue-tracker.md`). An issue is a snapshot of
the design conversation. This document holds what outlasts one: the rules
the series inherits (§0), each candidate's plan in the order it was built
(§1), and the record (§2).

---

## 0. Rules the series inherits

The vocabulary is the codebase-design skill's, used exactly: **module**,
**interface** (everything a caller must know, including its error modes, not
only the signature), **depth**, **seam**, **adapter**, **leverage**,
**locality**. `CONTEXT.md` holds the domain words (Op, Patch). Four rules
decide what a deepening is allowed to be:

- **Deep module.** A lot of behaviour behind a small interface. The deepest
  module in Reelcut is the core behind `rc_project_apply`: one JSON op goes
  in, and a project, "nothing changed" or a refusal comes out. A deepening
  moves knowledge toward an interface like that. It never adds a second,
  shallower way in beside it.
- **Seam.** The place where an interface lives. The series uses the seams
  that already exist: the op envelope through `rc_project_apply`, the MCP
  tools, and the FFI's three files in lockstep. It adds a new one only when
  something actually varies across it. One adapter is a hypothetical seam;
  two make a real one.
- **The deletion test.** Imagine deleting the module. If the complexity
  vanishes, the module was a pass-through. If it reappears across many
  callers, the module was earning its keep. A deepening is measured by what
  it lets the callers DELETE, and the record states that in lines.
- **The interface is the test surface.** A test crosses the seam a caller
  crosses. Rust tests go through the FFI (`core/tests/*.rs`), and proof
  scripts go through MCP against the built app (`tools/proof/`). A test that
  has to look past the interface means the module is the wrong shape. Tests
  are replaced, not layered: when the shallow checks go, a test that pinned
  their wording moves to the deep module's wording, with the reason written
  in the test.

The project's standing rules apply unchanged, and this series leans on four
of them:

- **Nothing in spec §11 is re-litigated**, and neither is a spec issue's
  Implementation Decisions section. Anything learned while building goes in
  §2 here, in a rulebook or in `CONTEXT.md`. It never goes back into the
  issue.
- **The prefactor lands first.** The first ticket of a candidate makes the
  deep module able to say what the shallow callers used to say. That turns
  every later ticket into a deletion.
- **Every ticket passes the gate for what it touched.** For the core that is
  `make test`, `make lint` and `cargo fmt --check`. For the app it is also
  `make typecheck` at 0 errors and the same 4 warnings, `make app`, an empty
  startup parity log and every proof green. A new proof claim is made to
  fail on purpose once, and its mutants are counted.
- **Size.** A file at the ~600-line cap gives something up before it takes
  anything on, and a new file is capped at 400 lines. A ticket that only
  deletes is a ticket that pays down `designs/reelcut-remaining.md` §3.

---

## 1. D1 — hand the core the caller's own patch

**Spec:** kpgalligan/reelcut#1.

**The problem.** An agent writing a property patch by hand over MCP could
make a mistake that got corrected or dropped instead of refused. The agent
door decoded the caller's object through the same lenient Swift types the
app uses to read what the core wrote, re-encoded the result and sent that
on. A misspelt enum became the vocabulary's first case, a wrong-typed
optional became a clear, and an incomplete filter entry was completed from
defaults. About four hundred lines of hand checks in the Swift handlers made
up for it, one door at a time. Two of those doors also disagreed with the
core about what a nested object means (replace against merge).

**The shape.** The seam is the existing one: every op reaches the core as
JSON through `rc_project_apply`. The agent door forwards the caller's object
verbatim, and the core becomes the one validator. A refusal names the dotted
path (with array indices) and the offending value, and leaves the project
untouched. A valid patch merges key by key at every depth: `null` clears a
key and an array replaces its list. The Swift checks, allow-lists and hand
readers are deleted. The rule "check enums and types by hand at every door"
becomes "lenient decoding is for what the core wrote; nothing a caller wrote
is decoded through it". There is no new export, no new tool and no format
bump. Agents will see two behaviour changes: a nested object merges where it
used to replace, and a colour must be four numbers where three were once
accepted.

**The tickets, in blocking order.** #2 → #3 → #4 → (#5 and #6, in either
order) → #7.

| Ticket | Title | Blocked by |
|---|---|---|
| kpgalligan/reelcut#2 | D1·1: the core names the path and the value in every patch refusal | — |
| kpgalligan/reelcut#3 | D1·2: the core changes what a patch may carry: filters, ticks, regions, end states | #2 |
| kpgalligan/reelcut#4 | D1·3: set_video forwards the caller's patch, and the patch-door proof is born | #3 |
| kpgalligan/reelcut#5 | D1·4: the remaining property doors forward raw; colours are four numbers | #4 |
| kpgalligan/reelcut#6 | D1·5: the end-state and region doors forward raw | #4 |
| kpgalligan/reelcut#7 | D1·6: contract and record: delete the launder, write the rule, fail the proof twice | #5, #6 |

D1·1 and D1·2 are core-only. Each proves its claims through the FFI. D1·3
creates the MCP proof that every later door ticket adds a section to. D1·6
is the contract step: the shared launder machinery goes, the rule is written
where the warning was, the proof is made to fail twice (once with the
launder restored at one door, once with the core's key walk disabled), and
the record below is closed with the lines deleted.

**Out of scope, and named so it is not rediscovered.** Deriving the catalog,
the typed factories and the parity check from the core's op table is a
separate candidate. So is a refusal that carries its reason for an op that
returns nothing (today an identity and a refusal look the same). The same
goes for the duplicated recipe key list and the other duplicates the
architecture review listed. What the core wrote (the project, the plan, the
recipe, export settings) stays leniently decoded.

---

## 2. D1 — the record

One entry per ticket, written when it lands.

### 2.1 D1·1 — the core names the path and the value (kpgalligan/reelcut#2)

**Commits.** `ebab0db` (the ticket) and `b02e4df` (what its review found,
below).

**What landed.** Core and documents only. No Swift changed, so an agent does
not see any of this yet: the agent door still decodes before the core does,
until D1·3.

- **The walk checks keys and kinds, with indices.** `edit_props.rs`'s
  `check_keys` builds the path per element, so a misspelt key on the second
  filter is `unknown key "filters[1].kindd" in a video patch`, where it used
  to say `filters.kindd`. At every step it also compares the value's JSON
  kind against the group's template. It refuses
  `bad value at "<path>" in a <group> patch: expected <kind>, not <value>`,
  where the kind is an object, a list, a string, a number, a whole number or
  true or false.
- **Why the kind check matters.** The review found that serde READS two
  wrong kinds. A struct deserializes from a JSON array of its fields in
  declaration order, so `{"duck": [0.9, 300000, 600000]}` stored a duck.
  A unit variant deserializes from a one-key object, so
  `{"blend": {"multiply": null}}` stored a blend. Both are refused now. The
  check also means a type refusal speaks the schema's words, not
  serde's `expected struct Duck`. A `null` always passes the walk, because
  in a patch it clears.
- **The read names its path.** `merge_group` is now typed
  (`merge_group<T>(base: &T, patch, group) -> Result<T, String>`): the
  object check, the walk, the deep merge, then a `serde_path_to_error` read.
  The read catches what only the type knows: a misspelt variant, a `null` a
  required field cannot take, a colour of the wrong length. It refuses them
  as ``bad value at "<path>" in a <group> patch: <serde's sentence>``, whose
  sentence names the value and, for a variant, what the vocabulary allows:
  ``bad value at "filters[1].kind" in a video patch: unknown variant `glw`, expected one of `blur`, …``.
  The path runs into the MERGED group, which gives the same path as the
  patch's. Its six callers (the four `set_*` arms, `add_text_clip` and
  `add_shape_clip`) each dropped their own `from_value` and their "… patch
  does not match the schema" message. A new clip's patch is therefore
  refused in exactly the words `set_text` / `set_shape` use.
- **The article is right:** "an audio patch", no longer "a audio patch".
  `set_clip` is unchanged, because it already named the key and the value
  (`"name" in a clip patch must be a string or null, not 5`).
- **The dependency.** `serde_path_to_error` 0.1.20 (MIT OR Apache-2.0). Its
  own dependencies, `serde_core` and `itoa`, were already in the lock file.
  It is the core's FOURTH direct dependency, not its third as the ticket
  said: `tiny_http` was already there. `core/CLAUDE.md`'s new
  **Dependencies** rule says why each of the four is there.

**Tests.** A new file, `core/tests/patch_door.rs`, holds six table tests
through the FFI. Every refusal goes through `Handle::errors`, which is the
"project unchanged" claim at this seam: NULL with a message means no new
project and no undo step, and a correction or a clear would come back as a
new handle and fail the test. (The first commit also compared the handle's
JSON before and after. A handle is immutable, so that could never fail, and
the review had it removed.) Each message is compared exactly, or by its path
prefix plus serde's value. The cases covered:

- an unknown key with an index (`filters[1]`, `obscure[1]`,
  `gradient.stops[1]`) or at depth (`motion.during`, `compressor`,
  `animation`), at every group;
- a misspelt variant at every group that has one (`filters[1].kind`,
  `blend`, `motion.in.kind`, `obscure[0].kind`, `align`, `animation.kind`,
  shape `kind`, `gradient.kind`);
- a wrong kind where a nested object belongs: shadow, duck, outline and
  stroke. Each is STORED on the fixture, so a clear would have been a real
  edit. A clip name that is not a string is covered too;
- a wrong kind inside an object or a list (`filters[0].amount`,
  `duck.attack` as a fraction, `outline.color[1]`, `gradient.stops[1].at`),
  and a `null` for the required `crop`;
- a list or an object where the schema has another kind (duck, a filter
  entry, crop, blend, animation, stroke);
- the `text` and `shape` of a new clip.

`audio` has no list and no enum, and `set_clip`'s patch is two flat strings.
"At every group" therefore means the deepest place each group's own
vocabulary has. `text` gets its index through a colour component.

Five existing tests asserted the old wording. Each now asserts the path and
says why in a comment naming this ticket: `schema_v4.rs`'s region key (and
its comment that said the path deliberately carried no index),
`schema_v5.rs`'s animation kind, `schema_v6.rs`'s blend and gradient kind
and its gradient stop key, and `schema_v8.rs`'s motion kinds.

**Measured.**

- `make test`: 627 passed, 0 failed (621 before, plus the 6 new tests).
- `make lint` and `cargo fmt --check`: clean.
- Line counts: `edit_props.rs` went from 432 to 522, `edit_clip.rs` from
  1043 to 1038, and the new `patch_door.rs` is 390.
- Mutants, all caught:
  - The walk without the index failed `patch_door` tests (4 of the final 6)
    plus the `schema_v4` and `schema_v6` key tests.
  - `serde_json::from_value` back in place of the path-tracking read failed
    3 `patch_door` tests plus the `schema_v5`, `schema_v6` and `schema_v8`
    kind tests.
  - "a audio" failed 4 `patch_door` tests.
  - The kind check disabled failed 3 `patch_door` tests; the positional
    reads came back.
  - The whole-number refinement disabled failed 1.

**The review** (standards and spec, in parallel, against the ticket and
spec #1).

Fixed:

- An array where an object belongs, and an object where an enum belongs,
  were read, not refused. This is the kind check above; the spec review
  found the array case.
- The tautological "project unchanged" comparison is gone.
- `Group::article` no longer repeats the four names.
- The test helper is `patch_op`, not `patch`: it returns an op.
- Spec §7.10's `edit_props.rs` row now names `merge_group`, mirroring
  `core/CLAUDE.md`.
- Rust type names in type refusals are gone, except in the read's
  `null`-on-a-required-field sentence (`expected struct Crop`).

Judged not real:

- *The range check after `merge_group` is repeated at six sites.* Each
  group's check has a different signature: video needs the clip's source
  size and the nest-blend check. Folding them into the read would need a
  per-group trait for no caller that needs it.
- *"patch must be a json object" appears twice.* This predates the ticket,
  and both copies are needed. `patch_clips` checks before resolving ids, so
  an empty selection still refuses a non-object. `merge_group`'s copy guards
  the two new-clip ops.
- *"Third dependency" and "every group" do not hold literally.* Both
  readings are recorded above.

**What the next tickets inherit.**

- The three sentence forms above are what D1·3's proof asserts over MCP.
- `merge_group` is the one read of a group patch. D1·2's end-state op and
  incomplete-filter refusal have the walk's path spelling to match, and the
  end-state op can reuse the kind check only against a template, since an
  end patch spans groups.
- **Range refusals are not indexed.** `props_check.rs` still spells a list
  entry as `video.filters[].amount` / `shape.gradient.stops[].at`, which
  names the field and the value but not which entry. Those refusals were not
  in this ticket's criteria, and `tools/proof/phase6_proof.py` asserts the
  `[]` spelling through the app. A ticket that wants indices there has to
  move that proof too.
- **A fraction where a tick count belongs** is refused by the walk, as serde
  already refused it. Any door that forwards raw JSON with tick values
  written as `600000.0` gets the refusal, not a rounding. D1·2's snap only
  moves whole-number ticks onto the frame grid.

**Documents.**

- Spec §6's row for the property patches now says a refusal names the path
  and the value, gives the three forms, and says a new clip's patch answers
  in the same words.
- Spec §7.10's dependency list, file tree and `edit_props.rs` row are
  updated.
- `edit.rs`'s op-table bullet says the same as spec §6.
- `core/CLAUDE.md`'s `edit_props.rs` entry names `merge_group`. Its "a patch
  of a nested object is a REPLACEMENT" was false about the core, which
  merges key by key, and now says so.

**Owed.** Nothing for this ticket.
