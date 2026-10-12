//! Editing INSIDE a nest — the envelope's `scope` key (spec §6, §4.4).
//!
//! Every `clip`, `track` and `action` argument in the op table resolves
//! through [`Project::clip`] and its siblings, which search `self.clips`
//! and `self.tracks` and nothing else. That is what made a nest a closed
//! box: no op could name what was in one, and the way in was the round trip
//! — `unnest`, edit, `nest` — which is the identity on clip content but
//! throws the nest clip's own group-level properties away.
//!
//! **The fix is not to teach sixty-one ops about nests.** It is to give
//! the ENVELOPE a scope, and to hand the op a project in which the nest's
//! own tracks and clips are the top level. Then `Project::clip` keeps its
//! one meaning, `apply_op` keeps its flat dispatch, every refusal and every
//! clamp every op documents holds unchanged, and undo stays one stack of
//! parent handles because what comes back out is still a whole
//! [`Project`].
//!
//! ### The view
//!
//! [`Project::scoped_view`] is the nest as a project:
//!
//! | Key | Value | Why |
//! |---|---|---|
//! | `canvas.width` / `height` | the NEST's frozen pair | a nest is composited at the size it was made at ([`Nest`]), so that is the canvas its contents are placed against — `add_background`'s plate and `add_zoom_action`'s solve both read it |
//! | `canvas.fps`, `background`, `fit_new_clips`, `timecode_frames` | the PARENT's | a [`Nest`] has none of them. The rate matters: every time argument snaps to the document's frame grid, and there is only one grid |
//! | `tracks` / `clips` | the nest's | the whole point |
//! | `media` | the parent's | a nest references the parent's `media[]` in the parent's one id space (spec §5.2); a view with none would fail `validate` on the first clip that shows a file |
//! | `nests` | the parent's, with the scoped one EMPTIED | see below — this is neither "the parent's" nor "the parent's minus the scope" |
//! | `markers` | none | a nest has no markers, and the timeline's are project time |
//! | `next_id` | the parent's | one id space, so an id minted inside is minted for the whole document |
//!
//! **The scoped nest's row stays and its CONTENTS go**, and both halves
//! are load-bearing. Neither of the two obvious answers works:
//!
//! - *Leave it whole* and `validate` refuses the view. Its uniqueness
//!   sweep inserts every `self.clips` id into one `HashSet` and then every
//!   `nest.clips` id into the SAME set, because a nest holds its clips in
//!   the parent's one id space. A view whose top level is nest 4's clips
//!   AND whose `nests[]` still holds nest 4 inserts every one of them
//!   twice, so the answer is `duplicate id N on a clip in nest 4` — and
//!   [`Project::finish`] validates every op result, so the FIRST op applied
//!   in any scope would be an `Err`. `check_caps` double-counts for the
//!   same reason.
//! - *Take the row out altogether* and `validate` refuses the view again,
//!   in the case the phase exists for. `check_clips` resolves every
//!   `Source::Nest` against `nests[]`, in EVERY container, so scoping into
//!   a nest that another nest shows — a nest inside a nest, which is what
//!   "go one level in" usually means — leaves that other nest's clip
//!   naming a nest the view has not got: `clip 172 in nest 170 refers to
//!   unknown nest 180`. Measured, not reasoned: it is what the depth test
//!   below reported before this paragraph existed.
//!
//! So the row is kept with `tracks` and `clips` emptied. The id resolves,
//! nothing is counted twice, and the emptiness is unreachable: a nest
//! cannot show itself at any remove (`check_nesting` refuses a cycle), so
//! no clip at the view's top level can name the scope, and the flattening
//! walk only ever descends from there. It is also what keeps `nest`'s
//! default name — `Nest <nests.len() + 1>` — counting the same list inside
//! a scope as outside it.
//!
//! The other nests are the parent's own, whole. They have to be: a nest
//! clip INSIDE the scope shows one of them, and `check_clips` would refuse
//! it otherwise.
//!
//! ### The merge
//!
//! [`Project::merge_scope`] writes the nest's `tracks` and `clips`,
//! `next_id`, `media` and `nests` back into a clone of the parent, and
//! leaves the canvas, the markers and the timeline's own clips exactly as
//! they were.
//!
//! **What the merge does NOT write is the half that keeps the markers
//! safe**, and the mutation run said so: giving the view the parent's
//! markers is an EQUIVALENT mutant today, because the three marker ops are
//! refused and the merge discards whatever the view did to them. The empty
//! `markers` on the view is defence — an `insert_time` inside a nest should
//! not spend its time shifting a list that is about to be thrown away — and
//! the load-bearing rule is that a scoped edit never writes markers back. A
//! future change that added them to this list would be the real bug, and it
//! is killed by `a_scoped_edit_does_not_move_the_timelines_markers`.
//!
//! `media` is on that list because of one op. `paste` appends a row for
//! every payload path the project does not already carry
//! (`edit_paste.rs`), so a paste inside a scope that dropped the view's
//! media would leave the pasted clips naming a media the parent has not
//! got, and the merged parent would fail `check_clips` with `clip N refers
//! to unknown media M`. It is a straight replace rather than a union
//! because on this path the list can only GROW: `add_media`, `relink_media`
//! and `remove_media` are refused inside a scope, so nothing else reorders,
//! rewrites or removes a row.
//!
//! `nests` is the subtle one, and the rule is **union first, orphans
//! after**. `unnest` ends by dropping the nest it opened when
//! `nest_is_shown` says nothing else shows it, and `nest_is_shown` asks
//! `every_clip()` — the project's own clips plus every nest's. In a view
//! the project's own clips are the SCOPED nest's, and the parent's timeline
//! clips are not there at all, so un-nesting an inner nest clip that a
//! timeline clip also shows judges that nest unused and drops it; the merge
//! would then leave the parent's clip dangling. Two clips sharing one nest
//! is a real state — `duplicate` clones the source rather than the group —
//! so this is not a corner. The merge therefore takes the UNION, dropping
//! nothing the view dropped, and only then asks the MERGED parent's own
//! `nest_is_shown` about each one. Keeping an orphan is harmless (an
//! orphaned nest is a legal project — `check_nesting` walks them
//! deliberately); dropping a shown one is a corrupt document.
//!
//! ### The result, which has a wider third arm
//!
//! A scoped op answers spec §5.5's three ways like any other, and it exits
//! through the same [`Project::finish`] — but the `Err` arm can fire where
//! no unscoped op can reach, because **two invariants are invisible from
//! inside a scope**:
//!
//! - **The caps.** `format::check_caps` sums the timeline's clips and
//!   tracks with every nest's, deliberately, so 64 nests of 64 tracks
//!   cannot slip past a cap that exists to bound exactly that. A view holds
//!   the nest's clips at top level and the parent's timeline clips nowhere,
//!   so its totals are strictly LOWER than the document's and an op refused
//!   at the parent's cap would be accepted inside a scope.
//! - **The depth.** `check_nesting` starts every walk at level 1, so a view
//!   cannot see how deep the nest it is already sits. A `nest` inside a
//!   scope at depth 8 builds a level-9 stack the view validates happily.
//!
//! Neither can be answered by the view, and neither should be answered
//! twice, so both are answered ONCE, at the end, by validating the MERGED
//! parent. The contract, stated so a caller can rely on it:
//!
//! - `Ok(Outcome::Applied(project))` — the view changed and the merged
//!   parent holds every invariant.
//! - `Ok(Outcome::Identity)` — the op is valid and the view changed
//!   nothing, or the merge came out equal to the project it started from.
//!   No undo step, exactly as at the top level.
//! - `Ok(Outcome::Refused(why))` — a rule inside the view declined the op,
//!   in its own words, which come back out of the scope unchanged: a rule
//!   about clips says the same thing whichever project they were counted
//!   in. No undo step either.
//! - `Err(message)` — `scope` names no nest; the op has no meaning inside
//!   one; the op's own arguments are invalid IN THE VIEW (an id that is not
//!   in this nest is `no clip with id N`, which is the honest answer);
//!   **or** the merged parent fails an invariant the view could not see —
//!   `too many clips`, `too many tracks`, `nests are more than 8 deep at
//!   nest N`. That last group is the one worth reading twice: *an op may
//!   succeed against the view and the scoped apply still return `Err`.*

