//! Road map 10's six templates on a tall canvas (spec §11 VR-43, VR-47): each
//! measures by `Math.min(ctx.width, ctx.height) / 1080`, so at 1080 × 1920
//! every visible text lies inside the frame inset by 24 px (G1), and at
//! 1920 × 1080 and 1080 × 1080 it draws byte for byte what the shipped text
//! drew (G2). The trap holds `GraphicTemplates+Revisions.swift`'s table to the
//! tree: a later edit of one of the six fails here until its new digest is
//! added (VR-44 (a)).

mod common;

use std::fs;
use std::sync::Arc;

use graphic::{rasterize, Module};
use resvg::usvg::{self, fontdb};

use common::{shared, BUDGET_MS, FIXTURES};

const FPS: f64 = 30.0;
const INSET: f32 = 24.0;
const NEW_UNIT: &str = "Math.min(ctx.width, ctx.height) / 1080";
const OLD_UNIT: &str = "ctx.height / 1080";
const REVISIONS: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../app/Sources/GraphicTemplates+Revisions.swift"
);

/// Each of the six's text at b71e20b5 (spec §11 G-45's `meta`), the last the
/// app bundled before VR-43.
const SHIPPED: [(&str, &str); 6] = [
    (
        "lower-third",
        "9676a844a90c3765c061c146dcf8ea6b4687430da3c7f20c300c0a03899032e3",
    ),
    (
        "title-card",
        "632be051990c326b7b489b0455abceeb27fdd0c3d4f3e8b7634fd28a36d4b0af",
    ),
    (
        "callout",
        "60efb8170a425cd78f805d23e048d9c1de6f45412a2b05e8c2a6be2b8e02b822",
    ),
    (
        "bar-chart",
        "269524824fbd6b89890c0be746bbff45bb02edf1da394aa43b6fab7eda597b82",
    ),
    (
        "counter",
        "eb9320e2ec26d421cd3f3cb92d399128f5f2e38833f7e55fb00dc56fdf1e2233",
    ),
    (
        "kinetic-type",
        "23b83131b69d090f47d4f446e3fa31ffa858e10e26907f8b31790defec717b7e",
    ),
];

fn compile(name: &str, source: &str) -> Module {
    Module::compile(shared(), name, source, BUDGET_MS)
        .unwrap_or_else(|d| panic!("{name} did not compile: {}", d.message))
}

fn duration(module: &Module) -> i64 {
    module.meta()["durationInFrames"].as_i64().unwrap_or(150)
}

fn svg_at(module: &Module, frame: i64, width: u32, height: u32) -> String {
    let ctx = common::ctx(frame, FPS, duration(module), width, height);
    let (svg, _) =
        graphic::svg(module, frame, &module.defaults(), &ctx, BUDGET_MS).unwrap_or_else(|d| {
            panic!(
                "{} {width}x{height} frame {frame}: {}",
                module.name(),
                d.message
            )
        });
    svg
}

fn bgra(module: &Module, frame: i64, width: u32, height: u32) -> Vec<u8> {
    let svg = svg_at(module, frame, width, height);
    let stride = width as usize * 4;
    let mut out = vec![0u8; stride * height as usize];
    rasterize(&shared(), &svg, width, height, &mut out, stride).unwrap_or_else(|d| {
        panic!(
            "{} {width}x{height} frame {frame}: {}",
            module.name(),
            d.message
        )
    });
    out
}

/// A font database of exactly the bundled faces, with G-6's generics.
fn fonts() -> Arc<fontdb::Database> {
    let mut db = fontdb::Database::new();
    for bytes in common::fonts() {
        db.load_font_source(fontdb::Source::Binary(Arc::new(bytes)));
    }
    db.set_serif_family("Source Serif 4");
    db.set_sans_serif_family("Source Sans 3");
    db.set_monospace_family("IBM Plex Mono");
    Arc::new(db)
}

/// Every text node's stroke box whose accumulated group opacity is above 0.
fn texts(group: &usvg::Group, opacity: f32, out: &mut Vec<usvg::Rect>) {
    for node in group.children() {
        match node {
            usvg::Node::Group(inner) => texts(inner, opacity * inner.opacity().get(), out),
            usvg::Node::Text(text) if opacity > 0.0 => out.push(text.abs_stroke_bounding_box()),
            _ => {}
        }
    }
}

