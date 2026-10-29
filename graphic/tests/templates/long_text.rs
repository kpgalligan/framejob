//! The long-text pass of `templates.rs` (spec §11 G-44 (b)): every `string`
//! property of every template given a long, realistic value — about 40
//! characters for a title or label, about 120 for a quote, ticker text or
//! subtitle-style field, a list its longest plausible entries — and held to
//! the same rule as the defaults. A template's string property with no row
//! here fails the pass, so a new one cannot go untested at length.
//! chapter-card's kicker is also held to breaking only between words, a
//! one-word kicker wider than its room shrinking onto one line.

use super::*;

/// `(stem, key, value)`: one long value for each template's `string`
/// property.
const LONG_TEXT: &[(&str, &str, &str)] = &[
    (
        "arrow-highlight",
        "label",
        "Click the Export button in the top corner",
    ),
    (
        "chapter-card",
        "kicker",
        "SECTION FOUR: ADVANCED COLOUR GRADING",
    ),
    (
        "chapter-card",
        "title",
        "Setting up your very first multicam edit",
    ),
    (
        "countdown",
        "label",
        "The livestream starts in just a moment",
    ),
    ("donut-chart", "values", "1250, 830, 415, 210, 95, 40"),
    (
        "donut-chart",
        "labels",
        "Colour grading and finishing, Sound design and mixing, Motion graphics, \
         Rough cut assembly, Exports and delivery, Everything else",
    ),
    (
        "donut-chart",
        "title",
        "Where the editing time went this quarter",
    ),
    (
        "end-screen",
        "title",
        "Watch these next before you go anywhere",
    ),
    (
        "end-screen",
        "videoA",
        "How I edit a whole video in one hour",
    ),
    (
        "end-screen",
        "videoB",
        "The five mistakes every new editor makes",
    ),
    (
        "end-screen",
        "subscribe",
        "Subscribe for a new video every week",
    ),
    ("gauge", "label", "Average download speed this month"),
    ("gauge", "units", "megabits per second"),
    (
        "handle-tag",
        "handle",
        "@the.everyday.video.editing.channel",
    ),
    ("keyboard-keys", "keys", "ctrl+option+cmd+shift+space"),
    (
        "keyboard-keys",
        "label",
        "Capture a selected window to the clipboard",
    ),
    (
        "line-chart",
        "values",
        "1250500, 1380250, 1420900, 1510000, 1688400, 1730250, 1802600, \
         1950750, 2010300, 2150800, 2290400, 2480900",
    ),
    (
        "line-chart",
        "labels",
        "January, February, March, April, May, June, July, August, September, \
         October, November, December",
    ),
    (
        "line-chart",
        "title",
        "Monthly active users across every platform",
    ),
    ("logo-reveal", "mark", "THE EVERYDAY VIDEO EDITING CHANNEL"),
    (
        "logo-reveal",
        "tagline",
        "Practical editing lessons for creators who would rather be out \
         shooting than sitting in front of a timeline all day",
    ),
    (
        "news-ticker",
        "headline",
        "LIVE FROM THE ANNUAL DEVELOPER CONFERENCE",
    ),
    (
        "news-ticker",
        "items",
        "Frame Job adds seventeen ready-made graphic templates to the Insert \
         menu, from charts and timers to social pop-ups | Every template is \
         drawn by code and stays inside title-safe at landscape, portrait and \
         square sizes | Long headlines like this one crawl past without ever \
         leaving the band",
    ),
    (
        "progress-bar",
        "label",
        "Rendering the final export for delivery",
    ),
    (
        "quote-card",
        "quote",
        "Good editing is invisible. All anyone should ever notice is the \
         story, the people in it and the way it made them feel.",
    ),
    (
        "quote-card",
        "attribution",
        "Margaret Example, Senior Colourist",
    ),
    (
        "social-popup",
        "handle",
        "@the.everyday.video.editing.channel",
    ),
    (
        "social-popup",
        "text",
        "Loved this edit! The pacing in the second half is perfect and the \
         colour grade makes every single shot feel warm.",
    ),
    (
        "step-badge",
        "label",
        "Open the export sheet from the File menu",
    ),
    (
        "subscribe-button",
        "label",
        "SUBSCRIBE FOR A NEW VIDEO EVERY WEEK",
    ),
    (
        "subscribe-button",
        "doneLabel",
        "SUBSCRIBED, THANK YOU FOR WATCHING",
    ),
    (
        "window-frame",
        "title",
        "Frame Job — Summer Trip Edit, Version 3",
    ),
    (
        "window-frame",
        "url",
        "https://www.example.com/tutorials/colour-grading-basics?ref=channel",
    ),
];

