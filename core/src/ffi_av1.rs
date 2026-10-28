//! C FFI: AV1 in MP4's container bytes (spec §11 CX-12 (4)) — three
//! exports over `av1_mp4.rs`'s pure readers, thin shims through
//! `ffi_util.rs`'s helpers. The app's encoder (CX-4) hands over its sequence
//! header, each packet and the written file's first bytes; nothing here
//! encodes.

use std::ffi::c_char;
use std::ptr;
use std::slice;

use serde_json::json;

use crate::av1_mp4;
use crate::container_codec::hex;
use crate::ffi_util::{fallible_op, out_string, read_bytes};

/// The `av1C` record for the first sequence header OBU in `obus` and the
/// fields it restates: JSON `{"av1c_hex", "seq_profile", "seq_level_idx",
/// "seq_tier", "bit_depth", "monochrome", "color": {"primaries",
/// "transfer", "matrix", "full_range"}}`. NULL with a message through
/// `err_out` when there is no sequence header or it ends early, or on a
/// caught panic. Freed with `rc_string_free`.
///
/// # Safety
/// `obus` must be NULL or point to `len` readable bytes, valid for the
/// call; `err_out` must be NULL or a valid pointer to writable `*mut c_char`.
#[no_mangle]
pub unsafe extern "C" fn rc_av1_config(
    obus: *const u8,
    len: usize,
    err_out: *mut *mut c_char,
) -> *mut c_char {
    let body = || {
        let bytes = unsafe { read_bytes(obus, len) }?;
        let config = av1_mp4::config_record(&bytes)?;
        let answer = json!({
            "av1c_hex": hex(&config.record),
            "seq_profile": config.seq_profile,
            "seq_level_idx": config.seq_level_idx,
            "seq_tier": config.seq_tier,
            "bit_depth": config.bit_depth,
            "monochrome": config.monochrome,
            "color": config.color,
        });
        Ok(answer.to_string())
    };
    unsafe {
        fallible_op(
            err_out,
            "building an av1C record",
            ptr::null_mut(),
            body,
            out_string,
        )
    }
}

/// `len` writable bytes at `bytes`, or `None` for a NULL pointer or a 0
/// length.
///
/// # Safety
/// `bytes` must be NULL or point to `len` writable bytes that outlive the
/// returned slice and are not aliased during it.
unsafe fn writable<'a>(bytes: *mut u8, len: usize) -> Option<&'a mut [u8]> {
    if bytes.is_null() || len == 0 {
        return None;
    }
    Some(unsafe { slice::from_raw_parts_mut(bytes, len) })
}

/// Removes every temporal delimiter OBU from the AV1 packet at `bytes`, in
/// place, and answers the length kept. 0 for a NULL pointer, a 0 length, a
/// run that is not whole OBUs (the bytes untouched), or a caught panic.
///
/// # Safety
/// `bytes` must be NULL or point to `len` writable bytes, valid and not
/// aliased for the call.
#[no_mangle]
pub unsafe extern "C" fn rc_av1_strip_temporal_delimiters(bytes: *mut u8, len: usize) -> usize {
    let Some(bytes) = (unsafe { writable(bytes, len) }) else {
        return 0;
    };
    let body = || av1_mp4::strip_temporal_delimiters(bytes).ok_or_else(String::new);
    unsafe {
        fallible_op(
            ptr::null_mut(),
            "stripping temporal delimiters",
            0,
            body,
            |kept| kept,
        )
    }
}

/// Makes the `ftyp` box at the start of `head` carry `av01`: 0 when it
/// already does, 1 when its first `mp41` was rewritten `av01` in place, -1
/// when there is no `ftyp` box at byte 0, it runs past `len`, or it has
/// neither (the bytes untouched), or on a caught panic.
///
/// # Safety
/// `head` must be NULL or point to `len` writable bytes, valid and not
/// aliased for the call.
#[no_mangle]
pub unsafe extern "C" fn rc_av1_ftyp_brand(head: *mut u8, len: usize) -> i32 {
    let Some(head) = (unsafe { writable(head, len) }) else {
        return -1;
    };
    let body = || av1_mp4::brand_av01(head);
    unsafe {
        fallible_op(
            ptr::null_mut(),
            "branding an ftyp box av01",
            -1,
            body,
            i32::from,
        )
    }
}
