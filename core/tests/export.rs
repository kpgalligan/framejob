//! Black-box tests for export preset resolution — spec §7.8, driven through
//! `rc_export_presets` and `rc_export_settings` exactly as the export sheet
//! and the agent's `export` tool drive them.
//!
//! The oracle is [`EXPECTED`]: the preset table written out a second time,
//! by hand, from what §7.8 says each row IS rather than from what
//! `export.rs` happens to hold. Both exports are checked against it, which
//! is the point of writing it twice — a preset that exists in the menu and
//! not in the resolver, or a row whose container and file type disagree,
//! fails here instead of at the save panel.
//!
//! What the file is built to catch:
//!
//! 1. **A preset that cannot be exported.** Every row of the menu resolves,
//!    and resolves to the row the menu advertised.
//! 2. **The two containers AVFoundation cannot write.** GIF and APNG carry
//!    no session preset, no audio and a capped size and rate; the null
//!    `avf_preset` is the only thing telling Swift to take the ImageIO path,
//!    so it is asserted as a null and not merely as "not an mp4 preset".
//! 3. **The bitrates.** They are overrides and nothing else: absent unless
//!    asked for, round-tripped exactly when they are, and refused — by a
//!    message naming the value — for anything that is not a positive whole
//!    number of bits per second.
//! 4. **The range.** Snapping happens on the EXPORT's frame grid, which the
//!    preset can now set: the same range resolves differently for a 30 fps
//!    movie preset and a 12.5 fps GIF. The tick arithmetic in every one of
//!    those assertions is worked out in the comment above it.
//! 5. **The documented permissiveness.** An override key this build does not
//!    know is ignored, and null means "use the preset".
//! 6. **The default.** The first row of the menu is what the export sheet
//!    opens on, and it has to export at the document's own size — a row
//!    with a size of its own put there by mistake would export every
//!    project at that size.
//! 7. **The size is an override.** A preset is an encoding and no movie
//!    row carries a size, so 1920 × 1080 comes from `width`/`height` — the
//!    way the sheet's Size popup and the tool's `size` reach the resolver —
//!    and each axis alone leaves the other the document's.
//! 8. **The two uncompressed audio rows.** WAV and AIFF are audio-only
//!    like M4A and carry a NON-NULL `avf_preset`, because null is the
//!    ImageIO writer's cue and a WAV handed to `ImageSequenceWriter` would
//!    be refused as an unknown image container — a format this table
//!    advertises failing with a GIF-shaped error. So the assertion here is
//!    the one the symptom would not give you: they are not image
//!    sequences.
//! 9. **The two loudness overrides.** `loudness_lufs` and `peak_dbtp`
//!    behave exactly as the bitrates do — absent unless asked for, echoed
//!    when they are, accepted by presets that cannot use them, refused by
//!    a message naming the value — with the single documented exception
//!    that a ceiling with no target is an error rather than an inert key.
//! 10. **The three rows with a fourth channel, and `alpha`.** The
//!     capability that says so is a fact about the ENCODING — true for
//!     `hevc_alpha`, `prores_4444` and `apng` and for nothing else, the same
//!     on a transparent canvas as on an opaque one, and not something an
//!     override can ask for — so the sweep is the whole table twice over
//!     rather than a check on the new row. `gif` is the row that makes the sweep worth
//!     writing: it shows a transparent pixel and still answers FALSE,
//!     because a palette index is not a channel. Beside it, the shape of a
//!     settings object is pinned key by key: the phase added ONE key, and
//!     a key that left with it would reach Swift as a silent default.
//! 11. **The header's list of overrides.** `rc_export_settings`' comment in
//!     `core/include/reelcut_core.h` enumerates every key it takes, and an
//!     FFI caller is entitled to trust it — so every key named there is
//!     read back out of the header and probed. Point 5's permissiveness is
//!     exactly what makes this necessary: a key the header names and
//!     nothing reads is dropped in silence, and the caller gets an export
//!     at settings they did not ask for, reported ok.
//!
//! The sizes the sheet offers are `core/tests/export_size.rs`.

mod common;

use serde_json::{json, Map, Value};

use common::{array, assert_contains, at, expect_string, flag, int, num, parse_json, text, Handle};
use reelcut_core::ffi_query::rc_export_presets;

/// One second in ticks (spec §5.1).
const SECOND: i64 = 600_000;

// ---- the oracle ----------------------------------------------------------

/// One preset as §7.8 describes it, independent of the table in
/// `core/src/export.rs`.
struct Expected {
    id: &'static str,
    container: &'static str,
    codec: &'static str,
    /// The fixed output size, or `None` for "whatever the project is" —
    /// every movie row, a preset being an encoding; the two image caps are
    /// the only `Some`.
    size: Option<(i64, i64)>,
    /// The fixed output rate, or `None` for "whatever the project is".
    fps: Option<(i64, i64)>,
    /// Whether the file carries pictures, and whether it can carry sound.
    video: bool,
    audio: bool,
    /// Whether the ENCODING carries a fourth channel. Written out here as
    /// a property of the ROW, which is the whole of §7.8's rule for it:
    /// nothing about a project can move it, so a table written from the
    /// spec can hold it and an oracle that had to know about a canvas
    /// could not.
    alpha: bool,
    /// The UTI of the file — `outputFileType` on the session path, the
    /// ImageIO destination type on the other, and the save panel's content
    /// type on both.
    file_type: &'static str,
    /// The `AVAssetExportSession` preset, or `None` when AVFoundation
    /// cannot write this container at all.
    avf_preset: Option<&'static str>,
}

/// The menu, in menu order: one row per encoding, and the ids are the
/// `export` tool's vocabulary. H.264 comes first because the first row is
/// the default (`first_preset_is_the_default_and_exports_at_the_document_size`)
/// and MP4/H.264 is the file everything plays; the three sound-only rows
/// sit together after the movies, and the two image formats come last:
/// they are the specialist rows, and everything above them is a file with
/// a timeline in it. The old size-carrying ids (`h264_1080p`, `hevc_4k`…)
/// are gone without aliases — `an_unknown_preset_errors_and_names_it`
/// pins that.
const EXPECTED: [Expected; 10] = [
    Expected {
        id: "h264",
        container: "mp4",
        codec: "h264",
        size: None,
        fps: None,
        video: true,
        audio: true,
        alpha: false,
        file_type: "public.mpeg-4",
        avf_preset: Some("AVAssetExportPresetHighestQuality"),
    },
    Expected {
        id: "hevc",
        container: "mp4",
        codec: "hevc",
        size: None,
        fps: None,
        video: true,
        audio: true,
        alpha: false,
        file_type: "public.mpeg-4",
        avf_preset: Some("AVAssetExportPresetHEVCHighestQuality"),
    },
    // HEVC with an alpha channel (spec §11 G-33): directly after `hevc`,
    // and everything `hevc` is except the three things that make it a
    // different file — a QuickTime movie rather than an MP4 (AVFoundation
    // writes HEVC with alpha into a `.mov` and refuses it an `.mp4`), a
    // codec name of its own, and the fourth channel.
    Expected {
        id: "hevc_alpha",
        container: "mov",
        codec: "hevc_alpha",
        size: None,
        fps: None,
        video: true,
        audio: true,
        alpha: true,
        file_type: "com.apple.quicktime-movie",
        avf_preset: Some("AVAssetExportPresetHEVCHighestQualityWithAlpha"),
    },
    Expected {
        id: "prores_422",
        container: "mov",
        codec: "prores422",
        size: None,
        fps: None,
        video: true,
        audio: true,
        alpha: false,
        file_type: "com.apple.quicktime-movie",
        avf_preset: Some("AVAssetExportPresetAppleProRes422LPCM"),
    },
    // The master row, and one of the three `alpha: true` rows. Everything
    // else about it is 422's — the same container, the same UTI, the same
    // "an editing master does not stream" answer to network optimization —
    // which is exactly why it is written out here beside 422 rather than
    // trusted: the pair differs in one field, and one field is what a
    // copy-pasted row loses.
    Expected {
        id: "prores_4444",
        container: "mov",
        codec: "prores4444",
        size: None,
        fps: None,
        video: true,
        audio: true,
        alpha: true,
        file_type: "com.apple.quicktime-movie",
        avf_preset: Some("AVAssetExportPresetAppleProRes4444LPCM"),
    },
    Expected {
        id: "audio_m4a",
        container: "m4a",
        codec: "aac",
        size: None,
        fps: None,
        video: false,
        audio: true,
        alpha: false,
        file_type: "com.apple.m4a-audio",
        avf_preset: Some("AVAssetExportPresetAppleM4A"),
    },
    // The two uncompressed rows: 16-bit LPCM at 48 kHz, the mix written
    // out rather than encoded, for handing to somebody else's tool. Their
    // UTIs are `AVFileType.wav` and `AVFileType.aiff`'s raw values, so
    // `Exporter.fileType(for:)` resolves them from `file_type` alone.
    //
    // The session preset is `audio_m4a`'s, and NOT because a WAV is an
    // M4A. AVFoundation has no `AVAssetExportPreset` for LPCM, and null in
    // that field is the one thing that routes an export to ImageIO, so a
    // null here would hand a WAV to the animated-GIF writer. §7.8 says the
    // name now means only "AVFoundation can write this row".
    Expected {
        id: "audio_wav",
        container: "wav",
        codec: "lpcm",
        size: None,
        fps: None,
        video: false,
        audio: true,
        alpha: false,
        file_type: "com.microsoft.waveform-audio",
        avf_preset: Some("AVAssetExportPresetAppleM4A"),
    },
    Expected {
        id: "audio_aiff",
        container: "aiff",
        codec: "lpcm",
        size: None,
        fps: None,
        video: false,
        audio: true,
        alpha: false,
        file_type: "public.aiff-audio",
        avf_preset: Some("AVAssetExportPresetAppleM4A"),
    },
    Expected {
        id: "gif",
        container: "gif",
        codec: "gif",
        // 480 × 270 at 12.5 fps: a palettised format whose cost is frames
        // times pixels, and whose frame delay is a whole number of
        // hundredths of a second — 12.5 fps is 8 of them exactly.
        size: Some((480, 270)),
        fps: Some((25, 2)),
        video: true,
        audio: false,
        alpha: false,
        file_type: "com.compuserve.gif",
        avf_preset: None,
    },
    Expected {
        id: "apng",
        container: "apng",
        codec: "apng",
        // An APNG is a PNG with animation chunks, so its type identifier is
        // PNG's — there is no separate APNG UTI to name.
        size: Some((960, 540)),
        fps: Some((25, 1)),
        video: true,
        audio: false,
        alpha: true,
        file_type: "public.png",
        avf_preset: None,
    },
];

