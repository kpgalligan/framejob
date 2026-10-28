//! The schema, the reader, and the time math — black box, over the FFI.
//!
//! What this file pins down:
//!
//! - every field of the spec §5.2 project schema survives a round trip
//!   through `rc_project_from_json` / `rc_project_to_json`, and a second
//!   round trip is byte-identical to the first;
//! - a project that omits every optional key gets the documented defaults;
//! - the reader's promise about keys it does not know (they are ignored,
//!   at every level except an action's opaque `end` patch);
//! - `format::read`'s version gate and every cap;
//! - every invariant `Project::validate` exists to catch;
//! - the timecode and frame-snapping tables, against values derived by hand
//!   in the comments — never against what the implementation happens to do;
//! - the NULL-safety sweep over EVERY export declared in
//!   `core/include/framejob_core.h`, with the list of exports read out of the
//!   header itself so a new export cannot quietly skip the sweep.

mod common;

use std::collections::BTreeSet;
use std::ffi::{c_char, c_void};
use std::ptr;

use serde_json::{json, Value};

use common::{array, assert_contains, at, cstring, expect_string, take_string, Handle};
use framejob_core::container::RcContainerSample;
use framejob_core::ffi::{
    rc_normalise_color, rc_project_clone, rc_project_free, rc_project_from_json, rc_project_new,
    rc_project_scoped, rc_project_to_json, rc_string_free, rc_time_snap_to_frame,
    rc_timecode_format, rc_timecode_parse,
};
use framejob_core::ffi_agent::{
    rc_agent_socket_release, rc_agent_socket_start, rc_agent_string_create,
};
use framejob_core::ffi_av1::{rc_av1_config, rc_av1_ftyp_brand, rc_av1_strip_temporal_delimiters};
use framejob_core::ffi_container::{
    rc_container_describe, rc_container_free, rc_container_open, rc_container_retime,
    rc_container_sample, rc_container_sample_count,
};
use framejob_core::ffi_cube::{rc_cube_copy_rgb, rc_cube_free, rc_cube_parse, rc_cube_size};
use framejob_core::ffi_edit::rc_project_apply;
use framejob_core::ffi_graphic::{
    rc_graphic_compile, rc_graphic_describe, rc_graphic_free, rc_graphic_image_cache,
    rc_graphic_library_add_asset, rc_graphic_library_add_font, rc_graphic_library_families,
    rc_graphic_library_free, rc_graphic_library_new, rc_graphic_rasterize, rc_graphic_svg,
};
use framejob_core::ffi_hdr10::{rc_hdr10_av1_peak, rc_hdr10_peak, rc_hdr10_still_peak};
use framejob_core::ffi_query::{
    rc_export_presets, rc_export_settings, rc_export_sizes, rc_op_names, rc_op_schemas,
    rc_project_clip_state, rc_project_composition_plan, rc_project_duration,
    rc_project_frame_recipe, rc_project_frame_recipe_opts, rc_project_snap_candidates,
    rc_project_source_map, rc_snap_resolve, rc_speed_limits,
};
use framejob_core::ffi_webm::{
    rc_webm_add_packet, rc_webm_end_track, rc_webm_finish, rc_webm_free, rc_webm_open,
};
use framejob_core::format::RC_FORMAT_VERSION;

/// Every `TransitionKind`, every `ShapeKind`, every `Curve` — the wire
/// spellings from spec §5.2. A variant added to the model without a line
/// here is a variant this file does not round-trip.
const TRANSITION_KINDS: [&str; 13] = [
    "cross_dissolve",
    "fade_black",
    "fade_white",
    "push_left",
    "push_right",
    "push_up",
    "push_down",
    "wipe",
    "slide",
    "zoom",
    "wipe_left",
    "wipe_up",
    "wipe_down",
];
const SHAPE_KINDS: [&str; 4] = ["rectangle", "ellipse", "line", "arrow"];
const FILTER_KINDS: [&str; 7] = [
    "blur", "sharpen", "pixelate", "sepia", "noir", "vignette", "invert",
];
const SPOT_SHAPES: [&str; 2] = ["rect", "ellipse"];
/// `ObscureKind`, format version 4. Both spellings are also `FilterKind`s,
/// which is why the sweep below looks INSIDE `video.obscure` for them
/// rather than trusting a search of the written text.
const OBSCURE_KINDS: [&str; 2] = ["blur", "pixelate"];
/// `BlendMode`, format version 6, in DECLARATION order — which is the
/// shader discriminant's order, so this list doubles as the statement of
/// it. `normal` is first and is 0.
const BLEND_MODES: [&str; 8] = [
    "normal",
    "multiply",
    "screen",
    "add",
    "overlay",
    "darken",
    "lighten",
    "difference",
];
/// `GradientKind`, format version 6. Both spellings are unique in the
/// written text, unlike the obscure kinds, so the sweep below can find
/// them by search.
const GRADIENT_KINDS: [&str; 2] = ["linear", "radial"];
/// `EdgeMotion`, format version 8. `spin` is also a `DuringMotion`, which
/// is why the sweep below reads the during kinds off the fixture rather
/// than searching the written text for them — `OBSCURE_KINDS`' problem
/// exactly, one version later.
const EDGE_MOTIONS: [&str; 9] = [
    "fade",
    "zoom_in",
    "zoom_out",
    "slide_left",
    "slide_right",
    "slide_up",
    "slide_down",
    "spin",
    "pop",
];
/// `DuringMotion`, format version 8.
const DURING_MOTIONS: [&str; 5] = ["pulse", "shake", "spin", "bounce", "drift"];
const CURVES: [&str; 4] = ["linear", "ease_in", "ease_out", "ease_in_out"];

// ---- the schema round trip -----------------------------------------------

/// A clip with every key of the schema present, for the generated sweeps to
/// specialize. Written out in full rather than defaulted: this file is a
/// test OF the defaults, so it may not lean on them.
fn base_clip(id: u64, track: u64, start: i64, duration: i64, source: Value) -> Value {
    json!({
        "id": id,
        "track": track,
        "start": start,
        "duration": duration,
        "source": source,
        "enabled": { "video": true, "audio": true },
        "speed": 1.0,
        "video": null,
        "audio": null,
        "text": null,
        "shape": null,
        "actions": [],
        "transition_in": null,
        "name": null,
        "label": null
    })
}

