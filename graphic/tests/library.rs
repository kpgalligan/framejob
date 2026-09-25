//! The Library: the bundled families and faces, the content version, the
//! warning for a font blob that loads nothing, and an empty library.

mod common;

use std::collections::BTreeMap;

use common::{assets, fonts, library, pixel, render, svg};
use graphic::{Diagnostic, Library};

#[test]
fn the_bundled_families_sorted() {
    let lib = library();
    assert_eq!(
        lib.families(),
        [
            "Anton",
            "Bebas Neue",
            "Darker Grotesque",
            "IBM Plex Mono",
            "Montserrat",
            "Source Sans 3"
        ]
    );
    assert!(lib.warnings().is_empty(), "{:?}", lib.warnings());
    assert_eq!(
        lib.asset_names(),
        [
            "blue-then-yellow.gif",
            "magenta.webp",
            "red.png",
            "steel.jpg"
        ]
    );
    assert!(lib
        .asset("red.png")
        .is_some_and(|d| d.starts_with(b"\x89PNG")));
    assert!(lib.asset("nope.png").is_none());
}

#[test]
fn the_variable_faces_load_once() {
    let faces = library().faces();
    let sans: Vec<_> = faces
        .iter()
        .filter(|f| f.family == "Source Sans 3")
        .collect();
    assert_eq!(sans.len(), 1, "{sans:?}");
    assert_eq!(sans[0].post_script_name, "SourceSans3-Roman");
    assert_eq!(sans[0].weight, 200);
    let darker: Vec<_> = faces
        .iter()
        .filter(|f| f.family == "Darker Grotesque")
        .collect();
    assert_eq!(darker.len(), 1, "{darker:?}");
    assert_eq!(darker[0].weight, 300);
}

#[test]
fn version_is_a_content_hash() {
    let a = library();
    let b = library();
    assert_eq!(a.version().len(), 64);
    assert!(
        a.version()
            .chars()
            .all(|c| matches!(c, '0'..='9' | 'a'..='f')),
        "{}",
        a.version()
    );
    assert_eq!(a.version(), b.version());
    let mut changed = assets();
    changed.get_mut("red.png").unwrap()[40] ^= 1;
    let c = Library::new(fonts(), changed);
    assert_ne!(a.version(), c.version());
}

#[test]
fn version_differs_at_entry_boundaries() {
    let one = Library::new(vec![], BTreeMap::from([("ab".to_string(), b"c".to_vec())]));
    let two = Library::new(vec![], BTreeMap::from([("a".to_string(), b"bc".to_vec())]));
    assert_ne!(one.version(), two.version(), "assets");
    let one = Library::new(vec![b"ab".to_vec(), b"c".to_vec()], BTreeMap::new());
    let two = Library::new(vec![b"a".to_vec(), b"bc".to_vec()], BTreeMap::new());
    assert_ne!(one.version(), two.version(), "fonts");
}

#[test]
fn a_blob_with_no_face_is_named_by_index() {
    let mut blobs = fonts();
    let index = blobs.len();
    blobs.push(vec![0u8; 16]);
    let lib = Library::new(blobs, BTreeMap::new());
    let messages: Vec<&str> = lib.warnings().iter().map(|w| w.message.as_str()).collect();
    assert_eq!(messages, [format!("font {index} loaded no face")]);
}

#[test]
fn an_empty_library_still_draws_shapes() {
    let lib = Library::new(vec![], BTreeMap::new());
    assert!(lib.families().is_empty());
    assert!(lib.asset_names().is_empty());
    let (out, warnings) = render(
        &lib,
        &svg(4, 4, "<rect width=\"4\" height=\"4\" fill=\"#fff\"/>"),
        4,
        4,
    );
    assert!(warnings.is_empty(), "{warnings:?}");
    assert_eq!(pixel(&out, 16, 1, 1), [0xff, 0xff, 0xff, 0xff]);
}

#[test]
fn a_diagnostic_serialises_in_order() {
    let mut d = Diagnostic::warning("careful");
    d.frame = Some(12);
    let json = d.to_json();
    let keys: Vec<&str> = json
        .as_object()
        .unwrap()
        .keys()
        .map(String::as_str)
        .collect();
    assert_eq!(keys, ["level", "message", "line", "column", "frame"]);
    assert_eq!(json["level"], "warning");
    assert!(json["line"].is_null());
    assert_eq!(json["frame"], 12);
}
