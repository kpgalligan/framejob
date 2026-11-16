//! Spec §11 PR-15 (#374): `rasterize_deep` keeps a gradient's levels at 16
//! bits a channel, through the vendored `tiny-skia` deep pixmap
//! (`graphic/vendor/`), and leaves `rasterize`'s 8-bit bytes alone.
//!
//! The oracles are independent of the patch: the exact value at a pixel
//! centre worked out here from the fixture's geometry, the count of
//! distinct values along #374's row, the length of flat runs where the
//! renderer reads a deep layer at 8 bits (a filter, a luminance mask), and
//! equality with the 8-bit raster wherever a colour sits on a level.

mod common;

use std::collections::BTreeSet;
use std::fs;
use std::sync::Arc;
use std::thread;

use common::{frame, library, messages, module, render, svg, GRAPHICS};
use graphic::{rasterize_deep, Diagnostic, Level, Library};

const W: u32 = 1920;
const H: u32 = 1080;

/// `raster_dither_proof.py`'s `band374` gradient: #374's span.
const GRADIENT: &str =
    "<defs><radialGradient id=\"g\" gradientUnits=\"userSpaceOnUse\" cx=\"960\" \
    cy=\"540\" r=\"1100\"><stop offset=\"0\" stop-color=\"#2A4F3D\"/><stop offset=\"1\" \
    stop-color=\"#0D1512\"/></radialGradient></defs>";
const RECT: &str = "<rect width=\"1920\" height=\"1080\" fill=\"url(#g)\"/>";

fn band(body: &str) -> String {
    svg(W, H, &format!("{GRADIENT}{body}"))
}

/// Draws `text` deep with stride `width × 4`; panics on an error.
fn deep(lib: &Library, text: &str, width: u32, height: u32) -> (Vec<u16>, Vec<Diagnostic>) {
    let stride = width as usize * 4;
    let mut out = vec![0u16; stride * height as usize];
    let warnings = rasterize_deep(lib, text, width, height, &mut out, stride)
        .unwrap_or_else(|e| panic!("rasterize_deep refused: {}", e.message));
    (out, warnings)
}

/// Row 540, x 0..=800, green, of a 1920-wide deep raster.
fn row(buf: &[u16]) -> Vec<u16> {
    (0..=800usize)
        .map(|x| buf[(540 * W as usize + x) * 4 + 1])
        .collect()
}

fn distinct(values: &[u16]) -> usize {
    values.iter().collect::<BTreeSet<_>>().len()
}

/// The median length of a run of equal neighbours.
fn median_run(values: &[u16]) -> usize {
    let mut runs = Vec::new();
    let mut run = 1;
    for pair in values.windows(2) {
        if pair[0] == pair[1] {
            run += 1;
        } else {
            runs.push(run);
            run = 1;
        }
    }
    runs.push(run);
    runs.sort();
    runs[runs.len() / 2]
}

/// T1: #374's gradient keeps a value a pixel, each within 2 of the exact one.
#[test]
fn the_gradient_keeps_its_levels() {
    let lib = library();
    let (out, warnings) = deep(&lib, &band(RECT), W, H);
    assert!(warnings.is_empty(), "{warnings:?}");
    let green = row(&out);
    let mut worst = 0.0f64;
    for (x, got) in green.iter().enumerate() {
        let (dx, dy) = (x as f64 + 0.5 - 960.0, 0.5);
        let t = ((dx * dx + dy * dy).sqrt() / 1100.0).min(1.0);
        let exact = (79.0 + (21.0 - 79.0) * t) / 255.0 * 65535.0;
        worst = worst.max((*got as f64 - exact).abs());
    }
    println!(
        "T1: {} distinct of 801, worst |error| {worst:.2} of 65535",
        distinct(&green)
    );
    assert!(distinct(&green) >= 780, "{} distinct", distinct(&green));
    assert!(worst <= 2.0, "worst error {worst}");
    assert!(out.chunks_exact(4).all(|p| p[3] == 65535), "not opaque");
}

