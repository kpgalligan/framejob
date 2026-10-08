//! Tracks, markers and the media list — spec §6, table
//! "Tracks, markers, canvas, media".
//!
//! One `impl Project` block for everything a clip sits *in* rather than
//! everything a clip *is*: the track stack, the marker list, and the media
//! the clips point at. The fourth member of that table's row, the canvas,
//! is `edit_canvas.rs`, cut out of here under the size rule; `edit_clip.rs`
//! owns the clips themselves; the rules both obey are written there and called from
//! here — [`Project::snapped`] for every tick argument, [`Project::finish`]
//! as the single exit that turns an identity result into
//! [`Outcome::Identity`] and a broken invariant into `Err`.
//!
//! Three invariants this module is responsible for:
//!
//! 1. **A project always has at least one track.** Removing the last one
//!    refuses; `remove_empty_tracks` keeps the back-most.
//! 2. **Two markers never share a tick.** A marker is how the user names a
//!    moment, and two at one moment is a UI the timeline cannot draw. The
//!    op that would create the collision is an `Err` naming the time.
//! 3. **One media entry per path.** Re-importing a file already in the
//!    project changes nothing; the clips reference the entry that is
//!    already there.

use serde_json::Value;

use crate::export::describe;
use crate::model::{
    Clip, Marker, Media, MediaKind, MediaOriginal, Project, Source, Track, TrackMatte,
    DEFAULT_MARKER_COLOR,
};
use crate::outcome::Outcome;
use crate::time::Ticks;

/// Media dimension ceiling. Nothing decodes at this size — it exists so a
/// probe that reports garbage (or a hand-written project) cannot put a
/// number in the document that later overflows a texture allocation or
/// collapses `fit_scale` to zero.
const MEDIA_DIMENSION_MAX: u32 = 65536;

/// The keys a media descriptor may carry: the spec §5.2 `media[]` element
/// MINUS `id`. Spelled out rather than derived from a serialized [`Media`],
/// because the point of the list is to NAME a misspelled key — serde would
/// silently drop `"widht"` and leave the user with a zero-width media.
/// `edit_relink.rs` reads it too, for a relink's probe.
pub(crate) const MEDIA_KEYS: [&str; 11] = [
    "path",
    "bookmark",
    "kind",
    "duration",
    "width",
    "height",
    "fps",
    "has_video",
    "has_audio",
    "has_alpha",
    "original",
];

// ---- helpers -------------------------------------------------------------

/// Whether `clip` shows `media`. The three media-bound sources name an id;
/// text, shape and nest do not (spec §5.2) — a nest clip shows a GROUP, and
/// what that group references is asked of its own clips, which live in the
/// same id space and are swept alongside the timeline's.
fn uses_media(clip: &Clip, media: u32) -> bool {
    matches!(
        clip.source,
        Source::Media { media: id, .. } | Source::Still { media: id, .. } | Source::Image { media: id }
            if id == media
    )
}

/// The clips of a `with_clips` refusal, as English (deepening D2·3).
///
/// Both refusals that `with_clips` is the way past — a track that still
/// holds clips and a media a clip still shows — name the clips a caller
/// would otherwise have to ask for, so this is written once. At most three
/// ids are listed and the rest are a count: a media used by two hundred
/// clips would otherwise answer with a sentence nothing could read, and the
/// first three plus the total is everything the caller acts on.
/// Both callers ask only when they have at least one, and the empty arm is
/// here anyway: `split_last` rather than `some[..len - 1]`, because the
/// index form underflows on an empty slice and the crate's rule is that no
/// input may panic (`core/CLAUDE.md`, Errors). A third caller that forgets
/// the guard gets a poor sentence rather than a caught panic.
fn clip_list(ids: &[u32]) -> String {
    let named: Vec<String> = ids.iter().take(3).map(|id| id.to_string()).collect();
    let rest = ids.len().saturating_sub(named.len());
    match (named.split_last(), rest) {
        (None, _) => "no clips".to_string(),
        (Some((last, [])), 0) => format!("clip {last}"),
        (Some((last, front)), 0) => format!("clips {} and {last}", front.join(", ")),
        (Some(_), more) => format!("clips {} and {more} more", named.join(", ")),
    }
}

