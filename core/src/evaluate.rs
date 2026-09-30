//! The composition plan (spec §7.2), and the A/B assignment it shares with
//! the frame recipe.
//!
//! The plan and the recipe are the same timeline seen from two distances.
//! The PLAN is structural — which source ranges go on which composition
//! track, which instruction covers which span — and Swift rebuilds its
//! `AVMutableComposition` only when the plan's JSON string differs from the
//! one it built (spec §7.6, §11), so this module must be deterministic to
//! the byte: same project, same string. Every object here is assembled from
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

use std::borrow::Cow;
use std::collections::BTreeMap;

use serde::Serialize;
use serde_json::{Map, Value};

use crate::audio::{Ducker, Voice};
use crate::model::{Clip, Project, Source};
use crate::nest::Instance;
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

/// The decoder budget. More than eight video composition tracks feeding one
/// instruction means eight simultaneous hardware decodes plus the
/// compositor's own work; past that, playback drops frames rather than
/// failing, so this is a warning in the plan and not a refusal.
const MAX_CONCURRENT_VIDEO_TRACKS: usize = 8;

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

// ---- the A/B assignment --------------------------------------------------

/// One clip's contribution to the composition: a source range placed at a
/// timeline range. `duration != source_duration` is Swift's signal to
/// follow the insert with `scaleTimeRange` (spec §7.2).
#[derive(Debug, Clone, Copy)]
struct Segment {
    clip: u32,
    media: u32,
    source_in: Ticks,
    source_duration: Ticks,
    start: Ticks,
    duration: Ticks,
    keep_pitch: bool,
}

impl Segment {
    fn end(&self) -> Ticks {
        self.start.saturating_add(self.duration)
    }

    fn to_json(self, audio: bool) -> Value {
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
            out.insert(
                "pitch".to_string(),
                Value::from(if self.keep_pitch { "spectral" } else { "off" }),
            );
        }
        Value::Object(out)
    }
}

/// One composition track: an id Swift will use as `preferredTrackID`, and
/// the non-overlapping segments on it, in start order.
#[derive(Debug, Clone)]
struct CompTrack<'a> {
    id: u32,
    segments: Vec<Segment>,
    /// One per segment, in the same order, on an AUDIO track; empty on a
    /// video track, which needs no envelope. A segment alone cannot say how
    /// loud it is — a nested clip's props and its track are not reachable
    /// from `Project` by id — so the envelope is computed from these
    /// (`audio.rs`) rather than by looking the segments' clips back up.
    voices: Vec<Voice<'a>>,
}

/// The whole assignment. `video_of` is the bridge to the recipe.
#[derive(Debug, Clone, Default)]
pub(crate) struct Assignment<'a> {
    video: Vec<CompTrack<'a>>,
    audio: Vec<CompTrack<'a>>,
    /// instance path → video composition track id, for the recipe's `track`
    /// sources. Keyed by [`Instance::path`] and not by clip id, because two
    /// clips may show the same nest and its contents then play at two places
    /// on the timeline, on two different composition tracks. A `BTreeMap`
    /// rather than a `HashMap` so nothing about this module can depend on a
    /// randomized iteration order.
    pub(crate) video_of: BTreeMap<Vec<u32>, u32>,
}

/// Places `segment` (and, on an audio track, the `voice` that says how loud
/// it is) on the first track whose last segment ends at or before it, adding
/// a track when none does — the A/B assignment of spec §7.2 — and answers
/// the id of the track it landed on.
///
/// With the overlap rule (§6: at most one neighbour per side, at most half
/// the shorter clip) two tracks per timeline track is the most a timeline
/// clip can ever need. A nest clip is the exception: it stands for a whole
/// stack, so it needs as many as the nest's own tracks do.
fn place<'a>(
    tracks: &mut Vec<CompTrack<'a>>,
    next_id: &mut u32,
    segment: Segment,
    voice: Option<Voice<'a>>,
) -> u32 {
    let free = tracks
        .iter()
        .position(|t| t.segments.last().is_none_or(|s| s.end() <= segment.start));
    match free.and_then(|i| tracks.get_mut(i)) {
        Some(track) => {
            track.segments.push(segment);
            track.voices.extend(voice);
            track.id
        }
        None => {
            let id = *next_id;
            *next_id = next_id.saturating_add(1);
            tracks.push(CompTrack {
                id,
                segments: vec![segment],
                voices: voice.into_iter().collect(),
            });
            id
        }
    }
}

