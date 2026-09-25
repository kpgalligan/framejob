//! What every test file shares: the bundled font set with the committed
//! assets, a render into a fresh buffer, and a pixel read.

#![allow(dead_code)]

use std::collections::BTreeMap;
use std::fs;

use graphic::{rasterize, Diagnostic, Library};

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
