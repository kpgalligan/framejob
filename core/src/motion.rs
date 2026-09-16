//! `video.motion` turned into PLACEMENT — road map 5 §5b–§5c's arithmetic,
//! and the only place in the crate that reads a preset.
//!
//! A preset says what a clip DOES; this says where it therefore IS at one
//! instant. [`apply`] takes the EVALUATED video props of a clip (actions
//! already applied), the clip time, the clip's own duration, the source's
//! pixel size and the container's canvas, and answers the same props with
//! five fields moved: `scale`, `rotation`, `opacity`, `x` and `y`. Every
//! other field passes through untouched, which is what lets `recipe.rs`
//! read a layer's per-pixel properties off the moved props without knowing
//! anything about motion.
//!
//! **It is called where placement is PRODUCED and nowhere else** (spec §11,
//! R5-4): the two call sites are `recipe.rs`'s `layer` and `frame_of`.
//! `evaluate_clip`, `clip_state`, `get_project`, `split_clip`'s state,
//! `add_zoom_action`, `freeze_frame` and the audio plan all read the clip
//! UN-MOVED, so an edit works on the numbers a person typed and only the
//! picture moves. A build that moved `evaluate_clip` instead would pass a
//! careless render check and break every edit.
//!
//! # The three slots
//!
//! An ARRIVAL runs for the first `in` of the clip on `a = ease_out(t/in′)`,
//! a DEPARTURE for the last `out` on `d = ease_in(v)` measured back from
//! the EXCLUSIVE end so the last drawn frame still shows a sliver
//! (`recipe_text.rs:150`'s convention), and a DURING runs for the whole
//! clip. Each yields a scale factor `F`, a rotation `φ` in degrees, an
//! opacity factor `O` and an offset `Δ` in canvas pixels; the totals are
//! `F = F_in·F_out·F_during`, `φ = Σφ`, `O = O_in·O_out` and `Δ = ΣΔ`.
//!
//! **The tent.** When `in + out > D` the two are scaled to meet —
//! `in′ = in·D/(in + out)`, `out′ = D − in′` — so the arrival ends on the
//! frame the departure begins and nothing refuses. "Too long for THIS clip"
//! is a fact about a clip, not about the vocabulary, and a later trim would
//! invalidate any refusal anyway.
//!
//! **Rotation is REDUCED.** `φ` is taken `rem_euclid(360)` before it is
//! added, so a whole turn is EXACTLY no turn. Without it a rotation of 360
//! would reach Swift as `Float(360·π/180)`, whose `sin` is ~1.7e-7 rather
//! than 0 (`Compositor.swift`), and `partnerBox`'s `rotation == 0` guard
//! would read the layer as rotated.
//!
//! **The pivot is the VISIBLE centre.** The core's placement rule (★,
//! `edit_zoom.rs`) pivots on the UNCROPPED anchor, so a zoom or a spin
//! about it would make a cropped layer drift across its own preset. The
//! moved position compensates:
//! `(x, y)′ = (x, y) + s·R(θ)·c − s″·R(θ″)·c + Δ`, with `c` the cropped
//! rect's centre in source pixels, `s″` the CLAMPED drawn scale and `θ″`
//! the drawn rotation. At `F = 1`, `φ = 0` the two terms are the same
//! expression and cancel to the bit, which is what makes an inactive
//! preset free.
//!
//! **Slides are measured against the DRAWN box.** `S_right` is the offset
//! that puts the layer's right edge exactly on the container's right edge,
//! measured at `s″` and `θ″` — the size actually drawn — from the BASE
//! visible centre `p = (x, y) + s·R(θ)·c`, which is where the pivot
//! compensation holds the layer whatever the other slots do. For TEXT the
//! core has no measured size (spec §11), so `hx = W/2`, `hy = H/2` and
//! `c = 0`: the anchor starts half a canvas beyond the edge, which clears
//! any text narrower than the canvas. Recorded as a limit.
//!
//! # It never trusts the file
//!
//! `validate` range-checks no property and `evaluate_clip`'s restore copies
//! the BASE motion past `clamp_video`, so a hand-written `period: 0`, a
//! negative duration or an `amount` of 5 arrives here. A slot whose
//! duration is ≤ 0 after the tent is inactive; a `during` whose `period` is
//! ≤ 0 is inactive; `amount` is clamped to 0…1; and every output is checked
//! finite, a non-finite one leaving that field as evaluated. No NaN reaches
//! the recipe.
//!
//! **And when nothing is active it SHORT-CIRCUITS**, returning
//! `video.clone()` rather than computing an identity. `x + b − b` is not
//! `x` in floats, and the frame at `in′` has to be byte-identical to the
//! same clip with no motion at all — which is the claim `core/tests/
//! motion.rs` makes and the one an export comparison rests on.