use serde_json::Value;

use crate::edit::Op;
use crate::export::describe;
use crate::model::{Canvas, Nest, Project};
use crate::outcome::Outcome;

/// Reads the envelope's `scope` out of the value `edit::parse` removed.
///
/// `None` for absent and for an explicit `null` — the envelope's standing
/// rule that the two mean the same thing — and an `Err` naming the value
/// for anything that is not a nest id, which is any u32. A negative number,
/// a fraction, a numeric STRING and a bool all land there: a scope decides
/// which document an edit lands in, so guessing at one is the last thing to
/// do.
pub(crate) fn read(value: Option<&Value>) -> Result<Option<u32>, String> {
    match value {
        None | Some(Value::Null) => Ok(None),
        Some(found) => found
            .as_u64()
            .and_then(|id| u32::try_from(id).ok())
            .map(Some)
            .ok_or_else(|| format!("scope must be a nest id, not {}", describe(found))),
    }
}

/// The ops with no meaning inside a nest, by name, or `None` for the fifty
/// that work in there unchanged.
///
/// Exhaustive rather than a short list with a `_` arm, and that is the
/// point of writing it out: an op added by a later phase does not compile
/// until somebody has decided which side of this line it falls on. The
/// compiler is the reviewer.
fn refused_inside(op: &Op) -> Option<&'static str> {
    match op {
        // A nest has no `markers[]` (spec §5.2). The timeline's markers are
        // PROJECT time and chapter points on the exported file; a marker
        // measured from a nest's own zero would be neither.
        Op::AddMarker { .. } => Some("add_marker"),
        Op::SetMarker { .. } => Some("set_marker"),
        Op::RemoveMarker { .. } => Some("remove_marker"),

        // Half of a canvas is not a nest's to have — the rate, the
        // background and the two switches are the document's — and the half
        // that is, its size, is FROZEN at the size the parent had when the
        // nest was made, so that a later `set_canvas` cannot silently
        // re-lay-out content nobody touched ([`Nest`]). Honouring that here
        // would be `set_canvas` reaching through a scope to do the one
        // thing the freeze exists to stop.
        Op::SetCanvas { .. } => Some("set_canvas"),

        // A nest references the parent's `media[]` in the parent's one id
        // space (spec §5.2). So a media edit inside a scope is a media edit
        // on the document wearing a scope — the same act, spelled twice —
        // and `remove_media` is worse than redundant: it would strip the
        // clips that show the file from the view's containers and leave
        // every TIMELINE clip that shows it dangling, since those are not
        // in the view to be found.
        Op::AddMedia { .. } => Some("add_media"),
        Op::RelinkMedia { .. } => Some("relink_media"),
        Op::RemoveMedia { .. } => Some("remove_media"),
        Op::SetMediaColor { .. } => Some("set_media_color"),

        // An adjustment clip grades what is behind it at the top level only
        // (spec §11 GR-6): `check_clips` refuses one inside a nest, so the
        // op is refused here before a view is built.
        Op::AddAdjustmentClip { .. } => Some("add_adjustment_clip"),

        // ---- everything else ------------------------------------------
        // Placement, trimming, properties, actions, tracks and grouping all
        // mean in a nest exactly what they mean on the timeline, `nest` and
        // `unnest` included: nesting the whole of a scope mints a FRESH id
        // and puts the new nest clip INSIDE the scoped nest, so no clip
        // ever points at its own container. It is a legal extra level,
        // bounded by `MAX_NEST_DEPTH` on the merged parent like any other.
        Op::AddClip { .. }
        | Op::AddTextClip { .. }
        | Op::AddShapeClip { .. }
        | Op::AddGraphicClip { .. }
        | Op::AddBackground { .. }
        | Op::AddBlurredBackground { .. }
        | Op::InsertClip { .. }
        | Op::OverwriteClip { .. }
        | Op::MoveClip { .. }
        | Op::TrimStart { .. }
        | Op::TrimEnd { .. }
        | Op::RateStretch { .. }
        | Op::Slip { .. }
        | Op::Roll { .. }
        | Op::Split { .. }
        | Op::Delete { .. }
        | Op::RippleDelete { .. }
        | Op::RippleDeleteRange { .. }
        | Op::RippleDeleteRanges { .. }
        | Op::LiftRange { .. }
        | Op::InsertTime { .. }
        | Op::CloseGap { .. }
        | Op::SetSpeed { .. }
        | Op::SetReversed { .. }
        | Op::FreezeFrame { .. }
        | Op::DetachAudio { .. }
        | Op::Duplicate { .. }
        | Op::Paste { .. }
        | Op::PasteAttributes { .. }
        | Op::Nest { .. }
        | Op::Unnest { .. }
        | Op::SetVideo { .. }
        | Op::SetAudio { .. }
        | Op::SetText { .. }
        | Op::SetShape { .. }
        | Op::SetGraphic { .. }
        | Op::SetClip { .. }
        | Op::SetEnabled { .. }
        | Op::SetTransition { .. }
        | Op::SetTransitionDuration { .. }
        | Op::AddTransition { .. }
        | Op::SetTransitionStyle { .. }
        | Op::AddAction { .. }
        | Op::AddZoomAction { .. }
        | Op::SetAction { .. }
        | Op::SetActionEnd { .. }
        | Op::RemoveAction { .. }
        | Op::AddTrack { .. }
        | Op::RemoveTrack { .. }
        | Op::MoveTrack { .. }
        | Op::SetTrack { .. }
        | Op::RemoveEmptyTracks {} => None,
    }
}

