//! C FFI: a PQ file's HDR10 peak (spec §11 HD-12) — one export over
//! `hdr10.rs`'s pure reader, a thin shim through `ffi_util.rs`'s helpers.
//! The import probe hands it the bytes AVFoundation gives it (the format
//! description's two extensions, else the first sample) and stores the
//! answer on the media.

use std::ffi::c_char;
use std::ptr;
use std::slice;

use crate::ffi_util::{fallible_op, out_string};
use crate::hdr10;

/// `len` bytes at `bytes`, or `None` for a NULL pointer or a 0 length (an
/// absent extension or sample).
///
/// # Safety
/// `bytes` must be NULL or point to `len` readable bytes that outlive the
/// returned slice.
unsafe fn optional<'a>(bytes: *const u8, len: usize) -> Option<&'a [u8]> {
    if bytes.is_null() || len == 0 {
        return None;
    }
    Some(unsafe { slice::from_raw_parts(bytes, len) })
}

/// The peak `hdr10::peak` reads: JSON `{"file": N, "from": "max_cll" |
/// "mastering_display"}`, or `{}` when nothing was read. `mastering` and
/// `content_light` are the format description's `MasteringDisplayColorVolume`
/// and `ContentLightLevelInfo` (read when either is given); `sample` the
/// first video sample, its NAL units prefixed by `nal_length_size` bytes
/// (read only when neither extension is given). A NULL pointer or a 0 length
/// is absent. NULL only on a caught panic. Freed with `rc_string_free`.
///
/// # Safety
/// Each pointer must be NULL or point to its length's readable bytes, valid
/// for the call.
#[no_mangle]
pub unsafe extern "C" fn rc_hdr10_peak(
    mastering: *const u8,
    mastering_len: usize,
    content_light: *const u8,
    content_light_len: usize,
    sample: *const u8,
    sample_len: usize,
    nal_length_size: u32,
) -> *mut c_char {
    let body = || {
        let mastering = unsafe { optional(mastering, mastering_len) };
        let content_light = unsafe { optional(content_light, content_light_len) };
        let sample = unsafe { optional(sample, sample_len) };
        let length = usize::try_from(nal_length_size).unwrap_or(0);
        let read = hdr10::peak(mastering, content_light, sample, length);
        serde_json::to_string(&read).map_err(|e| e.to_string())
    };
    unsafe {
        fallible_op(
            ptr::null_mut(),
            "reading an HDR10 peak",
            ptr::null_mut(),
            body,
            out_string,
        )
    }
}
