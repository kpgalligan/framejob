//! The `.cube` parser (spec §11 GR-8), black box over the four `rc_cube_*`
//! exports exactly as `ReelCore.swift` calls them. Every file is written
//! here: the table by [`table`], whose row order is the format's own (red
//! fastest) spelled out as three nested loops, so the copied floats are
//! checked against an independent index rather than the parser's.
//!
//! Pinned: every refusal sentence, the line it names counted 1-based; sizes
//! 2 and 65 read and 1 and 66 refused; red fastest; comments, `TITLE`, blank
//! lines, CRLF, a BOM and the default domain and input range accepted; the
//! 32 MiB cap; the header's `RC_CUBE_MAX_BYTES` equal to the core's; the
//! FFI round trip, its length check and its NULLs.

mod common;

use std::ffi::c_char;
use std::ptr;

use common::take_string;
use reelcut_core::cube::{Cube, CUBE_SIZE_MAX, CUBE_SIZE_MIN};
use reelcut_core::ffi_cube::{rc_cube_copy_rgb, rc_cube_free, rc_cube_parse, rc_cube_size};
use reelcut_core::format::RC_CUBE_MAX_BYTES;

/// The output the test tables give input `(r, g, b)` of a size-`n` lattice:
/// distinct per channel and per point, so a transposed axis cannot pass.
fn value(n: usize, r: usize, g: usize, b: usize, channel: usize) -> f64 {
    let step = (n - 1) as f64;
    match channel {
        0 => r as f64 / step * 0.5 + g as f64 / step * 0.25,
        1 => g as f64 / step * 0.75 + b as f64 / step * 0.125,
        _ => b as f64 / step * 0.875 + r as f64 / step * 0.0625,
    }
}

/// `n³` rows, red fastest: blue is the outer loop, green the middle, red the
/// inner, which is what "red changes fastest" means.
fn table(n: usize) -> String {
    let mut out = String::new();
    for b in 0..n {
        for g in 0..n {
            for r in 0..n {
                out.push_str(&format!(
                    "{} {} {}\n",
                    value(n, r, g, b, 0),
                    value(n, r, g, b, 1),
                    value(n, r, g, b, 2)
                ));
            }
        }
    }
    out
}

fn cube(n: usize) -> String {
    format!("LUT_3D_SIZE {n}\n{}", table(n))
}

/// Parses through the FFI: the size and the table, or the sentence.
fn parse(bytes: &[u8]) -> Result<(u32, Vec<f32>), String> {
    let mut err: *mut c_char = ptr::null_mut();
    let handle = unsafe { rc_cube_parse(bytes.as_ptr(), bytes.len(), &mut err) };
    if handle.is_null() {
        return Err(take_string(err).expect("rc_cube_parse returned NULL without a reason"));
    }
    assert!(
        err.is_null(),
        "rc_cube_parse returned a handle AND a reason"
    );
    let size = unsafe { rc_cube_size(handle) };
    let count = (size as usize).pow(3) * 3;
    let mut rgb = vec![f32::NAN; count];
    let copied = unsafe { rc_cube_copy_rgb(handle, rgb.as_mut_ptr(), count) };
    unsafe { rc_cube_free(handle) };
    assert!(copied, "rc_cube_copy_rgb refused the exact count");
    Ok((size, rgb))
}

fn refused(text: &str) -> String {
    parse(text.as_bytes()).expect_err("this file was expected to be refused")
}

/// The table read back against [`value`] at the index red-fastest gives.
fn assert_table(n: usize, rgb: &[f32]) {
    assert_eq!(rgb.len(), n * n * n * 3);
    for b in 0..n {
        for g in 0..n {
            for r in 0..n {
                let row = r + g * n + b * n * n;
                for channel in 0..3 {
                    let want = value(n, r, g, b, channel) as f32;
                    assert_eq!(
                        rgb[row * 3 + channel],
                        want,
                        "({r}, {g}, {b}) channel {channel}"
                    );
                }
            }
        }
    }
}

#[test]
fn sizes_two_and_sixty_five_read_red_fastest() {
    assert_eq!((CUBE_SIZE_MIN, CUBE_SIZE_MAX), (2, 65));
    for n in [2usize, 33, 65] {
        let (size, rgb) = parse(cube(n).as_bytes()).expect("a plain cube reads");
        assert_eq!(size as usize, n);
        assert_table(n, &rgb);
    }
}

#[test]
fn an_asymmetric_size_two_table_is_red_fastest() {
    // Each row names its own input: row k of a size-2 table is r = k & 1,
    // g = (k >> 1) & 1, b = k >> 2.
    let rows = (0..8)
        .map(|k| format!("{} {} {}", k & 1, (k >> 1) & 1, k >> 2))
        .collect::<Vec<_>>()
        .join("\n");
    let (_, rgb) = parse(format!("LUT_3D_SIZE 2\n{rows}\n").as_bytes()).expect("reads");
    let want: Vec<f32> = vec![
        0., 0., 0., 1., 0., 0., 0., 1., 0., 1., 1., 0., 0., 0., 1., 1., 0., 1., 0., 1., 1., 1., 1.,
        1.,
    ];
    assert_eq!(rgb, want);
}