// ---- fixtures ------------------------------------------------------------

/// The canvas every test resolves against: 1600 × 900 at 30 fps, chosen so
/// that "the project's own" is distinguishable from EVERY fixed value in
/// the table — no preset is 1600 × 900, none is 30 fps, and the two rows
/// that pin a rate pin 12.5 and 25.
const CANVAS_WIDTH: i64 = 1600;
const CANVAS_HEIGHT: i64 = 900;

/// Ten seconds of project, so a range has room to be clamped in both
/// directions.
const PROJECT_DURATION: i64 = 10 * SECOND;

/// A project with one ten-second clip on one track. Export settings are a
/// pure function of the canvas and the duration, so this is all the content
/// any test here needs.
fn project() -> Handle {
    project_with_background_alpha(1)
}

/// The same fixture with the canvas background at `alpha` — 1 opaque, 0
/// fully transparent. It exists for one claim and is used by one test:
/// `alpha` in the resolved settings is a fact about the ROW and never
/// about the document, so the two projects this builds must resolve every
/// preset to the same flag. Nothing else in export resolution reads the
/// background at all, which is why every other test takes the opaque one
/// without saying so.
fn project_with_background_alpha(alpha: i64) -> Handle {
    let handle = Handle::from_value(&json!({
        "version": 1,
        "canvas": {
            "width": CANVAS_WIDTH, "height": CANVAS_HEIGHT, "fps": [30, 1],
            "background": [0, 0, 0, alpha], "fit_new_clips": true, "timecode_frames": true
        },
        "media": [{
            "id": 1, "path": "/m/talk.mov", "kind": "video", "duration": 60 * SECOND,
            "width": 1920, "height": 1080, "fps": [30, 1],
            "has_video": true, "has_audio": true
        }],
        "tracks": [{"id": 2, "name": "Track 1"}],
        "clips": [{
            "id": 3, "track": 2, "start": 0, "duration": PROJECT_DURATION,
            "source": {"kind": "media", "media": 1, "in": 0}
        }],
        "next_id": 4
    }));
    assert_eq!(
        handle.duration(),
        PROJECT_DURATION,
        "the fixture's duration is what every range assertion clamps against"
    );
    handle
}

/// The settings for `preset`, asserting they resolved.
fn settings(handle: &Handle, preset: &str, overrides: Option<&Value>) -> Value {
    match handle.export_settings(preset, overrides) {
        Ok(value) => value,
        Err(msg) => panic!("{preset} was expected to resolve, but: {msg}"),
    }
}

/// The message from settings that were expected NOT to resolve.
fn refusal(handle: &Handle, preset: &str, overrides: &Value) -> String {
    match handle.export_settings(preset, Some(overrides)) {
        Err(msg) => msg,
        Ok(value) => panic!("{preset} with {overrides} was expected to error, but gave {value}"),
    }
}

/// The `[num, den]` rate a settings object or a preset row carries.
fn fps_of(value: &Value) -> (i64, i64) {
    (int(value, "/fps/0"), int(value, "/fps/1"))
}

/// The menu, exactly as `rc_export_presets` hands it to the picker. Called
/// through the FFI rather than through `presets()` so the test sees the
/// same bytes the app does.
fn preset_rows() -> Vec<Value> {
    let text = expect_string(unsafe { rc_export_presets() }, "rc_export_presets");
    match parse_json(&text, "rc_export_presets") {
        Value::Array(rows) => rows,
        other => panic!("rc_export_presets is not an array: {other}"),
    }
}

/// One override key with one value, for the tests that try a key against a
/// list of things it must refuse.
fn one(key: &str, value: Value) -> Value {
    let mut object = Map::new();
    object.insert(key.to_string(), value);
    Value::Object(object)
}

// ---- the menu ------------------------------------------------------------

#[test]
fn the_menu_is_the_table() {
    let rows = preset_rows();
    assert_eq!(
        rows.len(),
        EXPECTED.len(),
        "rc_export_presets offers {} presets, the table says {}",
        rows.len(),
        EXPECTED.len()
    );
    let mut names = std::collections::HashSet::new();
    for (row, want) in rows.iter().zip(EXPECTED.iter()) {
        let id = text(row, "/id");
        assert_eq!(id, want.id, "the menu is out of order at {id}");
        assert_eq!(text(row, "/container"), want.container, "{id} container");
        assert_eq!(text(row, "/codec"), want.codec, "{id} codec");
        assert_eq!(flag(row, "/video"), want.video, "{id} video");
        assert!(
            !text(row, "/name").is_empty(),
            "{id} has no name for the picker to show"
        );
        // Distinct, because `NSPopUpButton` drops an item whose title it
        // already has — a repeated name would shift every later row's
        // index and row 0 could stop meaning the table's first entry.
        assert!(
            names.insert(text(row, "/name").to_string()),
            "{id} repeats the name of an earlier row"
        );
        match want.size {
            Some((w, h)) => assert_eq!(
                (int(row, "/size/0"), int(row, "/size/1")),
                (w, h),
                "{id} size"
            ),
            None => assert!(
                at(row, "/size").is_null(),
                "{id} should size itself from the project, but the menu says {}",
                at(row, "/size")
            ),
        }
        match want.fps {
            Some((num, den)) => assert_eq!(fps_of(row), (num, den), "{id} rate"),
            None => assert!(
                at(row, "/fps").is_null(),
                "{id} should take the project's rate, but the menu says {}",
                at(row, "/fps")
            ),
        }
        match want.avf_preset {
            Some(name) => assert_eq!(text(row, "/avf_preset"), name, "{id} session preset"),
            None => assert!(
                at(row, "/avf_preset").is_null(),
                "{id} is written by ImageIO and must name no session preset, got {}",
                at(row, "/avf_preset")
            ),
        }
    }
}

