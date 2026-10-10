//! C FFI: a `.cube` 3D LUT (spec §11 GR-8) — four `rc_cube_*` exports over
//! `cube.rs`'s `Cube`, each a thin shim through `ffi_util.rs`'s helpers. An
//! `RcCube` is parsed once from the file's bytes, read (its size and its
//! table) and freed with `rc_cube_free`; it is immutable, so it may be read
//! from any thread.

use std::ffi::c_char;
use std::ptr;
use std::slice;

use crate::cube::Cube;
use crate::ffi_util::{boxed, fallible_op, free_boxed, read_bytes};

/// Parses `len` bytes at `bytes` as a `.cube` file. NULL with the reason
/// through `err_out` — the parser's lowercase sentence (`line 2:
/// LUT_3D_SIZE 200 is outside 2–65`, `the file is larger than 32 MB`, …),
/// or `bytes is NULL`.
///
/// # Safety
/// `bytes` must be NULL or point to `len` readable bytes; `err_out` must be
/// NULL or a valid pointer to writable `*mut c_char`, freed with
/// `rc_string_free`. The handle is freed with [`rc_cube_free`].
#[no_mangle]
pub unsafe extern "C" fn rc_cube_parse(
    bytes: *const u8,
    len: usize,
    err_out: *mut *mut c_char,
) -> *mut Cube {
    let body = || {
        let data = unsafe { read_bytes(bytes, len) }?;
        Cube::parse(&data)
    };
    unsafe { fallible_op(err_out, "parsing a LUT", ptr::null_mut(), body, boxed) }
}

/// Points an axis (2–65); 0 for NULL.
///
/// # Safety
/// `cube` must be NULL or a live handle from [`rc_cube_parse`].
#[no_mangle]
pub unsafe extern "C" fn rc_cube_size(cube: *const Cube) -> u32 {
    if cube.is_null() {
        return 0;
    }
    let body = || Ok(unsafe { &*cube }.size());
    unsafe { fallible_op(ptr::null_mut(), "reading a LUT's size", 0, body, |n| n) }
}

/// Copies the table, red fastest, into the `count` floats at `out`; false
/// (and `out` untouched) for NULL or unless `count` is `size³ · 3`.
///
/// # Safety
/// `cube` must be NULL or a live handle from [`rc_cube_parse`]; `out` must
/// be NULL or point to `count` writable floats.
#[no_mangle]
pub unsafe extern "C" fn rc_cube_copy_rgb(cube: *const Cube, out: *mut f32, count: usize) -> bool {
    if cube.is_null() || out.is_null() {
        return false;
    }
    let body = || {
        let cube = unsafe { &*cube };
        if count != cube.rgb.len() {
            return Ok(false);
        }
        let target = unsafe { slice::from_raw_parts_mut(out, count) };
        Ok(cube.copy_rgb(target))
    };
    unsafe { fallible_op(ptr::null_mut(), "copying a LUT", false, body, |b| b) }
}

/// Releases a LUT. NULL-tolerant.
///
/// # Safety
/// `cube` must be NULL or a live handle from [`rc_cube_parse`] not already
/// freed.
#[no_mangle]
pub unsafe extern "C" fn rc_cube_free(cube: *mut Cube) {
    unsafe { free_boxed(cube, "freeing a LUT") }
}