use crate::model::{DuringMotion, EdgeMotion, Motion, MotionDuring, MotionEdge, VideoProps};
use crate::nest::rotate;
use crate::props_check::{SCALE_MAX, SCALE_MIN};
use crate::time::Ticks;

/// The overshoot curve `pop` is built on: above 1 from `u ≈ 0.37`, peaking
/// at 1.100 around `u ≈ 0.58`, back at exactly 1 when `u` is 1.
fn back_out(u: f64) -> f64 {
    let p = u - 1.0;
    1.0 + 2.70158 * p * p * p + 1.70158 * p * p
}

/// Which container edge a slide measures itself against.
#[derive(Clone, Copy)]
enum Side {
    Left,
    Right,
    Top,
    Bottom,
}

/// One slot's contribution, before the geometry a slide needs is known.
struct Term {
    f: f64,
    phi: f64,
    o: f64,
    /// A slide, as the edge it is measured from and the fraction of the way
    /// out to it — resolved once `F` and `φ` have fixed the drawn box.
    slide: Option<(Side, f64)>,
    /// A displacement in canvas pixels that needs no geometry at all.
    delta: (f64, f64),
}

impl Term {
    /// The identity: nothing scaled, turned, faded or moved.
    const NONE: Term = Term {
        f: 1.0,
        phi: 0.0,
        o: 1.0,
        slide: None,
        delta: (0.0, 0.0),
    };
}

/// The arrival table (road map 5 §5b). `a` is the eased progress and `u`
/// the raw one, which only `pop` reads.
fn arrival(kind: EdgeMotion, a: f64, u: f64) -> Term {
    match kind {
        EdgeMotion::Fade => Term { o: a, ..Term::NONE },
        EdgeMotion::ZoomIn => Term {
            f: 0.6 + 0.4 * a,
            o: a,
            ..Term::NONE
        },
        EdgeMotion::ZoomOut => Term {
            f: 1.4 - 0.4 * a,
            o: a,
            ..Term::NONE
        },
        // A slide names the edge it comes FROM: `slide_left` moves left, so
        // it enters from the right.
        EdgeMotion::SlideLeft => Term {
            slide: Some((Side::Right, 1.0 - a)),
            ..Term::NONE
        },
        EdgeMotion::SlideRight => Term {
            slide: Some((Side::Left, 1.0 - a)),
            ..Term::NONE
        },
        EdgeMotion::SlideUp => Term {
            slide: Some((Side::Bottom, 1.0 - a)),
            ..Term::NONE
        },
        EdgeMotion::SlideDown => Term {
            slide: Some((Side::Top, 1.0 - a)),
            ..Term::NONE
        },
        EdgeMotion::Spin => Term {
            f: 0.3 + 0.7 * a,
            phi: -180.0 * (1.0 - a),
            o: a,
            ..Term::NONE
        },
        // The overshoot is the whole preset, so `pop` is the one arrival
        // measured on the RAW progress; its fade is over in the first
        // quarter, before the scale has passed 1.
        EdgeMotion::Pop => Term {
            f: back_out(u),
            o: (u / 0.25).min(1.0),
            ..Term::NONE
        },
    }
}

/// The departure table (road map 5 §5b). `d` is the eased progress and `v`
/// the raw one; `1 − v` is how much of the exit is LEFT, which is what
/// `pop` runs backwards on.
fn departure(kind: EdgeMotion, d: f64, v: f64) -> Term {
    let left = 1.0 - v;
    match kind {
        EdgeMotion::Fade => Term {
            o: 1.0 - d,
            ..Term::NONE
        },
        EdgeMotion::ZoomIn => Term {
            f: 1.0 + 0.4 * d,
            o: 1.0 - d,
            ..Term::NONE
        },
        EdgeMotion::ZoomOut => Term {
            f: 1.0 - 0.4 * d,
            o: 1.0 - d,
            ..Term::NONE
        },
        // On the way out a slide names the edge it leaves PAST, which is
        // the mirror of the arrival above.
        EdgeMotion::SlideLeft => Term {
            slide: Some((Side::Left, d)),
            ..Term::NONE
        },
        EdgeMotion::SlideRight => Term {
            slide: Some((Side::Right, d)),
            ..Term::NONE
        },
        EdgeMotion::SlideUp => Term {
            slide: Some((Side::Top, d)),
            ..Term::NONE
        },
        EdgeMotion::SlideDown => Term {
            slide: Some((Side::Bottom, d)),
            ..Term::NONE
        },
        EdgeMotion::Spin => Term {
            f: 1.0 - 0.7 * d,
            phi: 180.0 * d,
            o: 1.0 - d,
            ..Term::NONE
        },
        EdgeMotion::Pop => Term {
            f: back_out(left),
            o: (left / 0.25).min(1.0),
            ..Term::NONE
        },
    }
}

