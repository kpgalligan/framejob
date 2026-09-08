//! Black-box tests for the export sizes — spec §7.8, driven through
//! `rc_export_sizes` exactly as the export sheet's Size popup and the
//! agent's `export` tool drive it.
//!
//! The oracle is arithmetic done by hand in the comment above each list —
//! never the short-edge rule written out a second time. Every document
//! below was chosen for what it makes the rule do: a 16:9 one where every
//! standard size is a familiar number, a vertical one where the short edge
//! is the WIDTH, an ultrawide and a 16:10 one whose own size collides with
//! a standard row, a square, and two whose aspect puts the long edge
//! between two integers.
//!
//! What the file is built to catch:
//!
//! 1. **The default.** The first row is the document for every movie
//!    format and the cap for the two image formats, whatever the document.
//! 2. **The short-edge rule.** The number names the short edge, the long
//!    edge follows the document, and a vertical document gets vertical
//!    rows.
//! 3. **Even rounding.** A long edge that is not a whole even number lands
//!    on the nearest even one, a tie going up, so the size the popup shows
//!    is the size the writer keeps; the document row is never rounded.
//! 4. **Repeats and the fit.** A row equal to an earlier row is listed all
//!    the same — the ids are an API — and on an image format every row is
//!    the canvas fitted inside the box, never upscaled, and is its own
//!    fit when sent back as a size.
//! 5. **One lookup.** An unknown preset — the old size-carrying ids among
//!    them — errors naming it, with the words `rc_export_settings` uses.
//! 6. **NULL.** A NULL project or preset is a message, not a crash.

mod common;

use std::ffi::c_char;
use std::ptr;

use serde_json::{json, Value};

use common::{assert_contains, cstring, int, take_string, text, Handle};
use reelcut_core::ffi_query::rc_export_sizes;

/// One row of the list as §7.8 describes it: an id the `export` tool
/// takes, a name the popup shows, and the pixels.
type Row = (String, String, i64, i64);

/// A row written out by hand.
fn row(id: &str, name: &str, width: i64, height: i64) -> Row {
    (id.to_string(), name.to_string(), width, height)
}

/// The movie formats, which all list the same sizes — the three
/// audio-only rows included, on the terms `rc_export_settings` reports a
/// width for them. Only the two image formats list anything else, and only
/// because they are the only rows carrying a cap.
const MOVIE_FORMATS: [&str; 6] = [
    "h264",
    "hevc",
    "prores_422",
    "audio_m4a",
    "audio_wav",
    "audio_aiff",
];

/// The sizes for `preset` against `handle` as the rows of the array, or
/// the message.
fn sizes(handle: &Handle, preset: &str) -> Result<Vec<Value>, String> {
    match handle.export_sizes(preset)? {
        Value::Array(rows) => Ok(rows),
        other => panic!("rc_export_sizes is not an array: {other}"),
    }
}

/// The list for `preset`, flattened so a whole list can be compared
/// against one written out by hand. Reading each row through `text` and
/// `int` is also the check that every row carries the four keys with the
/// types `ExportSize` in `ReelCore.swift` decodes. One thing every list
/// must satisfy is asserted here for all of them: no id twice — the tool
/// finds a row by id. A SIZE may appear twice (the module doc says why),
/// so that is not.
fn listed(handle: &Handle, preset: &str) -> Vec<Row> {
    let rows = match sizes(handle, preset) {
        Ok(rows) => rows,
        Err(msg) => panic!("{preset} was expected to list sizes, but: {msg}"),
    };
    let flat: Vec<Row> = rows
        .iter()
        .map(|row| {
            (
                text(row, "/id").to_string(),
                text(row, "/name").to_string(),
                int(row, "/width"),
                int(row, "/height"),
            )
        })
        .collect();
    for (i, later) in flat.iter().enumerate() {
        for earlier in &flat[..i] {
            assert_ne!(
                later.0, earlier.0,
                "{preset} lists the id {} twice",
                later.0
            );
        }
    }
    flat
}

/// The whole list, in order, against the one written by hand.
fn assert_list(handle: &Handle, preset: &str, want: &[Row]) {
    assert_eq!(listed(handle, preset), want, "{preset} sizes");
}

/// A canvas at 30 fps; the rate plays no part in a size.
fn document(width: u32, height: u32) -> Handle {
    Handle::new(width, height, 30, 1)
}

