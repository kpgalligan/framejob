//! C FFI: the motion-graphics engine (road map 10 §5e) — nine `rc_graphic_*`
//! exports delegating to the `graphic` crate. **The only module of the core
//! that names that crate** (G-2): the core still does no pixel work and
//! reaches no file; it hands the app's bytes to the engine and the engine's
//! answer back.
//!
//! Two handles. An `RcGraphicLibrary` is a BUILDER of `graphic::Library`,
//! which is immutable because its `version` hashes every byte in it: fonts
//! and assets are added until the first `compile` or `rasterize` against it
//! FREEZES it into one `Arc<Library>`, and every add after that is refused.
//! So a library never changes under a compiled graphic. An `RcGraphic` wraps
//! a `graphic::Module`, whose own `Arc` keeps the library's fonts alive
//! after `rc_graphic_library_free`, so the two frees may come in any order.
//!
//! **`diag_out`** is the channel of every export that draws or compiles: NULL
//! or a JSON ARRAY of `{level, message, line, column, frame}`, keys in that
//! order (`Diagnostic::to_json`). A failure always writes exactly ONE error —
//! the crate's own, or this file's for an argument it could not read, or a
//! caught panic's `internal error: <what>` shaped the same way. A success
//! writes it only when there are warnings. `add_font` and `add_asset` refuse
//! through a plain `err_out`, as every other export in the header does.

use std::collections::BTreeMap;
use std::ffi::c_char;
use std::ptr;
use std::slice;
use std::sync::{Arc, Mutex, MutexGuard, OnceLock};

use graphic::{Diagnostic, Library, Module};
use serde_json::Value;

use crate::ffi_util::{
    boxed, fallible_op, fallible_op_wrapped, out_string, read_cstr, read_opt_cstr, set_message,
};

/// The refusal of an add after the first use.
const FROZEN: &str =
    "the library is frozen: a graphic was compiled or a frame drawn against it; build a new one";

/// A font and asset set being assembled, then the one `Library` it froze
/// into. `Sync`: the adds lock `pending`, and the freeze takes it whole.
pub struct RcGraphicLibrary {
    pending: Mutex<Option<Pending>>,
    built: OnceLock<Arc<Library>>,
}

/// What has been added and not yet frozen.
#[derive(Default)]
struct Pending {
    fonts: Vec<Vec<u8>>,
    assets: BTreeMap<String, Vec<u8>>,
}

/// A compiled graphic module; `Send + Sync`, each drawing thread keeping its
/// own engine (`graphic`'s `runtime.rs`).
pub struct RcGraphic {
    module: Module,
}

fn lock(lib: &RcGraphicLibrary) -> MutexGuard<'_, Option<Pending>> {
    lib.pending
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// The library, frozen on first call: the pending fonts and assets are taken
/// under the lock an add holds, so an add either lands before the freeze or
/// finds `None` and is refused.
fn frozen(lib: &RcGraphicLibrary) -> Arc<Library> {
    lib.built
        .get_or_init(|| {
            let pending = lock(lib).take().unwrap_or_default();
            Arc::new(Library::new(pending.fonts, pending.assets))
        })
        .clone()
}

/// A list of Diagnostics as the JSON array `diag_out` carries.
fn diag_json(list: &[Diagnostic]) -> String {
    Value::Array(list.iter().map(Diagnostic::to_json).collect()).to_string()
}

/// One error Diagnostic's array, for an argument this file could not read.
fn diag_error(message: String) -> String {
    diag_json(&[Diagnostic::error(message)])
}

/// Reads `len` bytes at `bytes` into an owned vector.
///
/// # Safety
/// `bytes` must be NULL or point to `len` readable bytes.
unsafe fn read_bytes(bytes: *const u8, len: usize) -> Result<Vec<u8>, String> {
    if bytes.is_null() {
        return Err("bytes is NULL".to_string());
    }
    Ok(unsafe { slice::from_raw_parts(bytes, len) }.to_vec())
}

/// A new, empty library builder. Never NULL.
///
/// # Safety
/// Takes no pointers; the handle is owned by the caller and freed with
/// [`rc_graphic_library_free`].
#[no_mangle]
pub unsafe extern "C" fn rc_graphic_library_new() -> *mut RcGraphicLibrary {
    boxed(RcGraphicLibrary {
        pending: Mutex::new(Some(Pending::default())),
        built: OnceLock::new(),
    })
}

