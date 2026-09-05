//! The two things the platform actually consumes: the composition plan
//! (spec §7.2) and the frame recipe (spec §7.3).
//!
//! They are the same timeline seen from two distances. The PLAN is
//! structural — which source ranges go on which composition track, which
//! instruction covers which span — and Swift rebuilds its
//! `AVMutableComposition` only when the plan's JSON string differs from the
//! one it built (spec §7.6, §11), so this module must be deterministic to
//! the byte: same project, same string. Every object here is assembled from
//! ordered walks over `Project::tracks` and `Project::clips_on_track`, never
//! from a hash map's iteration order.
//!
//! The RECIPE is per-instant and per-property: the back-to-front layer list
//! with every value already resolved through actions, asked for once per
//! composed frame by `Compositor` and again by the canvas overlay for
//! hit-testing. It changes on every property edit, which is exactly why it
//! is NOT part of the plan: a scale drag re-renders without rebuilding a
//! composition.
//!
//! The two must agree on one thing — the composition track id a clip's
//! video lands on — because the recipe names a track by the id Swift passed
//! as `preferredTrackID`. So the A/B assignment is written once, in
//! [`Project::assign`], and both entry points call it.
//!
//! Both are TOTAL: any project, any `t`, including a negative one, one past
//! the end, and one in a project with no clips at all.

use std::collections::BTreeMap;

use serde::Serialize;
use serde_json::{Map, Value};

use crate::actions::Evaluated;
use crate::model::{Clip, Project, Source};
use crate::time::{self, Ticks, TIMESCALE};

/// First video and first audio composition track id. Small, stable
/// integers: Swift creates each AVFoundation track with `preferredTrackID`
/// equal to one of these, and the recipe names a video source by the same
/// number (spec §7.2). The two ranges are far enough apart that a video and
/// an audio track can never collide, and an id read out of a plan is
/// self-describing in a log.
const FIRST_VIDEO_TRACK_ID: u32 = 1;
const FIRST_AUDIO_TRACK_ID: u32 = 101;

/// The decoder budget. More than eight video composition tracks feeding one
/// instruction means eight simultaneous hardware decodes plus the
/// compositor's own work; past that, playback drops frames rather than
/// failing, so this is a warning in the plan and not a refusal.
const MAX_CONCURRENT_VIDEO_TRACKS: usize = 8;

/// FNV-1a, 64-bit. A CACHE KEY, not a security digest: Swift keys its
/// rendered text and shape textures by this hex string, so all that is
/// asked of it is that the same description always produces the same key
/// and that two different descriptions rarely collide. FNV is a dozen lines
/// with no dependency, which is the whole reason it is here rather than a
/// real hash crate.
const FNV_OFFSET: u64 = 0xcbf2_9ce4_8422_2325;
const FNV_PRIME: u64 = 0x0000_0100_0000_01b3;

fn fnv1a(bytes: &[u8]) -> u64 {
    let mut hash = FNV_OFFSET;
    for byte in bytes {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(FNV_PRIME);
    }
    hash
}

/// The content hash of a rendered layer's description. Hashing the
/// serialized `Value` is what makes it canonical: `serde_json` writes an
/// object's keys in one fixed order, so two clips with identical text
/// always hash the same and share one texture.
fn content_hash(description: &Value) -> String {
    format!("{:016x}", fnv1a(description.to_string().as_bytes()))
}

/// Serializes a plain data value, or `null` if it somehow cannot be — these
/// are all `#[derive(Serialize)]` structs of numbers, so the fallback is
/// unreachable, but nothing here may panic.
fn json<T: Serialize>(value: &T) -> Value {
    serde_json::to_value(value).unwrap_or(Value::Null)
}

/// A float as JSON. `Value::from(f64)` turns a non-finite number into
/// `null`, which would fail to decode as a `Double` on the Swift side, so a
/// nonsense value becomes 0 and the frame still renders.
fn number(value: f64) -> Value {
    Value::from(if value.is_finite() { value } else { 0.0 })
}