/// The continuous table (road map 5 §5b). Every one of the five is the
/// IDENTITY at `t = 0`, so a clip starts exactly where it is placed.
fn during(
    kind: DuringMotion,
    amount: f64,
    t: f64,
    period: f64,
    duration: f64,
    w: f64,
    h: f64,
) -> Term {
    let cycles = t / period;
    match kind {
        DuringMotion::Pulse => Term {
            f: 1.0 + 0.2 * amount * (1.0 - (std::f64::consts::TAU * cycles).cos()) / 2.0,
            ..Term::NONE
        },
        // Two incommensurable sines per axis, so the shake never repeats
        // inside a period and never reads as a loop. `m` is the SHORT edge
        // of the container, so the displacement is the same fraction of the
        // picture whatever its aspect.
        DuringMotion::Shake => {
            let m = w.min(h);
            let wave = |k: f64| (std::f64::consts::TAU * k * cycles).sin();
            Term {
                delta: (
                    0.04 * amount * m * (0.6 * wave(1.0) + 0.4 * wave(2.7)),
                    0.04 * amount * m * (0.6 * wave(1.3) + 0.4 * wave(3.1)),
                ),
                ..Term::NONE
            }
        }
        // `amount` 0.5 is one whole turn per period, which is why the total
        // is reduced `rem_euclid(360)` by the caller rather than here: the
        // reduction has to see the SUM, or an edge spin plus a during spin
        // could land on a multiple of 360 and still read as turned.
        DuringMotion::Spin => Term {
            phi: 720.0 * amount * cycles,
            ..Term::NONE
        },
        DuringMotion::Bounce => Term {
            delta: (
                0.0,
                -0.08 * amount * h * (std::f64::consts::PI * cycles).sin().abs(),
            ),
            ..Term::NONE
        },
        // The one preset that ignores `period` entirely: a drift is a slow
        // push across the WHOLE clip, so its clock is the duration.
        DuringMotion::Drift => Term {
            f: 1.0 + 0.24 * amount * t / duration,
            ..Term::NONE
        },
    }
}

