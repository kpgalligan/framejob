//! The bundled templates (spec §11 G-44): every module of `tests/graphics/`
//! except road map 10's six fixtures draws without a warning, with no `NaN`
//! or `Infinity` in its SVG, and nothing outside the 90 % title-safe
//! rectangle moves — at 1920×1080, 1080×1920 and 1080×1080, every fifth
//! frame and the last, which every outro leaves bare. Every combination of
//! a template's `enum` options is held to the same through its entrance,
//! its hold and its last frame, and so is every template with its `string`
//! properties long (`templates/long_text.rs`). `project.yml` copies exactly
//! the folder's modules.
//! `GRAPHIC_TEMPLATE_PNGS=<dir>` writes frames 12, D/2 and D−8 of each, over
//! opaque `#6e6e74`, for a person to look at.

mod common;

use std::fs;
use std::time::Instant;

use graphic::{rasterize, Module};
use serde_json::Value;

use common::{shared, BUDGET_MS, FIXTURES, GRAPHICS};

#[path = "templates/long_text.rs"]
mod long_text;

const SIZES: [(u32, u32); 3] = [(1920, 1080), (1080, 1920), (1080, 1080)];
const FPS: f64 = 30.0;

/// The template stems: the folder's `*.js` less the fixtures, sorted.
fn templates() -> Vec<String> {
    let mut stems: Vec<String> = fs::read_dir(GRAPHICS)
        .expect("tests/graphics")
        .map(|entry| entry.expect("a directory entry").path())
        .filter(|path| path.extension().is_some_and(|ext| ext == "js"))
        .map(|path| path.file_stem().unwrap().to_string_lossy().into_owned())
        .filter(|stem| !FIXTURES.contains(&stem.as_str()))
        .collect();
    stems.sort();
    assert!(!stems.is_empty(), "no template in {GRAPHICS}");
    stems
}

fn duration(module: &Module) -> i64 {
    module.meta()["durationInFrames"]
        .as_i64()
        .expect("a template's meta.durationInFrames")
}

/// One frame drawn: the BGRA, or every problem with it named.
fn draw(
    module: &Module,
    frame: i64,
    props: &Value,
    (width, height): (u32, u32),
) -> Result<Vec<u8>, String> {
    let name = module.name();
    let ctx = common::ctx(frame, FPS, duration(module), width, height);
    let at = format!("{name} {width}x{height} frame {frame}");
    let (svg, warnings) = graphic::svg(module, frame, props, &ctx, BUDGET_MS)
        .map_err(|d| format!("{at}: {}", d.message))?;
    if !warnings.is_empty() {
        return Err(format!(
            "{at}: svg warned {:?}",
            common::messages(&warnings)
        ));
    }
    for bad in ["NaN", "Infinity"] {
        if svg.contains(bad) {
            return Err(format!("{at}: the SVG holds {bad}"));
        }
    }
    let stride = width as usize * 4;
    let mut out = vec![0u8; stride * height as usize];
    let raster = rasterize(&shared(), &svg, width, height, &mut out, stride)
        .map_err(|d| format!("{at}: rasterize refused: {}", d.message))?;
    if !raster.is_empty() {
        return Err(format!(
            "{at}: rasterize warned {:?}",
            common::messages(&raster)
        ));
    }
    Ok(out)
}

/// Whether pixel `(x, y)` is outside title-safe: x ∈ [0.05W, 0.95W),
/// y ∈ [0.05H, 0.95H).
fn outside(x: u32, y: u32, (width, height): (u32, u32)) -> bool {
    x < width * 5 / 100 || x >= width * 95 / 100 || y < height * 5 / 100 || y >= height * 95 / 100
}

/// The first pixel outside title-safe where `a` and `b` differ.
fn first_difference(a: &[u8], b: &[u8], size: (u32, u32)) -> Option<(u32, u32)> {
    let (width, height) = size;
    for y in 0..height {
        for x in 0..width {
            let at = (y as usize * width as usize + x as usize) * 4;
            if outside(x, y, size) && a[at..at + 4] != b[at..at + 4] {
                return Some((x, y));
            }
        }
    }
    None
}

/// Frame 0's alpha outside title-safe, when it is one value (0 or 255).
fn border_alpha(frame0: &[u8], size: (u32, u32)) -> Result<u8, String> {
    let (width, height) = size;
    let mut seen: Option<u8> = None;
    for y in 0..height {
        for x in 0..width {
            if !outside(x, y, size) {
                continue;
            }
            let alpha = frame0[(y as usize * width as usize + x as usize) * 4 + 3];
            match seen {
                None => seen = Some(alpha),
                Some(a) if a != alpha => {
                    return Err(format!(
                        "alpha {a} and {alpha} (at {x},{y}) outside title-safe"
                    ))
                }
                _ => {}
            }
        }
    }
    match seen {
        Some(a @ (0 | 255)) => Ok(a),
        other => Err(format!("alpha {other:?} outside title-safe, not 0 or 255")),
    }
}

