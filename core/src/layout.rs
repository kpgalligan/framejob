//! Camera layouts' geometry (road map "creator-jobs" CO6, spec §11 CO-60,
//! CO-65): where a layout puts the camera and the screen, as the six
//! placement keys `switch_layout` writes on each — `x`, `y`, `scale`,
//! `crop`, `corner_radius`, `opacity` — and nothing else. Pure: every
//! number is read from the container's canvas and the source sizes.
//!
//! W × H is the container's canvas (a nest's own inside a scope) and
//! `m = MARGIN·min(W, H)`. Every scale is clamped to
//! `SCALE_MIN…SCALE_MAX`; `x` and `y` are rounded half away from zero to
//! whole canvas pixels, as CAM-10 (3) rounds them; scale, crop and radius
//! are not. A radius is written in SOURCE pixels, its canvas length ÷ the
//! scale. A crop's centre is placed by `edit_zoom.rs`'s (★): the cropped
//! centre is the anchor plus `s·((l − r)/2, (t − b)/2)`.
//!
//! - **Full placement** is `add_clip`'s: 0, 0, `fit_scale`, no crop,
//!   radius 0, opacity 1 — the screen's in `corner`, `camera_full` and
//!   `screen_only`.
//! - **corner**: the box is `CORNER_WIDTH·W × CORNER_HEIGHT·H`, the
//!   picture's outer corner `CORNER_INSET` of each axis in from the chosen
//!   canvas corner. `square` and `rounded` fit the whole camera in it
//!   (CAM-10 (3)'s `cornerPatch` exactly); `rounded`'s radius is
//!   `ROUNDED_RADIUS` of the box's shorter side. `circle` crops the largest
//!   square of the source, centred on `focus`, to the box's shorter side,
//!   with a radius of half the square's side.
//! - **side_by_side**: the screen fitted in the left `SCREEN_SHARE` of the
//!   inner width `W − 3m` and `H − 2m` tall, centred there; the camera
//!   cropped to fill the right third; `PANEL_RADIUS` of the canvas's
//!   shorter side on each.
//! - **stacked**: the screen at `min((W − 2m)/sw, (H − 3m)·SCREEN_SHARE/sh)`,
//!   centred across, its top at m; the camera cropped to fill the
//!   `(W − 2m)`-wide rest below it, m between; the same radii.
//! - **camera_full**: the camera at `fill_scale`, uncropped, square.
//! - **screen_only**: the camera keeps where it is, at opacity 0.
//!
//! `focus` (CO-65) is a point in the camera's source pixels from the
//! UNCROPPED source's centre, y down; a crop is centred on it and clamped
//! inside the source.

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::model::{Crop, Project, VideoProps};
use crate::props_check::{SCALE_MAX, SCALE_MIN};
use crate::time::{Ticks, TIMESCALE};

/// The corner box's width, as a fraction of the canvas's (CAM-10 (3)).
pub(crate) const CORNER_WIDTH: f64 = 0.25;
/// The corner box's height, as a fraction of the canvas's.
pub(crate) const CORNER_HEIGHT: f64 = 1.0 / 3.0;
/// The corner picture's inset from the canvas's edges, per axis: the 90 %
/// ring of View ▸ Safe Areas.
pub(crate) const CORNER_INSET: f64 = 0.05;
/// `rounded`'s radius, as a fraction of the corner box's shorter side.
pub(crate) const ROUNDED_RADIUS: f64 = 0.08;
/// The margin round and between the panels, of the canvas's shorter side.
pub(crate) const MARGIN: f64 = 0.04;
/// Each panel's radius in `side_by_side` and `stacked`, of the canvas's
/// shorter side.
pub(crate) const PANEL_RADIUS: f64 = 0.02;
/// The screen's share of the inner width (`side_by_side`) or height
/// (`stacked`).
pub(crate) const SCREEN_SHARE: f64 = 2.0 / 3.0;
/// A switch's length when `duration` is absent (owner, 2026-11-01).
pub(crate) const DEFAULT_SWITCH: Ticks = TIMESCALE / 2;

/// The five layouts (CO-60).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CameraLayout {
    Corner,
    SideBySide,
    Stacked,
    CameraFull,
    ScreenOnly,
}

impl CameraLayout {
    /// Whether the screen takes its full placement in this layout.
    pub(crate) fn screen_full(self) -> bool {
        matches!(
            self,
            CameraLayout::Corner | CameraLayout::CameraFull | CameraLayout::ScreenOnly
        )
    }
}

/// The corner picture's shape.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LayoutShape {
    #[default]
    Square,
    Rounded,
    Circle,
}

/// The canvas corner the corner picture sits in.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LayoutCorner {
    #[default]
    BottomRight,
    BottomLeft,
    TopRight,
    TopLeft,
}

impl LayoutCorner {
    /// The signs of the corner's offset from the canvas centre, y down.
    fn signs(self) -> (f64, f64) {
        match self {
            LayoutCorner::BottomRight => (1.0, 1.0),
            LayoutCorner::BottomLeft => (-1.0, 1.0),
            LayoutCorner::TopRight => (1.0, -1.0),
            LayoutCorner::TopLeft => (-1.0, -1.0),
        }
    }
}

