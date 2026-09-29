//! Anti-aliased edges are premultiplied: every colour channel is at most
//! its alpha (a control proves the check can fail), and white text
//! composited with the premultiplied "over" is exactly white over white.

mod common;

use common::{library, render, svg};

#[test]
fn white_text_edges_composite_exactly() {
    let lib = library();
    let body = "<text x=\"16\" y=\"96\" font-family=\"Montserrat\" font-weight=\"800\" \
                font-size=\"64\" fill=\"#fff\">Edges &amp; curves</text>";
    let (out, warnings) = render(&lib, &svg(640, 128, body), 640, 128);
    assert!(warnings.is_empty(), "{warnings:?}");
    let over = |px: &[u8], dst: u8| -> [u8; 3] {
        let a = px[3] as u32;
        let mut done = [0u8; 3];
        for (c, value) in done.iter_mut().enumerate() {
            *value = (px[c] as u32 + dst as u32 * (255 - a) / 255) as u8;
        }
        done
    };
    let premultiplied = |px: &[u8]| px[..3].iter().all(|c| *c <= px[3]);
    assert!(
        !premultiplied(&[255, 255, 255, 128]),
        "the control: a straight-alpha pixel is not premultiplied"
    );
    let mut partial = 0;
    for px in out.chunks_exact(4) {
        if px[3] > 0 && px[3] < 255 {
            partial += 1;
        }
        assert!(premultiplied(px), "premultiplied: {px:?}");
        assert_eq!(over(px, 255), [255, 255, 255], "over white: {px:?}");
    }
    println!("partially covered pixels: {partial}");
    assert!(partial > 0, "no anti-aliased edge was drawn");
}