/// The same canvas with one ten-second clip on one track, for the test
/// that sends a size back through `rc_export_settings`, which refuses an
/// empty timeline before it looks at a size.
fn timeline(width: u32, height: u32) -> Handle {
    let second = 600_000;
    Handle::from_value(&json!({
        "version": 1,
        "canvas": {
            "width": width, "height": height, "fps": [30, 1],
            "background": [0, 0, 0, 1], "fit_new_clips": true, "timecode_frames": true
        },
        "media": [{
            "id": 1, "path": "/m/talk.mov", "kind": "video", "duration": 60 * second,
            "width": 1920, "height": 1080, "fps": [30, 1],
            "has_video": true, "has_audio": true
        }],
        "tracks": [{"id": 2, "name": "Track 1"}],
        "clips": [{
            "id": 3, "track": 2, "start": 0, "duration": 10 * second,
            "source": {"kind": "media", "media": 1, "in": 0}
        }],
        "next_id": 4
    }))
}

// ---- the default ---------------------------------------------------------

#[test]
fn the_first_row_is_the_document_for_every_movie_format() {
    // Three documents, one of them odd, to show the document row is the
    // canvas as it is.
    for (width, height) in [(1600, 900), (1080, 1920), (1000, 667)] {
        let handle = document(width, height);
        for preset in MOVIE_FORMATS {
            let rows = listed(&handle, preset);
            let first = rows
                .first()
                .unwrap_or_else(|| panic!("{preset} lists no sizes for {width} × {height}"));
            assert_eq!(
                *first,
                row(
                    "document",
                    "Document size",
                    i64::from(width),
                    i64::from(height)
                ),
                "{preset} on {width} × {height}"
            );
        }
    }
}

#[test]
fn the_image_formats_lead_with_their_cap_and_the_document_comes_second() {
    // The cap is the format's default whether the document is larger than
    // it or smaller: the row is the point of the format, not a ceiling that
    // applies only from above. The name is the format's, in capitals, and
    // says "default" rather than a number the popup appends anyway. The
    // NUMBERS are the canvas fitted inside the cap, the size the file will
    // have: 16:9 fills it exactly; 320 × 180 already fits and is not
    // upscaled; a vertical 1080 × 1920 meets the cap's height first, so
    // 270 tall and 1080 × 270 / 1920 = 151.875 → 152 wide for a GIF, and
    // 540 tall and 303.75 → 304 wide for an APNG.
    // A document and the numbers its GIF cap and its APNG cap resolve to.
    type Case = ((u32, u32), (i64, i64), (i64, i64));
    let cases: [Case; 3] = [
        ((1600, 900), (480, 270), (960, 540)),
        ((320, 180), (320, 180), (320, 180)),
        ((1080, 1920), (152, 270), (304, 540)),
    ];
    for ((width, height), gif_cap, apng_cap) in cases {
        let handle = document(width, height);
        let doc = row(
            "document",
            "Document size",
            i64::from(width),
            i64::from(height),
        );

        let gif = listed(&handle, "gif");
        assert_eq!(
            gif[0],
            row("preset", "GIF default", gif_cap.0, gif_cap.1),
            "gif on {width} × {height}"
        );
        assert_eq!(gif[1], doc, "gif on {width} × {height}");

        let apng = listed(&handle, "apng");
        assert_eq!(
            apng[0],
            row("preset", "APNG default", apng_cap.0, apng_cap.1),
            "apng on {width} × {height}"
        );
        assert_eq!(apng[1], doc, "apng on {width} × {height}");
    }
}

#[test]
fn the_audio_only_formats_list_what_h264_lists() {
    // One rule for every movie container; the sheet disables the control
    // for a file with no picture, the list does not pretend there is
    // nothing to disable. WAV and AIFF are here for the road map's own
    // words — the new rows come "with `audio_m4a`'s size rows" — which is
    // a claim about this list and is checked rather than assumed.
    for (width, height) in [(1600, 900), (1080, 1920), (480, 270)] {
        let handle = document(width, height);
        let h264 = listed(&handle, "h264");
        for preset in ["audio_m4a", "audio_wav", "audio_aiff", "hevc", "prores_422"] {
            assert_eq!(
                listed(&handle, preset),
                h264,
                "{preset} on {width} × {height}"
            );
        }
    }
}

// ---- the short-edge rule -------------------------------------------------

#[test]
fn a_16_9_document_gets_the_familiar_sizes() {
    // 1600 × 900 is 16:9, so every long edge is 16/9 of its short edge:
    // 2160 → 3840, 1440 → 2560, 1080 → 1920, 720 → 1280, all whole and
    // all even. Largest first, after the document, and no row equals the
    // document, so all four are listed.
    let handle = document(1600, 900);
    assert_list(
        &handle,
        "h264",
        &[
            row("document", "Document size", 1600, 900),
            row("2160p", "4K", 3840, 2160),
            row("1440p", "1440p", 2560, 1440),
            row("1080p", "1080p", 1920, 1080),
            row("720p", "720p", 1280, 720),
        ],
    );
}

