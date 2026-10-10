//! C FFI: the read-only queries (`rc_project_duration`,
//! `rc_project_composition_plan`, `rc_project_frame_recipe`,
//! `rc_project_frame_recipe_opts`, `rc_project_clip_state`,
//! `rc_project_snap_candidates`, `rc_snap_resolve`, `rc_op_names`,
//! `rc_op_schemas`, `rc_speed_limits` and the three `rc_export_*` queries in
//! the header).
//!
//! Thin shims only, all of them pure: a query never changes the project
//! and never allocates a handle. Every JSON answer here is COMPACT, unlike
//! `rc_project_to_json`, which writes the pretty form that goes in the
//! file: these are machine-consumed — the recipe once per composed frame,
//! the plan on every edit for a string compare — so the whitespace would
//! be paid for at frame rate and read by nobody.
//!
//! A query has no `err_out` except the two export resolvers,
//! [`rc_export_sizes`] and [`rc_export_settings`], whose failures (an
//! unknown preset, a bad override) are a user-facing dialog. The rest
//! answer NULL, 0 or `t` for a NULL project, an unknown id or malformed
//! JSON — there is nothing a caller could do with a message it did not
//! already know from the id it passed in.

use std::ffi::c_char;
use std::ptr;

use serde_json::Value;

use crate::edit;
use crate::edit_clip_timing::speed_limits;
use crate::export;
use crate::ffi_util::{
    fallible_op, out_string, project_get, project_json, read_cstr, read_opt_cstr,
};
use crate::model::Project;
use crate::op_schema;
use crate::recipe::RecipeOptions;
use crate::snap;
use crate::time::Ticks;

/// End of the last clip, in ticks. 0 for an empty project or NULL.
///
/// # Safety
/// `p` must be NULL or a valid handle from this library that has not been
/// freed.
#[no_mangle]
pub unsafe extern "C" fn rc_project_duration(p: *const Project) -> i64 {
    unsafe { project_get(p, 0, |project| Some(project.duration())) }
}

/// The composition plan (spec §7.2): what Swift builds an
/// `AVMutableComposition`, `AVMutableAudioMix` and
/// `AVVideoComposition.Configuration` from. Byte-for-byte deterministic, because
/// Swift rebuilds only when this string differs from the current plan.
/// NULL only for a NULL project.
///
/// # Safety
/// `p` must be NULL or a valid handle from this library that has not been
/// freed. The returned string is freed with [`crate::ffi::rc_string_free`].
#[no_mangle]
pub unsafe extern "C" fn rc_project_composition_plan(p: *const Project) -> *mut c_char {
    unsafe { project_json(p, |project| Some(project.composition_plan().to_string())) }
}

/// The frame recipe at project time `t` (spec §7.3): the back-to-front
/// layer list with every property already evaluated through actions.
/// Valid JSON for any `t`, including a negative one and one past the end
/// (an empty layer list). NULL only for a NULL project.
///
/// # Safety
/// `p` must be NULL or a valid handle from this library that has not been
/// freed. The returned string is freed with [`crate::ffi::rc_string_free`].
#[no_mangle]
pub unsafe extern "C" fn rc_project_frame_recipe(p: *const Project, t: i64) -> *mut c_char {
    unsafe { project_json(p, |project| Some(project.frame_recipe(t).to_string())) }
}