/// `module`'s `string` keys, in schema order.
fn string_keys(module: &Module) -> Vec<String> {
    let schema = module.schema();
    let schema = schema.as_object().expect("a schema object");
    schema
        .iter()
        .filter(|(_, entry)| entry["type"] == "string")
        .map(|(key, _)| key.clone())
        .collect()
}

/// Every template drawn with long text: all of its `string` properties long
/// at once under every combination of its `enum` options (an option can be
/// what shows a string, as social-popup's `comment` shows `text`), and each
/// alone with the rest at their defaults; at all three sizes, frames 0,
/// D/4, the hold D/2 and the last D − 1, held to `check()`'s rule.
#[test]
fn long_text_draws_cleanly_inside_title_safe() {
    let stems = templates();
    let mut failures = Vec::new();
    for (stem, key, _) in LONG_TEXT {
        let known = stems.iter().any(|s| s == stem)
            && string_keys(&common::module(stem)).iter().any(|k| k == key);
        if !known {
            failures.push(format!(
                "LONG_TEXT names {stem}.{key}, no template's string"
            ));
        }
    }
    for stem in &stems {
        let module = common::module(stem);
        let d = duration(&module);
        let mut long = module.defaults();
        let mut alone = Vec::new();
        for key in string_keys(&module) {
            let Some((_, _, value)) = LONG_TEXT.iter().find(|(s, k, _)| s == stem && *k == key)
            else {
                failures.push(format!("{stem}.{key}: a string with no LONG_TEXT row"));
                continue;
            };
            long[&key] = Value::from(*value);
            let mut props = module.defaults();
            props[&key] = Value::from(*value);
            alone.push((format!("{stem} long {key}"), props));
        }
        let all = combinations(&module, long)
            .into_iter()
            .map(|(what, props)| (format!("{stem} long{what}"), props));
        for (what, props) in all.chain(alone) {
            for size in SIZES {
                let frames = [0, d / 4, d / 2, d - 1];
                check(&module, &props, &frames, size, &what, &mut failures);
            }
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

/// The text of each `<tspan>` in `svg`, in order: chapter-card's kicker
/// lines, its only text drawn as tspans.
fn tspans(svg: &str) -> Vec<String> {
    svg.split("<tspan")
        .skip(1)
        .map(|rest| {
            let text = &rest[rest.find('>').map_or(0, |i| i + 1)..];
            text[..text.find("</tspan>").unwrap_or(text.len())].to_string()
        })
        .collect()
}

/// chapter-card's kicker breaks only between words: a one-word kicker wider
/// than its room at full size ("INTRODUCTION" in portrait and square) is
/// shrunk onto ONE line rather than split mid-word, and the default and the
/// long row's lines hold the kicker's own words; at all three sizes, the
/// one-word kickers also held to `check()` at frames 0, D/4, D/2 and D − 1.
#[test]
fn chapter_card_kicker_breaks_only_between_words() {
    let module = common::module("chapter-card");
    let d = duration(&module);
    let long = LONG_TEXT
        .iter()
        .find(|(s, k, _)| *s == "chapter-card" && *k == "kicker")
        .expect("chapter-card's long kicker row")
        .2;
    let mut failures = Vec::new();
    for kicker in ["CHAPTER", "INTRODUCTION", "CONCLUSION", long] {
        let mut props = module.defaults();
        props["kicker"] = Value::from(kicker);
        let words: Vec<&str> = kicker.split_whitespace().collect();
        for (width, height) in SIZES {
            let what = format!("chapter-card kicker {kicker:?} {width}x{height}");
            let ctx = common::ctx(d / 2, FPS, d, width, height);
            let svg = match graphic::svg(&module, d / 2, &props, &ctx, BUDGET_MS) {
                Ok((svg, _)) => svg,
                Err(e) => {
                    failures.push(format!("{what}: {}", e.message));
                    continue;
                }
            };
            let lines = tspans(&svg);
            let drawn: Vec<&str> = lines.iter().flat_map(|l| l.split_whitespace()).collect();
            if drawn != words || (words.len() == 1 && lines.len() != 1) {
                failures.push(format!("{what}: drawn as lines {lines:?}"));
            }
            if words.len() == 1 {
                let frames = [0, d / 4, d / 2, d - 1];
                check(
                    &module,
                    &props,
                    &frames,
                    (width, height),
                    &format!("chapter-card kicker {kicker:?}"),
                    &mut failures,
                );
            }
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}
