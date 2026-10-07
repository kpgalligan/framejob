//! The two graphic ops (road map 10's G2a): `add_graphic_clip`, which
//! places a clip drawn by a module in the package, and `set_graphic`, which
//! patches what it is drawn from.
//!
//! What a graphic IS — its fields, the name rule, the side bound, the
//! schema and props checks and the colour normalisation — is
//! `model_graphic.rs`'s, and this module only composes them into ops. The
//! placement tail is `edit_clip.rs`'s `add_described_clip`, the one every
//! sourceless clip is placed through, so a graphic clip obeys the overlap
//! rule and the default five seconds exactly as a text or shape clip does.
//!
//! **Every argument is checked before the placement tail runs**, name
//! first, so an op the table's bound probe sends reaches the side check on
//! any project, whatever its tracks.
//!
//! The core never reads a module (it has no filesystem), so the `schema`
//! a `props` patch is checked against arrives WITH the op (G-4). Without
//! one — a replayed op, a caller that has none — only the shape is
//! checked.
//!
//! `set_graphic` merges `props` key by key into the stored map: `insert`
//! keeps an existing key's slot and appends a new one, and `null` removes
//! with `shift_remove`, which keeps the other keys' order (`Map::remove`
//! would swap the last key into the hole). `Project ==` cannot see an
//! order change, so the Identity arm is unaffected either way, and only
//! the written text shows it. With a `schema`, a `null` for a prop an
//! action on the clip names stores the schema's default instead (spec §11
//! G-34 (d)): the action's ramp keeps a start.

use serde_json::{Map, Value};

use crate::actions_graphic::names_prop;
use crate::edit_action_graphic::schema_default;
use crate::edit_clip::Described;
use crate::export::describe;
use crate::model::{GraphicProps, Project, Source};
use crate::model_graphic::{
    check_count, check_name, check_props, check_schema, check_side, GRAPHIC_MAX_SIDE,
};
use crate::outcome::Outcome;
use crate::patch::unknown_key;
use crate::time::Ticks;

/// One read `set_graphic` patch: each field `None` when its key was absent.
struct GraphicPatch {
    name: Option<String>,
    width: Option<u32>,
    height: Option<u32>,
    /// The outer `Option` is "was the key given"; the inner is what to
    /// store, `None` for a `null`, which gives the length back to the
    /// clip's duration.
    length: Option<Option<Ticks>>,
    /// Checked and normalised, `null`s kept as removals.
    props: Option<Map<String, Value>>,
}

impl Project {
    /// A graphic clip at `at` on `track`, drawn by `graphics/<name>.js` at
    /// `width` × `height` (the canvas's when absent), five seconds long
    /// unless `duration` says otherwise, with `props` checked against
    /// `schema` when one is given (G-4). Fit scale, as a shape's box is.
    ///
    /// Refuses on an overlap-rule violation, in the rule's own sentence;
    /// `Err` for a bad name, a side outside 1–8192 (or a canvas side over
    /// it with no size given), a malformed schema, a bad prop, more than
    /// 64 props, an unknown track or a duration under a frame.
    #[allow(clippy::too_many_arguments)]
    pub fn add_graphic_clip(
        &self,
        track: u32,
        at: Ticks,
        duration: Option<Ticks>,
        name: &str,
        width: Option<u32>,
        height: Option<u32>,
        props: Option<&Value>,
        schema: Option<&Value>,
    ) -> Result<Outcome, String> {
        check_name(name)?;
        let width = self.graphic_side("width", width)?;
        let height = self.graphic_side("height", height)?;
        if let Some(schema) = schema {
            check_schema(schema)?;
        }
        let props = match props {
            None => Map::new(),
            Some(value) => {
                let patch = value.as_object().ok_or_else(|| {
                    format!("props must be a json object, not {}", describe(value))
                })?;
                let mut stored = check_props(patch, schema)?;
                stored.retain(|_, value| !value.is_null());
                check_count(&stored)?;
                stored
            }
        };
        // A graphic's size IS its source size, so an oversized one fits
        // like oversized footage does — the shape's rule.
        let scale = self.fit_scale(f64::from(width), f64::from(height));
        self.add_described_clip(
            track,
            at,
            duration,
            Described {
                source: Source::Graphic,
                scale,
                text: None,
                shape: None,
                graphic: Some(GraphicProps {
                    name: name.to_string(),
                    width,
                    height,
                    r#in: 0,
                    length: None,
                    props,
                }),
            },
        )
    }