/// T2–T4: the levels survive every layer resvg makes: an isolated group, a
/// pattern tile, a translucent solid over it (lowp at 8 bits), a clip path
/// and a flat mask.
#[test]
fn the_levels_survive_every_layer() {
    let lib = library();
    let scenes = [
        (
            "T2 a group at opacity 0.6",
            format!("<rect width=\"1920\" height=\"1080\" fill=\"#101010\"/><g opacity=\"0.6\">{RECT}</g>"),
        ),
        (
            "T2 a pattern tile",
            format!(
                "<pattern id=\"p\" patternUnits=\"userSpaceOnUse\" width=\"1920\" height=\"1080\">{RECT}</pattern>\
                 <rect width=\"1920\" height=\"1080\" fill=\"url(#p)\"/>"
            ),
        ),
        (
            "T3 a translucent solid over it",
            format!("{RECT}<rect width=\"1920\" height=\"1080\" fill=\"#000000\" fill-opacity=\"0.3\"/>"),
        ),
        (
            "T4 a clip path",
            format!(
                "<clipPath id=\"c\"><circle cx=\"960\" cy=\"540\" r=\"1000\"/></clipPath>\
                 <g clip-path=\"url(#c)\">{RECT}</g>"
            ),
        ),
        (
            "T4 a flat mask",
            format!(
                "<mask id=\"m\"><rect width=\"1920\" height=\"1080\" fill=\"#ffffff\" fill-opacity=\"0.8\"/></mask>\
                 <g mask=\"url(#m)\">{RECT}</g>"
            ),
        ),
    ];
    let mut failures = Vec::new();
    for (name, body) in scenes {
        let (out, warnings) = deep(&lib, &band(&body), W, H);
        assert!(warnings.is_empty(), "{name}: {warnings:?}");
        let count = distinct(&row(&out));
        println!("{name}: {count} distinct of 801");
        if count < 780 {
            failures.push(format!("{name}: {count} distinct"));
        }
        // The clip and the mask are applied, not only survived: the corner
        // outside the clip's circle is empty, and the mask's 204/255 scales
        // every value.
        let corner = out[3];
        if name == "T4 a clip path" && corner != 0 {
            failures.push(format!("{name}: the corner's alpha is {corner}"));
        }
        if name == "T4 a flat mask" {
            let worst = (0..=800usize)
                .map(|x| {
                    let t = (((x as f64 + 0.5 - 960.0).powi(2) + 0.25).sqrt() / 1100.0).min(1.0);
                    let exact = (79.0 - 58.0 * t) / 255.0 * 65535.0 * 204.0 / 255.0;
                    (out[(540 * W as usize + x) * 4 + 1] as f64 - exact).abs()
                })
                .fold(0.0, f64::max);
            println!("{name}: worst |error| {worst:.2} of 65535");
            if worst > 3.0 {
                failures.push(format!("{name}: {worst:.2} from the masked value"));
            }
        }
    }
    assert!(failures.is_empty(), "{failures:?}");
}

