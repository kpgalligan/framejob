//! C FFI: the motion-graphics engine (road map 10 §5e) — twelve
//! `rc_graphic_*` exports delegating to the `graphic` crate (the builder's
//! `new` and `add_asset` live in `ffi_graphic_pending.rs`, re-exported
//! here), the eleventh the engine's decoded-image cache (spec §11 G-39), the
//! twelfth what a library's parses and measures used (G-46 (b)). **The
//! only module of the core that names that crate** (G-2): the core still
//! does no pixel work and reaches no file; it hands the app's bytes to the
//! engine and the engine's answer back.
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
use std::sync::{Arc, Mutex, OnceLock};

use graphic::{Diagnostic, Library, Module};
use serde_json::Value;

use crate::ffi_graphic_pending::{lock, Pending, FROZEN};
pub use crate::ffi_graphic_pending::{rc_graphic_library_add_asset, rc_graphic_library_new};
use crate::ffi_util::{
    boxed, fallible_op, fallible_op_wrapped, free_boxed, handle_json, out_string, read_bytes,
    read_cstr, read_opt_cstr, set_message,
};

/// A font and asset set being assembled, then the one `Library` it froze
/// into. `Sync`: the adds lock `pending`, and the freeze takes it whole.
pub struct RcGraphicLibrary {
    pub(crate) pending: Mutex<Option<Pending>>,
    pub(crate) built: OnceLock<Arc<Library>>,
}

/// A compiled graphic module; `Send + Sync`, each drawing thread keeping its
/// own engine (`graphic`'s `runtime.rs`).
pub struct RcGraphic {
    module: Module,
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

/// The frozen library's families as a JSON array of strings, sorted and
/// deduplicated: the engine's own names, the exact strings a `font-family`
/// must match. Freezes the library as a compile would. NULL only for NULL.
///
/// # Safety
/// `lib` must be NULL or a live handle from [`rc_graphic_library_new`]. The
/// string is freed with `rc_string_free`.
#[no_mangle]
pub unsafe extern "C" fn rc_graphic_library_families(lib: *const RcGraphicLibrary) -> *mut c_char {
    unsafe {
        handle_json(lib, |lib| {
            Some(Value::from(frozen(lib).families().to_vec()).to_string())
        })
    }
}

/// `{"fonts":[<blob index>…],"assets":[<name>…]}`: the font blobs (indexes
/// in the order they were added, a faceless one counted) whose faces a parse
/// or a measure against `lib` selected, directly or as a fallback, ascending;
/// and the image assets it resolved, sorted. Cumulative over the library's
/// life (G-46 (b)). Freezes the library as a compile would. NULL only for
/// NULL.
///
/// # Safety
/// `lib` must be NULL or a live handle from [`rc_graphic_library_new`]. The
/// string is freed with `rc_string_free`.
#[no_mangle]
pub unsafe extern "C" fn rc_graphic_library_usage(lib: *const RcGraphicLibrary) -> *mut c_char {
    unsafe {
        handle_json(lib, |lib| {
            let usage = frozen(lib).usage();
            Some(serde_json::json!({"fonts": usage.fonts, "assets": usage.assets}).to_string())
        })
    }
}

/// Releases a library handle. NULL-tolerant. A graphic compiled against it
/// keeps its fonts alive.
///
/// # Safety
/// `lib` must be NULL or a live handle not already freed.
#[no_mangle]
pub unsafe extern "C" fn rc_graphic_library_free(lib: *mut RcGraphicLibrary) {
    unsafe { free_boxed(lib, "freeing a library") }
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

/// The graphic as `{"meta":…,"schema":…,"revision":…,"warnings":[…]}`: its
/// exported `meta` and `schema` in the module's own key order, the SHA-256 of
/// its source, and what its top level warned as it loaded (G-24 (a)), shaped
/// as `diag_out`'s entries, `[]` when none. NULL only for NULL.
///
/// # Safety
/// `g` must be NULL or a live handle from [`rc_graphic_compile`]. The string
/// is freed with `rc_string_free`.
#[no_mangle]
pub unsafe extern "C" fn rc_graphic_describe(g: *const RcGraphic) -> *mut c_char {
    let describe = |g: &RcGraphic| {
        let module = &g.module;
        Some(
            serde_json::json!({
                "meta": module.meta(),
                "schema": module.schema(),
                "revision": module.revision(),
                "warnings": module.warnings().iter().map(Diagnostic::to_json).collect::<Vec<_>>(),
            })
            .to_string(),
        )
    };
    unsafe { handle_json(g, describe) }
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
    unsafe { free_boxed(g, "freeing a graphic") }
}

/// The engine's decoded-image cache (spec §11 G-39): sets its limit in
/// bytes, trims it least recently used first, and answers the bytes it
/// holds after; 0 empties it. Never fails; a caught panic answers 0.
///
/// # Safety
/// Takes no pointers.
#[no_mangle]
pub unsafe extern "C" fn rc_graphic_image_cache(limit_bytes: usize) -> usize {
    let body = || Ok(graphic::set_image_cache_limit(limit_bytes));
    unsafe {
        fallible_op(
            ptr::null_mut(),
            "setting the image cache",
            0,
            body,
            |held| held,
        )
    }
}
