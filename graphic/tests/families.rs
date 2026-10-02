//! The font-family warnings resvg never reports: a family no face answers
//! (in an attribute, a sheet, or a nested SVG asset), a value that did not
//! parse (from an attribute, a `style` attribute or a sheet, or the family
//! of a `font` shorthand in either of the last two), and a text with no
//! family at all.

mod common;

use std::collections::BTreeMap;

use common::{library, library_with, messages, render, svg};
use graphic::Library;

const DIGIT: &str = "could not be parsed — a family name with a word that starts with a digit \
                     must be quoted: font-family=\"'Source Sans 3'\"";

fn text(attributes: &str) -> String {
    svg(
        320,
        80,
        &format!(
            "<text x=\"10\" y=\"56\" font-size=\"40\" fill=\"#fff\"{attributes}>Hamburg</text>"
        ),
    )
}

fn draws(out: &[u8]) -> bool {
    out.iter().any(|b| *b != 0)
}

fn names_every_family(lib: &Library, message: &str) {
    for family in lib.families() {
        assert!(
            message.contains(family.as_str()),
            "{message} lacks {family}"
        );
    }
}

#[test]
fn a_missing_family_is_named_with_the_set_and_draws_nothing() {
    let lib = library();
    let (out, warnings) = render(&lib, &text(" font-family=\"Nope\""), 320, 80);
    assert_eq!(warnings.len(), 1, "{warnings:?}");
    let message = &warnings[0].message;
    assert!(message.starts_with("font-family \"Nope\" is not in the font set; the set has: "));
    names_every_family(&lib, message);
    assert!(!draws(&out), "resvg drew a missing family");
}

#[test]
fn an_unquoted_digit_family_says_to_quote_it() {
    let lib = library();
    let (out, warnings) = render(&lib, &text(" font-family=\"Source Sans 3\""), 320, 80);
    assert_eq!(warnings.len(), 1, "{warnings:?}");
    let message = &warnings[0].message;
    assert!(
        message.starts_with(&format!(
            "font-family=\"Source Sans 3\" {DIGIT}; the set has: "
        )),
        "{message}"
    );
    names_every_family(&lib, message);
    assert!(!draws(&out));
}

#[test]
fn a_quoted_digit_family_draws_without_a_warning() {
    let lib = library();
    let (out, warnings) = render(&lib, &text(" font-family=\"'Source Sans 3'\""), 320, 80);
    assert!(warnings.is_empty(), "{warnings:?}");
    assert!(draws(&out));
}

#[test]
fn a_list_with_one_present_family_draws_without_a_warning() {
    let lib = library();
    let (out, warnings) = render(&lib, &text(" font-family=\"Nope, Montserrat\""), 320, 80);
    assert!(warnings.is_empty(), "{warnings:?}");
    assert!(draws(&out));
}

#[test]
fn a_list_with_no_present_family_names_the_list() {
    let lib = library();
    let (_, warnings) = render(&lib, &text(" font-family=\"Nope, Also\""), 320, 80);
    assert_eq!(warnings.len(), 1, "{warnings:?}");
    assert!(warnings[0].message.starts_with(
        "font-family \"Nope, Also\" — none of these is in the font set; the set has: "
    ));
}

#[test]
fn a_text_with_no_family_says_the_default_is_missing() {
    let lib = library();
    let (_, warnings) = render(&lib, &text(""), 320, 80);
    assert_eq!(warnings.len(), 1, "{warnings:?}");
    let message = &warnings[0].message;
    assert!(
        message.starts_with(
            "a <text> has no font-family (the default \"Times New Roman\" is not in the font set); the set has: "
        ),
        "{message}"
    );
    names_every_family(&lib, message);
}

#[test]
fn an_explicit_default_family_is_named_not_called_absent() {
    let lib = library();
    for value in ["Times New Roman", "'Times New Roman'"] {
        let (_, warnings) = render(&lib, &text(&format!(" font-family=\"{value}\"")), 320, 80);
        assert_eq!(warnings.len(), 1, "{value}: {warnings:?}");
        let message = &warnings[0].message;
        assert!(
            message.starts_with(
                "font-family \"Times New Roman\" is not in the font set; the set has: "
            ),
            "{value}: {message}"
        );
        assert!(
            !message.contains("has no font-family"),
            "{value}: {message}"
        );
        names_every_family(&lib, message);
    }
}

#[test]
fn a_missing_family_in_a_sheet_is_seen() {
    let lib = library();
    let body = "<style>text{font-family:Nope}</style>\
                <text x=\"10\" y=\"56\" font-size=\"40\">Hamburg</text>";
    let (_, warnings) = render(&lib, &svg(320, 80, body), 320, 80);
    assert_eq!(warnings.len(), 1, "{warnings:?}");
    assert!(warnings[0]
        .message
        .starts_with("font-family \"Nope\" is not in the font set"));
}