/// Writes `frame` of `module` at `size` over opaque `#6e6e74` as an RGB PNG.
fn dump(dir: &str, module: &Module, frame: i64, size: (u32, u32)) {
    let (width, height) = size;
    let bgra = draw(module, frame, &module.defaults(), size).unwrap_or_else(|e| panic!("{e}"));
    let grey = [0x6e_u32, 0x6e, 0x74];
    let rgb: Vec<u8> = bgra
        .chunks_exact(4)
        .flat_map(|p| {
            let under = 255 - p[3] as u32;
            let over = |src: u8, bg: u32| (src as u32 + (bg * under + 127) / 255).min(255) as u8;
            [
                over(p[2], grey[0]),
                over(p[1], grey[1]),
                over(p[0], grey[2]),
            ]
        })
        .collect();
    fs::create_dir_all(dir).expect("the PNG folder");
    let path = format!("{dir}/{}-{width}x{height}-{frame}.png", module.name());
    let file = fs::File::create(&path).expect("a PNG file");
    let mut encoder = png::Encoder::new(std::io::BufWriter::new(file), width, height);
    encoder.set_color(png::ColorType::Rgb);
    encoder.set_depth(png::BitDepth::Eight);
    let mut writer = encoder.write_header().expect("a PNG header");
    writer.write_image_data(&rgb).expect("PNG data");
}

/// The frames sampled: 0, 5, 10, … and the last.
fn sampled(duration: i64) -> Vec<i64> {
    let mut frames: Vec<i64> = (0..duration).step_by(5).collect();
    if frames.last() != Some(&(duration - 1)) {
        frames.push(duration - 1);
    }
    frames
}

/// The first pixel of the last frame that is not bare: for an overlay
/// (`border` 0) one with any alpha, for a card one that differs from the
/// background, frame 0's pixel (0, 0).
fn not_bare(last: &[u8], frame0: &[u8], border: u8, width: u32) -> Option<(u32, u32)> {
    let at = |i: usize| ((i % width as usize) as u32, (i / width as usize) as u32);
    last.chunks_exact(4)
        .position(|p| {
            if border == 0 {
                p[3] != 0
            } else {
                p != &frame0[..4]
            }
        })
        .map(at)
}

/// Draws `frames` (frame 0 first) of `module` with `props` at `size` and
/// holds them to G-44 (b) and (c): frame 0 has one alpha outside title-safe
/// (0 or 255), no later frame differs from it there, and the last frame,
/// `D − 1`, when sampled, is bare (`not_bare`) — every outro fades all of
/// its content. A frame 0 that fails to draw skips the comparisons. Answers
/// each frame's svg+rasterize ms.
fn check(
    module: &Module,
    props: &Value,
    frames: &[i64],
    size: (u32, u32),
    what: &str,
    failures: &mut Vec<String>,
) -> Vec<f64> {
    let last = duration(module) - 1;
    let mut times = Vec::new();
    let mut base: Option<(Vec<u8>, u8)> = None;
    for &frame in frames {
        let started = Instant::now();
        let drawn = draw(module, frame, props, size);
        times.push(started.elapsed().as_secs_f64() * 1000.0);
        let bgra = match drawn {
            Ok(bgra) => bgra,
            Err(e) => {
                failures.push(format!("{what}: {e}"));
                continue;
            }
        };
        if frame == 0 {
            match border_alpha(&bgra, size) {
                Ok(alpha) => base = Some((bgra, alpha)),
                Err(e) => failures.push(format!("{what} {size:?} frame 0: {e}")),
            }
            continue;
        }
        let Some((first, alpha)) = &base else {
            continue;
        };
        if let Some((x, y)) = first_difference(first, &bgra, size) {
            failures.push(format!(
                "{what} {size:?} frame {frame}: pixel ({x}, {y}) outside title-safe differs from frame 0"
            ));
        }
        if frame == last {
            if let Some((x, y)) = not_bare(&bgra, first, *alpha, size.0) {
                failures.push(format!(
                    "{what} {size:?} last frame {frame}: pixel ({x}, {y}) is still drawn after the outro"
                ));
            }
        }
    }
    times
}