/// The first row is what ⌘E exports without a choice being made — the sheet
/// opens on it — and the default export resolution is the document's own.
/// So the first row must carry no size (a fixed one would export a 1440p or
/// a vertical project at 1920 × 1080 by default), must be a movie, and must
/// resolve to the canvas exactly: 1600 × 900 here, a size no preset pins.
#[test]
fn first_preset_is_the_default_and_exports_at_the_document_size() {
    let rows = preset_rows();
    let first = rows.first().expect("rc_export_presets offers no preset");
    let id = text(first, "/id");
    // Present AND null: `Value`'s index reads an absent key as null too,
    // and a row that lost its `size` key would otherwise pass as unsized.
    assert!(
        matches!(first.get("size"), Some(Value::Null)),
        "the default preset {id} pins a size, or carries no size key"
    );
    assert!(
        flag(first, "/video"),
        "the default preset {id} has no video"
    );
    assert!(
        !text(first, "/name").is_empty(),
        "the default preset {id} has no name for the picker to show"
    );

    let out = settings(&project(), id, None);
    assert_eq!(
        (int(&out, "/width"), int(&out, "/height")),
        (CANVAS_WIDTH, CANVAS_HEIGHT),
        "the default export {id} is not at the document size"
    );
    assert_eq!(
        fps_of(&out),
        (30, 1),
        "the default export {id} is not at the document rate"
    );
}

#[test]
fn every_preset_in_the_menu_resolves_to_what_it_advertised() {
    let handle = project();
    for want in EXPECTED.iter() {
        let out = settings(&handle, want.id, None);
        assert_eq!(text(&out, "/preset"), want.id);
        assert_eq!(
            text(&out, "/container"),
            want.container,
            "{} container",
            want.id
        );
        assert_eq!(text(&out, "/codec"), want.codec, "{} codec", want.id);
        assert_eq!(
            text(&out, "/file_type"),
            want.file_type,
            "{} file type",
            want.id
        );
        assert_eq!(flag(&out, "/video"), want.video, "{} video", want.id);
        assert_eq!(flag(&out, "/audio"), want.audio, "{} audio", want.id);
        // The whole table, not three spot checks: a capability that is
        // true for one row is a claim about the other nine as much as
        // about that one, and `alpha` on a row with nowhere to put a
        // fourth channel would be reported to the sheet and the `export`
        // tool as a channel the file will carry.
        assert_eq!(flag(&out, "/alpha"), want.alpha, "{} alpha", want.id);

        let (w, h) = want.size.unwrap_or((CANVAS_WIDTH, CANVAS_HEIGHT));
        assert_eq!(
            (int(&out, "/width"), int(&out, "/height")),
            (w, h),
            "{} size",
            want.id
        );
        assert_eq!(
            fps_of(&out),
            want.fps.unwrap_or((30, 1)),
            "{} rate",
            want.id
        );

        match want.avf_preset {
            Some(name) => assert_eq!(text(&out, "/avf_preset"), name, "{} session", want.id),
            None => assert!(
                at(&out, "/avf_preset").is_null(),
                "{} must resolve to a null session preset, got {}",
                want.id,
                at(&out, "/avf_preset")
            ),
        }
        // Nothing asked for a bitrate, so nothing may claim one: an absent
        // key is what tells Swift to leave the encoder's own ladder alone.
        assert!(
            out.get("video_bitrate").is_none() && out.get("audio_bitrate").is_none(),
            "{} invented a bitrate nobody asked for: {out}",
            want.id
        );
        // Same rule, and the stakes are higher: an invented `loudness_lufs`
        // is not a bigger file, it is every export silently gain-changed.
        assert!(
            out.get("loudness_lufs").is_none() && out.get("peak_dbtp").is_none(),
            "{} invented a loudness target nobody asked for: {out}",
            want.id
        );
    }
}

#[test]
fn an_unknown_preset_errors_and_names_it() {
    let handle = project();
    // The old ids that carried a size are unknown now, with no alias: a
    // script still saying "h264_1080p" is told so rather than handed an
    // H.264 export at the document size it did not ask for.
    for id in [
        "h265_8k",
        "h264_1080p",
        "h264_720p",
        "h264_source",
        "hevc_1080p",
        "hevc_4k",
    ] {
        let msg = match handle.export_settings(id, None) {
            Err(msg) => msg,
            Ok(value) => panic!("the unknown preset {id} resolved to {value}"),
        };
        assert_contains(&msg, id);
    }
}

/// No movie row carries a size, so a fixed one is always an override —
/// the sheet's Size popup and the tool's `size` both arrive here as
/// `width`/`height` — and the two axes are independent: one alone leaves
/// the other the document's, rather than pulling a default in with it.
#[test]
fn a_size_override_is_how_a_movie_export_leaves_the_document_size() {
    let handle = project();
    for want in EXPECTED
        .iter()
        .filter(|want| want.video && want.size.is_none())
    {
        let both = settings(
            &handle,
            want.id,
            Some(&json!({"width": 1920, "height": 1080})),
        );
        assert_eq!(
            (int(&both, "/width"), int(&both, "/height")),
            (1920, 1080),
            "{} size override",
            want.id
        );

        let width_only = settings(&handle, want.id, Some(&json!({"width": 1280})));
        assert_eq!(
            (int(&width_only, "/width"), int(&width_only, "/height")),
            (1280, CANVAS_HEIGHT),
            "{} width alone",
            want.id
        );
        let height_only = settings(&handle, want.id, Some(&json!({"height": 720})));
        assert_eq!(
            (int(&height_only, "/width"), int(&height_only, "/height")),
            (CANVAS_WIDTH, 720),
            "{} height alone",
            want.id
        );
    }
}

// ---- ProRes 4444 and the alpha capability --------------------------------

/// The id exactly as the `export` tool and the Format popup spell it.
const PRORES_4444: &str = "prores_4444";

/// Every key a settings object carried BEFORE road map 2's phase 7 added
/// `alpha`, written out by hand.
///
/// It is the twelve of `every_settings_object_carries_every_key_swift_decodes`'
/// thirteen that predate the phase, written a second time and for a second
/// purpose: that test asks whether each key is PRESENT, and this one is the
/// other half of "the phase added exactly one key" — a claim about what is
/// ABSENT, which needs the whole set to make. The failure it catches is not
/// "`alpha` is missing" (the flag readers below catch that loudly) but
/// "`alpha` arrived and something else left with it", which nothing
/// downstream reports: `ExportSettings` in `ReelCore.swift` decodes a fixed
/// list of keys leniently, so a dropped or renamed one is a silent
/// Swift-side default rather than an error.
///
/// **The two lists stay separate whatever `CodingKeys` holds**, and the
/// reason is what each MEANS, not who has caught up with whom. That one is
/// the set a Swift-side decode must never find missing, and it grows with
/// every key Swift learns to read — `alpha` is in it, since
/// `ExportSettings` gained the case in this same phase. This one is frozen
/// at the pre-phase shape ON PURPOSE, because it is the base of an
/// EXACT-SET comparison: `alpha_is_the_only_key_the_settings_grew` appends
/// `"alpha"` to it and asserts equality, so a list that tracked Swift would
/// make the next phase's added key invisible to the very test written to
/// notice it. Do not merge them, and do not "update" this one when a
/// fourteenth key lands — a new phase writes its own base, or renames this
/// one. (`audio` and `video` are in the other list and are NOT in
/// `CodingKeys`, which is the same point from the other side:
/// the core emits them for the sheet's summary line and the `export`
/// tool's result, where the writer reads the composition's own tracks and
/// routes on `avf_preset`.)
const KEYS_BEFORE_ALPHA: [&str; 12] = [
    "audio",
    "avf_preset",
    "codec",
    "container",
    "file_type",
    "fps",
    "height",
    "optimize_for_network",
    "preset",
    "range",
    "video",
    "width",
];

/// The four keys that appear only when they were asked for — the two
/// bitrates and the two loudness figures. They are listed here so the
/// key-set assertion can be made twice: once with nothing asked for, where
/// none of them may appear, and once with all four, where exactly these
/// four join the rest and nothing else does.
const KEYS_WHEN_ASKED_FOR: [&str; 4] = [
    "audio_bitrate",
    "loudness_lufs",
    "peak_dbtp",
    "video_bitrate",
];

/// The keys of a settings object, sorted, for comparing whole shapes.
fn keys_of(value: &Value) -> Vec<String> {
    let object = value
        .as_object()
        .unwrap_or_else(|| panic!("the settings are not an object: {value}"));
    let mut keys: Vec<String> = object.keys().cloned().collect();
    keys.sort();
    keys
}

/// The two bitrates and the two loudness figures, all four asked for at
/// once, so the shape assertion below sees every optional key at the same
/// time. Every preset accepts all four (§7.8: one rule for reading
/// overrides, and the format flags say what the output can carry).
fn every_optional_override() -> Value {
    json!({
        "video_bitrate": 8_000_000,
        "audio_bitrate": 192_000,
        "loudness_lufs": -14.0,
        "peak_dbtp": -1.0
    })
}

