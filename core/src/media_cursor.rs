//! A media's cursor file as an op (road map "creator-jobs" CU5, spec §11
//! CU-50): `set_media_cursor {media, cursor}`, the one way an edit points a
//! media at its `.fjcursor`, clears it, or moves it — the Media tab's
//! Locate… and Remove, Consolidate's second copy (CU-51) and the open-time
//! re-anchor (CU-52) all write through it.
//!
//! - **The read.** `cursor` is read strictly ([`read_cursor`]), as
//!   `media_color.rs` reads `color`: an object or `null`; only the keys
//!   `path`, `bookmark` and `in_picture`; then the record's own shape
//!   ([`MediaCursor`], `in_picture` required). Each miss is an `Err` naming
//!   it, as is an unknown media.
//! - **The rules** are `cursor_props.rs`'s `check_media_cursor` (CU-39): an
//!   empty path, and a media that is not a video with a picture, each
//!   refused in its own sentence. The value is stored as given. The core
//!   opens no file, so nothing here compares the file's `movie_size` with
//!   the movie's; the app's tool and Locate… do (CU-50 (b)).
//! - **Identities.** `null` on a media with no cursor, and a value equal to
//!   the stored one.

use serde_json::Value;

use crate::cursor_props::check_media_cursor;
use crate::export::describe;
use crate::model::{MediaCursor, Project};
use crate::outcome::Outcome;

/// The keys a `cursor` may carry: the record's own.
const CURSOR_KEYS: [&str; 3] = ["path", "bookmark", "in_picture"];

/// `cursor` read strictly: `None` for `null`, else the record, or the `Err`
/// naming what is wrong — not an object, an unknown key, or a value serde
/// refuses (its own sentence).
fn read_cursor(cursor: &Value) -> Result<Option<MediaCursor>, String> {
    let fields = match cursor {
        Value::Null => return Ok(None),
        Value::Object(fields) => fields,
        other => {
            return Err(format!(
                "cursor must be a json object or null, not {}",
                describe(other)
            ))
        }
    };
    if let Some(key) = fields
        .keys()
        .find(|key| !CURSOR_KEYS.contains(&key.as_str()))
    {
        return Err(format!("unknown key \"{key}\" in cursor"));
    }
    serde_json::from_value(cursor.clone())
        .map(Some)
        .map_err(|e| format!("cursor does not match the schema: {e}"))
}

impl Project {
    /// Sets or clears `media`'s cursor file (spec §11 CU-50). `Err` for an
    /// unknown media or an unreadable `cursor`; an identity for `null` on a
    /// media with none or a value equal to the stored one; a refusal, in
    /// `check_media_cursor`'s own sentence, for an empty path or a media
    /// that is not a video with a picture.
    pub(crate) fn set_media_cursor(&self, media: u32, cursor: &Value) -> Result<Outcome, String> {
        let current = self.require_media(media)?;
        let asked = read_cursor(cursor)?;
        if current.cursor == asked {
            return Ok(Outcome::Identity);
        }
        let mut next = self.clone();
        let Some(row) = next.media.iter_mut().find(|m| m.id == media) else {
            return Err(format!("no media with id {media}"));
        };
        row.cursor = asked;
        if let Err(why) = check_media_cursor(row) {
            return Ok(Outcome::Refused(why));
        }
        self.finish(next)
    }
}
