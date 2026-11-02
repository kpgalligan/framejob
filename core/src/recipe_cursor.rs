//! A recipe layer's `cursor` key (format 38, spec §7.3, §11 CU-32): what the
//! compositor needs to draw a media's recorded cursor in its clip's layer —
//! the media whose cursor file it is, the source tick to read it at, whether
//! the clip plays reversed, and the clip's cursor props — or `null`.
//!
//! The key is `null` unless the clip's source is a `media` or a `still`, its
//! media has `media.cursor`, that cursor is not `in_picture` (the movie's
//! own picture already shows the pointer, CU-35), and the evaluated props
//! show the pointer or ripple its clicks. `at` is `freeze_frame`'s source
//! tick — `in` plus `source_read_by` (round(S) on a ramp, the base rate
//! otherwise), never below 0, in the stream the clip PLAYS, the reversed one
//! when reversed — or a still's own `at`. The core mirrors nothing (D4-6):
//! the app reads a reversed tick through `ReverseMirror`. `smoothing` and
//! `hide_idle` are the clip's BASE values (`with_base_cursor`), and `props`
//! is all eight keys, so it passes whole to `rc_cursor_query`'s `state`
//! (CU-25).

use serde_json::{Map, Value};

use crate::cursor_props::{clamp_cursor, with_base_cursor};
use crate::evaluate::{json, number};
use crate::model::{Clip, CursorClicks, Project, Source, VideoProps};
use crate::source_window::source_read_by;
use crate::time::Ticks;

impl Project {
    /// The `cursor` key of `clip`'s layer at clip time `clip_t`, given its
    /// evaluated video props (CU-32): `null`, or `{media, at, reversed,
    /// smoothing, hide_idle, props}`.
    pub(crate) fn layer_cursor(&self, clip: &Clip, clip_t: Ticks, evaluated: &VideoProps) -> Value {
        let (media, at, reversed) = match &clip.source {
            Source::Media {
                media,
                r#in,
                reversed,
            } => (
                *media,
                r#in.saturating_add(source_read_by(clip, clip_t)).max(0),
                *reversed,
            ),
            Source::Still { media, at } => (*media, *at, false),
            _ => return Value::Null,
        };
        let Some(file) = self.media(media).and_then(|m| m.cursor.as_ref()) else {
            return Value::Null;
        };
        if file.in_picture {
            return Value::Null;
        }
        let mut cursor = with_base_cursor(evaluated.clone(), clip.video.as_ref()).cursor;
        // A file's base values are not checked on read; the evaluator's
        // clamp holds the published props to their ranges whatever they are.
        clamp_cursor(&mut cursor);
        let props = cursor.unwrap_or_default();
        if !props.show && props.clicks != CursorClicks::Ripple {
            return Value::Null;
        }
        let mut out = Map::new();
        out.insert("media".to_string(), Value::from(media));
        out.insert("at".to_string(), Value::from(at));
        out.insert("reversed".to_string(), Value::from(reversed));
        out.insert("smoothing".to_string(), number(props.smoothing));
        out.insert("hide_idle".to_string(), json(&props.hide_idle));
        out.insert("props".to_string(), json(&props));
        Value::Object(out)
    }
}
