//! The cursor file, format v1 (spec §11 CU-10), black box over
//! `rc_cursor_open` and `rc_cursor_free` exactly as `ReelCore+Cursor.swift`
//! calls them. Every body is written here: [`minimal`] and [`full`] as JSON
//! values, the caps' columns as text so a 1.7-million-entry column costs no
//! `Value` per entry, and each PNG's base64 by [`base64`], an encoder
//! written here as the decoder's oracle.
//!
//! Pinned: a minimal and a full file accepted (negative scroll deltas
//! among them) and the full file's values read back; every refusal
//! sentence; each cap accepted at its count and refused one past; the parse
//! order (a v2 body with a key v1 does not know refused by its version, a
//! project's JSON by its format); touching hidden spans accepted and
//! overlapping ones refused; the header's `RC_CURSOR_FILE_VERSION` equal to
//! the core's; a NULL byte pointer.

mod common;

use std::ffi::c_char;
use std::ptr;

use common::take_string;
use framejob_core::cursor_file::{
    Anchor, CursorFile, CursorImageMode, CursorKind, SourceKind, CURSOR_FORMAT, MAX_CLICKS,
    MAX_DIRTY, MAX_GEOMETRY, MAX_HIDDEN, MAX_IMAGES, MAX_IMAGE_BYTES, MAX_IMAGE_CHANGES, MAX_MOVES,
    MAX_SCROLLS, MAX_SHORTCUTS, MAX_TYPED, RC_CURSOR_FILE_VERSION,
};
use framejob_core::ffi_cursor::{rc_cursor_free, rc_cursor_open};
use serde_json::{json, Value};

/// A PNG's eight signature bytes and a few more: the core checks the
/// signature only.
const PNG: [u8; 12] = [0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13];

/// Standard-alphabet, padded base64, written from RFC 4648 §4.
fn base64(bytes: &[u8]) -> String {
    const ALPHABET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::new();
    for chunk in bytes.chunks(3) {
        let mut group = [0u8; 3];
        group[..chunk.len()].copy_from_slice(chunk);
        let n = (u32::from(group[0]) << 16) | (u32::from(group[1]) << 8) | u32::from(group[2]);
        for k in 0..4 {
            if k <= chunk.len() {
                out.push(ALPHABET[((n >> (18 - 6 * k)) & 63) as usize] as char);
            } else {
                out.push('=');
            }
        }
    }
    out
}

/// Opens and frees through the FFI: `Ok` or the sentence.
fn open_bytes(bytes: &[u8]) -> Result<(), String> {
    let mut err: *mut c_char = ptr::null_mut();
    let handle = unsafe { rc_cursor_open(bytes.as_ptr(), bytes.len(), &mut err) };
    if handle.is_null() {
        return Err(take_string(err).expect("rc_cursor_open returned NULL without a reason"));
    }
    assert!(
        err.is_null(),
        "rc_cursor_open returned a handle AND a reason"
    );
    unsafe { rc_cursor_free(handle) };
    Ok(())
}

fn open(body: &Value) -> Result<(), String> {
    open_bytes(&serde_json::to_vec(body).expect("a test body serializes"))
}

fn refused(body: &Value) -> String {
    open(body).expect_err("this body was expected to be refused")
}

/// Every key, every column empty, one geometry entry.
fn minimal() -> Value {
    json!({
        "format": "framejob-cursor", "version": 1, "in_picture": false, "source": "display",
        "display_id": 1, "source_frame": [0, 0, 151200, 98200], "point_size": [151200, 98200],
        "pixels_per_point": 2.0, "content_size": [3024, 1964], "movie_size": [3024, 1964],
        "anchor": "e2", "anchor_host_us": 1000, "cursor_image": "current-system",
        "moves": {"t": [], "x": [], "y": []}, "images": [],
        "image_changes": {"t": [], "id": []}, "hidden": {"from": [], "to": []},
        "clicks": {"t": [], "button": [], "down": [], "x": [], "y": [], "count": []},
        "scrolls": {"t": [], "x": [], "y": [], "dx": [], "dy": []},
        "geometry": [{"t": 0, "screen_rect": [0, 0, 151200, 98200],
                      "content_rect": [0, 0, 151200, 98200],
                      "content_scale": 1.0, "scale_factor": 2.0}],
        "dirty": {"t": [], "x": [], "y": [], "w": [], "h": []},
        "keys": {"shortcut": {"t": [], "keys": [], "code": []}, "typed": {"t": []}}
    })
}