#[test]
fn every_template_draws_cleanly_inside_title_safe() {
    let dump_dir = std::env::var("GRAPHIC_TEMPLATE_PNGS").ok();
    let mut failures = Vec::new();
    for stem in templates() {
        let module = common::module(&stem);
        let props = module.defaults();
        let d = duration(&module);
        for size in SIZES {
            let mut times = check(&module, &props, &sampled(d), size, &stem, &mut failures);
            if size == SIZES[0] {
                times.sort_by(|a, b| a.partial_cmp(b).unwrap());
                let p95 = times[((times.len() as f64 * 0.95).ceil() as usize).max(1) - 1];
                println!("{stem}: p95 svg+rasterize {p95:.2} ms at 1920x1080");
            }
            if let Some(dir) = &dump_dir {
                for frame in [12, d / 2, d - 8] {
                    dump(dir, &module, frame, size);
                }
            }
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

/// Props at the schema's edges that the enum pass also draws: a window
/// frame filling title-safe, and one leaving its shadow a thin margin.
fn edges() -> Vec<(&'static str, Value)> {
    vec![
        ("window-frame", serde_json::json!({"scale": 1})),
        ("window-frame", serde_json::json!({"scale": 0.97})),
    ]
}

/// Every combination of a template's `enum` options over `base`, each as
/// `(what, props)`; `what` names the options chosen, and is empty for
/// `base` itself when the template has no `enum`.
fn combinations(module: &Module, base: Value) -> Vec<(String, Value)> {
    let mut out = vec![(String::new(), base)];
    for (key, entry) in module.schema().as_object().expect("a schema object") {
        if entry["type"] != "enum" {
            continue;
        }
        let options = entry["options"].as_array().expect("an enum's options");
        out = out
            .iter()
            .flat_map(|(what, props)| {
                options.iter().map(move |option| {
                    let mut props = props.clone();
                    props[key] = option.clone();
                    (
                        format!("{what} {key}={}", option.as_str().unwrap_or("?")),
                        props,
                    )
                })
            })
            .collect();
    }
    out
}

/// Every combination of a template's `enum` options, the other props at
/// their defaults, plus `edges()`: each as `(what, props)`.
fn variants(stem: &str, module: &Module) -> Vec<(String, Value)> {
    let mut out = combinations(module, module.defaults());
    for (_, overrides) in edges().into_iter().filter(|(s, _)| *s == stem) {
        let mut props = module.defaults();
        for (key, value) in overrides.as_object().unwrap() {
            props[key] = value.clone();
        }
        out.push((format!(" {overrides}"), props));
    }
    out.into_iter()
        .filter(|(what, _)| !what.is_empty())
        .map(|(what, props)| (format!("{stem}{what}"), props))
        .collect()
}

#[test]
fn every_enum_option_draws_cleanly_inside_title_safe() {
    let mut failures = Vec::new();
    let mut drawn = 0;
    for stem in templates() {
        let module = common::module(&stem);
        let d = duration(&module);
        for (what, props) in variants(&stem, &module) {
            drawn += 1;
            for size in SIZES {
                let frames = [0, 3, 6, 9, 12, d / 2, d - 1];
                check(&module, &props, &frames, size, &what, &mut failures);
            }
        }
    }
    assert!(drawn > 0, "no template has an enum");
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

#[test]
fn degenerate_props_draw_cleanly() {
    let cases = [
        ("line-chart", serde_json::json!({"values": "5"})),
        ("donut-chart", serde_json::json!({"values": "0, 0"})),
        ("gauge", serde_json::json!({"min": 0, "max": 0, "value": 0})),
    ];
    let mut failures = Vec::new();
    for (stem, overrides) in cases {
        let module = common::module(stem);
        let mut props = module.defaults();
        for (key, value) in overrides.as_object().unwrap() {
            props[key] = value.clone();
        }
        let d = duration(&module);
        for size in SIZES {
            for frame in [0, d / 2, d - 1] {
                if let Err(e) = draw(&module, frame, &props, size) {
                    failures.push(e);
                }
            }
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

/// The file names listed under `key:` in the "Copy Graphic Templates" phase.
fn listed(phase: &str, key: &str) -> Vec<String> {
    let mut names: Vec<String> = phase
        .lines()
        .skip_while(|line| line.trim() != format!("{key}:"))
        .skip(1)
        .take_while(|line| line.trim_start().starts_with("- "))
        .map(|line| line.rsplit('/').next().unwrap().trim().to_string())
        .collect();
    names.sort();
    names
}

#[test]
fn project_yml_lists_every_template() {
    let yml = fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/../project.yml"))
        .expect("project.yml");
    let start = yml
        .find("- name: Copy Graphic Templates")
        .expect("the Copy Graphic Templates phase");
    let rest = &yml[start + 1..];
    let phase = &rest[..rest.find("- name:").unwrap_or(rest.len())];
    let mut files: Vec<String> = fs::read_dir(GRAPHICS)
        .expect("tests/graphics")
        .map(|entry| entry.expect("a directory entry").path())
        .filter(|path| path.extension().is_some_and(|ext| ext == "js"))
        .map(|path| path.file_name().unwrap().to_string_lossy().into_owned())
        .collect();
    files.sort();
    assert_eq!(listed(phase, "inputFiles"), files, "inputFiles");
    assert_eq!(listed(phase, "outputFiles"), files, "outputFiles");
}
