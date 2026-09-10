//! C FFI: project lifecycle and time (`rc_string_free`, `rc_project_*`,
//! `rc_time_*`, `rc_timecode_*` in the header).
//!
//! Thin shims only. Every export here is `#[no_mangle] pub unsafe extern
//! "C"`, tolerates NULL first, keeps its `unsafe` blocks narrow, and routes
//! its plumbing — error reporting, panic catching, string conversion,
//! handle boxing — through `ffi_util`, which is the one place those
//! conventions are written.
//!
//! `RcProject` in the header is this crate's [`Project`], handed across as
//! an opaque pointer. It is IMMUTABLE from C's point of view: every
//! operation returns a new handle, which is what makes undo on the Swift
//! side a stack of handles.

use std::ffi::{c_char, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;

use crate::ffi_util::{boxed, fallible_op, out_string, project_json, read_cstr};
use crate::format;
use crate::model::Project;
use crate::time::{self, Fps};

// ---- memory --------------------------------------------------------------

/// Frees any string this library returned (results and `err_out`
/// messages). NULL-tolerant.
///
/// # Safety
/// `s` must be NULL or a pointer this library returned and has not already
/// been freed. Freeing twice, or freeing a string this library did not
/// allocate, is undefined.
#[no_mangle]
pub unsafe extern "C" fn rc_string_free(s: *mut c_char) {
    if s.is_null() {
        return;
    }
    // Reclaiming a CString cannot unwind, but wrapping it keeps the "no
    // export ever unwinds into C" rule uniform across the surface.
    let _ = catch_unwind(AssertUnwindSafe(|| drop(unsafe { CString::from_raw(s) })));
}

// ---- project lifecycle ---------------------------------------------------

/// A new empty project: one track, no media, no clips. Returns NULL for a
/// zero dimension or a zero fps numerator/denominator.
///
/// # Safety
/// Takes no pointers; the returned handle is owned by the caller and is
/// freed with [`rc_project_free`].
#[no_mangle]
pub unsafe extern "C" fn rc_project_new(
    width: u32,
    height: u32,
    fps_num: u32,
    fps_den: u32,
) -> *mut Project {
    match catch_unwind(|| {
        Project::new(
            width,
            height,
            Fps {
                num: fps_num,
                den: fps_den,
            },
        )
    }) {
        Ok(Some(project)) => boxed(project),
        _ => ptr::null_mut(),
    }
}

/// Parses project JSON of ANY format version this build knows. NULL with a
/// message through `err_out` on malformed, out-of-cap or invalid input.
///
/// # Safety
/// `json` must be NULL or a valid NUL-terminated C string; `err_out` must
/// be NULL or a valid pointer to writable `*mut c_char`, whose message the
/// caller frees with [`rc_string_free`].
#[no_mangle]
pub unsafe extern "C" fn rc_project_from_json(
    json: *const c_char,
    err_out: *mut *mut c_char,
) -> *mut Project {
    let body = || {
        let text = unsafe { read_cstr(json, "json") }?;
        format::read(&text)
    };
    unsafe {
        fallible_op(
            err_out,
            "parsing project json",
            ptr::null_mut(),
            body,
            boxed,
        )
    }
}

/// The project as JSON at `RC_FORMAT_VERSION`, in the same pretty form
/// `format::write` produces for the file on disk. NULL only for a NULL
/// project (a live project always satisfies the caps `write` checks).
///
/// # Safety
/// `p` must be NULL or a valid handle from this library that has not been
/// freed. The returned string is freed with [`rc_string_free`].
#[no_mangle]
pub unsafe extern "C" fn rc_project_to_json(p: *const Project) -> *mut c_char {
    unsafe { project_json(p, |project| format::write(project).ok()) }
}

/// Deep-copies the handle. NULL-tolerant.
///
/// # Safety
/// `p` must be NULL or a valid handle from this library that has not been
/// freed. The copy is owned by the caller and is freed with
/// [`rc_project_free`].
#[no_mangle]
pub unsafe extern "C" fn rc_project_clone(p: *const Project) -> *mut Project {
    if p.is_null() {
        return ptr::null_mut();
    }
    match catch_unwind(AssertUnwindSafe(|| unsafe { (*p).clone() })) {
        Ok(copy) => boxed(copy),
        Err(_) => ptr::null_mut(),
    }
}

/// The project INSIDE nest `nest_id`, as a new handle — the same view an
/// op carrying `"scope": nest_id` is applied to (`core/src/scope.rs`).
///
/// This is the READ half of a scope, and it exists because a scope has to be
/// LOOKED at as well as edited: the app plays, plans, renders and snapshots
/// a nest through this handle while every edit still goes to the parent's
/// handle with `scope` set. Both halves are [`Project::scoped_view`], which
/// is why they cannot disagree about what is in a nest — a read view that
/// drifted from the edit view would make the timeline show one project and
/// the edits land in another.
///
/// The handle is an ordinary immutable `RcProject`: it is freed with
/// [`rc_project_free`], and applying an op to it edits the VIEW rather than
/// the document, which is not what any caller wants. Nothing enforces that;
/// the app holds it for reading only.
///
/// NULL with a message through `err_out` for a NULL project or a nest id
/// this project has not got (`no nest with id N`, the same sentence the edit
/// path answers). There is no "valid but changes nothing" case here, so a
/// NULL return ALWAYS carries a message.
///
/// # Safety
/// `p` must be NULL or a valid handle from this library that has not been
/// freed; `err_out` must be NULL or a valid pointer to writable
/// `*mut c_char`, whose message the caller frees with [`rc_string_free`].
/// The returned handle is owned by the caller and is freed with
/// [`rc_project_free`].
#[no_mangle]
pub unsafe extern "C" fn rc_project_scoped(
    p: *const Project,
    nest_id: u32,
    err_out: *mut *mut c_char,
) -> *mut Project {
    let body = || {
        if p.is_null() {
            return Err("project is NULL".to_string());
        }
        let project = unsafe { &*p };
        let Some(nest) = project.nest(nest_id) else {
            return Err(format!("no nest with id {nest_id}"));
        };
        Ok(project.scoped_view(nest))
    };
    unsafe {
        fallible_op(
            err_out,
            "building a scoped project",
            ptr::null_mut(),
            body,
            boxed,
        )
    }
}

/// Releases a project handle. NULL-tolerant.
///
/// # Safety
/// `p` must be NULL or a valid handle from this library that has not
/// already been freed; no other pointer to it may be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn rc_project_free(p: *mut Project) {
    if p.is_null() {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| drop(unsafe { Box::from_raw(p) })));
}

