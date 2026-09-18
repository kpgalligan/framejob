//! C FFI: the one edit entry point (`rc_project_apply` in the header).
//!
//! A thin shim over [`Project::apply`], and the place the answers of spec
//! §5.5 are turned into C's return value and its two message channels. It
//! exists as its own module because that mapping is the whole reason the
//! app's undo stack is correct, and it deserves to be readable on its own.

use std::ffi::c_char;
use std::ptr;

use crate::ffi_util::{boxed, fallible_op, read_cstr, set_message};
use crate::model::Project;
use crate::outcome::Outcome;

/// Applies one edit op and returns a NEW project handle. `op` is
/// `{"op": "<name>", ...arguments}` — the table in the module doc of
/// `core/src/edit.rs` and spec §6.
///
/// NULL comes back in three cases the caller MUST distinguish, which is why
/// it must set `char *err = NULL; char *reason = NULL;` before the call and
/// test both after:
///
/// - **neither written** (both still NULL): the op is valid and nothing
///   needed to change — an identity edit. The caller registers **no undo
///   step**, and says nothing more than that: a caller told about a rule
///   here would go looking for one it did not break.
/// - **`*reason_out` set**: a rule refused the op, and this is that rule's
///   own sentence, naming what a caller could act on ("clips 3 and 4 would
///   overlap by 8000 ticks, more than half of the shorter clip (6000
///   ticks)"). Still **no undo step**, and still not an error: the project
///   is exactly as it was. The UI beeps or animates the gesture back.
/// - **`*err_out` set**: the op or its arguments are invalid (a malformed
///   envelope, an unknown op name, an unknown id, an out-of-range value).
///   Unchanged in meaning and in wording by deepening D2.
///
/// The two channels are never both written. Either message is owned by the
/// caller and is freed with [`crate::ffi::rc_string_free`].
///
/// The input project is never mutated: every edit is pure, which is what
/// makes undo on the Swift side a stack of handles.
///
/// # Safety
/// `p` must be NULL or a valid handle from this library that has not been
/// freed; `op` must be NULL or a valid NUL-terminated C string; `err_out`
/// and `reason_out` must each be NULL or a valid pointer to writable
/// `*mut c_char`. The returned handle is owned by the caller and is freed
/// with [`crate::ffi::rc_project_free`].
#[no_mangle]
pub unsafe extern "C" fn rc_project_apply(
    p: *const Project,
    op: *const c_char,
    err_out: *mut *mut c_char,
    reason_out: *mut *mut c_char,
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
            // The three arms of `Outcome` land here; `err_out` is written
            // by `fallible_op` above and never by this closure, which is
            // what keeps "invalid input" and "a rule said no" apart.
            |outcome| match outcome {
                Outcome::Applied(next) => boxed(next),
                Outcome::Identity => ptr::null_mut(),
                Outcome::Refused(why) => {
                    // Inside the `unsafe` block below, whose safety
                    // paragraph covers `reason_out`.
                    set_message(reason_out, &why);
                    ptr::null_mut()
                }
            },
        )
    }
}
