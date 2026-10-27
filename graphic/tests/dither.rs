//! Spec §11 PR-13 (#375 part 1): a gradient is dithered where tiny-skia
//! rounds it to 8 bits, by a fixed pattern of pixel position under half a
//! level, through the vendored `tiny-skia` patch (`graphic/vendor/`).
//!
//! The oracles are independent of the stage: `e` is the exact value in
//! levels, worked out here from each fixture's geometry at pixel centres,
//! and every claim is about the bytes `rasterize` writes against it — a
//! bracket of one level each side, the share of pixels that take the level
//! the plain rounding would never give, column means against `e`, and
//! equality with a solid fill, a translated copy or another channel.

mod common;

use std::time::Instant;

use common::{library, pixel, render, svg};

const DARK: [f64; 3] = [13.0, 21.0, 18.0]; // #0D1512
const MID: [f64; 3] = [42.0, 79.0, 61.0]; // #2A4F3D
const LIGHT: [f64; 3] = [60.0, 122.0, 90.0]; // #3C7A5A
const W: usize = 1024;
const H: usize = 256;

/// The RGB of BGRA pixel `(x, y)` in a `W`-wide buffer, as R, G, B.
fn rgb(buf: &[u8], width: usize, x: usize, y: usize) -> [u8; 3] {
    let p = pixel(buf, width * 4, x, y);
    [p[2], p[1], p[0]]
}

fn lerp(a: [f64; 3], b: [f64; 3], t: f64) -> [f64; 3] {
    [0, 1, 2].map(|c| a[c] + (b[c] - a[c]) * t)
}

/// The linear two-stop's exact value at column `x`.
fn two_stop(x: usize) -> [f64; 3] {
    lerp(DARK, LIGHT, (x as f64 + 0.5) / W as f64)
}

/// The three-stop's (offsets 0, 0.3, 1) exact value at column `x`.
fn three_stop(x: usize) -> [f64; 3] {
    let t = (x as f64 + 0.5) / W as f64;
    if t <= 0.3 {
        lerp(DARK, MID, t / 0.3)
    } else {
        lerp(MID, LIGHT, (t - 0.3) / 0.7)
    }
}

/// The radial's (centre 512, 128, r 600) exact value at `(x, y)`.
fn radial(x: usize, y: usize) -> [f64; 3] {
    let (dx, dy) = (x as f64 + 0.5 - 512.0, y as f64 + 0.5 - 128.0);
    lerp(DARK, LIGHT, ((dx * dx + dy * dy).sqrt() / 600.0).min(1.0))
}

fn stops(colours: &[(f64, &str)], opacity: &str) -> String {
    colours
        .iter()
        .map(|(at, c)| {
            format!("<stop offset=\"{at}\" stop-color=\"{c}\" stop-opacity=\"{opacity}\"/>")
        })
        .collect()
}

fn linear_svg(colours: &[(f64, &str)]) -> String {
    let body = format!(
        "<defs><linearGradient id=\"g\" gradientUnits=\"userSpaceOnUse\" x1=\"0\" y1=\"0\" \
         x2=\"{W}\" y2=\"0\">{}</linearGradient></defs>\
         <rect width=\"{W}\" height=\"{H}\" fill=\"url(#g)\"/>",
        stops(colours, "1")
    );
    svg(W as u32, H as u32, &body)
}

fn radial_svg() -> String {
    let body = format!(
        "<defs><radialGradient id=\"g\" gradientUnits=\"userSpaceOnUse\" cx=\"512\" cy=\"128\" \
         r=\"600\">{}</radialGradient></defs>\
         <rect width=\"{W}\" height=\"{H}\" fill=\"url(#g)\"/>",
        stops(&[(0.0, "#0D1512"), (1.0, "#3C7A5A")], "1")
    );
    svg(W as u32, H as u32, &body)
}

