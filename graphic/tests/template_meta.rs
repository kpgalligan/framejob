//! The bundled templates' `meta.category` and `meta.description` (spec §11
//! G-45 (b), (c)): every module of `tests/graphics/` — road map 10's six
//! fixtures included, since all 23 are templates — declares exactly the
//! category G-45 (c)'s table gives its stem, and a one-line description of
//! 1–120 characters. The Insert ▸ Graphic… dialog files a template under
//! its category and shows the description under the preview; the table is
//! written out here, so a template added without a row fails.

mod common;

use std::fs;

use common::{module, GRAPHICS};

/// G-45 (c), category by category.
const TABLE: [(&str, &[&str]); 4] = [
    (
        "Data & Time",
        &[
            "bar-chart",
            "counter",
            "countdown",
            "donut-chart",
            "gauge",
            "line-chart",
            "progress-bar",
        ],
    ),
    (
        "Screencast",
        &[
            "arrow-highlight",
            "callout",
            "keyboard-keys",
            "step-badge",
            "window-frame",
        ],
    ),
    (
        "Titles & Text",
        &[
            "chapter-card",
            "kinetic-type",
            "logo-reveal",
            "lower-third",
            "news-ticker",
            "quote-card",
            "title-card",
        ],
    ),
    (
        "Social & YouTube",
        &[
            "end-screen",
            "handle-tag",
            "social-popup",
            "subscribe-button",
        ],
    ),
];

/// Every `*.js` stem in the folder, sorted.
fn stems() -> Vec<String> {
    let mut stems: Vec<String> = fs::read_dir(GRAPHICS)
        .expect("tests/graphics")
        .map(|entry| entry.expect("a directory entry").path())
        .filter(|path| path.extension().is_some_and(|ext| ext == "js"))
        .map(|path| path.file_stem().unwrap().to_string_lossy().into_owned())
        .collect();
    stems.sort();
    stems
}

fn category_of(stem: &str) -> Option<&'static str> {
    TABLE
        .iter()
        .find(|(_, stems)| stems.contains(&stem))
        .map(|(category, _)| *category)
}

#[test]
fn the_table_names_every_template_once() {
    let mut listed: Vec<String> = TABLE
        .iter()
        .flat_map(|(_, stems)| stems.iter().map(|s| s.to_string()))
        .collect();
    listed.sort();
    assert_eq!(listed.len(), 23, "G-45 (c) names 23 templates");
    assert_eq!(
        listed,
        stems(),
        "the folder's templates and G-45 (c)'s table"
    );
}

#[test]
fn every_template_declares_its_category_and_a_one_line_description() {
    let mut problems = Vec::new();
    for stem in stems() {
        let compiled = module(&stem);
        let meta = compiled.meta();
        let want = category_of(&stem);
        let category = meta["category"].as_str();
        if category != want {
            problems.push(format!(
                "{stem}: meta.category {category:?}, wanted {want:?}"
            ));
        }
        match meta["description"].as_str() {
            None => problems.push(format!("{stem}: meta.description is not a string")),
            Some(text) => {
                let length = text.chars().count();
                if text.trim().is_empty() || length > 120 || text.contains(['\n', '\r']) {
                    problems.push(format!(
                        "{stem}: meta.description {text:?} is not one line of 1–120 \
                         characters ({length})"
                    ));
                }
            }
        }
    }
    assert!(problems.is_empty(), "{problems:#?}");
}
