//! The decoded-image cache (spec §11 G-39), rows I1–I6. The cache is one
//! per process, so every row holds `SERIAL`, starts at a limit of 0 (which
//! empties it), sets its own limit and makes its own draws: no row reads
//! state another row left. Every pixel claim compares a draw at a positive
//! limit with the same draw at 0, which is the original route.

mod common;

use std::collections::BTreeMap;
use std::sync::{Mutex, MutexGuard};

use common::{pixel, render, svg};
use graphic::{image_cache_builds, image_cache_bytes, set_image_cache_limit, Library};

const MIB: usize = 1 << 20;
const RAMP: (u32, u32) = (320, 64);

static SERIAL: Mutex<()> = Mutex::new(());

/// The row's hold on the process-wide cache, starting it empty at limit 0.
fn serial() -> MutexGuard<'static, ()> {
    let guard = SERIAL
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    set_image_cache_limit(0);
    guard
}

/// A PNG of `colour` at 8 bits, default compression and filtering.
fn png_of(width: u32, height: u32, colour: png::ColorType, data: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    let mut encoder = png::Encoder::new(&mut out, width, height);
    encoder.set_color(colour);
    encoder.set_depth(png::BitDepth::Eight);
    let mut writer = encoder.write_header().expect("a header");
    writer.write_image_data(data).expect("the rows");
    writer.finish().expect("the end");
    out
}

/// An RGBA alpha ramp: alpha rises left to right, colour varies with both.
fn ramp(width: u32, height: u32, seed: u8) -> Vec<u8> {
    let mut data = Vec::new();
    for y in 0..height {
        for x in 0..width {
            data.extend([
                (x * 255 / width) as u8 ^ seed,
                (y * 255 / height) as u8,
                200u8.wrapping_add(seed),
                (x * 255 / (width - 1)) as u8,
            ]);
        }
    }
    png_of(width, height, png::ColorType::Rgba, &data)
}

fn gray_alpha() -> Vec<u8> {
    let (width, height) = (48u32, 40u32);
    let data: Vec<u8> = (0..width * height)
        .flat_map(|i| [(i % 251) as u8, (i * 7 % 256) as u8])
        .collect();
    png_of(width, height, png::ColorType::GrayscaleAlpha, &data)
}

fn solid(rgba: [u8; 4]) -> Vec<u8> {
    let data: Vec<u8> = (0..16).flat_map(|_| rgba).collect();
    png_of(4, 4, png::ColorType::Rgba, &data)
}

fn library(assets: BTreeMap<String, Vec<u8>>) -> Library {
    Library::new(Vec::new(), assets)
}

/// Draws `body` at 400×300 at `limit`, then at 0; (the first, the second).
fn at_limit_and_zero(lib: &Library, body: &str, limit: usize) -> (Vec<u8>, Vec<u8>) {
    let scene = svg(400, 300, body);
    set_image_cache_limit(limit);
    let cached = render(lib, &scene, 400, 300).0;
    set_image_cache_limit(0);
    let original = render(lib, &scene, 400, 300).0;
    (cached, original)
}

fn image(href: &str, attributes: &str) -> String {
    format!("<image href=\"{href}\" {attributes}/>")
}

#[test]
fn i1_cached_copies_draw_the_original_pixels() {
    let _hold = serial();
    let mut assets = common::assets();
    assets.insert("ramp.png".into(), ramp(RAMP.0, RAMP.1, 0));
    assets.insert("ga.png".into(), gray_alpha());
    let lib = library(assets);
    let body = [
        image("ramp.png", "x=\"5\" y=\"5\" width=\"390\" height=\"90\" preserveAspectRatio=\"none\""),
        image("ga.png", "x=\"40\" y=\"100\" width=\"130\" height=\"110\" transform=\"rotate(17 100 150)\""),
        image("red.png", "x=\"200\" y=\"120\" width=\"70\" height=\"50\" image-rendering=\"optimizeSpeed\""),
        image("steel.jpg", "x=\"280\" y=\"180\" width=\"90\" height=\"90\" transform=\"rotate(-23 320 220)\""),
        image("ramp.png", "x=\"0\" y=\"210\" width=\"200\" height=\"80\" image-rendering=\"optimizeSpeed\" transform=\"scale(1.3 0.9)\""),
    ]
    .concat();
    let scene = svg(400, 300, &body);
    set_image_cache_limit(64 * MIB);
    let first = render(&lib, &scene, 400, 300).0;
    let second = render(&lib, &scene, 400, 300).0;
    let held = image_cache_bytes();
    set_image_cache_limit(0);
    let original = render(&lib, &scene, 400, 300).0;
    assert!(
        first == original && second == original,
        "a cached draw differs from the original route"
    );
    let floor = (RAMP.0 * RAMP.1 * 4) as usize;
    assert!(
        held >= floor,
        "the cache holds {held} bytes, under the ramp's {floor}"
    );
}

