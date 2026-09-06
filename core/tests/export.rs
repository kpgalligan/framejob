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

mod common;

use serde_json::{json, Map, Value};

use common::{array, assert_contains, at, expect_string, flag, int, parse_json, text, Handle};
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
    /// The fixed output size, or `None` for "whatever the project is".
    size: Option<(i64, i64)>,
    /// The fixed output rate, or `None` for "whatever the project is".
    fps: Option<(i64, i64)>,
    /// Whether the file carries pictures, and whether it can carry sound.
    video: bool,
    audio: bool,
    /// The UTI of the file — `outputFileType` on the session path, the
    /// ImageIO destination type on the other, and the save panel's content
    /// type on both.
    file_type: &'static str,
    /// The `AVAssetExportSession` preset, or `None` when AVFoundation
    /// cannot write this container at all.
    avf_preset: Option<&'static str>,
}

/// The menu, in menu order. The two image formats come last: they are the
/// specialist rows, and everything above them is a movie.
const EXPECTED: [Expected; 9] = [
    Expected {
        id: "h264_1080p",
        container: "mp4",
        codec: "h264",
        size: Some((1920, 1080)),
        fps: None,
        video: true,
        audio: true,
        file_type: "public.mpeg-4",
        avf_preset: Some("AVAssetExportPreset1920x1080"),
    },
    Expected {
        id: "h264_720p",
        container: "mp4",
        codec: "h264",
        size: Some((1280, 720)),
        fps: None,
        video: true,
        audio: true,
        file_type: "public.mpeg-4",
        avf_preset: Some("AVAssetExportPreset1280x720"),
    },
    Expected {
        id: "h264_source",
        container: "mp4",
        codec: "h264",
        size: None,
        fps: None,
        video: true,
        audio: true,
        file_type: "public.mpeg-4",
        avf_preset: Some("AVAssetExportPresetHighestQuality"),
    },
    Expected {
        id: "hevc_1080p",
        container: "mp4",
        codec: "hevc",
        size: Some((1920, 1080)),
        fps: None,
        video: true,
        audio: true,
        file_type: "public.mpeg-4",
        avf_preset: Some("AVAssetExportPresetHEVC1920x1080"),
    },
    Expected {
        id: "hevc_4k",
        container: "mp4",
        codec: "hevc",
        size: Some((3840, 2160)),
        fps: None,
        video: true,
        audio: true,
        file_type: "public.mpeg-4",
        avf_preset: Some("AVAssetExportPresetHEVC3840x2160"),
    },
    Expected {
        id: "prores_422",
        container: "mov",
        codec: "prores422",
        size: None,
        fps: None,
        video: true,
        audio: true,
        file_type: "com.apple.quicktime-movie",
        avf_preset: Some("AVAssetExportPresetAppleProRes422LPCM"),
    },
    Expected {
        id: "audio_m4a",
        container: "m4a",
        codec: "aac",
        size: None,
        fps: None,
        video: false,
        audio: true,
        file_type: "com.apple.m4a-audio",
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
    let handle = Handle::from_value(&json!({
        "version": 1,
        "canvas": {
            "width": CANVAS_WIDTH, "height": CANVAS_HEIGHT, "fps": [30, 1],
            "background": [0, 0, 0, 1], "fit_new_clips": true, "timecode_frames": true
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
    }
}

#[test]
fn an_unknown_preset_errors_and_names_it() {
    let handle = project();
    let msg = match handle.export_settings("h265_8k", None) {
        Err(msg) => msg,
        Ok(value) => panic!("an unknown preset resolved to {value}"),
    };
    assert_contains(&msg, "h265_8k");
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

#[test]
fn an_override_still_beats_the_image_preset() {
    let handle = project();
    // The cap is a default, not a rule: someone who wants a 4K GIF and
    // knows what that costs is allowed to ask for one.
    let out = settings(
        &handle,
        "gif",
        Some(&json!({"width": 3840, "height": 2160, "fps": [10, 1]})),
    );
    assert_eq!((int(&out, "/width"), int(&out, "/height")), (3840, 2160));
    assert_eq!(fps_of(&out), (10, 1));
}

// ---- bitrates ------------------------------------------------------------

#[test]
fn the_bitrates_round_trip_exactly() {
    let handle = project();
    let out = settings(
        &handle,
        "h264_1080p",
        Some(&json!({"video_bitrate": 8_000_000, "audio_bitrate": 192_000})),
    );
    assert_eq!(int(&out, "/video_bitrate"), 8_000_000);
    assert_eq!(int(&out, "/audio_bitrate"), 192_000);

    // Each is independent of the other: asking for one must not summon a
    // default for the other, because there is no default to summon.
    let video_only = settings(
        &handle,
        "h264_1080p",
        Some(&json!({"video_bitrate": 12_000_000})),
    );
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
        "hevc_1080p",
        Some(&json!({"video_bitrate": null, "audio_bitrate": null})),
    );
    assert_eq!(out, settings(&handle, "hevc_1080p", None));
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
            let msg = refusal(&handle, "h264_1080p", &one(key, bad.clone()));
            assert_contains(&msg, key);
            assert_contains(&msg, &bad.to_string());
        }
    }

    // And the top of the range is accepted, so the message above is about
    // the value and not about the bound being wrong.
    let out = settings(
        &handle,
        "h264_1080p",
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

// ---- overrides in general ------------------------------------------------

#[test]
fn an_override_key_this_build_does_not_know_is_ignored() {
    let handle = project();
    let plain = settings(&handle, "h264_720p", None);
    // Documented on `export_settings`: a newer UI may send fields this
    // build has never heard of, and must still get an export rather than
    // an error. `quality` is exactly the shape of the next such field.
    let out = settings(
        &handle,
        "h264_720p",
        Some(&json!({"quality": "best", "bitrate": 8_000_000, "codec": "av1"})),
    );
    assert_eq!(out, plain);
}

#[test]
fn a_malformed_overrides_object_errors() {
    let handle = project();
    for bad in [json!("width=800"), json!([800, 600]), json!(7)] {
        let msg = refusal(&handle, "h264_1080p", &bad);
        assert_contains(&msg, "json object");
    }
    // Absent and null both mean "no overrides".
    assert_eq!(
        settings(&handle, "h264_1080p", Some(&Value::Null)),
        settings(&handle, "h264_1080p", None)
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
        "h264_1080p",
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
        "h264_1080p",
        Some(&json!({"range": {"start": -3 * SECOND}})),
    );
    assert_eq!(int(&before, "/range/start"), 0);
    assert_eq!(int(&before, "/range/duration"), PROJECT_DURATION);

    // A duration past the end is cut to what is left after the start.
    let long = settings(
        &handle,
        "h264_1080p",
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
        "h264_1080p",
        &json!({"range": {"start": 0, "duration": 9_000}}),
    );
    assert_contains(&msg, "empty");

    // A start at or past the end leaves no room for any duration.
    let msg = refusal(
        &handle,
        "h264_1080p",
        &json!({"range": {"start": PROJECT_DURATION}}),
    );
    assert_contains(&msg, "empty");
    let msg = refusal(
        &handle,
        "h264_1080p",
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
        "h264_1080p",
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
        let msg = refusal(&handle, "h264_1080p", &bad);
        assert_contains(&msg, "export range");
    }
}

// ---- what the resolver must never drop -----------------------------------

#[test]
fn every_settings_object_carries_every_key_swift_decodes() {
    let handle = project();
    // `ExportSettings` in `app/Sources/ReelCore.swift` reads exactly these,
    // and reads them leniently — a key that vanishes here becomes a silent
    // default there rather than a decode failure, which is how a
    // zero-length range once disabled the Export button.
    const REQUIRED: [&str; 12] = [
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