/// The clip as the plan must see it: itself for a timeline clip, and a copy
/// placed at project time — shortened if the nest clip showing it ended
/// first — for a nested one.
///
/// Only the TAIL is ever cut, which is why there is no in-point arithmetic
/// here. The timeline gives its clips no window, so a nest clip is never
/// itself head-clipped, so its contents' first frames are never before the
/// window it hands them; the same argument then holds one level down. Give
/// `Source::Nest` an in point one day and this is where the `trim_start`
/// arithmetic belongs.
fn lifted<'a>(instance: &Instance<'a>) -> Cow<'a, Clip> {
    if instance.start == instance.clip.start && instance.duration() == instance.clip.duration {
        return Cow::Borrowed(instance.clip);
    }
    let mut clip = instance.clip.clone();
    clip.start = instance.start;
    clip.duration = instance.duration();
    Cow::Owned(clip)
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
            | Source::Nest { .. } => return None,
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
            keep_pitch: clip.audio.map(|a| a.keep_pitch).unwrap_or(true),
        })
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
                let Some(segment) = self.segment_of(&clip) else {
                    continue;
                };
                let Some(media) = self.media(segment.media) else {
                    continue;
                };
                if media.has_video && instance.shows_video() {
                    let id = place(&mut video, &mut next_video, segment, None);
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
                // one set the instance does not carry.
                if media.has_audio && instance.plays_audio() && !frozen {
                    place(
                        &mut audio,
                        &mut next_audio,
                        segment,
                        Some(Voice::of(&self.tracks, instance)),
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
            Source::Image { .. } | Source::Text | Source::Shape | Source::Graphic => true,
            Source::Nest { .. } => false,
        }
    }
}

// ---- the composition plan ------------------------------------------------

/// One entry of the instruction tiling, before it becomes JSON.
struct Instruction {
    start: Ticks,
    duration: Ticks,
    required: Vec<u32>,
}

impl Project {
    /// The composition plan (spec §7.2): everything structural Swift needs
    /// to build an `AVMutableComposition`, an `AVMutableAudioMix` and an
    /// `AVVideoComposition.Configuration`, and nothing that changes when a
    /// property does.
    ///
    /// Deterministic to the byte for a given project — Swift compares this
    /// string to the plan it last built and rebuilds only on a difference
    /// (spec §7.6).
    pub fn composition_plan(&self) -> Value {
        let assignment = self.assign();
        let duration = self.duration();

        let video_tracks: Vec<Value> = assignment
            .video
            .iter()
            .map(|track| {
                let mut out = Map::new();
                out.insert("id".to_string(), Value::from(track.id));
                out.insert(
                    "segments".to_string(),
                    Value::Array(track.segments.iter().map(|s| s.to_json(false)).collect()),
                );
                Value::Object(out)
            })
            .collect();

        // Ducking is a property of the whole project, so the duckers are
        // gathered once from the flattened timeline rather than per track:
        // `audio_ramps` drops the ones that are its own track's segments.
        let duckers: Vec<Ducker> = self.duckers(&self.all_instances());
        let audio_tracks: Vec<Value> = assignment
            .audio
            .iter()
            .map(|track| {
                let mut out = Map::new();
                out.insert("id".to_string(), Value::from(track.id));
                out.insert(
                    "segments".to_string(),
                    Value::Array(track.segments.iter().map(|s| s.to_json(true)).collect()),
                );
                // The envelope is computed from the voices, not the
                // segments: fades, actions, mute and ducking all live in the
                // model, audio.rs owns every one of them, and a nested
                // segment's clip cannot be looked back up by id.
                out.insert(
                    "ramps".to_string(),
                    Value::Array(
                        self.audio_ramps(&track.voices, &duckers)
                            .iter()
                            .map(json)
                            .collect(),
                    ),
                );
                Value::Object(out)
            })
            .collect();

        let instructions = self.instructions(&assignment, duration);
        let warnings = warnings_for(&instructions);

        let mut out = Map::new();
        out.insert("timescale".to_string(), Value::from(TIMESCALE));
        out.insert("duration".to_string(), Value::from(duration));
        out.insert(
            "fps".to_string(),
            Value::Array(vec![
                Value::from(self.canvas.fps.num),
                Value::from(self.canvas.fps.den),
            ]),
        );
        out.insert(
            "render_size".to_string(),
            Value::Array(vec![
                Value::from(self.canvas.width),
                Value::from(self.canvas.height),
            ]),
        );
        out.insert("video_tracks".to_string(), Value::Array(video_tracks));
        out.insert("audio_tracks".to_string(), Value::Array(audio_tracks));
        out.insert(
            "instructions".to_string(),
            Value::Array(
                instructions
                    .iter()
                    .map(|i| {
                        let mut entry = Map::new();
                        entry.insert("start".to_string(), Value::from(i.start));
                        entry.insert("duration".to_string(), Value::from(i.duration));
                        entry.insert(
                            "required_track_ids".to_string(),
                            Value::Array(i.required.iter().map(|id| Value::from(*id)).collect()),
                        );
                        Value::Object(entry)
                    })
                    .collect(),
            ),
        );
        out.insert(
            "warnings".to_string(),
            Value::Array(warnings.into_iter().map(Value::from).collect()),
        );
        Value::Object(out)
    }

