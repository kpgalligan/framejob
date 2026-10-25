//! C FFI: a WebM or Matroska file's index (spec §11 #216-R) — six
//! `rc_container_*` exports over `container.rs`'s `Container`, each a thin
//! shim through `ffi_util.rs`'s helpers. An `RcContainer` is opened once
//! and freed with `rc_container_free`; `rc_container_retime` is its one
//! mutation, comes before any sample is read and must have no concurrent
//! reader. After it, `rc_container_sample` and `rc_container_sample_count`
//! may be called from several threads at once (the app's rewrap reads it
//! from both pumps' queues): they only read the index.

use std::ffi::c_char;
use std::path::Path;
use std::ptr;

use crate::container::{Container, RcContainerSample};
use crate::ffi_util::{boxed, fallible_op, free_boxed, handle_get, handle_json, read_cstr};
use crate::time::Fps;

/// Opens and indexes the WebM or Matroska file at `path`, read-only. NULL
/// with the reason through `err_out` (a lowercase clause: "its DocType is
/// “x”, not webm or matroska", "track 1's CodecPrivate is … bytes, over the 1
/// MiB limit", …) when the file cannot be read as one.
///
/// # Safety
/// `path` must be NULL or a valid NUL-terminated C string; `err_out` must be
/// NULL or a valid pointer to writable `*mut c_char`, freed with
/// `rc_string_free`. The handle is freed with [`rc_container_free`].
#[no_mangle]
pub unsafe extern "C" fn rc_container_open(
    path: *const c_char,
    err_out: *mut *mut c_char,
) -> *mut Container {
    let body = || {
        let path = unsafe { read_cstr(path, "path") }?;
        Container::open(Path::new(&path))
    };
    unsafe { fallible_op(err_out, "opening a container", ptr::null_mut(), body, boxed) }
}

/// The index described as JSON (the header's keys). NULL only for NULL.
///
/// # Safety
/// `container` must be NULL or a live handle from [`rc_container_open`]. The
/// string is freed with `rc_string_free`.
#[no_mangle]
pub unsafe extern "C" fn rc_container_describe(container: *const Container) -> *mut c_char {
    unsafe { handle_json(container, |c| Some(c.describe().to_string())) }
}

/// Snaps the video to the grid of `fps_num`/`fps_den` when every frame lies
/// on it; true when it did. False for NULL, a rate either term of which is
/// not in 1…u32::MAX, or video off the grid, which keeps its raw times.
///
/// # Safety
/// `container` must be NULL or a live handle from [`rc_container_open`] that
/// no other thread is reading.
#[no_mangle]
pub unsafe extern "C" fn rc_container_retime(
    container: *mut Container,
    fps_num: i64,
    fps_den: i64,
) -> bool {
    let (Ok(num), Ok(den)) = (u32::try_from(fps_num), u32::try_from(fps_den)) else {
        return false;
    };
    if container.is_null() {
        return false;
    }
    let body = || Ok(unsafe { &mut *container }.retime(Fps { num, den }));
    unsafe { fallible_op(ptr::null_mut(), "retiming a container", false, body, |b| b) }
}

/// The copied samples of `track` (`RC_CONTAINER_VIDEO` or
/// `RC_CONTAINER_AUDIO`); 0 for NULL, another track, or one not copied.
///
/// # Safety
/// `container` must be NULL or a live handle from [`rc_container_open`].
#[no_mangle]
pub unsafe extern "C" fn rc_container_sample_count(container: *const Container, track: u32) -> u64 {
    unsafe { handle_get(container, 0, |c| Some(c.sample_count(track))) }
}

/// Writes the `index`th sample of `track`, in decode order, through `out`;
/// false (and `out` untouched) for NULL or an index past the count.
///
/// # Safety
/// `container` must be NULL or a live handle from [`rc_container_open`];
/// `out` must be NULL or point to a writable `RcContainerSample`.
#[no_mangle]
pub unsafe extern "C" fn rc_container_sample(
    container: *const Container,
    track: u32,
    index: u64,
    out: *mut RcContainerSample,
) -> bool {
    if container.is_null() || out.is_null() {
        return false;
    }
    let body = || Ok(unsafe { &*container }.sample(track, index));
    let write = |found: Option<RcContainerSample>| match found {
        Some(sample) => {
            unsafe { *out = sample };
            true
        }
        None => false,
    };
    unsafe { fallible_op(ptr::null_mut(), "reading a sample", false, body, write) }
}

/// Releases a container. NULL-tolerant.
///
/// # Safety
/// `container` must be NULL or a live handle not already freed.
#[no_mangle]
pub unsafe extern "C" fn rc_container_free(container: *mut Container) {
    unsafe { free_boxed(container, "freeing a container") }
}