impl Project {
    /// Applies one op inside nest `scope` (this module's doc).
    ///
    /// The order of the two refusals is deliberate: an unknown nest is
    /// answered FIRST, before the op is classified, because `scope` is the
    /// argument that decides which document the caller thinks it is editing
    /// and a mistake there is worth reporting ahead of anything else.
    pub(crate) fn apply_scoped(&self, op: &Op, scope: u32) -> Result<Outcome, String> {
        let Some(nest) = self.nest(scope) else {
            return Err(format!("no nest with id {scope}"));
        };
        if let Some(name) = refused_inside(op) {
            return Err(format!("{name} has no meaning inside nest {scope}"));
        }
        let edited = match self.scoped_view(nest).apply_op(op)? {
            Outcome::Applied(edited) => edited,
            // Both answers that left the VIEW alone leave the document
            // alone, and a rule that spoke inside the nest says the same
            // thing outside it: the sentence is about clips, not about
            // which project they were counted in.
            Outcome::Identity => return Ok(Outcome::Identity),
            Outcome::Refused(why) => return Ok(Outcome::Refused(why)),
        };
        // The one exit every op has. It answers the identity case and it is
        // where the caps and the depth are finally measured, on the MERGED
        // parent, which is the only place they are true.
        self.finish(self.merge_scope(scope, &edited))
    }

