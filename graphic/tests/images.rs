//! `<image>` answered from the asset map only: each raster format, SVG and
//! SVGZ assets, and the warnings for a miss, a data: URL, a non-image and a
//! root whose size is not the graphic's.

mod common;

use std::collections::BTreeMap;
use std::io::Write;

use common::{library, library_with, messages, pixel, render, svg};
use flate2::write::GzEncoder;
use flate2::Compression;

fn image(href: &str) -> String {
    svg(
        12,
        12,
        &format!("<image x=\"2\" y=\"2\" width=\"8\" height=\"8\" href=\"{href}\"/>"),
    )
}

/// The README's colours, as BGRA, with the per-channel tolerance.
const CASES: [(&str, [u8; 4], u8); 4] = [
    ("red.png", [0x00, 0x00, 0xff, 0xff], 0),
    ("steel.jpg", [0xc0, 0x80, 0x40, 0xff], 4),
    ("blue-then-yellow.gif", [0xff, 0x00, 0x00, 0xff], 0),
    ("magenta.webp", [0xff, 0x00, 0xff, 0xff], 0),
];

#[test]
fn each_raster_format_draws_its_colour() {
    let lib = library();
    for (name, want, tolerance) in CASES {
        let (out, warnings) = render(&lib, &image(name), 12, 12);
        assert!(warnings.is_empty(), "{name}: {warnings:?}");
        let centre = pixel(&out, 48, 6, 6);
        println!("{name}: centre {centre:?}");
        for c in 0..4 {
            assert!(
                centre[c].abs_diff(want[c]) <= tolerance,
                "{name}: centre {centre:?}, want {want:?}"
            );
        }
        assert_eq!(pixel(&out, 48, 0, 0), [0, 0, 0, 0], "{name}: corner");
    }
}

#[test]
fn svg_and_svgz_assets_draw_the_same_bytes() {
    let green = svg(8, 8, "<rect width=\"8\" height=\"8\" fill=\"#00ff00\"/>");
    let mut gz = GzEncoder::new(Vec::new(), Compression::default());
    gz.write_all(green.as_bytes()).unwrap();
    let extra = BTreeMap::from([
        ("green.svg".to_string(), green.clone().into_bytes()),
        ("green.svgz".to_string(), gz.finish().unwrap()),
    ]);
    let lib = library_with(extra);
    let (plain, w1) = render(&lib, &image("green.svg"), 12, 12);
    let (zipped, w2) = render(&lib, &image("green.svgz"), 12, 12);
    assert!(w1.is_empty() && w2.is_empty(), "{w1:?} {w2:?}");
    assert_eq!(plain, zipped);
    assert_eq!(pixel(&plain, 48, 6, 6), [0x00, 0xff, 0x00, 0xff]);
    assert_eq!(pixel(&plain, 48, 0, 0), [0, 0, 0, 0]);
}

#[test]
fn an_unknown_href_names_every_asset() {
    let lib = library();
    let (out, warnings) = render(&lib, &image("missing.png"), 12, 12);
    assert_eq!(
        messages(&warnings),
        vec![
            "<image> href \"missing.png\" is not an asset; the assets are: \
             blue-then-yellow.gif, magenta.webp, red.png, steel.jpg"
                .to_string()
        ]
    );
    assert!(out.iter().all(|b| *b == 0));
}

#[test]
fn an_unknown_href_with_no_assets_says_so() {
    let lib = graphic::Library::new(vec![], BTreeMap::new());
    let (_, warnings) = render(&lib, &image("logo.png"), 12, 12);
    assert_eq!(
        messages(&warnings),
        vec!["<image> href \"logo.png\" is not an asset; the assets are: (no assets)".to_string()]
    );
}

#[test]
fn a_data_url_is_refused_with_the_way_out() {
    let lib = library();
    let (out, warnings) = render(&lib, &image("data:image/png;base64,AAAA"), 12, 12);
    assert_eq!(
        messages(&warnings),
        vec![
            "<image> data: URLs are not supported; put the file in graphics/assets/ and use asset(name)"
                .to_string()
        ]
    );
    assert!(out.iter().all(|b| *b == 0));
}

#[test]
fn an_asset_that_is_not_an_image_is_named() {
    let extra = BTreeMap::from([("notes.txt".to_string(), b"hello".to_vec())]);
    let lib = library_with(extra);
    let (_, warnings) = render(&lib, &image("notes.txt"), 12, 12);
    assert_eq!(
        messages(&warnings),
        vec!["asset \"notes.txt\" is not a PNG, JPEG, GIF, WebP or SVG(Z) image".to_string()]
    );
}

#[test]
fn a_size_mismatch_warns_and_still_draws() {
    let lib = library();
    let text = svg(
        100,
        100,
        "<rect width=\"100\" height=\"100\" fill=\"#ff0000\"/>",
    );
    let (out, warnings) = render(&lib, &text, 120, 120);
    assert_eq!(
        messages(&warnings),
        vec!["the SVG is 100×100 but the graphic is 120×120".to_string()]
    );
    assert_eq!(pixel(&out, 480, 50, 50), [0x00, 0x00, 0xff, 0xff]);
    assert_eq!(pixel(&out, 480, 110, 110), [0, 0, 0, 0]);
}