/// What a switch asks for: the layout, its corner shape and corner, and
/// the camera's focus (CO-65).
#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) struct LayoutChoice {
    pub layout: CameraLayout,
    pub shape: LayoutShape,
    pub corner: LayoutCorner,
    pub focus: (f64, f64),
}

/// The six placement keys a layout writes on a role.
#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) struct Placement {
    pub x: f64,
    pub y: f64,
    pub scale: f64,
    pub crop: Crop,
    pub corner_radius: f64,
    pub opacity: f64,
}

impl Placement {
    /// Exactly the six keys, `crop` as `{l, t, r, b}`: a `set_video` patch,
    /// and an action end's `video`.
    pub(crate) fn to_json(self) -> Value {
        json!({
            "x": self.x,
            "y": self.y,
            "scale": self.scale,
            "crop": {"l": self.crop.l, "t": self.crop.t, "r": self.crop.r, "b": self.crop.b},
            "corner_radius": self.corner_radius,
            "opacity": self.opacity,
        })
    }

    /// The six keys of a video group.
    pub(crate) fn of(video: &VideoProps) -> Placement {
        Placement {
            x: video.x,
            y: video.y,
            scale: video.scale,
            crop: video.crop,
            corner_radius: video.corner_radius,
            opacity: video.opacity,
        }
    }

    /// The six keys an action's end names in `video`, or `None` when one is
    /// missing or not a number.
    pub(crate) fn from_end(end: &Value) -> Option<Placement> {
        let video = end.get("video")?;
        let number = |key: &str| video.get(key).and_then(Value::as_f64);
        let crop: Crop = serde_json::from_value(video.get("crop")?.clone()).ok()?;
        Some(Placement {
            x: number("x")?,
            y: number("y")?,
            scale: number("scale")?,
            crop,
            corner_radius: number("corner_radius")?,
            opacity: number("opacity")?,
        })
    }
}

/// Whether `placed` is `full`: every one of the nine numbers within 1e-9
/// (CO-62).
pub(crate) fn holds_full(placed: &Placement, full: &Placement) -> bool {
    let near = |a: f64, b: f64| (a - b).abs() <= 1e-9;
    near(placed.x, full.x)
        && near(placed.y, full.y)
        && near(placed.scale, full.scale)
        && near(placed.crop.l, full.crop.l)
        && near(placed.crop.t, full.crop.t)
        && near(placed.crop.r, full.crop.r)
        && near(placed.crop.b, full.crop.b)
        && near(placed.corner_radius, full.corner_radius)
        && near(placed.opacity, full.opacity)
}

/// A scale in the layer's legal range.
fn clamp_scale(scale: f64) -> f64 {
    if scale.is_finite() {
        scale.clamp(SCALE_MIN, SCALE_MAX)
    } else {
        1.0
    }
}

/// The container's canvas, and its margin.
fn canvas(p: &Project) -> (f64, f64, f64) {
    let (w, h) = (f64::from(p.canvas.width), f64::from(p.canvas.height));
    (w, h, MARGIN * w.min(h))
}

/// A `cw × ch` crop of an `a × b` source centred on `focus` (from the
/// uncropped centre, y down), clamped inside the source.
fn centred_crop(source: (f64, f64), size: (f64, f64), focus: (f64, f64)) -> Crop {
    let (a, b) = source;
    let axis = |whole: f64, part: f64, at: f64| {
        let part = if part >= whole - 1e-9 { whole } else { part };
        let room = (whole - part) / 2.0;
        // `switch_layout` refuses a non-finite focus before it gets here.
        let centre = at.clamp(-room, room);
        (room + centre, room - centre)
    };
    let (l, r) = axis(a, size.0, focus.0);
    let (t, b) = axis(b, size.1, focus.1);
    Crop { l, t, r, b }
}

/// The `x`, `y` that put a cropped picture's centre at `centre` (an offset
/// from the canvas centre) at scale `s` — (★) turned round, rounded.
fn place(centre: (f64, f64), scale: f64, crop: &Crop) -> (f64, f64) {
    let x = centre.0 - scale * (crop.l - crop.r) / 2.0;
    let y = centre.1 - scale * (crop.t - crop.b) / 2.0;
    (x.round(), y.round())
}

/// The camera cropped to fill a `bw × bh` box centred at `centre`.
fn filled(
    source: (f64, f64),
    boxed: (f64, f64),
    centre: (f64, f64),
    focus: (f64, f64),
    radius: f64,
) -> Placement {
    let (a, b) = source;
    let scale = clamp_scale((boxed.0 / a).max(boxed.1 / b));
    let crop = centred_crop(source, (boxed.0 / scale, boxed.1 / scale), focus);
    let (x, y) = place(centre, scale, &crop);
    Placement {
        x,
        y,
        scale,
        crop,
        corner_radius: radius / scale,
        opacity: 1.0,
    }
}