    /// The nest as a project — the table in this module's doc.
    ///
    /// `pub(crate)` for [`crate::ffi::rc_project_scoped`], which hands the
    /// SAME view to the app as a read-only handle so the timeline, the
    /// canvas, the plan and the player can all be pointed inside a nest. It
    /// is one function on purpose: a second builder that drifted would make
    /// the app draw one project and its edits land in another, which is the
    /// exact failure `core/CLAUDE.md`'s "one implementation per algorithm"
    /// is for.
    pub(crate) fn scoped_view(&self, nest: &Nest) -> Project {
        Project {
            version: self.version,
            canvas: Canvas {
                width: nest.width,
                height: nest.height,
                fps: self.canvas.fps,
                background: self.canvas.background,
                fit_new_clips: self.canvas.fit_new_clips,
                timecode_frames: self.canvas.timecode_frames,
            },
            media: self.media.clone(),
            tracks: nest.tracks.clone(),
            clips: nest.clips.clone(),
            markers: Vec::new(),
            next_id: self.next_id,
            // Every nest, with the scoped one's own tracks and clips
            // emptied — they are the view's top level, and a second copy
            // of them would double every id in `validate`'s one uniqueness
            // sweep. The ROW stays so that a nest clip elsewhere in the
            // document can still resolve it.
            nests: self
                .nests
                .iter()
                .map(|other| {
                    if other.id == nest.id {
                        Nest {
                            tracks: Vec::new(),
                            clips: Vec::new(),
                            ..other.clone()
                        }
                    } else {
                        other.clone()
                    }
                })
                .collect(),
        }
    }

    /// The edited view written back into a clone of this project.
    ///
    /// Not validated here — [`Project::apply_scoped`] hands the answer to
    /// [`Project::finish`], so there is exactly one place a scoped result
    /// is judged, and it is the same place every unscoped result is judged.
    fn merge_scope(&self, scope: u32, view: &Project) -> Project {
        let mut merged = self.clone();
        merged.media = view.media.clone();
        merged.next_id = view.next_id;

        // The parent's order first, so a nest keeps its place in the file
        // across an edit made inside another one; anything the view minted
        // goes on the end, which is where `nest` and `paste` put one.
        let mut nests: Vec<Nest> = Vec::with_capacity(self.nests.len().saturating_add(1));
        for nest in &self.nests {
            if nest.id == scope {
                let mut edited = nest.clone();
                edited.tracks = view.tracks.clone();
                edited.clips = view.clips.clone();
                nests.push(edited);
            } else if let Some(seen) = view.nest(nest.id) {
                nests.push(seen.clone());
            } else {
                // Dropped by the view. Kept for now — the union — and
                // judged below against the merged document, which is the
                // only one that can see every clip that might show it.
                nests.push(nest.clone());
            }
        }
        for nest in &view.nests {
            if !self.nests.iter().any(|other| other.id == nest.id) {
                nests.push(nest.clone());
            }
        }
        merged.nests = nests;

        let dropped: Vec<u32> = self
            .nests
            .iter()
            .map(|nest| nest.id)
            .filter(|id| *id != scope && view.nest(*id).is_none())
            .collect();
        if !dropped.is_empty() {
            let orphaned: Vec<u32> = dropped
                .into_iter()
                .filter(|id| !merged.nest_is_shown(*id))
                .collect();
            merged.nests.retain(|nest| !orphaned.contains(&nest.id));
        }
        merged
    }
}
