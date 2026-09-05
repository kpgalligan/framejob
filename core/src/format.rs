//! The persisted format: the version number, the reader's caps, and the
//! read-any-version / write-current pair behind `project.json` in a
//! `.reelcut` package (spec §5.6).
//!
//! The rule this module exists to enforce: **the reader accepts every prior
//! version, and the writer enforces the reader's caps**, so every file this
//! build produces can be read back by this build. Any change to the
//! persisted schema bumps [`RC_FORMAT_VERSION`] here AND the `#define` in
//! `core/include/reelcut_core.h`, and adds a migration step in [`read`].

use serde_json::Value;

use crate::model::Project;

/// Bumped by any change to the persisted project schema. Mirrored by
/// `RC_FORMAT_VERSION` in the C header.
pub const RC_FORMAT_VERSION: u32 = 1;

/// Reader caps, mirrored by the `RC_MAX_*` defines in the C header. They
/// exist so a corrupt or generated file cannot make the app allocate
/// without bound, and they are generous: 4096 clips is far past what the
/// timeline UI stays usable at.
pub const MAX_CLIPS: usize = 4096;
pub const MAX_TRACKS: usize = 64;
pub const MAX_MARKERS: usize = 1024;
pub const MAX_MEDIA: usize = 1024;

/// The caps check both sides share: [`Project::validate`] runs it on read,
/// [`write`] runs it before serializing. One implementation, so the writer
/// can never produce a file the reader rejects.
pub fn check_caps(p: &Project) -> Result<(), String> {
    if p.clips.len() > MAX_CLIPS {
        return Err(format!(
            "too many clips: {} (max {})",
            p.clips.len(),
            MAX_CLIPS
        ));
    }
    if p.tracks.len() > MAX_TRACKS {
        return Err(format!(
            "too many tracks: {} (max {})",
            p.tracks.len(),
            MAX_TRACKS
        ));
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

    // MIGRATION HOOK. Each future bump adds one step here, applied in order
    // from `version` up to RC_FORMAT_VERSION, rewriting `value` in place
    // before it is deserialized:
    //
    //     if version < 2 { migrate_1_to_2(&mut value); }
    //     if version < 3 { migrate_2_to_3(&mut value); }
    //
    // Version 1 is the first, so there is nothing to migrate yet. The
    // binding is `mut` for that future; silence the unused warning until
    // the first step lands.
    let _ = &mut value;

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
