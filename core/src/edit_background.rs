//! The two background commands — spec §6's `add_background` and
//! `add_blurred_background` (road map 2, phase 6c).
//!
//! Both answer one question: what goes BEHIND the picture. A 16:10 screen
//! recording on a 16:9 timeline, a phone capture on a landscape canvas, a
//! title standing on nothing — each leaves the canvas showing through, and
//! an editor fills it two ways. A **plate**: a colour, or an image, sized
//! to the canvas. Or a **blurred copy of the clip itself**, blown up past
//! the frame, which is the screencast look — the backdrop is always the
//! right colour because it is made of the same pixels.
//!
//! Both put exactly ONE clip on a NEW track inserted at index 0, the
//! back-most. Not on the back-most EXISTING track: a background is behind
//! everything, and a fresh track is the only place that is true whatever
//! the stack already holds — no overlap to check, nothing already there to
//! push aside, and one undo step to take it all away again. The plate
//! starts at 0 and runs the timeline's length; the blurred copy starts and
//! ends exactly where the clip it copies does.
//!
//! # Why these are core ops
//!
//! The plan of record called Add Blurred Background "a composite over
//! existing ops", and it is worth writing down why it is not, because the
//! recipe it proposed cannot be built and the one that replaces it carries
//! a constraint no single op states.
//!
//! The proposed recipe was the clip's clipboard payload `paste`d onto a new
//! track; that payload carries no `nests` key. (This op refuses a nest clip
//! too, for its own reason — see [`Project::add_blurred_background`] — so
//! that half of the argument is spent and is written down spent rather than
//! left standing.) Re-placing the media with `add_clip`
//! instead loses the SOURCE WINDOW — `add_clip` gives the whole media — so
//! the backdrop of a trimmed clip shows different frames from the
//! foreground and drifts out of sync, which is the one thing this feature
//! may not do; repairing it means a `trim_start` and a `trim_end` in the
//! app over arithmetic this crate already owns. `duplicate` is no way out
//! either: it lands its copy one selection span LATER on the SAME track,
//! where it can collide with a neighbour, be refused, or silently acquire a
//! cross dissolve for a reason the user never asked about.
//!
//! Here it is `clip.clone()` with five fields changed, and the derived
//! values — the source's pixel size, [`Project::fill_scale`], and the
//! [`crate::props_check::SCALE_MAX`] clamp on it — are core vocabulary the
//! app does not have. `insert_clip`, `overwrite_clip` and `add_zoom_action`
//! are the standing precedent and they name the rule: **a composite becomes
//! an op when composing it out of existing ops carries a constraint that no
//! single half states.** Frame-exact sync with the source clip is exactly
//! such a constraint.
//!
//! # What a blurred copy does NOT keep
//!
//! Five things, and each is a wrong picture — or a wrong SOUND — if it is
//! carried:
//!
//! 1. **Its audio.** The copy has the same media, the same in point and the
//!    same span, so a mix that played both would play one source twice:
//!    roughly +6 dB and comb filtering on every blurred background, and
//!    wrong numbers out of `detect_silence` and the level meter besides.
//!    It is INVISIBLE in a still frame, which is the reason it is stated
//!    here and tested by name rather than left to a render to catch. The
//!    switch moves: the copy's `enabled` is `{video: true, audio: false}`,
//!    which is exactly the pair `detach_audio` sets, read the other way
//!    round. Its `enabled.video` is forced ON for the same reason its audio
//!    is forced off: the copy exists to draw, so a hidden foreground clip
//!    must not mint a hidden backdrop that looks like the command did
//!    nothing.
//! 2. **Its duck** — and ONLY its duck, out of the whole audio group. A
//!    volume, a fade, a pan are facts about this clip's own sound and are
//!    inert once nothing plays it, so they travel; a duck is not about this
//!    clip's sound at all, it is an instruction to lower everything ELSE.
//!    [`Project::duckers`] collects every clip carrying one with no test of
//!    `enabled.audio`, of a mute, or of a solo — a duck is a fact about the
//!    timeline, gathered before any voice is assigned — so a copy that kept
//!    it would be a ducker on no track, ducking the whole mix INCLUDING the
//!    clip it was copied from, which the `others` filter cannot exclude
//!    because the copy is a voice nowhere. A picture command would halve
//!    the level of the very clip it is standing behind, and no rendered
//!    frame could see it. Clearing it on the copy is the narrow fix and the
//!    one this op is entitled to make. The wide one — teaching `duckers`
//!    that a clip nobody can hear does not duck — would also change how
//!    `detach_audio` has sounded since M2, which is a shipped feature and
//!    its own change to measure.
//! 3. **Its transition.** A `transition_in` describes an overlap on the
//!    ORIGINAL track (`detach_audio`'s stated reason). The copy is alone on
//!    a new track, so it has no predecessor and nothing to dissolve from.
//! 4. **Its actions.** A zoom action on the foreground would otherwise
//!    animate the backdrop out from under it — the background sliding while
//!    the picture on top of it moves, which is the opposite of what a
//!    background is for.
//! 5. **Its name and label.** The copy is named "Blurred Background", so
//!    the timeline can tell the two apart at a glance, and its label is
//!    cleared: a label is a mark the user put on one clip, and copying it
//!    would file the backdrop under a category nobody chose for it.
//!
//! Everything else IS kept, deliberately: the source and its in point (the
//! sync), the speed, the rest of the audio group, and every video property
//! the copy does not overwrite — opacity, rotation, corner radius, the
//! colour controls, the shadow, the reflection, the spotlight and the
//! hidden regions. Two honest limits fall out of that. A ROTATED clip gives a
//! rotated backdrop, and the fill scale is measured square, so a large
//! rotation can leave the corners showing; measuring through the rotation
//! the way `edit_zoom.rs` does would make the common case (no rotation)
//! magnify for a corner that is not there. And a hidden REGION rides along
//! at the copy's own scale against an uncropped rect, so it no longer
//! covers what it covered on the original — which costs nothing in
//! practice, because a full-strength blur over the whole layer is already
//! hiding everything the region was hiding.
//!
//! # The derived values
//!
//! - **`scale`** is [`Project::fill_scale`] of the source's pixel size:
//!   `max(cw/sw, ch/sh)`, clamped to the layer bounds. FILL, not fit — a
//!   backdrop that leaves a bar down the side has failed at its one job.
//! - **`x`, `y`** are 0. Fill leaves the surplus outside the canvas on one
//!   axis, and the only placement that spends it evenly is the centre.
//! - **`crop`** is cleared. A crop is what the editor cut away from the
//!   foreground; the backdrop is the thing that fills what the crop left
//!   empty, so keeping it would take the same bite out of both.
//! - **`filters`** becomes exactly one full-strength blur, REPLACING the
//!   clip's own stack rather than appending to it. The blur is what makes
//!   the copy a background instead of a second picture, a look the user
//!   chose for the foreground would fight it, and [`crate::model::MAX_FILTERS`]
//!   is 4, so appending could overflow a stack that was already full.
//! - **`blend`** is forced to [`crate::model::BlendMode::Normal`], whatever
//!   the clip in front carries. A backdrop is the BACK-most layer, so what
//!   it composites against is the canvas — black by default — and every
//!   mode with black for an operand either does nothing or destroys the
//!   plate: `multiply`, `darken` and `overlay` render it solid black,
//!   `screen`, `add` and `lighten` leave it exactly as it was, `difference`
//!   inverts it. A blend mode is a choice about a picture and what is UNDER
//!   it, and the copy's destination is not the one that choice was made
//!   against. `add_background`'s plate writes `VideoProps::default()` and is
//!   therefore `Normal` already; forcing it here is the two commands
//!   agreeing about the one property that decides whether a backdrop is
//!   visible at all.
//!
//! The PLATE takes the same **fill** scale, for the same reason and against
//! the same objection. `add_clip` gives a new clip a FIT scale and a plate
//! is otherwise shaped exactly as `add_clip` would shape it — but Fit is a
//! rescue for footage LARGER than the canvas ([`Project::fit_scale`]) and
//! answers 1 for everything else, so a 1280×720 picture chosen as a
//! background would float in the middle of the canvas with a bar down each
//! side, and a 3840×2400 one would leave two thinner ones. Which of those
//! happens depends on `canvas.fit_new_clips`, a flag about NEW CLIPS that
//! has no opinion about backgrounds at all. A background that leaves the
//! canvas showing has failed at its one job; a person who wants the whole
//! picture inside the frame scales it down from a state they can see, where
//! a person who wanted it to cover cannot discover the number that makes it.
//!
//! # The plate's colour
//!
//! `add_background` with no colour paints WHITE, not black. The default
//! canvas background is already black, so a black plate is a command that
//! appears to do nothing — the worst first impression a feature can make.
//! White is visible on arrival, it is the neutral plate a person then
//! re-colours in the inspector's Fill row, and it is the identity for
//! `multiply`, which is the blend mode a person tries first and the one
//! that renders black over the default canvas with nothing behind it.

