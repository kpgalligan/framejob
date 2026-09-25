//! The one non-oracle (road map 10 §5l): the SHA-256 of the BGRA of frames
//! 0, 30 and 90 of each fixture, pinned in `tests/pins.json`. A tripwire
//! for a resvg or QuickJS upgrade, not a correctness claim. On a mismatch
//! the frames are written to `target/pins/` to look at;
//! `GRAPHIC_REPIN=1` rewrites the file.

mod common;

use std::fs;

use graphic::rasterize;
use serde_json::{Map, Value};

use common::{shared, FIXTURES};

const PINS: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/pins.json");
const DUMP: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/target/pins");
const FRAMES: [i64; 3] = [0, 30, 90];

fn bgra(name: &str, frame: i64) -> Vec<u8> {
    let module = common::module(name);
    let (svg, _) =
        common::frame(&module, frame).unwrap_or_else(|d| panic!("{name} {frame}: {}", d.message));
    let mut out = vec![0u8; 1920 * 1080 * 4];
    rasterize(&shared(), &svg, 1920, 1080, &mut out, 1920 * 4)
        .unwrap_or_else(|d| panic!("{name} {frame}: {}", d.message));
    out
}

/// The frame as an RGBA PNG (still premultiplied: for a person to look at).
fn dump(name: &str, frame: i64, bgra: &[u8]) {
    fs::create_dir_all(DUMP).expect("target/pins");
    let rgba: Vec<u8> = bgra
        .chunks_exact(4)
        .flat_map(|p| [p[2], p[1], p[0], p[3]])
        .collect();
    let file = fs::File::create(format!("{DUMP}/{name}-{frame}.png")).expect("a PNG file");
    let mut encoder = png::Encoder::new(std::io::BufWriter::new(file), 1920, 1080);
    encoder.set_color(png::ColorType::Rgba);
    encoder.set_depth(png::BitDepth::Eight);
    let mut writer = encoder.write_header().expect("a PNG header");
    writer.write_image_data(&rgba).expect("PNG data");
}

#[test]
fn the_fixtures_frames_match_their_pins() {
    let mut current = Map::new();
    for name in FIXTURES {
        let mut frames = Map::new();
        for frame in FRAMES {
            let bytes = bgra(name, frame);
            frames.insert(frame.to_string(), Value::from(common::sha256(&bytes)));
            if std::env::var("GRAPHIC_REPIN").is_err() {
                let pins: Value =
                    serde_json::from_str(&fs::read_to_string(PINS).expect("tests/pins.json"))
                        .expect("pins.json is JSON");
                if pins[name][frame.to_string()] != frames[&frame.to_string()] {
                    for f in FRAMES {
                        dump(name, f, &bgra(name, f));
                    }
                    panic!(
                        "{name} frame {frame}: the rasterizer's output changed — if this is a resvg upgrade, re-pin after looking at the PNGs in target/pins/"
                    );
                }
            }
        }
        current.insert(name.to_string(), Value::Object(frames));
    }
    if std::env::var("GRAPHIC_REPIN").is_ok() {
        let text = serde_json::to_string_pretty(&Value::Object(current)).unwrap() + "\n";
        fs::write(PINS, text).expect("tests/pins.json written");
    }
}
