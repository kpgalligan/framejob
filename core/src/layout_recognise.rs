//! A camera layout recognised from the placements it wrote (road map
//! "creator-jobs" VR5b, spec §11 VR-53 (b)): the layout, shape and corner
//! whose solve on the AUTHORED canvas gives a switch's camera end and its
//! screen end. Pure; beside `layout.rs`, which is at its 400-line cap, and
//! read only by `reframe_layout.rs`.
//!
//! The candidates are tried in a fixed order — `corner` with each shape
//! (square, rounded, circle) at each corner (bottom right, bottom left, top
//! right, top left), `side_by_side`, `stacked` (both skipped when the switch
//! has no screen), `camera_full`, `screen_only` — and the first whose camera
//! AND screen placements are [`alike`] the ends wins. A candidate is solved
//! with the camera end's own crop centre as its `focus` ([`focus_of`]), so a
//! crop centred on a person (CO-70) is recognised whatever the focus was;
//! the tolerance is `RECOGNISE_PX` in every pixel-valued key (a switch's
//! `x` and `y` are whole pixels, its crop and radius are not) and
//! `RECOGNISE_RATIO` in scale and opacity, so an end moved by hand by more
//! than a pixel is not a layout Frame Job made.

use crate::edit_layout_reach::RoleKind;
use crate::layout::{
    camera_placement, screen_placement, CameraLayout, LayoutChoice, LayoutCorner, LayoutShape,
    Placement,
};
use crate::model::{Project, Source};

/// The tolerance on x, y, the four crop edges and the radius, in pixels.
pub(crate) const RECOGNISE_PX: f64 = 1.0;
/// The tolerance on scale and opacity.
pub(crate) const RECOGNISE_RATIO: f64 = 0.001;

/// Whether `got` is `solved` within the recognition tolerances.
pub(crate) fn alike(got: &Placement, solved: &Placement) -> bool {
    let px = |a: f64, b: f64| (a - b).abs() <= RECOGNISE_PX;
    let ratio = |a: f64, b: f64| (a - b).abs() <= RECOGNISE_RATIO;
    px(got.x, solved.x)
        && px(got.y, solved.y)
        && px(got.crop.l, solved.crop.l)
        && px(got.crop.t, solved.crop.t)
        && px(got.crop.r, solved.crop.r)
        && px(got.crop.b, solved.crop.b)
        && px(got.corner_radius, solved.corner_radius)
        && ratio(got.scale, solved.scale)
        && ratio(got.opacity, solved.opacity)
}

/// The centre of the camera's crop, from the uncropped source's centre, y
/// down: `layout.rs`'s `focus` as the crop shows it (clamped inside the
/// source, so not always the focus the switch was given).
pub(crate) fn focus_of(camera: &Placement) -> (f64, f64) {
    let crop = camera.crop;
    ((crop.l - crop.r) / 2.0, (crop.t - crop.b) / 2.0)
}

/// Whether two sources show the same thing: the same kind, and the same
/// media (a media, still or image source) or the same nest. `in`, `at` and
/// `reversed` are not compared, so a split half is the same source.
pub(crate) fn same_source(a: &Source, b: &Source) -> bool {
    match (a, b) {
        (Source::Media { media: x, .. }, Source::Media { media: y, .. })
        | (Source::Still { media: x, .. }, Source::Still { media: y, .. })
        | (Source::Image { media: x }, Source::Image { media: y }) => x == y,
        (Source::Nest { project: x }, Source::Nest { project: y }) => x == y,
        _ => false,
    }
}

/// The candidates in their order (the module doc).
fn candidates(focus: (f64, f64), with_screen: bool) -> Vec<LayoutChoice> {
    let choice = |layout, shape, corner| LayoutChoice {
        layout,
        shape,
        corner,
        focus,
    };
    let mut all = Vec::new();
    for shape in [
        LayoutShape::Square,
        LayoutShape::Rounded,
        LayoutShape::Circle,
    ] {
        for corner in [
            LayoutCorner::BottomRight,
            LayoutCorner::BottomLeft,
            LayoutCorner::TopRight,
            LayoutCorner::TopLeft,
        ] {
            all.push(choice(CameraLayout::Corner, shape, corner));
        }
    }
    let rest = [
        CameraLayout::SideBySide,
        CameraLayout::Stacked,
        CameraLayout::CameraFull,
        CameraLayout::ScreenOnly,
    ];
    for layout in rest {
        if with_screen || !matches!(layout, CameraLayout::SideBySide | CameraLayout::Stacked) {
            all.push(choice(
                layout,
                LayoutShape::default(),
                LayoutCorner::default(),
            ));
        }
    }
    all
}

/// The layout a switch made on `authored`'s canvas (only its `canvas` is
/// read): `camera` the camera's end and its source size, `screen` the
/// screen's end and source size when the switch has one. `Err(Camera)` when
/// no candidate gives the camera end; `Err(Screen)` when some do but none
/// also gives the screen end.
pub(crate) fn recognise(
    authored: &Project,
    camera: &Placement,
    camera_source: (f64, f64),
    screen: Option<(&Placement, (f64, f64))>,
) -> Result<LayoutChoice, RoleKind> {
    let screen_size = screen.map(|(_, size)| size);
    let mut camera_matched = false;
    for choice in candidates(focus_of(camera), screen.is_some()) {
        let solved = camera_placement(authored, &choice, camera_source, screen_size, camera);
        if !alike(camera, &solved) {
            continue;
        }
        camera_matched = true;
        let screen_fits = screen
            .is_none_or(|(end, size)| alike(end, &screen_placement(authored, choice.layout, size)));
        if screen_fits {
            return Ok(choice);
        }
    }
    Err(if camera_matched {
        RoleKind::Screen
    } else {
        RoleKind::Camera
    })
}