/// The phase added ONE key to the resolved settings and moved nothing
/// else. Asserted for every row of the table and for both shapes a
/// settings object comes in — nothing asked for, and every optional key
/// asked for — so that the four conditional keys are pinned as
/// conditional in the same breath: absent when nobody asked, and exactly
/// those four when everybody did. [`KEYS_BEFORE_ALPHA`] says what the
/// comparison is against and why it is written out twice.
#[test]
fn alpha_is_the_only_key_the_settings_grew() {
    let handle = project();
    for want in EXPECTED.iter() {
        let mut plain: Vec<String> = KEYS_BEFORE_ALPHA.iter().map(|k| k.to_string()).collect();
        plain.push("alpha".to_string());
        plain.sort();
        assert_eq!(
            keys_of(&settings(&handle, want.id, None)),
            plain,
            "{}'s settings are not the pre-phase keys plus alpha",
            want.id
        );

        let mut full = plain.clone();
        full.extend(KEYS_WHEN_ASKED_FOR.iter().map(|k| k.to_string()));
        full.sort();
        assert_eq!(
            keys_of(&settings(
                &handle,
                want.id,
                Some(&every_optional_override())
            )),
            full,
            "{} with every optional override is not the same shape plus those four",
            want.id
        );
    }
}

/// Three rows carry a fourth channel and seven do not. The sweep is the
/// whole table rather than a spot check on three rows, because `alpha` is
/// a claim about every row at once: reported true on a row with nowhere to
/// put it, the export sheet and the `export` tool would both promise a
/// channel the file cannot hold, and nothing later in the pipeline is in a
/// position to notice — `ExporterWriter` writes what the codec writes.
///
/// The id list is written out here rather than read from [`EXPECTED`]'s
/// `alpha` field, so this is a second, independent statement of §7.8's
/// rule and not the oracle checked against itself.
///
/// **`apng` is in the list and `gif` is not**, which is the pair worth
/// pinning: both can show a transparent pixel, so a reader who has
/// exported one will read this list as an oversight in one direction or
/// the other. APNG has a real fourth channel and a pixel may be any
/// fraction of opaque; a GIF nominates ONE palette index as transparent
/// and has no partial value to store. Both readings were measured against
/// the built app before this list was written — an `apng` of a
/// transparent canvas decodes `pix_fmt=rgba` with its corner at alpha 0,
/// a `gif` of the same timeline has a hard-edged transparent index — and
/// the flag is what stops the sheet promising a translucent GIF.
///
/// The three are in the MENU's order, `hevc_alpha` first because it sits
/// directly after `hevc` (spec §11 G-33): the order is the table's, and a
/// row that moved would fail here as well as in
/// `hevc_alpha_sits_directly_after_hevc`.
#[test]
fn only_prores_4444_hevc_alpha_and_apng_carry_alpha() {
    let handle = project();
    let carrying: Vec<&str> = EXPECTED
        .iter()
        .map(|want| want.id)
        .filter(|id| flag(&settings(&handle, id, None), "/alpha"))
        .collect();
    assert_eq!(
        carrying,
        ["hevc_alpha", PRORES_4444, "apng"],
        "the rows claiming an alpha channel are not the three that have one"
    );

    // And the menu offers it, so the id above is reachable from the Format
    // popup and not only from a script that already knew the spelling.
    assert!(
        preset_rows()
            .iter()
            .any(|row| text(row, "/id") == PRORES_4444),
        "{PRORES_4444} resolves but is not in the menu"
    );
}

/// A MOV that AVFoundation writes, at the document's own size and rate.
///
/// The `avf_preset` assertion is the one whose symptom would not name it:
/// a null there is `ExportSettings`'s literal definition of an image
/// sequence, so a `prores_4444` row that carried one would be handed to
/// `ImageSequenceWriter`, met by an `ImageSequenceFormat(container: "mov")`
/// that has never heard of MOV, and reported as an unsupported file type
/// for a format the menu offers. GIF and APNG are checked beside it for
/// the reason the LPCM rows are: it keeps this an assertion about THIS row
/// rather than about the field having quietly stopped being nullable.
#[test]
fn prores_4444_is_a_mov_avfoundation_writes() {
    let handle = project();
    let out = settings(&handle, PRORES_4444, None);

    assert_eq!(text(&out, "/container"), "mov");
    assert_eq!(text(&out, "/file_type"), "com.apple.quicktime-movie");
    assert_eq!(
        text(&out, "/avf_preset"),
        "AVAssetExportPresetAppleProRes4444LPCM",
        "the ProRes 4444 row does not name AVFoundation's own preset for it"
    );
    for image in ["gif", "apng"] {
        assert!(
            at(&settings(&handle, image, None), "/avf_preset").is_null(),
            "{image} stopped naming the ImageIO path, so {PRORES_4444}'s check proves nothing"
        );
    }

    // A preset is an ENCODING: this row carries no size and no rate of its
    // own, so a master comes out at the document's, and a size override
    // reaches it unfitted — fitting is the image formats' rule.
    assert_eq!(
        (int(&out, "/width"), int(&out, "/height")),
        (CANVAS_WIDTH, CANVAS_HEIGHT)
    );
    assert_eq!(fps_of(&out), (30, 1));
    let sized = settings(
        &handle,
        PRORES_4444,
        Some(&json!({"width": 1920, "height": 1080})),
    );
    assert_eq!(
        (int(&sized, "/width"), int(&sized, "/height")),
        (1920, 1080)
    );
    // 422's posture, which 4444 shares: nothing streams an editing master,
    // so there is no `moov` atom worth moving to the front.
    assert!(!flag(&out, "/optimize_for_network"));
}

/// **`alpha` is the ENCODING's fact, never the canvas's** (§7.8, and the
/// decision the road map's own phase-7 sketch had the other way round).
/// One flat settings object is resolved for every row, so a flag that
/// answered "the background is translucent" would say `alpha: true` on an
/// H.264, a GIF and a WAV — three files with nowhere to put a fourth
/// channel — and would say `alpha: false` on a ProRes 4444 or an APNG
/// export of an opaque timeline, which carry the channel and simply have
/// nothing transparent in them this time.
///
/// So the same ten rows are resolved against two documents differing
/// ONLY in the background's alpha, and every flag has to be the same in
/// both. A build wired to the canvas fails on both halves of this at once.
#[test]
fn alpha_is_the_encodings_fact_and_never_the_canvas() {
    let opaque = project_with_background_alpha(1);
    let transparent = project_with_background_alpha(0);
    for want in EXPECTED.iter() {
        let on_opaque = flag(&settings(&opaque, want.id, None), "/alpha");
        let on_transparent = flag(&settings(&transparent, want.id, None), "/alpha");
        assert_eq!(
            on_opaque, on_transparent,
            "{}'s alpha moved with the canvas background",
            want.id
        );
        assert_eq!(
            on_opaque,
            want.id == "hevc_alpha" || want.id == PRORES_4444 || want.id == "apng",
            "{} on an opaque canvas",
            want.id
        );
    }
}

/// And it is not an override either. `alpha` is a capability the table
/// states, so a caller cannot ask for one: sending it is the unknown-key
/// case §7.8 documents (ignored, so a newer UI still gets an export), and
/// what must NOT happen is the value being honoured — `{"alpha": true}` on
/// an H.264 would promise a channel the file cannot hold, and
/// `{"alpha": false}` on a ProRes 4444 would deny one it will write
/// anyway.
#[test]
fn alpha_is_not_an_override() {
    let handle = project();
    assert!(
        !flag(
            &settings(&handle, "h264", Some(&one("alpha", json!(true)))),
            "/alpha"
        ),
        "h264 accepted an alpha channel it cannot write"
    );
    assert!(
        flag(
            &settings(&handle, PRORES_4444, Some(&one("alpha", json!(false)))),
            "/alpha"
        ),
        "{PRORES_4444} gave up the channel it writes because an override said so"
    );
}

// ---- HEVC with alpha (spec §11 G-33) -------------------------------------

