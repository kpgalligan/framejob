//! The A/B assignment that the composition plan (`plan.rs`, spec §7.2) and
//! the frame recipe (`recipe.rs`) share.
//!
//! The plan and the recipe are the same timeline seen from two distances.
//! The PLAN is structural — which source ranges go on which composition
//! track, which instruction covers which span — and Swift rebuilds its
//! `AVMutableComposition` only when the plan's JSON string differs from the
//! one it built (spec §7.6, §11), so the assignment must be deterministic to
//! the byte: same project, same string. Everything here is assembled from
//! ordered walks over `Project::tracks` and `Project::clips_on_track`, never
//! from a hash map's iteration order.
//!
//! The RECIPE is per-instant and per-property, and lives in `recipe.rs`: it
//! changes on every property edit, which is exactly why it is not part of
//! the plan — a scale drag re-renders without rebuilding a composition.
//!
//! The two must agree on one thing — the composition track id a clip's
//! video lands on — because the recipe names a track by the id Swift passed
//! as `preferredTrackID`. So the A/B assignment is written once, in
//! [`Project::assign`], and both entry points call it. That is why it is
//! here and `pub(crate)`, along with [`Project::drawing_instances`], which
//! both the instruction tiling and the layer list are built from.
//!
//! Both are TOTAL: any project, any `t`, including a negative one, one past
//! the end, and one in a project with no clips at all.
//!
//! Neither works from `Project::clips` directly. What plays on a timeline
//! track is a list of [`Instance`]s (`nest.rs`): one per clip that actually
//! reaches the canvas or the mix, with a nest clip already replaced by the
//! clips inside it, times already in project time, extents already clipped.
//! A project with no nests gets exactly one instance per clip, so this is
//! not a second path — it is the only one.

use std::collections::BTreeMap;

use serde::Serialize;
use serde_json::{Map, Value};

use crate::audio::Voice;
use crate::edit_clip_timing::AUDIO_SPEED_MAX;
use crate::model::{Clip, Project, Source};
use crate::nest::{lifted, Instance};
use crate::speed_map::{peak_rate, SpeedMap};
use crate::speed_segments::{constant_ramp_audio, RampAudio};
use crate::time::{self, Ticks, TIMESCALE};

/// First video and first audio composition track id. Small, stable
/// integers: Swift creates each AVFoundation track with `preferredTrackID`
/// equal to one of these, and the recipe names a video source by the same
/// number (spec §7.2). The two ranges are far enough apart that a video and
/// an audio track can never collide, and an id read out of a plan is
/// self-describing in a log.
///
/// The audio range starts at 1001 and not the 101 of M1: two composition
/// tracks per timeline track was the ceiling only while every clip was its
/// own layer, and a nest contributes its own tracks on top of the timeline's.
/// The cap that bounds both is `MAX_TRACKS` = 64 counted across the timeline
/// AND every nest (`format::check_caps`), so at most 128 video ids can ever
/// be handed out — comfortably clear of 1001. A collision here would not be
/// subtle: `CompositionBuilder.makeTrack` throws on a duplicate
/// `preferredTrackID` rather than quietly renumbering.
const FIRST_VIDEO_TRACK_ID: u32 = 1;
const FIRST_AUDIO_TRACK_ID: u32 = 1001;

/// Serializes a plain data value, or `null` if it somehow cannot be — these
/// are all `#[derive(Serialize)]` structs of numbers, so the fallback is
/// unreachable, but nothing here may panic. Shared with `recipe.rs`, which
/// publishes the same kinds of value under the same rule.
pub(crate) fn json<T: Serialize>(value: &T) -> Value {
    serde_json::to_value(value).unwrap_or(Value::Null)
}

/// A float as JSON. `Value::from(f64)` turns a non-finite number into
/// `null`, which would fail to decode as a `Double` on the Swift side, so a
/// nonsense value becomes 0 and the frame still renders.
pub(crate) fn number(value: f64) -> Value {
    Value::from(if value.is_finite() { value } else { 0.0 })
}

// ---- the time-pitch algorithm -------------------------------------------

/// The time-pitch algorithm a plan audio segment plays at (spec §11 SY-26,
/// SY-39): keep pitch within ±0.1% of ×1 (not ×1 itself) is `off`
/// (varispeed, under 1.74 cents of pitch), keep pitch at a near-unity speed
/// outside that is `time_domain`, whose drift within a clip is bounded where
/// `spectral`'s grows; keep pitch elsewhere is `spectral`, and keep pitch off
/// is `off` (varispeed).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Pitch {
    Spectral,
    TimeDomain,
    Off,
}

