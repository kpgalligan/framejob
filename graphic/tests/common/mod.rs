//! What every test file shares: the bundled font set with the committed
//! assets, a render into a fresh buffer, and a pixel read; for the
//! JavaScript half, the fixtures, a compiled module, a frame of it and the
//! sandbox cases' source.

#![allow(dead_code)]

use std::collections::BTreeMap;
use std::fs;
use std::sync::{Arc, OnceLock};

use graphic::{rasterize, Diagnostic, Library, Module};
use sha2::{Digest, Sha256};

/// Every test's call deadline: §5b's preview budget.
pub const BUDGET_MS: u64 = 250;
pub const GRAPHICS: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/graphics");
/// The six fixtures of road map 10 §5k, by file stem.
pub const FIXTURES: [&str; 6] = [
    "lower-third",
    "title-card",
    "counter",
    "bar-chart",
    "kinetic-type",
    "callout",
];

pub const FONTS: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../app/Resources/Fonts");
pub const ASSETS: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/assets");

/// The app's bundled `.ttf` files, in file-name order.
pub fn fonts() -> Vec<Vec<u8>> {
    let mut paths: Vec<_> = fs::read_dir(FONTS)
        .expect("the bundled fonts directory")
        .map(|entry| entry.expect("a directory entry").path())
        .filter(|path| path.extension().is_some_and(|ext| ext == "ttf"))
        .collect();
    paths.sort();
    paths
        .iter()
        .map(|path| fs::read(path).expect("a font file"))
        .collect()
}

/// The four committed images, keyed by file name (README.md is not one).
pub fn assets() -> BTreeMap<String, Vec<u8>> {
    [
        "red.png",
        "steel.jpg",
        "blue-then-yellow.gif",
        "magenta.webp",
    ]
    .iter()
    .map(|name| {
        let data = fs::read(format!("{ASSETS}/{name}")).expect("a committed asset");
        (name.to_string(), data)
    })
    .collect()
}

pub fn library() -> Library {
    Library::new(fonts(), assets())
}

/// The bundled fonts with the committed assets plus `extra`.
pub fn library_with(extra: BTreeMap<String, Vec<u8>>) -> Library {
    let mut all = assets();
    all.extend(extra);
    Library::new(fonts(), all)
}

/// Draws `svg` at `width`×`height` with stride `width × 4`; panics on an
/// error, answers the buffer and the warnings.
pub fn render(lib: &Library, svg: &str, width: u32, height: u32) -> (Vec<u8>, Vec<Diagnostic>) {
    let stride = width as usize * 4;
    let mut out = vec![0u8; stride * height as usize];
    let warnings = rasterize(lib, svg, width, height, &mut out, stride)
        .unwrap_or_else(|e| panic!("rasterize refused: {}", e.message));
    (out, warnings)
}

/// The BGRA bytes of pixel `(x, y)`.
pub fn pixel(buf: &[u8], stride: usize, x: usize, y: usize) -> [u8; 4] {
    let at = y * stride + x * 4;
    [buf[at], buf[at + 1], buf[at + 2], buf[at + 3]]
}

pub fn messages(warnings: &[Diagnostic]) -> Vec<String> {
    warnings.iter().map(|w| w.message.clone()).collect()
}

pub fn svg(width: u32, height: u32, body: &str) -> String {
    format!(
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{width}\" height=\"{height}\">{body}</svg>"
    )
}

/// One library for the whole test binary, shared by every module.
pub fn shared() -> Arc<Library> {
    static SHARED: OnceLock<Arc<Library>> = OnceLock::new();
    SHARED.get_or_init(|| Arc::new(library())).clone()
}

/// §5c's `ctx` of `frame` on a `duration`-frame graphic at `fps`, the
/// graphic the size of the canvas.
pub fn ctx(frame: i64, fps: f64, duration: i64, width: u32, height: u32) -> serde_json::Value {
    let progress = (frame as f64 / ((duration - 1).max(1)) as f64).clamp(0.0, 1.0);
    serde_json::json!({
        "fps": fps, "time": frame as f64 / fps, "durationInFrames": duration,
        "progress": progress, "width": width, "height": height,
        "canvas": {"width": width, "height": height},
    })
}

/// The fixture `tests/graphics/<name>.js`'s source.
pub fn fixture(name: &str) -> String {
    fs::read_to_string(format!("{GRAPHICS}/{name}.js")).expect("a fixture")
}

/// The fixture `name`, compiled under `BUDGET_MS`; panics on a refusal.
pub fn module(name: &str) -> Module {
    Module::compile(shared(), name, &fixture(name), BUDGET_MS)
        .unwrap_or_else(|d| panic!("{name} did not compile: {}", d.message))
}

/// `module`'s `render` at `frame` with its default props, on a 1920×1080
/// canvas at 30 fps and the module's own `meta.durationInFrames`.
pub fn frame(module: &Module, frame: i64) -> Result<(String, Vec<Diagnostic>), Diagnostic> {
    let duration = module.meta()["durationInFrames"].as_i64().unwrap_or(150);
    graphic::svg(
        module,
        frame,
        &module.defaults(),
        &ctx(frame, 30.0, duration, 1920, 1080),
        BUDGET_MS,
    )
}

pub fn sha256(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

/// A sandbox case's module, shaped as G0's q6: `render` opens on line 3
/// (after `head`'s lines) and `body` is the line after it.
pub fn case(head: &str, body: &str) -> String {
    format!(
        "{head}export const meta = {{ name: \"case\" }};\nexport const schema = {{}};\n\
         export function render(frame, props, ctx) {{\n  {body}\n}}\n"
    )
}
