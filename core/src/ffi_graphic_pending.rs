//! C FFI: the graphic library builder's pending half (road map 10 §5e) —
//! what has been added to an `RcGraphicLibrary` and not yet frozen, the
//! lock an add holds, and the two exports that never name the `graphic`
//! crate: `rc_graphic_library_new` and `rc_graphic_library_add_asset`.
//! `ffi_graphic.rs` holds the handle, the freeze and every other export
//! (and re-exports these two), and stays the only module that names the
//! crate (G-2).

use std::collections::BTreeMap;
use std::ffi::c_char;
use std::sync::{Mutex, MutexGuard, OnceLock};

use crate::ffi_graphic::RcGraphicLibrary;
use crate::ffi_util::{boxed, fallible_op, read_bytes, read_cstr};

/// The refusal of an add after the first use.
pub(crate) const FROZEN: &str =
    "the library is frozen: a graphic was compiled or a frame drawn against it; build a new one";

/// What has been added and not yet frozen.
#[derive(Default)]
pub(crate) struct Pending {
    pub(crate) fonts: Vec<Vec<u8>>,
    pub(crate) assets: BTreeMap<String, Vec<u8>>,
}

pub(crate) fn lock(lib: &RcGraphicLibrary) -> MutexGuard<'_, Option<Pending>> {
    lib.pending
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// A new, empty library builder. Never NULL.
///
/// # Safety
/// Takes no pointers; the handle is owned by the caller and freed with
/// [`rc_graphic_library_free`](crate::ffi_graphic::rc_graphic_library_free).
#[no_mangle]
pub unsafe extern "C" fn rc_graphic_library_new() -> *mut RcGraphicLibrary {
    boxed(RcGraphicLibrary {
        pending: Mutex::new(Some(Pending::default())),
        built: OnceLock::new(),
    })
}

/// Adds one asset under `name`, the string a graphic's `<image href>`
/// names. False with a message through `err_out` for a NULL argument, an
/// empty name, a name already in the library, or a frozen library.
///
/// # Safety
/// `lib` must be NULL or a live handle from [`rc_graphic_library_new`];
/// `name` must be NULL or a valid NUL-terminated C string; `bytes` must be
/// NULL or point to `len` readable bytes; `err_out` must be NULL or a valid
/// pointer to writable `*mut c_char`, freed with `rc_string_free`.
#[no_mangle]
pub unsafe extern "C" fn rc_graphic_library_add_asset(
    lib: *mut RcGraphicLibrary,
    name: *const c_char,
    bytes: *const u8,
    len: usize,
    err_out: *mut *mut c_char,
) -> bool {
    let body = || {
        if lib.is_null() {
            return Err("library is NULL".to_string());
        }
        let name = unsafe { read_cstr(name, "name") }?;
        if name.is_empty() {
            return Err("name is empty".to_string());
        }
        let data = unsafe { read_bytes(bytes, len) }?;
        let mut guard = lock(unsafe { &*lib });
        let Some(pending) = guard.as_mut() else {
            return Err(FROZEN.to_string());
        };
        if pending.assets.contains_key(&name) {
            return Err(format!("asset \"{name}\" is already in the library"));
        }
        pending.assets.insert(name, data);
        Ok(())
    };
    unsafe { fallible_op(err_out, "adding an asset", false, body, |()| true) }
}
