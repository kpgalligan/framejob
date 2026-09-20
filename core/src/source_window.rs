//! THE source window: how much material a clip shows, how much lies either
//! side of it, and the one way a source in point moves.
//!
//! **Two units, and the name of every function here says which one it
//! answers in.** A clip has a `speed`, so the film under it and the timeline
//! over it run at different rates, and the two directions are not each
//! other's inverse in the same expression:
//!
//! - **SOURCE ticks** are a position or a length in the file —
//!   `content_length_in_source`, `last_in_point`, `last_still_time`, and
//!   everything `timeline_to_source` produces. Timeline × speed.
//! - **TIMELINE ticks** are a position or a length on the timeline —
//!   `source_head_on_timeline`, `source_length_on_timeline`,
//!   `longest_duration_on_grid`. Source ÷ speed, FLOORED, so a clip can
//!   never outrun its source by a partial frame.
//!
//! The asymmetry was the hazard this module exists to remove: the three
//! readers sat in `model_query.rs` with only their prose to say that one
//! multiplied where the other two divided, and every caller that had to
//! convert back wrote the multiplication out again — six copies of it
//! (`designs/reelcut-roadmap-7.md` §10.1). `in_advanced` is now the only
//! one, and `source_advanced` is it applied to a whole [`Source`], which is
//! what `trim_start`, `roll`, `split_clip` and `add_transition` each want.
//!
//! **Three answers, not two.** A measurement of a window is a
//! [`SourceBound`], because `Option` meant two opposite things in two
//! callers of the same reader: a `None` was "unbounded, apply no clamp" to a
//! trim and "no handle at all" to a transition. The three arms are
//! [`SourceBound::Unbounded`] (a source that HAS no window — a still, an
//! image, text, a shape, a nest, each of which may begin anywhere and run
//! any length), [`SourceBound::Unmeasured`] (a media clip whose window
//! exists but cannot be measured — unknown media, or a speed that is not a
//! positive finite number) and [`SourceBound::Timeline`] (measured). A
//! caller chooses what `Unmeasured` MEANS to it by name —
//! [`SourceBound::or_unbounded`] reads it as no clamp,
//! [`SourceBound::or_empty`] as nothing available — and the choice is
//! visible at the call site instead of buried in a reader's doc.
//!
//! Nothing here edits: every function takes `&self` or a `&Source` and
//! returns a value.

use crate::model::{Clip, Media, Project, Source};
use crate::time::Ticks;

/// What a TIMELINE-tick measurement of a clip's source window answers.
///
/// The three arms are the module doc's: a source with no window at all, a
/// media window that exists but cannot be measured, and a measurement in
/// timeline ticks.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SourceBound {
    /// No window: a still, an image, text, a shape or a nest.
    Unbounded,
    /// A media clip whose media is unknown, or whose speed is not a
    /// positive finite number. The window is there; the arithmetic is not.
    Unmeasured,
    /// Measured, in TIMELINE ticks.
    Timeline(Ticks),
}

impl SourceBound {
    /// Reads `Unmeasured` as UNBOUNDED. `None` means apply no clamp.
    ///
    /// What a trim wants: a window it cannot measure is one it cannot argue
    /// with, so the edge moves where the caller asked.
    pub fn or_unbounded(self) -> Option<Ticks> {
        match self {
            SourceBound::Unbounded | SourceBound::Unmeasured => None,
            SourceBound::Timeline(ticks) => Some(ticks),
        }
    }

    /// Reads `Unmeasured` as EMPTY — `Some(0)`. `None` means unbounded.
    ///
    /// What a handle count wants: a window it cannot measure supplies no
    /// material, so the handle is zero rather than infinite.
    pub fn or_empty(self) -> Option<Ticks> {
        match self {
            SourceBound::Unbounded => None,
            SourceBound::Unmeasured => Some(0),
            SourceBound::Timeline(ticks) => Some(ticks),
        }
    }
}

/// TIMELINE ticks to SOURCE ticks at a clip's rate: `timeline × speed`,
/// rounded. A product that is not finite is 0 — an absurd speed moves
/// nothing rather than moving somewhere arbitrary.
///
/// A sub-tick move at a very slow speed therefore rounds to nothing, which
/// is what lets `slip` answer an identity instead of writing an edit the
/// gesture did not make.
pub(crate) fn timeline_to_source(timeline: Ticks, speed: f64) -> Ticks {
    let scaled = timeline as f64 * speed;
    // The cast saturates rather than wrapping, so an absurd speed cannot
    // turn a forward move into a backward one.
    if scaled.is_finite() {
        scaled.round() as Ticks
    } else {
        0
    }
}

/// THE mover: a source in point advanced by `timeline` ticks of timeline at
/// this clip's rate, never below 0. A negative `timeline` moves it BACK,
/// which is what `add_transition` extending a clip's head asks for.
///
/// This is the one equation `trim_start`, `roll`, `split_clip`,
/// `freeze_frame`, `slip` and `add_transition` used to write out
/// separately — the arithmetic that keeps the frame under a moving edge
/// from moving with it.
pub(crate) fn in_advanced(source_in: Ticks, timeline: Ticks, speed: f64) -> Ticks {
    source_in
        .saturating_add(timeline_to_source(timeline, speed))
        .max(0)
}