/// The near-unity band, inclusive, in which keep pitch plays `time_domain`.
pub(crate) const PITCH_TIME_DOMAIN_MIN: f64 = 0.98;
pub(crate) const PITCH_TIME_DOMAIN_MAX: f64 = 1.02;

/// The band, inclusive, in which keep pitch plays `off` (spec §11 SY-39); ×1 excluded.
pub(crate) const PITCH_VARISPEED_MIN: f64 = 0.999;
pub(crate) const PITCH_VARISPEED_MAX: f64 = 1.001;

impl Pitch {
    pub(crate) fn of(keep_pitch: bool, speed: f64) -> Pitch {
        let varispeed =
            speed != 1.0 && (PITCH_VARISPEED_MIN..=PITCH_VARISPEED_MAX).contains(&speed);
        if !keep_pitch || varispeed {
            Pitch::Off
        } else if speed != 1.0 && (PITCH_TIME_DOMAIN_MIN..=PITCH_TIME_DOMAIN_MAX).contains(&speed) {
            Pitch::TimeDomain
        } else {
            Pitch::Spectral
        }
    }

    pub(crate) fn name(self) -> &'static str {
        match self {
            Pitch::Spectral => "spectral",
            Pitch::TimeDomain => "time_domain",
            Pitch::Off => "off",
        }
    }
}

// ---- the A/B assignment --------------------------------------------------

/// One clip's contribution to the composition: a source range placed at a
/// timeline range. `duration != source_duration` is Swift's signal to
/// follow the insert with `scaleTimeRange` (spec §7.2).
///
/// A ramped clip's ONE audio segment carries `ramp`, the map its rendered
/// sound follows (spec §11 SR-6, SR-10), and so does a constant media
/// clip's time-scaled Keep pitch off audio segment (SR-28,
/// [`Segment::with_constant_render`]); every other segment has none.
#[derive(Debug, Clone)]
pub(crate) struct Segment {
    clip: u32,
    media: u32,
    source_in: Ticks,
    source_duration: Ticks,
    start: Ticks,
    duration: Ticks,
    pitch: Pitch,
    ramp: Option<RampAudio>,
}

impl Segment {
    fn end(&self) -> Ticks {
        self.start.saturating_add(self.duration)
    }

    /// A constant `clip`'s AUDIO segment, carrying the two-point constant
    /// `ramp` when its sound is rendered offline (spec §11 SR-28): a
    /// `media` source, Keep pitch off, a duration above 0 and time-scaled.
    /// `pitch` stays `off`.
    fn with_constant_render(mut self, clip: &Clip) -> Segment {
        let media = matches!(clip.source, Source::Media { .. });
        let keep_pitch = clip.audio.map(|a| a.keep_pitch).unwrap_or(true);
        if media && !keep_pitch && self.duration > 0 && self.duration != self.source_duration {
            self.ramp = Some(constant_ramp_audio(
                self.source_in,
                self.source_duration,
                self.duration,
            ));
        }
        self
    }

    pub(crate) fn to_json(&self, audio: bool) -> Value {
        let mut out = Map::new();
        out.insert("clip".to_string(), Value::from(self.clip));
        out.insert("media".to_string(), Value::from(self.media));
        out.insert("source_in".to_string(), Value::from(self.source_in));
        out.insert(
            "source_duration".to_string(),
            Value::from(self.source_duration),
        );
        out.insert("start".to_string(), Value::from(self.start));
        out.insert("duration".to_string(), Value::from(self.duration));
        if audio {
            // The time-pitch algorithm name Swift sets on the segment when
            // a speed change would otherwise transpose the clip.
            out.insert("pitch".to_string(), Value::from(self.pitch.name()));
            if let Some(ramp) = &self.ramp {
                out.insert("ramp".to_string(), ramp.to_json());
            }
        }
        Value::Object(out)
    }
}

/// One composition track: an id Swift will use as `preferredTrackID`, and
/// the non-overlapping segments on it, in start order.
#[derive(Debug, Clone)]
pub(crate) struct CompTrack<'a> {
    pub(crate) id: u32,
    pub(crate) segments: Vec<Segment>,
    /// One per segment, in the same order, on an AUDIO track; empty on a
    /// video track, which needs no envelope. A segment alone cannot say how
    /// loud it is — a nested clip's props and its track are not reachable
    /// from `Project` by id — so the envelope is computed from these
    /// (`audio.rs`) rather than by looking the segments' clips back up.
    pub(crate) voices: Vec<Voice<'a>>,
}

