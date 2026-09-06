//! The output sizes the export sheet offers for one document and one
//! format — `rc_export_sizes` (spec §7.8) — and the one rule for what a
//! size MEANS on an image format, which `export_settings` applies too.
//!
//! A preset is an encoding and carries no size (`export.rs`), so the size
//! is a second choice, and this module is the list that choice is made
//! from: the format's cap if it has one, the document's own size, and the
//! standard sizes fitted to the document's aspect. The FIRST row is the
//! default — the rule every list the export sheet is built from follows —
//! which is the document's size for a movie format and the cap for an
//! image format, because an image format's cap is the point of the row
//! and not a ceiling that only applies from above.
//!
//! **The number is the short edge.** A standard size is named by one
//! number, and the number people use is the short one: "1080p ultrawide"
//! is 2560 × 1080 and "1080p vertical" is 1080 × 1920, and both are 1080p
//! to everyone who says it. Naming by the long edge would call the
//! ultrawide 2560p and the vertical 1920p, which nobody does. So a row
//! keeps its short edge exactly and the long edge follows the document:
//! L = S × long / short of the document, on whichever axis the document is
//! longer along, and S × S for a square.
//!
//! **The long edge is rounded to even.** 4:2:0 chroma puts one colour
//! sample under each 2 × 2 block of luma, so H.264 and HEVC want even
//! dimensions, and `ExporterWriter.evenDimension` rounds an odd one down
//! before writing. Rounding here — to the nearest even integer, a tie
//! going up — means the size the popup shows is the size the file has;
//! leaving it to the writer would change the size behind the sheet's
//! back. The document row is the exception and is the canvas as it is,
//! odd or not: a "Document size" that was not the document's size would be
//! a lie, and the writer's own rounding is the right place for that one.
//!
//! **An image format's numbers are the file's.** A GIF or an APNG is
//! written frame by frame with the picture FITTED inside the size — aspect
//! kept, never upscaled — where a movie is letterboxed to exactly the frame
//! asked for (`ExporterImageSequence`, spec §7.8): padding costs bytes in
//! every frame for pixels that carry nothing, and a bigger frame carries no
//! more detail. So on those two formats every row here, and every size
//! `export_settings` resolves — the cap, a standard row, a custom size — is
//! the canvas fitted inside that box ([`fit_within`]), so that the popup,
//! the sheet's readout and the `export` tool all report the numbers the
//! file will have: a vertical 1080 × 1920 timeline's "GIF default" is
//! 152 × 270, not 480 × 270. The fit is decided here, once; the writer
//! draws each frame at exactly this size and does not fit a second time.
//! It is also its own fixed point — a fitted size fed back as the box
//! fits to itself — because that is exactly what happens: the sheet and
//! the tool send a listed row's numbers back through `export_settings` as
//! `width` and `height`, and a fit that could move a derived edge by a
//! pixel on the second pass would show one size and write another.
//!
//! **Rows may repeat.** A 1920 × 1080 document's 1080p row IS the document
//! row, and on a 1080 × 1920 document every image-format row from 1080p up
//! is the document again. They are listed anyway, because an id is the
//! `export` tool's vocabulary and a request for `1080p` has to mean the
//! same thing on every document — refusing it exactly where it is a no-op
//! would be the popup's tidiness leaking into an API. The sheet hides a
//! row whose numbers an earlier row already has, so a person never sees one
//! size under two names, and the row that shows is the one whose name says
//! more ("Document size" over "1080p"). Rows larger than the document are
//! offered for a movie — they were before, as the 4K preset — because a
//! 720p screen recording exported at 4K for a platform that picks its
//! bitrate by resolution is a real request.

use serde_json::{Map, Value};

use crate::export;
use crate::model::Project;

/// The standard sizes, largest first, as (id, name, short edge). The id is
/// the `export` tool's vocabulary and the name is the popup's; they differ
/// only for 4K, which nobody calls 2160p out loud but which needs a
/// short-edge id to sit in the same vocabulary as the other three.
const STANDARD: [(&str, &str, u32); 4] = [
    ("2160p", "4K", 2160),
    ("1440p", "1440p", 1440),
    ("1080p", "1080p", 1080),
    ("720p", "720p", 720),
];

/// One row of the list, before it is JSON.
struct Row {
    id: &'static str,
    name: String,
    width: u32,
    height: u32,
}

impl Row {
    fn to_json(&self) -> Value {
        let mut out = Map::new();
        out.insert("id".to_string(), Value::from(self.id));
        out.insert("name".to_string(), Value::from(self.name.as_str()));
        out.insert("width".to_string(), Value::from(self.width));
        out.insert("height".to_string(), Value::from(self.height));
        Value::Object(out)
    }
}