#[test]
fn the_accepted_variants_read_the_same_table() {
    let plain = parse(cube(3).as_bytes()).expect("plain");
    let dressed = format!(
        "\u{feff}# made by a script\r\nTITLE \"Film look\"\r\n\r\nDOMAIN_MIN 0 0 0\r\n\
         DOMAIN_MAX 1.0 1 1\r\nLUT_3D_INPUT_RANGE 0 1\r\n  # indented comment\r\n\
         LUT_3D_SIZE 3\r\n{}\r\n\r\n",
        table(3).trim_end().replace('\n', "\r\n")
    );
    assert_eq!(parse(dressed.as_bytes()).expect("dressed"), plain);
    let tabs = cube(3).replace(' ', "\t");
    assert_eq!(parse(tabs.as_bytes()).expect("tabs"), plain);
}

#[test]
fn table_values_are_any_finite_number() {
    let mut rows = ["-0.5 1.5 1e3"; 8];
    rows[1] = "0 0 0";
    let (_, rgb) = parse(format!("LUT_3D_SIZE 2\n{}\n", rows.join("\n")).as_bytes()).expect("ok");
    assert_eq!(&rgb[..6], &[-0.5, 1.5, 1000.0, 0.0, 0.0, 0.0]);
}

#[test]
fn each_refusal_names_its_line_and_what_was_on_it() {
    let t2 = table(2);
    let cases: Vec<(String, String)> = vec![
        (
            "# a 1D LUT\nLUT_1D_SIZE 1024\n".to_string(),
            "line 2: LUT_1D_SIZE is a 1D LUT; only 3D LUTs are read".to_string(),
        ),
        (
            "LUT_1D_INPUT_RANGE 0 1\n".to_string(),
            "line 1: LUT_1D_INPUT_RANGE is a 1D LUT; only 3D LUTs are read".to_string(),
        ),
        (
            "TITLE \"x\"\nLUT_3D_SIZE 200\n".to_string(),
            "line 2: LUT_3D_SIZE 200 is outside 2–65".to_string(),
        ),
        (
            "LUT_3D_SIZE 1\n0 0 0\n".to_string(),
            "line 1: LUT_3D_SIZE 1 is outside 2–65".to_string(),
        ),
        (
            "LUT_3D_SIZE 66\n".to_string(),
            "line 1: LUT_3D_SIZE 66 is outside 2–65".to_string(),
        ),
        (
            "LUT_3D_SIZE 2.5\n".to_string(),
            "line 1: LUT_3D_SIZE 2.5 is not a whole number".to_string(),
        ),
        (
            format!("LUT_3D_SIZE 2\nDOMAIN_MIN 0 0 -0.1\n{t2}"),
            "line 2: DOMAIN_MIN must be 0 0 0, not 0 0 -0.1".to_string(),
        ),
        (
            format!("DOMAIN_MAX 1 1 2\nLUT_3D_SIZE 2\n{t2}"),
            "line 1: DOMAIN_MAX must be 1 1 1, not 1 1 2".to_string(),
        ),
        (
            format!("LUT_3D_INPUT_RANGE 0 4095\nLUT_3D_SIZE 2\n{t2}"),
            "line 1: LUT_3D_INPUT_RANGE must be 0 1, not 0 4095".to_string(),
        ),
        (
            "LUT_3D_SIZE 2\nFOO 1\n".to_string(),
            "line 2: unknown keyword FOO".to_string(),
        ),
        (
            format!("LUT_3D_SIZE 2\n{t2}TITLE \"late\"\n"),
            "line 10: TITLE comes after the table".to_string(),
        ),
        (
            "LUT_3D_SIZE 2\nLUT_3D_SIZE 3\n".to_string(),
            "line 2: a second LUT_3D_SIZE".to_string(),
        ),
        (
            "DOMAIN_MAX 1 1\n".to_string(),
            "line 1: DOMAIN_MAX needs 3 numbers".to_string(),
        ),
        (
            "LUT_3D_SIZE\n".to_string(),
            "line 1: LUT_3D_SIZE needs 1 number".to_string(),
        ),
        (
            "LUT_3D_SIZE 2\n0 0 0\n0.5x 0 0\n".to_string(),
            "line 3: \"0.5x\" is not a number".to_string(),
        ),
        (
            "LUT_3D_SIZE 2\n0 0 0\n0 nan 0\n".to_string(),
            "line 3: nan is not a finite number".to_string(),
        ),
        (
            "LUT_3D_SIZE 2\n0 0 0\ninf 0 0\n".to_string(),
            "line 3: inf is not a finite number".to_string(),
        ),
        (
            "LUT_3D_SIZE 2\n\n0 0\n".to_string(),
            "line 3: a table row has 3 numbers, not 2".to_string(),
        ),
        (
            "LUT_3D_SIZE 2\n0 0 0 # a trailing comment\n".to_string(),
            "line 2: \"#\" is not a number".to_string(),
        ),
        // A table with no size line: its rows are counted, and the file
        // ends without the line that says how many it needs.
        (t2.clone(), "no LUT_3D_SIZE line".to_string()),
        (
            "# nothing\n\n".to_string(),
            "no LUT_3D_SIZE line".to_string(),
        ),
        (
            format!(
                "LUT_3D_SIZE 2\n{}",
                t2.lines().take(7).collect::<Vec<_>>().join("\n")
            ),
            "LUT_3D_SIZE 2 needs 8 table rows, not 7".to_string(),
        ),
        (
            format!("LUT_3D_SIZE 2\n{t2}0 0 0\n"),
            "LUT_3D_SIZE 2 needs 8 table rows, not 9".to_string(),
        ),
    ];
    for (text, want) in cases {
        assert_eq!(refused(&text), want, "{text:?}");
    }
    // A 33³ table one row short, the header's own example.
    let mut short = cube(33);
    let cut = short.trim_end().rfind('\n').expect("rows");
    short.truncate(cut + 1);
    assert_eq!(
        refused(&short),
        "LUT_3D_SIZE 33 needs 35937 table rows, not 35936"
    );
    // A size line after the table is a keyword after the table.
    assert_eq!(
        refused(&format!("{t2}LUT_3D_SIZE 2\n")),
        "line 9: LUT_3D_SIZE comes after the table"
    );
}