#[test]
fn an_unquoted_digit_family_in_a_sheet_says_to_quote_it() {
    let lib = library();
    let body = "<style>text{font-family:Source Sans 3}</style>\
                <text x=\"10\" y=\"56\" font-size=\"40\">Hamburg</text>";
    let (_, warnings) = render(&lib, &svg(320, 80, body), 320, 80);
    assert_eq!(messages(&warnings).len(), 1, "{warnings:?}");
    let message = &warnings[0].message;
    assert!(message.contains(DIGIT), "{message}");
    assert!(!message.contains("has no font-family"), "{message}");
}

#[test]
fn an_unquoted_digit_family_in_a_style_attribute_says_to_quote_it() {
    let lib = library();
    let (_, warnings) = render(&lib, &text(" style=\"font-family:Source Sans 3\""), 320, 80);
    assert_eq!(warnings.len(), 1, "{warnings:?}");
    assert!(warnings[0].message.contains(DIGIT), "{warnings:?}");
}

#[test]
fn a_missing_family_inside_a_nested_svg_asset_is_seen() {
    // The lock-discipline oracle: the nested parse re-enters `select_font`
    // on this thread, so a probe lock held across it would hang this test.
    let nested = svg(
        200,
        60,
        "<text x=\"0\" y=\"40\" font-family=\"Nope\" font-size=\"30\">inner</text>",
    );
    let lib = library_with(BTreeMap::from([(
        "nested.svg".to_string(),
        nested.into_bytes(),
    )]));
    let body = "<image x=\"0\" y=\"0\" width=\"200\" height=\"60\" href=\"nested.svg\"/>";
    let (_, warnings) = render(&lib, &svg(200, 60, body), 200, 60);
    assert_eq!(warnings.len(), 1, "{warnings:?}");
    assert!(warnings[0]
        .message
        .starts_with("font-family \"Nope\" is not in the font set"));
}

#[test]
fn an_unquoted_digit_family_in_a_font_shorthand_says_to_quote_it() {
    let lib = library();
    let (_, warnings) = render(&lib, &text(" style=\"font: 40px Source Sans 3\""), 320, 80);
    assert_eq!(warnings.len(), 1, "{warnings:?}");
    let message = &warnings[0].message;
    assert!(
        message.starts_with(&format!(
            "font-family=\"Source Sans 3\" {DIGIT}; the set has: "
        )),
        "{message}"
    );
    names_every_family(&lib, message);
}

#[test]
fn an_unquoted_digit_family_in_a_sheets_font_shorthand_says_to_quote_it() {
    let lib = library();
    let body = "<style>text{font:40px Source Sans 3}</style>\
                <text x=\"10\" y=\"56\">Hamburg</text>";
    let (_, warnings) = render(&lib, &svg(320, 80, body), 320, 80);
    assert_eq!(messages(&warnings).len(), 1, "{warnings:?}");
    let message = &warnings[0].message;
    assert!(message.contains(DIGIT), "{message}");
    assert!(!message.contains("has no font-family"), "{message}");
}

#[test]
fn a_quoted_digit_family_in_a_font_shorthand_draws_without_a_warning() {
    let lib = library();
    let (out, warnings) = render(
        &lib,
        &text(" style=\"font: 40px 'Source Sans 3'\""),
        320,
        80,
    );
    assert!(warnings.is_empty(), "{warnings:?}");
    assert!(draws(&out));
}

#[test]
fn a_font_xml_attribute_is_not_read_as_a_family() {
    // usvg keeps `font="…"` as an attribute it never reads, so the text has
    // no family and gets the default's sentence.
    let lib = library();
    let (_, warnings) = render(&lib, &text(" font=\"40px Source Sans 3\""), 320, 80);
    assert_eq!(warnings.len(), 1, "{warnings:?}");
    assert!(
        warnings[0]
            .message
            .starts_with("a <text> has no font-family"),
        "{warnings:?}"
    );
}

#[test]
fn the_generic_families_draw_their_mapped_faces_without_a_warning() {
    // G-6: serif, sans-serif and monospace are named on the font set.
    let lib = library();
    for (generic, face) in [
        ("serif", "'Source Serif 4'"),
        ("sans-serif", "'Source Sans 3'"),
        ("monospace", "'IBM Plex Mono'"),
    ] {
        let (out, warnings) = render(&lib, &text(&format!(" font-family=\"{generic}\"")), 320, 80);
        assert!(warnings.is_empty(), "{generic}: {warnings:?}");
        assert!(draws(&out), "{generic} drew nothing");
        let (named, _) = render(&lib, &text(&format!(" font-family=\"{face}\"")), 320, 80);
        assert!(out == named, "{generic} is not drawn in {face}");
    }
}

#[test]
fn an_unmapped_generic_family_is_warned_like_a_missing_one() {
    let lib = library();
    let (out, warnings) = render(&lib, &text(" font-family=\"cursive\""), 320, 80);
    assert_eq!(warnings.len(), 1, "{warnings:?}");
    let message = &warnings[0].message;
    assert!(
        message.starts_with("font-family \"cursive\" is not in the font set; the set has: "),
        "{message}"
    );
    names_every_family(&lib, message);
    assert!(!draws(&out), "an unmapped generic drew");
}
