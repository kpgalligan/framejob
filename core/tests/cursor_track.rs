//! A cursor file evaluated (spec §11 CU-20…CU-25), black box through
//! `rc_cursor_open` and `rc_cursor_query` as `ReelCore+Cursor.swift` calls
//! them. Every fixture is written here and every answer computed by hand
//! from the decisions' rules, never read back from the code: the mapping
//! (M2, the geometry in force, the first entry before any), the raw path and
//! the hold rule, the pins (first and last moves, clicks, holds) and RDP's
//! scaled tolerance, `state` at an unprepared smoothing answering raw, idle
//! hide's fade and lead and hidden spans, ripples, the image in force and
//! its sizes, `image`, `events` (typing stretches by CU7's figures), `path`
//! at 10 Hz, and every refusal.
//!
//! A linear or collinear-uniform answer is held to 1e-9 px. A two-pin
//! smoothed segment is held to its smoothstep to 1e-5 px: the knot floor
//! (1e-6, CU-21) at a duplicated end moves it by at most the floor over the
//! knot span times the segment's length (under 7e-6 px in these fixtures).

mod common;

use std::ffi::{c_char, CString};
use std::ptr;

use common::take_string;
use framejob_core::cursor_track::CursorTrack;
use framejob_core::ffi_cursor::{rc_cursor_free, rc_cursor_open, rc_cursor_query};
use serde_json::{json, Value};

const PNG: [u8; 12] = [0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13];

/// Standard-alphabet, padded base64, from RFC 4648 §4 (the oracle).
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

/// µs to source ticks (600,000 a second); every fixture time is a multiple
/// of 5 µs, so this is exact.
fn ticks(us: i64) -> i64 {
    assert_eq!(us % 5, 0);
    us / 5 * 3
}

