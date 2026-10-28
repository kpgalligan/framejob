//! The block-level half of the WebM writer's EBML (spec §11 CX-15 (3)): the
//! Cues and the builders of a block's body and its BlockGroup, which
//! `webm_writer.rs` places in its Clusters, and the alpha BlockGroup of a
//! `vp9_alpha_webm` video block (CX-17 (5)).
//!
//! Moved whole out of `webm_ebml.rs` under the 400-line cap for a new module,
//! as codec-export C5's toll T2, a pure move. `webm_ebml.rs` re-exports the
//! builders and `CUES`, so every `ebml::` path in `webm_writer.rs` holds.

use crate::webm_ebml::{binary, int, master, uint, vint, BLOCK_GROUP};

const BLOCK: u32 = 0xA1;
const DISCARD_PADDING: u32 = 0x75A2;
pub(crate) const CUES: u32 = 0x1C53_BB6B;
const CUE_POINT: u32 = 0xBB;
const CUE_TIME: u32 = 0xB3;
const CUE_TRACK_POSITIONS: u32 = 0xB7;
const CUE_TRACK: u32 = 0xF7;
const CUE_CLUSTER_POSITION: u32 = 0xF1;
const BLOCK_ADDITIONS: u32 = 0x75A1;
const BLOCK_MORE: u32 = 0xA6;
const BLOCK_ADD_ID: u32 = 0xEE;
const BLOCK_ADDITIONAL: u32 = 0xA5;
const REFERENCE_BLOCK: u32 = 0xFB;

/// Cues of (time in ms, Cluster position in the Segment's data), track 1.
pub(crate) fn cues(points: &[(u64, u64)]) -> Vec<u8> {
    let points: Vec<Vec<u8>> = points
        .iter()
        .map(|(time, pos)| {
            master(
                CUE_POINT,
                &[
                    uint(CUE_TIME, *time),
                    master(
                        CUE_TRACK_POSITIONS,
                        &[uint(CUE_TRACK, 1), uint(CUE_CLUSTER_POSITION, *pos)],
                    ),
                ],
            )
        })
        .collect();
    master(CUES, &points)
}

/// A block's body: the track number, the time relative to its Cluster and
/// the flags, then the frame (no lacing).
pub(crate) fn block_body(track: u32, relative_ms: i16, flags: u8, bytes: &[u8]) -> Vec<u8> {
    let mut out = vint(track.into());
    out.extend(relative_ms.to_be_bytes());
    out.push(flags);
    out.extend_from_slice(bytes);
    out
}

/// A BlockGroup carrying `body` as its Block and a DiscardPadding in ns.
pub(crate) fn block_group(body: &[u8], discard_padding_ns: i64) -> Vec<u8> {
    master(
        BLOCK_GROUP,
        &[
            binary(BLOCK, body),
            int(DISCARD_PADDING, discard_padding_ns),
        ],
    )
}

/// A BlockGroup carrying `body` as its Block and `alpha` as its
/// BlockAdditional with BlockAddID 1, VP9's alpha (spec §11 CX-17 (5)); a
/// non-key block also carries its ReferenceBlock, `reference_ms` (the
/// previous video block's time less this one's), and a key carries none,
/// which is what marks a BlockGroup's Block as a key.
pub(crate) fn alpha_block_group(body: &[u8], alpha: &[u8], reference_ms: Option<i64>) -> Vec<u8> {
    let more = master(
        BLOCK_MORE,
        &[uint(BLOCK_ADD_ID, 1), binary(BLOCK_ADDITIONAL, alpha)],
    );
    let mut children = vec![binary(BLOCK, body), master(BLOCK_ADDITIONS, &[more])];
    if let Some(reference) = reference_ms {
        children.push(int(REFERENCE_BLOCK, reference));
    }
    master(BLOCK_GROUP, &children)
}
