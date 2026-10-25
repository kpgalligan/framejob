//! C FFI: a PQ file's HDR10 peak (spec §11 HD-12, HD-18, HD-20) — three
//! exports over `hdr10.rs`'s and `hdr10_still.rs`'s pure readers, thin shims
//! through `ffi_util.rs`'s helpers. The import probe hands them the bytes
//! AVFoundation gives it (the format description's two extensions, else the
//! first sample; for AV1 the `av1C` record and the first sample), or a PQ
//! still's whole file, and stores the answer on the media.

use std::ffi::c_char;
use std::slice;

use crate::ffi_util::quiet_string;
use crate::hdr10;
use crate::hdr10_still;

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
    quiet_string("reading an HDR10 peak", body)
}

/// The peak `hdr10::av1_peak` reads from an AV1 track whose description
/// carries neither extension (spec §11 HD-18 (c)): `config` the `av1C`
/// record, `sample` the first video sample with data; JSON as
/// `rc_hdr10_peak`'s. A NULL pointer or a 0 length is absent. NULL only on a
/// caught panic. Freed with `rc_string_free`.
///
/// # Safety
/// Each pointer must be NULL or point to its length's readable bytes, valid
/// for the call.
#[no_mangle]
pub unsafe extern "C" fn rc_hdr10_av1_peak(
    config: *const u8,
    config_len: usize,
    sample: *const u8,
    sample_len: usize,
) -> *mut c_char {
    let body = || {
        let config = unsafe { optional(config, config_len) };
        let sample = unsafe { optional(sample, sample_len) };
        let read = hdr10::av1_peak(config, sample);
        serde_json::to_string(&read).map_err(|e| e.to_string())
    };
    quiet_string("reading an AV1 HDR10 peak", body)
}

/// The peak `hdr10_still::still_peak` reads from a PQ still's whole file
/// (spec §11 HD-20 (b)): a PNG's `cLLI`/`mDCV`, an ISOBMFF file's primary
/// item's `clli`/`mdcv`; JSON as `rc_hdr10_peak`'s, `{}` for a NULL pointer
/// or a 0 length. NULL only on a caught panic. Freed with `rc_string_free`.
///
/// # Safety
/// `file` must be NULL or point to `file_len` readable bytes, valid for the
/// call.
#[no_mangle]
pub unsafe extern "C" fn rc_hdr10_still_peak(file: *const u8, file_len: usize) -> *mut c_char {
    let body = || {
        let read = unsafe { optional(file, file_len) }
            .map(hdr10_still::still_peak)
            .unwrap_or_default();
        serde_json::to_string(&read).map_err(|e| e.to_string())
    };
    quiet_string("reading a still's HDR10 peak", body)
}
