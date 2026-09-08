//! The persisted format: the version number, the reader's caps, and the
//! read-any-version / write-current pair behind `project.json` in a
//! `.reelcut` package (spec §5.6).
//!
//! The rule this module exists to enforce: **the reader accepts every prior
//! version, and the writer enforces the reader's caps**, so every file this
//! build produces can be read back by this build. Any change to the
//! persisted schema bumps [`RC_FORMAT_VERSION`] here AND the `#define` in
//! `core/include/reelcut_core.h`, and adds a migration step in [`read`].

use serde_json::{json, Value};

use crate::model::{Canvas, Project};

/// Bumped by any change to the persisted project schema. Mirrored by
/// `RC_FORMAT_VERSION` in the C header.
///
/// Version 2 is the M3 schema: nests (`project.nests`, and a nest CLIP
/// naming one by id instead of by path), filters, reflection, spotlight,
/// reversed media, and audio pan / compressor / noise reduction. Every one
/// of those fields carries a serde default, so a version-1 file reads
/// unchanged — with the single exception the nest payload's type change
/// forces, which [`migrate_1_to_2`] handles.
///
/// Version 3 is clip identity (road map 2, phase 2): `Clip.name`,
/// `Clip.label` and `Track.solo`. All three carry a serde default — `None`,
/// `None`, `false` — so a version-2 file reads unchanged and no migration
/// step exists for it; the bump is there so a version-2 build refuses a
/// file whose names and labels it would otherwise silently drop.
///
/// Version 4 is hidden regions (road map 2, phase 3c):
/// [`crate::model::VideoProps::obscure`], a list of at most
/// [`crate::model::MAX_OBSCURE`] rectangles or ellipses each hiding what is
/// under it behind a blur or a pixelation. The list carries a serde default
/// — the empty one — so a version-3 file reads unchanged and there is again
/// no migration step; the bump is there for version 3's reason exactly,
/// that unknown keys are ignored at every level by design (`model.rs`'s
/// module doc), so without the version gate a version-3 build would open a
/// version-4 file, drop every region on read, and write the loss back over
/// the original on the next save. Nothing else phase 3 added persists a new
/// key: `ripple_delete_ranges` only removes time, and `add_zoom_action`
/// writes an ordinary [`crate::model::Action`] whose `end` patch is schema
/// that already existed.
///
/// Version 5 is text animations (road map 2, phase 4c):
/// [`crate::model::TextProps::animation`], the kind of reveal a text layer
/// arrives and leaves with and how long each half takes. The field is an
/// `Option` and defaults to `None`, so a version-4 file reads unchanged and
/// there is no migration step for it either. The bump is there for
/// versions 3 and 4's reason exactly, and it is worth restating rather than
/// pointing at, because a defaulted field is precisely the case where the
/// bump looks like paperwork: unknown keys are ignored at every level by
/// design (`model.rs`'s module doc), so without the version gate a
/// version-4 build would open a version-5 file, drop every animation on
/// read, and write the loss back over the original on the next save —
/// silently, since the project still opens and the text is still there. It
/// is the fields that need NO migration whose loss is quietest. Nothing
/// else phase 4 added persists a new key: auto captions and caption export
/// both work in ordinary text clips through the ops that already existed,
/// and the per-frame reveal the animation produces is computed by
/// [`crate::recipe`] and never stored.
pub const RC_FORMAT_VERSION: u32 = 5;

/// Reader caps, mirrored by the `RC_MAX_*` defines in the C header. They
/// exist so a corrupt or generated file cannot make the app allocate
/// without bound, and they are generous: 4096 clips is far past what the
/// timeline UI stays usable at.
pub const MAX_CLIPS: usize = 4096;
pub const MAX_TRACKS: usize = 64;
pub const MAX_MARKERS: usize = 1024;
pub const MAX_MEDIA: usize = 1024;