/// The two edge durations after the tent rule, in ticks as floats.
fn tent(motion: &Motion, duration: f64) -> (f64, f64) {
    let raw = |edge: &Option<MotionEdge>| edge.map_or(0.0, |e| e.duration as f64);
    let (mut arrive, mut leave) = (raw(&motion.r#in), raw(&motion.out));
    if arrive + leave > duration && arrive + leave > 0.0 {
        arrive = arrive * duration / (arrive + leave);
        leave = duration - arrive;
    }
    (arrive, leave)
}

/// A `during` slot that is actually running: `period` above zero, and a
/// duration to measure a drift against.
fn live_during(motion: &Motion, duration: f64) -> Option<(MotionDuring, f64, f64)> {
    let slot = motion.during?;
    let period = slot.period as f64;
    if period <= 0.0 || !period.is_finite() {
        return None;
    }
    // A drift divides by the clip's duration; every other kind ignores it.
    if matches!(slot.kind, DuringMotion::Drift) && duration <= 0.0 {
        return None;
    }
    let amount = if slot.amount.is_finite() {
        slot.amount.clamp(0.0, 1.0)
    } else {
        0.0
    };
    Some((slot, amount, period))
}

/// `video` with its five placed fields moved by whatever `video.motion`
/// asks for at `clip_t`. Every other field is the input's.
///
/// `size` is the source's pixel size (`Project::source_size`), `None` for
/// text; `container` is the canvas the clip is placed in — the project's,
/// or the frozen canvas of the nest it lives inside. See the module doc.
pub(crate) fn apply(
    video: &VideoProps,
    clip_t: Ticks,
    duration: Ticks,
    size: Option<(f64, f64)>,
    container: (f64, f64),
) -> VideoProps {
    let Some(motion) = video.motion else {
        return video.clone();
    };
    let t = clip_t as f64;
    let d = duration as f64;
    let (arrive, leave) = tent(&motion, d);

    let arrival_term = motion.r#in.filter(|_| arrive > 0.0 && t < arrive).map(|e| {
        let u = t / arrive;
        arrival(
            e.kind,
            crate::actions::ease(crate::model::Curve::EaseOut, u),
            u,
        )
    });
    let departure_term = motion
        .out
        .filter(|_| leave > 0.0 && t >= d - leave)
        .map(|e| {
            let v = 1.0 - (d - t) / leave;
            departure(
                e.kind,
                crate::actions::ease(crate::model::Curve::EaseIn, v),
                v,
            )
        });
    let during_term = live_during(&motion, d).map(|(slot, amount, period)| {
        during(slot.kind, amount, t, period, d, container.0, container.1)
    });

    // Nothing running: the clip is exactly where it is placed, and saying so
    // by cloning rather than by computing an identity is what makes the
    // frame byte-identical to a clip with no motion (module doc).
    if arrival_term.is_none() && departure_term.is_none() && during_term.is_none() {
        return video.clone();
    }

    let terms = [&arrival_term, &departure_term, &during_term];
    let mut factor = 1.0_f64;
    let mut phi = 0.0_f64;
    let mut opacity_factor = 1.0_f64;
    let mut delta = (0.0_f64, 0.0_f64);
    for term in terms.iter().filter_map(|t| t.as_ref()) {
        factor *= term.f;
        phi += term.phi;
        delta.0 += term.delta.0;
        delta.1 += term.delta.1;
    }
    // Opacity is the two EDGES only — a during never fades, so folding the
    // third term in would be a factor of 1 that could still round.
    for term in [&arrival_term, &departure_term]
        .iter()
        .filter_map(|t| t.as_ref())
    {
        opacity_factor *= term.o;
    }
    let phi = if phi.is_finite() {
        phi.rem_euclid(360.0)
    } else {
        0.0
    };

    let base_scale = if video.scale.is_finite() {
        video.scale
    } else {
        1.0
    };
    let base_rotation = if video.rotation.is_finite() {
        video.rotation
    } else {
        0.0
    };
    let drawn_scale = (base_scale * factor).clamp(SCALE_MIN, SCALE_MAX);
    let drawn_rotation = base_rotation + phi;

    // The cropped rect's centre in source pixels (★'s `c`), and the visible
    // size the slide box is measured from. Text has neither, so it takes the
    // half-canvas rule the module doc records as a limit.
    let crop = video.crop;
    let (centre, half_x, half_y) = match size {
        Some((sw, sh)) => {
            let visible_w = (sw - crop.l - crop.r).max(0.0);
            let visible_h = (sh - crop.t - crop.b).max(0.0);
            let k = drawn_rotation.to_radians().cos().abs();
            let n = drawn_rotation.to_radians().sin().abs();
            (
                ((crop.l - crop.r) / 2.0, (crop.t - crop.b) / 2.0),
                drawn_scale * (visible_w * k + visible_h * n) / 2.0,
                drawn_scale * (visible_w * n + visible_h * k) / 2.0,
            )
        }
        None => ((0.0, 0.0), container.0 / 2.0, container.1 / 2.0),
    };

    // The BASE visible centre — where the pivot compensation below holds the
    // layer whatever the other slots do to scale and rotation.
    let base_pivot = rotate(centre.0 * base_scale, centre.1 * base_scale, base_rotation);
    let p = (video.x + base_pivot.0, video.y + base_pivot.1);
    let side = |side: Side| match side {
        Side::Right => (container.0 / 2.0 + half_x - p.0, 0.0),
        Side::Left => (-(container.0 / 2.0 + half_x) - p.0, 0.0),
        Side::Bottom => (0.0, container.1 / 2.0 + half_y - p.1),
        Side::Top => (0.0, -(container.1 / 2.0 + half_y) - p.1),
    };
    for term in terms.iter().filter_map(|t| t.as_ref()) {
        if let Some((edge, fraction)) = term.slide {
            let (sx, sy) = side(edge);
            delta.0 += fraction * sx;
            delta.1 += fraction * sy;
        }
    }

    let drawn_pivot = rotate(
        centre.0 * drawn_scale,
        centre.1 * drawn_scale,
        drawn_rotation,
    );
    let x = video.x + base_pivot.0 - drawn_pivot.0 + delta.0;
    let y = video.y + base_pivot.1 - drawn_pivot.1 + delta.1;
    let opacity = video.opacity * opacity_factor;

    // A non-finite result leaves that field AS EVALUATED rather than
    // poisoning the frame: no NaN reaches the recipe.
    let keep = |moved: f64, evaluated: f64| if moved.is_finite() { moved } else { evaluated };
    VideoProps {
        x: keep(x, video.x),
        y: keep(y, video.y),
        scale: keep(drawn_scale, video.scale),
        rotation: keep(drawn_rotation, video.rotation),
        opacity: keep(opacity.clamp(0.0, 1.0), video.opacity),
        ..video.clone()
    }
}