/// `add_clip`'s placement of a source of this size (CO-60).
pub(crate) fn full_placement(p: &Project, source: (f64, f64)) -> Placement {
    Placement {
        x: 0.0,
        y: 0.0,
        scale: p.fit_scale(source.0, source.1),
        crop: Crop::default(),
        corner_radius: 0.0,
        opacity: 1.0,
    }
}

/// The screen's scale in `stacked`.
fn stacked_screen_scale(p: &Project, source: (f64, f64)) -> f64 {
    let (w, h, m) = canvas(p);
    clamp_scale(((w - 2.0 * m) / source.0).min((h - 3.0 * m) * SCREEN_SHARE / source.1))
}

/// Where the screen goes in `layout` (CO-60).
pub(crate) fn screen_placement(p: &Project, layout: CameraLayout, source: (f64, f64)) -> Placement {
    let (w, h, m) = canvas(p);
    let radius = PANEL_RADIUS * w.min(h);
    match layout {
        CameraLayout::SideBySide => {
            let bw = (w - 3.0 * m) * SCREEN_SHARE;
            let bh = h - 2.0 * m;
            let scale = clamp_scale((bw / source.0).min(bh / source.1));
            let x = (m + bw / 2.0 - w / 2.0).round();
            Placement {
                x,
                y: 0.0,
                scale,
                crop: Crop::default(),
                corner_radius: radius / scale,
                opacity: 1.0,
            }
        }
        CameraLayout::Stacked => {
            let scale = stacked_screen_scale(p, source);
            let y = (m + source.1 * scale / 2.0 - h / 2.0).round();
            Placement {
                x: 0.0,
                y,
                scale,
                crop: Crop::default(),
                corner_radius: radius / scale,
                opacity: 1.0,
            }
        }
        CameraLayout::Corner | CameraLayout::CameraFull | CameraLayout::ScreenOnly => {
            full_placement(p, source)
        }
    }
}

/// Where the camera goes (CO-60): `screen` is the screen's source size
/// (`stacked` stands the camera under it), `kept` the camera's own six keys
/// now (`screen_only` keeps them at opacity 0).
pub(crate) fn camera_placement(
    p: &Project,
    choice: &LayoutChoice,
    source: (f64, f64),
    screen: Option<(f64, f64)>,
    kept: &Placement,
) -> Placement {
    let (w, h, m) = canvas(p);
    let panel = PANEL_RADIUS * w.min(h);
    let (a, b) = source;
    match choice.layout {
        CameraLayout::Corner => corner(p, choice, source),
        CameraLayout::SideBySide => {
            let inner = w - 3.0 * m;
            let boxed = (inner * (1.0 - SCREEN_SHARE), h - 2.0 * m);
            let left = m + inner * SCREEN_SHARE + m;
            let centre = (left + boxed.0 / 2.0 - w / 2.0, 0.0);
            filled(source, boxed, centre, choice.focus, panel)
        }
        CameraLayout::Stacked => {
            let above = screen.map_or(0.0, |s| s.1 * stacked_screen_scale(p, s));
            let boxed = (w - 2.0 * m, h - 3.0 * m - above);
            let centre = (0.0, 2.0 * m + above + boxed.1 / 2.0 - h / 2.0);
            filled(source, boxed, centre, choice.focus, panel)
        }
        CameraLayout::CameraFull => Placement {
            x: 0.0,
            y: 0.0,
            scale: p.fill_scale(a, b),
            crop: Crop::default(),
            corner_radius: 0.0,
            opacity: 1.0,
        },
        CameraLayout::ScreenOnly => Placement {
            opacity: 0.0,
            ..*kept
        },
    }
}

/// `corner`'s three shapes.
fn corner(p: &Project, choice: &LayoutChoice, source: (f64, f64)) -> Placement {
    let (w, h, _) = canvas(p);
    let (a, b) = source;
    let (bw, bh) = (CORNER_WIDTH * w, CORNER_HEIGHT * h);
    let (sx, sy) = choice.corner.signs();
    let (ix, iy) = (CORNER_INSET * w, CORNER_INSET * h);
    match choice.shape {
        LayoutShape::Square | LayoutShape::Rounded => {
            let scale = clamp_scale((bw / a).min(bh / b));
            let x = (sx * (w / 2.0 - ix - a * scale / 2.0)).round();
            let y = (sy * (h / 2.0 - iy - b * scale / 2.0)).round();
            let corner_radius = match choice.shape {
                LayoutShape::Rounded => ROUNDED_RADIUS * bw.min(bh) / scale,
                _ => 0.0,
            };
            Placement {
                x,
                y,
                scale,
                crop: Crop::default(),
                corner_radius,
                opacity: 1.0,
            }
        }
        LayoutShape::Circle => {
            let side = a.min(b);
            let crop = centred_crop(source, (side, side), choice.focus);
            let scale = clamp_scale(bw.min(bh) / side);
            let shown = side * scale / 2.0;
            let centre = (sx * (w / 2.0 - ix - shown), sy * (h / 2.0 - iy - shown));
            let (x, y) = place(centre, scale, &crop);
            Placement {
                x,
                y,
                scale,
                crop,
                corner_radius: side / 2.0,
                opacity: 1.0,
            }
        }
    }
}