use crate::model::{
    AudioProps, BlendMode, Clip, Color, Crop, Enabled, Filter, FilterKind, MediaKind, Project,
    ShapeKind, ShapeProps, Source, Track, VideoProps,
};
use crate::outcome::Outcome;
use crate::props_check::check_shape;
use crate::time::Ticks;

/// What a plate is called on the timeline, and what a blurred copy is
/// called. Both are `Clip::name`s, so the app's fallback ("call it what it
/// shows") is overridden by something that says what the clip is FOR — the
/// one thing a backdrop's own source cannot say, since it is the same
/// source as the clip in front of it.
const BACKGROUND_NAME: &str = "Background";
const BLURRED_BACKGROUND_NAME: &str = "Blurred Background";

/// The plate `add_background` paints when the caller names no colour. White
/// rather than black — the module doc argues it.
const DEFAULT_PLATE: Color = [1.0, 1.0, 1.0, 1.0];

impl Project {
    /// A clone of this project with a new EMPTY track at index 0, and that
    /// track's id.
    ///
    /// Both ops start here, and the id ORDER is part of their contract. The
    /// module doc of `edit.rs` promises that a new id is the project's
    /// `next_id` from before the call; these two ops mint two objects, so
    /// the promise has to say which is which — the TRACK takes `next_id`
    /// and the clip takes the one after it.
    ///
    /// The name follows `detach_audio`'s, the crate's other op that invents
    /// a track it was not asked for: `Track <count + 1>`, unique without
    /// renumbering anything above it. A track called "Background" would
    /// read better for one second and then be wrong, because the user is
    /// free to put anything else on it.
    fn with_back_track(&self) -> (Project, u32) {
        let mut next = self.clone();
        let id = next.allocate_id();
        let name = format!("Track {}", next.tracks.len().saturating_add(1));
        next.tracks.insert(
            0,
            Track {
                id,
                name,
                hidden: false,
                muted: false,
                locked: false,
                solo: false,
            },
        );
        (next, id)
    }

