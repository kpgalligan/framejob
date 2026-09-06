//! Shared helpers for Reelcut's black-box tests.
//!
//! Every test in `core/tests/` drives the crate the way the app does — over
//! the C surface in `core/include/reelcut_core.h` — so this module owns the
//! pointer dance once: NUL-terminating the JSON that goes in, freeing every
//! string that comes back through `rc_string_free`, freeing every handle
//! through `rc_project_free`, and turning the header's three-way answer
//! into a Rust value a test can match on.
//!
//! That three-way answer is the reason [`Handle::try_apply`] exists and is
//! worth reading before writing a test (spec §5.5, and the doc comment on
//! `rc_project_apply`):
//!
//! - a new handle — the edit changed something;
//! - NULL with `err_out` UNTOUCHED — the op is valid but changes nothing
//!   (an identity edit or a documented refusal); the app registers no undo
//!   step. Here: `Ok(None)`, asserted with [`Handle::refuses`].
//! - NULL with `err_out` SET — the op or an argument is invalid. Here:
//!   `Err(message)`, asserted with [`Handle::errors`].
//!
//! Add to this file rather than re-deriving a helper inside a test: a
//! second copy of the pointer dance is a second place for a leak to hide.

// Each test binary compiles this module separately and uses a different
// slice of it, so "never used here" says nothing about the helper.
#![allow(dead_code)]

use std::ffi::{c_char, CStr, CString};
use std::ptr;

use serde_json::Value;

use reelcut_core::ffi::{
    rc_project_clone, rc_project_free, rc_project_from_json, rc_project_new, rc_project_to_json,
    rc_string_free,
};
use reelcut_core::ffi_edit::rc_project_apply;
use reelcut_core::ffi_query::{
    rc_export_settings, rc_export_sizes, rc_project_clip_state, rc_project_composition_plan,
    rc_project_duration, rc_project_frame_recipe, rc_project_snap_candidates,
};
use reelcut_core::model::Project;

// ---- strings -------------------------------------------------------------

/// A NUL-terminated copy of `s` for passing to the FFI. Panics on an
/// interior NUL, which only a test typo can produce.
pub fn cstring(s: &str) -> CString {
    CString::new(s).expect("test string contains an interior NUL")
}

/// Copies a string the library returned and frees it with `rc_string_free`,
/// which is the header's rule for EVERY `char *` it hands back. `None` for
/// NULL.
pub fn take_string(raw: *mut c_char) -> Option<String> {
    if raw.is_null() {
        return None;
    }
    let owned = unsafe { CStr::from_ptr(raw) }
        .to_str()
        .expect("the library returned a string that is not UTF-8")
        .to_string();
    unsafe { rc_string_free(raw) };
    Some(owned)
}

/// [`take_string`] plus the assertion that the pointer was not NULL.
pub fn expect_string(raw: *mut c_char, what: &str) -> String {
    take_string(raw).unwrap_or_else(|| panic!("{what} returned NULL"))
}

/// Parses JSON the library returned, naming the caller in the panic.
pub fn parse_json(text: &str, what: &str) -> Value {
    serde_json::from_str(text).unwrap_or_else(|e| panic!("{what} is not valid json: {e}\n{text}"))
}

/// Asserts `haystack` contains `needle`, printing both when it does not —
/// the way every "the message names the offending value" check reads.
pub fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected the message to contain {needle:?}, got {haystack:?}"
    );
}

// ---- ops -----------------------------------------------------------------

/// Anything a test can hand to an edit: a `serde_json::Value` built with
/// `json!` for the normal case, or a raw `&str` for the malformed-envelope
/// cases that must not reach `json!` at all.
pub trait OpText {
    fn op_text(&self) -> String;
}

impl OpText for str {
    fn op_text(&self) -> String {
        self.to_string()
    }
}

impl OpText for String {
    fn op_text(&self) -> String {
        self.clone()
    }
}

impl OpText for Value {
    fn op_text(&self) -> String {
        self.to_string()
    }
}

// ---- project handles -----------------------------------------------------

/// An owned `RcProject` handle: the same opaque, immutable pointer the app
/// holds, freed on drop so a failing test cannot leak a project.
pub struct Handle {
    ptr: *mut Project,
}