/// A project exercising every field, every `Source` variant, both states of
/// every nullable sub-object, and every variant of every enum in the model.
fn full_project() -> Value {
    // Clip 10: a media clip with every video and audio field set to a
    // NON-default value, so a field that silently fell back to its default
    // on read would fail the comparison rather than pass it by luck.
    let mut clip10 = base_clip(
        10,
        4,
        0,
        12_000_000,
        json!({ "kind": "media", "media": 1, "in": 3_000_000, "reversed": true }),
    );
    clip10["enabled"] = json!({ "video": true, "audio": false });
    clip10["speed"] = json!(1.5);
    clip10["name"] = json!("Talk");
    clip10["label"] = json!("blue");
    clip10["video"] = json!({
        "x": 120.5, "y": -64.25, "scale": 0.75, "rotation": 12.5, "opacity": 0.9,
        "crop": { "l": 10.0, "t": 20.0, "r": 30.0, "b": 40.0 },
        "corner_radius": 18.0,
        "shadow": { "color": [0.0, 0.0, 0.0, 1.0], "opacity": 0.5, "blur": 12.0,
                    "angle": 315.0, "distance": 8.0 },
        "color": { "brightness": 0.1, "contrast": -0.2, "saturation": 0.3, "hue": 45.0 },
        "chroma": { "key": [0.0, 1.0, 0.0], "tolerance": 0.2, "softness": 0.1, "spill": 0.5 },
        "filters": [
            { "kind": "blur", "amount": 0.25 },
            { "kind": "sharpen", "amount": 0.5 },
            { "kind": "pixelate", "amount": 0.75 },
            { "kind": "sepia", "amount": 1.0 }
        ],
        "reflection": { "opacity": 0.35, "height": 0.5, "gap": 4.0, "falloff": 0.8 },
        "spotlight": { "shape": "rect", "x": -20.0, "y": 30.0, "width": 480.0,
                       "height": 270.0, "feather": 40.0, "dim": 0.6, "zoom": 1.5 },
        "obscure": [
            { "shape": "ellipse", "x": -220.5, "y": 140.25, "width": 260.0,
              "height": 320.0, "feather": 36.0, "kind": "blur", "amount": 0.75 },
            { "shape": "rect", "x": 310.0, "y": -80.0, "width": 640.0,
              "height": 96.0, "feather": 0.0, "kind": "pixelate", "amount": 0.25 }
        ],
        "blend": "screen",
        "motion": {
            "in": { "kind": "slide_up", "duration": 300_000 },
            "out": { "kind": "zoom_out", "duration": 450_000 },
            "during": { "kind": "drift", "amount": 0.75, "period": 900_000 }
        }
    });
    clip10["audio"] = json!({
        "volume": 1.25, "muted": false, "fade_in": 300_000, "fade_out": 600_000,
        "duck": { "level": 0.2, "attack": 300_000, "release": 600_000 },
        "mono": true, "keep_pitch": false,
        "pan": -0.5, "noise_reduction": 0.25,
        "compressor": { "threshold_db": -24.0, "ratio": 4.0, "attack": 6000,
                        "release": 120_000, "makeup_db": 3.0 }
    });
    // One action per curve, laid out end to end inside the clip.
    let ends = [
        json!({ "video": { "opacity": 0.0 } }),
        json!({ "video": { "scale": 0.6, "x": 520.0 } }),
        json!({ "audio": { "volume": 0.5 } }),
        json!({ "video": { "rotation": 0.0 }, "audio": { "volume": 1.0 } }),
    ];
    clip10["actions"] = Value::Array(
        CURVES
            .iter()
            .zip(ends)
            .enumerate()
            .map(|(i, (curve, end))| {
                json!({
                    "id": 11 + i as u64,
                    "start": 1_200_000 * i as i64,
                    "duration": 600_000,
                    "curve": curve,
                    "end": end
                })
            })
            .collect(),
    );

    // Clip 20: a still, and the place `shadow` and `chroma` are null.
    let mut clip20 = base_clip(
        20,
        4,
        12_000_000,
        1_200_000,
        json!({ "kind": "still", "media": 1, "at": 9_000_000 }),
    );
    clip20["video"] = json!({
        "x": 0.0, "y": 0.0, "scale": 1.0, "rotation": 0.0, "opacity": 1.0,
        "crop": { "l": 0.0, "t": 0.0, "r": 0.0, "b": 0.0 },
        "corner_radius": 0.0,
        "shadow": null,
        "color": { "brightness": 0.0, "contrast": 0.0, "saturation": 0.0, "hue": 0.0 },
        "chroma": null,
        "filters": [],
        "reflection": null,
        "spotlight": null,
        "obscure": [],
        "blend": "normal",
        "motion": null
    });

    // Clip 21: an image, with the audio group absent (`null`) even though
    // the video group is present — the two are independent.
    let clip21 = base_clip(
        21,
        4,
        13_200_000,
        1_200_000,
        json!({ "kind": "image", "media": 3 }),
    );

    // Clips 22, 41, 42: text, covering every TextAlign and TextVAlign and
    // both states of `outline`, `backdrop` and `width`.
    let mut clip22 = base_clip(22, 5, 0, 3_000_000, json!({ "kind": "text" }));
    clip22["text"] = json!({
        "content": "Frame Job", "font": "SourceSans3-Bold", "size": 96.0,
        "color": [1.0, 0.9, 0.2, 1.0], "align": "left", "valign": "bottom",
        "line_spacing": 1.25, "tracking": 2.5,
        "outline": { "width": 2.0, "color": [0.0, 0.0, 0.0, 1.0] },
        "backdrop": { "color": [0.0, 0.0, 0.0, 0.6], "padding": 12.0, "radius": 8.0 },
        "width": 800.0
    });
    let mut clip41 = base_clip(41, 5, 3_000_000, 600_000, json!({ "kind": "text" }));
    clip41["text"] = json!({
        "content": "right / top", "font": "SourceSans3-SemiBold", "size": 72.0,
        "color": [1.0, 1.0, 1.0, 1.0], "align": "right", "valign": "top",
        "line_spacing": 1.0, "tracking": 0.0,
        "outline": null, "backdrop": null, "width": null
    });
    let mut clip42 = base_clip(42, 5, 3_600_000, 600_000, json!({ "kind": "text" }));
    clip42["text"] = json!({
        "content": "center / middle", "font": "SourceSans3-SemiBold", "size": 72.0,
        "color": [1.0, 1.0, 1.0, 1.0], "align": "center", "valign": "middle",
        "line_spacing": 1.0, "tracking": 0.0,
        "outline": null, "backdrop": null, "width": null
    });

    // Clips 23-26: one per ShapeKind. The ellipse leaves `stroke` null and
    // the line leaves `fill` null, so both nullable halves are covered.
    let shape_clips: Vec<Value> = SHAPE_KINDS
        .iter()
        .enumerate()
        .map(|(i, kind)| {
            let id = 23 + i as u64;
            let mut clip = base_clip(
                id,
                5,
                4_200_000 + 600_000 * i as i64,
                600_000,
                json!({ "kind": "shape" }),
            );
            clip["shape"] = json!({
                "kind": kind,
                "width": 320.0, "height": 120.0,
                "stroke": if *kind == "ellipse" {
                    Value::Null
                } else {
                    json!({ "width": 6.0, "color": [1.0, 1.0, 1.0, 1.0] })
                },
                "fill": if *kind == "line" {
                    Value::Null
                } else {
                    json!([0.2, 0.4, 0.8, 0.5])
                },
                "arrow_start": false, "arrow_end": true, "radius": 16.0,
                "from": [0.0, 1.0], "to": [1.0, 0.0],
                // The rectangle takes a linear gradient and the ellipse a
                // radial one, so both kinds round-trip; the line and the
                // arrow leave it null, so both halves of the option are
                // covered the way `stroke` and `fill` already are. Every
                // field is away from its default, stops included.
                "gradient": match *kind {
                    "rectangle" => json!({
                        "kind": "linear",
                        "stops": [
                            { "at": 0.0, "color": [1.0, 0.0, 0.0, 1.0] },
                            { "at": 0.25, "color": [1.0, 1.0, 0.0, 0.75] },
                            { "at": 1.0, "color": [0.0, 0.0, 1.0, 0.5] }
                        ],
                        "angle": 45.0
                    }),
                    "ellipse" => json!({
                        "kind": "radial",
                        "stops": [
                            { "at": 0.1, "color": [1.0, 1.0, 1.0, 1.0] },
                            { "at": 0.9, "color": [0.0, 0.0, 0.0, 0.0] }
                        ],
                        "angle": 0.0
                    }),
                    _ => Value::Null,
                }
            });
            clip
        })
        .collect();

    // Clips 30-39 and 88-90: one per TransitionKind.
    //
    // The generated id is `30 + i` for the first ten and jumps to 88 for the
    // three format version 7 appended, because `30 + i` would COLLIDE at
    // 40, 41 and 42 with the nest clip and the two text clips below. 88-90
    // are free; 91-104 are format version 8's motion sweep and `next_id` is
    // 105, so the next block starts at 105.
    let transition_clips: Vec<Value> = TRANSITION_KINDS
        .iter()
        .enumerate()
        .map(|(i, kind)| {
            let mut clip = base_clip(
                if i < 10 { 30 + i as u64 } else { 78 + i as u64 },
                4,
                20_000_000 + 600_000 * i as i64,
                600_000,
                json!({ "kind": "media", "media": 1, "in": 0 }),
            );
            clip["transition_in"] = json!({ "kind": kind });
            clip
        })
        .collect();

    // Clips 80-87: one per BlendMode. Eight modes and only three clips
    // above carry a video group, so the sweep needs a generated set of its
    // own — the same answer the transition kinds got, for the same reason.
    let blend_clips: Vec<Value> = BLEND_MODES
        .iter()
        .enumerate()
        .map(|(i, mode)| {
            let mut clip = base_clip(
                80 + i as u64,
                4,
                30_000_000 + 600_000 * i as i64,
                600_000,
                json!({ "kind": "image", "media": 3 }),
            );
            clip["video"] = json!({ "blend": mode });
            clip
        })
        .collect();

    // Clips 91-104: one per EdgeMotion as an `in`, then one per
    // DuringMotion as a `during`. Fourteen kinds across two enums and no
    // clip above carries a motion but clip 10, so the sweep needs a
    // generated set of its own — `blend_clips`' answer, for `blend_clips`'
    // reason. The `in` slot carries the edge kinds rather than `out`
    // because the two read the same nine spellings and one of them is
    // enough to cover the enum.
    let motion_clips: Vec<Value> =
        EDGE_MOTIONS
            .iter()
            .map(|kind| json!({ "in": { "kind": kind, "duration": 300_000 } }))
            .chain(DURING_MOTIONS.iter().map(
                |kind| json!({ "during": { "kind": kind, "amount": 0.5, "period": 600_000 } }),
            ))
            .enumerate()
            .map(|(i, motion)| {
                let mut clip = base_clip(
                    91 + i as u64,
                    4,
                    40_000_000 + 600_000 * i as i64,
                    600_000,
                    json!({ "kind": "image", "media": 3 }),
                );
                clip["video"] = json!({ "motion": motion });
                clip
            })
            .collect();

    // Clip 40: a nest, naming nest 60 by id — the format version 2 shape.
    let clip40 = base_clip(
        40,
        5,
        7_800_000,
        1_200_000,
        json!({ "kind": "nest", "project": 60 }),
    );

    // Clip 43: the filter kinds and the spotlight shape clip 10 did not
    // reach. Four filters is the cap, and there are seven kinds, so no one
    // clip can carry them all.
    let mut clip43 = base_clip(
        43,
        5,
        9_000_000,
        600_000,
        json!({ "kind": "image", "media": 3 }),
    );
    clip43["video"] = json!({
        "x": 0.0, "y": 0.0, "scale": 1.0, "rotation": 0.0, "opacity": 1.0,
        "crop": { "l": 0.0, "t": 0.0, "r": 0.0, "b": 0.0 },
        "corner_radius": 0.0, "shadow": null,
        "color": { "brightness": 0.0, "contrast": 0.0, "saturation": 0.0, "hue": 0.0 },
        "chroma": null,
        "filters": [
            { "kind": "noir", "amount": 1.0 },
            { "kind": "vignette", "amount": 0.4 },
            { "kind": "invert", "amount": 0.2 }
        ],
        "reflection": null,
        "spotlight": { "shape": "ellipse", "x": 0.0, "y": 0.0, "width": 320.0,
                       "height": 320.0, "feather": 0.0, "dim": 1.0, "zoom": 1.0 },
        "obscure": [],
        "blend": "difference"
    });

    let mut clips = vec![clip10, clip20, clip21, clip22, clip41, clip42, clip43];
    clips.extend(shape_clips);
    clips.extend(transition_clips);
    clips.extend(blend_clips);
    clips.extend(motion_clips);
    clips.push(clip40);

    json!({
        "version": RC_FORMAT_VERSION,
        "canvas": {
            "width": 1280, "height": 720, "fps": [30000, 1001],
            "background": [0.1, 0.2, 0.3, 1.0],
            "fit_new_clips": false, "timecode_frames": false
        },
        "media": [
            { "id": 1, "path": "/Users/x/talk.mov", "bookmark": "Ym9va21hcmsA",
              "kind": "video", "duration": 36_000_000, "width": 1920, "height": 1080,
              "fps": [30000, 1001], "has_video": true, "has_audio": true, "has_alpha": false },
            { "id": 2, "path": "/Users/x/music.m4a", "bookmark": null,
              "kind": "audio", "duration": 12_000_000, "width": 0, "height": 0,
              "fps": [30, 1], "has_video": false, "has_audio": true, "has_alpha": false },
            { "id": 3, "path": "/Users/x/logo.png", "bookmark": null,
              "kind": "image", "duration": 0, "width": 512, "height": 512,
              "fps": [30, 1], "has_video": true, "has_audio": false, "has_alpha": true }
        ],
        "tracks": [
            { "id": 4, "name": "Track 1", "hidden": false, "muted": false, "locked": false,
              "solo": false },
            { "id": 5, "name": "Overlay", "hidden": true, "muted": true, "locked": true,
              "solo": true }
        ],
        "clips": clips,
        "markers": [
            { "id": 50, "time": 6_000_000, "name": "Intro", "color": "red", "chapter": true },
            { "id": 51, "time": 12_000_000, "name": "", "color": "blue", "chapter": false }
        ],
        // Two nests, one inside the other: every id here lives in the same
        // number space as everything above it, which is the whole point of
        // the shape (`Nest` in model.rs).
        "nests": [
            {
                "id": 60, "name": "Intro", "width": 1280, "height": 720,
                "tracks": [
                    { "id": 61, "name": "Nested", "hidden": false,
                      "muted": false, "locked": false, "solo": false }
                ],
                "clips": [
                    base_clip(62, 61, 0, 1_200_000,
                              json!({ "kind": "media", "media": 1, "in": 0,
                                      "reversed": false })),
                    base_clip(63, 61, 1_200_000, 600_000,
                              json!({ "kind": "nest", "project": 70 }))
                ]
            },
            {
                "id": 70, "name": "Logo", "width": 640, "height": 360,
                "tracks": [
                    { "id": 71, "name": "Nested", "hidden": false,
                      "muted": false, "locked": false, "solo": false }
                ],
                "clips": [
                    base_clip(72, 71, 0, 600_000, json!({ "kind": "image", "media": 3 }))
                ]
            }
        ],
        "next_id": 105
    })
}

/// Asserts every path in `expected` survives into `actual` with an equal
/// value. Written as its own walk rather than `assert_eq!` on the two
/// values so the failure names the path, and so a number may cross the
/// int/float line (serde writes `1` for an f64 field holding 1.0).
fn assert_kept(expected: &Value, actual: &Value, path: &str) {
    match expected {
        Value::Object(fields) => {
            let got = actual
                .as_object()
                .unwrap_or_else(|| panic!("{path}: expected an object, the writer wrote {actual}"));
            for (key, value) in fields {
                let child = got
                    .get(key)
                    .unwrap_or_else(|| panic!("{path}/{key}: the round trip dropped this key"));
                assert_kept(value, child, &format!("{path}/{key}"));
            }
        }
        Value::Array(items) => {
            let got = actual
                .as_array()
                .unwrap_or_else(|| panic!("{path}: expected an array, the writer wrote {actual}"));
            assert_eq!(
                items.len(),
                got.len(),
                "{path}: the round trip changed the array length"
            );
            for (index, item) in items.iter().enumerate() {
                assert_kept(item, &got[index], &format!("{path}/{index}"));
            }
        }
        Value::Number(_) => {
            if let (Some(want), Some(got)) = (expected.as_i64(), actual.as_i64()) {
                assert_eq!(want, got, "{path}: the round trip changed this number");
            } else {
                assert_eq!(
                    expected.as_f64(),
                    actual.as_f64(),
                    "{path}: the round trip changed this number"
                );
            }
        }
        _ => assert_eq!(
            expected, actual,
            "{path}: the round trip changed this value"
        ),
    }
}

fn collect_keys(value: &Value, into: &mut BTreeSet<String>) {
    match value {
        Value::Object(fields) => {
            for (key, child) in fields {
                into.insert(key.clone());
                collect_keys(child, into);
            }
        }
        Value::Array(items) => items.iter().for_each(|item| collect_keys(item, into)),
        _ => {}
    }
}

#[test]
fn every_schema_field_round_trips() {
    let source = full_project();
    let first = Handle::from_value(&source).to_json();

    // Every key the test set is still in the written text...
    let mut keys = BTreeSet::new();
    collect_keys(&source, &mut keys);
    assert!(
        keys.len() > 60,
        "the fixture stopped covering the schema: only {} distinct keys",
        keys.len()
    );
    for key in &keys {
        assert!(
            first.contains(&format!("\"{key}\":")),
            "the written project has no {key:?} key"
        );
    }

    // ...with its value, at its path.
    let written = serde_json::from_str::<Value>(&first).expect("the writer emits valid json");
    assert_kept(&source, &written, "");

    // And the second trip is byte-identical to the first, which is what
    // lets Swift compare project strings at all.
    let second = Handle::from_json(&first).to_json();
    assert_eq!(first, second, "a second round trip changed the bytes");
}