/// The row as G-33 decided it, key by key: a QuickTime movie AVFoundation
/// writes, with sound, with the fourth channel, at the document's size and
/// rate, and NOT rewritten for network use unless somebody asks.
///
/// That last one is the assertion the container would not give you for
/// free. An HEVC-with-alpha movie is a delivery file — it is what a web
/// page plays over its own background — and the other delivery rows
/// default the flag on; this one is a `.mov`, whose default is off, and the
/// owner's choice was to leave it there. So the default is pinned as false
/// and the override as honoured, which is what makes "off by default" a
/// decision a test holds rather than a side effect of the container.
#[test]
fn hevc_alpha_is_a_mov_avfoundation_writes() {
    let handle = project();
    let out = settings(&handle, "hevc_alpha", None);

    assert_eq!(text(&out, "/preset"), "hevc_alpha");
    assert_eq!(text(&out, "/container"), "mov");
    assert_eq!(text(&out, "/file_type"), "com.apple.quicktime-movie");
    assert_eq!(text(&out, "/codec"), "hevc_alpha");
    assert_eq!(
        text(&out, "/avf_preset"),
        "AVAssetExportPresetHEVCHighestQualityWithAlpha",
        "the row does not name AVFoundation's own preset for HEVC with alpha"
    );
    assert!(flag(&out, "/video"), "hevc_alpha has no picture");
    assert!(flag(&out, "/audio"), "hevc_alpha carries no sound");
    assert!(flag(&out, "/alpha"), "hevc_alpha carries no alpha channel");
    assert!(
        !flag(&out, "/optimize_for_network"),
        "hevc_alpha is rewritten for network use by default"
    );
    assert_eq!(
        (int(&out, "/width"), int(&out, "/height")),
        (CANVAS_WIDTH, CANVAS_HEIGHT)
    );
    assert_eq!(fps_of(&out), (30, 1));
    assert!(
        out.get("video_bitrate").is_none(),
        "hevc_alpha invented a bit rate nobody asked for: {out}"
    );

    let asked = settings(
        &handle,
        "hevc_alpha",
        Some(&json!({"optimize_for_network": true, "video_bitrate": 6_000_000})),
    );
    assert!(
        flag(&asked, "/optimize_for_network"),
        "hevc_alpha ignored an asked-for network rewrite"
    );
    assert_eq!(
        int(&asked, "/video_bitrate"),
        6_000_000,
        "hevc_alpha did not echo the bit rate it was asked for"
    );
}

/// The Format popup lists the rows in the table's order, and G-33 put this
/// one directly after "HEVC (MP4)": the two HEVC rows read as a pair, the
/// one with the channel second.
#[test]
fn hevc_alpha_sits_directly_after_hevc() {
    let rows = preset_rows();
    let ids: Vec<&str> = rows.iter().map(|row| text(row, "/id")).collect();
    let hevc = ids
        .iter()
        .position(|id| *id == "hevc")
        .expect("the menu has no hevc row");
    assert_eq!(
        ids.get(hevc + 1).copied(),
        Some("hevc_alpha"),
        "the row after hevc is not hevc_alpha: {ids:?}"
    );
    assert_eq!(text(&rows[hevc + 1], "/name"), "HEVC with Alpha (MOV)");
}

/// Adding a row beside `hevc` must not move `hevc` (owner choice 12: the
/// existing row byte for byte as before). The literals below are what the
/// tree printed for the preset row and for its resolved settings — with
/// nothing asked for, and with every optional override — BEFORE the
/// `hevc_alpha` row was added, written out whole so that a key gained, lost
/// or changed on the old row fails here by name.
#[test]
fn the_hevc_row_is_what_it_was() {
    let row = preset_rows()
        .into_iter()
        .find(|row| text(row, "/id") == "hevc")
        .expect("the menu has no hevc row");
    assert_eq!(
        row,
        json!({
            "id": "hevc",
            "name": "HEVC (MP4)",
            "container": "mp4",
            "codec": "hevc",
            "video": true,
            "size": null,
            "fps": null,
            "avf_preset": "AVAssetExportPresetHEVCHighestQuality"
        })
    );

    let handle = project();
    assert_eq!(
        settings(&handle, "hevc", None),
        json!({
            "preset": "hevc",
            "avf_preset": "AVAssetExportPresetHEVCHighestQuality",
            "container": "mp4",
            "file_type": "public.mpeg-4",
            "codec": "hevc",
            "width": 1600,
            "height": 900,
            "fps": [30, 1],
            "range": {"start": 0, "duration": 6_000_000},
            "audio": true,
            "video": true,
            "alpha": false,
            "optimize_for_network": true
        })
    );
    assert_eq!(
        settings(&handle, "hevc", Some(&every_optional_override())),
        json!({
            "preset": "hevc",
            "avf_preset": "AVAssetExportPresetHEVCHighestQuality",
            "container": "mp4",
            "file_type": "public.mpeg-4",
            "codec": "hevc",
            "width": 1600,
            "height": 900,
            "fps": [30, 1],
            "video_bitrate": 8_000_000,
            "audio_bitrate": 192_000,
            "loudness_lufs": -14.0,
            "peak_dbtp": -1.0,
            "range": {"start": 0, "duration": 6_000_000},
            "audio": true,
            "video": true,
            "alpha": false,
            "optimize_for_network": true
        })
    );
}

// ---- the image formats ---------------------------------------------------

#[test]
fn the_image_formats_carry_no_session_and_no_sound() {
    let handle = project();
    for id in ["gif", "apng"] {
        let out = settings(&handle, id, None);
        assert!(
            at(&out, "/avf_preset").is_null(),
            "{id} named a session preset: {out}"
        );
        assert!(!flag(&out, "/audio"), "{id} claims it can hold audio");
        assert!(flag(&out, "/video"), "{id} must still carry pictures");
        // `shouldOptimizeForNetworkUse` is a movie-atom rewrite; there is
        // no atom to move in either format.
        assert!(
            !flag(&out, "/optimize_for_network"),
            "{id} asked for a moov-atom rewrite it has no moov atom for"
        );
    }
}

#[test]
fn the_image_formats_cap_the_size_and_the_rate_the_project_would_have_given() {
    let handle = project();
    // The fixture is 1600 × 900 at 30 fps, so every number below would be
    // the canvas's if the preset did not pin one.
    let gif = settings(&handle, "gif", None);
    assert_eq!((int(&gif, "/width"), int(&gif, "/height")), (480, 270));
    assert_eq!(fps_of(&gif), (25, 2));

    let apng = settings(&handle, "apng", None);
    assert_eq!((int(&apng, "/width"), int(&apng, "/height")), (960, 540));
    assert_eq!(fps_of(&apng), (25, 1));
}

/// On an image format a size is a box the picture is fitted inside, never
/// upscaled, and the settings report the FIT — the size the file will
/// have — for the cap and for an override alike, while a movie reports the
/// override exactly (the writer letterboxes to it). The fit itself is
/// `rc_export_sizes`'s rule, pinned in `export_size.rs`'s tests; here only
/// that `rc_export_settings` applies the same one.
#[test]
fn an_image_format_resolves_to_the_fit_not_the_box() {
    // A vertical 1080 × 1920 canvas on the 1600 × 900 fixture's project.
    let handle = project().apply(&json!({"op": "set_canvas", "width": 1080, "height": 1920}));
    let size = |value: &Value| (int(value, "/width"), int(value, "/height"));

    // The cap: 270 tall, 1080 × 270 / 1920 = 151.875 → 152 wide.
    assert_eq!(size(&settings(&handle, "gif", None)), (152, 270));
    // The same box asked for by hand is the same fit.
    assert_eq!(
        size(&settings(
            &handle,
            "gif",
            Some(&json!({"width": 480, "height": 270}))
        )),
        (152, 270)
    );
    // A box the canvas already fits inside is the canvas — never upscaled.
    assert_eq!(
        size(&settings(
            &handle,
            "gif",
            Some(&json!({"width": 4000, "height": 4000}))
        )),
        (1080, 1920)
    );
    // A movie is the box itself, letterboxed by the writer.
    assert_eq!(
        size(&settings(
            &handle,
            "h264",
            Some(&json!({"width": 480, "height": 270}))
        )),
        (480, 270)
    );
}

#[test]
fn an_override_still_beats_the_image_preset() {
    let handle = project();
    // The cap is a default, not a rule: a smaller box is honoured — the
    // 16:9 fixture fills 320 × 180 exactly — and so is a rate.
    let out = settings(
        &handle,
        "gif",
        Some(&json!({"width": 320, "height": 180, "fps": [10, 1]})),
    );
    assert_eq!((int(&out, "/width"), int(&out, "/height")), (320, 180));
    assert_eq!(fps_of(&out), (10, 1));
    // A bigger box is honoured too, up to the picture there is: an image
    // format is never upscaled, so "4K" on a 1600 × 900 timeline is the
    // timeline. That is the rule `an_image_format_resolves_to_the_fit_not_
    // the_box` pins; here only that the override reached it.
    let out = settings(
        &handle,
        "gif",
        Some(&json!({"width": 3840, "height": 2160})),
    );
    assert_eq!(
        (int(&out, "/width"), int(&out, "/height")),
        (CANVAS_WIDTH, CANVAS_HEIGHT)
    );
}

// ---- the uncompressed audio rows -----------------------------------------