/// How many levels of nest may sit inside one another. A cap on the WALK,
/// not on taste: every evaluation of a nested layer recurses once per
/// level, and eight levels is already past anything an editor does on
/// purpose. `Project::validate` refuses a deeper file, and it refuses a
/// nest that reaches itself at any depth, so no walk downstream needs a
/// visited set of its own.
pub const MAX_NEST_DEPTH: u32 = 8;

/// The caps check both sides share: [`Project::validate`] runs it on read,
/// [`write`] runs it before serializing. One implementation, so the writer
/// can never produce a file the reader rejects.
///
/// Nested tracks and clips count toward the same two caps as the
/// timeline's. They are the same tracks and clips — a nest is a group held
/// in the parent's one id space, and flattening one at evaluation time
/// gives its clips real composition tracks — so counting them separately
/// would let a project with 64 nests of 64 tracks past a cap that exists to
/// bound exactly that.
pub fn check_caps(p: &Project) -> Result<(), String> {
    let nested_clips: usize = p.nests.iter().map(|n| n.clips.len()).sum();
    let nested_tracks: usize = p.nests.iter().map(|n| n.tracks.len()).sum();
    let clips = p.clips.len().saturating_add(nested_clips);
    let tracks = p.tracks.len().saturating_add(nested_tracks);
    if clips > MAX_CLIPS {
        return Err(format!("too many clips: {clips} (max {MAX_CLIPS})"));
    }
    if tracks > MAX_TRACKS {
        return Err(format!("too many tracks: {tracks} (max {MAX_TRACKS})"));
    }
    if p.markers.len() > MAX_MARKERS {
        return Err(format!(
            "too many markers: {} (max {})",
            p.markers.len(),
            MAX_MARKERS
        ));
    }
    if p.media.len() > MAX_MEDIA {
        return Err(format!(
            "too many media: {} (max {})",
            p.media.len(),
            MAX_MEDIA
        ));
    }
    Ok(())
}

/// Version 1 → 2. One key needs rewriting: a nest clip's `project`.
///
/// In version 1 it was a PATH — a reference the core, which has no
/// filesystem, could never resolve, so `evaluate.rs` could only drop the
/// clip — and in version 2 it is the id of a `Nest` in `nests[]`. No build
/// ever created one (no op makes a nest yet; the reader round-tripped the
/// key and nothing else), so nothing real is being reinterpreted here. The
/// step exists because "the reader accepts every prior version" is a
/// promise about hand-written and third-party files too, and a `String`
/// where a `u32` now belongs is the one version-1 shape serde cannot take
/// with a default.
///
/// The path becomes an EMPTY nest carrying it as a name. That keeps the
/// clip — its track, its times, its transform, its actions — and loses only
/// a reference that never resolved to anything; deleting the clip instead
/// would silently throw away something a person placed on a timeline.
///
/// Anything else is left exactly as it is. A shape this cannot make sense
/// of gets serde's schema error, naming the key, rather than a guess made
/// here.
fn migrate_1_to_2(value: &mut Value) {
    let default_canvas = Canvas::default();
    let width = value
        .pointer("/canvas/width")
        .and_then(Value::as_u64)
        .unwrap_or(u64::from(default_canvas.width));
    let height = value
        .pointer("/canvas/height")
        .and_then(Value::as_u64)
        .unwrap_or(u64::from(default_canvas.height));
    // Ids come from the file's own counter, which is exactly what it is
    // for: `validate` demands `next_id` be past every id in the project, so
    // allocating from it cannot collide with one.
    let mut next_id = value.get("next_id").and_then(Value::as_u64).unwrap_or(1);

    let mut made: Vec<Value> = Vec::new();
    if let Some(clips) = value.get_mut("clips").and_then(Value::as_array_mut) {
        for clip in clips {
            let Some(source) = clip.get_mut("source").and_then(Value::as_object_mut) else {
                continue;
            };
            if source.get("kind").and_then(Value::as_str) != Some("nest") {
                continue;
            }
            let Some(path) = source.get("project").and_then(Value::as_str) else {
                continue;
            };
            let id = next_id;
            next_id = next_id.saturating_add(1);
            made.push(json!({
                "id": id, "name": path, "width": width, "height": height,
                "tracks": [], "clips": []
            }));
            source.insert("project".to_string(), Value::from(id));
        }
    }
    if made.is_empty() {
        return;
    }

    let Some(root) = value.as_object_mut() else {
        return;
    };
    // A version-1 file with a `nests` key is a hand edit, not something a
    // build wrote, so the migrated nests join it rather than replacing it.
    match root.get_mut("nests").and_then(Value::as_array_mut) {
        Some(existing) => existing.extend(made),
        None => {
            root.insert("nests".to_string(), Value::Array(made));
        }
    }
    root.insert("next_id".to_string(), Value::from(next_id));
}