impl Handle {
    /// `rc_project_new`, asserting it produced a handle.
    pub fn new(width: u32, height: u32, fps_num: u32, fps_den: u32) -> Handle {
        let ptr = unsafe { rc_project_new(width, height, fps_num, fps_den) };
        assert!(
            !ptr.is_null(),
            "rc_project_new({width}, {height}, {fps_num}/{fps_den}) returned NULL"
        );
        Handle { ptr }
    }

    /// `rc_project_from_json`, asserting the project parsed.
    pub fn from_json(json: &str) -> Handle {
        match Handle::try_from_json(json) {
            Ok(handle) => handle,
            Err(msg) => panic!("this project was expected to parse, but: {msg}\n{json}"),
        }
    }

    /// The same, built from a `json!` value.
    pub fn from_value(project: &Value) -> Handle {
        Handle::from_json(&project.to_string())
    }

    /// `rc_project_from_json` with its failure message, for the tests that
    /// assert a refusal (a bad version, a busted cap, a broken invariant).
    pub fn try_from_json(json: &str) -> Result<Handle, String> {
        let text = cstring(json);
        let mut err: *mut c_char = ptr::null_mut();
        let ptr_ = unsafe { rc_project_from_json(text.as_ptr(), &mut err) };
        if ptr_.is_null() {
            // The header promises a NULL handle here ALWAYS carries a
            // message: this export has no "valid but changes nothing" case.
            let msg = take_string(err)
                .expect("rc_project_from_json returned NULL without setting err_out");
            return Err(msg);
        }
        assert!(
            err.is_null(),
            "rc_project_from_json returned a handle AND set err_out"
        );
        Ok(Handle { ptr: ptr_ })
    }

    /// The same, from a `json!` value.
    pub fn try_from_value(project: &Value) -> Result<Handle, String> {
        Handle::try_from_json(&project.to_string())
    }

    /// The raw handle, for the NULL-safety sweep and anything else that
    /// needs to call an export directly.
    pub fn as_ptr(&self) -> *const Project {
        self.ptr
    }

    /// `rc_project_clone` — a deep copy, as its own handle.
    pub fn duplicate(&self) -> Handle {
        let ptr = unsafe { rc_project_clone(self.ptr) };
        assert!(!ptr.is_null(), "rc_project_clone returned NULL");
        Handle { ptr }
    }

    /// The project as the pretty JSON that goes in the file.
    pub fn to_json(&self) -> String {
        expect_string(
            unsafe { rc_project_to_json(self.ptr) },
            "rc_project_to_json",
        )
    }

    /// The project as a parsed value.
    pub fn value(&self) -> Value {
        let text = self.to_json();
        parse_json(&text, "rc_project_to_json")
    }

    /// `rc_project_duration`.
    pub fn duration(&self) -> i64 {
        unsafe { rc_project_duration(self.ptr) }
    }

    /// Applies one op the header's way, mapping the three answers onto
    /// `Ok(Some)` / `Ok(None)` / `Err` (see this module's doc).
    pub fn try_apply(&self, op: &(impl OpText + ?Sized)) -> Result<Option<Handle>, String> {
        let text = cstring(&op.op_text());
        let mut err: *mut c_char = ptr::null_mut();
        let next = unsafe { rc_project_apply(self.ptr, text.as_ptr(), &mut err) };
        match (next.is_null(), take_string(err)) {
            (true, Some(msg)) => Err(msg),
            (true, None) => Ok(None),
            (false, None) => Ok(Some(Handle { ptr: next })),
            (false, Some(msg)) => {
                unsafe { rc_project_free(next) };
                panic!("rc_project_apply returned a handle AND the error {msg:?}")
            }
        }
    }

    /// Applies an op that MUST change something.
    pub fn apply(&self, op: &(impl OpText + ?Sized)) -> Handle {
        match self.try_apply(op) {
            Ok(Some(next)) => next,
            Ok(None) => panic!(
                "this op was expected to change the project, but it changed nothing: {}",
                op.op_text()
            ),
            Err(msg) => panic!(
                "this op was expected to apply, but: {msg}\n{}",
                op.op_text()
            ),
        }
    }