/// Something in every column, negative scroll deltas and touching hidden
/// spans among it.
fn full() -> Value {
    let mut v = minimal();
    v["source"] = json!("window");
    v["display_id"] = Value::Null;
    v["moves"] = json!({"t": [0, 8333, 8333, 16666], "x": [100, 200, 300, -400],
                        "y": [50, 60, 70, 80]});
    v["images"] = json!([
        {"png": base64(&PNG), "hot_x": 400, "hot_y": 400, "w": 1600, "h": 2400, "kind": "arrow"},
        {"png": base64(&PNG[..9]), "hot_x": 0, "hot_y": 1600, "w": 1600, "h": 1600},
        {"png": base64(&PNG[..10]), "hot_x": 800, "hot_y": 800, "w": 1600, "h": 1600,
         "kind": "resize_up_down"}
    ]);
    v["image_changes"] = json!({"t": [0, 500, 900], "id": [0, 2, 1]});
    v["hidden"] = json!({"from": [10, 20, 40], "to": [20, 30, 41]});
    v["clicks"] = json!({"t": [100, 180], "button": [0, 31], "down": [1, 0],
                         "x": [100, 100], "y": [50, 50], "count": [2, 1]});
    v["scrolls"] = json!({"t": [200, 210], "x": [5, 5], "y": [6, 6], "dx": [-150, 0],
                          "dy": [-1225, 300]});
    v["geometry"] = json!([
        {"t": 0, "screen_rect": [0, 0, 100100, 70100], "content_rect": [0, 0, 100100, 70100],
         "content_scale": 1.0, "scale_factor": 1.0},
        {"t": 4000, "screen_rect": [500, 700, 100100, 70100],
         "content_rect": [0, 0, 100100, 70100], "content_scale": 0.5, "scale_factor": 2.0}
    ]);
    v["dirty"] = json!({"t": [10], "x": [1], "y": [2], "w": [3], "h": [4]});
    v["keys"] = json!({"shortcut": {"t": [300, 300], "keys": ["cmd+shift+plus", "ctrl+c"],
                                    "code": [24, 8]},
                       "typed": {"t": [400, 401, 401]}});
    v
}

/// `body` with every `"@name@"` string replaced by its text.
fn with_text(body: &Value, fills: &[(&str, String)]) -> Vec<u8> {
    let mut text = serde_json::to_string(body).expect("a test body serializes");
    for (name, fill) in fills {
        let marker = format!("\"@{name}@\"");
        assert_eq!(
            text.matches(&marker).count(),
            1,
            "{marker} is in the body once"
        );
        text = text.replace(&marker, fill);
    }
    text.into_bytes()
}

/// A JSON array of `n` copies of `item`.
fn repeated(item: &str, n: usize) -> String {
    let mut out = String::with_capacity(n * (item.len() + 1) + 2);
    out.push('[');
    for i in 0..n {
        if i > 0 {
            out.push(',');
        }
        out.push_str(item);
    }
    out.push(']');
    out
}

#[test]
fn a_minimal_and_a_full_file_are_accepted() {
    assert_eq!(open(&minimal()), Ok(()));
    assert_eq!(open(&full()), Ok(()));
    let mut no_images = minimal();
    no_images["cursor_image"] = json!("none");
    no_images["anchor"] = json!("e1");
    assert_eq!(open(&no_images), Ok(()));
}

#[test]
fn the_full_file_reads_back_its_values() {
    let bytes = serde_json::to_vec(&full()).unwrap();
    let file = CursorFile::parse(&bytes).expect("the full file parses");
    assert_eq!(file.format, CURSOR_FORMAT);
    assert_eq!(file.source, SourceKind::Window);
    assert_eq!(file.display_id, None);
    assert_eq!(file.anchor, Anchor::E2);
    assert_eq!(file.cursor_image, CursorImageMode::CurrentSystem);
    assert_eq!(file.scrolls.dx, vec![-150, 0]);
    assert_eq!(file.scrolls.dy, vec![-1225, 300]);
    assert_eq!(file.moves.x, vec![100, 200, 300, -400]);
    let pngs: Vec<&[u8]> = file.images.iter().map(|i| i.png.as_slice()).collect();
    assert_eq!(pngs, vec![&PNG[..], &PNG[..9], &PNG[..10]]);
    assert_eq!(file.images[0].kind, Some(CursorKind::Arrow));
    assert_eq!(file.images[1].kind, None);
    assert_eq!(file.images[2].kind, Some(CursorKind::ResizeUpDown));
    assert_eq!(file.geometry[1].content_scale, 0.5);
    assert_eq!(file.keys.shortcut.keys, vec!["cmd+shift+plus", "ctrl+c"]);
    assert_eq!(file.keys.typed.t, vec![400, 401, 401]);
}

