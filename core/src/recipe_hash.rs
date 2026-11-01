//! The content hash — the key Swift's texture cache is keyed by — moved out
//! of `recipe.rs` whole (a pure move), which re-exports `content_hash`
//! `pub(crate)`, so every `crate::recipe::content_hash` path holds.

use serde_json::Value;

/// FNV-1a, 64-bit. A CACHE KEY, not a security digest: Swift keys its
/// rendered text and shape textures by this hex string, so all that is
/// asked of it is that the same description always produces the same key
/// and that two different descriptions rarely collide. FNV is a dozen lines
/// with no dependency, which is the whole reason it is here rather than a
/// real hash crate.
const FNV_OFFSET: u64 = 0xcbf2_9ce4_8422_2325;
const FNV_PRIME: u64 = 0x0000_0100_0000_01b3;

fn fnv1a(bytes: &[u8]) -> u64 {
    let mut hash = FNV_OFFSET;
    for byte in bytes {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(FNV_PRIME);
    }
    hash
}

/// The content hash of a rendered layer's description, over its keys
/// SORTED at every depth: `serde_json`'s `Map` keeps insertion order in this
/// build (`graphic` turns `preserve_order` on), so the sort is what makes
/// two clips with identical text hash the same and share one texture — and
/// it is the order every hash before the link was taken in.
pub(crate) fn content_hash(description: &Value) -> String {
    format!("{:016x}", fnv1a(sorted(description).to_string().as_bytes()))
}

/// `value` with every object's keys in sorted order, recursively.
fn sorted(value: &Value) -> Value {
    match value {
        Value::Object(map) => {
            let keys: std::collections::BTreeMap<&String, Value> =
                map.iter().map(|(k, v)| (k, sorted(v))).collect();
            Value::Object(keys.into_iter().map(|(k, v)| (k.clone(), v)).collect())
        }
        Value::Array(items) => Value::Array(items.iter().map(sorted).collect()),
        other => other.clone(),
    }
}
