//! C FFI: the `.fjgraphic` package — two exports: `rc_graphic_package_write`
//! (spec §11 G-46 (c)), delegating to `graphic_package.rs`, and
//! `rc_graphic_package_read` (G-47 (c)), delegating to
//! `graphic_package_read.rs`. It names no engine type: the app has already
//! chosen the files a package holds, and copies what a read answers.

use std::ffi::c_char;
use std::ptr;

use crate::ffi_util::{fallible_op, out_string, read_bytes, read_cstr};
use crate::graphic_package;
use crate::graphic_package_read;

/// Writes the `.fjgraphic` at `path` (created or truncated). `package_json`
/// is `{"module","title","category","description":string|null,
/// "app_version","files":[{"path","size"}…]}`, each path relative to the
/// project's `graphics/` folder, the first exactly `<module>.js` and every
/// other `fonts/<n>` or `assets/<n>`; `data` is the files' bytes
/// concatenated in that order. Answers the `manifest.json` it wrote. NULL
/// with a lowercase sentence naming the value through `err_out` for a NULL
/// argument, a spec that fails its checks, sizes that do not sum to `len`,
/// an archive past a zip without Zip64, or an I/O failure; an input refusal
/// writes nothing.
///
/// # Safety
/// `path` and `package_json` must be NULL or valid NUL-terminated C
/// strings; `data` must be NULL or point to `len` readable bytes; `err_out`
/// must be NULL or a valid pointer to writable `*mut c_char`. Both strings
/// are freed with `rc_string_free`.
#[no_mangle]
pub unsafe extern "C" fn rc_graphic_package_write(
    path: *const c_char,
    package_json: *const c_char,
    data: *const u8,
    len: usize,
    err_out: *mut *mut c_char,
) -> *mut c_char {
    let body = || {
        let path = unsafe { read_cstr(path, "path") }?;
        let package = unsafe { read_cstr(package_json, "package_json") }?;
        if data.is_null() {
            return Err("data is NULL".to_string());
        }
        let data = unsafe { read_bytes(data, len) }?;
        graphic_package::write(&path, &package, &data)
    };
    unsafe {
        fallible_op(
            err_out,
            "writing a graphic package",
            ptr::null_mut(),
            body,
            out_string,
        )
    }
}

/// Checks the `.fjgraphic` held in `data` (`len` bytes) and answers its
/// manifest as JSON: `{"fjgraphic":1,"module","title","category",
/// "description":string|null,"app_version","files":[{"path","name","size",
/// "sha256","offset"}…]}`, `files[0]` the module and each `offset` the byte
/// offset of that file's data in `data`. NULL with a lowercase sentence
/// naming the value through `err_out` for a NULL `data`, an archive that is
/// not a stored zip without Zip64, a damaged entry or a wrong CRC-32, a
/// manifest that fails its checks or is of a newer format, or entries that
/// do not match the manifest by path, size or SHA-256.
///
/// # Safety
/// `data` must be NULL or point to `len` readable bytes; `err_out` must be
/// NULL or a valid pointer to writable `*mut c_char`. Both strings are freed
/// with `rc_string_free`.
#[no_mangle]
pub unsafe extern "C" fn rc_graphic_package_read(
    data: *const u8,
    len: usize,
    err_out: *mut *mut c_char,
) -> *mut c_char {
    let body = || {
        if data.is_null() {
            return Err("data is NULL".to_string());
        }
        let data = unsafe { read_bytes(data, len) }?;
        graphic_package_read::read(&data)
    };
    unsafe {
        fallible_op(
            err_out,
            "reading a graphic package",
            ptr::null_mut(),
            body,
            out_string,
        )
    }
}