/// `raster_dither_proof.py`'s `band374`: a full-canvas radial gradient over
/// #374's span, at 1920×1080.
fn band374() -> String {
    let body = "<defs><radialGradient id=\"g\" gradientUnits=\"userSpaceOnUse\" cx=\"960\" \
                cy=\"540\" r=\"1100\"><stop offset=\"0\" stop-color=\"#2A4F3D\"/>\
                <stop offset=\"1\" stop-color=\"#0D1512\"/></radialGradient></defs>\
                <rect width=\"1920\" height=\"1080\" fill=\"url(#g)\"/>";
    svg(1920, 1080, body)
}

#[test]
fn every_gradient_kind_brackets_its_exact_value() {
    let lib = library();
    type Exact = Box<dyn Fn(usize, usize) -> [f64; 3]>;
    let kinds: [(&str, String, Exact); 3] = [
        (
            "linear two-stop",
            linear_svg(&[(0.0, "#0D1512"), (1.0, "#3C7A5A")]),
            Box::new(|x, _| two_stop(x)),
        ),
        (
            "linear three-stop",
            linear_svg(&[(0.0, "#0D1512"), (0.3, "#2A4F3D"), (1.0, "#3C7A5A")]),
            Box::new(|x, _| three_stop(x)),
        ),
        ("radial two-stop", radial_svg(), Box::new(radial)),
    ];
    let mut failures = Vec::new();
    for (name, text, exact) in kinds {
        let (out, warnings) = render(&lib, &text, W as u32, H as u32);
        assert!(warnings.is_empty(), "{name}: {warnings:?}");
        let (mut outside, mut first) = (0usize, None);
        let (mut low_n, mut low_up, mut high_n, mut high_down) = (0usize, 0usize, 0usize, 0usize);
        for y in 0..H {
            for x in 0..W {
                let got = rgb(&out, W, x, y);
                let e = exact(x, y);
                for c in 0..3 {
                    let (v, e) = (got[c] as f64, e[c]);
                    let (lo, hi) = ((e - 1.0 / 16.0).floor(), (e + 1.0 / 16.0).ceil());
                    if v < lo || v > hi {
                        outside += 1;
                        first.get_or_insert(format!("({x}, {y}) channel {c}: {v}, e {e:.4}"));
                    }
                    let frac = e - e.floor();
                    if (0.15..=0.45).contains(&frac) {
                        low_n += 1;
                        low_up += (v == e.ceil()) as usize;
                    } else if (0.55..=0.85).contains(&frac) {
                        high_n += 1;
                        high_down += (v == e.floor()) as usize;
                    }
                }
            }
        }
        let up = low_up as f64 / low_n.max(1) as f64;
        let down = high_down as f64 / high_n.max(1) as f64;
        println!(
            "{name}: {outside} outside the bracket; frac 0.15–0.45 take ceil(e) {:.1} % of \
             {low_n}; frac 0.55–0.85 take floor(e) {:.1} % of {high_n}",
            up * 100.0,
            down * 100.0
        );
        if outside > 0 {
            failures.push(format!("{name}: {outside} outside, first {first:?}"));
        }
        if low_n == 0 || up < 0.05 {
            failures.push(format!("{name}: ceil(e) share {up:.4} under 5 %"));
        }
        if high_n == 0 || down < 0.05 {
            failures.push(format!("{name}: floor(e) share {down:.4} under 5 %"));
        }
    }
    assert!(failures.is_empty(), "{failures:#?}");
}

#[test]
fn column_means_follow_the_exact_value() {
    let lib = library();
    let text = linear_svg(&[(0.0, "#0D1512"), (1.0, "#3C7A5A")]);
    let (out, _) = render(&lib, &text, W as u32, H as u32);
    let (mut sum, mut rounded) = (0.0, 0.0);
    for x in 0..W {
        let mean = (0..H).map(|y| rgb(&out, W, x, y)[1] as f64).sum::<f64>() / H as f64;
        let e = two_stop(x)[1];
        sum += (mean - e).powi(2);
        rounded += (e.round() - e).powi(2);
    }
    let rms = (sum / W as f64).sqrt();
    let plain = (rounded / W as f64).sqrt();
    println!("column means of G: RMS {rms:.4} levels against e; round(e)'s RMS {plain:.4}");
    assert!(
        rms <= 0.1,
        "RMS {rms:.4} over 0.1 (round(e) would be {plain:.4})"
    );
}