/// T5: where the renderer reads a deep layer at 8 bits, it rounds with
/// PR-13's offset. A filter under sRGB interpolation reads its source's
/// bytes as they are, and a luminance mask reads the gradient as coverage;
/// both come out on 8-bit levels, in runs as short as today's dither's.
#[test]
fn a_layer_read_at_eight_bits_is_dithered() {
    let lib = library();
    let scenes = [
        (
            "a filtered group",
            format!(
                "<filter id=\"f\" x=\"0\" y=\"0\" width=\"1\" height=\"1\" color-interpolation-filters=\"sRGB\">\
                 <feDropShadow dx=\"0\" dy=\"8\" stdDeviation=\"2\" flood-opacity=\"0.5\"/></filter>\
                 <g filter=\"url(#f)\">{RECT}</g>"
            ),
        ),
        (
            "a filter's arithmetic composite",
            format!(
                "<filter id=\"f\" x=\"0\" y=\"0\" width=\"1\" height=\"1\" color-interpolation-filters=\"sRGB\">\
                 <feComposite in=\"SourceGraphic\" in2=\"SourceGraphic\" operator=\"arithmetic\" \
                 k1=\"0\" k2=\"1\" k3=\"0\" k4=\"0\"/></filter><g filter=\"url(#f)\">{RECT}</g>"
            ),
        ),
        (
            "a luminance mask",
            "<mask id=\"m\"><rect width=\"1920\" height=\"1080\" fill=\"url(#g)\"/></mask>\
             <rect width=\"1920\" height=\"1080\" fill=\"#ffffff\" mask=\"url(#m)\"/>"
                .to_string(),
        ),
    ];
    let mut failures = Vec::new();
    for (name, body) in scenes {
        let (out, warnings) = deep(&lib, &band(&body), W, H);
        assert!(warnings.is_empty(), "{name}: {warnings:?}");
        let green = row(&out);
        let (run, count) = (median_run(&green), distinct(&green));
        println!("T5 {name}: median run {run} px, {count} levels");
        if green.iter().any(|v| v % 257 != 0) {
            failures.push(format!("{name}: a value off an 8-bit level"));
        }
        if run > 4 {
            failures.push(format!("{name}: median run {run} px"));
        }
        if count < 20 {
            failures.push(format!("{name}: {count} levels"));
        }
    }
    assert!(failures.is_empty(), "{failures:?}");
}

/// T5b: `collapse` gives the offset to every pixel holding a residual, not
/// only a gradient's (PR-15's limit). A flat translucent fill inside a
/// filtered group, premultiplied red 40.8, is a mix of levels 40 and 41
/// whose mean is within a tenth of a level in a deep raster, flat in the 8-bit one, and an
/// opaque fill on a level is flat in both.
#[test]
fn a_flat_colour_in_a_filter_takes_the_offset() {
    let lib = library();
    let scene = |opacity: &str| {
        svg(
            256,
            128,
            &format!(
                "<filter id=\"f\" x=\"0\" y=\"0\" width=\"1\" height=\"1\" \
                 color-interpolation-filters=\"sRGB\"><feComposite in=\"SourceGraphic\" \
                 in2=\"SourceGraphic\" operator=\"arithmetic\" k1=\"0\" k2=\"1\" k3=\"0\" \
                 k4=\"0\"/></filter><g filter=\"url(#f)\"><rect width=\"256\" height=\"128\" \
                 fill=\"#336699\" fill-opacity=\"{opacity}\"/></g>"
            ),
        )
    };
    let inner = || (32..96usize).flat_map(|y| (32..224usize).map(move |x| (y * 256 + x) * 4));
    let (out, warnings) = deep(&lib, &scene("0.8"), 256, 128);
    assert!(warnings.is_empty(), "{warnings:?}");
    let reds: Vec<u16> = inner().map(|i| out[i]).collect();
    let levels: BTreeSet<u16> = reds.iter().copied().collect();
    let mean = reds.iter().map(|v| *v as f64).sum::<f64>() / reds.len() as f64 / 257.0;
    println!("T5b translucent: levels {levels:?}, mean {mean:.4} of 40.8");
    assert_eq!(levels, BTreeSet::from([40 * 257, 41 * 257]));
    assert!((mean - 40.8).abs() < 0.1, "mean {mean}");
    assert!(inner().all(|i| out[i + 3] == 204 * 257), "alpha moved");
    let (eight, _) = render(&lib, &scene("0.8"), 256, 128);
    assert!(
        inner().all(|i| eight[i + 2] == 41),
        "the 8-bit raster is not flat"
    );
    let (opaque, _) = deep(&lib, &scene("1"), 256, 128);
    assert!(
        inner().all(|i| opaque[i] == 51 * 257 && opaque[i + 3] == 65535),
        "an opaque colour on a level moved"
    );
}