#[test]
fn every_enum_variant_is_covered_by_the_round_trip() {
    // Guards the fixture itself: if a variant is added to the model and not
    // to the lists above, this fails before the round trip can pass by
    // simply never mentioning it.
    let handle = Handle::from_value(&full_project());
    let written = handle.to_json();
    for kind in TRANSITION_KINDS
        .iter()
        .chain(SHAPE_KINDS.iter())
        .chain(FILTER_KINDS.iter())
        .chain(OBSCURE_KINDS.iter())
    {
        assert_contains(&written, &format!("\"kind\": \"{kind}\""));
    }
    for shape in SPOT_SHAPES {
        assert_contains(&written, &format!("\"shape\": \"{shape}\""));
    }
    // `BlendMode` and `GradientKind`, format version 6. The blend is a key
    // of its own, so it is searched by key; a gradient's kind is spelled
    // `kind` like every other discriminant, and both of its spellings are
    // unique in the written text.
    for mode in BLEND_MODES {
        assert_contains(&written, &format!("\"blend\": \"{mode}\""));
    }
    for kind in GRADIENT_KINDS {
        assert_contains(&written, &format!("\"kind\": \"{kind}\""));
    }
    // `EdgeMotion` and `DuringMotion`, format version 8. Searching the text
    // would not do here for `OBSCURE_KINDS`' reason: `spin` is spelled in
    // BOTH enums, so a hit proves nothing about which of them the fixture
    // covers. The sweep reads the clips' own motion objects instead, which
    // is a claim about the FIXTURE and not about a substring of it.
    let project = handle.value();
    let motions: Vec<&Value> = array(&project, "/clips")
        .iter()
        .filter_map(|clip| clip.get("video").and_then(|video| video.get("motion")))
        .filter(|motion| !motion.is_null())
        .collect();
    for kind in EDGE_MOTIONS {
        assert!(
            motions
                .iter()
                .any(|motion| motion.pointer("/in/kind") == Some(&json!(kind))),
            "no clip in the fixture enters with a {kind}"
        );
    }
    for kind in DURING_MOTIONS {
        assert!(
            motions
                .iter()
                .any(|motion| motion.pointer("/during/kind") == Some(&json!(kind))),
            "no clip in the fixture moves with a {kind}"
        );
    }

    for curve in CURVES {
        assert_contains(&written, &format!("\"curve\": \"{curve}\""));
    }
    for kind in ["video", "audio", "image"] {
        assert_contains(&written, &format!("\"kind\": \"{kind}\""));
    }
    for source in ["media", "still", "text", "shape", "nest"] {
        assert_contains(&written, &format!("\"kind\": \"{source}\""));
    }
    for align in ["left", "center", "right", "top", "middle", "bottom"] {
        assert_contains(&written, &format!("\"{align}\""));
    }

    // One list cannot be guarded by searching the text at all: every
    // `ObscureKind` is also a `FilterKind`, and a region's `shape` is the
    // spotlight's own `SpotShape`, so the sweeps above find both spellings
    // whether or not the fixture hides a single region. The guard for
    // format version 4's list has to read the list itself.
    let regions = array(&project, "/clips/0/video/obscure");
    for kind in OBSCURE_KINDS {
        assert!(
            regions.iter().any(|region| region["kind"] == kind),
            "no region in the fixture is a {kind}"
        );
    }
    for shape in SPOT_SHAPES {
        assert!(
            regions.iter().any(|region| region["shape"] == shape),
            "no region in the fixture is a {shape}"
        );
    }
}

// ---- new, and clone ------------------------------------------------------

#[test]
fn a_new_project_is_the_documented_empty_project() {
    // One track, no media, no clips, and ids starting at 1 so 0 can mean
    // "none" on the Swift side.
    let project = Handle::new(1280, 720, 30000, 1001);
    assert_eq!(project.duration(), 0);
    assert_eq!(
        project.value(),
        json!({
            "version": RC_FORMAT_VERSION,
            "canvas": {
                "width": 1280, "height": 720, "fps": [30000, 1001],
                "background": [0.0, 0.0, 0.0, 1.0],
                "fit_new_clips": true, "timecode_frames": true
            },
            "media": [],
            "tracks": [{ "id": 1, "name": "Track 1", "hidden": false,
                         "muted": false, "locked": false, "solo": false }],
            "clips": [],
            "markers": [],
            "next_id": 2,
            "nests": []
        })
    );
}

#[test]
fn a_clone_is_an_independent_equal_project() {
    // Undo on the Swift side is a stack of these handles, so a copy must be
    // deep, equal, and must outlive the handle it came from.
    let original = Handle::from_value(&full_project());
    let json = original.to_json();
    let copy = original.duplicate();
    drop(original);
    assert_eq!(copy.to_json(), json, "the copy is not the same project");
}

// ---- defaults ------------------------------------------------------------

#[test]
fn an_empty_object_is_an_empty_project() {
    let project = Handle::from_json("{}").value();
    assert_eq!(
        project,
        json!({
            "version": RC_FORMAT_VERSION,
            "canvas": {
                "width": 1920, "height": 1080, "fps": [30, 1],
                "background": [0.0, 0.0, 0.0, 1.0],
                "fit_new_clips": true, "timecode_frames": true
            },
            "media": [],
            "tracks": [],
            "clips": [],
            "markers": [],
            "next_id": 1,
            "nests": []
        }),
        "an empty project object did not take the documented defaults"
    );
}

#[test]
fn omitted_optional_keys_take_the_documented_defaults() {
    // Only the defaultless keys: a clip's id/track/start/duration/source, a
    // media's id/path/kind, a track's id, a marker's id/time, an action's
    // id/start/duration.
    let project = Handle::from_value(&json!({
        "media": [{ "id": 4, "path": "/x.mov", "kind": "video" }],
        "tracks": [{ "id": 1 }],
        "clips": [{
            "id": 2, "track": 1, "start": 0, "duration": 600_000,
            "source": { "kind": "text" },
            "actions": [{ "id": 6, "start": 0, "duration": 600_000 }]
        }],
        "markers": [{ "id": 5, "time": 0 }],
        "next_id": 7
    }))
    .value();

    assert_eq!(at(&project, "/version"), &json!(RC_FORMAT_VERSION));
    // A file that never heard of nests reads as one with none, which is
    // what "every new field carries a serde default" buys.
    assert_eq!(at(&project, "/nests"), &json!([]));
    assert_eq!(
        at(&project, "/media/0"),
        &json!({
            "id": 4, "path": "/x.mov", "bookmark": null, "kind": "video",
            "duration": 0, "width": 0, "height": 0, "fps": [30, 1],
            "has_video": false, "has_audio": false, "has_alpha": false,
            "original": null
        }),
        "media defaults"
    );
    assert_eq!(
        at(&project, "/tracks/0"),
        &json!({ "id": 1, "name": "", "hidden": false, "muted": false, "locked": false,
                 "solo": false }),
        "track defaults"
    );
    assert_eq!(
        at(&project, "/markers/0"),
        // "red" is the spec §5.2 example's colour and the default the
        // `add_marker` row of the edit.rs op table documents, so a marker
        // read from a file that omitted the key has to match one the op
        // creates. It is a palette NAME the UI resolves, not a hex triple.
        &json!({ "id": 5, "time": 0, "name": "", "color": "red", "chapter": false }),
        "marker defaults"
    );
    assert_eq!(
        at(&project, "/clips/0"),
        &json!({
            "id": 2, "track": 1, "start": 0, "duration": 600_000,
            "source": { "kind": "text" },
            "enabled": { "video": true, "audio": true },
            "speed": 1.0,
            "video": null, "audio": null, "text": null, "shape": null, "graphic": null,
            "actions": [
                { "id": 6, "start": 0, "duration": 600_000, "curve": "linear", "end": {} }
            ],
            "transition_in": null,
            "name": null, "label": null
        }),
        "clip and action defaults"
    );
}

#[test]
fn empty_property_objects_take_the_documented_defaults() {
    // Each property group carries a container-level `#[serde(default)]`, so
    // `{}` is the whole group's default — the values in spec §5.2.
    let project = Handle::from_value(&json!({
        "tracks": [{ "id": 1 }],
        "clips": [
            { "id": 2, "track": 1, "start": 0, "duration": 600_000,
              "source": { "kind": "text" },
              "video": {}, "audio": {}, "text": {}, "shape": {} },
            { "id": 3, "track": 1, "start": 600_000, "duration": 600_000,
              "source": { "kind": "text" },
              "video": { "shadow": {}, "chroma": {}, "filters": [{}],
                         "reflection": {}, "spotlight": {} },
              "audio": { "duck": {}, "compressor": {} },
              "text": { "outline": {}, "backdrop": {} },
              "shape": { "stroke": {}, "gradient": {} } }
        ],
        "next_id": 4
    }))
    .value();

    assert_eq!(
        at(&project, "/clips/0/video"),
        &json!({
            "x": 0.0, "y": 0.0, "scale": 1.0, "rotation": 0.0, "opacity": 1.0,
            "crop": { "l": 0.0, "t": 0.0, "r": 0.0, "b": 0.0 },
            "corner_radius": 0.0, "shadow": null,
            "color": { "brightness": 0.0, "contrast": 0.0, "saturation": 0.0, "hue": 0.0 },
            "chroma": null,
            "filters": [], "reflection": null, "spotlight": null, "obscure": [],
            "blend": "normal", "motion": null
        }),
        "VideoProps defaults"
    );
    assert_eq!(
        at(&project, "/clips/0/audio"),
        &json!({
            "volume": 1.0, "muted": false, "fade_in": 0, "fade_out": 0,
            "duck": null, "mono": false, "keep_pitch": true,
            "pan": 0.0, "compressor": null, "noise_reduction": 0.0
        }),
        "AudioProps defaults"
    );
    assert_eq!(
        at(&project, "/clips/0/text"),
        &json!({
            "content": "", "font": "SourceSans3-SemiBold", "size": 72.0,
            "color": [1.0, 1.0, 1.0, 1.0], "align": "center", "valign": "middle",
            "line_spacing": 1.0, "tracking": 0.0,
            "outline": null, "backdrop": null, "width": null,
            "animation": null, "case": "as_written", "words": [], "word_style": null
        }),
        "TextProps defaults"
    );
    assert_eq!(
        at(&project, "/clips/0/shape"),
        &json!({
            "kind": "rectangle", "width": 320.0, "height": 120.0,
            "stroke": { "width": 6.0, "color": [1.0, 1.0, 1.0, 1.0] },
            "fill": null, "arrow_start": false, "arrow_end": false,
            "radius": 0.0, "from": [0.0, 1.0], "to": [1.0, 0.0],
            "gradient": null
        }),
        "ShapeProps defaults"
    );

    assert_eq!(
        at(&project, "/clips/1/video/shadow"),
        &json!({ "color": [0.0, 0.0, 0.0, 1.0], "opacity": 0.5, "blur": 12.0,
                 "angle": 315.0, "distance": 8.0 }),
        "Shadow defaults"
    );
    assert_eq!(
        at(&project, "/clips/1/video/chroma"),
        &json!({ "key": [0.0, 1.0, 0.0], "tolerance": 0.2, "softness": 0.1, "spill": 0.5 }),
        "Chroma defaults"
    );
    assert_eq!(
        at(&project, "/clips/1/video/reflection"),
        &json!({ "opacity": 0.35, "height": 0.5, "gap": 0.0, "falloff": 1.0 }),
        "Reflection defaults"
    );
    assert_eq!(
        at(&project, "/clips/1/video/spotlight"),
        &json!({ "shape": "rect", "x": 0.0, "y": 0.0, "width": 480.0, "height": 270.0,
                 "feather": 40.0, "dim": 0.6, "zoom": 1.0 }),
        "Spotlight defaults"
    );
    assert_eq!(
        at(&project, "/clips/1/video/filters/0"),
        &json!({ "kind": "blur", "amount": 0.5 }),
        "Filter defaults"
    );
    assert_eq!(
        at(&project, "/clips/1/audio/compressor"),
        // 10 ms attack and 200 ms release, in ticks at 600 000/s.
        &json!({ "threshold_db": -18.0, "ratio": 3.0, "attack": 6000,
                 "release": 120_000, "makeup_db": 0.0 }),
        "Compressor defaults"
    );
    assert_eq!(
        at(&project, "/clips/1/audio/duck"),
        &json!({ "level": 0.2, "attack": 300_000, "release": 600_000 }),
        "Duck defaults"
    );
    assert_eq!(
        at(&project, "/clips/1/text/outline"),
        &json!({ "width": 2.0, "color": [0.0, 0.0, 0.0, 1.0] }),
        "Outline defaults"
    );
    assert_eq!(
        at(&project, "/clips/1/text/backdrop"),
        &json!({ "color": [0.0, 0.0, 0.0, 0.6], "padding": 12.0, "radius": 8.0 }),
        "Backdrop defaults"
    );
    assert_eq!(
        at(&project, "/clips/1/shape/stroke"),
        &json!({ "width": 6.0, "color": [1.0, 1.0, 1.0, 1.0] }),
        "Stroke defaults"
    );
    assert_eq!(
        at(&project, "/clips/1/shape/gradient"),
        // Black to white, left to right: `{"gradient": {}}` is what the
        // inspector's Add and the most natural agent patch both send, so
        // this IS the feature's first impression rather than a formality.
        &json!({
            "kind": "linear",
            "stops": [
                { "at": 0.0, "color": [0.0, 0.0, 0.0, 1.0] },
                { "at": 1.0, "color": [1.0, 1.0, 1.0, 1.0] }
            ],
            "angle": 0.0
        }),
        "Gradient defaults"
    );
}