/// Every key, every column empty; pixels per point 2 and one geometry entry
/// at the origin with content scale 1, so a file unit (points × 100) is
/// 1/50 px.
fn base() -> Value {
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

fn with_moves(t: &[i64], x: &[i64], y: &[i64]) -> Value {
    let mut v = base();
    v["moves"] = json!({"t": t, "x": x, "y": y});
    v
}

/// Down clicks (button 0, count 1) at `(t, x, y)`.
fn with_downs(mut v: Value, downs: &[(i64, i64, i64)]) -> Value {
    let n = downs.len();
    v["clicks"] = json!({
        "t": downs.iter().map(|d| d.0).collect::<Vec<_>>(),
        "button": vec![0; n], "down": vec![1; n],
        "x": downs.iter().map(|d| d.1).collect::<Vec<_>>(),
        "y": downs.iter().map(|d| d.2).collect::<Vec<_>>(),
        "count": vec![1; n],
    });
    v
}

struct Track(*mut CursorTrack);

impl Track {
    fn open(body: &Value) -> Track {
        let bytes = serde_json::to_vec(body).unwrap();
        let mut err: *mut c_char = ptr::null_mut();
        let handle = unsafe { rc_cursor_open(bytes.as_ptr(), bytes.len(), &mut err) };
        assert!(!handle.is_null(), "open refused: {:?}", take_string(err));
        Track(handle)
    }

    fn ask(&self, request: Value) -> Result<Value, String> {
        ask_many(&[self], request)
    }

    fn ok(&self, request: Value) -> Value {
        self.ask(request).expect("the request was refused")
    }

    fn state(&self, at: i64, props: Value) -> Value {
        self.ok(json!({"state": {"at": at, "props": props}}))
    }
}

impl Drop for Track {
    fn drop(&mut self) {
        unsafe { rc_cursor_free(self.0) };
    }
}

fn ask_many(tracks: &[&Track], request: Value) -> Result<Value, String> {
    let pointers: Vec<*const CursorTrack> = tracks.iter().map(|t| t.0 as *const _).collect();
    let text = CString::new(request.to_string()).unwrap();
    let mut err: *mut c_char = ptr::null_mut();
    let answer = unsafe {
        rc_cursor_query(
            pointers.as_ptr(),
            pointers.len(),
            ptr::null(),
            text.as_ptr(),
            &mut err,
        )
    };
    if answer.is_null() {
        return Err(take_string(err).expect("NULL without a sentence"));
    }
    assert!(err.is_null(), "an answer AND a sentence");
    Ok(serde_json::from_str(&take_string(answer).unwrap()).unwrap())
}

fn close(actual: &Value, expected: f64, tolerance: f64) {
    let a = actual.as_f64().expect("a number");
    assert!(
        (a - expected).abs() <= tolerance,
        "{a} is not {expected} (± {tolerance})"
    );
}

fn xy(answer: &Value, x: f64, y: f64, tolerance: f64) {
    close(&answer["x"], x, tolerance);
    close(&answer["y"], y, tolerance);
}

/// `s²(3 − 2s)`: a two-pin centripetal segment with both neighbours
/// duplicated, in the knot floor's limit.
fn smoothstep(s: f64) -> f64 {
    s * s * (3.0 - 2.0 * s)
}

#[test]
fn the_mapping_reads_the_geometry_in_force_and_the_first_entry_before_any() {
    let mut v = with_moves(&[0, 1_000_000], &[30000, 30000], &[40000, 40000]);
    v["geometry"] = json!([
        {"t": 100, "screen_rect": [10000, 20000, 100000, 100000],
         "content_rect": [1000, 2000, 100000, 100000], "content_scale": 0.5, "scale_factor": 2.0},
        {"t": 500000, "screen_rect": [0, 0, 100000, 100000],
         "content_rect": [0, 0, 100000, 100000], "content_scale": 1.0, "scale_factor": 2.0}
    ]);
    let track = Track::open(&v);
    // Before any entry, the first: (300 − 100) × 0.5 × 2 + 10 × 2, (400 − 200) × 0.5 × 2 + 20 × 2.
    let first = track.state(0, json!({}));
    xy(&first, 220.0, 240.0, 1e-9);
    close(&first["px_per_point"], 1.0, 1e-12);
    // Past the second entry: 300 × 2, 400 × 2.
    let second = track.state(ticks(600_000), json!({}));
    xy(&second, 600.0, 800.0, 1e-9);
    close(&second["px_per_point"], 2.0, 1e-12);
}

#[test]
fn the_mapping_is_m2_scale_factor_not_pixels_per_point() {
    // A display recorded at Nominal on a 2× panel (CU-S2's `mapping_display=M2`): the stream is
    // the point size, so pixels per point 1, content scale 0.5 and scale factor 2. M2 maps a
    // point p to (p − origin) × 0.5 × 2 = p px; M1 (pixels per point for scale factor) would
    // answer p × 0.5 × 1 = p / 2.
    let mut v = with_moves(&[0], &[30000], &[40000]);
    v["pixels_per_point"] = json!(1.0);
    v["content_size"] = json!([1512, 982]);
    v["movie_size"] = json!([1512, 982]);
    v["geometry"] = json!([
        {"t": 0, "screen_rect": [0, 0, 151200, 98200], "content_rect": [0, 0, 75600, 49100],
         "content_scale": 0.5, "scale_factor": 2.0}
    ]);
    let track = Track::open(&v);
    let state = track.state(0, json!({}));
    xy(&state, 300.0, 400.0, 1e-9);
    close(&state["px_per_point"], 1.0, 1e-12);
    // A content rect's origin is in points and lands at × scale factor: (300 − 100) × 0.5 × 2
    // + 10 × 2 = 220.
    v["geometry"] = json!([
        {"t": 0, "screen_rect": [10000, 20000, 151200, 98200],
         "content_rect": [1000, 2000, 75600, 49100], "content_scale": 0.5, "scale_factor": 2.0}
    ]);
    let moved = Track::open(&v);
    xy(&moved.state(0, json!({})), 220.0, 240.0, 1e-9);
}

#[test]
fn the_raw_path_is_linear_and_holds_a_gap_until_one_poll_before_the_next_move() {
    let v = with_moves(
        &[0, 10_000, 20_000, 120_000],
        &[0, 1000, 2000, 5000],
        &[0, 0, 0, 0],
    );
    let track = Track::open(&v);
    xy(&track.state(ticks(5_000), json!({})), 10.0, 0.0, 1e-9);
    xy(&track.state(ticks(15_000), json!({})), 30.0, 0.0, 1e-9);
    // Inside the hold (20,000 → 111,667): move 2 exactly, at every smoothing.
    xy(&track.state(ticks(60_000), json!({})), 40.0, 0.0, 1e-9);
    track.ok(json!({"prepare": {"smoothing": 0.5}}));
    xy(
        &track.state(ticks(60_000), json!({"smoothing": 0.5})),
        40.0,
        0.0,
        1e-9,
    );
    // After it: linear from (111,667, 2000) to (120,000, 5000).
    let x = (2000.0 + 3000.0 * (115_000.0 - 111_667.0) / (120_000.0 - 111_667.0)) / 50.0;
    xy(&track.state(ticks(115_000), json!({})), x, 0.0, 1e-9);
    // Past the last move, the last.
    xy(&track.state(ticks(200_000), json!({})), 100.0, 0.0, 1e-9);
}

#[test]
fn a_smoothed_path_passes_through_its_clicks_and_is_linear_between_uniform_pins() {
    let t: Vec<i64> = (0..=6).map(|k| k * 10_000).collect();
    let x: Vec<i64> = (0..=6).map(|k| k * 1000).collect();
    let v = with_downs(
        with_moves(&t, &x, &[0; 7]),
        &[(20_000, 2000, 0), (40_000, 4000, 0)],
    );
    let track = Track::open(&v);
    let prepared = track.ok(json!({"prepare": {"smoothing": 0.5}}));
    assert_eq!(prepared, json!({"prepared": {"smoothing": 0.5, "kept": 4}}));
    let s = json!({"smoothing": 0.5});
    xy(&track.state(ticks(20_000), s.clone()), 40.0, 0.0, 1e-9);
    xy(&track.state(ticks(40_000), s.clone()), 80.0, 0.0, 1e-9);
    // Between the two clicks the four kept points are collinear and uniform.
    xy(&track.state(ticks(25_000), s.clone()), 50.0, 0.0, 1e-9);
    xy(&track.state(ticks(35_000), s), 70.0, 0.0, 1e-9);
}

#[test]
fn a_click_off_the_moves_is_where_the_smoothed_cursor_is_when_it_clicks() {
    let t: Vec<i64> = (0..=6).map(|k| k * 10_000).collect();
    let x: Vec<i64> = (0..=6).map(|k| k * 1000).collect();
    let v = with_downs(with_moves(&t, &x, &[0; 7]), &[(30_000, 3000, 600)]);
    let track = Track::open(&v);
    track.ok(json!({"prepare": {"smoothing": 1.0}}));
    xy(
        &track.state(ticks(30_000), json!({"smoothing": 1.0})),
        60.0,
        12.0,
        1e-9,
    );
}

#[test]
fn rdp_tolerance_grows_with_smoothing() {
    // The middle move is 5 pt off the chord: kept under 12 pt × 0.25, dropped under 12 pt × 1.
    let track = Track::open(&with_moves(
        &[0, 10_000, 20_000],
        &[0, 1000, 2000],
        &[0, 500, 0],
    ));
    let kept = |s: f64| track.ok(json!({"prepare": {"smoothing": s}}))["prepared"]["kept"].clone();
    assert_eq!(kept(0.25), json!(3));
    assert_eq!(kept(1.0), json!(2));
    // At 0, the moves, and nothing is stored.
    assert_eq!(kept(0.0), json!(3));
    assert_eq!(
        track.ok(json!({"unprepare": {"smoothing": 0}})),
        json!({"unprepared": false})
    );
}

#[test]
fn a_continuous_run_with_no_click_has_its_ends_pinned() {
    let t: Vec<i64> = (0..=6).map(|k| k * 10_000).collect();
    let v = with_moves(
        &t,
        &[0, 900, 2100, 2900, 4200, 4800, 6000],
        &[0, 300, -200, 100, 400, -300, 0],
    );
    let track = Track::open(&v);
    track.ok(json!({"prepare": {"smoothing": 0.5}}));
    let s = json!({"smoothing": 0.5});
    xy(&track.state(0, s.clone()), 0.0, 0.0, 1e-9);
    xy(&track.state(ticks(60_000), s.clone()), 120.0, 0.0, 1e-9);
    xy(&track.state(ticks(90_000), s), 120.0, 0.0, 1e-9);
}

#[test]
fn a_hold_is_held_exactly_when_smoothed() {
    let track = Track::open(&with_moves(
        &[0, 10_000, 100_000],
        &[0, 1000, 3000],
        &[0, 0, 0],
    ));
    // First, both hold ends, last.
    let kept = track.ok(json!({"prepare": {"smoothing": 0.5}}));
    assert_eq!(kept["prepared"]["kept"], json!(4));
    for us in [10_000, 50_000, 90_000] {
        xy(
            &track.state(ticks(us), json!({"smoothing": 0.5})),
            20.0,
            0.0,
            1e-9,
        );
    }
}

#[test]
fn state_answers_raw_until_prepare_and_again_after_unprepare() {
    let t: Vec<i64> = (0..=6).map(|k| k * 10_000).collect();
    let x: Vec<i64> = (0..=6).map(|k| k * 1000).collect();
    let track = Track::open(&with_moves(&t, &x, &[0; 7]));
    let s = json!({"smoothing": 0.5});
    xy(&track.state(ticks(25_000), s.clone()), 50.0, 0.0, 1e-9);
    assert_eq!(
        track.ok(json!({"prepare": {"smoothing": 0.5}}))["prepared"]["kept"],
        json!(2)
    );
    let smoothed = 6000.0 * smoothstep(25_000.0 / 60_000.0) / 50.0;
    xy(&track.state(ticks(25_000), s.clone()), smoothed, 0.0, 1e-5);
    assert_eq!(
        track.ok(json!({"unprepare": {"smoothing": 0.5}})),
        json!({"unprepared": true})
    );
    xy(&track.state(ticks(25_000), s), 50.0, 0.0, 1e-9);
    assert_eq!(
        track.ok(json!({"unprepare": {"smoothing": 0.5}})),
        json!({"unprepared": false})
    );
}

#[test]
fn idle_hide_fades_after_the_idle_time_and_returns_ahead_of_the_next_activity() {
    let mut v = with_downs(
        with_moves(&[0, 3_000_000], &[0, 1000], &[0, 0]),
        &[(1_000_000, 500, 0)],
    );
    v["hidden"] = json!({"from": [2_000_000], "to": [2_100_000]});
    let track = Track::open(&v);
    let idle = json!({"hide_idle": 0.5});
    let opacity = |us: i64, props: &Value| track.state(ticks(us), props.clone());
    close(&opacity(400_000, &idle)["opacity"], 1.0, 0.0);
    close(&opacity(600_000, &idle)["opacity"], 0.5, 1e-12);
    let gone = opacity(800_000, &idle);
    close(&gone["opacity"], 0.0, 0.0);
    assert_eq!(gone["visible"], json!(false));
    // 150 ms before the click, at once.
    close(&opacity(900_000, &idle)["opacity"], 1.0, 0.0);
    // The click is activity.
    close(&opacity(1_200_000, &idle)["opacity"], 1.0, 0.0);
    // A hidden span hides, whatever else holds.
    close(&opacity(2_050_000, &json!({}))["opacity"], 0.0, 0.0);
    close(&opacity(2_100_000, &idle)["opacity"], 0.0, 0.0);
    close(&opacity(600_000, &json!({}))["opacity"], 1.0, 0.0);
    let none = Track::open(&base());
    assert_eq!(none.state(0, json!({}))["visible"], json!(false));
}

#[test]
fn ripples_run_for_450_ms_newest_first_at_most_four() {
    let mut v = with_downs(
        with_moves(&[0], &[0], &[0]),
        &[
            (100_000, 100, 0),
            (200_000, 200, 0),
            (300_000, 300, 0),
            (400_000, 400, 0),
            (500_000, 500, 0),
        ],
    );
    // An up click between them is no ripple.
    v["clicks"]["t"] = json!([100_000, 150_000, 200_000, 300_000, 400_000, 500_000]);
    v["clicks"]["button"] = json!([0, 0, 0, 0, 0, 0]);
    v["clicks"]["down"] = json!([1, 0, 1, 1, 1, 1]);
    v["clicks"]["x"] = json!([100, 150, 200, 300, 400, 500]);
    v["clicks"]["y"] = json!([0, 0, 0, 0, 0, 0]);
    v["clicks"]["count"] = json!([1, 1, 1, 1, 1, 1]);
    let track = Track::open(&v);
    let ripple = json!({"clicks": "ripple"});
    let at = |us: i64| track.state(ticks(us), ripple.clone())["ripples"].clone();
    let expect = |list: &Value, rows: &[(f64, f64)]| {
        let list = list.as_array().unwrap();
        assert_eq!(list.len(), rows.len(), "{list:?}");
        for (r, &(x, phase)) in list.iter().zip(rows) {
            close(&r["x"], x, 1e-9);
            close(&r["phase"], phase, 1e-12);
        }
    };
    expect(
        &at(520_000),
        &[
            (10.0, 20_000.0 / 450_000.0),
            (8.0, 120_000.0 / 450_000.0),
            (6.0, 220_000.0 / 450_000.0),
            (4.0, 320_000.0 / 450_000.0),
        ],
    );
    expect(
        &at(800_000),
        &[(10.0, 300_000.0 / 450_000.0), (8.0, 400_000.0 / 450_000.0)],
    );
    expect(&at(850_000), &[(10.0, 350_000.0 / 450_000.0)]);
    assert_eq!(track.state(ticks(520_000), json!({}))["ripples"], json!([]));
}

#[test]
fn the_image_in_force_is_sized_in_px_and_image_answers_its_png() {
    let mut v = with_moves(&[0], &[0], &[0]);
    v["images"] = json!([
        {"png": base64(&PNG), "hot_x": 400, "hot_y": 400, "w": 1600, "h": 2400, "kind": "arrow"},
        {"png": base64(&PNG[..9]), "hot_x": 0, "hot_y": 1600, "w": 1600, "h": 1600}
    ]);
    v["image_changes"] = json!({"t": [100_000, 500_000], "id": [1, 0]});
    let track = Track::open(&v);
    let scaled = json!({"scale": 1.5});
    assert_eq!(
        track.state(ticks(50_000), scaled.clone())["image"],
        Value::Null
    );
    assert_eq!(
        track.state(ticks(200_000), scaled.clone())["image"],
        json!({"id": 1, "w": 48.0, "h": 48.0, "hot_x": 0.0, "hot_y": 48.0})
    );
    assert_eq!(
        track.state(ticks(600_000), scaled)["image"],
        json!({"id": 0, "w": 48.0, "h": 72.0, "hot_x": 12.0, "hot_y": 12.0})
    );
    assert_eq!(
        track.ok(json!({"image": {"id": 0}})),
        json!({"id": 0, "png": base64(&PNG), "w": 16.0, "h": 24.0, "hot_x": 4.0, "hot_y": 4.0,
               "kind": "arrow"})
    );
    assert_eq!(track.ok(json!({"image": {"id": 1}}))["kind"], Value::Null);
    assert_eq!(
        track.ask(json!({"image": {"id": 2}})),
        Err("image 2 is not in this cursor file (it has 2)".to_string())
    );
    assert_eq!(
        track.ask(json!({"image": {"id": -1}})),
        Err("image -1 is not in this cursor file (it has 2)".to_string())
    );
    let mut none = with_moves(&[0], &[0], &[0]);
    none["cursor_image"] = json!("none");
    assert_eq!(Track::open(&none).state(0, json!({}))["image"], Value::Null);
}

#[test]
fn events_answer_only_the_kinds_asked_within_the_range() {
    let mut v = with_moves(&[0], &[0], &[0]);
    v["clicks"] = json!({"t": [500_000, 600_000, 5_000_000], "button": [0, 1, 0],
                         "down": [1, 0, 1], "x": [100, 200, 300], "y": [50, 60, 70],
                         "count": [1, 2, 1]});
    v["scrolls"] = json!({"t": [1_000_000], "x": [500], "y": [600], "dx": [-150], "dy": [300]});
    v["keys"]["shortcut"] = json!({"t": [2_000_000], "keys": ["cmd+s"], "code": [1]});
    v["keys"]["typed"] = json!({"t": [0, 500_000, 900_000, 3_000_000, 3_200_000, 5_000_000,
                                      5_100_000, 5_200_000, 5_300_000, 7_000_000, 8_000_000,
                                      8_500_000, 9_000_000]});
    let track = Track::open(&v);
    let (from, to) = (ticks(600_000), ticks(5_000_000));
    let asked =
        track.ok(json!({"events": {"from": from, "to": to, "kinds": ["typing", "clicks"]}}));
    assert_eq!(
        asked,
        json!({
            "clicks": [{"t": ticks(600_000), "button": 1, "down": 0, "x": 4.0, "y": 1.2,
                        "count": 2}],
            "typing": [{"from": 0, "to": ticks(900_000), "marks": 3}],
        })
    );
    let rest = track.ok(json!({"events": {"from": 0, "to": ticks(10_000_000),
                                          "kinds": ["scrolls", "shortcuts", "typing"]}}));
    assert_eq!(
        rest["scrolls"],
        json!([{"t": ticks(1_000_000), "x": 10.0, "y": 12.0, "dx": -1.5, "dy": 3.0}])
    );
    assert_eq!(
        rest["shortcuts"],
        json!([{"t": ticks(2_000_000), "keys": "cmd+s", "code": 1}])
    );
    // Two marks are no stretch, and a gap of exactly 1.0 s splits one.
    assert_eq!(
        rest["typing"],
        json!([
            {"from": 0, "to": ticks(900_000), "marks": 3},
            {"from": ticks(5_000_000), "to": ticks(5_300_000), "marks": 4},
            {"from": ticks(8_000_000), "to": ticks(9_000_000), "marks": 3},
        ])
    );
    assert!(rest.get("clicks").is_none());
    assert_eq!(
        track.ask(json!({"events": {"from": 10, "to": 5, "kinds": []}})),
        Err("to (5) is before from (10)".to_string())
    );
}

#[test]
fn path_samples_at_10_hz_raw_and_smoothed_and_never_stores() {
    let t: Vec<i64> = (0..=100).map(|k| k * 10_000).collect();
    let x: Vec<i64> = (0..=100).map(|k| k * 1000).collect();
    let track = Track::open(&with_moves(&t, &x, &[0; 101]));
    let raw = track.ok(json!({"path": {"from": 0, "to": 600_000, "step": 60_000,
                                       "smoothing": 0}}));
    let ts: Vec<i64> = (0..10).map(|k| k * 60_000).collect();
    assert_eq!(raw["t"], json!(ts));
    for k in 0..10 {
        close(&raw["x"][k], k as f64 * 200.0, 1e-9);
        close(&raw["y"][k], 0.0, 0.0);
    }
    let smooth = track.ok(json!({"path": {"from": 0, "to": 600_000, "step": 60_000,
                                          "smoothing": 0.5}}));
    for k in 0..10 {
        let expected = 100_000.0 * smoothstep(k as f64 / 10.0) / 50.0;
        close(&smooth["x"][k], expected, 1e-5);
    }
    assert_eq!(
        track.ok(json!({"unprepare": {"smoothing": 0.5}})),
        json!({"unprepared": false})
    );
    assert_eq!(
        track.ask(json!({"path": {"from": 0, "to": 600_000, "step": 59_999, "smoothing": 0}})),
        Err(
            "path's step is 59999 ticks; a path is sampled at most 10 times a second \
             (step ≥ 60000)"
                .to_string()
        )
    );
    let over: i64 = 144_000 * 60_000 + 1;
    assert_eq!(
        track.ask(json!({"path": {"from": 0, "to": over, "step": 60_000, "smoothing": 0}})),
        Err(format!(
            "path's range from 0 to {over} at step 60000 is 144001 samples; a path holds at \
             most 144000"
        ))
    );
    assert_eq!(
        track.ask(json!({"path": {"from": 9, "to": 3, "step": 60_000, "smoothing": 0}})),
        Err("to (3) is before from (9)".to_string())
    );
}

#[test]
fn every_refusal_is_its_own_sentence() {
    let track = Track::open(&with_moves(&[0], &[0], &[0]));
    let refused = |r: Value| track.ask(r).expect_err("expected a refusal");
    let starts = |r: Value, head: &str| {
        let sentence = refused(r);
        assert!(
            sentence.starts_with(head),
            "{sentence:?} does not start {head:?}"
        );
    };
    starts(
        json!({"stat": {}}),
        "the cursor request at \".\": unknown variant `stat`",
    );
    starts(
        json!({"state": {"at": 0, "prop": {}}}),
        "the cursor request at \"state.prop\": unknown field `prop`",
    );
    starts(
        json!({"prepare": {"smoothing": "a"}}),
        "the cursor request at \"prepare.smoothing\": ",
    );
    assert_eq!(
        refused(json!({"prepare": {"smoothing": 1.5}})),
        "smoothing is 1.5; it runs 0…1"
    );
    assert_eq!(
        refused(json!({"unprepare": {"smoothing": -0.5}})),
        "smoothing is -0.5; it runs 0…1"
    );
    assert_eq!(
        refused(json!({"state": {"at": 0, "props": {"scale": 0}}})),
        "scale is 0; it must be a finite number above 0"
    );
    assert_eq!(
        refused(json!({"state": {"at": 0, "props": {"hide_idle": -1}}})),
        "hide_idle is -1; it must be a finite number above 0"
    );
    // Props ignore keys they do not read: the recipe's object may be passed.
    track.ok(json!({"state": {"at": 0, "props": {"media": 3, "smoothing": 0, "x": "y"}}}));
    assert_eq!(
        ask_many(&[&track, &track], json!({"state": {"at": 0}})),
        Err("state reads one cursor track; 2 were given".to_string())
    );
    assert_eq!(
        ask_many(&[], json!({"prepare": {"smoothing": 0}})),
        Err("prepare reads one cursor track; 0 were given".to_string())
    );
}

#[test]
fn a_newer_file_with_only_v1_keys_is_refused_by_its_version() {
    let mut v = base();
    v["version"] = json!(2);
    let bytes = serde_json::to_vec(&v).unwrap();
    let mut err: *mut c_char = ptr::null_mut();
    let handle = unsafe { rc_cursor_open(bytes.as_ptr(), bytes.len(), &mut err) };
    assert!(handle.is_null());
    assert_eq!(
        take_string(err).as_deref(),
        Some("the cursor file is version 2; this Frame Job reads cursor files up to version 1")
    );
}

#[test]
fn state_with_ends_answers_each_end_as_a_state_at_that_tick() {
    // CU-115: each end equals a `state` asked at that tick, raw and smoothed
    // (prepared and unprepared alike); no `ends` key without the argument.
    let t: Vec<i64> = (0..=6).map(|k| k * 10_000).collect();
    let x: Vec<i64> = (0..=6).map(|k| k * 1000).collect();
    let y: Vec<i64> = (0..=6).map(|k| k * k * 300).collect();
    let track = Track::open(&with_moves(&t, &x, &y));
    let (at, t0, t1) = (ticks(25_000), ticks(15_000), ticks(45_000));
    for (smoothing, prepare) in [(0.0, false), (0.5, false), (0.5, true)] {
        if prepare {
            track.ok(json!({"prepare": {"smoothing": smoothing}}));
        }
        let props = json!({ "smoothing": smoothing });
        let answer = track.ok(json!({"state": {"at": at, "props": props, "ends": [t0, t1]}}));
        let plain = track.state(at, props.clone());
        assert_eq!(answer["x"], plain["x"]);
        assert_eq!(answer["y"], plain["y"]);
        assert!(plain.get("ends").is_none(), "{plain}");
        let first = track.state(t0, props.clone());
        let last = track.state(t1, props);
        assert_eq!(
            answer["ends"],
            json!([[first["x"], first["y"]], [last["x"], last["y"]]]),
            "smoothing {smoothing}, prepared {prepare}"
        );
        assert_ne!(answer["ends"][0], answer["ends"][1]);
    }
}
