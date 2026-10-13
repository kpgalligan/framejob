//! `rasterize`'s pixels: premultiplied BGRA, the strided copy, the refusals,
//! and that a Library draws the same bytes from any thread.

mod common;

use std::sync::Arc;
use std::thread;

use common::{library, pixel, render, svg};
use graphic::{rasterize, Level, Library};

#[test]
fn a_rect_draws_in_bgra_and_nothing_else_is_touched() {
    let lib = library();
    let body = "<rect x=\"2\" y=\"3\" width=\"4\" height=\"5\" fill=\"#ff8000\"/>";
    let (out, warnings) = render(&lib, &svg(10, 10, body), 10, 10);
    assert!(warnings.is_empty(), "{warnings:?}");
    for y in 0..10 {
        for x in 0..10 {
            let inside = (2..6).contains(&x) && (3..8).contains(&y);
            let want = if inside {
                [0x00, 0x80, 0xff, 0xff]
            } else {
                [0, 0, 0, 0]
            };
            assert_eq!(pixel(&out, 40, x, y), want, "pixel ({x}, {y})");
        }
    }
}

#[test]
fn half_alpha_white_is_premultiplied() {
    let lib = library();
    let body = "<rect width=\"10\" height=\"10\" fill=\"#fff\" fill-opacity=\"0.5\"/>";
    let (out, _) = render(&lib, &svg(10, 10, body), 10, 10);
    let p = pixel(&out, 40, 5, 5);
    println!("half-alpha white: {p:?}");
    assert!(p.iter().all(|c| *c == p[0]), "channels differ: {p:?}");
    assert!(p[0] == 127 || p[0] == 128, "not half: {p:?}");
}

#[test]
fn bytes_past_the_row_are_untouched() {
    let lib = library();
    let (width, height, stride) = (5u32, 4u32, 32usize);
    let mut out = vec![0xABu8; stride * height as usize];
    let body = "<rect width=\"5\" height=\"4\" fill=\"#00ff00\"/>";
    let warnings = rasterize(&lib, &svg(5, 4, body), width, height, &mut out, stride).unwrap();
    assert!(warnings.is_empty(), "{warnings:?}");
    for y in 0..height as usize {
        for x in 0..width as usize {
            assert_eq!(pixel(&out, stride, x, y), [0, 0xff, 0, 0xff]);
        }
        let padding = &out[y * stride + 20..(y + 1) * stride];
        assert!(padding.iter().all(|b| *b == 0xAB), "row {y}: {padding:?}");
    }
}

#[test]
fn the_refusals_name_the_rule_and_write_nothing() {
    let lib = library();
    let rect = svg(4, 4, "<rect width=\"4\" height=\"4\" fill=\"#fff\"/>");
    let cases: [(&str, u32, u32, usize, usize, &str); 5] = [
        (
            &rect,
            8193,
            4,
            8193 * 4,
            8193 * 16,
            "width 8193 is over the 8192 cap",
        ),
        (&rect, 4, 0, 16, 64, "height 0 is not allowed"),
        (&rect, 4, 4, 12, 64, "stride 12 is under width × 4 = 16"),
        (
            &rect,
            4,
            40,
            16,
            100,
            "out holds 100 bytes; height × stride needs 640",
        ),
        ("not an svg", 4, 4, 16, 64, "the SVG did not parse: "),
    ];
    for (text, width, height, stride, len, want) in cases {
        let mut out = vec![0xABu8; len];
        let error = rasterize(&lib, text, width, height, &mut out, stride).expect_err(want);
        assert_eq!(error.level, Level::Error);
        assert!(
            error.message.starts_with(want),
            "{:?} vs {want:?}",
            error.message
        );
        assert!(out.iter().all(|b| *b == 0xAB), "{want}: out was written");
    }
}

#[test]
fn four_threads_draw_identical_bytes() {
    let lib = Arc::new(library());
    let text = svg(
        240,
        80,
        "<rect width=\"240\" height=\"80\" fill=\"#123456\" fill-opacity=\"0.4\"/>\
         <text x=\"10\" y=\"56\" font-family=\"Montserrat\" font-weight=\"800\" \
         font-size=\"48\" fill=\"#fff\">Frame Job</text>",
    );
    let handles: Vec<_> = (0..4)
        .map(|_| {
            let (lib, text) = (lib.clone(), text.clone());
            thread::spawn(move || render(&lib, &text, 240, 80))
        })
        .collect();
    let answers: Vec<_> = handles.into_iter().map(|h| h.join().unwrap()).collect();
    assert!(answers[0].0.iter().any(|b| *b != 0));
    for answer in &answers[1..] {
        assert_eq!(answer.0, answers[0].0);
        assert_eq!(answer.1, answers[0].1);
    }
}

#[test]
fn a_library_is_send_and_sync() {
    fn assert_send_sync<T: Send + Sync>() {}
    assert_send_sync::<Library>();
}