#[test]
fn format_and_version_are_read_before_the_strict_parse() {
    let mut newer = minimal();
    newer["version"] = json!(2);
    newer["a_key_v1_does_not_know"] = json!({"x": 1});
    assert_eq!(
        refused(&newer),
        "the cursor file is version 2; this Frame Job reads cursor files up to version 1"
    );
    let project = json!({"format_version": 38, "tracks": []});
    let format = "this is not a Frame Job cursor file: its \"format\" is not \"framejob-cursor\"";
    assert_eq!(refused(&project), format);
    let mut other = minimal();
    other["format"] = json!("framejob-project");
    assert_eq!(refused(&other), format);
    assert_eq!(
        refused(&json!([1, 2])),
        "the cursor file is not a JSON object"
    );
    assert!(open_bytes(b"{\"format\": ")
        .unwrap_err()
        .starts_with("the cursor file is not JSON: "));
    let not_integer = "the cursor file's \"version\" is not an integer";
    for version in [json!("1"), json!(1.0), Value::Null] {
        let mut v = minimal();
        v["version"] = version;
        assert_eq!(refused(&v), not_integer);
    }
    let mut absent = minimal();
    absent.as_object_mut().unwrap().remove("version");
    assert_eq!(refused(&absent), not_integer);
    let mut zero = minimal();
    zero["version"] = json!(0);
    assert_eq!(
        refused(&zero),
        "the cursor file is version 0; versions start at 1"
    );
    let mut huge = minimal();
    huge["version"] = json!(u64::MAX);
    assert_eq!(
        refused(&huge),
        format!(
            "the cursor file is version {}; this Frame Job reads cursor files up to version 1",
            u64::MAX
        )
    );
}

#[test]
fn the_strict_parse_names_its_path() {
    let mut extra = minimal();
    extra["extra"] = json!(1);
    let msg = refused(&extra);
    assert!(
        msg.starts_with("the cursor file at \"extra\": unknown field `extra`, expected one of"),
        "{msg}"
    );
    let mut missing = minimal();
    missing.as_object_mut().unwrap().remove("moves");
    assert_eq!(
        refused(&missing),
        "the cursor file at its top level: missing field `moves`"
    );
    let mut source = minimal();
    source["source"] = json!("screen");
    assert_eq!(
        refused(&source),
        "the cursor file at \"source\": unknown variant `screen`, expected one of `display`, \
         `window`, `picked`"
    );
    let mut kind = full();
    kind["images"][1]["kind"] = json!("hand");
    assert!(refused(&kind).starts_with(
        "the cursor file at \"images[1].kind\": unknown variant `hand`, expected one of `arrow`"
    ));
    let mut anchor = minimal();
    anchor["anchor"] = json!("e3");
    assert_eq!(
        refused(&anchor),
        "the cursor file at \"anchor\": unknown variant `e3`, expected `e2` or `e1`"
    );
    let mut image_mode = minimal();
    image_mode["cursor_image"] = json!("system");
    assert_eq!(
        refused(&image_mode),
        "the cursor file at \"cursor_image\": unknown variant `system`, expected \
         `current-system` or `none`"
    );
    let mut fractional = full();
    fractional["moves"]["t"][1] = json!(8333.5);
    assert_eq!(
        refused(&fractional),
        "the cursor file at \"moves.t[1]\": invalid type: floating point `8333.5`, expected i64"
    );
    let mut nested = minimal();
    nested["moves"]["z"] = json!([]);
    assert!(refused(&nested).starts_with("the cursor file at \"moves.z\": unknown field `z`"));
}

#[test]
fn a_typed_key_is_its_time_only() {
    let mut label = full();
    label["keys"]["typed"]["label"] = json!(["a", "b", "c"]);
    assert_eq!(
        refused(&label),
        "keys.typed holds a typed key's time only; \"label\" is refused (spec §11 CU-7)"
    );
    let mut code = minimal();
    code["keys"]["typed"] = json!({"t": [], "code": []});
    assert_eq!(
        refused(&code),
        "keys.typed holds a typed key's time only; \"code\" is refused (spec §11 CU-7)"
    );
}