/// T6: the door is per call and per thread: an 8-bit raster after a deep
/// one, and beside deep ones on other threads, is the one taken before.
#[test]
fn the_eight_bit_raster_is_unchanged_beside_a_deep_one() {
    let lib = Arc::new(library());
    let text = band(RECT);
    let (before, _) = render(&lib, &text, W, H);
    let (deep_before, _) = deep(&lib, &text, W, H);
    let (after, _) = render(&lib, &text, W, H);
    assert!(before == after, "an 8-bit raster after a deep one differs");
    let handles: Vec<_> = (0..4)
        .map(|i| {
            let (lib, text) = (lib.clone(), text.clone());
            thread::spawn(move || {
                let mut answers = Vec::new();
                for _ in 0..3 {
                    answers.push(if i % 2 == 0 {
                        (render(&lib, &text, W, H).0, Vec::new())
                    } else {
                        (Vec::new(), deep(&lib, &text, W, H).0)
                    });
                }
                answers
            })
        })
        .collect();
    for handle in handles {
        for (eight, sixteen) in handle.join().unwrap() {
            assert!(eight.is_empty() || eight == before, "8-bit beside deep");
            assert!(
                sixteen.is_empty() || sixteen == deep_before,
                "deep beside 8-bit"
            );
        }
    }
}

/// T7: a colour on a level is the 8-bit raster's, widened; and every
/// bundled template stays within 4 levels of its 8-bit raster, each channel
/// at most its alpha, with the same warnings.
#[test]
fn a_deep_raster_agrees_with_the_eight_bit_one() {
    let lib = library();
    let solids = svg(
        64,
        64,
        "<rect width=\"64\" height=\"64\" fill=\"#204060\"/>\
         <rect x=\"8\" y=\"8\" width=\"16\" height=\"16\" fill=\"#ff8000\"/>\
         <rect x=\"32\" y=\"32\" width=\"16\" height=\"16\" fill=\"#0D1512\"/>",
    );
    let (eight, _) = render(&lib, &solids, 64, 64);
    let (sixteen, _) = deep(&lib, &solids, 64, 64);
    for (p, q) in eight.chunks_exact(4).zip(sixteen.chunks_exact(4)) {
        let want = [p[2], p[1], p[0], p[3]].map(|c| c as u16 * 257);
        assert_eq!(q, want, "a solid is not the 8-bit raster × 257");
    }

    let mut names: Vec<String> = fs::read_dir(GRAPHICS)
        .unwrap()
        .map(|e| e.unwrap().path())
        .filter(|p| p.extension().is_some_and(|e| e == "js"))
        .map(|p| p.file_stem().unwrap().to_string_lossy().to_string())
        .collect();
    names.sort();
    assert!(names.len() >= 23, "{} templates", names.len());
    let (mut worst, mut failures) = (0i32, Vec::new());
    for name in names {
        let m = module(&name);
        let duration = m.meta()["durationInFrames"].as_i64().unwrap_or(150);
        let (text, _) = frame(&m, duration / 2).expect("a frame");
        let (eight, warned8) = render(&lib, &text, W, H);
        let (sixteen, warned16) = deep(&lib, &text, W, H);
        if messages(&warned8) != messages(&warned16) {
            failures.push(format!("{name}: warnings differ"));
        }
        let mut far = 0i32;
        let mut over = 0usize;
        for (p, q) in eight.chunks_exact(4).zip(sixteen.chunks_exact(4)) {
            let p = [p[2], p[1], p[0], p[3]];
            for c in 0..4 {
                // 257 is one level; compare in 16-bit units, rounded up to levels.
                far = far.max((p[c] as i32 * 257 - q[c] as i32).abs());
            }
            if q[..3].iter().any(|c| *c > q[3]) {
                over += 1;
            }
        }
        worst = worst.max(far);
        if far > 4 * 257 {
            failures.push(format!("{name}: {far} of 65535 from the 8-bit raster"));
        }
        if over > 0 {
            failures.push(format!("{name}: {over} pixels with a channel over alpha"));
        }
    }
    println!(
        "T7: worst distance from the 8-bit raster {worst} of 65535 ({:.2} levels)",
        worst as f64 / 257.0
    );
    assert!(failures.is_empty(), "{failures:?}");
}

