//! The described clips — text, shape, and the shared tail graphic and
//! adjustment clips use — a pure move out of `edit_clip.rs`.
//!
//! The two ops here that DO take a patch — `add_text_clip` and
//! `add_shape_clip` — build their preset and then hand it to `edit_props`'s
//! merge and `props_check`'s checks, so a `text` argument is validated
//! exactly as a later `set_text` would be.

use serde_json::Value;

use crate::edit_clip::DEFAULT_CLIP_DURATION;
use crate::model::{
    Clip, GraphicProps, Project, ShapeKind, ShapeProps, Source, TextProps, VideoProps,
};
use crate::outcome::Outcome;
use crate::patch::{merge_group, Group};
use crate::props_check::{check_shape, check_text};
use crate::time::Ticks;

/// The font of the Title text preset (spec §4.3). A concrete face, not a
/// family: the renderer asks for exactly this name, and a bold weight is
/// what a title over footage needs to stay legible.
const TITLE_FONT: &str = "SourceSans3-Bold";

/// Placeholder content for a new text clip. A text clip that renders
/// nothing is indistinguishable from a broken one, so a new one says what
/// it is and arrives selected for the user to overtype.
const TITLE_CONTENT: &str = "Title";

/// What a sourceless clip — text, shape or graphic — is made of, so the
/// shared placement tail takes one argument instead of five.
pub(crate) struct Described {
    pub(crate) source: Source,
    pub(crate) scale: f64,
    pub(crate) text: Option<TextProps>,
    pub(crate) shape: Option<ShapeProps>,
    pub(crate) graphic: Option<GraphicProps>,
}

impl Project {
    /// A text clip at `at` on `track`: the default title, centered, five
    /// seconds by default, with `text` merged over it as a `set_text`
    /// patch (spec §6, §4.3).
    ///
    /// Refuses on an overlap-rule violation, in the rule's own sentence;
    /// `Err` for an unknown track, a non-positive duration, or a bad patch.
    pub fn add_text_clip(
        &self,
        track: u32,
        at: Ticks,
        duration: Option<Ticks>,
        text: Option<&Value>,
    ) -> Result<Outcome, String> {
        let title = TextProps {
            content: TITLE_CONTENT.to_string(),
            font: TITLE_FONT.to_string(),
            size: 72.0,
            color: [1.0, 1.0, 1.0, 1.0],
            ..TextProps::default()
        };
        let props = match text {
            None => title,
            Some(patch) => {
                let mut props = merge_group(&title, patch, Group::Text)?;
                check_text(&props)?;
                // The same door `set_text` is, ticks included
                // (`edit_props.rs`'s `snap_animation`, and the Times rule
                // it keeps).
                self.snap_animation(&mut props);
                props
            }
        };
        self.add_described_clip(
            track,
            at,
            duration,
            Described {
                source: Source::Text,
                // Text has no source size — only the platform can measure a
                // layout — so a new text clip is always at native scale.
                scale: 1.0,
                text: Some(props),
                shape: None,
                graphic: None,
            },
        )
    }

    /// A shape clip at `at` on `track`: the default stroked box, five
    /// seconds by default, with `shape` merged over it as a `set_shape`
    /// patch (spec §6). An arrow is created with its head on.
    pub fn add_shape_clip(
        &self,
        track: u32,
        at: Ticks,
        duration: Option<Ticks>,
        shape: Option<&Value>,
    ) -> Result<Outcome, String> {
        let props = match shape {
            None => ShapeProps::default(),
            Some(patch) => {
                // An arrow with `arrow_end: false` draws as a plain diagonal
                // line, which is not what asking for an arrow means and not
                // what spec §5.2's own arrow example shows. The head is
                // switched on HERE, in the creation preset, rather than in
                // `ShapeProps::default()`: that default is also the base a
                // stored shape is deserialized against and the value a
                // later `set_shape { "kind": "arrow" }` merges into, and a
                // patch that re-paints a field the caller did not name
                // would break the merge contract. Merging the patch over
                // this preset (not under it) keeps an explicit
                // `"arrow_end": false` winning.
                let kind = patch
                    .get("kind")
                    .and_then(|value| serde_json::from_value(value.clone()).ok());
                let base = ShapeProps {
                    arrow_end: matches!(kind, Some(ShapeKind::Arrow)),
                    ..ShapeProps::default()
                };
                let props = merge_group(&base, patch, Group::Shape)?;
                check_shape(&props)?;
                props
            }
        };
        // A shape's box IS its source size, so an oversized one fits like
        // oversized footage does.
        let scale = self.fit_scale(props.width, props.height);
        self.add_described_clip(
            track,
            at,
            duration,
            Described {
                source: Source::Shape,
                scale,
                text: None,
                shape: Some(props),
                graphic: None,
            },
        )
    }

    /// The shared tail of `add_text_clip`, `add_shape_clip` and
    /// `edit_graphic.rs`'s `add_graphic_clip`: a clip with no source bound,
    /// placed under the same rules as any other.
    pub(crate) fn add_described_clip(
        &self,
        track: u32,
        at: Ticks,
        duration: Option<Ticks>,
        described: Described,
    ) -> Result<Outcome, String> {
        self.require_track(track)?;
        let at = self.snapped(at).max(0);
        let duration = match duration {
            None => DEFAULT_CLIP_DURATION,
            Some(given) => {
                let snapped = self.snapped(given);
                if snapped < self.frame() {
                    return Err(format!(
                        "clip duration must be at least one frame ({} ticks), not {given}",
                        self.frame()
                    ));
                }
                snapped
            }
        };

        let mut next = self.clone();
        let clip = Clip {
            video: Some(VideoProps {
                scale: described.scale,
                ..VideoProps::default()
            }),
            text: described.text,
            shape: described.shape,
            graphic: described.graphic,
            ..Clip::placed(next.allocate_id(), track, at, duration, described.source)
        };
        self.commit_additions(next, vec![clip])
    }
}