/// Parses project JSON of ANY version this build knows, migrating it
/// forward, and validates the result. Names the reason on failure.
///
/// The version is read from the raw JSON before deserializing, so a file
/// from a newer build reports "update Reelcut" instead of a confusing
/// schema error about a field this build has never heard of.
///
/// That gate is also what lets the schema itself be lenient: keys this
/// build does not know are IGNORED at every level and are dropped by the
/// next [`write`] (the module doc of `model.rs` says why, and names the one
/// exception — an action's opaque `end` patch).
pub fn read(json: &str) -> Result<Project, String> {
    let mut value: Value =
        serde_json::from_str(json).map_err(|e| format!("project json is not valid json: {e}"))?;

    // A version spelled as a JSON float (`2.0`) is still a version. Reading
    // it with `as_u64` alone would miss it, fall back to the current
    // version, and hand the user a schema error about a field this build
    // has never heard of instead of "update Reelcut" — which is the whole
    // reason the gate is read from the raw JSON. `trunc` rather than a
    // round, so 1.9 is treated as version 1 and gets the schema error it
    // deserves rather than being refused as a version from the future.
    let version = match value.get("version") {
        None | Some(Value::Null) => u64::from(RC_FORMAT_VERSION),
        Some(number) => number
            .as_u64()
            .or_else(|| {
                number
                    .as_f64()
                    .filter(|v| v.is_finite() && *v >= 0.0)
                    .map(|v| v.trunc() as u64)
            })
            .ok_or_else(|| format!("project version must be a whole number, not {number}"))?,
    };
    if version > u64::from(RC_FORMAT_VERSION) {
        return Err(format!(
            "project format version {version} is newer than this build understands \
             (version {RC_FORMAT_VERSION}); update Reelcut to open it"
        ));
    }

    // MIGRATION HOOK. Each bump adds one step here, applied in order from
    // `version` up to RC_FORMAT_VERSION, rewriting `value` in place before
    // it is deserialized. Versions 3, 4 and 5 needed no rewrite — every
    // field any of them added carries a serde default — so none has a
    // line; the next version that changes a field's SHAPE adds its own
    // below.
    if version < 2 {
        migrate_1_to_2(&mut value);
    }

    let mut project: Project = serde_json::from_value(value)
        .map_err(|e| format!("project json does not match the schema: {e}"))?;
    // A migrated project is now a current-version project.
    project.version = RC_FORMAT_VERSION;
    project.validate()?;
    Ok(project)
}

/// The project as JSON at [`RC_FORMAT_VERSION`], pretty-printed: the file
/// lives inside a package a user may open, inspect and diff, and the cost
/// of the extra whitespace is nothing next to the media it references.
pub fn write(p: &Project) -> Result<String, String> {
    check_caps(p)?;
    // The common case is already current, so serialize in place; only a
    // project carried over from an older file needs the clone to stamp the
    // version. `write` runs after every edit (Swift rebuilds its snapshot
    // from it), so the saved clone is worth the branch.
    let json = if p.version == RC_FORMAT_VERSION {
        serde_json::to_string_pretty(p)
    } else {
        let mut current = p.clone();
        current.version = RC_FORMAT_VERSION;
        serde_json::to_string_pretty(&current)
    };
    json.map_err(|e| format!("could not serialize the project: {e}"))
}