    /// Applies a sequence of ops, each of which must change something.
    pub fn apply_all(&self, ops: &[Value]) -> Handle {
        let mut current = self.duplicate();
        for op in ops {
            current = current.apply(op);
        }
        current
    }

    /// Asserts the op is VALID but changes nothing — NULL with `err_out`
    /// untouched, the answer that must register no undo step.
    pub fn refuses(&self, op: &(impl OpText + ?Sized)) {
        match self.try_apply(op) {
            Ok(None) => {}
            Ok(Some(_)) => panic!(
                "this op was expected to change nothing, but it applied: {}",
                op.op_text()
            ),
            Err(msg) => panic!(
                "this op was expected to change nothing, but it errored: {msg}\n{}",
                op.op_text()
            ),
        }
    }

    /// Asserts the op is INVALID and returns the message, for the caller to
    /// check names the offending value.
    pub fn errors(&self, op: &(impl OpText + ?Sized)) -> String {
        match self.try_apply(op) {
            Err(msg) => msg,
            Ok(Some(_)) => panic!(
                "this op was expected to error, but it applied: {}",
                op.op_text()
            ),
            Ok(None) => panic!(
                "this op was expected to error, but it only changed nothing: {}",
                op.op_text()
            ),
        }
    }

    /// The composition plan (spec §7.2) as the RAW string the FFI returned.
    ///
    /// Swift compares this string against the plan it last built and
    /// rebuilds its `AVMutableComposition` only on a difference (spec §7.6),
    /// so a test about that decision has to compare the same bytes — a
    /// re-serialized `Value` would normalize away exactly the differences
    /// the comparison is looking for.
    pub fn plan_text(&self) -> String {
        expect_string(
            unsafe { rc_project_composition_plan(self.ptr) },
            "rc_project_composition_plan",
        )
    }

    /// The composition plan (spec §7.2), parsed.
    pub fn plan(&self) -> Value {
        let text = self.plan_text();
        parse_json(&text, "rc_project_composition_plan")
    }

    /// The frame recipe at `t` (spec §7.3), parsed.
    pub fn recipe(&self, t: i64) -> Value {
        let text = expect_string(
            unsafe { rc_project_frame_recipe(self.ptr, t) },
            "rc_project_frame_recipe",
        );
        parse_json(&text, "rc_project_frame_recipe")
    }

    /// One clip's evaluated state at project time `t`; `None` for an
    /// unknown clip id.
    pub fn clip_state(&self, clip: u32, t: i64) -> Option<Value> {
        take_string(unsafe { rc_project_clip_state(self.ptr, clip, t) })
            .map(|text| parse_json(&text, "rc_project_clip_state"))
    }

    /// Snap candidates, with the dragged clips excluded.
    pub fn snap_candidates(&self, exclude: &[u32]) -> Value {
        let json = serde_json::to_string(exclude).expect("a list of ids always serializes");
        let text = cstring(&json);
        let out = expect_string(
            unsafe { rc_project_snap_candidates(self.ptr, text.as_ptr()) },
            "rc_project_snap_candidates",
        );
        parse_json(&out, "rc_project_snap_candidates")
    }

    /// The Size popup's rows for `preset` — `rc_export_sizes` — or the
    /// message explaining the refusal.
    pub fn export_sizes(&self, preset: &str) -> Result<Value, String> {
        let preset_text = cstring(preset);
        let mut err: *mut c_char = ptr::null_mut();
        let raw = unsafe { rc_export_sizes(self.ptr, preset_text.as_ptr(), &mut err) };
        match take_string(raw) {
            Some(text) => {
                assert!(
                    err.is_null(),
                    "rc_export_sizes returned sizes AND set err_out"
                );
                Ok(parse_json(&text, "rc_export_sizes"))
            }
            None => {
                Err(take_string(err)
                    .expect("rc_export_sizes returned NULL without setting err_out"))
            }
        }
    }