#[test]
fn a_shortcut_holds_cmd_or_ctrl_and_clean_tokens() {
    for (keys, why) in [
        ("shift+k", "it holds neither cmd nor ctrl"),
        ("k", "it holds neither cmd nor ctrl"),
        ("cmd+", "a token is empty"),
        ("", "a token is empty"),
        ("cmd++k", "a token is empty"),
        ("cmd+ k", "a token holds whitespace"),
        ("cmd+page\tdown", "a token holds whitespace"),
    ] {
        let mut v = minimal();
        v["keys"]["shortcut"] = json!({"t": [5], "keys": [keys], "code": [1]});
        assert_eq!(
            refused(&v),
            format!("keys.shortcut.keys[0] \"{keys}\" is not a shortcut: {why} (spec §11 CU-7)")
        );
    }
}

/// One change to [`full`].
type Edit = fn(&mut Value);

#[test]
fn every_check_refuses_in_its_own_sentence() {
    let cases: Vec<(Edit, &str)> = vec![
        (
            |v| v["anchor_host_us"] = json!(-1),
            "anchor_host_us is -1; a host time is never negative",
        ),
        (
            |v| v["pixels_per_point"] = json!(0),
            "pixels_per_point is 0; it must be a finite number above 0",
        ),
        (
            |v| v["content_size"] = json!([0, 10]),
            "content_size [0, 10] is outside 1…16384",
        ),
        (
            |v| v["movie_size"] = json!([16385, 10]),
            "movie_size [16385, 10] is outside 1…16384",
        ),
        (
            |v| v["moves"]["x"] = json!([1, 2, 3]),
            "moves.x has 3 entries and moves.t has 4; a column's entries match its siblings'",
        ),
        (
            |v| v["clicks"]["count"] = json!([1]),
            "clicks.count has 1 entries and clicks.t has 2; a column's entries match its \
             siblings'",
        ),
        (
            |v| v["keys"]["shortcut"]["code"] = json!([]),
            "keys.shortcut.code has 0 entries and keys.shortcut.t has 2; a column's entries \
             match its siblings'",
        ),
        (
            |v| v["moves"]["t"][0] = json!(-1),
            "moves.t[0] is -1, a negative time",
        ),
        (
            |v| v["moves"]["t"][3] = json!(8000),
            "moves.t[3] is 8000, before moves.t[2] (8333); a column's times never go back",
        ),
        (
            |v| v["geometry"][1]["t"] = json!(-4),
            "geometry.t[1] is -4, a negative time",
        ),
        (
            |v| v["keys"]["typed"]["t"] = json!([5, 4]),
            "keys.typed.t[1] is 4, before keys.typed.t[0] (5); a column's times never go back",
        ),
        (
            |v| v["hidden"] = json!({"from": [10, 30], "to": [20, 30]}),
            "hidden span 1 is empty (from 30 to 30)",
        ),
        (
            |v| v["hidden"] = json!({"from": [10, 5], "to": [20, 8]}),
            "hidden span 1 (from 5) starts before hidden span 0 (from 10); spans are in order",
        ),
        (
            |v| v["hidden"] = json!({"from": [10, 19], "to": [20, 25]}),
            "hidden span 1 (from 19) overlaps hidden span 0 (to 20)",
        ),
        (
            |v| v["hidden"] = json!({"from": [-3], "to": [20]}),
            "hidden.from[0] is -3, a negative time",
        ),
        (
            |v| v["images"][0]["png"] = json!("iVBO*w=="),
            "images[0].png is not base64: byte 0x2a at 4 is outside the base64 alphabet",
        ),
        (
            |v| v["images"][0]["png"] = json!("iVBORw0"),
            "images[0].png is not base64: its length 7 is not a multiple of 4",
        ),
        (
            |v| v["images"][0]["png"] = json!("iV=ORw0K"),
            "images[0].png is not base64: \"=\" at 2 comes before its end",
        ),
        (
            |v| v["images"][0]["png"] = json!("iVBOR==="),
            "images[0].png is not base64: it ends in more than two \"=\"",
        ),
        (
            |v| v["images"][1]["png"] = json!(base64(b"GIF89a")),
            "images[1].png is not a PNG: its bytes do not begin with the PNG signature",
        ),
        (
            |v| v["images"][2]["hot_x"] = json!(1601),
            "images[2]'s hot spot (1601, 800) lies outside its size (1600 × 1600)",
        ),
        (
            |v| v["images"][0]["hot_y"] = json!(-1),
            "images[0]'s hot spot (400, -1) lies outside its size (1600 × 2400)",
        ),
        (
            |v| v["image_changes"]["id"][1] = json!(3),
            "image_changes.id[1] is 3; the file has 3 images",
        ),
        (
            |v| v["image_changes"]["id"][0] = json!(-1),
            "image_changes.id[0] is -1; the file has 3 images",
        ),
        (
            |v| v["cursor_image"] = json!("none"),
            "cursor_image is \"none\", yet the file holds 3 images and 3 image changes",
        ),
        (
            |v| v["clicks"]["button"][1] = json!(32),
            "clicks.button[1] is 32; a button is 0…31",
        ),
        (
            |v| v["clicks"]["down"][0] = json!(2),
            "clicks.down[0] is 2; down is 0 or 1",
        ),
        (
            |v| v["clicks"]["count"][0] = json!(0),
            "clicks.count[0] is 0; a click count is at least 1",
        ),
        (
            |v| v["geometry"] = json!([]),
            "geometry holds no entry; a cursor file has at least one",
        ),
        (
            |v| v["geometry"][1]["content_scale"] = json!(-0.5),
            "geometry[1].content_scale is -0.5; it must be a finite number above 0",
        ),
        (
            |v| v["geometry"][0]["scale_factor"] = json!(0.0),
            "geometry[0].scale_factor is 0; it must be a finite number above 0",
        ),
    ];
    for (edit, sentence) in cases {
        let mut v = full();
        edit(&mut v);
        assert_eq!(refused(&v), sentence);
    }
    // `none` with image changes but no images.
    let mut v = minimal();
    v["cursor_image"] = json!("none");
    v["image_changes"] = json!({"t": [0], "id": [0]});
    assert_eq!(
        refused(&v),
        "image_changes.id[0] is 0; the file has 0 images"
    );
}