#[test]
fn portrait_text_inside_the_frame() {
    let (width, height) = (1080u32, 1920u32);
    let (w, h) = (width as f32, height as f32);
    let options = usvg::Options {
        fontdb: fonts(),
        ..usvg::Options::default()
    };
    let mut failures = Vec::new();
    let mut counted = 0;
    for name in FIXTURES {
        let module = common::module(name);
        let d = duration(&module);
        for frame in [0, d / 2, d - 1] {
            let svg = svg_at(&module, frame, width, height);
            let tree = usvg::Tree::from_str(&svg, &options)
                .unwrap_or_else(|e| panic!("{name} frame {frame}: usvg: {e}"));
            let mut boxes = Vec::new();
            texts(tree.root(), 1.0, &mut boxes);
            for b in boxes {
                let meets = b.left() < w && b.right() > 0.0 && b.top() < h && b.bottom() > 0.0;
                if !meets {
                    continue;
                }
                counted += 1;
                if b.left() < INSET
                    || b.right() > w - INSET
                    || b.top() < INSET
                    || b.bottom() > h - INSET
                {
                    failures.push(format!(
                        "{name} frame {frame}: text [{:.1}, {:.1}] × [{:.1}, {:.1}] outside [{INSET}, {}] × [{INSET}, {}]",
                        b.left(),
                        b.right(),
                        b.top(),
                        b.bottom(),
                        w - INSET,
                        h - INSET
                    ));
                }
            }
        }
    }
    assert!(counted > 0, "no visible text was found in any template");
    assert!(failures.is_empty(), "\n{}", failures.join("\n"));
}

#[test]
fn landscape_and_square_unchanged() {
    let mut failures = Vec::new();
    for (name, digest) in SHIPPED {
        let current = common::fixture(name);
        assert_eq!(
            current.matches(NEW_UNIT).count(),
            1,
            "{name}: the unit line by the short side, once"
        );
        let shipped = current.replace(NEW_UNIT, OLD_UNIT);
        assert_eq!(
            common::sha256(shipped.as_bytes()),
            digest,
            "{name}: the new text with the unit line put back is not the shipped text"
        );
        let new = compile(name, &current);
        let old = compile(name, &shipped);
        let d = duration(&new);
        let mut frames: Vec<i64> = (0..d).step_by(5).collect();
        if frames.last() != Some(&(d - 1)) {
            frames.push(d - 1);
        }
        for (width, height) in [(1920u32, 1080u32), (1080, 1080)] {
            for &frame in &frames {
                if bgra(&new, frame, width, height) != bgra(&old, frame, width, height) {
                    failures.push(format!("{name} {width}x{height} frame {frame} differs"));
                }
            }
        }
    }
    assert!(failures.is_empty(), "\n{}", failures.join("\n"));
}

/// `"<64 hex>": "<stem>"` rows of the Swift table.
fn table() -> Vec<(String, String)> {
    let text = fs::read_to_string(REVISIONS).expect("GraphicTemplates+Revisions.swift");
    let mut rows = Vec::new();
    for line in text.lines() {
        let parts: Vec<&str> = line.split('"').collect();
        if parts.len() >= 5 && parts[2].trim() == ":" {
            let (hex, stem) = (parts[1], parts[3]);
            if hex.len() == 64 && hex.chars().all(|c| c.is_ascii_hexdigit()) {
                rows.push((hex.to_string(), stem.to_string()));
            }
        }
    }
    rows
}

#[test]
fn revision_table_holds_every_current_template() {
    let rows = table();
    assert!(!rows.is_empty(), "no row read from {REVISIONS}");
    let mut failures = Vec::new();
    for name in FIXTURES {
        let digest = common::sha256(common::fixture(name).as_bytes());
        if !rows
            .iter()
            .any(|(hex, stem)| *hex == digest && stem == name)
        {
            failures.push(format!(
                "{name}: its current digest {digest} is not a row of GraphicTemplates.shippedRevisions — add it"
            ));
        }
    }
    assert!(failures.is_empty(), "\n{}", failures.join("\n"));
}