fn clip_end(clip: &Clip) -> Ticks {
    clip.start.saturating_add(clip.duration)
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
struct CompTrack {
    id: u32,
    segments: Vec<Segment>,
}

/// The whole assignment. `video_of` is the bridge to the recipe.
#[derive(Debug, Clone, Default)]
struct Assignment {
    video: Vec<CompTrack>,
    audio: Vec<CompTrack>,
    /// clip id → video composition track id, for the recipe's `track`
    /// sources. A `BTreeMap` rather than a `HashMap` so nothing about this
    /// module can depend on a randomized iteration order.
    video_of: BTreeMap<u32, u32>,
}

/// Places `segment` on the first track whose last segment ends at or before
/// it, adding a track when none does — the A/B assignment of spec §7.2.
/// With the overlap rule (§6: at most one neighbour per side, at most half
/// the shorter clip) two tracks per timeline track is the most this can
/// ever allocate.
fn place(tracks: &mut Vec<CompTrack>, next_id: &mut u32, segment: Segment) {
    let free = tracks
        .iter()
        .position(|t| t.segments.last().is_none_or(|s| s.end() <= segment.start));
    match free.and_then(|i| tracks.get_mut(i)) {
        Some(track) => track.segments.push(segment),
        None => {
            let id = *next_id;
            *next_id = next_id.saturating_add(1);
            tracks.push(CompTrack {
                id,
                segments: vec![segment],
            });
        }
    }
}

impl Project {
    /// The clip's source range, or `None` when it needs no composition
    /// track at all.
    ///
    /// Only `media` and `still` sources are DECODED: `image`, `text` and
    /// `shape` layers are drawn by the compositor from the recipe, and a
    /// clip whose media is missing has no file to insert — it draws a slate
    /// instead (spec §7.3).
    fn segment_of(&self, clip: &Clip) -> Option<Segment> {
        let (media_id, source_in, source_duration) = match &clip.source {
            Source::Media { media, r#in } => {
                let found = self.media(*media)?;
                // Timeline duration times speed IS the source range: at 2x
                // a 5 s clip consumes 10 s of source, and Swift scales the
                // inserted range back down to 5 s.
                let scaled = clip.duration as f64 * clip.speed;
                let length = if scaled.is_finite() && scaled > 0.0 {
                    // The cast saturates rather than wrapping, so an absurd
                    // speed cannot produce a negative range.
                    scaled.round() as Ticks
                } else {
                    clip.duration
                };
                // A clip may outrun its source, and hand-written JSON may
                // put its `in` outside the file altogether (nothing in the
                // schema forbids either; `validate` polices ids and spans,
                // not source bounds). BOTH ends are clamped to what the
                // file holds, because handing AVFoundation a range that
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
            Source::Image { .. } | Source::Text | Source::Shape | Source::Nest { .. } => {
                return None
            }
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
    /// Timeline tracks are walked back to front and their clips in start
    /// order, and ids are handed out as tracks are needed, so the numbering
    /// is a pure function of the project — which is what lets Swift compare
    /// plan strings instead of diffing structures.
    fn assign(&self) -> Assignment {
        let mut assignment = Assignment::default();
        let mut next_video = FIRST_VIDEO_TRACK_ID;
        let mut next_audio = FIRST_AUDIO_TRACK_ID;

        for track in &self.tracks {
            let mut video: Vec<CompTrack> = Vec::new();
            let mut audio: Vec<CompTrack> = Vec::new();
            for clip in self.clips_on_track(track.id) {
                let Some(segment) = self.segment_of(clip) else {
                    continue;
                };
                let Some(media) = self.media(segment.media) else {
                    continue;
                };
                if media.has_video && clip.enabled.video && !track.hidden {
                    place(&mut video, &mut next_video, segment);
                }
                // A `still` is a FROZEN PICTURE. Its segment is one source
                // frame scaled across the whole clip (spec §7.2), which is
                // the freeze-frame idiom for video and nonsense for sound:
                // a 1/30 s fragment smeared over seconds at full volume.
                // `freeze_frame` clears `enabled.audio` on the still it
                // makes, but `set_enabled` can put it back, so the
                // exclusion belongs here — with the assignment — and not in
                // the one op that happens to create stills.
                let frozen = matches!(clip.source, Source::Still { .. });
                // A muted TRACK still contributes its audio segments: the
                // mute is a zero envelope (audio.rs), so unmuting is a
                // property edit and never rebuilds the composition.
                if media.has_audio && clip.enabled.audio && !frozen {
                    place(&mut audio, &mut next_audio, segment);
                }
            }
            for comp in &video {
                for segment in &comp.segments {
                    assignment.video_of.insert(segment.clip, comp.id);
                }
            }
            assignment.video.extend(video);
            assignment.audio.extend(audio);
        }
        assignment
    }

    /// Every clip that draws a layer, BACK TO FRONT: timeline track order
    /// (index 0 first), and within a track by start (spec §7.3).
    ///
    /// One list serves both the recipe's layers and the plan's instruction
    /// boundaries, so the two can never disagree about what is visible.
    fn drawing_clips(&self) -> Vec<&Clip> {
        let mut out: Vec<&Clip> = Vec::new();
        for track in &self.tracks {
            if track.hidden {
                continue;
            }
            for clip in self.clips_on_track(track.id) {
                if clip.enabled.video && self.draws(clip) {
                    out.push(clip);
                }
            }
        }
        out
    }

    /// Whether the clip's SOURCE puts anything on the canvas. A missing
    /// media draws a slate, so it counts; an audio-only file used as a
    /// media clip does not; a nested project is M3 and draws nothing yet.
    fn draws(&self, clip: &Clip) -> bool {
        match &clip.source {
            Source::Media { media, .. } | Source::Still { media, .. } => {
                self.media(*media).is_none_or(|m| m.has_video)
            }
            Source::Image { .. } | Source::Text | Source::Shape => true,
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
    /// `AVMutableVideoComposition`, and nothing that changes when a
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

        let audio_tracks: Vec<Value> = assignment
            .audio
            .iter()
            .map(|track| {
                // The envelope is computed from the clips, not the
                // segments: fades, actions and ducking all live in the
                // model, and audio.rs owns every one of them.
                let clips: Vec<&Clip> = track
                    .segments
                    .iter()
                    .filter_map(|s| self.clip(s.clip))
                    .collect();
                let mut out = Map::new();
                out.insert("id".to_string(), Value::from(track.id));
                out.insert(
                    "segments".to_string(),
                    Value::Array(track.segments.iter().map(|s| s.to_json(true)).collect()),
                );
                out.insert(
                    "ramps".to_string(),
                    Value::Array(self.audio_ramps(&clips).iter().map(json).collect()),
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

        // The visible clips are gathered ONCE — the per-span test below
        // re-reads this small list rather than re-walking the project's
        // tracks and clips for every boundary.
        let visible: Vec<(Ticks, Ticks, Option<u32>)> = self
            .drawing_clips()
            .iter()
            .map(|c| {
                (
                    c.start,
                    clip_end(c),
                    assignment.video_of.get(&c.id).copied(),
                )
            })
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

// ---- the frame recipe ----------------------------------------------------

impl Project {
    /// The frame recipe at project time `t` (spec §7.3): the back-to-front
    /// layer list, every property already resolved through actions.
    ///
    /// A layer appears when `t` is inside `[start, start + duration)` — the
    /// half-open range that makes a cut show exactly one clip on the frame
    /// they share — its track is not hidden, and `enabled.video` is set.
    /// During a transition both clips are present and adjacent, each
    /// carrying the same kind and progress with opposite roles, because
    /// they are neighbours on one track and the layer list keeps track
    /// order.
    ///
    /// Total: `t` may be negative or past the end, and either simply
    /// produces no layers.
    pub fn frame_recipe(&self, t: Ticks) -> Value {
        let assignment = self.assign();

        let layers: Vec<Value> = self
            .drawing_clips()
            .into_iter()
            .filter(|c| c.start <= t && t < clip_end(c))
            .map(|clip| self.layer(clip, t, &assignment))
            .collect();

        let mut canvas = Map::new();
        canvas.insert("width".to_string(), Value::from(self.canvas.width));
        canvas.insert("height".to_string(), Value::from(self.canvas.height));
        canvas.insert(
            "background".to_string(),
            Value::Array(self.canvas.background.iter().map(|c| number(*c)).collect()),
        );

        let mut out = Map::new();
        out.insert("t".to_string(), Value::from(t));
        out.insert("canvas".to_string(), Value::Object(canvas));
        out.insert("layers".to_string(), Value::Array(layers));
        Value::Object(out)
    }

    /// One layer of the recipe.
    fn layer(&self, clip: &Clip, t: Ticks, assignment: &Assignment) -> Value {
        // Clip time: 0 is the clip's first frame, which is what actions are
        // measured in (spec §5.4).
        let evaluated = self.evaluate_clip(clip, t.saturating_sub(clip.start));
        let video = &evaluated.video;
        let (source, source_size) = self.layer_source(clip, &evaluated, assignment);

        let transition = match self.transition_at(clip.id, t) {
            Some((kind, progress, incoming, partner)) => {
                let mut entry = Map::new();
                entry.insert("kind".to_string(), json(&kind));
                entry.insert("progress".to_string(), number(progress));
                entry.insert(
                    "role".to_string(),
                    Value::from(if incoming { "in" } else { "out" }),
                );
                entry.insert("partner".to_string(), Value::from(partner));
                Value::Object(entry)
            }
            None => Value::Null,
        };

        let mut out = Map::new();
        out.insert("clip".to_string(), Value::from(clip.id));
        out.insert("source".to_string(), source);
        out.insert("source_size".to_string(), source_size);
        out.insert("crop".to_string(), json(&video.crop));
        out.insert("x".to_string(), number(video.x));
        out.insert("y".to_string(), number(video.y));
        out.insert("scale".to_string(), number(video.scale));
        out.insert("rotation".to_string(), number(video.rotation));
        out.insert("opacity".to_string(), number(video.opacity));
        out.insert("corner_radius".to_string(), number(video.corner_radius));
        out.insert("shadow".to_string(), json(&video.shadow));
        out.insert("color".to_string(), json(&video.color));
        out.insert("chroma".to_string(), json(&video.chroma));
        out.insert("transition".to_string(), transition);
        Value::Object(out)
    }

    /// A layer's `source` and `source_size`.
    ///
    /// `track` means "sample composition video track N", the id the plan
    /// gave this clip; `image` means "decode this media with ImageIO";
    /// `text` and `shape` carry the resolved description plus the content
    /// hash Swift caches the rendered texture by; `missing` is the slate
    /// (spec §7.3).
    ///
    /// **The `missing` arms are defensive, not a feature path.** They fire
    /// for a clip whose media id is not in `media[]`, and
    /// [`Project::validate`] refuses exactly that, so no project the FFI
    /// can hand out reaches them. Spec §5.6's missing media is the FILE
    /// being gone with the `media[]` entry intact — the core has no
    /// filesystem, so it cannot see that; Swift substitutes the same
    /// `missing` source when an asset fails to load. Keeping these arms
    /// means one vocabulary for the slate rather than two, and means a
    /// future reader that tolerates a dangling id renders instead of
    /// panicking.
    fn layer_source(
        &self,
        clip: &Clip,
        evaluated: &Evaluated,
        assignment: &Assignment,
    ) -> (Value, Value) {
        let media_size = |media: u32| -> Value {
            match self.media(media) {
                Some(m) => Value::Array(vec![Value::from(m.width), Value::from(m.height)]),
                None => Value::Null,
            }
        };

        match &clip.source {
            Source::Media { media, .. } | Source::Still { media, .. } => {
                match assignment.video_of.get(&clip.id) {
                    Some(track_id) => {
                        let mut source = Map::new();
                        source.insert("kind".to_string(), Value::from("track"));
                        source.insert("track_id".to_string(), Value::from(*track_id));
                        (Value::Object(source), media_size(*media))
                    }
                    // Reachable only for media the project does not have:
                    // `drawing_clips` already dropped the clips whose media
                    // exists but carries no video.
                    None => (missing_source(), Value::Null),
                }
            }
            Source::Image { media } => {
                if self.is_missing_media(*media) {
                    return (missing_source(), Value::Null);
                }
                let mut source = Map::new();
                source.insert("kind".to_string(), Value::from("image"));
                source.insert("media".to_string(), Value::from(*media));
                (Value::Object(source), media_size(*media))
            }
            Source::Text => {
                // A text clip with no description is malformed rather than
                // impossible; the defaults keep the recipe renderable.
                let text = evaluated.text.clone().unwrap_or_default();
                let description = json(&text);
                let mut source = Map::new();
                source.insert("kind".to_string(), Value::from("text"));
                source.insert("hash".to_string(), Value::from(content_hash(&description)));
                source.insert("text".to_string(), description);
                // Only the platform can lay text out, so the model has no
                // size to report (spec §5.3, §11).
                (Value::Object(source), Value::Null)
            }
            Source::Shape => {
                let shape = evaluated.shape.clone().unwrap_or_default();
                let description = json(&shape);
                let mut source = Map::new();
                source.insert("kind".to_string(), Value::from("shape"));
                source.insert("hash".to_string(), Value::from(content_hash(&description)));
                source.insert("shape".to_string(), description);
                let size = Value::Array(vec![number(shape.width), number(shape.height)]);
                (Value::Object(source), size)
            }
            // Nesting is M3; `drawing_clips` filters these out, so this arm
            // exists only to keep the match exhaustive.
            Source::Nest { .. } => (missing_source(), Value::Null),
        }
    }
}

fn missing_source() -> Value {
    let mut source = Map::new();
    source.insert("kind".to_string(), Value::from("missing"));
    Value::Object(source)
}