#[test]
fn a_vertical_document_gets_vertical_rows() {
    // 1080 × 1920: the short edge is the WIDTH, so 720p is 720 wide and
    // 720 × 1920 / 1080 = 1280 tall, 1440p is 1440 × 2560 and 4K is
    // 2160 × 3840. The 1080p row is 1080 × 1920 — the document itself —
    // and is listed all the same: "1080p" means this on this document.
    let handle = document(1080, 1920);
    assert_list(
        &handle,
        "h264",
        &[
            row("document", "Document size", 1080, 1920),
            row("2160p", "4K", 2160, 3840),
            row("1440p", "1440p", 1440, 2560),
            row("1080p", "1080p", 1080, 1920),
            row("720p", "720p", 720, 1280),
        ],
    );
}

#[test]
fn the_number_is_the_short_edge_not_the_long_one() {
    // 2560 × 1080 is "1080p ultrawide": its 1080p row is 2560 × 1080,
    // which is the document, and the others keep the 2560 / 1080 =
    // 2.370… aspect on the long edge:
    //   2160 × 2.370… = 5120 exactly;
    //   1440 × 2.370… = 3413.3…, nearer 3414 than 3412;
    //    720 × 2.370… = 1706.6…, nearer 1706 than 1708.
    // Naming by the long edge would have made this document "2560p" and
    // offered a 1920 × 810 "1080p", which nobody means by the word.
    let handle = document(2560, 1080);
    assert_list(
        &handle,
        "h264",
        &[
            row("document", "Document size", 2560, 1080),
            row("2160p", "4K", 5120, 2160),
            row("1440p", "1440p", 3414, 1440),
            row("1080p", "1080p", 2560, 1080),
            row("720p", "720p", 1706, 720),
        ],
    );
}

#[test]
fn a_16_10_document_keeps_its_aspect() {
    // 1728 × 1080 is 16:10 (1.6): 720 × 1.6 = 1152, 1440 × 1.6 = 2304,
    // 2160 × 1.6 = 3456, every one whole and even; 1080 × 1.6 = 1728 is
    // the document. Nothing here is 16:9 — a rule that fitted to the
    // nearest broadcast aspect would show 1920 × 1080.
    let handle = document(1728, 1080);
    assert_list(
        &handle,
        "h264",
        &[
            row("document", "Document size", 1728, 1080),
            row("2160p", "4K", 3456, 2160),
            row("1440p", "1440p", 2304, 1440),
            row("1080p", "1080p", 1728, 1080),
            row("720p", "720p", 1152, 720),
        ],
    );
}

#[test]
fn a_square_document_gets_square_rows() {
    // Both edges are the short edge, so every row is S × S, and 1080p is
    // the document.
    let handle = document(1080, 1080);
    assert_list(
        &handle,
        "h264",
        &[
            row("document", "Document size", 1080, 1080),
            row("2160p", "4K", 2160, 2160),
            row("1440p", "1440p", 1440, 1440),
            row("1080p", "1080p", 1080, 1080),
            row("720p", "720p", 720, 720),
        ],
    );
}

// ---- even rounding -------------------------------------------------------

#[test]
fn the_long_edge_rounds_to_the_nearest_even_integer() {
    // 1000 × 667 is 1.4993…, an aspect no standard size divides:
    //   1080 × 1000 / 667 = 1619.19… → 1620 (1618 is 1.19 away, 1620 0.81);
    //   2160 × 1000 / 667 = 3238.38… → 3238 (0.38 away; 3240 is 1.62);
    //   1440 × 1000 / 667 = 2158.92… → 2158 (0.92 away; 2160 is 1.08);
    //    720 × 1000 / 667 = 1079.46… → 1080 (0.54 away; 1078 is 1.46).
    // The document row is the canvas as it is, odd height and all.
    let handle = document(1000, 667);
    assert_list(
        &handle,
        "h264",
        &[
            row("document", "Document size", 1000, 667),
            row("2160p", "4K", 3238, 2160),
            row("1440p", "1440p", 2158, 1440),
            row("1080p", "1080p", 1620, 1080),
            row("720p", "720p", 1080, 720),
        ],
    );
}

