//! C FFI: a cursor file (spec §11 CU-9, CU-10) — `rc_cursor_open` and
//! `rc_cursor_free` over `cursor_file.rs`'s `CursorFile`, each a thin shim
//! through `ffi_util.rs`'s helpers. An `RcCursor` is parsed and checked once
//! from the file's bytes; a check is an open and a free (the recorder's
//! read-back, CU-15). It is immutable, so it may be read from any thread.

use std::ffi::c_char;
use std::ptr;

use crate::cursor_file::CursorFile;
use crate::ffi_util::{boxed, fallible_op, free_boxed, read_bytes};

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
) -> *mut CursorFile {
    let body = || {
        let data = unsafe { read_bytes(bytes, len) }?;
        CursorFile::parse(&data)
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
pub unsafe extern "C" fn rc_cursor_free(cursor: *mut CursorFile) {
    unsafe { free_boxed(cursor, "freeing a cursor file") }
}
