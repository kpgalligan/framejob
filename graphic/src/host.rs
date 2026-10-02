//! The host functions the standard library is built on (road map 10 §5c),
//! installed as globals before `stdlib.js` runs: `__measureText`,
//! `__assetNames`, `__warn` and `__namedColour`. What crosses back to
//! JavaScript is JSON text; `stdlib.js` parses it.

use std::cell::RefCell;
use std::rc::Rc;
use std::sync::Arc;

use rquickjs::Function;

use crate::diagnostic::Diagnostic;
use crate::library::Library;
use crate::measure::{measure_text, FontStyle, TextFont};

/// Installs the four globals on `ctx`. `sink` collects `__warn`'s
/// messages for the engine that owns it.
pub(crate) fn install(
    ctx: &rquickjs::Ctx<'_>,
    library: &Arc<Library>,
    sink: Rc<RefCell<Vec<String>>>,
) -> Result<(), Diagnostic> {
    let fonts = library.clone();
    // No lock is held here around `measure_text`: its memo lock lives in
    // `library.rs` and is taken only for the memo's own read and write.
    let measure = Function::new(
        ctx.clone(),
        move |text: String,
              family: String,
              size: f64,
              weight: f64,
              style: String,
              letter_spacing: f64,
              xml_space: String| {
            // Seven parameters: rquickjs 0.14's `FromParams` maximum.
            let preserve_space = match xml_space.as_str() {
                "default" => false,
                "preserve" => true,
                other => {
                    let message = format!(
                        "measureText: xmlSpace must be \"default\" or \"preserve\", not \"{other}\""
                    );
                    return serde_json::json!({ "error": message }).to_string();
                }
            };
            let font = TextFont {
                family,
                size,
                weight: weight as u16,
                style: match style.as_str() {
                    "italic" => FontStyle::Italic,
                    "oblique" => FontStyle::Oblique,
                    _ => FontStyle::Normal,
                },
                letter_spacing,
                preserve_space,
            };
            match measure_text(&fonts, &text, &font) {
                Ok(metrics) => metrics.to_json().to_string(),
                Err(d) => serde_json::json!({ "error": d.message }).to_string(),
            }
        },
    )
    .map_err(host_error)?;
    let assets = library.clone();
    let names = Function::new(ctx.clone(), move || {
        serde_json::Value::from(assets.asset_names()).to_string()
    })
    .map_err(host_error)?;
    let warn = Function::new(ctx.clone(), move |message: String| {
        sink.borrow_mut().push(message);
    })
    .map_err(host_error)?;
    let colour = Function::new(ctx.clone(), named_colour).map_err(host_error)?;
    let globals = ctx.globals();
    globals.set("__measureText", measure).map_err(host_error)?;
    globals.set("__assetNames", names).map_err(host_error)?;
    globals.set("__namedColour", colour).map_err(host_error)?;
    globals.set("__warn", warn).map_err(host_error)
}

/// G-12's step 4 for `stdlib.js`'s `__parseColour`: a word of ASCII
/// lowercase letters looked up in svgtypes' named-colour table (the one usvg
/// draws `fill` with, and the core's `model_color.rs` reads), answered as
/// JSON `[r, g, b, a]` in bytes, or `null` for any other text.
fn named_colour(name: String) -> String {
    if name.is_empty() || !name.bytes().all(|b| b.is_ascii_lowercase()) {
        return "null".to_string();
    }
    match name.parse::<svgtypes::Color>() {
        Ok(c) => serde_json::json!([c.red, c.green, c.blue, c.alpha]).to_string(),
        Err(_) => "null".to_string(),
    }
}

fn host_error(e: rquickjs::Error) -> Diagnostic {
    Diagnostic::error(format!(
        "the engine could not install its host functions: {e}"
    ))
}
