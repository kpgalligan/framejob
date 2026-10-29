//! `Library::usage()` (spec §11 G-46 (b)): the font blobs a parse or a
//! measure selected, directly or as a fallback, and the image assets it
//! resolved — cumulative per library, by the blob's index in `new()`.

mod common;

use std::collections::BTreeMap;
use std::fs;

use common::{assets, fonts, render, svg, FONTS};
use graphic::{measure_text, FontStyle, Library, TextFont, Usage};

/// The index of the bundled font `file` in `common::fonts()`'s order.
fn index_of(file: &str) -> usize {
    let mut names: Vec<String> = fs::read_dir(FONTS)
        .expect("the bundled fonts directory")
        .map(|entry| entry.expect("an entry").file_name().into_string().unwrap())
        .filter(|name| name.ends_with(".ttf"))
        .collect();
    names.sort();
    names
        .iter()
        .position(|name| name == file)
        .unwrap_or_else(|| panic!("{file} is not a bundled font"))
}

fn font_bytes(file: &str) -> Vec<u8> {
    fs::read(format!("{FONTS}/{file}")).expect("a bundled font")
}

fn text(family: &str, body: &str) -> String {
    svg(
        200,
        60,
        &format!("<text x=\"4\" y=\"44\" font-family=\"{family}\" font-size=\"40\">{body}</text>"),
    )
}

fn image(href: &str) -> String {
    svg(
        12,
        12,
        &format!("<image x=\"2\" y=\"2\" width=\"8\" height=\"8\" href=\"{href}\"/>"),
    )
}

fn inked(buf: &[u8]) -> bool {
    buf.chunks(4).any(|px| px[3] != 0)
}

fn usage(fonts: Vec<usize>, assets: &[&str]) -> Usage {
    Usage {
        fonts,
        assets: assets.iter().map(|name| name.to_string()).collect(),
    }
}

#[test]
fn a_drawn_family_records_its_blob() {
    let lib = Library::new(fonts(), BTreeMap::new());
    render(&lib, &text("Anton", "Hello"), 200, 60);
    assert_eq!(lib.usage(), usage(vec![index_of("Anton-Regular.ttf")], &[]));

    let lib = Library::new(fonts(), BTreeMap::new());
    render(&lib, &text("serif", "Hello"), 200, 60);
    assert_eq!(lib.usage(), usage(vec![index_of("SourceSerif4.ttf")], &[]));

    let lib = Library::new(fonts(), BTreeMap::new());
    let (_, warnings) = render(&lib, &text("No Such Family", "Hello"), 200, 60);
    assert!(!warnings.is_empty(), "a missing family is warned");
    assert_eq!(lib.usage(), Usage::default());
}

#[test]
fn a_fallback_records_both_faces() {
    // Greek alpha: Source Sans 3 has it, Anton does not. Anton alone draws
    // only its missing-glyph box, the same box it draws for Cyrillic Zhe.
    let alpha = text("Anton", "\u{3b1}");
    let alone = Library::new(vec![font_bytes("Anton-Regular.ttf")], BTreeMap::new());
    let (boxed, _) = render(&alone, &alpha, 200, 60);
    let (zhe, _) = render(&alone, &text("Anton", "\u{416}"), 200, 60);
    assert!(
        inked(&boxed) && boxed == zhe,
        "Anton alone draws the missing-glyph box"
    );
    assert_eq!(alone.usage(), usage(vec![0], &[]));

    let pair = Library::new(
        vec![
            font_bytes("Anton-Regular.ttf"),
            font_bytes("SourceSans3.ttf"),
        ],
        BTreeMap::new(),
    );
    let (out, _) = render(&pair, &alpha, 200, 60);
    assert!(
        inked(&out) && out != boxed,
        "Source Sans 3 draws the alpha as a fallback"
    );
    assert_eq!(pair.usage(), usage(vec![0, 1], &[]));
}

#[test]
fn measure_alone_records_its_face() {
    let lib = Library::new(fonts(), BTreeMap::new());
    let font = TextFont {
        family: "Anton".to_string(),
        size: 40.0,
        weight: 400,
        style: FontStyle::Normal,
        letter_spacing: 0.0,
        preserve_space: false,
    };
    measure_text(&lib, "Hello", &font).expect("a measure");
    assert_eq!(lib.usage(), usage(vec![index_of("Anton-Regular.ttf")], &[]));
}

#[test]
fn only_a_drawn_image_asset_is_recorded() {
    let mut all = assets();
    all.insert("notes.txt".to_string(), b"not an image".to_vec());
    let lib = Library::new(fonts(), all);
    render(&lib, &image("red.png"), 12, 12);
    let (_, warnings) = render(&lib, &image("notes.txt"), 12, 12);
    assert!(!warnings.is_empty(), "a non-image asset is warned");
    let (_, warnings) = render(&lib, &image("missing.png"), 12, 12);
    assert!(!warnings.is_empty(), "a missing href is warned");
    assert_eq!(lib.usage(), usage(vec![], &["red.png"]));
}

#[test]
fn a_nested_svg_assets_text_records_its_face() {
    let label = svg(
        8,
        8,
        "<text x=\"0\" y=\"7\" font-family=\"Anton\" font-size=\"8\">A</text>",
    );
    let mut all = BTreeMap::new();
    all.insert("label.svg".to_string(), label.into_bytes());
    let lib = Library::new(fonts(), all);
    render(&lib, &image("label.svg"), 12, 12);
    assert_eq!(
        lib.usage(),
        usage(vec![index_of("Anton-Regular.ttf")], &["label.svg"])
    );
}

#[test]
fn a_faceless_blob_counts_in_the_indexes() {
    let lib = Library::new(
        vec![b"not a font".to_vec(), font_bytes("Anton-Regular.ttf")],
        BTreeMap::new(),
    );
    assert_eq!(lib.warnings().len(), 1);
    render(&lib, &text("Anton", "Hello"), 200, 60);
    assert_eq!(lib.usage(), usage(vec![1], &[]));
}

#[test]
fn usage_accumulates_and_is_per_library() {
    let lib = Library::new(fonts(), assets());
    let other = Library::new(fonts(), assets());
    render(&lib, &text("Anton", "Hello"), 200, 60);
    render(&lib, &image("steel.jpg"), 12, 12);
    render(&lib, &text("serif", "Hello"), 200, 60);
    render(&lib, &image("red.png"), 12, 12);
    let mut want = vec![index_of("Anton-Regular.ttf"), index_of("SourceSerif4.ttf")];
    want.sort();
    assert_eq!(lib.usage(), usage(want, &["red.png", "steel.jpg"]));
    assert_eq!(other.usage(), Usage::default());
}