#[test]
fn a_long_edge_that_lands_on_an_odd_integer_goes_up() {
    // 1619 × 1080: its 1080p long edge is 1080 × 1619 / 1080 = 1619
    // exactly, an odd integer and so a tie between 1618 and 1620, which
    // goes up. That makes the row 1620 × 1080, which is NOT the document's
    // 1619 × 1080, so both are listed — the document row is never rounded,
    // or a 1619-wide document could not be exported at its own width. The
    // rest: 2160 × 1619 / 1080 = 3238 exactly; 1440 × 1619 / 1080 =
    // 2158.6…, nearer 2158 than 2160; 720 × 1619 / 1080 = 1079.3…, nearer
    // 1080 than 1078.
    let handle = document(1619, 1080);
    assert_list(
        &handle,
        "h264",
        &[
            row("document", "Document size", 1619, 1080),
            row("2160p", "4K", 3238, 2160),
            row("1440p", "1440p", 2158, 1440),
            row("1080p", "1080p", 1620, 1080),
            row("720p", "720p", 1080, 720),
        ],
    );
}

#[test]
fn a_tie_goes_up_not_to_the_even_half() {
    // 1619's tie was between 1618 and 1620 and half-to-even would also
    // pick 1620 (809.5 → 810), so it cannot tell the two rules apart.
    // 3242 × 2160 can: its 1080p long edge is 3242 / 2 = 1621 exactly,
    // and half of that is 810.5, which half-to-even rounds DOWN to 810
    // (→ 1620) and a tie going up rounds to 811 (→ 1622). The rest are
    // not ties: 1440 × 3242 / 2160 = 2161.3… → 2162 (2160 is 1.33 away,
    // 2162 0.67); 720 × 3242 / 2160 = 1080.6… → 1080 (0.67 away; 1082 is
    // 1.33); 4K is the document.
    let handle = document(3242, 2160);
    assert_list(
        &handle,
        "h264",
        &[
            row("document", "Document size", 3242, 2160),
            row("2160p", "4K", 3242, 2160),
            row("1440p", "1440p", 2162, 1440),
            row("1080p", "1080p", 1622, 1080),
            row("720p", "720p", 1080, 720),
        ],
    );
}

// ---- repeats -------------------------------------------------------------

#[test]
fn a_standard_row_equal_to_the_document_is_listed_all_the_same() {
    // 1920 × 1080 IS 1080p, and the row is there under both names: the id
    // has to exist on every document for the `export` tool, and it is the
    // sheet that hides one of the two.
    let handle = document(1920, 1080);
    assert_list(
        &handle,
        "h264",
        &[
            row("document", "Document size", 1920, 1080),
            row("2160p", "4K", 3840, 2160),
            row("1440p", "1440p", 2560, 1440),
            row("1080p", "1080p", 1920, 1080),
            row("720p", "720p", 1280, 720),
        ],
    );
    // 3840 × 2160 IS 4K, the largest row.
    let handle = document(3840, 2160);
    assert_list(
        &handle,
        "h264",
        &[
            row("document", "Document size", 3840, 2160),
            row("2160p", "4K", 3840, 2160),
            row("1440p", "1440p", 2560, 1440),
            row("1080p", "1080p", 1920, 1080),
            row("720p", "720p", 1280, 720),
        ],
    );
}

// ---- an image format's numbers are the file's --------------------------

#[test]
fn a_listed_image_size_sent_back_as_the_box_is_its_own_fit() {
    // The sheet and the tool send a listed row's numbers back through
    // rc_export_settings as width and height, so a row must fit to
    // itself. 3024 × 1964 is a 14-inch MacBook Pro screen recording,
    // whose aspect no standard size divides: its 1080p box is 1662 × 1080
    // (1080 × 3024 / 1964 = 1662.9…, nearest even 1662), and fitting the
    // canvas inside that box meets the width first — 1662 × 1964 =
    // 3 264 168 ≤ 1080 × 3024 = 3 265 920 — so the height is
    // 1964 × 1662 / 3024 = 1079.4…, which a nearest rounding would make
    // 1079 and a ceiling makes 1080. Sent back, 1662 × 1079 would have
    // flipped to height-limited and come out 1661 wide; 1662 × 1080 comes
    // back as itself.
    let handle = document(3024, 1964);
    let rows = listed(&handle, "gif");
    let row_1080p = rows.iter().find(|r| r.0 == "1080p").expect("no 1080p row");
    assert_eq!(*row_1080p, row("1080p", "1080p", 1662, 1080));

    // Every row of every image format, on documents of every aspect the
    // file uses, resolves to itself.
    for (width, height) in [
        (3024, 1964),
        (1000, 667),
        (1080, 1920),
        (2560, 1080),
        (1619, 1080),
    ] {
        let handle = timeline(width, height);
        for preset in ["gif", "apng"] {
            for (id, _, w, h) in listed(&handle, preset) {
                let again = handle
                    .export_settings(preset, Some(&json!({"width": w, "height": h})))
                    .unwrap_or_else(|msg| panic!("{preset} {id} on {width} × {height}: {msg}"));
                assert_eq!(
                    (int(&again, "/width"), int(&again, "/height")),
                    (w, h),
                    "{preset} {id} on {width} × {height} did not fit to itself"
                );
            }
        }
    }
}