// ---- unknown keys --------------------------------------------------------

#[test]
fn unknown_keys_are_ignored_and_dropped_on_write() {
    // The promise (model.rs's module doc): unknown keys are IGNORED at
    // every level and are gone from the next write. Strictness lives in the
    // ops, where a person just typed the key.
    let written = Handle::from_value(&json!({
        "unknown_top_level": { "anything": true },
        "tracks": [{ "id": 1, "unknown_track_key": 1 }],
        "media": [{ "id": 7, "path": "/x.mov", "kind": "video", "unknown_media_key": 1 }],
        "markers": [{ "id": 8, "time": 0, "unknown_marker_key": 1 }],
        "clips": [{
            "id": 2, "track": 1, "start": 0, "duration": 600_000,
            "source": { "kind": "media", "media": 7, "in": 0, "unknown_source_key": 1 },
            "unknown_clip_key": "ignored",
            "video": { "scale": 0.5, "unknown_video_key": 1 },
            "audio": { "volume": 0.5, "unknown_audio_key": 1 },
            "actions": [{ "id": 3, "start": 0, "duration": 600_000,
                          "unknown_action_key": 1, "end": {} }]
        }],
        "next_id": 9
    }))
    .to_json();

    for key in [
        "unknown_top_level",
        "unknown_track_key",
        "unknown_media_key",
        "unknown_marker_key",
        "unknown_source_key",
        "unknown_clip_key",
        "unknown_video_key",
        "unknown_audio_key",
        "unknown_action_key",
    ] {
        assert!(
            !written.contains(key),
            "{key} survived the round trip; the reader promises to drop unknown keys"
        );
    }
    // The known neighbours of the ignored keys still arrived.
    let project: Value = serde_json::from_str(&written).expect("valid json");
    assert_eq!(at(&project, "/clips/0/video/scale"), &json!(0.5));
    assert_eq!(at(&project, "/clips/0/audio/volume"), &json!(0.5));
}

#[test]
fn an_action_end_patch_keeps_the_keys_it_is_given() {
    // The one exception, and it is deliberate: `end` is opaque JSON here,
    // merged and evaluated leniently by actions.rs. Losing a key on save
    // would silently change a project a NEWER build wrote — the file would
    // open, the animation it described would be gone, and the loss would be
    // written back over the original.
    //
    // This is the whole of that promise since D1·2 (kpgalligan/framejob#3):
    // the OP refuses `video.from_a_newer_build` by its path
    // (`edit_tests.rs`'s `set_action_end_merges_and_a_null_removes_a_key`),
    // and the reader below keeps the very same key through an open and a
    // save. Strictness at the op never costs a file.
    let project = Handle::from_value(&json!({
        "tracks": [{ "id": 1 }],
        "clips": [{
            "id": 2, "track": 1, "start": 0, "duration": 600_000,
            "source": { "kind": "text" },
            "actions": [{ "id": 3, "start": 0, "duration": 600_000,
                          "end": { "video": { "scale": 0.5, "from_a_newer_build": 1 },
                                   "not_a_property": 7 } }]
        }],
        "next_id": 4
    }))
    .value();
    assert_eq!(
        at(&project, "/clips/0/actions/0/end"),
        &json!({ "video": { "scale": 0.5, "from_a_newer_build": 1 },
                 "not_a_property": 7 })
    );
}

#[test]
fn an_unknown_source_kind_is_a_schema_error() {
    // `kind` is the discriminant, so an unknown one is not an unknown key:
    // there would be no way to guess what the clip shows.
    let msg = Handle::try_from_value(&json!({
        "tracks": [{ "id": 1 }],
        "clips": [{ "id": 2, "track": 1, "start": 0, "duration": 600_000,
                    "source": { "kind": "hologram" } }],
        "next_id": 3
    }))
    .expect_err("an unknown source kind must be refused");
    assert_contains(&msg, "project json does not match the schema");
    assert_contains(&msg, "hologram");
}

// ---- the reader: version and caps ----------------------------------------

#[test]
fn a_newer_format_version_is_refused_and_says_so() {
    // ONE PAST the current version, computed rather than written, so a bump
    // needs no edit here.
    let current = RC_FORMAT_VERSION;
    let future = current + 1;
    let msg = Handle::try_from_value(&json!({ "version": future }))
        .expect_err("a newer format version must be refused");
    assert_contains(
        &msg,
        &format!("version {future} is newer than this build understands"),
    );
    assert_contains(&msg, &format!("(version {current})"));
    assert_contains(&msg, "update Frame Job");

    // The gate reads the RAW json, so it has to cope with however the
    // writer that produced the file spelled the number. A version written
    // as a JSON float is the case that would otherwise slip past `as_u64`,
    // fall back to "current", and reach the user as a schema error about a
    // field this build has never heard of.
    // One past the current version again, written as a float.
    let msg = Handle::try_from_value(&json!({ "version": f64::from(future) }))
        .expect_err("a newer format version written as a float must be refused");
    assert_contains(
        &msg,
        &format!("version {future} is newer than this build understands"),
    );

    // A version that is not a number at all is named rather than ignored.
    let msg = Handle::try_from_value(&json!({ "version": "two" }))
        .expect_err("a non-numeric version must be refused");
    assert_contains(&msg, "project version must be a whole number");
}

#[test]
fn every_prior_version_is_accepted_and_the_writer_stamps_the_current_one() {
    // The reader's promise (spec §5.6): a file from an older build opens,
    // and what comes back out is the current version.
    for version in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] {
        assert_eq!(
            Handle::from_value(&json!({ "version": version })).value()["version"],
            json!(RC_FORMAT_VERSION),
            "version {version} did not read back as the current version"
        );
    }
    // Absent, the version defaults to current rather than to 0.
    assert_eq!(
        Handle::from_json("{}").value()["version"],
        json!(RC_FORMAT_VERSION)
    );
}

#[test]
fn malformed_json_names_itself() {
    let msg = Handle::try_from_json("{\"version\":").expect_err("truncated json must be refused");
    assert_contains(&msg, "project json is not valid json");
}

/// A project with exactly the requested number of each kind, ids handed out
/// in one sequence so `next_id` is always past every id.
fn sized_project(media: usize, tracks: usize, clips: usize, markers: usize) -> Value {
    // Ids run in one sequence — media, tracks, clips, markers — so they are
    // unique across kinds and `next_id` is past every one of them.
    let media_first = 1u64;
    let track_first = media_first + media as u64;
    let clip_first = track_first + tracks as u64;
    let marker_first = clip_first + clips as u64;

    let media_list: Vec<Value> = (0..media)
        .map(|i| {
            json!({ "id": media_first + i as u64, "path": format!("/tmp/{i}.mov"),
                    "kind": "video" })
        })
        .collect();
    let tracks_list: Vec<Value> = (0..tracks)
        .map(|i| json!({ "id": track_first + i as u64 }))
        .collect();
    let clips_list: Vec<Value> = (0..clips)
        .map(|i| {
            json!({
                "id": clip_first + i as u64, "track": track_first,
                "start": 600_000 * i as i64, "duration": 600_000,
                "source": { "kind": "text" }
            })
        })
        .collect();
    let markers_list: Vec<Value> = (0..markers)
        .map(|i| json!({ "id": marker_first + i as u64, "time": 600_000 * i as i64 }))
        .collect();
    json!({
        "media": media_list,
        "tracks": tracks_list,
        "clips": clips_list,
        "markers": markers_list,
        "next_id": marker_first + markers as u64
    })
}

#[test]
fn every_cap_is_enforced_and_the_message_names_it() {
    // The caps are RC_MAX_CLIPS / RC_MAX_TRACKS / RC_MAX_MARKERS in the
    // header (plus MAX_MEDIA, which has no header define). One over each.
    let cases = [
        (
            sized_project(0, 1, 4097, 0),
            "too many clips: 4097 (max 4096)",
        ),
        (sized_project(0, 65, 0, 0), "too many tracks: 65 (max 64)"),
        (
            sized_project(0, 1, 0, 1025),
            "too many markers: 1025 (max 1024)",
        ),
        (
            sized_project(1025, 1, 0, 0),
            "too many media: 1025 (max 1024)",
        ),
    ];
    for (project, expected) in cases {
        let msg =
            Handle::try_from_value(&project).expect_err("an over-cap project must be refused");
        assert_eq!(msg, expected);
    }
}

#[test]
fn a_project_at_every_cap_still_reads() {
    // The boundary is inclusive: the writer enforces the reader's caps, so
    // a file sitting exactly ON them must survive a save and reopen.
    let project = Handle::from_value(&sized_project(1024, 64, 4096, 1024));
    let value = project.value();
    assert_eq!(value["media"].as_array().map(Vec::len), Some(1024));
    assert_eq!(value["tracks"].as_array().map(Vec::len), Some(64));
    assert_eq!(value["clips"].as_array().map(Vec::len), Some(4096));
    assert_eq!(value["markers"].as_array().map(Vec::len), Some(1024));
    // Reopening what was just written must also work.
    Handle::from_json(&project.to_json());
}

// ---- validate ------------------------------------------------------------

/// The message `rc_project_from_json` reports for a project that parses but
/// breaks an invariant.
fn refusal(project: Value) -> String {
    Handle::try_from_value(&project).expect_err("this project must be refused")
}

#[test]
fn validate_catches_an_unusable_canvas() {
    // `composition_plan` publishes the canvas verbatim as `render_size` and
    // `frame()` derives the frame grid from the rate, so a canvas with a
    // zero dimension or a degenerate rate is a project that parses and then
    // produces a plan AVFoundation cannot build from. `rc_project_new`
    // already returns NULL for both, and `set_canvas` refuses both, so this
    // is the gate on a hand-edited `project.json`.
    assert_eq!(
        refusal(json!({ "canvas": { "width": 0, "height": 1080 } })),
        "canvas must have a positive width and height, not 0x1080"
    );
    assert_eq!(
        refusal(json!({ "canvas": { "width": 1920, "height": 0 } })),
        "canvas must have a positive width and height, not 1920x0"
    );
    assert_eq!(
        refusal(json!({ "canvas": { "fps": [0, 1] } })),
        "canvas fps must be [num, den] with non-zero terms, not [0, 1]"
    );
    assert_eq!(
        refusal(json!({ "canvas": { "fps": [30, 0] } })),
        "canvas fps must be [num, den] with non-zero terms, not [30, 0]"
    );

    // Only "usable", NOT `set_canvas`'s stricter 16..16384-and-even bounds:
    // the reader accepts every prior version (spec §5.6), so a canvas an
    // older build or another tool wrote still opens.
    let odd = Handle::from_value(&json!({ "canvas": { "width": 641, "height": 481 } }));
    assert_eq!(at(&odd.value(), "/canvas/width"), &json!(641));
}