/// [`rc_project_frame_recipe`] with the caller's recipe options (spec §7.3;
/// [`RecipeOptions`]). `opts_json` is `{"burn_in_timecode": bool,
/// "ungraded": bool}` (either key may be absent) or NULL
/// for the defaults, and NULL is exactly what
/// [`rc_project_frame_recipe`] asks for — the two exports are one
/// implementation, so a plain call to either produces the same bytes.
///
/// An `opts_json` that is not JSON at all answers NULL, which is all this
/// export can say: the queries carry no `err_out` (this module's doc gives
/// the reason). A key that is ABSENT, of the wrong type, or in a document
/// that is not an object is not a failure at all — it means OFF, and
/// [`RecipeOptions::of`] argues why the two are spelled differently.
///
/// # Safety
/// `p` must be NULL or a valid handle from this library that has not been
/// freed; `opts_json` must be NULL or a valid NUL-terminated C string. The
/// returned string is freed with [`crate::ffi::rc_string_free`].
#[no_mangle]
pub unsafe extern "C" fn rc_project_frame_recipe_opts(
    p: *const Project,
    t: i64,
    opts_json: *const c_char,
) -> *mut c_char {
    unsafe {
        project_json(p, |project| {
            // Read inside the closure so the whole body, pointer read
            // included, runs under the one catch_unwind project_json owns —
            // `rc_project_snap_candidates` above does the same for the same
            // reason.
            let text = read_opt_cstr(opts_json, "opts_json").ok()?;
            let opts = match text {
                None => RecipeOptions::default(),
                Some(json) => RecipeOptions::of(&serde_json::from_str::<Value>(&json).ok()?),
            };
            Some(project.frame_recipe_opts(t, opts).to_string())
        })
    }
}

/// One clip's evaluated properties at project time `t`, for the inspector.
/// NULL for a NULL project or an unknown clip id.
///
/// # Safety
/// `p` must be NULL or a valid handle from this library that has not been
/// freed. The returned string is freed with [`crate::ffi::rc_string_free`].
#[no_mangle]
pub unsafe extern "C" fn rc_project_clip_state(
    p: *const Project,
    clip: u32,
    t: i64,
) -> *mut c_char {
    unsafe {
        project_json(p, |project| {
            project.clip_state(clip, t).map(|state| state.to_string())
        })
    }
}

/// Snap candidates for a timeline drag: `{"ticks": [...], "labels": {...}}`
/// with the ticks sorted and deduped. `exclude_clips_json` is a JSON array
/// of the clip ids being dragged (their own edges are not candidates), or
/// NULL for none. NULL for a NULL project or an `exclude_clips_json` that
/// is not an array of ids.
///
/// # Safety
/// `p` must be NULL or a valid handle from this library that has not been
/// freed; `exclude_clips_json` must be NULL or a valid NUL-terminated C
/// string. The returned string is freed with
/// [`crate::ffi::rc_string_free`].
#[no_mangle]
pub unsafe extern "C" fn rc_project_snap_candidates(
    p: *const Project,
    exclude_clips_json: *const c_char,
) -> *mut c_char {
    unsafe {
        project_json(p, |project| {
            // Read inside the closure so the whole body, pointer read
            // included, runs under the one catch_unwind project_json owns.
            let text = read_opt_cstr(exclude_clips_json, "exclude_clips_json").ok()?;
            let exclude: Vec<u32> = match text {
                None => Vec::new(),
                Some(json) => serde_json::from_str(&json).ok()?,
            };
            Some(project.snap_candidates(&exclude).to_string())
        })
    }
}

/// The nearest candidate to `t` within `threshold` ticks, else `t`.
/// `candidates_json` is a JSON array of ticks — the `"ticks"` member of
/// [`rc_project_snap_candidates`], to which Swift appends its view state
/// (the playhead, the in/out points) before calling. `snapped_out`, when
/// non-NULL, reports whether a candidate was taken; it is left untouched
/// only if the array cannot be read.
///
/// # Safety
/// `candidates_json` must be NULL or a valid NUL-terminated C string;
/// `snapped_out` must be NULL or a valid pointer to a writable `bool`.
#[no_mangle]
pub unsafe extern "C" fn rc_snap_resolve(
    candidates_json: *const c_char,
    t: i64,
    threshold: i64,
    snapped_out: *mut bool,
) -> i64 {
    let body = || {
        let text = unsafe { read_cstr(candidates_json, "candidates_json") }?;
        let candidates: Vec<Ticks> = serde_json::from_str(&text)
            .map_err(|e| format!("candidates_json is not an array of ticks: {e}"))?;
        Ok(snap::resolve(&candidates, t, threshold))
    };
    // No err_out in the header: a malformed array is "nothing to snap to",
    // and passing NULL is how fallible_op says "swallow the message".
    unsafe {
        fallible_op(ptr::null_mut(), "resolving a snap", t, body, |(at, hit)| {
            if !snapped_out.is_null() {
                *snapped_out = hit;
            }
            at
        })
    }
}