#[test]
fn hidden_spans_may_touch_but_not_overlap() {
    let mut touching = minimal();
    touching["hidden"] = json!({"from": [0, 10, 20], "to": [10, 20, 30]});
    assert_eq!(open(&touching), Ok(()));
    let mut overlapping = minimal();
    overlapping["hidden"] = json!({"from": [0, 9], "to": [10, 20]});
    assert_eq!(
        refused(&overlapping),
        "hidden span 1 (from 9) overlaps hidden span 0 (to 10)"
    );
}

/// `name`'s count at `cap` accepted and one past it refused with
/// `"<name> holds <n> entries; its cap is <cap>"`.
fn at_and_past(name: &str, cap: usize, body: impl Fn(usize) -> Vec<u8>) {
    assert_eq!(open_bytes(&body(cap)), Ok(()), "{name} at its cap");
    assert_eq!(
        open_bytes(&body(cap + 1)),
        Err(format!(
            "{name} holds {} entries; its cap is {cap}",
            cap + 1
        )),
        "{name} one past its cap"
    );
}

#[test]
fn every_column_is_capped() {
    let column = |key: &str, columns: &[(&str, &str)]| {
        let mut v = minimal();
        let mut object = serde_json::Map::new();
        for (name, _) in columns {
            object.insert(name.to_string(), json!(format!("@{name}@")));
        }
        v[key] = Value::Object(object);
        v
    };
    let fill = |v: &Value, columns: &[(&str, &str)], n: usize| {
        let fills: Vec<(&str, String)> = columns
            .iter()
            .map(|(name, item)| (*name, repeated(item, n)))
            .collect();
        with_text(v, &fills)
    };
    let moves = [("t", "0"), ("x", "1"), ("y", "2")];
    let m = column("moves", &moves);
    at_and_past("moves", MAX_MOVES, |n| fill(&m, &moves, n));
    let scrolls = [
        ("t", "0"),
        ("x", "1"),
        ("y", "2"),
        ("dx", "-3"),
        ("dy", "4"),
    ];
    let s = column("scrolls", &scrolls);
    at_and_past("scrolls", MAX_SCROLLS, |n| fill(&s, &scrolls, n));
    let dirty = [("t", "0"), ("x", "1"), ("y", "2"), ("w", "3"), ("h", "4")];
    let d = column("dirty", &dirty);
    at_and_past("dirty", MAX_DIRTY, |n| fill(&d, &dirty, n));
    let clicks = [
        ("t", "0"),
        ("button", "0"),
        ("down", "1"),
        ("x", "1"),
        ("y", "1"),
        ("count", "1"),
    ];
    let c = column("clicks", &clicks);
    at_and_past("clicks", MAX_CLICKS, |n| fill(&c, &clicks, n));

    let mut images = minimal();
    images["images"] = json!("@images@");
    images["cursor_image"] = json!("current-system");
    let image = format!(
        r#"{{"png":"{}","hot_x":0,"hot_y":0,"w":100,"h":100}}"#,
        base64(&PNG)
    );
    at_and_past("images", MAX_IMAGES, |n| {
        with_text(&images, &[("images", repeated(&image, n))])
    });

    let mut changes = minimal();
    changes["images"] = json!([{"png": base64(&PNG), "hot_x": 0, "hot_y": 0, "w": 1, "h": 1}]);
    let ic = [("t", "0"), ("id", "0")];
    let mut changes_column = column("image_changes", &ic);
    changes_column["images"] = changes["images"].clone();
    at_and_past("image_changes", MAX_IMAGE_CHANGES, |n| {
        fill(&changes_column, &ic, n)
    });

    let mut hidden = minimal();
    hidden["hidden"] = json!({"from": "@from@", "to": "@to@"});
    let spans = |n: usize, offset: usize| {
        let items: Vec<String> = (0..n).map(|i| (2 * i + offset).to_string()).collect();
        format!("[{}]", items.join(","))
    };
    at_and_past("hidden", MAX_HIDDEN, |n| {
        with_text(&hidden, &[("from", spans(n, 0)), ("to", spans(n, 1))])
    });

    let mut geometry = minimal();
    geometry["geometry"] = json!("@geometry@");
    let entry = r#"{"t":0,"screen_rect":[0,0,1,1],"content_rect":[0,0,1,1],"content_scale":1,"scale_factor":1}"#;
    at_and_past("geometry", MAX_GEOMETRY, |n| {
        with_text(&geometry, &[("geometry", repeated(entry, n))])
    });

    let mut shortcut = minimal();
    shortcut["keys"]["shortcut"] = json!({"t": "@t@", "keys": "@keys@", "code": "@code@"});
    at_and_past("keys.shortcut", MAX_SHORTCUTS, |n| {
        with_text(
            &shortcut,
            &[
                ("t", repeated("0", n)),
                ("keys", repeated("\"cmd+k\"", n)),
                ("code", repeated("40", n)),
            ],
        )
    });

    let mut typed = minimal();
    typed["keys"]["typed"] = json!({"t": "@t@"});
    at_and_past("keys.typed", MAX_TYPED, |n| {
        with_text(&typed, &[("t", repeated("0", n))])
    });
}