/// The two ids exactly as the `export` tool and the Format popup spell
/// them.
const LPCM_ROWS: [&str; 2] = ["audio_wav", "audio_aiff"];

/// The defect this file exists to catch for these two rows, and the one
/// their symptom would not name: a null `avf_preset` is `ExportSettings`'s
/// literal definition of an image sequence, so a WAV row that carried one
/// would be handed to `ImageSequenceWriter`, refused by an
/// `ImageSequenceFormat(container: "wav")` that has never heard of WAV, and
/// reported as an unsupported file type for a format the menu offers. The
/// assertion is therefore on the null itself, in both the menu and the
/// resolved settings, and not on anything downstream of it.
#[test]
fn the_uncompressed_audio_rows_are_not_image_sequences() {
    let handle = project();
    let rows = preset_rows();
    for id in LPCM_ROWS {
        let row = rows
            .iter()
            .find(|row| text(row, "/id") == id)
            .unwrap_or_else(|| panic!("{id} is not in the menu"));
        assert!(
            !at(row, "/avf_preset").is_null(),
            "{id} carries a null session preset, which is Swift's cue to write it frame by \
             frame through ImageIO: {row}"
        );

        let out = settings(&handle, id, None);
        assert!(
            !at(&out, "/avf_preset").is_null(),
            "{id} resolves to a null session preset: {out}"
        );
        // The image rows are the ones a null belongs to, and they still
        // have it — so the assertion above is about these two rows and not
        // about the field having quietly stopped being nullable.
        for image in ["gif", "apng"] {
            assert!(
                at(&settings(&handle, image, None), "/avf_preset").is_null(),
                "{image} stopped naming the ImageIO path, so {id}'s check proves nothing"
            );
        }
    }
}

/// Sound and nothing else, on M4A's terms: `video: false`, `audio: true`,
/// and no `moov` atom to move — a RIFF or an IFF file is a header followed
/// by samples.
#[test]
fn the_uncompressed_audio_rows_carry_sound_and_no_picture() {
    let handle = project();
    for id in LPCM_ROWS {
        let out = settings(&handle, id, None);
        assert!(!flag(&out, "/video"), "{id} claims to carry pictures");
        assert!(flag(&out, "/audio"), "{id} claims it cannot hold sound");
        assert!(
            !flag(&out, "/optimize_for_network"),
            "{id} asked for a moov-atom rewrite it has no moov atom for"
        );
    }
}

/// A preset is an encoding, and these two carry no size of their own — so
/// they report the document's, the way `audio_m4a` does, and a size
/// override reaches them as it reaches every other row. (The Size popup's
/// own list for them is `core/tests/export_size.rs`, which sweeps them
/// beside `audio_m4a`.) The rate is the document's too: nothing about
/// LPCM caps a frame rate the file has no frames for.
#[test]
fn the_uncompressed_audio_rows_size_themselves_from_the_document() {
    let handle = project();
    let m4a = settings(&handle, "audio_m4a", None);
    for id in LPCM_ROWS {
        let out = settings(&handle, id, None);
        assert_eq!(
            (int(&out, "/width"), int(&out, "/height")),
            (CANVAS_WIDTH, CANVAS_HEIGHT),
            "{id} did not report the document size"
        );
        assert_eq!(fps_of(&out), fps_of(&m4a), "{id} rate");
        assert_eq!(
            int(&out, "/range/duration"),
            int(&m4a, "/range/duration"),
            "{id} length"
        );

        // A width is a request the sheet greys out and a script may still
        // send; it is honoured and never fitted, because fitting is the
        // image formats' rule and these rows are not image formats.
        let sized = settings(&handle, id, Some(&json!({"width": 1920, "height": 1080})));
        assert_eq!(
            (int(&sized, "/width"), int(&sized, "/height")),
            (1920, 1080),
            "{id} size override"
        );
    }
}

// ---- bitrates ------------------------------------------------------------

#[test]
fn the_bitrates_round_trip_exactly() {
    let handle = project();
    let out = settings(
        &handle,
        "h264",
        Some(&json!({"video_bitrate": 8_000_000, "audio_bitrate": 192_000})),
    );
    assert_eq!(int(&out, "/video_bitrate"), 8_000_000);
    assert_eq!(int(&out, "/audio_bitrate"), 192_000);

    // Each is independent of the other: asking for one must not summon a
    // default for the other, because there is no default to summon.
    let video_only = settings(&handle, "h264", Some(&json!({"video_bitrate": 12_000_000})));
    assert_eq!(int(&video_only, "/video_bitrate"), 12_000_000);
    assert!(
        video_only.get("audio_bitrate").is_none(),
        "a video bitrate pulled an audio one in with it: {video_only}"
    );

    let audio_only = settings(
        &handle,
        "audio_m4a",
        Some(&json!({"audio_bitrate": 256_000})),
    );
    assert_eq!(int(&audio_only, "/audio_bitrate"), 256_000);
    assert!(
        audio_only.get("video_bitrate").is_none(),
        "an audio bitrate pulled a video one in with it: {audio_only}"
    );
}

#[test]
fn a_null_bitrate_means_the_preset_decides() {
    let handle = project();
    // Null is the documented "leave this one alone" for every override, so
    // a sheet can send one object with the fields it does not set nulled.
    let out = settings(
        &handle,
        "hevc",
        Some(&json!({"video_bitrate": null, "audio_bitrate": null})),
    );
    assert_eq!(out, settings(&handle, "hevc", None));
}

#[test]
fn a_bitrate_that_is_not_a_positive_count_of_bits_errors() {
    let handle = project();
    // Zero is the interesting one: it is a number, it is the value a
    // stepper starts at, and it means "no data at all".
    for bad in [
        json!(0),
        json!(-1),
        json!(-8_000_000),
        json!(1.5),
        json!("8 Mbps"),
        json!([8_000_000]),
        json!({"value": 8_000_000}),
        json!(true),
        // One past u32::MAX — 4.3 Gbit/s is already an order of magnitude
        // past anything deliverable, so the ceiling is a real refusal and
        // not an accident of the type.
        json!(4_294_967_296u64),
    ] {
        for key in ["video_bitrate", "audio_bitrate"] {
            let msg = refusal(&handle, "h264", &one(key, bad.clone()));
            assert_contains(&msg, key);
            assert_contains(&msg, &bad.to_string());
        }
    }

    // And the top of the range is accepted, so the message above is about
    // the value and not about the bound being wrong.
    let out = settings(
        &handle,
        "h264",
        Some(&json!({"video_bitrate": 4_294_967_295u64})),
    );
    assert_eq!(int(&out, "/video_bitrate"), 4_294_967_295);
}

#[test]
fn a_bitrate_is_accepted_by_every_preset_that_cannot_use_one() {
    let handle = project();
    // The same permissiveness that reports a width for the audio-only row:
    // one rule for reading overrides, and the format flags say what the
    // output can carry. A GIF has no bitrate and an M4A has no picture,
    // and neither is a reason to refuse the export.
    let gif = settings(&handle, "gif", Some(&json!({"video_bitrate": 2_000_000})));
    assert_eq!(int(&gif, "/video_bitrate"), 2_000_000);
    assert!(!flag(&gif, "/audio"));

    let m4a = settings(
        &handle,
        "audio_m4a",
        Some(&json!({"video_bitrate": 2_000_000})),
    );
    assert_eq!(int(&m4a, "/video_bitrate"), 2_000_000);
    assert!(!flag(&m4a, "/video"));
}

// ---- loudness ------------------------------------------------------------