#[test]
fn i2_the_same_name_with_other_bytes_draws_its_own_pixel() {
    let _hold = serial();
    set_image_cache_limit(64 * MIB);
    let body = image("swatch.png", "x=\"0\" y=\"0\" width=\"8\" height=\"8\"");
    let scene = svg(8, 8, &body);
    let blue = library(BTreeMap::from([(
        "swatch.png".into(),
        solid([0, 0, 255, 255]),
    )]));
    let green = library(BTreeMap::from([(
        "swatch.png".into(),
        solid([0, 255, 0, 255]),
    )]));
    let (first, _) = render(&blue, &scene, 8, 8);
    let (second, _) = render(&green, &scene, 8, 8);
    assert_eq!(
        pixel(&first, 32, 4, 4),
        [255, 0, 0, 255],
        "the blue swatch (BGRA)"
    );
    assert_eq!(
        pixel(&second, 32, 4, 4),
        [0, 255, 0, 255],
        "the green swatch (BGRA)"
    );
}

#[test]
fn i3_a_limit_of_zero_empties_the_cache() {
    let _hold = serial();
    let lib = library(BTreeMap::from([(
        "ramp.png".into(),
        ramp(RAMP.0, RAMP.1, 0),
    )]));
    set_image_cache_limit(64 * MIB);
    render(
        &lib,
        &svg(100, 100, &image("ramp.png", "width=\"100\" height=\"100\"")),
        100,
        100,
    );
    assert!(image_cache_bytes() > 0, "the ramp's copy is held");
    assert_eq!(set_image_cache_limit(0), 0, "a limit of 0 left bytes held");
    assert_eq!(image_cache_bytes(), 0);
}

#[test]
fn i4_a_copy_over_the_limit_is_kept_nowhere_and_not_rebuilt() {
    let _hold = serial();
    let lib = library(BTreeMap::from([(
        "ramp.png".into(),
        ramp(RAMP.0, RAMP.1, 0),
    )]));
    let body = image("ramp.png", "x=\"10\" y=\"10\" width=\"380\" height=\"280\"");
    let limit = 1000;
    let (cached, original) = at_limit_and_zero(&lib, &body, limit);
    assert_eq!(
        cached, original,
        "the over-limit draw differs from the original route"
    );
    set_image_cache_limit(limit);
    render(&lib, &svg(400, 300, &body), 400, 300);
    assert_eq!(image_cache_bytes(), 0, "a copy over the limit was kept");
    let before = image_cache_builds();
    render(&lib, &svg(400, 300, &body), 400, 300);
    assert_eq!(image_cache_builds(), before, "the copy was rebuilt");
}

#[test]
fn i5_the_least_recently_used_copy_gives_way_and_is_not_rebuilt() {
    let _hold = serial();
    let lib = library(BTreeMap::from([
        ("a.png".into(), ramp(320, 64, 0)),
        ("b.png".into(), ramp(300, 70, 90)),
    ]));
    let draw = |name: &str| {
        let scene = svg(100, 100, &image(name, "width=\"100\" height=\"100\""));
        render(&lib, &scene, 100, 100);
    };
    let limit = 120_000;
    set_image_cache_limit(limit);
    draw("b.png");
    let b_bytes = image_cache_bytes();
    set_image_cache_limit(0);
    set_image_cache_limit(limit);
    draw("a.png");
    let a_bytes = image_cache_bytes();
    assert!(a_bytes > 0 && b_bytes > 0 && a_bytes != b_bytes && a_bytes + b_bytes > limit);
    draw("b.png");
    assert_eq!(image_cache_bytes(), b_bytes, "only B's copy is held");
    let before = image_cache_builds();
    draw("a.png");
    assert_eq!(image_cache_builds(), before, "A's copy was rebuilt");
    assert_eq!(image_cache_bytes(), b_bytes, "B's copy is still held");
}

#[test]
fn i6_gif_and_webp_never_reach_the_cache() {
    let _hold = serial();
    let lib = library(common::assets());
    let body = [
        image(
            "blue-then-yellow.gif",
            "x=\"10\" y=\"10\" width=\"150\" height=\"120\"",
        ),
        image(
            "magenta.webp",
            "x=\"200\" y=\"100\" width=\"150\" height=\"150\" transform=\"rotate(9 275 175)\"",
        ),
    ]
    .concat();
    let (cached, original) = at_limit_and_zero(&lib, &body, 64 * MIB);
    assert_eq!(cached, original);
    set_image_cache_limit(64 * MIB);
    render(&lib, &svg(400, 300, &body), 400, 300);
    assert_eq!(image_cache_bytes(), 0, "a GIF or WebP asset was cached");
}