    /// Patches each named graphic clip's `name`, `width`, `height`,
    /// `length` and `props` (road map 10 §5h). `props` merges key by key and
    /// a `null` removes its key — except, with a `schema`, a prop an action
    /// on the clip names, which takes the schema's default (G-34 (d)); `in`
    /// is not patchable, because the trims and `split` own it (G-9).
    ///
    /// `Err` for a malformed schema, a patch that is not an object, an
    /// unknown clip, a clip that is not a graphic, an unknown key and any
    /// value its check refuses; an identity when nothing changes — a colour
    /// re-sent in another spelling included. No rule refuses a patch, as
    /// none refuses `set_shape`'s.
    pub fn set_graphic(
        &self,
        clips: &[u32],
        patch: &Value,
        schema: Option<&Value>,
    ) -> Result<Outcome, String> {
        if let Some(schema) = schema {
            check_schema(schema)?;
        }
        let Some(fields) = patch.as_object() else {
            return Err(format!(
                "graphic patch must be a json object, not {}",
                describe(patch)
            ));
        };
        let ids: Vec<u32> = self.selected_clips(clips)?.iter().map(|c| c.id).collect();
        if ids.is_empty() {
            return Ok(Outcome::Identity);
        }
        for id in &ids {
            let clip = self.require_clip(*id)?;
            if !(matches!(clip.source, Source::Graphic) && clip.graphic.is_some()) {
                return Err(format!("clip {id} is not a graphic clip"));
            }
        }
        let read = self.read_graphic_patch(fields, schema)?;

        let mut next = self.clone();
        for id in ids {
            let Some(original) = self.clip(id) else {
                continue;
            };
            let Some(graphic) = next.clip_mut(id).and_then(|clip| clip.graphic.as_mut()) else {
                continue;
            };
            if let Some(name) = &read.name {
                graphic.name = name.clone();
            }
            if let Some(width) = read.width {
                graphic.width = width;
            }
            if let Some(height) = read.height {
                graphic.height = height;
            }
            if let Some(length) = read.length {
                graphic.length = length;
            }
            if let Some(props) = &read.props {
                for (key, value) in props {
                    let kept = schema
                        .and_then(|schema| schema_default(schema, key))
                        .filter(|_| value.is_null() && names_prop(original, key));
                    if let Some(default) = kept {
                        graphic.props.insert(key.clone(), default);
                    } else if value.is_null() {
                        graphic.props.shift_remove(key);
                    } else {
                        graphic.props.insert(key.clone(), value.clone());
                    }
                }
                check_count(&graphic.props)?;
            }
        }
        self.finish(next)
    }

    /// A side the caller gave, checked; or the canvas's same side, which a
    /// graphic cannot draw at when it is over the bound. Only the defaulted
    /// side is tested, so a caller who gave the other one is not refused
    /// for it.
    fn graphic_side(&self, key: &str, given: Option<u32>) -> Result<u32, String> {
        match given {
            Some(side) => {
                check_side(key, u64::from(side))?;
                Ok(side)
            }
            None => {
                let (width, height) = (self.canvas.width, self.canvas.height);
                let side = if key == "width" { width } else { height };
                if side > GRAPHIC_MAX_SIDE {
                    return Err(format!(
                        "the canvas is {width}×{height} and a graphic's side is at most \
                         {GRAPHIC_MAX_SIDE}; pass width and height"
                    ));
                }
                Ok(side)
            }
        }
    }

    /// Reads a `set_graphic` patch key by key, every value checked before
    /// any is applied, ticks snapped after their check.
    fn read_graphic_patch(
        &self,
        fields: &Map<String, Value>,
        schema: Option<&Value>,
    ) -> Result<GraphicPatch, String> {
        let mut read = GraphicPatch {
            name: None,
            width: None,
            height: None,
            length: None,
            props: None,
        };
        for (key, value) in fields {
            match key.as_str() {
                "name" => {
                    let name = value
                        .as_str()
                        .ok_or_else(|| format!("name must be a string, not {}", describe(value)))?;
                    check_name(name)?;
                    read.name = Some(name.to_string());
                }
                "width" | "height" => {
                    let side = value.as_u64().ok_or_else(|| {
                        format!("{key} must be a whole number, not {}", describe(value))
                    })?;
                    check_side(key, side)?;
                    // Inside 1–8192, so the narrowing cannot fail.
                    let side = u32::try_from(side).unwrap_or(GRAPHIC_MAX_SIDE);
                    if key == "width" {
                        read.width = Some(side);
                    } else {
                        read.height = Some(side);
                    }
                }
                "length" => read.length = Some(self.graphic_length(value)?),
                "props" => {
                    let patch = value.as_object().ok_or_else(|| {
                        format!("props must be a json object, not {}", describe(value))
                    })?;
                    read.props = Some(check_props(patch, schema)?);
                }
                "in" => {
                    return Err(
                        "\"in\" cannot be patched: trim_start and split own a graphic's in point"
                            .to_string(),
                    )
                }
                other => return Err(unknown_key(other, "a graphic patch")),
            }
        }
        Ok(read)
    }

    /// `null` gives the length back to the clip's duration; a number is
    /// snapped to the nearest frame, and under one frame is an `Err` naming
    /// what was sent.
    fn graphic_length(&self, value: &Value) -> Result<Option<Ticks>, String> {
        if value.is_null() {
            return Ok(None);
        }
        let given = value.as_i64().ok_or_else(|| {
            format!(
                "length must be a whole number of ticks or null, not {}",
                describe(value)
            )
        })?;
        let snapped = self.snapped(given);
        if snapped < self.frame() {
            return Err(format!(
                "length must be at least one frame ({} ticks), not {given}",
                self.frame()
            ));
        }
        Ok(Some(snapped))
    }
}
