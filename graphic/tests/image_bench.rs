//! #127 G6 phase 5's engine bench (`tools/proof/image_cache_bench.py` runs
//! it): the section scene's SVGs drawn by the original assets with the
//! decoded-image cache at a limit of 0 (ORIG) and by the same library at a
//! limit of 1 GiB after one untimed warm frame (CACHED, spec §11 G-39),
//! rounds alternating, every frame's bytes compared. Phase 5's spike ran a
//! STORED arm in CACHED's place — the library with every PNG asset swapped
//! for a stored copy the test built — and its figures are G-39 (g)'s.
//! Ignored: it reads `GRAPHIC_IMAGE_BENCH` (the dumped folder) and
//! `GRAPHIC_IMAGE_BENCH_ROUNDS` (5 by default).

mod common;

use std::collections::BTreeMap;
use std::fs;
use std::path::Path;
use std::time::Instant;

use graphic::{image_cache_bytes, rasterize, set_image_cache_limit, Library};
use resvg::tiny_skia::Pixmap;

const PNG_MAGIC: [u8; 4] = [0x89, 0x50, 0x4E, 0x47];
const JPEG_MAGIC: [u8; 3] = [0xFF, 0xD8, 0xFF];
const GIB: usize = 1 << 30;

/// `files` in `dir` (a folder that may be absent), in name order.
fn files_in(dir: &Path) -> Vec<(String, Vec<u8>)> {
    let Ok(entries) = fs::read_dir(dir) else {
        return Vec::new();
    };
    let mut paths: Vec<_> = entries
        .map(|entry| entry.expect("a directory entry").path())
        .filter(|path| path.is_file())
        .collect();
    paths.sort();
    paths
        .iter()
        .map(|path| {
            let name = path.file_name().unwrap().to_string_lossy().to_string();
            (name, fs::read(path).expect("a file"))
        })
        .collect()
}

fn median(values: &mut [f64]) -> f64 {
    values.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let n = values.len();
    if n % 2 == 1 {
        values[n / 2]
    } else {
        (values[n / 2 - 1] + values[n / 2]) / 2.0
    }
}

/// One pass over every SVG: (the summed rasterize time in ms, each
/// frame's output digest). Only the rasterize call is timed.
fn round(lib: &Library, svgs: &[String], width: u32, height: u32) -> (f64, Vec<String>) {
    let stride = width as usize * 4;
    let mut out = vec![0u8; stride * height as usize];
    let mut total = 0.0;
    let mut digests = Vec::with_capacity(svgs.len());
    for svg in svgs {
        let started = Instant::now();
        rasterize(lib, svg, width, height, &mut out, stride)
            .unwrap_or_else(|e| panic!("rasterize refused: {}", e.message));
        total += started.elapsed().as_secs_f64() * 1000.0;
        digests.push(common::sha256(&out));
    }
    (total, digests)
}

#[test]
#[ignore]
fn section_scene_orig_against_cached() {
    let dir = std::env::var("GRAPHIC_IMAGE_BENCH").expect("GRAPHIC_IMAGE_BENCH names the folder");
    let dir = Path::new(&dir);
    let rounds: usize = std::env::var("GRAPHIC_IMAGE_BENCH_ROUNDS")
        .ok()
        .and_then(|text| text.parse().ok())
        .unwrap_or(5);
    let frames: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(dir.join("frames.json")).unwrap()).unwrap();
    let width = frames["width"].as_u64().unwrap() as u32;
    let height = frames["height"].as_u64().unwrap() as u32;
    let svgs: Vec<String> = frames["files"]
        .as_array()
        .unwrap()
        .iter()
        .map(|file| fs::read_to_string(dir.join(file.as_str().unwrap())).unwrap())
        .collect();

    let mut fonts = common::fonts();
    fonts.extend(
        files_in(&dir.join("fonts"))
            .into_iter()
            .map(|(_, data)| data),
    );
    let assets: BTreeMap<String, Vec<u8>> = files_in(&dir.join("assets")).into_iter().collect();
    let mut pngs = Vec::new();
    for (name, data) in &assets {
        if data.starts_with(&PNG_MAGIC) {
            println!("asset {name}: PNG, {} bytes", data.len());
            pngs.push(name.clone());
        } else if data.starts_with(&JPEG_MAGIC) {
            println!(
                "asset {name}: JPEG, {} bytes (not in the decode share)",
                data.len()
            );
        }
    }
    let lib = Library::new(fonts, assets.clone());

    // Each PNG href's decode time, the median of 5.
    let mut decode_ms = BTreeMap::new();
    for name in &pngs {
        let mut times: Vec<f64> = (0..5)
            .map(|_| {
                let started = Instant::now();
                Pixmap::decode_png(&assets[name]).unwrap();
                started.elapsed().as_secs_f64() * 1000.0
            })
            .collect();
        decode_ms.insert(name.clone(), median(&mut times));
    }
    let decode_total: f64 = svgs
        .iter()
        .map(|svg| {
            decode_ms
                .iter()
                .map(|(name, ms)| svg.matches(&format!("href=\"{name}\"")).count() as f64 * ms)
                .sum::<f64>()
        })
        .sum();

    let stride = width as usize * 4;
    let mut warm = vec![0u8; stride * height as usize];
    let mut orig_ms = Vec::new();
    let mut cached_ms = Vec::new();
    let mut reference: Option<Vec<String>> = None;
    for index in 0..rounds {
        for arm in ["ORIG", "CACHED"] {
            if arm == "ORIG" {
                set_image_cache_limit(0);
            } else {
                set_image_cache_limit(GIB);
                rasterize(&lib, &svgs[0], width, height, &mut warm, stride)
                    .unwrap_or_else(|e| panic!("rasterize refused: {}", e.message));
            }
            let (total, digests) = round(&lib, &svgs, width, height);
            let held = image_cache_bytes();
            println!("round {index} {arm}: {total:.1} ms ({held} bytes cached after)");
            if arm == "ORIG" {
                orig_ms.push(total);
            } else {
                cached_ms.push(total);
            }
            match &reference {
                None => reference = Some(digests),
                Some(first) => {
                    for (frame, (a, b)) in first.iter().zip(&digests).enumerate() {
                        assert_eq!(a, b, "frame {frame} differs in {arm}, round {index}");
                    }
                }
            }
        }
    }
    set_image_cache_limit(0);
    let spread = (orig_ms.iter().cloned().fold(f64::MIN, f64::max)
        - orig_ms.iter().cloned().fold(f64::MAX, f64::min))
        / median(&mut orig_ms.clone());
    let orig_median = median(&mut orig_ms);
    let cached_median = median(&mut cached_ms);
    println!("{} frames of {width}×{height}, {rounds} rounds", svgs.len());
    println!("ORIG median {orig_median:.1} ms, CACHED median {cached_median:.1} ms");
    println!("saving = {:.4}", 1.0 - cached_median / orig_median);
    println!("spread = {spread:.4}");
    println!(
        "decode share = {:.4} ({decode_total:.1} ms of PNG decodes)",
        decode_total / orig_median
    );
    println!("every frame identical across the arms");
}
