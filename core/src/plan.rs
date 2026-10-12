//! The composition plan (spec §7.2): everything structural Swift needs to
//! build its composition, the instruction tiling, and the decoder-budget
//! warning. It is built on the A/B assignment in `evaluate.rs`, which the
//! frame recipe shares, and is deterministic to the byte for the reason
//! that module's doc gives. A pure move out of `evaluate.rs`, grading GR1.

use serde_json::{Map, Value};

use crate::audio::Ducker;
use crate::evaluate::{json, Assignment};
use crate::model::Project;
use crate::time::{Ticks, TIMESCALE};

/// The decoder budget. More than eight video composition tracks feeding one
/// instruction means eight simultaneous hardware decodes plus the
/// compositor's own work; past that, playback drops frames rather than
/// failing, so this is a warning in the plan and not a refusal.
const MAX_CONCURRENT_VIDEO_TRACKS: usize = 8;

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
                    Value::Array(
                        track
                            .segments
                            .iter()
                            .map(|s| self.video_segment(s.to_json(false)))
                            .collect(),
                    ),
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

    /// A video segment as the plan publishes it: with `input` — its media's
    /// Camera Log, `media_color.rs`'s `media_input` — ONLY when the media
    /// converts (spec §11 GR-16), so every other plan is byte-identical to
    /// the one before version 19. A segment with `input` makes its
    /// composition a converting one, and a plan change rebuilds it.
    fn video_segment(&self, mut segment: Value) -> Value {
        let media = segment
            .get("media")
            .and_then(Value::as_u64)
            .and_then(|id| u32::try_from(id).ok());
        if let (Some(media), Value::Object(segment)) = (media, &mut segment) {
            let input = self.media_input(media);
            if !input.is_null() {
                segment.insert("input".to_string(), input);
            }
        }
        segment
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