#[test]
fn a_colour_on_a_level_stays_exact() {
    let lib = library();
    for (colour, opacity) in [("#336699", "1"), ("#326496", "0.6")] {
        let body = format!(
            "<defs><linearGradient id=\"g\" x1=\"0\" y1=\"0\" x2=\"1\" y2=\"0\">{}\
             </linearGradient></defs>\
             <rect width=\"256\" height=\"64\" fill=\"url(#g)\"/>\
             <rect x=\"256\" width=\"64\" height=\"64\" fill=\"{colour}\" \
             fill-opacity=\"{opacity}\"/>",
            stops(&[(0.0, colour), (1.0, colour)], opacity)
        );
        let (out, _) = render(&lib, &svg(320, 64, &body), 320, 64);
        let solid = pixel(&out, 320 * 4, 288, 32);
        let mut differ = Vec::new();
        for y in 0..64 {
            for x in 0..320 {
                let got = pixel(&out, 320 * 4, x, y);
                if got != solid {
                    differ.push(((x, y), got));
                }
            }
        }
        println!(
            "{colour} at {opacity}: the solid is BGRA {solid:?}; {} pixels differ",
            differ.len()
        );
        assert!(
            differ.is_empty(),
            "{colour} at {opacity}: {} pixels differ from the solid {solid:?}, first {:?}",
            differ.len(),
            &differ[..differ.len().min(4)]
        );
    }
}

#[test]
fn one_offset_for_every_channel() {
    let lib = library();
    let (out, _) = render(
        &lib,
        &linear_svg(&[(0.0, "#202020"), (1.0, "#A0A0A0")]),
        W as u32,
        H as u32,
    );
    let mut split = Vec::new();
    for y in 0..H {
        for x in 0..W {
            let [r, g, b] = rgb(&out, W, x, y);
            if r != g || g != b {
                split.push(((x, y), [r, g, b]));
            }
        }
    }
    assert!(
        split.is_empty(),
        "{} grey pixels with unequal channels, first {:?}",
        split.len(),
        &split[..split.len().min(4)]
    );
}

#[test]
fn alpha_is_not_dithered() {
    let lib = library();
    let body = "<defs><linearGradient id=\"g\" gradientUnits=\"userSpaceOnUse\" x1=\"0\" \
                y1=\"0\" x2=\"512\" y2=\"0\"><stop offset=\"0\" stop-color=\"#fff\" \
                stop-opacity=\"0.1\"/><stop offset=\"1\" stop-color=\"#fff\" \
                stop-opacity=\"0.9\"/></linearGradient></defs>\
                <rect width=\"512\" height=\"64\" fill=\"url(#g)\"/>";
    let (out, _) = render(&lib, &svg(512, 64, body), 512, 64);
    let alpha = |y: usize| -> Vec<u8> { (0..512).map(|x| pixel(&out, 2048, x, y)[3]).collect() };
    let row0 = alpha(0);
    let moved: Vec<usize> = (1..64).filter(|&y| alpha(y) != row0).collect();
    let mut over = Vec::new();
    let mut varied = 0;
    for x in 0..512 {
        let first = pixel(&out, 2048, x, 0);
        let mut differs = false;
        for y in 0..64 {
            let p = pixel(&out, 2048, x, y);
            if p[0] > p[3] || p[1] > p[3] || p[2] > p[3] {
                over.push(((x, y), p));
            }
            differs |= p[..3] != first[..3];
        }
        varied += differs as usize;
    }
    println!(
        "{} rows' alpha differ from row 0's; {} pixels with a channel over alpha; {varied} \
         columns whose colour differs between rows",
        moved.len(),
        over.len()
    );
    assert!(
        moved.is_empty(),
        "rows whose alpha differ from row 0: {moved:?}"
    );
    assert!(
        over.is_empty(),
        "{} channels over alpha, first {:?}",
        over.len(),
        &over[..over.len().min(4)]
    );
    assert!(
        varied > 0,
        "no column's colour differs between rows: not dithered"
    );
}