#[test]
fn a_file_that_is_not_text_is_refused() {
    assert_eq!(
        parse(&[0x4c, 0xff, 0xfe, 0x00]).unwrap_err(),
        "the file is not text"
    );
    assert_eq!(
        parse(b"LUT_3D_SIZE 2\n\0").unwrap_err(),
        "the file is not text"
    );
}

#[test]
fn the_size_cap_is_thirty_two_mib_and_the_header_states_it() {
    assert_eq!(RC_CUBE_MAX_BYTES, 32 * 1024 * 1024);
    let header = include_str!("../include/reelcut_core.h");
    let stated = header
        .lines()
        .find_map(|line| line.strip_prefix("#define RC_CUBE_MAX_BYTES "))
        .expect("the header has a `#define RC_CUBE_MAX_BYTES <n>` line");
    assert_eq!(stated.trim().parse::<usize>().ok(), Some(RC_CUBE_MAX_BYTES));
    // Exactly the cap is read as far as its text goes; one byte more is the
    // cap's sentence, before any line is looked at.
    let mut at_cap = cube(2).into_bytes();
    at_cap.resize(RC_CUBE_MAX_BYTES, b'\n');
    assert_eq!(parse(&at_cap).map(|(size, _)| size), Ok(2));
    at_cap.push(b'\n');
    assert_eq!(parse(&at_cap).unwrap_err(), "the file is larger than 32 MB");
}

#[test]
fn the_ffi_checks_the_count_and_tolerates_null() {
    let text = cube(2);
    let mut err: *mut c_char = ptr::null_mut();
    let handle = unsafe { rc_cube_parse(text.as_ptr(), text.len(), &mut err) };
    assert!(!handle.is_null() && err.is_null());
    let mut out = vec![7.0f32; 25];
    // One float short and one long: false, and nothing written.
    assert!(!unsafe { rc_cube_copy_rgb(handle, out.as_mut_ptr(), 23) });
    assert!(!unsafe { rc_cube_copy_rgb(handle, out.as_mut_ptr(), 25) });
    assert!(out.iter().all(|v| *v == 7.0));
    assert!(!unsafe { rc_cube_copy_rgb(handle, ptr::null_mut(), 24) });
    assert!(unsafe { rc_cube_copy_rgb(handle, out.as_mut_ptr(), 24) });
    assert_eq!(out[24], 7.0);
    unsafe { rc_cube_free(handle) };

    let mut err: *mut c_char = ptr::null_mut();
    assert!(unsafe { rc_cube_parse(ptr::null(), 4, &mut err) }.is_null());
    assert_eq!(take_string(err).as_deref(), Some("bytes is NULL"));
    assert_eq!(unsafe { rc_cube_size(ptr::null()) }, 0);
    assert!(!unsafe { rc_cube_copy_rgb(ptr::null(), out.as_mut_ptr(), 24) });
    unsafe { rc_cube_free(ptr::null_mut()) };
    // A NULL err_out is tolerated on a refusal.
    let bad = b"LUT_3D_SIZE 1\n";
    assert!(unsafe { rc_cube_parse(bad.as_ptr(), bad.len(), ptr::null_mut()) }.is_null());
}

#[test]
fn the_rust_api_answers_as_the_ffi_does() {
    let parsed = Cube::parse(cube(2).as_bytes()).expect("reads");
    assert_eq!(parsed.size(), 2);
    let mut out = vec![0f32; 24];
    assert!(parsed.copy_rgb(&mut out));
    assert_table(2, &out);
    assert!(!parsed.copy_rgb(&mut out[..23]));
}