/// The whole assignment. `video_of` is the bridge to the recipe.
#[derive(Debug, Clone, Default)]
pub(crate) struct Assignment<'a> {
    pub(crate) video: Vec<CompTrack<'a>>,
    pub(crate) audio: Vec<CompTrack<'a>>,
    /// instance path → video composition track id, for the recipe's `track`
    /// sources. Keyed by [`Instance::path`] and not by clip id, because two
    /// clips may show the same nest and its contents then play at two places
    /// on the timeline, on two different composition tracks. A `BTreeMap`
    /// rather than a `HashMap` so nothing about this module can depend on a
    /// randomized iteration order.
    pub(crate) video_of: BTreeMap<Vec<u32>, u32>,
}

/// Places `unit` — one clip's segments, in start order: one for a constant
/// clip, a ramped clip's every video segment — (and, on an audio track, the
/// `voice` that says how loud it is) on the first track whose last segment
/// ends at or before the unit's first, adding a track when none does — the
/// A/B assignment of spec §7.2 — and answers the id of the track it landed
/// on. A unit is never split across tracks, so the recipe names one track
/// for one instance (spec §11 SR-10).
///
/// With the overlap rule (§6: at most one neighbour per side, at most half
/// the shorter clip) two tracks per timeline track is the most a timeline
/// clip can ever need — six on an audio track whose overlapping clips mix
/// the three pitch names (`match_pitch` below). A nest clip is the exception: it stands for a whole
/// stack, so it needs as many as the nest's own tracks do.
///
/// With `match_pitch` (audio) a track is free only if its last segment has
/// the same `pitch`, so every plan audio track has ONE `pitch`, Swift's
/// first-segment read of it holds, and each clip keeps its own pitch setting
/// (spec §11 #190, #211).
fn place<'a>(
    tracks: &mut Vec<CompTrack<'a>>,
    next_id: &mut u32,
    unit: Vec<Segment>,
    voice: Option<Voice<'a>>,
    match_pitch: bool,
) -> u32 {
    let Some(first) = unit.first() else {
        return 0;
    };
    let free = tracks.iter().position(|t| {
        t.segments
            .last()
            .is_none_or(|s| s.end() <= first.start && (!match_pitch || s.pitch == first.pitch))
    });
    match free.and_then(|i| tracks.get_mut(i)) {
        Some(track) => {
            track.segments.extend(unit);
            track.voices.extend(voice);
            track.id
        }
        None => {
            let id = *next_id;
            *next_id = next_id.saturating_add(1);
            tracks.push(CompTrack {
                id,
                segments: unit,
                voices: voice.into_iter().collect(),
            });
            id
        }
    }
}