/// The `size`×`size` block at `(x, y)`, row by row.
fn block(buf: &[u8], width: usize, x: usize, y: usize, size: usize) -> Vec<u8> {
    (y..y + size)
        .flat_map(|row| buf[(row * width + x) * 4..(row * width + x + size) * 4].to_vec())
        .collect()
}

#[test]
fn solid_paints_text_and_images_are_not_dithered() {
    let lib = library();
    let body = "<rect x=\"20\" y=\"20\" width=\"200\" height=\"100\" fill=\"#336699\" \
                fill-opacity=\"0.6\"/>\
                <text x=\"300\" y=\"600\" font-family=\"Anton\" font-size=\"560\" \
                fill=\"#336699\" fill-opacity=\"0.6\">M</text>";
    let (out, warnings) = render(&lib, &svg(1024, 640, body), 1024, 640);
    assert!(warnings.is_empty(), "{warnings:?}");
    let rect: Vec<[u8; 4]> = (20..120)
        .flat_map(|y| (20..220).map(move |x| (x, y)))
        .map(|(x, y)| pixel(&out, 4096, x, y))
        .collect();
    let mut rect_values = rect.clone();
    rect_values.sort();
    rect_values.dedup();
    let glyph: Vec<[u8; 4]> = (0..640)
        .flat_map(|y| (260..1024).map(move |x| (x, y)))
        .map(|(x, y)| pixel(&out, 4096, x, y))
        .filter(|p| p[3] == 153)
        .collect();
    let mut glyph_values = glyph.clone();
    glyph_values.sort();
    glyph_values.dedup();
    println!(
        "rect: {} values over {} pixels; glyph: {} values over {} fully covered pixels",
        rect_values.len(),
        rect.len(),
        glyph_values.len(),
        glyph.len()
    );
    assert_eq!(rect_values.len(), 1, "the solid rect: {rect_values:?}");
    assert!(
        glyph.len() > 10_000,
        "the glyph covers {} pixels",
        glyph.len()
    );
    assert_eq!(glyph_values.len(), 1, "the glyph: {glyph_values:?}");

    let place = |what: &str| -> Vec<u8> {
        let body = format!(
            "<defs><linearGradient id=\"g\" x1=\"0\" y1=\"0\" x2=\"1\" y2=\"1\">\
             <stop offset=\"0\" stop-color=\"#0D1512\"/><stop offset=\"1\" \
             stop-color=\"#3C7A5A\"/></linearGradient></defs>\
             {}{}",
            what.replace("XY", "x=\"0\" y=\"0\""),
            what.replace("XY", "x=\"517\" y=\"263\"")
        );
        render(&lib, &svg(1024, 640, &body), 1024, 640).0
    };
    let image =
        place("<image XY width=\"200\" height=\"200\" href=\"steel.jpg\" opacity=\"0.6\"/>");
    let images_equal = block(&image, 1024, 0, 0, 200) == block(&image, 1024, 517, 263, 200);
    let gradient = place("<rect XY width=\"200\" height=\"200\" fill=\"url(#g)\"/>");
    let gradients_equal =
        block(&gradient, 1024, 0, 0, 200) == block(&gradient, 1024, 517, 263, 200);
    println!("image copies equal: {images_equal}; gradient copies equal: {gradients_equal}");
    assert!(images_equal, "the two copies of steel.jpg differ");
    assert!(
        !gradients_equal,
        "the two copies of the objectBoundingBox gradient are equal: not dithered by position"
    );
}

#[test]
#[ignore]
fn section_gradient_raster_cost() {
    let lib = library();
    let text = band374();
    render(&lib, &text, 1920, 1080);
    let mut times: Vec<f64> = (0..30)
        .map(|_| {
            let started = Instant::now();
            render(&lib, &text, 1920, 1080);
            started.elapsed().as_secs_f64() * 1000.0
        })
        .collect();
    times.sort_by(|a, b| a.partial_cmp(b).unwrap());
    println!(
        "band374 at 1920×1080: median {:.2} ms over 30 (min {:.2}, max {:.2})",
        times[15], times[0], times[29]
    );
}
