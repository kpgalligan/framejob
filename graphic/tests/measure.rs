//! `measure_text`: its ink agrees with the ink a composed render draws, its
//! whitespace collapses, variable faces widen with weight, and its errors,
//! zeros, memo and JSON.

mod common;

use std::time::Instant;

use common::{library, render};
use graphic::{measure_text, FontStyle, Library, TextFont};

const STRINGS: [&str; 24] = [
    "the",
    "Quick brown fox",
    "jumps over the lazy dog",
    "AVATAR",
    "Wave",
    "kerning",
    "fjord",
    "Zürich",
    "café über",
    "résumé naïve",
    "LTAV",
    "illumination",
    "WWW mm",
    "Hello, world!",
    "Reelcut",
    "0",
    "42",
    "2026",
    "3.14",
    "1,284,093",
    "(Typo) — 100%",
    "\"quoted\" & 'single'",
    "a:b;c?",
    "The quick brown fox jumps over the dog.",
];

fn font(family: &str, size: f64, weight: u16) -> TextFont {
    TextFont {
        family: family.to_string(),
        size,
        weight,
        style: FontStyle::Normal,
        letter_spacing: 0.0,
        preserve_space: false,
    }
}

fn escape(text: &str) -> String {
    text.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

/// The ink columns of `text` inside a composed SVG — a bar above it, a disc
/// below it, the text in a translated group — counting alpha > 0 in the
/// text's band only (the spike's `rows_text.rs:91-127`).
fn composed_ink(
    lib: &Library,
    text: &str,
    family: &str,
    size: f64,
    weight: u16,
    advance: f64,
) -> f64 {
    let pad = size;
    let w = (advance + 3.0 * pad).ceil() as u32;
    let h = (size * 4.0).ceil() as u32;
    let band = (size * 0.5).ceil() as usize + 1;
    let svg = format!(
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{w}\" height=\"{h}\">\
         <rect x=\"0\" y=\"0\" width=\"{w}\" height=\"{bar}\" fill=\"#336\"/>\
         <g transform=\"translate({pad} 0)\"><text x=\"0\" y=\"{baseline}\" font-family=\"{family}\" \
         font-size=\"{size}\" font-weight=\"{weight}\" fill=\"#fff\">{t}</text></g>\
         <circle cx=\"{c}\" cy=\"{cy}\" r=\"{r}\" fill=\"#f00\"/></svg>",
        bar = size * 0.5,
        baseline = size * 2.0,
        t = escape(text),
        c = w as f64 / 2.0,
        cy = h as f64 - size * 0.25,
        r = size * 0.2,
    );
    let (out, _) = render(lib, &svg, w, h);
    let (w, bottom) = (w as usize, h as usize - band);
    let mut columns = (usize::MAX, 0usize);
    for y in band..bottom {
        for x in 0..w {
            if out[(y * w + x) * 4 + 3] > 0 {
                columns = (columns.0.min(x), columns.1.max(x));
            }
        }
    }
    if columns.0 == usize::MAX {
        0.0
    } else {
        (columns.1 - columns.0 + 1) as f64
    }
}

#[test]
fn ink_width_matches_the_ink_a_composed_render_draws() {
    let lib = library();
    let faces = [
        ("Montserrat", 800u16),
        ("Anton", 400),
        ("IBM Plex Mono", 400),
        ("Bebas Neue", 400),
    ];
    let (mut count, mut worst) = (0, (0.0f64, String::new()));
    for (family, weight) in faces {
        for size in [24.0, 64.0, 160.0] {
            for text in STRINGS {
                let m = measure_text(&lib, text, &font(family, size, weight)).unwrap();
                let ink = composed_ink(&lib, text, family, size, weight, m.width.max(m.ink_width));
                let d = (m.ink_width - ink).abs();
                if d > worst.0 {
                    worst = (
                        d,
                        format!(
                            "{family} {weight} {size}px {text:?}: ink_width {} vs {ink} columns",
                            m.ink_width
                        ),
                    );
                }
                assert!(
                    d <= 2.0,
                    "{family} {weight} {size}px {text:?}: ink_width {} vs {ink} columns",
                    m.ink_width
                );
                count += 1;
            }
        }
    }
    println!(
        "parity: {count} cases, worst {:.3} px ({})",
        worst.0, worst.1
    );
    assert_eq!(count, 288);
}

#[test]
fn whitespace_collapses() {
    let lib = library();
    let f = font("Montserrat", 64.0, 800);
    let base = measure_text(&lib, "a b", &f).unwrap();
    for text in ["a  b", "a b ", " a b"] {
        assert_eq!(measure_text(&lib, text, &f).unwrap(), base, "{text:?}");
    }
}

#[test]
fn variable_faces_widen_with_weight() {
    let lib = library();
    for family in ["Source Sans 3", "Darker Grotesque"] {
        let widths: Vec<f64> = [200u16, 400, 700, 900]
            .iter()
            .map(|w| {
                measure_text(&lib, "Hamburgefonstiv", &font(family, 64.0, *w))
                    .unwrap()
                    .width
            })
            .collect();
        println!("{family} at 200/400/700/900: {widths:?}");
        assert!(
            widths.windows(2).all(|p| p[0] < p[1]),
            "{family}: {widths:?}"
        );
    }
}

#[test]
fn a_missing_family_is_an_error_naming_the_set() {
    let lib = library();
    let error = measure_text(&lib, "Hello", &font("Nope", 64.0, 400)).unwrap_err();
    assert_eq!(
        error.message,
        format!(
            "measureText: no face for family \"Nope\"; the set has: {}",
            lib.families().join(", ")
        )
    );
}

#[test]
fn a_bad_font_is_an_error() {
    let lib = library();
    let cases = [
        (
            font("Montserrat", 0.0, 400),
            "measureText: size 0 must be finite and > 0",
        ),
        (
            font("Montserrat", 64.0, 0),
            "measureText: weight 0 must be 1–1000",
        ),
        (
            TextFont {
                letter_spacing: f64::NAN,
                ..font("Montserrat", 64.0, 400)
            },
            "measureText: letterSpacing must be finite",
        ),
    ];
    for (f, want) in cases {
        assert_eq!(measure_text(&lib, "Hello", &f).unwrap_err().message, want);
    }
}

#[test]
fn whitespace_only_measures_zero() {
    let lib = library();
    let m = measure_text(&lib, " \t ", &font("Montserrat", 64.0, 800)).unwrap();
    for value in [
        m.width,
        m.ascent,
        m.descent,
        m.line_height,
        m.ink_x,
        m.ink_width,
    ] {
        assert_eq!(value, 0.0);
    }
}

#[test]
fn the_same_call_answers_the_same_metrics() {
    let lib = library();
    let f = font("Anton", 96.0, 400);
    let started = Instant::now();
    let first = measure_text(&lib, "Remembered", &f).unwrap();
    let cold = started.elapsed();
    let started = Instant::now();
    let second = measure_text(&lib, "Remembered", &f).unwrap();
    let warm = started.elapsed();
    println!("measure_text: first {cold:?}, second {warm:?}");
    assert_eq!(first, second);
}

#[test]
fn letter_spacing_changes_the_advance() {
    let lib = library();
    let plain = measure_text(&lib, "Spaced", &font("Montserrat", 64.0, 800)).unwrap();
    let spaced = TextFont {
        letter_spacing: 10.0,
        ..font("Montserrat", 64.0, 800)
    };
    let wide = measure_text(&lib, "Spaced", &spaced).unwrap();
    assert!(
        wide.width > plain.width,
        "{} vs {}",
        wide.width,
        plain.width
    );
}

#[test]
fn to_json_keys_are_in_order() {
    let lib = library();
    let m = measure_text(&lib, "Keys", &font("Montserrat", 64.0, 800)).unwrap();
    let json = m.to_json();
    let keys: Vec<&str> = json
        .as_object()
        .unwrap()
        .keys()
        .map(String::as_str)
        .collect();
    assert_eq!(
        keys,
        [
            "width",
            "ascent",
            "descent",
            "lineHeight",
            "inkX",
            "inkWidth"
        ]
    );
    assert_eq!(json["lineHeight"].as_f64(), Some(m.line_height));
}

#[test]
fn a_generic_family_measures_as_its_mapped_face() {
    let lib = library();
    for (generic, face) in [
        ("serif", "Source Serif 4"),
        ("sans-serif", "Source Sans 3"),
        ("monospace", "IBM Plex Mono"),
    ] {
        let a = measure_text(&lib, "Hamburg", &font(generic, 64.0, 400))
            .unwrap_or_else(|e| panic!("{generic}: {}", e.message));
        let b = measure_text(&lib, "Hamburg", &font(face, 64.0, 400)).unwrap();
        assert_eq!(a, b, "{generic} against {face}");
    }
}

#[test]
fn preserved_spaces_count_and_the_flag_is_in_the_memo() {
    // G-22. Default first, so a memo that ignored the flag would answer the
    // collapsed width for the preserved call.
    let lib = library();
    let plain = font("Source Sans 3", 64.0, 400);
    let preserved = TextFont {
        preserve_space: true,
        ..font("Source Sans 3", 64.0, 400)
    };
    let collapsed = measure_text(&lib, "a  b", &plain).unwrap();
    let kept = measure_text(&lib, "a  b", &preserved).unwrap();
    println!(
        "\"a  b\": default {}, preserved {}",
        collapsed.width, kept.width
    );
    assert_eq!(collapsed, measure_text(&lib, "a b", &plain).unwrap());
    assert!(
        kept.width > collapsed.width,
        "{} vs {}",
        kept.width,
        collapsed.width
    );
}

#[test]
fn preserved_whitespace_only_measures_zero_as_default_does() {
    let lib = library();
    let preserved = TextFont {
        preserve_space: true,
        ..font("Montserrat", 64.0, 800)
    };
    let m = measure_text(&lib, "   ", &preserved)
        .unwrap_or_else(|e| panic!("preserved whitespace: {}", e.message));
    assert_eq!(m.width, 0.0);
    assert_eq!(
        m,
        measure_text(&lib, "   ", &font("Montserrat", 64.0, 800)).unwrap()
    );
}
