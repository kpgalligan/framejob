//! Shared plumbing for the FFI shims (`ffi`, `ffi_edit`, `ffi_query`,
//! `ffi_agent`): error reporting through `err_out`, panic-safe wrappers, and
//! the string conversions every shim needs. Nothing here is exported through
//! the C header — these are the helpers the exported functions are built
//! from, so the conventions (catch_unwind everywhere, NULL tolerance, heap
//! CString errors freed with `rc_string_free`) live in ONE place.

use std::ffi::{c_char, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;

use crate::model::Project;

/// Stores a heap-allocated copy of `msg` through `err_out` (if non-NULL).
/// Interior NUL bytes are replaced so the `CString` conversion cannot fail.
///
/// # Safety
/// `err_out` must be NULL or a valid pointer to writable `*mut c_char`.
pub(crate) unsafe fn set_err(err_out: *mut *mut c_char, msg: &str) {
    if err_out.is_null() {
        return;
    }
    let sanitized = msg.replace('\0', " ");
    let cstring = CString::new(sanitized)
        .unwrap_or_else(|_| CString::new("reelcut-core error").expect("static string"));
    unsafe {
        *err_out = cstring.into_raw();
    }
}

/// Reads a required C-string argument into an owned `String`, naming the
/// argument in the error ("`what` is NULL" / "`what` is not valid UTF-8").
///
/// # Safety
/// `ptr` must be NULL or a valid NUL-terminated C string.
pub(crate) unsafe fn read_cstr(ptr: *const c_char, what: &str) -> Result<String, String> {
    if ptr.is_null() {
        return Err(format!("{what} is NULL"));
    }
    unsafe { CStr::from_ptr(ptr) }
        .to_str()
        .map(str::to_owned)
        .map_err(|_| format!("{what} is not valid UTF-8"))
}

/// Reads an OPTIONAL C-string argument: NULL is `None`, invalid UTF-8 is an
/// error naming the argument.
///
/// # Safety
/// `ptr` must be NULL or a valid NUL-terminated C string.
pub(crate) unsafe fn read_opt_cstr(
    ptr: *const c_char,
    what: &str,
) -> Result<Option<String>, String> {
    if ptr.is_null() {
        return Ok(None);
    }
    unsafe { read_cstr(ptr, what) }.map(Some)
}

/// Hands a Rust string to the C side as a heap allocation the caller frees
/// with `rc_string_free`. Interior NULs are replaced.
pub(crate) fn out_string(s: String) -> *mut c_char {
    let sanitized = if s.contains('\0') {
        s.replace('\0', " ")
    } else {
        s
    };
    match CString::new(sanitized) {
        Ok(owned) => owned.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Boxes a value and leaks it as the raw handle the C side owns.
pub(crate) fn boxed<T>(value: T) -> *mut T {
    Box::into_raw(Box::new(value))
}

/// Runs a fallible FFI body under [`catch_unwind`], mapping `Ok` through
/// `success` and reporting failures through `err_out`: an `Err` message
/// passes through verbatim, a caught panic becomes the long-form
/// "internal error: `what`". Either failure returns `failure`.
///
/// # Safety
/// `err_out` must be NULL or a valid pointer to writable `*mut c_char`.
pub(crate) unsafe fn fallible_op<T, R>(
    err_out: *mut *mut c_char,
    what: &str,
    failure: R,
    body: impl FnOnce() -> Result<T, String>,
    success: impl FnOnce(T) -> R,
) -> R {
    match catch_unwind(AssertUnwindSafe(body)) {
        Ok(Ok(value)) => success(value),
        Ok(Err(msg)) => {
            unsafe { set_err(err_out, &msg) };
            failure
        }
        Err(_) => {
            unsafe { set_err(err_out, &format!("internal error: {what}")) };
            failure
        }
    }
}

/// Runs a pure query against `p`, returning `default` for NULL input, `None`,
/// or a panic. The one place the query-or-default mapping is written.
///
/// # Safety
/// `p` must be NULL or a valid pointer to a live `Project`.
pub(crate) unsafe fn project_get<T, F>(p: *const Project, default: T, get: F) -> T
where
    F: FnOnce(&Project) -> Option<T>,
{
    if p.is_null() {
        return default;
    }
    let project = unsafe { &*p };
    match catch_unwind(AssertUnwindSafe(|| get(project))) {
        Ok(Some(value)) => value,
        _ => default,
    }
}

/// A JSON-returning query against `p`: NULL input, `None`, or a panic all
/// yield NULL.
///
/// # Safety
/// `p` must be NULL or a valid pointer to a live `Project`.
pub(crate) unsafe fn project_json<F>(p: *const Project, get: F) -> *mut c_char
where
    F: FnOnce(&Project) -> Option<String>,
{
    unsafe { project_get(p, ptr::null_mut(), |project| get(project).map(out_string)) }
}