/// A media's `original` as it is stored (spec §11 #228-O): the path
/// trimmed, and a blank bookmark dropped, for the reason `add_media` drops
/// a blank media bookmark. An empty path is left for `check_media_fields`
/// to refuse by name. `add_media` and a relink's probe both read it.
pub(crate) fn normalize_original(original: Option<MediaOriginal>) -> Option<MediaOriginal> {
    original.map(|given| MediaOriginal {
        path: given.path.trim().to_string(),
        bookmark: given.bookmark.filter(|b| !b.trim().is_empty()),
    })
}

/// The checks a media record's fields must pass once the descriptor has
/// matched the schema — `add_media`'s, and a relink probe's
/// (`edit_relink.rs`), in one order and one set of sentences: an empty
/// path, a negative duration, a media with pixels whose size or rate is not
/// usable, an original with an empty path.
pub(crate) fn check_media_fields(media: &Media) -> Result<(), String> {
    if media.path.trim().is_empty() {
        return Err("media path must not be empty".to_string());
    }
    if media.duration < 0 {
        return Err(format!(
            "media duration must not be negative, not {}",
            media.duration
        ));
    }
    // Size and rate are only meaningful for a media with pixels: an
    // audio file legitimately reports 0×0. A drawing media with a zero
    // dimension would make `fit_scale` and the frame recipe's
    // `source_size` meaningless.
    let draws = media.has_video || matches!(media.kind, MediaKind::Image);
    if draws {
        if media.width == 0 || media.height == 0 {
            return Err(format!(
                "a media with pixels must have a positive width and height, not {}x{}",
                media.width, media.height
            ));
        }
        if media.width > MEDIA_DIMENSION_MAX || media.height > MEDIA_DIMENSION_MAX {
            return Err(format!(
                "media dimensions must be at most {MEDIA_DIMENSION_MAX}, not {}x{}",
                media.width, media.height
            ));
        }
    }
    if media.has_video && !media.fps.is_valid() {
        return Err(format!(
            "a media with video must have a frame rate with non-zero terms, not [{}, {}]",
            media.fps.num, media.fps.den
        ));
    }
    if media
        .original
        .as_ref()
        .is_some_and(|original| original.path.trim().is_empty())
    {
        return Err("media original path must not be empty".to_string());
    }
    Ok(())
}

// ---- the ops -------------------------------------------------------------

impl Project {
    fn require_marker(&self, id: u32) -> Result<&Marker, String> {
        self.marker(id)
            .ok_or_else(|| format!("no marker with id {id}"))
    }

    // ---- tracks ----------------------------------------------------------

    /// Inserts a track at `index`, where 0 is the BACK-most (bottom) layer
    /// and `tracks.len()` is the front; `None` means the front, which is
    /// where a new layer goes (spec §6).
    ///
    /// The default name is `Track <count + 1>` — named by the count, not by
    /// the index, so inserting in the middle does not renumber the tracks
    /// above it under the user. A name of only whitespace is treated as
    /// absent. `Err` for an index past the end, or (through `finish`) for
    /// exceeding the track cap.
    pub fn add_track(&self, index: Option<usize>, name: Option<&str>) -> Result<Outcome, String> {
        let at = match index {
            None => self.tracks.len(),
            Some(given) if given <= self.tracks.len() => given,
            Some(given) => {
                return Err(format!(
                    "track index {given} is out of range (0..={})",
                    self.tracks.len()
                ))
            }
        };

        let mut next = self.clone();
        let id = next.allocate_id();
        let name = name
            .map(str::trim)
            .filter(|given| !given.is_empty())
            .map(|given| given.to_string())
            .unwrap_or_else(|| format!("Track {}", next.tracks.len().saturating_add(1)));
        next.tracks.insert(
            at,
            Track {
                id,
                name,
                hidden: false,
                muted: false,
                locked: false,
                solo: false,
                matte: TrackMatte::None,
            },
        );
        self.finish(next)
    }