    /// How long a plate is: the caller's `duration`, or the whole timeline's
    /// length when it is absent (spec §6).
    ///
    /// The default is snapped even though every clip end already sits on the
    /// grid — a hand-written project file is the case that is not — and it
    /// floors at one frame, because a background of an EMPTY timeline would
    /// otherwise be a zero-length clip, which `validate` refuses and which
    /// is not a thing the timeline can hold.
    ///
    /// A duration the caller GAVE is refused rather than floored, which is
    /// `add_text_clip`'s and `add_shape_clip`'s rule for the same argument
    /// and the envelope's rule for a length (`edit.rs`): a negative or
    /// sub-frame length is a caller's arithmetic mistake, and clamping it
    /// would answer a bug with a clip.
    fn plate_duration(&self, duration: Option<Ticks>) -> Result<Ticks, String> {
        let Some(given) = duration else {
            return Ok(self.snapped(self.duration()).max(self.frame()));
        };
        let snapped = self.snapped(given);
        if snapped < self.frame() {
            return Err(format!(
                "background duration must be at least one frame ({} ticks), not {given}",
                self.frame()
            ));
        }
        Ok(snapped)
    }

    /// Puts a backdrop on a new back-most track, running from 0 for
    /// `duration` — the timeline's own length when that is absent (spec §6).
    ///
    /// With `media`, the clip is shaped as `add_clip` would shape one of
    /// that file in every respect but its scale: the right source kind,
    /// audio props when the file has sound, and a FILL scale where
    /// `add_clip` takes a Fit one — the module doc argues that one
    /// difference. With `color`, or
    /// with neither, it is a canvas-sized filled rectangle with no stroke,
    /// at scale 1 — the rectangle IS the canvas, so there is nothing for
    /// Fit to do and writing the 1 outright keeps it exact whatever
    /// `fit_new_clips` says. Either way the clip is named "Background".
    ///
    /// A plate the user then re-colours in the inspector's Fill row is the
    /// whole of the "Solid Color" command, and it is also how a full-canvas
    /// GRADIENT becomes reachable: a gradient is a shape's fill, so the
    /// gradient background the road map asks for is this clip with a
    /// `set_shape` after it.
    ///
    /// `Err` for `media` and `color` together (they are alternatives, and a
    /// caller that named both meant one of them), for an unknown media, for
    /// a media with no pictures to show, for a colour outside 0–1, and for a
    /// duration under a frame — and, through [`Project::finish`], when the
    /// extra track or clip would break a reader cap. Never an identity: the clip
    /// lands on a track of its own, so there is nothing here to refuse
    /// quietly.
    ///
    /// A timed media — video or audio — IS clamped to its own length,
    /// whether the duration was given or defaulted to the timeline's (spec
    /// §11, D4-4). It reads [`Project::whole_media_length`], which is what
    /// `add_clip` gives a clip of the same file, so the plate ends where
    /// its file does and its segment plays at rate 1. What that paragraph
    /// used to say — that an unclamped plate "shows nothing" past the end
    /// of its media — was measured FALSE: the plan stretched a six-second
    /// file over a twelve-second plate at rate 0.5. An image plate is
    /// unclamped still, having no source bound at all.
    pub fn add_background(
        &self,
        media: Option<u32>,
        color: Option<Color>,
        duration: Option<Ticks>,
    ) -> Result<Outcome, String> {
        if let (Some(media), Some(_)) = (media, color) {
            return Err(format!(
                "add_background takes a media or a color, not both (media {media})"
            ));
        }
        let mut duration = self.plate_duration(duration)?;

        // Everything that can refuse is decided against `self`, before a
        // track exists to leave behind.
        let (source, video, audio, shape) = match media {
            Some(id) => {
                let found = self.require_media(id)?.clone();
                let has_pixels = found.has_video || matches!(found.kind, MediaKind::Image);
                if !(has_pixels && found.width > 0 && found.height > 0) {
                    return Err(format!(
                        "media {id} has no pixel size, so it cannot be a background"
                    ));
                }
                let source = match found.kind {
                    MediaKind::Image => Source::Image { media: id },
                    MediaKind::Video | MediaKind::Audio => {
                        // A timed plate is held INSIDE its own file, by the
                        // same function `add_clip` measures a whole media
                        // with — so the plate's two `Err` sentences are
                        // that op's, and the segment plays at rate 1
                        // (spec §11, D4-4).
                        duration = duration.min(self.whole_media_length(&found)?);
                        Source::Media {
                            media: id,
                            r#in: 0,
                            reversed: false,
                        }
                    }
                };
                // FILL, not `add_clip`'s Fit: a plate that leaves the canvas
                // showing down one side has failed at the one thing a
                // background is for, and whether Fit leaves it showing
                // depends on `canvas.fit_new_clips`, which has no opinion
                // about backgrounds. The module doc argues it at length.
                let video = VideoProps {
                    scale: self.fill_scale(f64::from(found.width), f64::from(found.height)),
                    ..VideoProps::default()
                };
                (
                    source,
                    video,
                    found.has_audio.then(AudioProps::default),
                    None,
                )
            }
            None => {
                let plate = ShapeProps {
                    kind: ShapeKind::Rectangle,
                    width: f64::from(self.canvas.width),
                    height: f64::from(self.canvas.height),
                    stroke: None,
                    fill: Some(color.unwrap_or(DEFAULT_PLATE)),
                    ..ShapeProps::default()
                };
                // The caller's colour reaches the same check a `set_shape`
                // of it would, so `[0, 0, 255, 1]` is named here rather
                // than blown out on the canvas.
                check_shape(&plate)?;
                (Source::Shape, VideoProps::default(), None, Some(plate))
            }
        };

        let (mut next, track) = self.with_back_track();
        let clip = Clip {
            id: next.allocate_id(),
            track,
            start: 0,
            duration,
            source,
            enabled: Enabled::default(),
            speed: 1.0,
            video: Some(video),
            audio,
            text: None,
            shape,
            graphic: None,
            actions: Vec::new(),
            transition_in: None,
            name: Some(BACKGROUND_NAME.to_string()),
            label: None,
        };
        next.clips.push(clip);
        self.finish(next)
    }