// ---- time ----------------------------------------------------------------

/// Rounds `t` to the nearest frame boundary of `fps_num`/`fps_den`.
/// Returns `t` unchanged for a degenerate rate.
///
/// # Safety
/// Takes no pointers. Declared `unsafe` only so the whole exported surface
/// reads the same way.
#[no_mangle]
pub unsafe extern "C" fn rc_time_snap_to_frame(t: i64, fps_num: u32, fps_den: u32) -> i64 {
    catch_unwind(|| {
        time::snap_to_frame(
            t,
            Fps {
                num: fps_num,
                den: fps_den,
            },
        )
    })
    .unwrap_or(t)
}

/// Non-drop timecode: "HH:MM:SS:FF" when `frames`, else "HH:MM:SS.mmm".
/// Negative times get a leading '-'.
///
/// # Safety
/// Takes no pointers. The returned string is freed with
/// [`rc_string_free`]; NULL means the conversion failed.
#[no_mangle]
pub unsafe extern "C" fn rc_timecode_format(
    t: i64,
    fps_num: u32,
    fps_den: u32,
    frames: bool,
) -> *mut c_char {
    let fps = Fps {
        num: fps_num,
        den: fps_den,
    };
    match catch_unwind(|| time::format_timecode(t, fps, frames)) {
        Ok(text) => out_string(text),
        Err(_) => ptr::null_mut(),
    }
}

/// Parses "HH:MM:SS:FF", "MM:SS", "SS.sss" and "HH:MM:SS.mmm" into ticks,
/// snapped to the frame grid. Returns false, with `*out` untouched, when
/// the text is not a time.
///
/// # Safety
/// `s` must be NULL or a valid NUL-terminated C string; `out` must be NULL
/// or a valid pointer to a writable `int64_t`. A NULL `out` still reports
/// whether the text parsed; it simply has nowhere to store the value.
#[no_mangle]
pub unsafe extern "C" fn rc_timecode_parse(
    s: *const c_char,
    fps_num: u32,
    fps_den: u32,
    out: *mut i64,
) -> bool {
    let parsed = catch_unwind(AssertUnwindSafe(|| {
        let text = unsafe { read_cstr(s, "s") }.ok()?;
        time::parse_timecode(
            &text,
            Fps {
                num: fps_num,
                den: fps_den,
            },
        )
    }));
    match parsed {
        Ok(Some(ticks)) => {
            if !out.is_null() {
                unsafe { *out = ticks };
            }
            true
        }
        _ => false,
    }
}
