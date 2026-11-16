# Spec §11 — decisions: Deepening, a clip ripple closing up to its neighbour onward (road map 7)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The entries continue [`deepening.md`](deepening.md), so a citation never has to say which file. This
file holds #601, and a new decision of this kind is appended here. It is new because
[`deepening-5.md`](deepening-5.md) had reached the spec's ~500-line split rule (2026-11-11).

- **#601 — a clip ripple closes up to the neighbour that begins inside a
  removed clip, and is refused when a track it moved breaks the overlap
  rule.** (Owner, 2026-11-13: option 1 of the issue, with option 2's refusal
  kept behind it. Recorded before the code. Amends #427 (g)'s
  `ripple_delete {clips}` clause, §6a's linked-pair and #427 paragraphs and
  §6b's `ripple_delete` row.) On one track A [0, 4 s), B [3 s, 8 s), C [7 s,
  12 s), D [12 s, 20 s), each overlap a dissolve, `ripple_delete {clips:
  [B]}` shifted by B's 5 s at 8 s: C, which starts inside B, stayed at 7 s,
  and D slid to 7 s, wholly under it, stored past the rule; every range cut
  that moved that track was then refused naming C and D. Driven in the app
  before the fix (`refusal_proof.py` 12b–12e, red on Debug built from
  aa5a1512).
  (a) Where a removed span ends. The spans are still the union of the
  removed clips' spans, each one's linked partner included (AU-91), closed
  right to left. A merged span now ends at the earliest start of a
  surviving clip that begins strictly inside a removed clip of that span on
  the removed clip's own track, when that track is unlocked; with no such
  clip it ends at the removed clips' end, as before. Everything on an
  unlocked track starting at or after that end shifts left by the span's new
  length, so in the example the span is [3 s, 7 s): C to 3 s, D to 8 s, every
  unlocked track by 4 s. A clip on another track that began inside the old
  span but at or after the new end moves with it; one that straddles the
  new end stays (rule 3 of `edit_time.rs`, unchanged).
  (b) One amount everywhere; the first start wins. When the removed clips
  of one merged span would stop at different places — a linked pair whose
  picture dissolves into its neighbour at 7 s while its sound butts the next
  sound at 8 s, or clips selected on two tracks — the span ends at the
  earliest. The later end is exactly the stored overlap this issue is about
  (the earlier neighbour stays, the clip after it slides under it), so it
  could only be refused, and refusing "ripple-delete a detached pair with a
  dissolve" is the everyday refusal the owner turned down. The earlier end
  keeps every track in step and leaves a visible gap on the track that had
  more to close (in the pair above, the next sound lands at 4 s, one second
  after the hole's start: the second its picture's dissolve covers), which
  `close_gap` closes.
  (c) A removed clip on a locked track pulls nothing back: its neighbour
  cannot move, so nothing can slide under it, and the other tracks close its
  full length as before.
  (d) Unchanged: the span's start (C lands on A by the overlap A had with
  B and keeps its own stored transition; a clip with none gains the minted
  dissolve, as any ripple that brings two clips together does); locked
  tracks never move; markers stay; a partner moves with its clip whatever
  its start; the before-0 refusal comes first.
  (e) The backstop. After every shift, each track holding a clip whose
  start changed is judged whole by THE overlap rule, in the project's track
  order, and the first violation refuses the op, nothing removed, in the
  rule's own sentence (`check_overlap_rule`'s: the over-half pair, two
  neighbours on one side, an adjustment clip in an overlap). A track the
  ripple did not move is not judged, as `close_gap` does not (#427 (b)), so
  removing a clip from a track that already breaks the rule elsewhere still
  applies when nothing on it moves; a moved track already past the limit
  refuses, as #427 (c) has it for the range cuts.
  (f) What the backstop refuses that used to be stored: another track's
  clip sliding more than half under a clip that straddles the span's end; a
  multi-track selection of unequal lengths with material between (track 1
  B [3 s, 5 s), K [5 s, 20 s), L [20 s, 30 s), track 2 X [3 s, 20 s):
  removing B and X slid L under K); and a successor too short for the
  overlap it inherits at the span's start (A [0, 4 s), B [3 s, 8 s), C
  [7.5 s, 9 s): C would sit under A by 1 s, over its 0.75 s). Refused, never
  repaired (#427 (d)): no transition is shortened and nothing is moved
  further.
  (g) Where a person meets it: ⌘⌫ (Edit ▸ Ripple Delete) with clips
  selected, at the inspector's foot; the tool's error "Ripple Delete was
  refused at ripple_delete: …". The op's arguments do not change, and
  nothing persisted does: no format bump.
  Proofs: `core/tests/ripple_close_up.rs` R1–R9 with hand mutants on the
  closing end, the union, the removed set, the earliest start, the lock,
  "begins inside", the backstop and the moved-tracks rule;
  `refusal_proof.py` section 12 (12b–12e red on the unfixed Debug build,
  then green on Release).