/// Every op name [`crate::model::Project::apply`] accepts, as a JSON array
/// of strings in op-table order — `OP_NAMES` in `crate::edit`.
///
/// It is exported for the host's own startup check: the MCP catalog in
/// `app/Sources/AgentCatalog.swift` must carry a tool for every row of the
/// table, and the only way to check that without a second list to drift is
/// to ask the side that owns the first one. Never NULL.
///
/// # Safety
/// Takes no pointers; declared `unsafe` only so the whole exported surface
/// reads the same way. The returned string is freed with
/// [`crate::ffi::rc_string_free`].
#[no_mangle]
pub unsafe extern "C" fn rc_op_names() -> *mut c_char {
    unsafe {
        fallible_op(
            ptr::null_mut(),
            "listing op names",
            ptr::null_mut(),
            || {
                serde_json::to_string(&edit::OP_NAMES[..])
                    .map_err(|e| format!("op names are not serializable: {e}"))
            },
            out_string,
        )
    }
}

/// Every op's ARGUMENTS as JSON Schema: an object mapping each name
/// [`rc_op_names`] reports to
/// `{"type": "object", "properties": {…}, "required": […]}` for that op —
/// `crate::op_schema::op_schemas`, built out of `op_table.rs`.
///
/// It is exported for the same reason [`rc_op_names`] is, one level
/// further in: the MCP catalog in `app/Sources/AgentCatalog*.swift` used to
/// write every op tool's argument types, `minimum`s, `enum`s and `required`
/// list by hand, and the only way those cannot drift from what the core
/// decodes is to print the side that owns them — which all fifty-seven op
/// tools have done since road map 7's D3·4. The core says what an
/// argument IS; the app's prose says what it is FOR, and this carries none
/// of it — nor the envelope's `scope`, which is not an argument of any op.
///
/// A query, so it takes no handle, changes nothing persisted and is never
/// NULL; adding it moves no format version.
///
/// # Safety
/// Takes no pointers; declared `unsafe` only so the whole exported surface
/// reads the same way. The returned string is freed with
/// [`crate::ffi::rc_string_free`].
#[no_mangle]
pub unsafe extern "C" fn rc_op_schemas() -> *mut c_char {
    unsafe {
        fallible_op(
            ptr::null_mut(),
            "listing op schemas",
            ptr::null_mut(),
            || Ok(op_schema::op_schemas().to_string()),
            out_string,
        )
    }
}

/// Every number about a clip's speed, as JSON:
/// `{"min":0.1,"max":1000.0,"audio_max":12.0}` — the range `set_speed`
/// clamps to and the reader enforces, and the speed above which the plan
/// leaves a clip's audio out, in both pitch modes (spec §11 #190). The one
/// home of those numbers is `crate::edit_clip_timing`; the app reads them
/// here and types none.
///
/// A query — no handle, nothing persisted changes, and never NULL.
///
/// # Safety
/// Takes no pointers; declared `unsafe` only so the whole exported surface
/// reads the same way. The returned string is freed with
/// [`crate::ffi::rc_string_free`].
#[no_mangle]
pub unsafe extern "C" fn rc_speed_limits() -> *mut c_char {
    unsafe {
        fallible_op(
            ptr::null_mut(),
            "listing speed limits",
            ptr::null_mut(),
            || Ok(speed_limits().to_string()),
            out_string,
        )
    }
}

