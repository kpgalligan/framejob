//! What a recipe was asked for BESIDES the instant: [`RecipeOptions`] and
//! its reader (spec §7.3, §7.9's `rc_project_frame_recipe_opts`).
//!
//! A pure move out of `recipe.rs`, which stood at 548 lines against the
//! ~600 cap with no seam named: grading-2's G2-0, paid first and alone, as
//! the Swift side had already cut its own (`RecipeOptions.swift`). The
//! struct and its `of` came here whole, their bodies untouched, and
//! `recipe.rs` re-exports the struct, so `crate::recipe::RecipeOptions`
//! resolves as though the cut had not happened. Nothing was widened.

use serde_json::Value;

// ---- what a caller asked for -------------------------------------------

/// What a recipe was asked for BESIDES the instant (spec §7.3, §7.9's
/// `rc_project_frame_recipe_opts`).
///
/// Two members — the timecode burn-in of road map 2's phase 7 and the
/// ungraded picture of grading GR3 (spec §11 GR-4) — and a struct rather
/// than `bool` arguments because each would otherwise be a second FFI
/// signature and a third. One struct behind one
/// `opts_json` string is the shape the header already uses for
/// `rc_export_settings`' `overrides_json`.
///
/// **It is deliberately NOT an export override.** `export_overrides.rs`
/// IGNORES an unknown key so a newer UI still gets an export, so an option
/// posted through `rc_export_settings` would vanish silently and the
/// `export` tool would report success on an un-burnt file. An option that
/// changes the PICTURE has to travel with the thing that describes the
/// picture.
///
/// Nothing here persists. These are a question asked of a project, not a
/// property of one, so no format version moves when a member is added —
/// which is the same reason the export overrides are not in the schema
/// either.
#[derive(Debug, Clone, Copy, Default)]
pub struct RecipeOptions {
    /// Draw the project timecode at `t` over everything else.
    pub burn_in_timecode: bool,
    /// Every layer's `video.color` neutral (all thirteen keys), its wheels
    /// neutral (all nine, spec §11 GR-11) and its look removed, nested and
    /// matte layers included: the picture as if no clip were graded.
    pub ungraded: bool,
}

impl RecipeOptions {
    /// The options a JSON value asks for. An absent key, a key of the wrong
    /// type and a document that is not an object at all all mean OFF.
    ///
    /// It is read by hand rather than derived, and that is the whole point.
    /// A `#[serde(default)]` derive would make `{"burn_in_timecode": "yes"}`
    /// an `Err`, and there is nowhere on this path to put the message: the
    /// query exports carry no `err_out` (`ffi_query.rs`'s module doc says
    /// why), so the only two answers available are a recipe and NULL, and
    /// NULL at frame rate is a black preview. OFF is the picture the caller
    /// would have got before the option existed, which is the failure
    /// direction the rest of `recipe.rs` already fails in — `number()` turning
    /// a non-finite value into 0, `Reveal`'s ramp failing toward SHOWING the
    /// text.
    ///
    /// A mistyped option is still refused BY NAME, one layer up: the MCP
    /// handler reads it through `AgentServer+Arguments.swift`'s throwing
    /// `boolArg`, which has a caller to tell. This is the layer that has
    /// nobody.
    pub fn of(value: &Value) -> RecipeOptions {
        RecipeOptions {
            burn_in_timecode: value
                .get("burn_in_timecode")
                .and_then(Value::as_bool)
                .unwrap_or(false),
            ungraded: value
                .get("ungraded")
                .and_then(Value::as_bool)
                .unwrap_or(false),
        }
    }
}