    /// Copies `clip` onto a new back-most track, blown up to fill the canvas
    /// and blurred — the screencast backdrop (spec §6).
    ///
    /// The copy keeps the source, the in point, the start, the duration and
    /// the speed, so it plays the SAME FRAMES as the clip in front of it and
    /// stays exact under any later trim of its own; it drops its audio, its
    /// duck, its transition, its actions and its identity, and it takes a
    /// fill scale, a centred position, no crop, a `normal` blend and one
    /// full-strength blur. The module doc argues each of those.
    ///
    /// **A NEST clip is refused**, and it is the one refusal here that is
    /// not about a missing size — a nest has a frozen canvas and
    /// `Project::source_size` answers with it. It is about the BLUR.
    /// Flattening
    /// (`nest.rs`) folds a nest clip's PLACEMENT down onto the layers inside
    /// it and drops every per-pixel property it carries: a nest clip never
    /// becomes a layer of its own, so `recipe.rs::layer` reads `filters`,
    /// the colour controls, the chroma key, the shadow, the reflection, the
    /// spotlight, the hidden regions and the blend off the INNER clip and
    /// never off the nest clip. The blur this op writes would therefore
    /// reach nothing, and the command would report success having minted a
    /// SHARP 1.5× duplicate of the nest sitting behind the original, at
    /// double the render cost — a wrong picture answered with no message,
    /// which is the failure shape this crate refuses by name everywhere
    /// else. It is the same call `edit_props.rs`'s `check_blend` makes about
    /// `video.blend` on a nest clip, and `clamp_video`'s about an end patch
    /// carrying one; a blur is a per-pixel property like any other. The way
    /// in is the round trip the rest of the crate already uses for a nest —
    /// ⇧⌘G, blur the clip, ⌘G — and it is what `Frame`'s doc in `nest.rs`
    /// records as a limit of the flattening rather than of this op.
    ///
    /// `Err` for an unknown clip, for a nest, for a source with no pixel
    /// size — a text clip, an audio-only one, or a degenerate shape, which
    /// have nothing to scale to the canvas — and for a clip carrying no
    /// video properties at all. `Err` too when
    /// the extra track or clip would break a reader cap, which
    /// [`Project::finish`] reports through `validate`. Never an identity: a copy
    /// on a new empty track can neither be an identity nor break the overlap
    /// rule, so there is nothing here to refuse quietly.
    pub fn add_blurred_background(&self, clip: u32) -> Result<Outcome, String> {
        let target = self.require_clip(clip)?.clone();
        if matches!(target.source, Source::Nest { .. }) {
            return Err(format!(
                "clip {clip} shows a nest, whose own filters the flattening drops, \
                 so a blurred copy of it would come out sharp"
            ));
        }
        let Some((source_width, source_height)) = self.source_size(&target) else {
            return Err(format!(
                "clip {clip}'s source has no pixel size, so nothing can be scaled to fill the canvas"
            ));
        };
        let Some(video) = target.video.clone() else {
            return Err(format!("clip {clip} has no video properties"));
        };

        let (mut next, track) = self.with_back_track();
        let mut copy = target;
        copy.id = next.allocate_id();
        copy.track = track;
        // The pair `detach_audio` sets, read the other way: this half of the
        // clip is the picture, and the sound stays with the original.
        copy.enabled = Enabled {
            video: true,
            audio: false,
        };
        // The one field of the audio group that is not about this clip's own
        // sound. `duckers` gathers a duck from the flattened timeline with no
        // test of `enabled.audio`, a mute or a solo, so a copy that kept one
        // would duck the whole mix — the clip it was copied from included,
        // since the copy is a voice on no track and the `others` filter has
        // nothing to exclude it by. A picture command may not change the
        // sound, and no rendered frame could catch it if it did.
        copy.audio = copy.audio.map(|audio| AudioProps {
            duck: None,
            ..audio
        });
        copy.transition_in = None;
        copy.actions = Vec::new();
        copy.name = Some(BLURRED_BACKGROUND_NAME.to_string());
        copy.label = None;
        copy.video = Some(VideoProps {
            scale: self.fill_scale(source_width, source_height),
            x: 0.0,
            y: 0.0,
            crop: Crop::default(),
            filters: vec![Filter {
                kind: FilterKind::Blur,
                amount: 1.0,
            }],
            // A plate composites with the CANVAS, never with a mode chosen
            // for the picture in front of it — over the default black that
            // mode is either destructive or inert. The module doc argues it.
            blend: BlendMode::Normal,
            // And it does not MOVE (format version 8). A backdrop that slid
            // in, spun or pulsed behind the clip it was copied from would
            // be two pictures of one recording disagreeing about where they
            // are, which is the visible half of the same mistake as keeping
            // the audio switch — and a slide would leave the canvas showing
            // down one side, which is the one thing a background exists to
            // prevent.
            motion: None,
            ..video
        });
        next.clips.push(copy);
        self.finish(next)
    }
}