/// T8: the refusals are `rasterize`'s, counted in values; values past the
/// row are untouched; and the same call twice writes the same values.
#[test]
fn the_refusals_the_stride_and_determinism() {
    let lib = library();
    let rect = svg(4, 4, "<rect width=\"4\" height=\"4\" fill=\"#fff\"/>");
    let cases: [(&str, u32, u32, usize, usize, &str); 5] = [
        (
            &rect,
            8193,
            4,
            8193 * 4,
            8193 * 16,
            "width 8193 is over the 8192 cap",
        ),
        (&rect, 4, 0, 16, 64, "height 0 is not allowed"),
        (&rect, 4, 4, 12, 64, "stride 12 is under width × 4 = 16"),
        (
            &rect,
            4,
            40,
            16,
            100,
            "out holds 100 values; height × stride needs 640",
        ),
        ("not an svg", 4, 4, 16, 64, "the SVG did not parse: "),
    ];
    for (text, width, height, stride, len, want) in cases {
        let mut out = vec![0xABCDu16; len];
        let error = rasterize_deep(&lib, text, width, height, &mut out, stride).expect_err(want);
        assert_eq!(error.level, Level::Error);
        assert!(
            error.message.starts_with(want),
            "{:?} vs {want:?}",
            error.message
        );
        assert!(out.iter().all(|v| *v == 0xABCD), "{want}: out was written");
    }

    let (width, height, stride) = (5u32, 4u32, 32usize);
    let mut out = vec![0xABCDu16; stride * height as usize];
    let body = "<rect width=\"5\" height=\"4\" fill=\"#00ff00\"/>";
    let warnings = rasterize_deep(&lib, &svg(5, 4, body), width, height, &mut out, stride).unwrap();
    assert!(warnings.is_empty(), "{warnings:?}");
    for y in 0..height as usize {
        for x in 0..width as usize {
            let at = y * stride + x * 4;
            assert_eq!(out[at..at + 4], [0, 65535, 0, 65535], "pixel ({x}, {y})");
        }
        let padding = &out[y * stride + 20..(y + 1) * stride];
        assert!(padding.iter().all(|v| *v == 0xABCD), "row {y}: {padding:?}");
    }

    let text = band(RECT);
    assert!(deep(&lib, &text, W, H).0 == deep(&lib, &text, W, H).0);
}

/// T9: a fade from 1/255 to transparent in a group at opacity 0.4, every
/// value under half an 8-bit level, keeps its values where the 8-bit plane
/// alone reads zero.
#[test]
fn a_fade_to_nothing_keeps_its_tail() {
    let lib = library();
    let body = "<defs><linearGradient id=\"f\" gradientUnits=\"userSpaceOnUse\" x1=\"0\" y1=\"0\" \
                x2=\"1024\" y2=\"0\"><stop offset=\"0\" stop-color=\"#ffffff\" stop-opacity=\"0.004\"/>\
                <stop offset=\"1\" stop-color=\"#ffffff\" stop-opacity=\"0\"/></linearGradient></defs>\
                <g opacity=\"0.4\"><rect width=\"1024\" height=\"8\" fill=\"url(#f)\"/></g>";
    let (out, _) = deep(&lib, &svg(1024, 8, body), 1024, 8);
    let alpha: Vec<u16> = (0..1024).map(|x| out[(4 * 1024 + x) * 4 + 3]).collect();
    let tail: BTreeSet<u16> = alpha
        .iter()
        .copied()
        .filter(|v| (1..128).contains(v))
        .collect();
    println!(
        "T9: {} distinct non-zero alphas under 128 of 65535",
        tail.len()
    );
    assert!(tail.len() >= 50, "{} values in the tail", tail.len());
    assert!(alpha.iter().all(|v| *v < 128), "a value on an 8-bit level");
    assert!(
        alpha.windows(2).all(|p| p[0] >= p[1]),
        "the fade is not monotonic"
    );
}
