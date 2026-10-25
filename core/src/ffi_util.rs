//! Shared plumbing for every `ffi*` shim: error reporting through
//! `err_out`, panic-safe wrappers, the handle getters every handle type
//! shares, and the string conversions every shim needs. Nothing here is exported through
//! the C header — these are the helpers the exported functions are built
//! from, so the conventions (catch_unwind everywhere, NULL tolerance, heap
//! CString errors freed with `rc_string_free`) live in ONE place.

use std::ffi::{c_char, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;
use std::slice;

/// Stores a heap-allocated copy of `msg` through a `char **` out-parameter
/// (if non-NULL). Interior NUL bytes are replaced so the `CString`
/// conversion cannot fail.
///
/// The header has two such channels and this is the one spelling of both:
/// `err_out`, which every export carries and which means the request was
/// invalid, and `rc_project_apply`'s `reason_out`, which carries a rule's
/// refusal. What they MEAN differs; how they allocate must not.
///
/// # Safety
/// `out` must be NULL or a valid pointer to writable `*mut c_char`.
pub(crate) unsafe fn set_message(out: *mut *mut c_char, msg: &str) {
    if out.is_null() {
        return;
    }
    let sanitized = msg.replace('\0', " ");
    let cstring = CString::new(sanitized)
        .unwrap_or_else(|_| CString::new("framejob-core error").expect("static string"));
    unsafe {
        *out = cstring.into_raw();
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

/// Reads `len` bytes at `bytes` into an owned vector.
///
/// # Safety
/// `bytes` must be NULL or point to `len` readable bytes.
pub(crate) unsafe fn read_bytes(bytes: *const u8, len: usize) -> Result<Vec<u8>, String> {
    if bytes.is_null() {
        return Err("bytes is NULL".to_string());
    }
    Ok(unsafe { slice::from_raw_parts(bytes, len) }.to_vec())
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

/// Drops a handle [`boxed`] made, under [`fallible_op`] with no channel;
/// NULL is a no-op.
///
/// # Safety
/// `p` must be NULL or a live handle from [`boxed`] not already freed.
pub(crate) unsafe fn free_boxed<T>(p: *mut T, what: &str) {
    if p.is_null() {
        return;
    }
    let body = || {
        drop(unsafe { Box::from_raw(p) });
        Ok(())
    };
    unsafe { fallible_op(ptr::null_mut(), what, (), body, |()| ()) }
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
    unsafe { fallible_op_wrapped(err_out, what, failure, body, success, |msg| msg) }
}

/// [`fallible_op`] for a channel whose messages have a shape of their own:
/// `internal` wraps the caught panic's "internal error: `what`" before it is
/// written (`ffi_graphic.rs`'s `diag_out` is a JSON array of Diagnostics).
/// An `Err` from `body` is written as it stands — shaping it is the body's.
///
/// # Safety
/// `err_out` must be NULL or a valid pointer to writable `*mut c_char`.
pub(crate) unsafe fn fallible_op_wrapped<T, R>(
    err_out: *mut *mut c_char,
    what: &str,
    failure: R,
    body: impl FnOnce() -> Result<T, String>,
    success: impl FnOnce(T) -> R,
    internal: impl FnOnce(String) -> String,
) -> R {
    match catch_unwind(AssertUnwindSafe(body)) {
        Ok(Ok(value)) => success(value),
        Ok(Err(msg)) => {
            unsafe { set_message(err_out, &msg) };
            failure
        }
        Err(_) => {
            let msg = internal(format!("internal error: {what}"));
            unsafe { set_message(err_out, &msg) };
            failure
        }
    }
}

/// Runs a pure query against the handle `h`, returning `default` for NULL
/// input, `None`, or a panic. The one place the query-or-default mapping is
/// written, for every handle type the header hands out.
///
/// # Safety
/// `h` must be NULL or a valid pointer to a live `H`.
pub(crate) unsafe fn handle_get<H, T, F>(h: *const H, default: T, get: F) -> T
where
    F: FnOnce(&H) -> Option<T>,
{
    if h.is_null() {
        return default;
    }
    let handle = unsafe { &*h };
    match catch_unwind(AssertUnwindSafe(|| get(handle))) {
        Ok(Some(value)) => value,
        _ => default,
    }
}

/// A JSON-returning query against the handle `h`: NULL input, `None`, or a
/// panic all yield NULL.
///
/// # Safety
/// `h` must be NULL or a valid pointer to a live `H`.
pub(crate) unsafe fn handle_json<H, F>(h: *const H, get: F) -> *mut c_char
where
    F: FnOnce(&H) -> Option<String>,
{
    unsafe { handle_get(h, ptr::null_mut(), |handle| get(handle).map(out_string)) }
}

/// A string answer with no message channel: [`fallible_op`] with a NULL
/// `err_out`, so an `Err` and a caught panic ("internal error: `what`") both
/// answer NULL and write nothing. Safe, because the one pointer it would
/// need is the NULL it supplies.
pub(crate) fn quiet_string(
    what: &str,
    body: impl FnOnce() -> Result<String, String>,
) -> *mut c_char {
    unsafe { fallible_op(ptr::null_mut(), what, ptr::null_mut(), body, out_string) }
}