impl Project {
    /// The clip's source range, or `None` when it needs no composition
    /// track at all.
    ///
    /// Only `media` and `still` sources are DECODED: `image`, `text` and
    /// `shape` layers are drawn by the compositor from the recipe, a nest is
    /// never seen here at all (the walk replaced it with its contents), and
    /// a clip whose media is missing has no file to insert — it draws a
    /// slate instead (spec §7.3).
    fn segment_of(&self, clip: &Clip) -> Option<Segment> {
        let (media_id, source_in, source_duration) = match &clip.source {
            Source::Media { media, r#in, .. } => {
                let found = self.media(*media)?;
                // Timeline duration times speed IS the source range: at 2x
                // a 5 s clip consumes 10 s of source, and Swift scales the
                // inserted range back down to 5 s. ONE function says how
                // much that is (spec §11, D4-1).
                let length = self.content_length_in_source(clip);
                // The core's own ops no longer mint a window past the end
                // of a file: EVERY site that writes a media clip's window
                // reads one bound (spec §11, #22 and D4-2 to D4-5) —
                // `add_clip`'s whole length, `trim_end`, `roll`, `resnap`,
                // `set_speed`, `paste`'s two loops, `unnest`,
                // `relink_media`'s hold to a shorter file (#63) and
                // `add_background`'s plate. So this clamp is the LAST line
                // of defence rather than the ordinary path, and what still
                // reaches it is hand-written JSON putting `in` outside the
                // file, a document minted before those rules, and the
                // one-frame floor those writers apply after the bound, for
                // a media shorter than a frame (nothing in the schema
                // forbids any of it; `validate` polices ids and spans, not
                // source bounds). BOTH ends are clamped to what
                // the file holds, because handing AVFoundation a range that
                // starts or ends past an asset makes the insert throw —
                // clamped, it becomes a stretch of the last frame, which
                // renders.
                let last = found.duration.saturating_sub(1).max(0);
                let source_in = (*r#in).clamp(0, last);
                let remaining = found.duration.saturating_sub(source_in).max(0);
                (*media, source_in, length.min(remaining).max(1))
            }
            Source::Still { media, at } => {
                let found = self.media(*media)?;
                // The freeze-frame idiom (spec §7.2, §11): ONE source frame
                // inserted and scaled to the clip's whole duration. No
                // image is extracted, so a freeze costs nothing to build
                // and nothing to keep in memory.
                let frame = time::frame_duration(found.fps)
                    .or_else(|| time::frame_duration(self.canvas.fps))
                    // A media whose rate is unusable still has to freeze
                    // something: 1/30 s of source, scaled like any other.
                    .unwrap_or(TIMESCALE / 30)
                    .max(1);
                // Same clamp as the media arm, leaving room for the whole
                // frame: `freeze_frame` already places `at` inside the
                // file, but a hand-written still need not have.
                let last = found.duration.saturating_sub(frame).max(0);
                (*media, (*at).clamp(0, last), frame)
            }
            Source::Image { .. }
            | Source::Text
            | Source::Shape
            | Source::Graphic
            | Source::Nest { .. }
            | Source::Adjustment => return None,
        };

        Some(Segment {
            clip: clip.id,
            media: media_id,
            source_in,
            source_duration,
            start: clip.start,
            duration: clip.duration,
            // A structural fact about the segment, so it comes from the
            // base props: the time-pitch algorithm is chosen when the
            // composition is built, not per frame.
            pitch: Pitch::of(clip.audio.map(|a| a.keep_pitch).unwrap_or(true), clip.speed),
            ramp: None,
        })
    }

    /// A RAMPED clip's segments (spec §11 SR-10): its video segments, one
    /// per held piece and one per canvas frame inside each ramp
    /// (`speed_segments.rs`), and its one audio segment over the whole slot,
    /// `pitch` `off`, carrying the map. `clip` is the LIFTED clip, so a nest
    /// clip's tail cut truncates both. `None` for a missing media, which
    /// draws a slate as a constant clip's does.
    fn ramp_segments_of(&self, clip: &Clip, map: &SpeedMap) -> Option<(Vec<Segment>, Segment)> {
        let Source::Media { media, r#in, .. } = &clip.source else {
            return None;
        };
        let found = self.media(*media)?;
        // `segment_of`'s clamp, for the same reason.
        let last = found.duration.saturating_sub(1).max(0);
        let source_in = (*r#in).clamp(0, last);
        let piece =
            |start: Ticks, duration: Ticks, source_in: Ticks, source_duration: Ticks| Segment {
                clip: clip.id,
                media: *media,
                source_in,
                source_duration,
                start,
                duration,
                pitch: Pitch::Off,
                ramp: None,
            };
        let video = self
            .ramp_spans(clip, map, source_in, found.duration)
            .into_iter()
            .map(|s| piece(s.start, s.duration, s.source_in, s.source_duration))
            .collect();
        // D4-1's one reader: for a ramped clip it is S(duration) of this map.
        let length = self.content_length_in_source(clip);
        let remaining = found.duration.saturating_sub(source_in).max(0);
        let mut audio = piece(
            clip.start,
            clip.duration,
            source_in,
            length.min(remaining).max(1),
        );
        audio.ramp = Some(self.ramp_audio(clip, map, source_in));
        Some((video, audio))
    }

    /// Every clip's place in the composition (spec §7.2's A/B assignment).
    ///
    /// Timeline tracks are walked back to front and their instances in start
    /// order, and ids are handed out as tracks are needed, so the numbering
    /// is a pure function of the project — which is what lets Swift compare
    /// plan strings instead of diffing structures.
    ///
    /// Instances are sorted by start before they are placed, which the walk
    /// alone does not guarantee: a nest hands its clips over one inner track
    /// at a time, so a later track's early clip would otherwise find every
    /// existing composition track occupied and be given one of its own.
    /// Packing them in time order is not correctness — segments on a track
    /// never overlap either way — it is decodes: an extra composition track
    /// is an extra simultaneous decode for as long as it exists.
    pub(crate) fn assign(&self) -> Assignment<'_> {
        let mut assignment = Assignment::default();
        let mut next_video = FIRST_VIDEO_TRACK_ID;
        let mut next_audio = FIRST_AUDIO_TRACK_ID;

        for track in &self.tracks {
            let mut video: Vec<CompTrack> = Vec::new();
            let mut audio: Vec<CompTrack> = Vec::new();
            let mut instances = self.instances_on_track(track.id);
            // Cached: the key is a heap-allocated path, and re-deriving it on
            // every comparison would allocate through the whole sort.
            instances.sort_by_cached_key(|i| (i.start, i.path()));
            for instance in &instances {
                let clip = lifted(instance);
                if let Some(map) = SpeedMap::of(&clip) {
                    let Some((unit, sound)) = self.ramp_segments_of(&clip, &map) else {
                        continue;
                    };
                    let Some(media) = self.media(sound.media) else {
                        continue;
                    };
                    if media.has_video && instance.shows_video() && !unit.is_empty() {
                        let id = place(&mut video, &mut next_video, unit, None, false);
                        assignment.video_of.insert(instance.path(), id);
                    }
                    // The ×12 rule on the greatest rate the instance's own
                    // clip, unlifted, NAMES: the figure `SpeedAudioDrop`
                    // reads off the snapshot, so a nest clip's tail cut or
                    // a trimmed ramp cannot make the two disagree (spec
                    // §11 SR-10, SR-19 (d)).
                    let peak = peak_rate(instance.clip);
                    if media.has_audio && instance.plays_audio() && peak <= AUDIO_SPEED_MAX {
                        place(
                            &mut audio,
                            &mut next_audio,
                            vec![sound],
                            Some(Voice::of(&self.tracks, instance)),
                            true,
                        );
                    }
                    continue;
                }
                let Some(segment) = self.segment_of(&clip) else {
                    continue;
                };
                let Some(media) = self.media(segment.media) else {
                    continue;
                };
                if media.has_video && instance.shows_video() {
                    let id = place(
                        &mut video,
                        &mut next_video,
                        vec![segment.clone()],
                        None,
                        false,
                    );
                    assignment.video_of.insert(instance.path(), id);
                }
                // A `still` is a FROZEN PICTURE. Its segment is one source
                // frame scaled across the whole clip (spec §7.2), which is
                // the freeze-frame idiom for video and nonsense for sound:
                // a 1/30 s fragment smeared over seconds at full volume.
                // `freeze_frame` clears `enabled.audio` on the still it
                // makes, but `set_enabled` can put it back, so the
                // exclusion belongs here — with the assignment — and not in
                // the one op that happens to create stills.
                let frozen = matches!(instance.clip.source, Source::Still { .. });
                // A muted TRACK still contributes its audio segments: the
                // mute is a zero envelope (audio.rs), so unmuting is a
                // property edit and never rebuilds the composition. A solo
                // is the same envelope, judged against the container's
                // track set — which for the timeline is `self.tracks`, the
                // one set the instance does not carry. Above
                // `AUDIO_SPEED_MAX` a clip's audio is left out: an export's
                // loudness pass never finishes there (spec §11 #190).
                if media.has_audio
                    && instance.plays_audio()
                    && !frozen
                    && clip.speed <= AUDIO_SPEED_MAX
                {
                    place(
                        &mut audio,
                        &mut next_audio,
                        vec![segment.with_constant_render(&clip)],
                        Some(Voice::of(&self.tracks, instance)),
                        true,
                    );
                }
            }
            assignment.video.extend(video);
            assignment.audio.extend(audio);
        }
        assignment
    }

    /// Every instance that draws a layer, BACK TO FRONT: timeline track
    /// order (index 0 first), within a track by start, and a nest clip
    /// replaced in place by its own stack walked the same way (spec §7.3).
    ///
    /// One list serves both the recipe's layers and the plan's instruction
    /// boundaries, so the two can never disagree about what is visible.
    pub(crate) fn drawing_instances(&self) -> Vec<Instance<'_>> {
        let mut out = self.all_instances();
        out.retain(|i| i.shows_video() && self.draws(i.clip));
        out
    }

    /// Whether the clip's SOURCE puts anything on the canvas. A missing
    /// media draws a slate, so it counts; an audio-only file used as a
    /// media clip does not.
    ///
    /// A nest never reaches here as an instance — the walk replaced it with
    /// what is inside it — so that arm only answers for a nest clip whose
    /// nest id is dangling, which `validate` refuses and which draws
    /// nothing rather than a slate: the slate says "this file is missing",
    /// and no file is involved.
    fn draws(&self, clip: &Clip) -> bool {
        match &clip.source {
            Source::Media { media, .. } | Source::Still { media, .. } => {
                self.media(*media).is_none_or(|m| m.has_video)
            }
            // An adjustment clip draws by grading what is behind it
            // (spec §11 GR-6), so it is a drawing instance like a shape.
            Source::Image { .. }
            | Source::Text
            | Source::Shape
            | Source::Graphic
            | Source::Adjustment => true,
            Source::Nest { .. } => false,
        }
    }
}