    /// Resolved export settings, or the message explaining the refusal.
    pub fn export_settings(
        &self,
        preset: &str,
        overrides: Option<&Value>,
    ) -> Result<Value, String> {
        let preset_text = cstring(preset);
        let overrides_text = overrides.map(|value| cstring(&value.to_string()));
        let overrides_ptr = match &overrides_text {
            Some(text) => text.as_ptr(),
            None => ptr::null(),
        };
        let mut err: *mut c_char = ptr::null_mut();
        let raw =
            unsafe { rc_export_settings(self.ptr, preset_text.as_ptr(), overrides_ptr, &mut err) };
        match take_string(raw) {
            Some(text) => {
                assert!(
                    err.is_null(),
                    "rc_export_settings returned settings AND set err_out"
                );
                Ok(parse_json(&text, "rc_export_settings"))
            }
            None => {
                Err(take_string(err)
                    .expect("rc_export_settings returned NULL without setting err_out"))
            }
        }
    }
}

impl Drop for Handle {
    fn drop(&mut self) {
        unsafe { rc_project_free(self.ptr) };
    }
}

/// A shape, not an address: this is what `expect_err` prints when a project
/// a test expected to be refused was accepted instead, and a 4096-clip JSON
/// dump would bury the failure.
impl std::fmt::Debug for Handle {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let project = self.value();
        let count = |key: &str| project[key].as_array().map(Vec::len).unwrap_or(0);
        write!(
            f,
            "Handle {{ media: {}, tracks: {}, clips: {}, markers: {}, duration: {} }}",
            count("media"),
            count("tracks"),
            count("clips"),
            count("markers"),
            self.duration()
        )
    }
}

// ---- reading JSON --------------------------------------------------------

/// A JSON pointer lookup that names the missing path instead of panicking
/// with `None`. `at(&project, "/clips/0/duration")`.
pub fn at<'a>(value: &'a Value, pointer: &str) -> &'a Value {
    value
        .pointer(pointer)
        .unwrap_or_else(|| panic!("no value at {pointer} in {value}"))
}

/// A number at `pointer`, as f64 — JSON writes `1` and `1.0` for the same
/// f64 field depending on the value, so tests must not compare `Value`s.
pub fn num(value: &Value, pointer: &str) -> f64 {
    at(value, pointer).as_f64().unwrap_or_else(|| {
        panic!(
            "the value at {pointer} is not a number: {}",
            at(value, pointer)
        )
    })
}

/// An integer (a tick count, an id) at `pointer`.
pub fn int(value: &Value, pointer: &str) -> i64 {
    at(value, pointer).as_i64().unwrap_or_else(|| {
        panic!(
            "the value at {pointer} is not an integer: {}",
            at(value, pointer)
        )
    })
}

/// A string at `pointer`.
pub fn text<'a>(value: &'a Value, pointer: &str) -> &'a str {
    at(value, pointer).as_str().unwrap_or_else(|| {
        panic!(
            "the value at {pointer} is not a string: {}",
            at(value, pointer)
        )
    })
}

/// A boolean at `pointer` — `enabled.video`, `track.locked`, a marker's
/// `chapter`. The flags are half of what an edit op changes, so reading one
/// deserves the same "name the path" panic every other accessor gives.
pub fn flag(value: &Value, pointer: &str) -> bool {
    at(value, pointer).as_bool().unwrap_or_else(|| {
        panic!(
            "the value at {pointer} is not a boolean: {}",
            at(value, pointer)
        )
    })
}

/// An array at `pointer`.
pub fn array<'a>(value: &'a Value, pointer: &str) -> &'a Vec<Value> {
    at(value, pointer).as_array().unwrap_or_else(|| {
        panic!(
            "the value at {pointer} is not an array: {}",
            at(value, pointer)
        )
    })
}

/// The element of the array at `pointer` whose `"id"` is `id` — how a test
/// finds one clip, track, media or marker after an edit reordered nothing
/// in particular.
pub fn by_id<'a>(value: &'a Value, pointer: &str, id: u64) -> &'a Value {
    array(value, pointer)
        .iter()
        .find(|item| item.get("id").and_then(Value::as_u64) == Some(id))
        .unwrap_or_else(|| panic!("no element with id {id} in {pointer}"))
}
