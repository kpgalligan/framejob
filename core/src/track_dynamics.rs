//! Reading and checking `set_track`'s `compressor` and `limiter` (format 36,
//! spec §11 AU-150): a track's dynamics, run post-fader on its sub-mix
//! (AU-151). The DSP is the Swift side's (`AudioTrackDynamics.swift`, the
//! export's `ExportMixRead.swift`); nothing here touches a sample.
//!
//! Each argument is three-valued, which a plain `Option<Value>` field cannot
//! tell apart: ABSENT keeps the track's value, `null` clears it, and an
//! object REPLACES it whole — the keys it leaves out take the clip type's
//! defaults, never the stored value's, so what a caller sends is what the
//! track holds. [`present`] is the field's `deserialize_with`, which makes
//! `null` arrive as `Some(Value::Null)` rather than `None`.
//!
//! The refusals are the vocabulary's own rule — a key or a value the type
//! does not have is refused, never dropped (`patch.rs`): `compressor must be
//! a json object or null, not 5`, `unknown key "compressor.knee" in
//! set_track`, `bad value at "limiter.release" in set_track: <serde's
//! reason>`, then the range in `in_range`'s sentence under the track's key
//! (`compressor.ratio must be between 1 and 20, not 30`).

use serde::de::DeserializeOwned;
use serde::{Deserialize, Deserializer, Serialize};
use serde_json::Value;

use crate::audio_dynamics::{check_compressor, check_limiter};
use crate::export::describe;
use crate::model::{Compressor, Limiter};
use crate::patch::path_under;

/// What the refusals call the op.
const SUBJECT: &str = "set_track";

/// `deserialize_with` for an argument whose `null` means something: a
/// present key is `Some` of its value, `null` included; an absent one is the
/// field's `default`, `None`.
pub(crate) fn present<'de, D: Deserializer<'de>>(d: D) -> Result<Option<Value>, D::Error> {
    Value::deserialize(d).map(Some)
}

/// `set_track`'s `compressor`: `null` → `Ok(None)` (clear), an object → the
/// whole compressor, range-checked.
pub(crate) fn read_compressor(v: &Value) -> Result<Option<Compressor>, String> {
    let Some(compressor) = read::<Compressor>("compressor", v)? else {
        return Ok(None);
    };
    check_compressor("compressor", &compressor)?;
    Ok(Some(compressor))
}

/// `set_track`'s `limiter`: `null` → `Ok(None)`, an object → the whole
/// limiter, range-checked.
pub(crate) fn read_limiter(v: &Value) -> Result<Option<Limiter>, String> {
    let Some(limiter) = read::<Limiter>("limiter", v)? else {
        return Ok(None);
    };
    check_limiter("limiter", &limiter)?;
    Ok(Some(limiter))
}

/// The kind, the keys against the type's own default's, then the typed read
/// with the path of whatever only the type can refuse.
fn read<T: DeserializeOwned + Serialize + Default>(
    key: &str,
    v: &Value,
) -> Result<Option<T>, String> {
    let given = match v {
        Value::Null => return Ok(None),
        Value::Object(given) => given,
        other => {
            return Err(format!(
                "{key} must be a json object or null, not {}",
                describe(other)
            ))
        }
    };
    let template = serde_json::to_value(T::default()).unwrap_or(Value::Null);
    for name in given.keys() {
        if template.get(name).is_none() {
            return Err(format!("unknown key \"{key}.{name}\" in {SUBJECT}"));
        }
    }
    serde_path_to_error::deserialize(v.clone())
        .map(Some)
        .map_err(|e| {
            let path = path_under(key, &e.path().to_string());
            format!("bad value at \"{path}\" in {SUBJECT}: {}", e.inner())
        })
}