#[test]
fn one_png_is_capped_at_a_mebibyte() {
    let png_of = |len: usize| {
        let mut bytes = vec![0u8; len];
        bytes[..8].copy_from_slice(&PNG[..8]);
        bytes
    };
    let mut v = minimal();
    v["images"] = json!([{"png": base64(&png_of(MAX_IMAGE_BYTES)), "hot_x": 0, "hot_y": 0,
                          "w": 1, "h": 1}]);
    assert_eq!(open(&v), Ok(()));
    v["images"][0]["png"] = json!(base64(&png_of(MAX_IMAGE_BYTES + 1)));
    assert_eq!(
        refused(&v),
        format!(
            "images[0].png is {} bytes; its cap is {MAX_IMAGE_BYTES}",
            MAX_IMAGE_BYTES + 1
        )
    );
}

#[test]
fn the_header_states_the_same_cursor_file_version_as_the_core() {
    let header = include_str!("../include/framejob_core.h");
    let stated = header
        .lines()
        .find_map(|line| line.strip_prefix("#define RC_CURSOR_FILE_VERSION "))
        .expect("the header has a `#define RC_CURSOR_FILE_VERSION <n>` line");
    assert_eq!(
        stated.trim().parse::<u32>().ok(),
        Some(RC_CURSOR_FILE_VERSION)
    );
}

#[test]
fn null_bytes_are_refused_by_name() {
    let mut err: *mut c_char = ptr::null_mut();
    assert!(unsafe { rc_cursor_open(ptr::null(), 0, &mut err) }.is_null());
    assert_eq!(take_string(err).as_deref(), Some("bytes is NULL"));
    assert!(unsafe { rc_cursor_open(ptr::null(), 0, ptr::null_mut()) }.is_null());
    unsafe { rc_cursor_free(ptr::null_mut()) };
}