impl Project {
    /// The sizes the export sheet offers for `preset_id` against this
    /// document, as the JSON array of `{id, name, width, height}` rows
    /// `rc_export_sizes` returns, in menu order — the first is the default.
    ///
    /// The rows:
    ///
    /// 1. `preset` — the format's cap, "GIF default" / "APNG default", for
    ///    the two rows of the table that carry one; nothing for the rest.
    /// 2. `document` — "Document size", the canvas as it is.
    /// 3. `2160p` ("4K"), `1440p`, `1080p`, `720p` — the short edge named,
    ///    the long edge fitted to the canvas and rounded to even.
    ///
    /// On an image format every row's numbers are the canvas fitted inside
    /// that row's box, never upscaled — the size the file will have. Rows
    /// may repeat an earlier row's numbers and are listed anyway (the
    /// module doc says why); the sheet hides the repeats.
    ///
    /// One list for every movie format, the audio-only row included: a
    /// width is reported for it the way `export_settings` reports one, and
    /// the sheet disables the control rather than this module keeping a
    /// second rule for one row. `Err` for an unknown preset, naming it —
    /// the same lookup and the same words as `export_settings`.
    pub fn export_sizes(&self, preset_id: &str) -> Result<Value, String> {
        let preset = export::preset(preset_id)?;
        let document = (self.canvas.width, self.canvas.height);
        let fits = preset.fits_inside_size();
        let sized = |(width, height): (u32, u32)| {
            if fits {
                fit_within(document, (width, height))
            } else {
                (width, height)
            }
        };

        let mut rows: Vec<Row> = Vec::new();
        if let Some(cap) = preset.size {
            // The codec in capitals is the format's name as people write
            // it — GIF, APNG — for the two rows that carry a cap.
            let (width, height) = sized(cap);
            rows.push(Row {
                id: "preset",
                name: format!("{} default", preset.codec.to_uppercase()),
                width,
                height,
            });
        }
        rows.push(Row {
            id: "document",
            name: "Document size".to_string(),
            width: document.0,
            height: document.1,
        });
        for (id, name, short) in STANDARD {
            let (width, height) = sized(fitted(document, short));
            rows.push(Row {
                id,
                name: name.to_string(),
                width,
                height,
            });
        }

        Ok(Value::Array(rows.iter().map(Row::to_json).collect()))
    }
}

/// The size whose short edge is `short`, in the aspect of a `width` ×
/// `height` document: the long edge is `short` × the document's long edge
/// over its short one, rounded to the nearest even integer with a tie
/// going up, on the axis the document is longer along. A square document
/// gives `short` × `short`.
fn fitted((width, height): (u32, u32), short: u32) -> (u32, u32) {
    let doc_long = u64::from(width.max(height));
    // `validate` refuses a zero edge; the `max` keeps the division total
    // regardless, since no input may panic.
    let doc_short = u64::from(width.min(height)).max(1);

    // The nearest even integer to short × doc_long / doc_short is twice
    // the nearest integer to half of it, and round(a / b) with a tie going
    // up is (2a + b) / 2b in integer division — here a = short × doc_long
    // and b = 2 × doc_short, so the whole thing is one division. u64
    // because a canvas need only be non-zero (`validate`), not inside
    // `set_canvas`'s 16..16384, so the product is not bounded by u32.
    let half = (u64::from(short) * doc_long + doc_short) / (2 * doc_short);
    // A canvas far outside those bounds can carry a ratio no u32 holds;
    // the row is then unusable, but a query must answer, and evenly.
    let long = u32::try_from(half * 2).unwrap_or(u32::MAX - 1);

    if width >= height {
        (long, short)
    } else {
        (short, long)
    }
}

/// A `width` × `height` canvas fitted inside a box: the canvas itself when
/// it already fits — never upscaled — and otherwise scaled down, aspect
/// kept, so that the edge which meets the box first takes the box's value
/// exactly and the other is the scaled value rounded UP to a whole pixel.
/// The rule an image format's size means (module doc), shared by
/// `export_settings` and [`Project::export_sizes`] so the two cannot
/// disagree about what a GIF will measure.
///
/// Up rather than to the nearest, so that the fit is its own fixed point.
/// Fitting the result again compares box × canvas products on the two
/// axes, and the derived edge — never below its exact value — keeps the
/// same axis limiting, whose derived edge is the same ceiling; rounded to
/// the nearest it can fall below the exact value, flip the limiting axis
/// on the second pass, and take a pixel off the other edge (a 3024 × 1964
/// recording's 1080p box, 1662 × 1080, came back 1662 × 1079 and then
/// 1661 × 1079). The ceiling never leaves the box: the limiting axis is
/// the one whose exact scaled value fits, and a whole number no smaller
/// than a value that fits inside a whole box edge fits too.
pub(crate) fn fit_within((width, height): (u32, u32), (box_w, box_h): (u32, u32)) -> (u32, u32) {
    if width <= box_w && height <= box_h {
        return (width, height);
    }
    let (w, h) = (u64::from(width).max(1), u64::from(height).max(1));
    let (bw, bh) = (u64::from(box_w).max(1), u64::from(box_h).max(1));
    // The width meets the box first when box_w / w ≤ box_h / h, which is
    // box_w × h ≤ box_h × w with no division to round.
    let (fw, fh) = if bw * h <= bh * w {
        (bw, ceil_div(h * bw, w))
    } else {
        (ceil_div(w * bh, h), bh)
    };
    let edge = |value: u64| u32::try_from(value).unwrap_or(u32::MAX).max(1);
    (edge(fw), edge(fh))
}

/// `a / b` rounded up to a whole number; `b ≥ 1`.
fn ceil_div(a: u64, b: u64) -> u64 {
    a.div_ceil(b)
}