#[test]
fn validate_catches_a_clip_on_a_missing_track() {
    assert_eq!(
        refusal(json!({
            "tracks": [{ "id": 1 }],
            "clips": [{ "id": 2, "track": 9, "start": 0, "duration": 600_000,
                        "source": { "kind": "text" } }],
            "next_id": 3
        })),
        "clip 2 is on unknown track 9"
    );
}

#[test]
fn validate_catches_a_clip_whose_media_is_absent() {
    for source in [
        json!({ "kind": "media", "media": 7, "in": 0 }),
        json!({ "kind": "still", "media": 7, "at": 0 }),
        json!({ "kind": "image", "media": 7 }),
    ] {
        assert_eq!(
            refusal(json!({
                "tracks": [{ "id": 1 }],
                "clips": [{ "id": 2, "track": 1, "start": 0, "duration": 600_000,
                            "source": source }],
                "next_id": 3
            })),
            "clip 2 refers to unknown media 7"
        );
    }
}

#[test]
fn validate_catches_duplicate_ids_across_kinds() {
    // Ids are unique across ALL kinds, so an MCP call can name anything by
    // one integer (spec §5.2). Each case collides a different pair.
    let clip = |id: u64| {
        json!({ "id": id, "track": 1, "start": 0, "duration": 600_000,
                "source": { "kind": "text" } })
    };
    assert_eq!(
        refusal(json!({
            "media": [{ "id": 1, "path": "/x.mov", "kind": "video" }],
            "tracks": [{ "id": 1 }],
            "clips": [], "next_id": 2
        })),
        "duplicate id 1 on track"
    );
    assert_eq!(
        refusal(json!({
            "tracks": [{ "id": 1 }],
            "clips": [clip(1)],
            "next_id": 2
        })),
        "duplicate id 1 on clip"
    );
    assert_eq!(
        refusal(json!({
            "tracks": [{ "id": 1 }],
            "clips": [{ "id": 2, "track": 1, "start": 0, "duration": 600_000,
                        "source": { "kind": "text" },
                        "actions": [{ "id": 3, "start": 0, "duration": 600_000 },
                                    { "id": 3, "start": 600_000, "duration": 600_000 }] }],
            "next_id": 4
        })),
        "duplicate id 3 on action"
    );
    assert_eq!(
        refusal(json!({
            "tracks": [{ "id": 1 }],
            "clips": [{ "id": 2, "track": 1, "start": 0, "duration": 600_000,
                        "source": { "kind": "text" },
                        "actions": [{ "id": 3, "start": 0, "duration": 600_000 }] }],
            "markers": [{ "id": 3, "time": 0 }],
            "next_id": 4
        })),
        "duplicate id 3 on marker"
    );
}

#[test]
fn validate_catches_next_id_not_past_every_id() {
    assert_eq!(
        refusal(json!({
            "tracks": [{ "id": 1 }],
            "clips": [{ "id": 5, "track": 1, "start": 0, "duration": 600_000,
                        "source": { "kind": "text" } }],
            "next_id": 3
        })),
        "next_id 3 is not greater than id 5"
    );
    // Equal is not "past": next_id 5 would reissue id 5.
    assert_eq!(
        refusal(json!({
            "tracks": [{ "id": 1 }],
            "clips": [{ "id": 5, "track": 1, "start": 0, "duration": 600_000,
                        "source": { "kind": "text" } }],
            "next_id": 5
        })),
        "next_id 5 is not greater than id 5"
    );
}

#[test]
fn validate_catches_bad_clip_and_action_spans() {
    assert_eq!(
        refusal(json!({
            "tracks": [{ "id": 1 }],
            "clips": [{ "id": 2, "track": 1, "start": 0, "duration": 0,
                        "source": { "kind": "text" } }],
            "next_id": 3
        })),
        "clip 2 has non-positive duration 0"
    );
    assert_eq!(
        refusal(json!({
            "tracks": [{ "id": 1 }],
            "clips": [{ "id": 2, "track": 1, "start": -5, "duration": 600_000,
                        "source": { "kind": "text" } }],
            "next_id": 3
        })),
        "clip 2 has negative start -5"
    );
    assert_eq!(
        refusal(json!({
            "tracks": [{ "id": 1 }],
            "clips": [{ "id": 2, "track": 1, "start": 0, "duration": 600_000,
                        "source": { "kind": "text" },
                        "actions": [{ "id": 3, "start": 0, "duration": 0 }] }],
            "next_id": 4
        })),
        "action 3 on clip 2 has non-positive duration 0"
    );
}

// ---- timecode ------------------------------------------------------------

fn timecode(ticks: i64, fps: (u32, u32), frames: bool) -> String {
    expect_string(
        unsafe { rc_timecode_format(ticks, fps.0, fps.1, frames) },
        "rc_timecode_format",
    )
}

/// Parses through the FFI, and checks the header's other promise while it
/// is here: on `false`, `*out` is left untouched.
fn parse_timecode(text: &str, fps: (u32, u32)) -> Option<i64> {
    let s = cstring(text);
    let sentinel = i64::MIN + 12345;
    let mut out = sentinel;
    let ok = unsafe { rc_timecode_parse(s.as_ptr(), fps.0, fps.1, &mut out) };
    if ok {
        Some(out)
    } else {
        assert_eq!(out, sentinel, "rc_timecode_parse wrote *out for {text:?}");
        None
    }
}

const FPS_24: (u32, u32) = (24, 1);
const FPS_25: (u32, u32) = (25, 1);
const FPS_30: (u32, u32) = (30, 1);
const FPS_50: (u32, u32) = (50, 1);
const FPS_60: (u32, u32) = (60, 1);
/// 23.976 — a frame is 600000*1001/24000 = 25025 ticks.
const FPS_23_976: (u32, u32) = (24000, 1001);
/// 29.97 — a frame is 600000*1001/30000 = 20020 ticks.
const FPS_29_97: (u32, u32) = (30000, 1001);

#[test]
fn timecode_formats_the_hand_computed_table() {
    // Frame durations, derived from TIMESCALE = 600000:
    //   24 -> 25000   25 -> 24000   30 -> 20000   50 -> 12000   60 -> 10000
    //   24000/1001 -> 25025         30000/1001 -> 20020
    // Non-drop counts ceil(num/den) frames per timecode second, so the
    // /1001 rates count 24 and 30 and DRIFT against the wall clock. The
    // frame shown is the frame NEAREST t (round half away from zero).
    let cases: [(i64, (u32, u32), &str, &str); 22] = [
        (0, FPS_30, "00:00:00:00", "the origin"),
        // 23 * 25000 = 575000, the last frame of the first second at 24.
        (
            575_000,
            FPS_24,
            "00:00:00:23",
            "24 fps, last frame of second 0",
        ),
        (600_000, FPS_24, "00:00:01:00", "24 fps, one second"),
        // 24 * 24000 = 576000 at 25 fps.
        (
            576_000,
            FPS_25,
            "00:00:00:24",
            "25 fps, last frame of second 0",
        ),
        (600_000, FPS_25, "00:00:01:00", "25 fps, one second"),
        // 29 * 20000 = 580000 at 30 fps.
        (
            580_000,
            FPS_30,
            "00:00:00:29",
            "30 fps, last frame of second 0",
        ),
        (600_000, FPS_30, "00:00:01:00", "30 fps, one second"),
        // 49 * 12000 = 588000 at 50 fps.
        (
            588_000,
            FPS_50,
            "00:00:00:49",
            "50 fps, last frame of second 0",
        ),
        // 59 * 10000 = 590000 at 60 fps.
        (
            590_000,
            FPS_60,
            "00:00:00:59",
            "60 fps, last frame of second 0",
        ),
        // 29 * 20020 = 580580; 30 * 20020 = 600600 (one second of TAPE).
        (580_580, FPS_29_97, "00:00:00:29", "29.97, frame 29"),
        (600_600, FPS_29_97, "00:00:01:00", "29.97, frame 30"),
        // One WALL second is 600000 ticks = 29.97002... frames, which rounds
        // to frame 30: non-drop already reads 1;00 before the tape does.
        (600_000, FPS_29_97, "00:00:01:00", "29.97, one wall second"),
        // The half-frame boundary sits at 29.5 * 20020 = 590590 exactly, and
        // half rounds AWAY from zero.
        (
            590_589,
            FPS_29_97,
            "00:00:00:29",
            "29.97, just under the half frame",
        ),
        (
            590_590,
            FPS_29_97,
            "00:00:01:00",
            "29.97, exactly the half frame",
        ),
        // 23 * 25025 = 575575; 24 * 25025 = 600600.
        (575_575, FPS_23_976, "00:00:00:23", "23.976, frame 23"),
        (600_600, FPS_23_976, "00:00:01:00", "23.976, frame 24"),
        // Half-frame boundary at 23.5 * 25025 = 588087.5.
        (
            588_087,
            FPS_23_976,
            "00:00:00:23",
            "23.976, just under the half frame",
        ),
        (
            588_088,
            FPS_23_976,
            "00:00:01:00",
            "23.976, just over the half frame",
        ),
        // One hour of wall clock = 3600 * 600000 = 2160000000 ticks.
        //   24 fps:  86400 frames                -> 01:00:00:00
        //   29.97:   3600 * 30000/1001 = 107892.108 -> frame 107892
        //            107892 = 3596 * 30 + 12, and 3596 s = 00:59:56
        //   23.976:  3600 * 24000/1001 = 86313.686  -> frame 86314
        //            86314  = 3596 * 24 + 10
        (2_160_000_000, FPS_24, "01:00:00:00", "one hour at 24"),
        (
            2_160_000_000,
            FPS_29_97,
            "00:59:56:12",
            "one hour at 29.97 drifts 3.6 s",
        ),
        (
            2_160_000_000,
            FPS_23_976,
            "00:59:56:10",
            "one hour at 23.976 drifts 3.6 s",
        ),
        // 600 s = 360000000 ticks; 600 * 30000/1001 = 17982.018 -> 17982
        // frames = 599 s + 12 frames.
        (
            360_000_000,
            FPS_29_97,
            "00:09:59:12",
            "ten minutes at 29.97",
        ),
    ];
    for (ticks, fps, expected, why) in cases {
        assert_eq!(
            timecode(ticks, fps, true),
            expected,
            "{ticks} at {}/{} ({why})",
            fps.0,
            fps.1
        );
    }
}

#[test]
fn timecode_formats_the_milliseconds_form() {
    // 600 ticks is one millisecond exactly; the rate is not consulted.
    let cases: [(i64, (u32, u32), &str, &str); 8] = [
        (0, FPS_30, "00:00:00.000", "the origin"),
        (600_000, FPS_30, "00:00:01.000", "one second"),
        (
            2_160_000_000,
            FPS_29_97,
            "01:00:00.000",
            "one hour, rate ignored",
        ),
        (
            300,
            FPS_30,
            "00:00:00.001",
            "half a millisecond rounds away from zero",
        ),
        (299, FPS_30, "00:00:00.000", "just under half a millisecond"),
        // 599700 ticks = 999.5 ms: the rounding carries into the seconds.
        (599_700, FPS_30, "00:00:01.000", "999.5 ms carries"),
        (-600_000, FPS_30, "-00:00:01.000", "negatives get a sign"),
        // 100 h = 360000 s: hours never wrap.
        (
            216_000_000_000,
            FPS_30,
            "100:00:00.000",
            "hours do not wrap",
        ),
    ];
    for (ticks, fps, expected, why) in cases {
        assert_eq!(timecode(ticks, fps, false), expected, "{ticks} ({why})");
    }

    // A degenerate rate falls back to this form even when frames are asked
    // for, because the milliseconds form needs no rate at all.
    assert_eq!(timecode(600_000, (0, 1), true), "00:00:01.000");
    assert_eq!(timecode(600_000, (30, 0), true), "00:00:01.000");

    // Negatives in the frames form too, and 100 hours of frames.
    assert_eq!(timecode(-20_000, FPS_30, true), "-00:00:00:01");
    assert_eq!(timecode(216_000_000_000, FPS_30, true), "100:00:00:00");
}