    /// Removes a track. Refuses on a track that still holds clips unless
    /// `with_clips`, which removes those clips with it, and refuses to
    /// remove the LAST track: a project always has somewhere to put a clip,
    /// and an empty track stack is a UI with nothing to drop onto.
    ///
    /// Both refusals carry their own sentence. The last-track one is asked
    /// FIRST, because `with_clips: true` is the way past the other and past
    /// this one it is not: a caller told about the clips would send it and
    /// be refused again.
    ///
    /// `Err` only for an unknown track.
    pub fn remove_track(&self, track: u32, with_clips: bool) -> Result<Outcome, String> {
        self.require_track(track)?;
        if self.tracks.len() <= 1 {
            return Ok(Outcome::Refused(format!(
                "track {track} is the only track left, and a project must always have one"
            )));
        }
        let held: Vec<u32> = self
            .clips
            .iter()
            .filter(|c| c.track == track)
            .map(|c| c.id)
            .collect();
        if !held.is_empty() && !with_clips {
            return Ok(Outcome::Refused(format!(
                "track {track} still holds {}; pass with_clips: true to remove the track \
                 and its clips",
                clip_list(&held)
            )));
        }

        let mut next = self.clone();
        next.tracks.retain(|t| t.id != track);
        next.clips.retain(|c| c.track != track);
        self.finish(next)
    }

    /// Moves a track to `index` in the stack (0 = back-most), sliding the
    /// tracks it passes over the other way — the layer reorder the timeline
    /// drag makes (spec §6).
    ///
    /// `Err` for an unknown track or an index past the end; an identity
    /// when the track is already there.
    pub fn move_track(&self, track: u32, index: usize) -> Result<Outcome, String> {
        let from = self.require_track_index(track)?;
        if index >= self.tracks.len() {
            return Err(format!(
                "track index {index} is out of range (0..{})",
                self.tracks.len()
            ));
        }
        if index == from {
            return Ok(Outcome::Identity);
        }

        let mut next = self.clone();
        // `from` came from `track_index`, so it addresses a track that is
        // there; `index` was just bounds-checked against the same list.
        let moved = next.tracks.remove(from);
        next.tracks.insert(index, moved);
        self.finish(next)
    }

    /// Sets any subset of a track's fields; an omitted argument keeps its
    /// value (spec §6). The name is stored trimmed, and an empty name is
    /// allowed — it means "unnamed", and the timeline draws the track's
    /// position instead. `matte` makes the track a matte for the track
    /// directly behind it, `none` an ordinary track again (spec §11 MT-1);
    /// re-choosing the current mode is an identity through `finish`, like
    /// every other unchanged field.
    #[allow(clippy::too_many_arguments)]
    pub fn set_track(
        &self,
        track: u32,
        name: Option<&str>,
        hidden: Option<bool>,
        muted: Option<bool>,
        locked: Option<bool>,
        solo: Option<bool>,
        matte: Option<TrackMatte>,
    ) -> Result<Outcome, String> {
        self.require_track(track)?;
        let mut next = self.clone();
        if let Some(found) = next.tracks.iter_mut().find(|t| t.id == track) {
            if let Some(name) = name {
                found.name = name.trim().to_string();
            }
            if let Some(hidden) = hidden {
                found.hidden = hidden;
            }
            if let Some(muted) = muted {
                found.muted = muted;
            }
            if let Some(locked) = locked {
                found.locked = locked;
            }
            if let Some(solo) = solo {
                found.solo = solo;
            }
            if let Some(matte) = matte {
                found.matte = matte;
            }
        }
        self.finish(next)
    }