/// The export presets as a JSON array (spec §7.8), in menu order: one row
/// per encoding, none with a size of its own but the two image caps. The
/// FIRST row is the default: the export sheet opens on it, which is why the
/// table puts H.264 there (`export::PRESETS`).
///
/// # Safety
/// Takes no pointers; declared `unsafe` only so the whole exported surface
/// reads the same way. The returned string is freed with
/// [`crate::ffi::rc_string_free`].
#[no_mangle]
pub unsafe extern "C" fn rc_export_presets() -> *mut c_char {
    unsafe {
        fallible_op(
            ptr::null_mut(),
            "listing export presets",
            ptr::null_mut(),
            || Ok(export::presets().to_string()),
            out_string,
        )
    }
}

/// The output sizes the export sheet offers for `preset_id` against the
/// project, as a JSON array of `{id, name, width, height}` in menu order,
/// the FIRST row the default: the document's own size, or an image
/// format's cap ahead of it (`Project::export_sizes` in `export_size.rs`
/// says why the standard rows are named by their short edge). On a row
/// that needs even pixel dimensions the `document` row is the canvas
/// evened — an odd edge one pixel smaller, the size the file will have —
/// and is named "Document (even)" when that is not the canvas's own size
/// (spec §11 G-33). NULL with a
/// message through `err_out` for a NULL project, a NULL `preset_id` or an
/// unknown preset.
///
/// # Safety
/// `p` must be NULL or a valid handle from this library that has not been
/// freed; `preset_id` must be NULL or a valid NUL-terminated C string;
/// `err_out` must be NULL or a valid pointer to writable `*mut c_char`.
/// Both the result and the message are freed with
/// [`crate::ffi::rc_string_free`].
#[no_mangle]
pub unsafe extern "C" fn rc_export_sizes(
    p: *const Project,
    preset_id: *const c_char,
    err_out: *mut *mut c_char,
) -> *mut c_char {
    let body = || {
        if p.is_null() {
            return Err("project is NULL".to_string());
        }
        let preset = unsafe { read_cstr(preset_id, "preset_id") }?;
        let project = unsafe { &*p };
        project.export_sizes(&preset).map(|sizes| sizes.to_string())
    };
    unsafe {
        fallible_op(
            err_out,
            "listing export sizes",
            ptr::null_mut(),
            body,
            out_string,
        )
    }
}

/// A preset plus optional `overrides_json` resolved against the project
/// into the concrete settings an `AVAssetExportSession` needs. The
/// resolved `width` and `height` are the size the file will have: evened
/// on a row that needs even pixel dimensions (an odd edge one pixel
/// smaller, whether the canvas's or an override's), fitted on the two
/// image formats, and as asked on `prores_4444` (spec §11 G-33). NULL with a
/// message through `err_out` for a NULL project, an unknown preset, bad
/// overrides, or an empty export range.
///
/// # Safety
/// `p` must be NULL or a valid handle from this library that has not been
/// freed; `preset_id` and `overrides_json` must be NULL or valid
/// NUL-terminated C strings; `err_out` must be NULL or a valid pointer to
/// writable `*mut c_char`. Both the result and the message are freed with
/// [`crate::ffi::rc_string_free`].
#[no_mangle]
pub unsafe extern "C" fn rc_export_settings(
    p: *const Project,
    preset_id: *const c_char,
    overrides_json: *const c_char,
    err_out: *mut *mut c_char,
) -> *mut c_char {
    let body = || {
        if p.is_null() {
            return Err("project is NULL".to_string());
        }
        let preset = unsafe { read_cstr(preset_id, "preset_id") }?;
        let overrides = match unsafe { read_opt_cstr(overrides_json, "overrides_json") }? {
            None => None,
            Some(text) => Some(
                serde_json::from_str::<Value>(&text)
                    .map_err(|e| format!("export overrides are not valid json: {e}"))?,
            ),
        };
        let project = unsafe { &*p };
        project
            .export_settings(&preset, overrides.as_ref())
            .map(|settings| settings.to_string())
    };
    unsafe {
        fallible_op(
            err_out,
            "resolving export settings",
            ptr::null_mut(),
            body,
            out_string,
        )
    }
}