#[test]
fn an_image_format_lists_what_the_file_will_measure() {
    // A vertical 1080 × 1920 document as a GIF. The cap fits the picture
    // to 152 × 270 (see the cap test). Every standard row from 1080p up
    // is a box the document already fits inside, and a GIF is never
    // upscaled, so each of those is the document again — listed, since
    // the ids must exist, and hidden by the sheet. 720p is the one
    // downscale: 720 × 1280 in the document's own aspect fits exactly.
    let handle = document(1080, 1920);
    assert_list(
        &handle,
        "gif",
        &[
            row("preset", "GIF default", 152, 270),
            row("document", "Document size", 1080, 1920),
            row("2160p", "4K", 1080, 1920),
            row("1440p", "1440p", 1080, 1920),
            row("1080p", "1080p", 1080, 1920),
            row("720p", "720p", 720, 1280),
        ],
    );
    // A 480 × 270 document as a GIF: it fits inside the cap and inside
    // every standard box, so every row is 480 × 270 and the popup shows
    // one row, "GIF default", the name that says more.
    let handle = document(480, 270);
    assert_list(
        &handle,
        "gif",
        &[
            row("preset", "GIF default", 480, 270),
            row("document", "Document size", 480, 270),
            row("2160p", "4K", 480, 270),
            row("1440p", "1440p", 480, 270),
            row("1080p", "1080p", 480, 270),
            row("720p", "720p", 480, 270),
        ],
    );
    // A 1920 × 1080 document as an APNG: the cap is a downscale to
    // 960 × 540; 4K and 1440p are boxes the document fits, so they are the
    // document; 1080p is the document; 720p is a downscale to 1280 × 720.
    let handle = document(1920, 1080);
    assert_list(
        &handle,
        "apng",
        &[
            row("preset", "APNG default", 960, 540),
            row("document", "Document size", 1920, 1080),
            row("2160p", "4K", 1920, 1080),
            row("1440p", "1440p", 1920, 1080),
            row("1080p", "1080p", 1920, 1080),
            row("720p", "720p", 1280, 720),
        ],
    );
    // The movie formats are not fitted: the same rows on the same
    // document are the boxes themselves.
    let h264 = listed(&handle, "h264");
    assert_eq!(h264[1], row("2160p", "4K", 3840, 2160));
}

// ---- one lookup ----------------------------------------------------------

#[test]
fn an_unknown_preset_errors_naming_it_with_the_settings_message() {
    let handle = document(1600, 900);
    // The old size-carrying ids are the likeliest unknowns: a script that
    // still says "h264_1080p" must be told, not handed the h264 list.
    for id in ["h265_8k", "h264_1080p", "hevc_4k", "h264_source", "H264"] {
        let msg = match sizes(&handle, id) {
            Err(msg) => msg,
            Ok(rows) => panic!("the unknown preset {id} listed sizes: {rows:?}"),
        };
        assert_contains(&msg, id);
        // Same lookup, same words: the sheet shows either verbatim, and a
        // person should not read two spellings of one mistake.
        let from_settings = match handle.export_settings(id, None) {
            Err(msg) => msg,
            Ok(value) => panic!("the unknown preset {id} resolved to {value}"),
        };
        assert_eq!(msg, from_settings, "{id}");
    }
}

// ---- NULL ----------------------------------------------------------------

#[test]
fn a_null_project_or_preset_is_a_message_not_a_crash() {
    let preset = cstring("h264");
    let mut err: *mut c_char = ptr::null_mut();
    assert!(unsafe { rc_export_sizes(ptr::null(), preset.as_ptr(), &mut err) }.is_null());
    assert_eq!(take_string(err).as_deref(), Some("project is NULL"));

    let live = document(1600, 900);
    let mut err: *mut c_char = ptr::null_mut();
    assert!(unsafe { rc_export_sizes(live.as_ptr(), ptr::null(), &mut err) }.is_null());
    assert_eq!(take_string(err).as_deref(), Some("preset_id is NULL"));

    // A NULL err_out is "swallow the message", never a write through NULL.
    assert!(unsafe { rc_export_sizes(ptr::null(), ptr::null(), ptr::null_mut()) }.is_null());
}
