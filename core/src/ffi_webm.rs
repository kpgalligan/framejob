//! C FFI: the WebM writer (spec §11 CX-6, CX-15) — five `rc_webm_*`
//! exports over `webm_writer.rs`'s `WebmWriter`, each a thin shim through
//! `ffi_util.rs`'s helpers. An `RcWebm` holds the writer behind a mutex, so
//! the app's video and audio queues may add packets, end tracks and finish
//! from several threads at once; each call is whole before the next starts.

use std::ffi::c_char;
use std::path::Path;
use std::ptr;
use std::slice;
use std::sync::{Mutex, MutexGuard};

use crate::ffi_util::{boxed, fallible_op, free_boxed, read_cstr};
use crate::webm_writer::WebmWriter;

/// The handle `rc_webm_open` answers: one file being written.
pub struct RcWebm(Mutex<WebmWriter>);

/// The writer behind `webm`, locked, or the sentence refusing the call.
///
/// # Safety
/// `webm` must be NULL or a live handle from [`rc_webm_open`].
unsafe fn locked<'a>(webm: *const RcWebm) -> Result<MutexGuard<'a, WebmWriter>, String> {
    if webm.is_null() {
        return Err("webm is NULL".to_string());
    }
    unsafe { &*webm }
        .0
        .lock()
        .map_err(|_| "the writer stopped after an internal error".to_string())
}

/// Creates the file at `path` and writes its header from `layout_json` (the
/// header's keys). NULL with a lowercase sentence through `err_out` naming
/// the value when the layout is refused or the file cannot be created.
///
/// # Safety
/// `path` and `layout_json` must be NULL or valid NUL-terminated C strings;
/// `err_out` must be NULL or a valid pointer to writable `*mut c_char`,
/// freed with `rc_string_free`. The handle is freed with [`rc_webm_free`].
#[no_mangle]
pub unsafe extern "C" fn rc_webm_open(
    path: *const c_char,
    layout_json: *const c_char,
    err_out: *mut *mut c_char,
) -> *mut RcWebm {
    let body = || {
        let path = unsafe { read_cstr(path, "path") }?;
        let layout = unsafe { read_cstr(layout_json, "layout_json") }?;
        WebmWriter::open(Path::new(&path), &layout).map(|w| RcWebm(Mutex::new(w)))
    };
    unsafe { fallible_op(err_out, "opening a webm file", ptr::null_mut(), body, boxed) }
}

/// Adds one packet of `track` (`RC_WEBM_VIDEO` or `RC_WEBM_AUDIO`) at
/// `pts_ns`, writing what the interleave allows. False with the sentence
/// through `err_out` for NULL, an unknown or ended track, a negative pts or
/// one not after the track's last, a call after finish, or an I/O failure.
///
/// # Safety
/// `webm` must be NULL or a live handle; `bytes` must be NULL or point to
/// `len` readable bytes; `err_out` as [`rc_webm_open`]'s.
#[no_mangle]
pub unsafe extern "C" fn rc_webm_add_packet(
    webm: *mut RcWebm,
    track: u32,
    pts_ns: i64,
    key: bool,
    discard_padding_ns: i64,
    bytes: *const u8,
    len: usize,
    err_out: *mut *mut c_char,
) -> bool {
    let body = || {
        let mut writer = unsafe { locked(webm) }?;
        if bytes.is_null() {
            return Err("bytes is NULL".to_string());
        }
        let data = unsafe { slice::from_raw_parts(bytes, len) };
        writer.add_packet(track, pts_ns, key, discard_padding_ns, data)
    };
    unsafe { fallible_op(err_out, "adding a webm packet", false, body, |()| true) }
}

/// Ends `track`: no packet of it follows. False with the sentence through
/// `err_out` for NULL, an unknown or ended track, or a call after finish.
///
/// # Safety
/// `webm` must be NULL or a live handle; `err_out` as [`rc_webm_open`]'s.
#[no_mangle]
pub unsafe extern "C" fn rc_webm_end_track(
    webm: *mut RcWebm,
    track: u32,
    err_out: *mut *mut c_char,
) -> bool {
    let body = || unsafe { locked(webm) }?.end_track(track);
    unsafe { fallible_op(err_out, "ending a webm track", false, body, |()| true) }
}

/// Writes every queued packet, the Cues, the SeekHead and the Segment's size,
/// and closes the file. False with the sentence through `err_out` for NULL,
/// a second finish, or an I/O failure.
///
/// # Safety
/// `webm` must be NULL or a live handle; `err_out` as [`rc_webm_open`]'s.
#[no_mangle]
pub unsafe extern "C" fn rc_webm_finish(webm: *mut RcWebm, err_out: *mut *mut c_char) -> bool {
    let body = || unsafe { locked(webm) }?.finish();
    unsafe { fallible_op(err_out, "finishing a webm file", false, body, |()| true) }
}

/// Releases a writer. NULL-tolerant. A file not finished is left as it is,
/// for the app to remove.
///
/// # Safety
/// `webm` must be NULL or a live handle not already freed.
#[no_mangle]
pub unsafe extern "C" fn rc_webm_free(webm: *mut RcWebm) {
    unsafe { free_boxed(webm, "freeing a webm writer") }
}
