//! Spec §11 PR-15 (#374): what a deep raster costs beside the 8-bit one.
//! Ignored: a measurement, not a claim. One thread, alternating rounds, the
//! median of each; every buffer is made before the clock starts.
//!
//! `cargo test --release --test deep_bench -- --ignored --nocapture --test-threads=1`

mod common;

use std::fs;
use std::hint::black_box;
use std::time::Instant;

use common::{frame, library, module, GRAPHICS};
use graphic::{rasterize, rasterize_deep, Library};

const GRADIENT: &str =
    "<defs><radialGradient id=\"g\" gradientUnits=\"userSpaceOnUse\" cx=\"960\" \
    cy=\"540\" r=\"1100\"><stop offset=\"0\" stop-color=\"#2A4F3D\"/><stop offset=\"1\" \
    stop-color=\"#0D1512\"/></radialGradient></defs>";

fn median(values: &mut [f64]) -> f64 {
    values.sort_by(|a, b| a.partial_cmp(b).unwrap());
    values[values.len() / 2]
}

/// Every bundled template at a quarter and a half of its duration, then five
/// synthetic scenes, each drawn at `w`×`h` from a 1920×1080 view box.
fn scenes(w: u32, h: u32) -> Vec<(String, String)> {
    let mut names: Vec<String> = fs::read_dir(GRAPHICS)
        .unwrap()
        .map(|e| e.unwrap().path())
        .filter(|p| p.extension().is_some_and(|e| e == "js"))
        .map(|p| p.file_stem().unwrap().to_string_lossy().to_string())
        .collect();
    names.sort();
    let mut out = Vec::new();
    for name in names {
        let m = module(&name);
        let duration = m.meta()["durationInFrames"].as_i64().unwrap_or(150);
        for at in [duration / 4, duration / 2] {
            let (text, _) = frame(&m, at).expect("a frame");
            let text = if (w, h) == (1920, 1080) {
                text
            } else {
                assert!(text.contains("viewBox=\"0 0 1920 1080\""), "{name}");
                text.replacen("width=\"1920\"", &format!("width=\"{w}\""), 1)
                    .replacen("height=\"1080\"", &format!("height=\"{h}\""), 1)
            };
            out.push((format!("{name}@{at}"), text));
        }
    }
    let rect = "<rect width=\"1920\" height=\"1080\" fill=\"url(#g)\"/>";
    let wrap = |body: String| {
        format!(
            "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{w}\" height=\"{h}\" viewBox=\"0 0 1920 1080\">{GRADIENT}{body}</svg>"
        )
    };
    out.push((
        "synthetic: empty (the fixed cost)".into(),
        wrap(String::new()),
    ));
    out.push(("synthetic: full-canvas gradient".into(), wrap(rect.into())));
    out.push((
        "synthetic: gradient in a group at opacity 0.6".into(),
        wrap(format!(
            "<rect width=\"1920\" height=\"1080\" fill=\"#101010\"/><g opacity=\"0.6\">{rect}</g>"
        )),
    ));
    out.push((
        "synthetic: full-canvas solid at fill-opacity 0.5 over a solid".into(),
        wrap(
            "<rect width=\"1920\" height=\"1080\" fill=\"#204060\"/><rect width=\"1920\" height=\"1080\" fill=\"#ffffff\" fill-opacity=\"0.5\"/>"
                .into(),
        ),
    ));
    out.push((
        "synthetic: gradient under feGaussianBlur 4".into(),
        wrap(format!(
            "<filter id=\"f\" x=\"0\" y=\"0\" width=\"1\" height=\"1\"><feGaussianBlur stdDeviation=\"4\"/></filter><g filter=\"url(#f)\">{rect}</g>"
        )),
    ));
    out
}

fn eight(lib: &Library, text: &str, w: u32, h: u32, out: &mut [u8]) -> f64 {
    let start = Instant::now();
    rasterize(lib, text, w, h, out, w as usize * 4).expect("a raster");
    black_box(&out);
    start.elapsed().as_secs_f64() * 1e3
}

fn deep(lib: &Library, text: &str, w: u32, h: u32, out: &mut [u16]) -> f64 {
    let start = Instant::now();
    rasterize_deep(lib, text, w, h, out, w as usize * 4).expect("a raster");
    black_box(&out);
    start.elapsed().as_secs_f64() * 1e3
}

fn bench(w: u32, h: u32, rounds: usize) {
    let lib = library();
    let mut b8 = vec![0u8; (w * h * 4) as usize];
    let mut b16 = vec![0u16; (w * h * 4) as usize];
    let (mut all, mut templates) = ([0.0f64; 2], [0.0f64; 2]);
    println!("{w}×{h}, median of {rounds} alternating rounds, ms a raster");
    println!(
        "{:<62} {:>8} {:>8} {:>8}",
        "scene", "8-bit", "deep", "deep/8"
    );
    let scenes = scenes(w, h);
    let count = scenes
        .iter()
        .filter(|s| !s.0.starts_with("synthetic"))
        .count();
    for (name, text) in &scenes {
        eight(&lib, text, w, h, &mut b8); // one untimed warm raster (fonts, the image cache)
        let (mut t8, mut t16) = (Vec::new(), Vec::new());
        for _ in 0..rounds {
            t8.push(eight(&lib, text, w, h, &mut b8));
            t16.push(deep(&lib, text, w, h, &mut b16));
        }
        let m = [median(&mut t8), median(&mut t16)];
        for i in 0..2 {
            all[i] += m[i];
            if !name.starts_with("synthetic") {
                templates[i] += m[i];
            }
        }
        println!(
            "{:<62} {:>8.2} {:>8.2} {:>8.2}",
            name,
            m[0],
            m[1],
            m[1] / m[0]
        );
    }
    println!(
        "{:<62} {:>8.2} {:>8.2} {:>8.2}",
        format!("TEMPLATES ({count} frames) sum"),
        templates[0],
        templates[1],
        templates[1] / templates[0]
    );
    println!(
        "{:<62} {:>8.2} {:>8.2} {:>8.2}",
        "ALL sum",
        all[0],
        all[1],
        all[1] / all[0]
    );
}

#[test]
#[ignore]
fn bench_1080() {
    bench(1920, 1080, 7);
}

#[test]
#[ignore]
fn bench_2160() {
    bench(3840, 2160, 5);
}