/// Adds one font file's bytes (`.ttf`/`.otf`/`.ttc`). False with a message
/// through `err_out` for a NULL argument, bytes that load no face, or a
/// library already frozen by a `compile` or `rasterize`.
///
/// # Safety
/// `lib` must be NULL or a live handle from [`rc_graphic_library_new`];
/// `bytes` must be NULL or point to `len` readable bytes; `err_out` must be
/// NULL or a valid pointer to writable `*mut c_char`, freed with
/// `rc_string_free`.
#[no_mangle]
pub unsafe extern "C" fn rc_graphic_library_add_font(
    lib: *mut RcGraphicLibrary,
    bytes: *const u8,
    len: usize,
    err_out: *mut *mut c_char,
) -> bool {
    let body = || {
        if lib.is_null() {
            return Err("library is NULL".to_string());
        }
        let data = unsafe { read_bytes(bytes, len) }?;
        // The crate answers a faceless blob with a warning; a one-font
        // throwaway library is how this door reads it.
        if !Library::new(vec![data.clone()], BTreeMap::new())
            .warnings()
            .is_empty()
        {
            return Err("font bytes loaded no face".to_string());
        }
        match lock(unsafe { &*lib }).as_mut() {
            Some(pending) => {
                pending.fonts.push(data);
                Ok(())
            }
            None => Err(FROZEN.to_string()),
        }
    };
    unsafe { fallible_op(err_out, "adding a font", false, body, |()| true) }
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

/// Releases a library handle. NULL-tolerant. A graphic compiled against it
/// keeps its fonts alive.
///
/// # Safety
/// `lib` must be NULL or a live handle not already freed.
#[no_mangle]
pub unsafe extern "C" fn rc_graphic_library_free(lib: *mut RcGraphicLibrary) {
    if lib.is_null() {
        return;
    }
    let body = || {
        drop(unsafe { Box::from_raw(lib) });
        Ok(())
    };
    unsafe { fallible_op(ptr::null_mut(), "freeing a library", (), body, |()| ()) }
}

/// Compiles `source` as the ES module `name` against `lib` (freezing it),
/// under a deadline of `budget_ms` for the module's top level. NULL with one
/// error Diagnostic through `diag_out` on failure.
///
/// # Safety
/// `lib` must be NULL or a live library handle; `name` and `source` must be
/// NULL or valid NUL-terminated C strings; `diag_out` must be NULL or a
/// valid pointer to writable `*mut c_char`, freed with `rc_string_free`.
/// The handle is owned by the caller and freed with [`rc_graphic_free`].
#[no_mangle]
pub unsafe extern "C" fn rc_graphic_compile(
    lib: *const RcGraphicLibrary,
    name: *const c_char,
    source: *const c_char,
    budget_ms: u32,
    diag_out: *mut *mut c_char,
) -> *mut RcGraphic {
    let body = || {
        if lib.is_null() {
            return Err(diag_error("library is NULL".to_string()));
        }
        let name = unsafe { read_cstr(name, "name") }.map_err(diag_error)?;
        let source = unsafe { read_cstr(source, "source") }.map_err(diag_error)?;
        let library = frozen(unsafe { &*lib });
        Module::compile(library, &name, &source, u64::from(budget_ms)).map_err(|d| diag_json(&[d]))
    };
    unsafe {
        fallible_op_wrapped(
            diag_out,
            "compiling a graphic",
            ptr::null_mut(),
            body,
            |module| boxed(RcGraphic { module }),
            diag_error,
        )
    }
}

/// The graphic as `{"meta":…,"schema":…,"revision":…}`: its exported `meta`
/// and `schema` in the module's own key order, and the SHA-256 of its
/// source. NULL only for NULL.
///
/// # Safety
/// `g` must be NULL or a live handle from [`rc_graphic_compile`]. The string
/// is freed with `rc_string_free`.
#[no_mangle]
pub unsafe extern "C" fn rc_graphic_describe(g: *const RcGraphic) -> *mut c_char {
    if g.is_null() {
        return ptr::null_mut();
    }
    let body = || {
        let module = unsafe { &(*g).module };
        Ok(serde_json::json!({
            "meta": module.meta(),
            "schema": module.schema(),
            "revision": module.revision(),
        })
        .to_string())
    };
    unsafe {
        fallible_op(
            ptr::null_mut(),
            "describing",
            ptr::null_mut(),
            body,
            out_string,
        )
    }
}

/// The SVG of frame `frame`, `props_json` overlaid on the schema's defaults
/// (NULL is `{}`), `ctx_json` the context object, under a deadline of
/// `budget_ms`. NULL with one error Diagnostic through `diag_out` on
/// failure; on success `diag_out` is written only when there are warnings.
///
/// # Safety
/// `g` must be NULL or a live graphic handle; `props_json` and `ctx_json`
/// must be NULL or valid NUL-terminated C strings; `diag_out` must be NULL
/// or a valid pointer to writable `*mut c_char`. Both strings are freed with
/// `rc_string_free`.
#[no_mangle]
pub unsafe extern "C" fn rc_graphic_svg(
    g: *const RcGraphic,
    frame: i64,
    props_json: *const c_char,
    ctx_json: *const c_char,
    budget_ms: u32,
    diag_out: *mut *mut c_char,
) -> *mut c_char {
    let body = || {
        if g.is_null() {
            return Err(diag_error("graphic is NULL".to_string()));
        }
        let props = match unsafe { read_opt_cstr(props_json, "props_json") }.map_err(diag_error)? {
            None => Value::Object(serde_json::Map::new()),
            Some(text) => serde_json::from_str(&text)
                .map_err(|e| diag_error(format!("props_json is not JSON: {e}")))?,
        };
        let ctx_text = unsafe { read_cstr(ctx_json, "ctx_json") }.map_err(diag_error)?;
        let ctx: Value = serde_json::from_str(&ctx_text)
            .map_err(|e| diag_error(format!("ctx_json is not JSON: {e}")))?;
        let module = unsafe { &(*g).module };
        graphic::svg(module, frame, &props, &ctx, u64::from(budget_ms)).map_err(|d| diag_json(&[d]))
    };
    unsafe {
        fallible_op_wrapped(
            diag_out,
            "drawing a graphic's frame",
            ptr::null_mut(),
            body,
            |(svg, warnings)| {
                if !warnings.is_empty() {
                    set_message(diag_out, &diag_json(&warnings));
                }
                out_string(svg)
            },
            diag_error,
        )
    }
}

/// Draws `svg` with `lib`'s fonts and assets (freezing it) into `out_bgra`:
/// `w`×`h` premultiplied BGRA rows `stride` bytes apart, the bytes past
/// `w × 4` in a row untouched. False with one error Diagnostic through
/// `diag_out` on failure, and nothing written; on success `diag_out` is
/// written only when there are warnings.
///
/// # Safety
/// `lib` must be NULL or a live library handle; `svg` must be NULL or a
/// valid NUL-terminated C string; `out_bgra` must be NULL or point to
/// `h × stride` writable bytes; `diag_out` must be NULL or a valid pointer
/// to writable `*mut c_char`, freed with `rc_string_free`.
#[no_mangle]
pub unsafe extern "C" fn rc_graphic_rasterize(
    lib: *const RcGraphicLibrary,
    svg: *const c_char,
    w: u32,
    h: u32,
    out_bgra: *mut u8,
    stride: usize,
    diag_out: *mut *mut c_char,
) -> bool {
    let body = || {
        if lib.is_null() {
            return Err(diag_error("library is NULL".to_string()));
        }
        let svg = unsafe { read_cstr(svg, "svg") }.map_err(diag_error)?;
        if out_bgra.is_null() {
            return Err(diag_error("out_bgra is NULL".to_string()));
        }
        let len = (h as usize)
            .checked_mul(stride)
            .filter(|&n| n <= isize::MAX as usize)
            .ok_or_else(|| diag_error("height × stride overflows".to_string()))?;
        let out = unsafe { slice::from_raw_parts_mut(out_bgra, len) };
        let library = frozen(unsafe { &*lib });
        graphic::rasterize(&library, &svg, w, h, out, stride).map_err(|d| diag_json(&[d]))
    };
    unsafe {
        fallible_op_wrapped(
            diag_out,
            "rasterizing a graphic",
            false,
            body,
            |warnings| {
                if !warnings.is_empty() {
                    set_message(diag_out, &diag_json(&warnings));
                }
                true
            },
            diag_error,
        )
    }
}

/// Releases a graphic handle. NULL-tolerant.
///
/// # Safety
/// `g` must be NULL or a live handle not already freed.
#[no_mangle]
pub unsafe extern "C" fn rc_graphic_free(g: *mut RcGraphic) {
    if g.is_null() {
        return;
    }
    let body = || {
        drop(unsafe { Box::from_raw(g) });
        Ok(())
    };
    unsafe { fallible_op(ptr::null_mut(), "freeing a graphic", (), body, |()| ()) }
}