#[test]
fn a_reading_that_rounds_to_zero_carries_no_minus_sign() {
    // Both forms quantize, so a small negative tick is a ZERO reading, and
    // a zero reading with a minus sign in front of it is not a time: it is
    // what the toolbar field would show while a drag crosses the origin,
    // and it does not even parse back to itself.
    //
    // 30 fps: the frame is 20000 ticks, so the half-frame boundary is at
    // 10000 and everything from -9999 to -1 rounds to frame 0.
    for ticks in [-1, -9_999] {
        assert_eq!(
            timecode(ticks, FPS_30, true),
            "00:00:00:00",
            "{ticks} rounds to frame 0"
        );
    }
    // -10000 is exactly the half frame and rounds AWAY from zero, so it is
    // a genuine frame 1 and keeps its sign.
    assert_eq!(timecode(-10_000, FPS_30, true), "-00:00:00:01");

    // Milliseconds: 600 ticks per ms, so -299 rounds to 0 ms and -300 (half
    // a millisecond) rounds away to 1 ms.
    assert_eq!(timecode(-1, FPS_30, false), "00:00:00.000");
    assert_eq!(timecode(-299, FPS_30, false), "00:00:00.000");
    assert_eq!(timecode(-300, FPS_30, false), "-00:00:00.001");

    // The sign that IS printed round-trips, which is the point of dropping
    // the one that is not.
    assert_eq!(parse_timecode("-00:00:00:01", FPS_30), Some(-20_000));
    assert_eq!(parse_timecode("00:00:00:00", FPS_30), Some(0));
}

#[test]
fn timecode_parses_the_hand_computed_table() {
    let cases: [(&str, (u32, u32), i64, &str); 14] = [
        ("00:00:01:00", FPS_30, 600_000, "30 fps, frame 30"),
        (
            "00:00:00:49",
            FPS_50,
            588_000,
            "50 fps, frame 49 = 49 * 12000",
        ),
        (
            "00:00:01:00",
            FPS_60,
            600_000,
            "60 fps, frame 60 = 60 * 10000",
        ),
        (
            "01:00:00:00",
            FPS_24,
            2_160_000_000,
            "24 fps, 86400 * 25000",
        ),
        ("00:00:00:24", FPS_25, 576_000, "25 fps, 24 * 24000"),
        // 3596 * 30 + 12 = 107892 frames; 107892 * 20020 = 2159997840.
        (
            "00:59:56:12",
            FPS_29_97,
            2_159_997_840,
            "29.97, the one-hour reading",
        ),
        // 3596 * 24 + 10 = 86314 frames; 86314 * 25025 = 2160007850.
        (
            "00:59:56:10",
            FPS_23_976,
            2_160_007_850,
            "23.976, the one-hour reading",
        ),
        // 599 * 30 + 12 = 17982 frames; 17982 * 20020 = 359999640.
        ("00:09:59:12", FPS_29_97, 359_999_640, "29.97, ten minutes"),
        ("00:00:00:29", FPS_29_97, 580_580, "29.97, frame 29"),
        ("1:30", FPS_30, 54_000_000, "MM:SS is 90 seconds"),
        ("90", FPS_30, 54_000_000, "a bare number is seconds"),
        (
            "00:00:01.500",
            FPS_30,
            900_000,
            "the milliseconds form, on the grid",
        ),
        ("-00:00:01", FPS_30, -600_000, "a leading sign"),
        (
            " 00:00:01 ",
            FPS_30,
            600_000,
            "surrounding space is trimmed",
        ),
    ];
    for (text, fps, expected, why) in cases {
        assert_eq!(
            parse_timecode(text, fps),
            Some(expected),
            "{text:?} at {}/{} ({why})",
            fps.0,
            fps.1
        );
    }

    // The result is SNAPPED to the grid: 0.1 s is 60000 ticks, which at 24
    // fps is 2.4 frames -> frame 2 -> 50000 ticks.
    assert_eq!(parse_timecode("0.1", FPS_24), Some(50_000));
    assert_eq!(
        parse_timecode("0.1", FPS_30),
        Some(60_000),
        "3 frames exactly"
    );
    // Fields are summed, not range-checked, so an over-range frame count
    // rolls over the way an over-range second count does.
    assert_eq!(parse_timecode("00:00:01:24", FPS_24), Some(1_200_000));
    assert_eq!(parse_timecode("120", FPS_30), Some(72_000_000));
}

#[test]
fn timecode_rejects_text_that_is_not_a_time() {
    for text in [
        "",
        "   ",
        "-",
        "abc",
        "1:2:3:4:5",
        "00::01",
        "1:",
        ":1",
        "+3",
        "1e3",
        "1.2.3",
        // A fraction in the frames field is not a timecode.
        "00:00:01:12.5", // The frames form needs a rate to count frames with.
    ] {
        assert_eq!(
            parse_timecode(text, FPS_30),
            None,
            "{text:?} was accepted as a time"
        );
    }
    // The frames form needs a usable rate; the other forms do not.
    assert_eq!(parse_timecode("00:00:01:00", (0, 1)), None);
    assert_eq!(parse_timecode("00:00:01", (0, 1)), Some(600_000));
}

#[test]
fn timecode_round_trips_on_the_frame_grid() {
    // format -> parse is the identity for any tick already on the grid,
    // including the rates that do not divide the timescale evenly.
    let grid: [((u32, u32), i64); 7] = [
        (FPS_24, 25_000),
        (FPS_25, 24_000),
        (FPS_30, 20_000),
        (FPS_50, 12_000),
        (FPS_60, 10_000),
        (FPS_23_976, 25_025),
        (FPS_29_97, 20_020),
    ];
    for (fps, frame) in grid {
        for index in [0i64, 1, 29, 30, 1_000, 107_892] {
            let ticks = index * frame;
            let text = timecode(ticks, fps, true);
            assert_eq!(
                parse_timecode(&text, fps),
                Some(ticks),
                "{text} at {}/{} did not round-trip",
                fps.0,
                fps.1
            );
        }
    }
}

// ---- frame snapping ------------------------------------------------------

fn snap(t: i64, fps: (u32, u32)) -> i64 {
    unsafe { rc_time_snap_to_frame(t, fps.0, fps.1) }
}

#[test]
fn snap_to_frame_rounds_to_the_nearest_boundary_half_away_from_zero() {
    // A 30 fps frame is 20000 ticks, so the half-frame is 10000.
    assert_eq!(snap(0, FPS_30), 0);
    assert_eq!(
        snap(9_999, FPS_30),
        0,
        "just under the half frame rounds down"
    );
    assert_eq!(
        snap(10_000, FPS_30),
        20_000,
        "exactly half rounds away from zero"
    );
    assert_eq!(snap(10_001, FPS_30), 20_000);
    assert_eq!(snap(20_000, FPS_30), 20_000, "already on the grid");
    assert_eq!(snap(30_000, FPS_30), 40_000, "1.5 frames rounds up");

    // Negative times are symmetric: half rounds away from zero there too.
    assert_eq!(snap(-9_999, FPS_30), 0);
    assert_eq!(snap(-10_000, FPS_30), -20_000);
    assert_eq!(snap(-25_000, FPS_30), -20_000, "-1.25 frames");
    assert_eq!(snap(-30_000, FPS_30), -40_000, "-1.5 frames");

    // 29.97: a frame is 20020, so the half-frame is 10010 exactly.
    assert_eq!(snap(10_009, FPS_29_97), 0);
    assert_eq!(snap(10_010, FPS_29_97), 20_020);
    assert_eq!(snap(-10_010, FPS_29_97), -20_020);
    // 23.976: a frame is 25025, and the half-frame 12512.5 is NOT an
    // integer, so no tick sits exactly on it.
    assert_eq!(snap(12_512, FPS_23_976), 0);
    assert_eq!(snap(12_513, FPS_23_976), 25_025);

    // Extremes saturate instead of overflowing: the nearest 30 fps boundary
    // to i64::MAX is 461168601842739 * 20000 = 9223372036854780000, past
    // i64::MAX, so the answer clamps to the end of the range rather than
    // wrapping. At 29.97 the boundary below it (a multiple of 20020) is
    // representable, so no clamp is needed there.
    assert_eq!(snap(i64::MAX, FPS_30), i64::MAX);
    assert_eq!(snap(i64::MIN, FPS_30), i64::MIN);
    assert_eq!(snap(i64::MAX, FPS_29_97), 9_223_372_036_854_775_800);
    assert_eq!(snap(i64::MIN, FPS_29_97), -9_223_372_036_854_775_800);
}

#[test]
fn snap_to_frame_leaves_a_degenerate_rate_alone() {
    for fps in [(0, 1), (30, 0), (0, 0)] {
        assert_eq!(snap(12_345, fps), 12_345, "{fps:?} must pass t through");
        assert_eq!(snap(-12_345, fps), -12_345);
    }
}

// ---- bytes that are not text ---------------------------------------------

#[test]
fn text_that_is_not_utf8_is_reported_rather_than_crashing() {
    // A Swift `String` is always valid UTF-8, so this can only arrive from
    // a C caller or a corrupt buffer — which is exactly why the shims check
    // instead of trusting. `{` 0xFF `}` is a plausible-looking object whose
    // second byte is not a UTF-8 sequence.
    let bytes = std::ffi::CString::new(vec![0x7b_u8, 0xff, 0x7d]).expect("no interior NUL");

    let mut err: *mut c_char = ptr::null_mut();
    assert!(unsafe { rc_project_from_json(bytes.as_ptr(), &mut err) }.is_null());
    assert_eq!(take_string(err).as_deref(), Some("json is not valid UTF-8"));

    let live = Handle::new(1920, 1080, 30, 1);
    let mut err: *mut c_char = ptr::null_mut();
    let mut reason: *mut c_char = ptr::null_mut();
    assert!(
        unsafe { rc_project_apply(live.as_ptr(), bytes.as_ptr(), &mut err, &mut reason) }.is_null()
    );
    assert_eq!(take_string(err).as_deref(), Some("op is not valid UTF-8"));
    // Invalid input is not a refusal: the two channels are never both
    // written.
    assert_eq!(take_string(reason), None);

    // The exports with no `err_out` answer with their failure value.
    let mut out: i64 = 99;
    assert!(!unsafe { rc_timecode_parse(bytes.as_ptr(), 30, 1, &mut out) });
    assert_eq!(out, 99);
    assert!(unsafe { rc_project_snap_candidates(live.as_ptr(), bytes.as_ptr()) }.is_null());
    assert_eq!(
        unsafe { rc_snap_resolve(bytes.as_ptr(), 7, 100, ptr::null_mut()) },
        7
    );
}

// ---- the NULL-safety sweep -----------------------------------------------

/// Reads the export names out of the C header. The header is the contract,
/// so it — not a list in this file — decides what the sweep must cover.
fn exports_declared_in_the_header() -> Vec<String> {
    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/include/framejob_core.h");
    let text = std::fs::read_to_string(path).expect("the C header must be readable");
    let code = strip_c_comments(&text);

    let chars: Vec<char> = code.chars().collect();
    let mut names = Vec::new();
    let mut i = 0;
    while i < chars.len() {
        if chars[i].is_ascii_alphabetic() || chars[i] == '_' {
            let start = i;
            while i < chars.len() && (chars[i].is_ascii_alphanumeric() || chars[i] == '_') {
                i += 1;
            }
            let word: String = chars[start..i].iter().collect();
            // A declaration is the name followed by '(' — the `RC_*` defines
            // and the typedef's name are not.
            let mut j = i;
            while j < chars.len() && chars[j].is_whitespace() {
                j += 1;
            }
            if word.starts_with("rc_") && chars.get(j) == Some(&'(') {
                names.push(word);
            }
        } else {
            i += 1;
        }
    }
    names.sort();
    names.dedup();
    assert!(
        names.len() >= 20,
        "the header parse found only {} exports, which cannot be right: {names:?}",
        names.len()
    );
    names
}

