//! C FFI: the one edit entry point (`rc_project_apply` in the header).
//!
//! A thin shim over [`Project::apply`], and the place the three-way answer
//! of spec §5.5 is turned into C's two return values. It exists as its own
//! module because that mapping is the whole reason the app's undo stack is
//! correct, and it deserves to be readable on its own.

use std::ffi::c_char;
use std::ptr;

use crate::ffi_util::{boxed, fallible_op, read_cstr};
use crate::model::Project;

/// Applies one edit op and returns a NEW project handle. `op` is
/// `{"op": "<name>", ...arguments}` — the table in the module doc of
/// `core/src/edit.rs` and spec §6.
///
/// NULL comes back in two cases the caller MUST distinguish, which is why
/// it must set `char *err = NULL;` before the call and test it after:
///
/// - `*err_out` **untouched** (still NULL): the op is valid but would
///   change nothing — an identity edit, or a documented refusal such as
///   the overlap rule. The caller registers **no undo step**; the UI beeps
///   or animates the gesture back. Registering one here would be a phantom
///   step the user has to undo twice.
/// - `*err_out` **set**: the op or its arguments are invalid (a malformed
///   envelope, an unknown op name, an unknown id, an out-of-range value).
///   The message is owned by the caller and is freed with
///   [`crate::ffi::rc_string_free`].
///
/// The input project is never mutated: every edit is pure, which is what
/// makes undo on the Swift side a stack of handles.
///
/// # Safety
/// `p` must be NULL or a valid handle from this library that has not been
/// freed; `op` must be NULL or a valid NUL-terminated C string; `err_out`
/// must be NULL or a valid pointer to writable `*mut c_char`. The returned
/// handle is owned by the caller and is freed with
/// [`crate::ffi::rc_project_free`].
#[no_mangle]
pub unsafe extern "C" fn rc_project_apply(
    p: *const Project,
    op: *const c_char,
    err_out: *mut *mut c_char,
) -> *mut Project {
    let body = || {
        // A NULL project is a caller bug, not an identity edit, so it
        // reports through err_out rather than as "nothing changed".
        if p.is_null() {
            return Err("project is NULL".to_string());
        }
        let text = unsafe { read_cstr(op, "op") }?;
        let project = unsafe { &*p };
        project.apply(&text)
    };
    unsafe {
        fallible_op(
            err_out,
            "applying an edit op",
            ptr::null_mut(),
            body,
            // Ok(None) — valid, changes nothing — lands here, and returns
            // NULL with err_out never written.
            |edited| match edited {
                Some(next) => boxed(next),
                None => ptr::null_mut(),
            },
        )
    }
}