#[test]
fn the_loudness_overrides_round_trip_exactly() {
    let handle = project();
    // The three the sheet's popup offers and the ceiling it always sends,
    // plus a fractional target, which is the point of these being floats:
    // −14.5 LUFS is a real request and a bitrate-shaped integer check
    // would refuse it.
    for target in [-14.0, -16.0, -23.0, -14.5, -0.5] {
        let out = settings(
            &handle,
            "audio_wav",
            Some(&json!({"loudness_lufs": target, "peak_dbtp": -1.0})),
        );
        assert_eq!(num(&out, "/loudness_lufs"), target);
        assert_eq!(num(&out, "/peak_dbtp"), -1.0);
    }

    // A target alone is the common case — the ceiling is fixed in the
    // sheet — and must not summon a ceiling that was never asked for. It
    // is Swift that decides what an absent ceiling means, exactly as an
    // absent bitrate is the encoder's own ladder.
    let target_only = settings(&handle, "h264", Some(&json!({"loudness_lufs": -14.0})));
    assert_eq!(num(&target_only, "/loudness_lufs"), -14.0);
    assert!(
        target_only.get("peak_dbtp").is_none(),
        "a loudness target pulled a ceiling in with it: {target_only}"
    );

    // An integer target is a number like any other: JSON does not
    // distinguish -14 from -14.0 and neither may the reader.
    let whole = settings(&handle, "h264", Some(&json!({"loudness_lufs": -14})));
    assert_eq!(num(&whole, "/loudness_lufs"), -14.0);

    // Both bounds are inclusive, so the refusals below are about the value
    // and not about the bound being off by one.
    let edges = settings(
        &handle,
        "h264",
        Some(&json!({"loudness_lufs": -70.0, "peak_dbtp": -20.0})),
    );
    assert_eq!(num(&edges, "/loudness_lufs"), -70.0);
    assert_eq!(num(&edges, "/peak_dbtp"), -20.0);
    let top = settings(
        &handle,
        "h264",
        Some(&json!({"loudness_lufs": 0, "peak_dbtp": 0})),
    );
    assert_eq!(num(&top, "/loudness_lufs"), 0.0);
    assert_eq!(num(&top, "/peak_dbtp"), 0.0);
}

#[test]
fn a_null_loudness_target_means_no_normalisation() {
    let handle = project();
    // Null is the documented "leave this one alone" for every override, so
    // a sheet whose Loudness popup is on Off can send the key nulled — and
    // a null ceiling beside a null target must not trip the pairing rule.
    let out = settings(
        &handle,
        "audio_wav",
        Some(&json!({"loudness_lufs": null, "peak_dbtp": null})),
    );
    assert_eq!(out, settings(&handle, "audio_wav", None));
    assert!(out.get("loudness_lufs").is_none(), "{out}");
}

#[test]
fn a_loudness_figure_that_is_not_a_decibel_in_range_errors() {
    let handle = project();
    // Each key with the values it must refuse: past either end of its own
    // range, and every JSON type that is not a number. A bool is here
    // because `serde_json`'s `as_f64` is the only type check and it has to
    // be the one that catches it.
    for (key, bad) in [
        ("loudness_lufs", json!(-70.25)),
        ("loudness_lufs", json!(-999.5)),
        ("loudness_lufs", json!(0.25)),
        ("loudness_lufs", json!(12.5)),
        ("loudness_lufs", json!("-14 LUFS")),
        ("loudness_lufs", json!(true)),
        ("loudness_lufs", json!([-14.0])),
        ("loudness_lufs", json!({"target": -14.0})),
        ("peak_dbtp", json!(-20.25)),
        ("peak_dbtp", json!(-99.5)),
        ("peak_dbtp", json!(0.25)),
        ("peak_dbtp", json!(12.5)),
        ("peak_dbtp", json!("-1 dBTP")),
        ("peak_dbtp", json!(true)),
    ] {
        // A ceiling needs a target to be legal at all, so the bad ceilings
        // are sent with a good target: otherwise the pairing rule would
        // refuse them first and this test would prove nothing about the
        // range.
        let mut overrides = one(key, bad.clone());
        if key == "peak_dbtp" {
            overrides
                .as_object_mut()
                .expect("one() builds an object")
                .insert("loudness_lufs".to_string(), json!(-14.0));
        }
        let msg = refusal(&handle, "audio_wav", &overrides);
        assert_contains(&msg, key);
        assert_contains(&msg, &bad.to_string());
    }
}

/// The one place an override refuses because of what ANOTHER override
/// says, and the reason it is worth the exception: normalisation is
/// gain-only with no limiter, so the ceiling exists solely to cap a gain a
/// target computed. Asked for alone it would be accepted, echoed and
/// silently do nothing — the one failure shape this table has no
/// precedent for.
#[test]
fn a_peak_ceiling_with_no_target_is_refused_by_name() {
    let handle = project();
    let msg = refusal(&handle, "audio_wav", &json!({"peak_dbtp": -1.0}));
    assert_contains(&msg, "peak_dbtp");
    assert_contains(&msg, "loudness_lufs");

    // An explicitly null target is the same as an absent one everywhere
    // else, and is here too.
    let msg = refusal(
        &handle,
        "audio_wav",
        &json!({"peak_dbtp": -1.0, "loudness_lufs": null}),
    );
    assert_contains(&msg, "peak_dbtp");

    // And with a target it resolves, so the refusal is about the pairing
    // and not about the ceiling being unwelcome.
    let out = settings(
        &handle,
        "audio_wav",
        Some(&json!({"peak_dbtp": -1.0, "loudness_lufs": -16.0})),
    );
    assert_eq!(num(&out, "/peak_dbtp"), -1.0);
}

#[test]
fn a_loudness_target_is_accepted_by_every_preset_that_cannot_use_one() {
    let handle = project();
    // The bitrates' rule, and the same reason: one rule for reading
    // overrides, and the format flags say what the output can carry. A GIF
    // has no audio track to normalise, and that is `audio: false`'s job to
    // say — not this reader's.
    let gif = settings(&handle, "gif", Some(&json!({"loudness_lufs": -14.0})));
    assert_eq!(num(&gif, "/loudness_lufs"), -14.0);
    assert!(!flag(&gif, "/audio"));

    // And every row in the menu takes one, so the sheet may send the key
    // without asking which format is selected.
    for want in EXPECTED.iter() {
        let out = settings(
            &handle,
            want.id,
            Some(&json!({"loudness_lufs": -23.0, "peak_dbtp": -1.0})),
        );
        assert_eq!(num(&out, "/loudness_lufs"), -23.0, "{}", want.id);
        assert_eq!(num(&out, "/peak_dbtp"), -1.0, "{}", want.id);
    }
}

// ---- overrides in general ------------------------------------------------

#[test]
fn an_override_key_this_build_does_not_know_is_ignored() {
    let handle = project();
    let plain = settings(&handle, "h264", None);
    // Documented on `export_settings`: a newer UI may send fields this
    // build has never heard of, and must still get an export rather than
    // an error. `quality` is exactly the shape of the next such field.
    let out = settings(
        &handle,
        "h264",
        Some(&json!({"quality": "best", "bitrate": 8_000_000, "codec": "av1"})),
    );
    assert_eq!(out, plain);
}

/// The two readers phase 5's cut moved out of `export.rs` and into
/// `export_overrides.rs` with no test standing under them. Neither
/// behaviour is new; this exists so the move is provably not a change, and
/// so the next reader added beside them inherits a place to be checked.
#[test]
fn the_rate_and_the_network_flag_are_read_the_way_they_always_were() {
    let handle = project();

    // A rate is two non-zero terms and nothing else. A one-term array, a
    // three-term one, a zero either side and a bare number are all the
    // shapes a caller actually sends by mistake.
    for bad in [
        json!([30]),
        json!([30, 1, 1]),
        json!([0, 1]),
        json!([30, 0]),
        json!(30),
        json!("30"),
        json!({"num": 30, "den": 1}),
    ] {
        let msg = refusal(&handle, "h264", &one("fps", bad.clone()));
        assert_contains(&msg, "export fps");
        assert_contains(&msg, &bad.to_string());
    }
    // And a legal rate is taken, so the refusals are about the value.
    assert_eq!(
        fps_of(&settings(&handle, "h264", Some(&json!({"fps": [24, 1]})))),
        (24, 1)
    );

    // The network flag is a boolean, both ways, and overrides the
    // container's own default in both directions — MP4 defaults on, MOV
    // defaults off.
    for (preset, default) in [("h264", true), ("prores_422", false)] {
        assert_eq!(
            flag(&settings(&handle, preset, None), "/optimize_for_network"),
            default,
            "{preset} default"
        );
        for asked in [true, false] {
            let out = settings(
                &handle,
                preset,
                Some(&json!({"optimize_for_network": asked})),
            );
            assert_eq!(flag(&out, "/optimize_for_network"), asked, "{preset}");
        }
    }
    for bad in [json!("yes"), json!(1), json!(0), json!([true])] {
        let msg = refusal(&handle, "h264", &one("optimize_for_network", bad.clone()));
        assert_contains(&msg, "optimize_for_network");
        assert_contains(&msg, &bad.to_string());
    }
}

#[test]
fn a_malformed_overrides_object_errors() {
    let handle = project();
    for bad in [json!("width=800"), json!([800, 600]), json!(7)] {
        let msg = refusal(&handle, "h264", &bad);
        assert_contains(&msg, "json object");
    }
    // Absent and null both mean "no overrides".
    assert_eq!(
        settings(&handle, "h264", Some(&Value::Null)),
        settings(&handle, "h264", None)
    );
}

// ---- the range -----------------------------------------------------------