fn strip_c_comments(src: &str) -> String {
    let mut out = String::with_capacity(src.len());
    let mut chars = src.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '/' && chars.peek() == Some(&'*') {
            chars.next();
            let mut previous = ' ';
            for inner in chars.by_ref() {
                if previous == '*' && inner == '/' {
                    break;
                }
                previous = inner;
            }
            out.push(' ');
        } else if c == '/' && chars.peek() == Some(&'/') {
            for inner in chars.by_ref() {
                if inner == '\n' {
                    break;
                }
            }
            out.push('\n');
        } else {
            out.push(c);
        }
    }
    out
}

/// The tool handler `rc_agent_socket_start` takes. The sweep never lets a
/// server start, so this is never called.
unsafe extern "C" fn unused_tool_handler(
    _context: *mut c_void,
    _tool_name: *const c_char,
    _arguments_json: *const c_char,
) -> *mut c_char {
    ptr::null_mut()
}

/// Calls every export with NULL pointers (and with a NULL `err_out`, which
/// must also be tolerated), asserting each returns its documented failure
/// value. Returns the names it covered, for the header comparison.
fn sweep_every_export_with_nulls() -> Vec<String> {
    let mut swept: Vec<String> = Vec::new();
    let mut cover = |name: &str| swept.push(name.to_string());

    let live = Handle::new(1920, 1080, 30, 1);
    let op = cstring("{\"op\":\"remove_empty_tracks\"}");
    let preset = cstring("h264");

    // rc_string_free — NULL-tolerant.
    unsafe { rc_string_free(ptr::null_mut()) };
    cover("rc_string_free");

    // rc_project_new — NULL for a zero dimension or a degenerate rate.
    for (w, h, num, den) in [
        (0, 1080, 30, 1),
        (1920, 0, 30, 1),
        (1920, 1080, 0, 1),
        (1920, 1080, 30, 0),
    ] {
        assert!(
            unsafe { rc_project_new(w, h, num, den) }.is_null(),
            "rc_project_new({w}, {h}, {num}/{den}) must be NULL"
        );
    }
    cover("rc_project_new");

    // rc_project_from_json — NULL json is an error, not a crash.
    let mut err: *mut c_char = ptr::null_mut();
    assert!(unsafe { rc_project_from_json(ptr::null(), &mut err) }.is_null());
    assert_eq!(
        take_string(err).as_deref(),
        Some("json is NULL"),
        "rc_project_from_json(NULL) must report through err_out"
    );
    assert!(unsafe { rc_project_from_json(ptr::null(), ptr::null_mut()) }.is_null());
    cover("rc_project_from_json");

    assert!(unsafe { rc_project_to_json(ptr::null()) }.is_null());
    cover("rc_project_to_json");

    assert!(unsafe { rc_project_clone(ptr::null()) }.is_null());
    cover("rc_project_clone");

    // rc_project_scoped — a NULL project is a caller bug, so it sets
    // err_out rather than answering a bare NULL: this export has no "valid
    // but changes nothing" case, and a caller cannot tell "no such nest"
    // from "you passed nothing" without a message. A NULL err_out is still
    // tolerated, which is the other half of the pair.
    let mut err: *mut c_char = ptr::null_mut();
    assert!(unsafe { rc_project_scoped(ptr::null(), 1, &mut err) }.is_null());
    assert_eq!(take_string(err).as_deref(), Some("project is NULL"));
    assert!(unsafe { rc_project_scoped(ptr::null(), 1, ptr::null_mut()) }.is_null());
    cover("rc_project_scoped");

    unsafe { rc_project_free(ptr::null_mut()) };
    cover("rc_project_free");

    // rc_project_apply — both pointers, separately and together. A NULL
    // project is a caller bug (err_out set), NOT "changes nothing".
    let mut err: *mut c_char = ptr::null_mut();
    assert!(
        unsafe { rc_project_apply(ptr::null(), op.as_ptr(), &mut err, ptr::null_mut()) }.is_null()
    );
    assert_eq!(take_string(err).as_deref(), Some("project is NULL"));
    let mut err: *mut c_char = ptr::null_mut();
    assert!(
        unsafe { rc_project_apply(live.as_ptr(), ptr::null(), &mut err, ptr::null_mut()) }
            .is_null()
    );
    assert_eq!(take_string(err).as_deref(), Some("op is NULL"));
    assert!(unsafe {
        rc_project_apply(ptr::null(), ptr::null(), ptr::null_mut(), ptr::null_mut())
    }
    .is_null());
    cover("rc_project_apply");

    assert_eq!(unsafe { rc_project_duration(ptr::null()) }, 0);
    cover("rc_project_duration");

    assert!(unsafe { rc_project_composition_plan(ptr::null()) }.is_null());
    cover("rc_project_composition_plan");

    assert!(unsafe { rc_project_frame_recipe(ptr::null(), 0) }.is_null());
    cover("rc_project_frame_recipe");

    // A NULL opts_json means the default options, so only the project may be
    // NULL here — and the pointer is read INSIDE the closure that catches
    // panics, which is what this pair is really standing over.
    assert!(unsafe { rc_project_frame_recipe_opts(ptr::null(), 0, ptr::null()) }.is_null());
    let defaulted =
        take_string(unsafe { rc_project_frame_recipe_opts(live.as_ptr(), 0, ptr::null()) })
            .expect("a NULL opts_json is not a failure");
    assert_contains(&defaulted, "\"layers\"");
    cover("rc_project_frame_recipe_opts");

    assert!(unsafe { rc_project_clip_state(ptr::null(), 1, 0) }.is_null());
    cover("rc_project_clip_state");

    assert!(unsafe { rc_project_source_map(ptr::null(), 1) }.is_null());
    cover("rc_project_source_map");

    // A NULL exclude list means "exclude nothing", so only the project may
    // be NULL here.
    assert!(unsafe { rc_project_snap_candidates(ptr::null(), ptr::null()) }.is_null());
    let candidates = take_string(unsafe { rc_project_snap_candidates(live.as_ptr(), ptr::null()) })
        .expect("a NULL exclude list is not a failure");
    assert_contains(&candidates, "\"ticks\"");
    cover("rc_project_snap_candidates");

    // rc_snap_resolve — an unreadable array snaps to nothing and leaves
    // snapped_out untouched.
    let mut snapped = true;
    assert_eq!(
        unsafe { rc_snap_resolve(ptr::null(), 7, 100, &mut snapped) },
        7
    );
    assert!(
        snapped,
        "rc_snap_resolve wrote snapped_out for a NULL array"
    );
    assert_eq!(
        unsafe { rc_snap_resolve(ptr::null(), 7, 100, ptr::null_mut()) },
        7
    );
    cover("rc_snap_resolve");

    assert_eq!(unsafe { rc_time_snap_to_frame(7, 0, 0) }, 7);
    cover("rc_time_snap_to_frame");

    assert!(!unsafe { rc_timecode_format(0, 0, 0, true) }.is_null());
    take_string(unsafe { rc_timecode_format(0, 0, 0, true) });
    cover("rc_timecode_format");

    let mut out: i64 = 99;
    assert!(!unsafe { rc_timecode_parse(ptr::null(), 30, 1, &mut out) });
    assert_eq!(out, 99, "rc_timecode_parse wrote *out for NULL text");
    let text = cstring("00:00:01");
    assert!(unsafe { rc_timecode_parse(text.as_ptr(), 30, 1, ptr::null_mut()) });
    cover("rc_timecode_parse");

    assert!(unsafe { rc_normalise_color(ptr::null()) }.is_null());
    cover("rc_normalise_color");

    // rc_op_names takes no pointers at all, so "NULL-safe" here just means
    // it answers its documented never-NULL string.
    let ops = take_string(unsafe { rc_op_names() }).expect("op names are never NULL");
    assert_contains(&ops, "\"add_shape_clip\"");
    cover("rc_op_names");

    // rc_op_schemas takes no pointers either, and answers one schema per
    // op — `core/tests/op_schemas.rs` is where its contents are checked.
    let schemas = take_string(unsafe { rc_op_schemas() }).expect("op schemas are never NULL");
    assert_contains(&schemas, "\"add_shape_clip\"");
    cover("rc_op_schemas");

    // rc_speed_limits takes no pointers either — `core/tests/speed_x1000.rs`
    // is where its contents are checked.
    let limits = take_string(unsafe { rc_speed_limits() }).expect("limits are never NULL");
    assert_contains(&limits, "\"audio_max\"");
    cover("rc_speed_limits");

    let presets = take_string(unsafe { rc_export_presets() }).expect("presets are never NULL");
    assert_contains(&presets, "\"h264\"");
    cover("rc_export_presets");

    // rc_export_sizes — the project and the preset, separately and
    // together; a NULL project is a caller bug and says so.
    let mut err: *mut c_char = ptr::null_mut();
    assert!(unsafe { rc_export_sizes(ptr::null(), preset.as_ptr(), &mut err) }.is_null());
    assert_eq!(take_string(err).as_deref(), Some("project is NULL"));
    let mut err: *mut c_char = ptr::null_mut();
    assert!(unsafe { rc_export_sizes(live.as_ptr(), ptr::null(), &mut err) }.is_null());
    assert_eq!(take_string(err).as_deref(), Some("preset_id is NULL"));
    assert!(unsafe { rc_export_sizes(ptr::null(), ptr::null(), ptr::null_mut()) }.is_null());
    cover("rc_export_sizes");

    let mut err: *mut c_char = ptr::null_mut();
    assert!(
        unsafe { rc_export_settings(ptr::null(), preset.as_ptr(), ptr::null(), &mut err) }
            .is_null()
    );
    assert_eq!(take_string(err).as_deref(), Some("project is NULL"));
    let mut err: *mut c_char = ptr::null_mut();
    assert!(
        unsafe { rc_export_settings(live.as_ptr(), ptr::null(), ptr::null(), &mut err) }.is_null()
    );
    assert_eq!(take_string(err).as_deref(), Some("preset_id is NULL"));
    assert!(
        unsafe { rc_export_settings(ptr::null(), ptr::null(), ptr::null(), ptr::null_mut()) }
            .is_null()
    );
    cover("rc_export_settings");

    assert!(unsafe { rc_agent_string_create(ptr::null()) }.is_null());
    cover("rc_agent_string_create");

    let version = cstring("0.1.0");
    let tools = cstring("[]");

    // The socket's NULL path is refused before anything is read or bound;
    // a NULL name after a real path still binds nothing.
    let mut err: *mut c_char = ptr::null_mut();
    assert!(!unsafe {
        rc_agent_socket_start(
            ptr::null(),
            ptr::null(),
            ptr::null(),
            ptr::null(),
            unused_tool_handler,
            ptr::null_mut(),
            &mut err,
        )
    });
    assert_eq!(take_string(err).as_deref(), Some("socket_path is NULL"));
    let path = cstring("/nonexistent-rc-sweep/agent.sock");
    let mut err: *mut c_char = ptr::null_mut();
    assert!(!unsafe {
        rc_agent_socket_start(
            path.as_ptr(),
            ptr::null(),
            version.as_ptr(),
            tools.as_ptr(),
            unused_tool_handler,
            ptr::null_mut(),
            &mut err,
        )
    });
    assert_eq!(take_string(err).as_deref(), Some("server_name is NULL"));
    assert!(!unsafe {
        rc_agent_socket_start(
            ptr::null(),
            ptr::null(),
            ptr::null(),
            ptr::null(),
            unused_tool_handler,
            ptr::null_mut(),
            ptr::null_mut(),
        )
    });
    cover("rc_agent_socket_start");

    // Safe when none is bound.
    rc_agent_socket_release();
    cover("rc_agent_socket_release");

    // The graphics exports (`graphic_ffi.rs` checks what they draw). Every
    // `diag_out` failure is ONE error Diagnostic in a JSON array.
    let diag_of = |raw: *mut c_char| -> String {
        let list: Value = serde_json::from_str(&take_string(raw).expect("diag_out was written"))
            .expect("diag_out is JSON");
        assert_eq!(
            list.as_array().map(Vec::len),
            Some(1),
            "one diagnostic: {list}"
        );
        assert_eq!(list[0]["level"], "error");
        list[0]["message"].as_str().expect("a message").to_string()
    };
    let lib = unsafe { rc_graphic_library_new() };
    assert!(!lib.is_null(), "rc_graphic_library_new is never NULL");
    cover("rc_graphic_library_new");

    let byte = [0u8; 1];
    let mut err: *mut c_char = ptr::null_mut();
    assert!(!unsafe { rc_graphic_library_add_font(ptr::null_mut(), byte.as_ptr(), 1, &mut err) });
    assert_eq!(take_string(err).as_deref(), Some("library is NULL"));
    let mut err: *mut c_char = ptr::null_mut();
    assert!(!unsafe { rc_graphic_library_add_font(lib, ptr::null(), 0, &mut err) });
    assert_eq!(take_string(err).as_deref(), Some("bytes is NULL"));
    assert!(!unsafe {
        rc_graphic_library_add_font(ptr::null_mut(), ptr::null(), 0, ptr::null_mut())
    });
    cover("rc_graphic_library_add_font");

    let asset = cstring("a.png");
    let mut err: *mut c_char = ptr::null_mut();
    assert!(!unsafe { rc_graphic_library_add_asset(lib, ptr::null(), byte.as_ptr(), 1, &mut err) });
    assert_eq!(take_string(err).as_deref(), Some("name is NULL"));
    let mut err: *mut c_char = ptr::null_mut();
    assert!(!unsafe {
        rc_graphic_library_add_asset(lib, asset.as_ptr(), ptr::null(), 0, &mut err)
    });
    assert_eq!(take_string(err).as_deref(), Some("bytes is NULL"));
    assert!(!unsafe {
        rc_graphic_library_add_asset(
            ptr::null_mut(),
            ptr::null(),
            ptr::null(),
            0,
            ptr::null_mut(),
        )
    });
    cover("rc_graphic_library_add_asset");

    assert!(unsafe { rc_graphic_library_families(ptr::null()) }.is_null());
    cover("rc_graphic_library_families");

    let source = cstring("export function render() { return \"\"; }");
    let mut diag: *mut c_char = ptr::null_mut();
    assert!(unsafe {
        rc_graphic_compile(ptr::null(), asset.as_ptr(), source.as_ptr(), 50, &mut diag)
    }
    .is_null());
    assert_eq!(diag_of(diag), "library is NULL");
    let mut diag: *mut c_char = ptr::null_mut();
    assert!(
        unsafe { rc_graphic_compile(lib, ptr::null(), source.as_ptr(), 50, &mut diag) }.is_null()
    );
    assert_eq!(diag_of(diag), "name is NULL");
    let mut diag: *mut c_char = ptr::null_mut();
    assert!(
        unsafe { rc_graphic_compile(lib, asset.as_ptr(), ptr::null(), 50, &mut diag) }.is_null()
    );
    assert_eq!(diag_of(diag), "source is NULL");
    assert!(unsafe {
        rc_graphic_compile(ptr::null(), ptr::null(), ptr::null(), 50, ptr::null_mut())
    }
    .is_null());
    cover("rc_graphic_compile");

    assert!(unsafe { rc_graphic_describe(ptr::null()) }.is_null());
    cover("rc_graphic_describe");

    let ctx = cstring("{}");
    let mut diag: *mut c_char = ptr::null_mut();
    assert!(
        unsafe { rc_graphic_svg(ptr::null(), 0, ptr::null(), ctx.as_ptr(), 50, &mut diag) }
            .is_null()
    );
    assert_eq!(diag_of(diag), "graphic is NULL");
    assert!(unsafe {
        rc_graphic_svg(
            ptr::null(),
            0,
            ptr::null(),
            ptr::null(),
            50,
            ptr::null_mut(),
        )
    }
    .is_null());
    cover("rc_graphic_svg");

    let svg = cstring("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1\" height=\"1\"/>");
    let mut pixel = [0u8; 4];
    let mut diag: *mut c_char = ptr::null_mut();
    assert!(!unsafe {
        rc_graphic_rasterize(
            ptr::null(),
            svg.as_ptr(),
            1,
            1,
            pixel.as_mut_ptr(),
            4,
            &mut diag,
        )
    });
    assert_eq!(diag_of(diag), "library is NULL");
    let mut diag: *mut c_char = ptr::null_mut();
    assert!(!unsafe {
        rc_graphic_rasterize(lib, ptr::null(), 1, 1, pixel.as_mut_ptr(), 4, &mut diag)
    });
    assert_eq!(diag_of(diag), "svg is NULL");
    let mut diag: *mut c_char = ptr::null_mut();
    assert!(!unsafe {
        rc_graphic_rasterize(lib, svg.as_ptr(), 1, 1, ptr::null_mut(), 4, &mut diag)
    });
    assert_eq!(diag_of(diag), "out_bgra is NULL");
    assert!(!unsafe {
        rc_graphic_rasterize(
            ptr::null(),
            ptr::null(),
            1,
            1,
            ptr::null_mut(),
            4,
            ptr::null_mut(),
        )
    });
    cover("rc_graphic_rasterize");

    unsafe { rc_graphic_free(ptr::null_mut()) };
    cover("rc_graphic_free");
    unsafe { rc_graphic_library_free(ptr::null_mut()) };
    unsafe { rc_graphic_library_free(lib) };
    cover("rc_graphic_library_free");

    // No pointers: a limit of 0 (the engine's default) empties the cache.
    assert_eq!(unsafe { rc_graphic_image_cache(0) }, 0);
    cover("rc_graphic_image_cache");

    let mut err: *mut c_char = ptr::null_mut();
    assert!(unsafe { rc_container_open(ptr::null(), &mut err) }.is_null());
    assert_eq!(take_string(err).as_deref(), Some("path is NULL"));
    assert!(unsafe { rc_container_open(ptr::null(), ptr::null_mut()) }.is_null());
    cover("rc_container_open");
    assert!(unsafe { rc_container_describe(ptr::null()) }.is_null());
    cover("rc_container_describe");
    assert!(!unsafe { rc_container_retime(ptr::null_mut(), 30, 1) });
    cover("rc_container_retime");
    assert_eq!(unsafe { rc_container_sample_count(ptr::null(), 0) }, 0);
    cover("rc_container_sample_count");
    let mut sample = RcContainerSample::default();
    assert!(!unsafe { rc_container_sample(ptr::null(), 0, 0, &mut sample) });
    assert!(!unsafe { rc_container_sample(ptr::null(), 0, 0, ptr::null_mut()) });
    cover("rc_container_sample");
    unsafe { rc_container_free(ptr::null_mut()) };
    cover("rc_container_free");

    let mut err: *mut c_char = ptr::null_mut();
    assert!(unsafe { rc_cube_parse(ptr::null(), 0, &mut err) }.is_null());
    assert_eq!(take_string(err).as_deref(), Some("bytes is NULL"));
    assert!(unsafe { rc_cube_parse(ptr::null(), 0, ptr::null_mut()) }.is_null());
    cover("rc_cube_parse");
    assert_eq!(unsafe { rc_cube_size(ptr::null()) }, 0);
    cover("rc_cube_size");
    let mut floats = [0f32; 24];
    assert!(!unsafe { rc_cube_copy_rgb(ptr::null(), floats.as_mut_ptr(), 24) });
    assert!(!unsafe { rc_cube_copy_rgb(ptr::null(), ptr::null_mut(), 0) });
    cover("rc_cube_copy_rgb");
    unsafe { rc_cube_free(ptr::null_mut()) };
    cover("rc_cube_free");

    // rc_hdr10_peak — every NULL is an absent input, so nothing is read: `{}`.
    let read = unsafe { rc_hdr10_peak(ptr::null(), 24, ptr::null(), 4, ptr::null(), 100, 4) };
    assert_eq!(take_string(read).as_deref(), Some("{}"));
    cover("rc_hdr10_peak");
    // rc_hdr10_av1_peak — the same: `{}`.
    let read = unsafe { rc_hdr10_av1_peak(ptr::null(), 40, ptr::null(), 100) };
    assert_eq!(take_string(read).as_deref(), Some("{}"));
    cover("rc_hdr10_av1_peak");
    // rc_hdr10_still_peak — a NULL file reads nothing: `{}`.
    let read = unsafe { rc_hdr10_still_peak(ptr::null(), 64) };
    assert_eq!(take_string(read).as_deref(), Some("{}"));
    cover("rc_hdr10_still_peak");

    // rc_av1_config — NULL bytes are refused through err_out, and tolerated
    // with no channel.
    let mut err: *mut c_char = ptr::null_mut();
    assert!(unsafe { rc_av1_config(ptr::null(), 16, &mut err) }.is_null());
    assert_eq!(take_string(err).as_deref(), Some("bytes is NULL"));
    assert!(unsafe { rc_av1_config(ptr::null(), 0, ptr::null_mut()) }.is_null());
    cover("rc_av1_config");
    // rc_av1_strip_temporal_delimiters — NULL keeps nothing.
    assert_eq!(
        unsafe { rc_av1_strip_temporal_delimiters(ptr::null_mut(), 16) },
        0
    );
    cover("rc_av1_strip_temporal_delimiters");
    // rc_av1_ftyp_brand — NULL has no ftyp.
    assert_eq!(unsafe { rc_av1_ftyp_brand(ptr::null_mut(), 32) }, -1);
    cover("rc_av1_ftyp_brand");

    // rc_webm_* — a NULL path or handle is refused through err_out, and
    // tolerated with no channel; free is a no-op.
    let mut err: *mut c_char = ptr::null_mut();
    assert!(unsafe { rc_webm_open(ptr::null(), ptr::null(), &mut err) }.is_null());
    assert_eq!(take_string(err).as_deref(), Some("path is NULL"));
    assert!(unsafe { rc_webm_open(ptr::null(), ptr::null(), ptr::null_mut()) }.is_null());
    cover("rc_webm_open");
    let byte = [0u8; 1];
    let mut err: *mut c_char = ptr::null_mut();
    assert!(!unsafe {
        rc_webm_add_packet(ptr::null_mut(), 1, 0, true, 0, byte.as_ptr(), 1, &mut err)
    });
    assert_eq!(take_string(err).as_deref(), Some("webm is NULL"));
    assert!(!unsafe {
        rc_webm_add_packet(
            ptr::null_mut(),
            1,
            0,
            true,
            0,
            ptr::null(),
            0,
            ptr::null_mut(),
        )
    });
    cover("rc_webm_add_packet");
    let mut err: *mut c_char = ptr::null_mut();
    assert!(!unsafe { rc_webm_end_track(ptr::null_mut(), 1, &mut err) });
    assert_eq!(take_string(err).as_deref(), Some("webm is NULL"));
    assert!(!unsafe { rc_webm_end_track(ptr::null_mut(), 1, ptr::null_mut()) });
    cover("rc_webm_end_track");
    let mut err: *mut c_char = ptr::null_mut();
    assert!(!unsafe { rc_webm_finish(ptr::null_mut(), &mut err) });
    assert_eq!(take_string(err).as_deref(), Some("webm is NULL"));
    assert!(!unsafe { rc_webm_finish(ptr::null_mut(), ptr::null_mut()) });
    cover("rc_webm_finish");
    unsafe { rc_webm_free(ptr::null_mut()) };
    cover("rc_webm_free");

    swept.sort();
    swept.dedup();
    swept
}

#[test]
fn null_safety_sweep_covers_every_export_in_the_header() {
    let swept = sweep_every_export_with_nulls();
    let declared = exports_declared_in_the_header();
    assert_eq!(
        declared, swept,
        "the header and the NULL-safety sweep disagree: an export declared in \
         core/include/framejob_core.h but never called with NULL here (or the \
         other way round) is exactly the bug this test exists to catch"
    );
}