/// A media source with its `in` moved by [`in_advanced`]; every other source
/// cloned unchanged.
///
/// A still's frozen frame and the sourceless kinds do not move when an edge
/// does: a still shows ONE instant wherever it sits, and an image, text, a
/// shape and a nest have no window to slide. Callers hand the whole source
/// here rather than matching on the kind themselves, so that rule is stated
/// once.
pub(crate) fn source_advanced(source: &Source, timeline: Ticks, speed: f64) -> Source {
    match source {
        Source::Media {
            media,
            r#in,
            reversed,
        } => Source::Media {
            media: *media,
            r#in: in_advanced(*r#in, timeline, speed),
            reversed: *reversed,
        },
        other => other.clone(),
    }
}

impl Project {
    /// The source material one clip shows, in SOURCE ticks: its timeline
    /// length times its speed. The same quantity `evaluate::segment_of`
    /// inserts into the composition — it reads this function, so a speed
    /// edit here and the segment there cannot disagree (spec §11, D4-1).
    ///
    /// The middle of the three measurements:
    /// [`Project::source_head_on_timeline`] is what lies before the window,
    /// this is the window, and [`Project::source_length_on_timeline`] is
    /// what a window starting at `in` could still grow to.
    pub fn content_length_in_source(&self, clip: &Clip) -> Ticks {
        let scaled = clip.duration as f64 * clip.speed;
        // The cast saturates rather than wrapping, so an absurd speed
        // cannot produce a negative length; a degenerate one falls back to
        // 1:1.
        if scaled.is_finite() && scaled >= 1.0 {
            scaled.round() as Ticks
        } else {
            clip.duration.max(1)
        }
    }

    /// How much TIMELINE time lies before a clip's first frame — how far
    /// its front edge could be dragged left before the media runs out.
    /// `in` ticks of source lie in front, which is `in / speed` ticks of
    /// timeline at this clip's rate.
    ///
    /// `Unbounded` for a source with no window: a still, an image, text, a
    /// shape and a nest may begin anywhere. A degenerate speed is
    /// `Unmeasured` — the window exists, it just cannot be measured — which
    /// the two callers that clamp a front edge read as EMPTY.
    pub fn source_head_on_timeline(&self, clip: &Clip) -> SourceBound {
        let Source::Media { r#in, .. } = clip.source else {
            return SourceBound::Unbounded;
        };
        if !(clip.speed.is_finite() && clip.speed > 0.0) {
            return SourceBound::Unmeasured;
        }
        let head = (r#in.max(0) as f64 / clip.speed).floor();
        SourceBound::Timeline(if head.is_finite() { head as Ticks } else { 0 })
    }

    /// The longest TIMELINE duration `clip` could have: the media's
    /// remaining source length from its in point, divided by `speed` (at 2x
    /// a 10 s remainder fills 5 s of timeline). Floored, so a clip can
    /// never outrun its source by a partial frame.
    ///
    /// `Unbounded` for a source with no source bound — `still`, `image`,
    /// `text`, `shape` and `nest` may have ANY duration. `Unmeasured` for an
    /// unknown media or a speed that is not a positive finite number: both
    /// were one `None` before, and they are still read the same way by every
    /// caller, but a caller now says which reading it takes.
    pub fn source_length_on_timeline(&self, clip: &Clip) -> SourceBound {
        let (media_id, source_in) = match &clip.source {
            Source::Media { media, r#in, .. } => (*media, *r#in),
            _ => return SourceBound::Unbounded,
        };
        let Some(media) = self.media(media_id) else {
            return SourceBound::Unmeasured;
        };
        if !(clip.speed.is_finite() && clip.speed > 0.0) {
            return SourceBound::Unmeasured;
        }
        let remaining = media.duration.saturating_sub(source_in).max(0);
        SourceBound::Timeline((remaining as f64 / clip.speed).floor() as Ticks)
    }

    /// THE bound a media clip's duration is held to:
    /// [`Project::source_length_on_timeline`] with its measurement snapped
    /// DOWN to the canvas frame grid.
    ///
    /// The division above is floored and lands anywhere, so a length taken
    /// straight from it is not on the grid; snapped to the NEAREST frame it
    /// rounds UP past the end of the file whenever the last frame is more
    /// than half a frame short, which is exactly the defect spec §11's #22
    /// closed. Down, `in + duration × speed ≤ media.duration` holds by
    /// construction and the plan hands the clip a segment that plays at
    /// rate 1.
    pub fn longest_duration_on_grid(&self, clip: &Clip) -> SourceBound {
        match self.source_length_on_timeline(clip) {
            SourceBound::Timeline(length) => SourceBound::Timeline(self.snapped_down(length)),
            bound => bound,
        }
    }

    /// The last SOURCE tick a clip's window could START at and still fit
    /// inside `media`: what is left over when the window is pushed against
    /// the tail of the file.
    ///
    /// A window longer than its own media — which a speed edit can leave
    /// behind — has no room at all rather than negative room, which is the
    /// floor at 0.
    pub(crate) fn last_in_point(&self, clip: &Clip, media: &Media) -> Ticks {
        media
            .duration
            .max(0)
            .saturating_sub(self.content_length_in_source(clip))
            .max(0)
    }

    /// The last SOURCE tick a STILL could hold, one canvas frame short of
    /// the end of `media`.
    ///
    /// A still is one instant, not a window, so all it needs is a margin
    /// from the end. How long a still's source segment really is — one
    /// frame at the MEDIA's rate — is `evaluate.rs`'s business, and the
    /// canvas frame is a good enough margin here.
    pub(crate) fn last_still_time(&self, media: &Media) -> Ticks {
        media.duration.saturating_sub(self.frame()).max(0)
    }
}
