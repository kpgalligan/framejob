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
//! **Every site that WRITES a media clip's window reads the one bound
//! here**, and which function it reads says what it is writing (spec §11,
//! D4-2 to D4-5). A site that writes a DURATION measures the window from
//! tick 0 — [`Project::longest_duration_on_grid`], and through it
//! [`Project::duration_resnapped`] (`set_canvas`'s re-snap, `paste`'s two
//! loops, `unnest`) and [`Project::duration_at_speed`] (`set_speed`);
//! `whole_media_length` is the same measurement of a whole file. A site
//! that writes an END measures it from the clip's OWN start —
//! [`Project::latest_end_on_grid`], which `trim_end` and `roll` clamp
//! against — and a site that writes a START reads
//! [`Project::earliest_start_on_grid`] (`trim_start`, `roll` and
//! `add_transition`'s head handle). The two directions are not the same
//! number: the end has to land on the grid, so for a start that is off it,
//! and by a tick at a rate whose frame is not a whole tick count
//! (24981/1000), `start + longest_duration_on_grid` is not
//! `latest_end_on_grid`. That is why
//! [`Project::longest_duration_on_grid_of`] takes the pieces with `start`
//! among them rather than a clip, and why routing the existing sites
//! through it moved no answer.
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

/// How much TIMELINE time a window starting at `source_in` still has in
/// `media` at `speed`, unsnapped: `(duration − in) / speed`, FLOORED, so a
/// clip can never outrun its source by a partial frame.
///
/// The one place that division is written. `speed` is the caller's to
/// guard — both callers answer `Unmeasured` for a speed that is not a
/// positive finite number before they get here.
fn available_on_timeline(media: &Media, source_in: Ticks, speed: f64) -> Ticks {
    let remaining = media.duration.saturating_sub(source_in).max(0);
    (remaining as f64 / speed).floor() as Ticks
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
        SourceBound::Timeline(available_on_timeline(media, source_in, clip.speed))
    }

    /// THE bound, from the pieces: the longest TIMELINE duration a window
    /// of `media` from `source_in` at `speed`, placed at `start`, could
    /// have and still END on the frame grid inside the file.
    ///
    /// The division is floored and lands anywhere, so a length taken
    /// straight from it is not on the grid; snapped to the NEAREST frame it
    /// rounds UP past the end of the file whenever the last frame is more
    /// than half a frame short, which is exactly the defect spec §11's #22
    /// closed. Down, `in + duration × speed ≤ media.duration` holds by
    /// construction and the plan hands the clip a segment that plays at
    /// exactly the clip's speed.
    ///
    /// **`start` is a parameter because the two readings differ** (spec
    /// §11, D4-2). At `start = 0` this is `snapped_down(available)`, a grid
    /// LENGTH — what a site that writes a DURATION wants. At
    /// `start = clip.start` the clip's END is what lands on the grid, which
    /// is not the same number when the start is off the grid, nor at a rate
    /// whose frame is not a whole tick count. `Unmeasured` for a speed that
    /// is not a positive finite number: the window is there, the arithmetic
    /// is not.
    pub(crate) fn longest_duration_on_grid_of(
        &self,
        start: Ticks,
        media: &Media,
        source_in: Ticks,
        speed: f64,
    ) -> SourceBound {
        if !(speed.is_finite() && speed > 0.0) {
            return SourceBound::Unmeasured;
        }
        let available = available_on_timeline(media, source_in, speed);
        let end = self.snapped_down(start.saturating_add(available));
        SourceBound::Timeline(end.saturating_sub(start).max(0))
    }

    /// THE bound a media clip's DURATION is held to:
    /// [`Project::longest_duration_on_grid_of`] measured at start 0, which
    /// is the whole window snapped DOWN to the canvas frame grid.
    ///
    /// `Unbounded` for a source with no window and `Unmeasured` for an
    /// unknown media, exactly as [`Project::source_length_on_timeline`]
    /// answers them.
    pub fn longest_duration_on_grid(&self, clip: &Clip) -> SourceBound {
        let (media_id, source_in) = match &clip.source {
            Source::Media { media, r#in, .. } => (*media, *r#in),
            _ => return SourceBound::Unbounded,
        };
        let Some(media) = self.media(media_id) else {
            return SourceBound::Unmeasured;
        };
        self.longest_duration_on_grid_of(0, media, source_in, clip.speed)
    }

    /// The latest timeline POSITION a media clip's end edge may reach — its
    /// own start plus the bound measured THERE, so the end lands on the
    /// frame grid and inside the file.
    ///
    /// `None` means apply no clamp, and it is the `or_unbounded` reading
    /// both callers (`trim_end`, `roll`'s tail) already took: a source with
    /// no window cannot be argued with, and neither can one whose
    /// arithmetic is unmeasurable (spec §11, D4-2).
    pub(crate) fn latest_end_on_grid(&self, clip: &Clip) -> Option<Ticks> {
        let (media_id, source_in) = match &clip.source {
            Source::Media { media, r#in, .. } => (*media, *r#in),
            _ => return None,
        };
        let media = self.media(media_id)?;
        let bound = self
            .longest_duration_on_grid_of(clip.start, media, source_in, clip.speed)
            .or_unbounded()?;
        Some(clip.start.saturating_add(bound))
    }

    /// The earliest timeline POSITION a media clip's front edge may reach:
    /// its start less its head, snapped UP so the edge lands on a frame
    /// that is really inside the source (spec §11, D4-5).
    ///
    /// A timeline position and therefore NOT a [`SourceBound`]:
    /// [`SourceBound::or_empty`]'s `Some(0)` is a LENGTH, and a caller
    /// reading it as a position would take it for "back to tick 0". `None`
    /// is no window and no clamp; an `Unmeasured` head is EMPTY, which is
    /// what all three callers read it as. The answer may be NEGATIVE — a
    /// clip may start before tick 0 in the arithmetic if not in the model —
    /// so each caller keeps its own `.max(0)`.
    pub(crate) fn earliest_start_on_grid(&self, clip: &Clip) -> Option<Ticks> {
        let head = self.source_head_on_timeline(clip).or_empty()?;
        Some(self.snapped_up(clip.start.saturating_sub(head)))
    }

    /// What every RE-SNAP of a media clip's duration writes: the stored
    /// duration on this document's grid, at least one frame, and never
    /// longer than the window the file still holds (spec §11, D4-4).
    ///
    /// `set_canvas`'s re-snap, `paste`'s clip loop, `paste`'s nest absorb
    /// and `unnest` all write this one number. The one-frame floor is
    /// applied LAST and so wins over the bound: a media shorter than a
    /// canvas frame still leaves a clip a frame long, which is one of the
    /// cases `evaluate.rs`'s last-line clamp stays for.
    ///
    /// Preconditions: the clip's media resolves in `self` (an unmeasurable
    /// window is simply not clamped), and a degenerate `speed` has already
    /// been set to 1.0 where the caller does that.
    pub(crate) fn duration_resnapped(&self, clip: &Clip) -> Ticks {
        let frame = self.frame();
        let snapped = self.snapped(clip.duration).max(frame);
        match self.longest_duration_on_grid(clip).or_unbounded() {
            Some(bound) => snapped.min(bound).max(frame),
            None => snapped,
        }
    }

    /// What `set_speed` writes: the clip's own content length played at
    /// `rate`, snapped to the NEAREST frame and then held to the bound
    /// measured AT THAT RATE (spec §11, D4-3).
    ///
    /// The content length is read off `clip` AS GIVEN — at its OLD speed,
    /// since that is the window it is showing — but the bound is measured
    /// on a copy running at `rate`, because that is the speed the segment
    /// will play at and the one the invariant has to hold for. A quotient
    /// that is not finite leaves the duration alone. `rate` arrives already
    /// clamped to ×0.1 – ×10.
    pub(crate) fn duration_at_speed(&self, clip: &Clip, rate: f64) -> Ticks {
        let scaled = self.content_length_in_source(clip) as f64 / rate;
        if !scaled.is_finite() {
            return clip.duration;
        }
        let mut at_rate = clip.clone();
        at_rate.speed = rate;
        at_rate.duration = scaled.round() as Ticks;
        self.duration_resnapped(&at_rate)
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
