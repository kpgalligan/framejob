//! C FFI: a cursor file (spec §11 CU-9, CU-10, CU-25) — `rc_cursor_open`,
//! `rc_cursor_free` and `rc_cursor_query` over `cursor_track.rs`'s
//! `CursorTrack`, each a thin shim through `ffi_util.rs`'s helpers. An
//! `RcCursor` is parsed and checked once from the file's bytes; a check is an
//! open and a free (the recorder's read-back, CU-15). It holds its prepared
//! paths under a lock, so any thread may query it.

use std::ffi::c_char;
use std::ptr;
use std::slice;

use crate::cursor_query::query;
use crate::cursor_track::CursorTrack;
use crate::ffi_util::{boxed, fallible_op, free_boxed, out_string, read_bytes, read_cstr};
use crate::model::Project;

/// Parses and checks `len` bytes at `bytes` as a cursor file. NULL with the
/// reason through `err_out` — `cursor_file.rs`'s sentence ("the cursor file
/// is version 2; this Frame Job reads cursor files up to version 1", …), or
/// `bytes is NULL`.
///
/// # Safety
/// `bytes` must be NULL or point to `len` readable bytes; `err_out` must be
/// NULL or a valid pointer to writable `*mut c_char`, freed with
/// `rc_string_free`. The handle is freed with [`rc_cursor_free`].
#[no_mangle]
pub unsafe extern "C" fn rc_cursor_open(
    bytes: *const u8,
    len: usize,
    err_out: *mut *mut c_char,
) -> *mut CursorTrack {
    let body = || {
        let data = unsafe { read_bytes(bytes, len) }?;
        CursorTrack::parse(&data)
    };
    unsafe {
        fallible_op(
            err_out,
            "opening a cursor file",
            ptr::null_mut(),
            body,
            boxed,
        )
    }
}

/// Releases a cursor file. NULL-tolerant.
///
/// # Safety
/// `cursor` must be NULL or a live handle from [`rc_cursor_open`] not
/// already freed.
#[no_mangle]
pub unsafe extern "C" fn rc_cursor_free(cursor: *mut CursorTrack) {
    unsafe { free_boxed(cursor, "freeing a cursor file") }
}

/// Answers one JSON request (`cursor_query.rs`'s vocabulary, spec §11
/// CU-25) against the `n` tracks at `tracks`; `project` may be NULL and is
/// unused by today's requests. NULL with the sentence through `err_out` on
/// any refusal ("request_json is NULL", "tracks is NULL", "tracks[i] is
/// NULL", "the cursor request at …", …). The answer is freed with
/// `rc_string_free`.
///
/// # Safety
/// `tracks` must be NULL or point to `n` pointers, each NULL or a live
/// handle from [`rc_cursor_open`]; `project` NULL or a live project handle;
/// `request_json` NULL or a NUL-terminated string; `err_out` NULL or a valid
/// pointer to writable `*mut c_char`, freed with `rc_string_free`.
#[no_mangle]
pub unsafe extern "C" fn rc_cursor_query(
    tracks: *const *const CursorTrack,
    n: usize,
    project: *const Project,
    request_json: *const c_char,
    err_out: *mut *mut c_char,
) -> *mut c_char {
    let body = || {
        let request = unsafe { read_cstr(request_json, "request_json") }?;
        if tracks.is_null() {
            return Err("tracks is NULL".to_string());
        }
        let pointers = unsafe { slice::from_raw_parts(tracks, n) };
        let mut list = Vec::with_capacity(n);
        for (i, &track) in pointers.iter().enumerate() {
            if track.is_null() {
                return Err(format!("tracks[{i}] is NULL"));
            }
            list.push(unsafe { &*track });
        }
        let project = unsafe { project.as_ref() };
        query(&list, project, &request)
    };
    unsafe {
        fallible_op(
            err_out,
            "querying a cursor file",
            ptr::null_mut(),
            body,
            out_string,
        )
    }
}