    /// The instruction tiling: contiguous, non-overlapping spans covering
    /// `[0, duration]` with a boundary wherever the set of visible layers
    /// changes.
    ///
    /// AVFoundation REQUIRES the tiling — instructions that leave a hole or
    /// overlap are rejected outright — so spans where nothing is visible
    /// are covered too, with an empty `required_track_ids`. An empty
    /// project has no timeline to tile and gets no instructions.
    fn instructions(&self, assignment: &Assignment, duration: Ticks) -> Vec<Instruction> {
        if duration <= 0 {
            return Vec::new();
        }

        // The visible instances are gathered ONCE — the per-span test below
        // re-reads this small list rather than re-walking the project's
        // tracks and clips for every boundary. An INSTANCE's edges, not a
        // clip's: a clip inside a nest starts where the nest clip puts it
        // and ends where the nest clip cuts it off, and a boundary missed
        // here is a span whose first tick disagrees with the rest of it —
        // the one invariant the tiling rests on.
        let visible: Vec<(Ticks, Ticks, Option<u32>)> = self
            .drawing_instances()
            .iter()
            .map(|i| (i.start, i.end, assignment.video_of.get(&i.path()).copied()))
            .collect();

        let mut bounds: Vec<Ticks> = vec![0, duration];
        for (start, end, _) in &visible {
            bounds.push((*start).clamp(0, duration));
            bounds.push((*end).clamp(0, duration));
        }
        bounds.sort_unstable();
        bounds.dedup();

        let mut out: Vec<Instruction> = Vec::with_capacity(bounds.len());
        for pair in bounds.windows(2) {
            let (Some(&start), Some(&end)) = (pair.first(), pair.get(1)) else {
                continue;
            };
            if end <= start {
                continue;
            }
            // Every clip edge is a boundary, so membership at the span's
            // first tick holds for the whole span.
            let mut required: Vec<u32> = visible
                .iter()
                .filter(|(from, to, _)| *from <= start && start < *to)
                .filter_map(|(_, _, track)| *track)
                .collect();
            required.sort_unstable();
            required.dedup();
            out.push(Instruction {
                start,
                duration: end.saturating_sub(start),
                required,
            });
        }
        out
    }
}

/// The plan's `warnings`. One line for the first instruction over the
/// decoder budget plus a count of the rest: a long project can put hundreds
/// of instructions over it, and a plan carrying hundreds of near-identical
/// strings would be compared, stored and shown to the user for no gain.
fn warnings_for(instructions: &[Instruction]) -> Vec<String> {
    let over: Vec<&Instruction> = instructions
        .iter()
        .filter(|i| i.required.len() > MAX_CONCURRENT_VIDEO_TRACKS)
        .collect();
    let mut warnings = Vec::new();
    if let Some(first) = over.first() {
        warnings.push(format!(
            "{} video tracks are required at once (at {} ticks), more than the {} \
             simultaneous decodes playback can keep up with",
            first.required.len(),
            first.start,
            MAX_CONCURRENT_VIDEO_TRACKS
        ));
        if over.len() > 1 {
            warnings.push(format!(
                "{} more instructions are over the video track budget",
                over.len().saturating_sub(1)
            ));
        }
    }
    warnings
}