#[test]
fn the_range_snaps_to_the_export_rate_not_the_project_rate() {
    let handle = project();
    // 30 fps is 20 000 ticks a frame. A start of 50 000 is two and a half
    // frames in, and snapping rounds half away from zero, so it lands on
    // frame 3 = 60 000. A duration of 100 000 is five frames exactly.
    let movie = settings(
        &handle,
        "h264",
        Some(&json!({"range": {"start": 50_000, "duration": 100_000}})),
    );
    assert_eq!(int(&movie, "/range/start"), 60_000);
    assert_eq!(int(&movie, "/range/duration"), 100_000);

    // The same request as a GIF snaps to 12.5 fps = 48 000 ticks a frame:
    // 50 000 is a hair past frame 1 (48 000), and 100 000 is a hair past
    // frame 2 (96 000). Both round to the nearer boundary.
    let gif = settings(
        &handle,
        "gif",
        Some(&json!({"range": {"start": 50_000, "duration": 100_000}})),
    );
    assert_eq!(int(&gif, "/range/start"), 48_000);
    assert_eq!(int(&gif, "/range/duration"), 96_000);
}

#[test]
fn the_range_is_clamped_to_the_project_after_snapping() {
    let handle = project();

    // A start before zero is zero, and the duration that follows is the
    // whole project.
    let before = settings(
        &handle,
        "h264",
        Some(&json!({"range": {"start": -3 * SECOND}})),
    );
    assert_eq!(int(&before, "/range/start"), 0);
    assert_eq!(int(&before, "/range/duration"), PROJECT_DURATION);

    // A duration past the end is cut to what is left after the start.
    let long = settings(
        &handle,
        "h264",
        Some(&json!({"range": {"start": 2 * SECOND, "duration": 99 * SECOND}})),
    );
    assert_eq!(int(&long, "/range/start"), 2 * SECOND);
    assert_eq!(int(&long, "/range/duration"), PROJECT_DURATION - 2 * SECOND);

    // The default is the whole project on every preset, image formats
    // included — the cap is on size and rate, never on length.
    for want in EXPECTED.iter() {
        let out = settings(&handle, want.id, None);
        assert_eq!(int(&out, "/range/start"), 0, "{} start", want.id);
        assert_eq!(
            int(&out, "/range/duration"),
            PROJECT_DURATION,
            "{} duration",
            want.id
        );
    }
}

#[test]
fn a_range_that_resolves_to_nothing_is_refused() {
    let handle = project();

    // Half a frame at 30 fps rounds to zero.
    let msg = refusal(
        &handle,
        "h264",
        &json!({"range": {"start": 0, "duration": 9_000}}),
    );
    assert_contains(&msg, "empty");

    // A start at or past the end leaves no room for any duration.
    let msg = refusal(
        &handle,
        "h264",
        &json!({"range": {"start": PROJECT_DURATION}}),
    );
    assert_contains(&msg, "empty");
    let msg = refusal(
        &handle,
        "h264",
        &json!({"range": {"start": 99 * SECOND, "duration": SECOND}}),
    );
    assert_contains(&msg, "empty");

    // A range shorter than one GIF frame is empty AT 12.5 FPS while the
    // same range exports fine as a movie — the refusal is about the grid
    // the export writes on, and the message says which project it was
    // measured against.
    let msg = refusal(
        &handle,
        "gif",
        &json!({"range": {"start": 0, "duration": 20_000}}),
    );
    assert_contains(&msg, "empty");
    assert_contains(&msg, &PROJECT_DURATION.to_string());
    let movie = settings(
        &handle,
        "h264",
        Some(&json!({"range": {"start": 0, "duration": 20_000}})),
    );
    assert_eq!(int(&movie, "/range/duration"), 20_000);
}

#[test]
fn a_range_that_is_not_two_tick_counts_errors() {
    let handle = project();
    for bad in [
        json!({"range": "0..10"}),
        json!({"range": [0, 100]}),
        json!({"range": {"start": "0"}}),
        json!({"range": {"duration": 1.5}}),
    ] {
        let msg = refusal(&handle, "h264", &bad);
        assert_contains(&msg, "export range");
    }
}

// ---- what the resolver must never drop -----------------------------------

#[test]
fn every_settings_object_carries_every_key_swift_decodes() {
    let handle = project();
    // Every key `ExportSettings` in `app/Sources/ReelCore.swift` decodes,
    // and it decodes them leniently — a key that vanishes here becomes a
    // silent default there rather than a decode failure, which is how a
    // zero-length range once disabled the Export button. `alpha` (road map
    // 2's phase 7) is in the list because that type gained the
    // `CodingKeys` case for it in the same phase, and its lenient default
    // is FALSE: dropped here, it would reach the sheet as "no row can
    // carry alpha" — a wrong answer that looks like a working build.
    //
    // `audio` and `video` are the two the core emits that Swift does NOT
    // decode; they are guarded here anyway, because the export tool's
    // result and the sheet's summary line read them straight off this
    // object. [`KEYS_BEFORE_ALPHA`] is the sibling list and is deliberately
    // NOT this one — its doc says why the two must not be merged.
    const REQUIRED: [&str; 13] = [
        "preset",
        "avf_preset",
        "container",
        "file_type",
        "codec",
        "width",
        "height",
        "fps",
        "range",
        "audio",
        "video",
        "alpha",
        "optimize_for_network",
    ];
    for want in EXPECTED.iter() {
        let out = settings(&handle, want.id, None);
        for key in REQUIRED {
            assert!(
                out.get(key).is_some(),
                "{} resolved without {key}: {out}",
                want.id
            );
        }
        assert_eq!(
            array(&out, "/fps").len(),
            2,
            "{} rate is not [num, den]",
            want.id
        );
    }
}

// ---- the header's list of overrides --------------------------------------

/// The override keys the C header names, read out of the header itself.
///
/// The header is the contract — the three-file lockstep in the root
/// `CLAUDE.md` — so it, not a list written out again here, decides what
/// has to be readable. `model_tests.rs` reads the export NAMES out of it
/// for the null-safety sweep on the same principle.
///
/// The enumeration is the paragraph beginning "The overrides are", which
/// ends at the comment's next blank line; every backticked word in it is a
/// key. Nothing outside that paragraph is parsed, which is what lets the
/// sentence below it say there is no `size` key without the sentence being
/// read as declaring one.
fn override_keys_named_in_the_header() -> Vec<String> {
    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/include/reelcut_core.h");
    let header = std::fs::read_to_string(path).expect("the C header must be readable");

    let mut paragraph = String::new();
    for line in header
        .lines()
        .map(str::trim_start)
        .skip_while(|line| !line.contains("The overrides are"))
    {
        // ` *` alone is the blank line that ends the paragraph.
        let body = line.trim_start_matches('*').trim();
        if body.is_empty() {
            break;
        }
        paragraph.push_str(body);
        paragraph.push(' ');
    }
    assert!(
        paragraph.contains("The overrides are"),
        "rc_export_settings' comment no longer enumerates its overrides — \
         the paragraph beginning \"The overrides are\" is what this test reads"
    );

    let mut keys: Vec<String> = paragraph
        .split('`')
        .skip(1)
        .step_by(2)
        .map(str::to_string)
        .collect();
    keys.sort();
    keys.dedup();
    keys
}

/// Every key the header advertises is a key `export_settings` actually
/// reads. This exists because of rule 2 in `export_overrides.rs` — an
/// unknown key is dropped in SILENCE — which makes a wrong name in the
/// header the one failure the file's rules cannot report: an FFI caller
/// who spells a size the way the header told them to would get settings
/// that resolve, at the document's size, with `ok` and no message. So the
/// probe is a value no reader accepts: an `Err` naming the key proves
/// something read it, and an `Ok` proves nothing did.
#[test]
fn every_override_the_header_names_is_one_the_resolver_reads() {
    let handle = project();
    let keys = override_keys_named_in_the_header();
    assert!(
        keys.len() >= 8,
        "the header parse found only {} override keys, which cannot be right: {keys:?}",
        keys.len()
    );
    for key in &keys {
        let msg = refusal(&handle, "h264", &one(key, json!("not a legal value")));
        assert_contains(&msg, key);
    }
    // And the paragraph still names the keys a caller most needs, so a
    // parse that quietly found the wrong text cannot pass by finding
    // nothing wrong with it.
    for expected in ["width", "height", "fps", "range", "loudness_lufs"] {
        assert!(
            keys.iter().any(|key| key == expected),
            "the header no longer names {expected}, so this test is reading the wrong text: {keys:?}"
        );
    }
}