    /// Removes every track that holds no clips — the tidy-up after a big
    /// delete (spec §6).
    ///
    /// If that would empty the stack, the back-most track survives: it is
    /// the one a fresh project starts with, and keeping the bottom of the
    /// stack means the surviving track is where a drop lands.
    pub fn remove_empty_tracks(&self) -> Result<Outcome, String> {
        let mut next = self.clone();
        next.tracks
            .retain(|t| self.clips.iter().any(|c| c.track == t.id));
        if next.tracks.is_empty() {
            next.tracks = self.tracks.iter().take(1).cloned().collect();
        }
        self.finish(next)
    }

    // ---- markers ---------------------------------------------------------

    /// Adds a marker at `at`, snapped to the frame grid and clamped to 0 —
    /// a drag can start left of the timeline, and there is no negative time
    /// (spec §6).
    ///
    /// The default name is `Marker <count + 1>` and the default colour is
    /// `"red"`. `Err` when another marker already holds the tick: two
    /// markers may not share a time, and moving the existing one is the
    /// caller's decision, not this op's.
    pub fn add_marker(
        &self,
        at: Ticks,
        name: Option<&str>,
        chapter: Option<bool>,
        color: Option<&str>,
    ) -> Result<Outcome, String> {
        let at = self.snapped(at).max(0);
        if let Some(existing) = self.markers.iter().find(|m| m.time == at) {
            return Err(format!("marker {} is already at {at} ticks", existing.id));
        }

        let mut next = self.clone();
        let id = next.allocate_id();
        let name = name
            .map(|given| given.trim().to_string())
            .unwrap_or_else(|| format!("Marker {}", next.markers.len().saturating_add(1)));
        let color = color
            .map(str::trim)
            .filter(|given| !given.is_empty())
            .unwrap_or(DEFAULT_MARKER_COLOR)
            .to_string();
        next.markers.push(Marker {
            id,
            time: at,
            name,
            color,
            chapter: chapter.unwrap_or(false),
        });
        self.finish(next)
    }

    /// Sets any subset of a marker's fields; an omitted argument keeps its
    /// value. A new time is snapped and clamped to 0 like `add_marker`'s,
    /// and collides with another marker the same way (`Err`).
    ///
    /// An empty `name` is allowed: it clears the label, which is how a
    /// marker becomes a plain mark.
    pub fn set_marker(
        &self,
        marker: u32,
        time: Option<Ticks>,
        name: Option<&str>,
        chapter: Option<bool>,
        color: Option<&str>,
    ) -> Result<Outcome, String> {
        self.require_marker(marker)?;
        let time = match time {
            None => None,
            Some(given) => {
                let at = self.snapped(given).max(0);
                if let Some(other) = self.markers.iter().find(|m| m.id != marker && m.time == at) {
                    return Err(format!("marker {} is already at {at} ticks", other.id));
                }
                Some(at)
            }
        };

        let mut next = self.clone();
        if let Some(found) = next.markers.iter_mut().find(|m| m.id == marker) {
            if let Some(time) = time {
                found.time = time;
            }
            if let Some(name) = name {
                found.name = name.trim().to_string();
            }
            if let Some(chapter) = chapter {
                found.chapter = chapter;
            }
            // An empty colour falls back to the default rather than being
            // stored: the UI has to draw the mark as something.
            if let Some(color) = color.map(str::trim).filter(|given| !given.is_empty()) {
                found.color = color.to_string();
            }
        }
        self.finish(next)
    }

    /// Removes a marker. `Err` only for an unknown id.
    pub fn remove_marker(&self, marker: u32) -> Result<Outcome, String> {
        self.require_marker(marker)?;
        let mut next = self.clone();
        next.markers.retain(|m| m.id != marker);
        self.finish(next)
    }

    // ---- media -----------------------------------------------------------

