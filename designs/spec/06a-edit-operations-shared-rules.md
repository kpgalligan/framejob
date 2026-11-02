# 6a Edit operations — the rules every op shares

The clip ops are §6b; the action, track, marker, canvas and media ops, and the op table's two halves, are §6c.

All ops take clip/track/marker *ids*. Caller-supplied timeline tick arguments
are snapped to the document's frame grid before placement or storage, usually
to the nearest frame; `add_transition.duration` instead floors a positive
overlap request to whole frames in both modes. A negative project position
may snap and then clamp to zero; negative clip-relative starts and lengths
follow their op's checks. Source positions and measured media durations stay
in source ticks, and audio envelopes keep sample precision. The tick values
a PATCH carries are also snapped — a motion
preset's two edge durations and its `during` period, and a text animation's
`in` and `out` — which the core snaps after the range checks, so a refusal
names the number the caller sent.

An optional op argument may be omitted; this alone does not make JSON `null`
valid. `add_transition.ripple`, `paste_attributes.skip_missing`, both
`with_clips` arguments, `set_canvas.rescale_clips` and the `alone` of
`trim_start`, `trim_end` and `roll` are plain booleans:
omission means `false`, while `null` is a decode error. Every other optional
core enum field is `Option<T>` and decodes absence and null alike. The
separate `scope` envelope key accepts absence or null; a present value must
be a nest id. The app's MCP schemas may apply stricter present-value rules
for transition arguments (§7.9).

**A linked pair moves as one in time** (format 28, §11 AU-90…AU-96). Detach Audio's
picture and sound name each other in `clips[].linked`, and every placement op takes a clip's
partner on an UNLOCKED track with it — locks win over links everywhere:

- `move_clip`, `split`, `duplicate`, `nest` and `ripple_delete` act on the named clips and their
  partners. A move moves the pair by ONE delta, clamped so no clip of the pair starts before 0
  (a sound lead is kept), and the track delta is anchored on and applied to the NAMED clips only:
  a partner keeps its own track, so a sound half dragged to a track of its own goes alone.
- `delete` takes a picture's sound with it, but a linked SOUND half (its picture off) named alone
  is deleted alone and its picture stays, silent. `ripple_delete` takes both either way.
- A timeline-wide shift — the ripples, `close_gap`, `insert_time`, `retime_range`,
  `add_transition`'s ripple form —
  moves each moved clip's partner too, whatever its own start, and refuses, nothing moved, when
  that would put a partner before 0: "clip S would start before 0: it leads its linked clip P by
  N ticks".
- A split pairs its halves (§6b `split`); a copy (`duplicate`, `paste`, `unnest`) re-pairs through
  its fresh ids and clears a link whose partner was not copied.
- `trim_start`, `trim_end` and `roll` carry the same `to` to a partner whose same edge coincides
  unless `alone` is true — the J- and L-cut; `slip` slips both; speed, direction and speed-action
  edits on a linked clip are refused until `attach_audio` merges the pair (§6b).
- Whatever an op leaves one-sided (half a pair deleted, nested or overwritten) is cleared before
  its result is compared or stored, so no op writes a one-sided link.

**How to read a "refuses" in §6b and §6c.** An op the core understood answers one of
three ways (§5.5): it applies, it is an **identity**, or a rule **refuses**
it and hands back that rule's own sentence. The rows of §6b and §6c name the RULE,
which is what a reader needs — a row that says an op refuses on an empty
selection or when nothing changes is naming an identity, which carries no
sentence, and every other "refuses" is a rule that either speaks already or
is a candidate to. §5.5 says where the one list of the ones that speak is
kept. Either way the project is exactly as it was and no undo step is made,
and the UI beeps or animates back; "error" = `Err`, the request itself could
not be read.

**Every op that takes a caller-authored PATCH reads it the one way** (§5.2):
a nested object MERGES key by key at every depth, a key set to `null` CLEARS
it, and an array REPLACES its whole list. The core is the one validator of
what a patch may carry — an unknown key, a value of the wrong JSON kind or a
misspelt variant at any depth is an error naming the dotted path with array
indices and the value sent, the project is untouched and no undo step is
made. The agent door forwards the caller's own object unread (§7.9), so an
agent and the app's own writers meet exactly the same rules.

**The envelope's one non-argument key: `scope?: u32`.** A nest id. Absent
(or `null` — the envelope reads the two the same way), every id in the op
resolves against the timeline, as it always did. Present, every id in the
op — clips, tracks, actions — resolves against that nest's own tracks and
clips, and the op itself is unchanged: `Project::apply` builds a **view
project** out of the nest (`tracks` / `clips` the nest's, the canvas SIZE
its frozen pair, the rate / background / switches and the `media[]` and
`next_id` the parent's, no markers, and the nest's own row kept in
`nests[]` with its contents emptied so ids resolve without being counted
twice), applies the op to it, and merges `tracks`, `clips`, `next_id`,
`media` and `nests` back. So `Project::clip` keeps its one meaning, no op
gained a nest-aware code path, undo is still one stack of parent handles,
and `rc_op_names` gains no name — a scope is an envelope key, not an op.
Times inside a scope are the nest's own, measured from its zero; a nest has
no speed, so `t − nest_clip.start` is the whole mapping.

**Eleven ops are an error with a scope**, each naming itself and the nest
(`add_marker has no meaning inside nest 4`): `add_marker`, `set_marker`,
`remove_marker` — a nest has no `markers[]`, and the timeline's are project
time and chapter points on the file; `set_canvas` — a nest's size is frozen
at the size the parent had when it was made (§5.2), deliberately, and the
rest of a canvas is the document's; and `add_media`, `relink_media`,
`remove_media`, `set_media_color`, `set_media_speech` — a nest references the parent's `media[]` in the parent's
one id space, so a media edit inside a scope is a media edit on the
document wearing a scope; `add_adjustment_clip` — an adjustment clip
grades what is behind it at the top level only (§11 GR-6); and `keep_range` —
it keeps a range of the document's timeline, applied only to a derived
document (§11 CJ-50). An unknown
`scope` is `no nest with id N`, answered ahead of everything else; a `scope` that is not a nest id is
`scope must be a nest id, not <value>`. Everything else works inside a nest
as it works on the timeline, `nest` and `unnest` included: nesting the
whole of a scope mints a fresh id and puts the new nest clip INSIDE the
scoped nest, which is a legal extra level and not a cycle.

**A scope widens §5.5's invalid-argument answer and nothing else.** Two
invariants are invisible from inside a view — the caps count the whole
document (§5.6) and the nesting depth is measured from the timeline down —
so both are checked once, at the end, on the MERGED parent. *An op may
succeed against the view and the scoped apply still return `Err`*: `too
many clips`, `too many tracks`, `nests are more than 8 deep at nest N`.
`core/src/scope.rs`'s module doc is the full contract.