    /// Adds one probed file to the media list. `descriptor` is the spec
    /// §5.2 `media[]` element MINUS `id` — the host probes the file and
    /// fills in kind, duration, size, rate and the track flags.
    ///
    /// **The new media's id is the project's `next_id` BEFORE this call.**
    /// There is one JSON op entry point (spec §11), so an op cannot return
    /// a value; reading `next_id` first is how the caller learns the id it
    /// is about to be able to `add_clip` with.
    ///
    /// Adding a file whose path is already in the list changes nothing (an
    /// identity): two entries for one path would each carry their own
    /// bookmark, thumbnails and peaks, and relinking one would leave the
    /// other missing. The caller that gets it looks the path up to find the
    /// id that is already there.
    ///
    /// `Err` for a descriptor that is not an object, an unknown or `id`
    /// key, a value that does not match the schema, an empty path, a
    /// negative duration, a media with pixels whose size or rate is not
    /// usable, or an `original` with an empty path. An `original` (spec §11
    /// #228-O) is stored with its path trimmed and a blank bookmark dropped.
    pub fn add_media(&self, descriptor: &Value) -> Result<Outcome, String> {
        let Value::Object(fields) = descriptor else {
            return Err(format!(
                "a media descriptor must be a json object, not {}",
                describe(descriptor)
            ));
        };
        if fields.contains_key("id") {
            return Err(format!(
                "a media descriptor must not carry an id: the project assigns it (this one gets {})",
                self.next_id
            ));
        }
        for key in fields.keys() {
            if !MEDIA_KEYS.contains(&key.as_str()) {
                return Err(format!("unknown key \"{key}\" in a media descriptor"));
            }
        }

        // Deserializing through `Media` itself means the descriptor's
        // schema is the model's schema — `kind` is checked against the
        // three variants, `fps` against `[num, den]` — with no second
        // spelling of it here. The id is stamped in first because `Media`
        // requires one.
        let mut with_id = descriptor.clone();
        if let Value::Object(map) = &mut with_id {
            map.insert("id".to_string(), Value::from(self.next_id));
        }
        let mut media: Media = serde_json::from_value(with_id)
            .map_err(|e| format!("media descriptor does not match the schema: {e}"))?;

        media.original = normalize_original(media.original);
        check_media_fields(&media)?;
        let path = media.path.trim().to_string();
        if self.media.iter().any(|m| m.path == path) {
            return Ok(Outcome::Identity);
        }

        let mut next = self.clone();
        let mut record = media;
        record.id = next.allocate_id();
        record.path = path;
        // An empty bookmark is not a bookmark; storing one would make
        // `relink` think the file had been located once.
        record.bookmark = record.bookmark.filter(|b| !b.trim().is_empty());
        next.media.push(record);
        self.finish(next)
    }

    /// Removes a media entry. Refuses while clips still show it unless
    /// `with_clips`, which removes those clips with it (spec §6) — the
    /// model has no "missing on purpose" state, and a clip pointing at an
    /// id that is gone is what `validate` rejects. The refusal names the
    /// clips ([`clip_list`]) and the argument that would let it through.
    pub fn remove_media(&self, media: u32, with_clips: bool) -> Result<Outcome, String> {
        self.require_media(media)?;
        // A nest references the project's `media[]` like everything else
        // (spec §5.2, one id space), so a clip INSIDE one counts as usage
        // and is removed with `with_clips` — but the nest CLIP is not
        // itself a user of the media and stays put. Taking it out would
        // throw away everything else in the group over one file.
        let used: Vec<u32> = self
            .every_clip()
            .filter(|c| uses_media(c, media))
            .map(|c| c.id)
            .collect();
        if !used.is_empty() && !with_clips {
            return Ok(Outcome::Refused(format!(
                "media {media} is still used by {}; pass with_clips: true to remove the \
                 media and its clips",
                clip_list(&used)
            )));
        }

        let mut next = self.clone();
        next.clips.retain(|c| !uses_media(c, media));
        for nest in next.nests.iter_mut() {
            nest.clips.retain(|c| !uses_media(c, media));
        }
        next.media.retain(|m| m.id != media);
        self.finish(next)
    }
}
