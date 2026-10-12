//! Black-box tests for the edit ops — spec §6 and the op table in the module
//! doc of `core/src/edit.rs` — driven the way the app drives them: one JSON
//! envelope at a time through `rc_project_apply`.
//!
//! Four things this file is built to catch, in rough order of value:
//!
//! 1. **`split` losing something.** A split followed by [`join`] — the
//!    inverse, written here from the split's contract alone — must reproduce
//!    the original project byte for byte. It is the one check that covers
//!    the second half's evaluated base props, a straddled action's two
//!    halves, the id allocation and the clip ordering all at once.
//! 2. **The three-way answer.** An op that would change nothing must report
//!    "no change" (NULL, `err_out` untouched) and never a copy, or the app
//!    grows a phantom undo step (spec §5.5).
//! 3. **Every op in the table is reachable.** [`op_table`] drives every one
//!    of them and asserts its own coverage against `OP_NAMES`, so an op that
//!    gains an argument and loses its only caller cannot pass unnoticed.
//! 4. **The documented refusals and clamps**: the overlap rule's exact
//!    boundary, the trim clamps at both source bounds, ripple's respect for
//!    a locked track, and freeze frame's sync across tracks.
//!
//! Every expected value is hand-computed from the spec in the test that uses
//! it — the fixtures below are chosen so that arithmetic lands on the frame
//! grid — and nothing here is captured from a run.

mod common;

use serde_json::{json, Value};

use common::{array, assert_contains, at, by_id, flag, int, num, source_in, text, Handle, Outcome};
use reelcut_core::OP_NAMES;

/// One frame of the 30 fps canvas every fixture but [`overlap_project`] uses.
/// 600 000 ticks per second (spec §5.1), so 30 fps is 20 000 ticks.
const FRAME: i64 = 20_000;

/// One second, for fixtures that read better in seconds.
const SECOND: i64 = 600_000;

// ---- fixtures ------------------------------------------------------------

/// The everything fixture: three media (video with audio, audio only, an
/// image), five tracks, a media clip with one action, an audio clip, a text
/// clip, a shape clip, a nest clip with a text clip inside it, a marker, and
/// an ABUTTING PAIR (clips 46 and 47 on track 8, each showing media 1 with
/// handles on both sides of the cut). Sized so that every op in the table
/// has somewhere legal to land on it.
///
/// The abutting pair is road map 5 E1's, and it is on a track of its own
/// deliberately: `op_table`'s `close_gap` row is aimed at track 6's gap and
/// a pair placed there would fill it. It is what gives `roll`,
/// `add_transition` and `set_transition_style` a hard cut to work at — the
/// first of which therefore LEFT `UNCHANGING`.
fn general() -> Handle {
    Handle::from_json(
        r#"{
  "version": 2,
  "canvas": {"width": 1920, "height": 1080, "fps": [30, 1], "background": [0, 0, 0, 1],
             "fit_new_clips": true, "timecode_frames": true},
  "media": [
    {"id": 1, "path": "/m/talk.mov", "kind": "video", "duration": 36000000,
     "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": true},
    {"id": 2, "path": "/m/music.m4a", "kind": "audio", "duration": 18000000,
     "has_audio": true},
    {"id": 3, "path": "/m/logo.png", "kind": "image", "width": 800, "height": 600,
     "fps": [30, 1]}
  ],
  "tracks": [
    {"id": 4, "name": "Track 1"},
    {"id": 5, "name": "Track 2"},
    {"id": 6, "name": "Track 3"},
    {"id": 7, "name": "Track 4"},
    {"id": 8, "name": "Track 5"}
  ],
  "clips": [
    {"id": 10, "track": 4, "start": 0, "duration": 6000000,
     "source": {"kind": "media", "media": 1, "in": 600000},
     "video": {}, "audio": {},
     "actions": [{"id": 11, "start": 1200000, "duration": 600000,
                  "curve": "ease_in_out", "end": {"video": {"scale": 0.6, "x": 520}}}]},
    {"id": 20, "track": 5, "start": 9000000, "duration": 3000000,
     "source": {"kind": "media", "media": 2, "in": 0}, "audio": {}},
    {"id": 30, "track": 6, "start": 0, "duration": 3000000,
     "source": {"kind": "text"}, "video": {}, "text": {"content": "Hello"}},
    {"id": 40, "track": 6, "start": 4200000, "duration": 3000000,
     "source": {"kind": "shape"}, "video": {}, "shape": {"width": 320, "height": 120}},
    {"id": 41, "track": 7, "start": 0, "duration": 3000000,
     "source": {"kind": "nest", "project": 42}, "video": {}},
    {"id": 46, "track": 8, "start": 0, "duration": 3000000,
     "source": {"kind": "media", "media": 1, "in": 3000000},
     "video": {}, "audio": {}},
    {"id": 47, "track": 8, "start": 3000000, "duration": 3000000,
     "source": {"kind": "media", "media": 1, "in": 12000000},
     "video": {}, "audio": {}},
    {"id": 48, "track": 7, "start": 4200000, "duration": 3000000,
     "source": {"kind": "graphic"}, "video": {},
     "graphic": {"name": "lower-third", "width": 1920, "height": 1080}}
  ],
  "markers": [{"id": 50, "time": 6000000, "name": "Intro"}],
  "next_id": 60,
  "nests": [
    {"id": 42, "name": "Nest 1", "width": 1920, "height": 1080,
     "tracks": [{"id": 43, "name": "Nested"}],
     "clips": [{"id": 44, "track": 43, "start": 0, "duration": 3000000,
                "source": {"kind": "text"}, "video": {},
                "text": {"content": "Inside"}}]}
  ]
}"#,
    )
}

/// A clip with three actions, a transition and non-default base props, on a
/// track where it overlaps a predecessor — everything `split` has to carry
/// across a cut. Clip 20 runs 2 400 000 – 14 400 000.
fn split_project() -> Handle {
    Handle::from_json(
        r#"{
  "version": 1,
  "canvas": {"width": 1920, "height": 1080, "fps": [30, 1], "background": [0, 0, 0, 1],
             "fit_new_clips": true, "timecode_frames": true},
  "media": [
    {"id": 1, "path": "/m/talk.mov", "kind": "video", "duration": 36000000,
     "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": true}
  ],
  "tracks": [{"id": 2, "name": "Track 1"}],
  "clips": [
    {"id": 10, "track": 2, "start": 0, "duration": 3000000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 20, "track": 2, "start": 2400000, "duration": 12000000,
     "source": {"kind": "media", "media": 1, "in": 1200000}, "speed": 1.0,
     "video": {"x": 40, "scale": 0.8},
     "audio": {"volume": 0.9, "fade_in": 120000},
     "transition_in": {"kind": "push_left"},
     "actions": [
       {"id": 21, "start": 1200000, "duration": 600000, "curve": "ease_in_out",
        "end": {"video": {"scale": 0.6, "x": 520}}},
       {"id": 22, "start": 4800000, "duration": 1200000, "curve": "linear",
        "end": {"video": {"opacity": 0.5}, "audio": {"volume": 0.25}}},
       {"id": 23, "start": 9000000, "duration": 600000, "curve": "ease_out",
        "end": {"video": {"x": 0, "y": 100}}}
     ]}
  ],
  "markers": [],
  "next_id": 30
}"#,
    )
}

/// The overlap-rule fixture, deliberately at 600 000 fps — ONE TICK per
/// frame.
///
/// The rule's boundary is "an overlap of more than half the shorter clip",
/// and half is measured in ticks. Every op snaps its arguments to the canvas
/// grid first (spec §6), so on any ordinary grid a test can only bracket the
/// boundary to within a frame; a one-tick grid lets it be pinned exactly.
/// Nothing else about the rate matters here — no time is formatted and no
/// media is decoded.
///
/// Track 2 is the half-rule case, track 3 the both-sides case, track 4 the
/// two-neighbours case.
fn overlap_project() -> Handle {
    Handle::from_json(
        r#"{
  "version": 1,
  "canvas": {"width": 1920, "height": 1080, "fps": [600000, 1], "background": [0, 0, 0, 1],
             "fit_new_clips": true, "timecode_frames": true},
  "media": [
    {"id": 1, "path": "/m/talk.mov", "kind": "video", "duration": 36000000,
     "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": true}
  ],
  "tracks": [{"id": 2, "name": "A"}, {"id": 3, "name": "B"}, {"id": 4, "name": "C"}],
  "clips": [
    {"id": 10, "track": 2, "start": 0, "duration": 1000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 11, "track": 2, "start": 2000, "duration": 1000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 12, "track": 3, "start": 0, "duration": 1000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 13, "track": 3, "start": 1500, "duration": 1000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {},
     "transition_in": {"kind": "wipe"}},
    {"id": 14, "track": 3, "start": 3000, "duration": 1000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 15, "track": 4, "start": 0, "duration": 1000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 16, "track": 4, "start": 900, "duration": 400,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {},
     "transition_in": {"kind": "fade_black"}},
    {"id": 17, "track": 4, "start": 5000, "duration": 400,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}}
  ],
  "markers": [],
  "next_id": 20
}"#,
    )
}

/// Three clips on three tracks, each pressed against a different bound:
/// clip 10 has 1 200 000 ticks of source in front of it, clip 11 is exactly
/// one frame long, and clip 12's in point sits at the very end of its media.
fn trim_project() -> Handle {
    Handle::from_json(
        r#"{
  "version": 1,
  "canvas": {"width": 1920, "height": 1080, "fps": [30, 1], "background": [0, 0, 0, 1],
             "fit_new_clips": true, "timecode_frames": true},
  "media": [
    {"id": 1, "path": "/m/talk.mov", "kind": "video", "duration": 36000000,
     "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": true}
  ],
  "tracks": [{"id": 2, "name": "A"}, {"id": 3, "name": "B"}, {"id": 4, "name": "C"}],
  "clips": [
    {"id": 10, "track": 2, "start": 3000000, "duration": 6000000,
     "source": {"kind": "media", "media": 1, "in": 1200000}, "video": {}, "audio": {}},
    {"id": 11, "track": 3, "start": 0, "duration": 20000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 12, "track": 4, "start": 0, "duration": 600000,
     "source": {"kind": "media", "media": 1, "in": 36000000}, "video": {}, "audio": {}}
  ],
  "markers": [],
  "next_id": 20
}"#,
    )
}

/// One ten-second media clip carrying one action, alone on its track: the
/// shape `set_speed` and `rate_stretch` both rescale.
fn speed_project() -> Handle {
    Handle::from_json(
        r#"{
  "version": 1,
  "canvas": {"width": 1920, "height": 1080, "fps": [30, 1], "background": [0, 0, 0, 1],
             "fit_new_clips": true, "timecode_frames": true},
  "media": [
    {"id": 1, "path": "/m/talk.mov", "kind": "video", "duration": 36000000,
     "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": true}
  ],
  "tracks": [{"id": 2, "name": "A"}],
  "clips": [
    {"id": 10, "track": 2, "start": 0, "duration": 6000000,
     "source": {"kind": "media", "media": 1, "in": 0}, "speed": 1.0,
     "video": {}, "audio": {"keep_pitch": true},
     "actions": [{"id": 11, "start": 1200000, "duration": 600000, "curve": "linear",
                  "end": {"video": {"scale": 0.5}}}]}
  ],
  "markers": [],
  "next_id": 20
}"#,
    )
}

/// Two tracks: clip 10 sits on the upper one (there is a track below it),
/// clips 20 and 30 sit on the bottom one. Media 2 has no audio track.
fn detach_project() -> Handle {
    Handle::from_json(
        r#"{
  "version": 1,
  "canvas": {"width": 1920, "height": 1080, "fps": [30, 1], "background": [0, 0, 0, 1],
             "fit_new_clips": true, "timecode_frames": true},
  "media": [
    {"id": 1, "path": "/m/av.mov", "kind": "video", "duration": 36000000,
     "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": true},
    {"id": 2, "path": "/m/silent.mov", "kind": "video", "duration": 36000000,
     "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": false}
  ],
  "tracks": [{"id": 3, "name": "Track 1"}, {"id": 4, "name": "Track 2"}],
  "clips": [
    {"id": 10, "track": 4, "start": 0, "duration": 3000000,
     "source": {"kind": "media", "media": 1, "in": 600000}, "speed": 1.0,
     "video": {}, "audio": {"volume": 0.8}},
    {"id": 20, "track": 3, "start": 6000000, "duration": 3000000,
     "source": {"kind": "media", "media": 2, "in": 0}, "video": {}},
    {"id": 30, "track": 3, "start": 12000000, "duration": 3000000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}}
  ],
  "markers": [],
  "next_id": 40
}"#,
    )
}

/// Three tracks with known gaps, the middle one LOCKED, plus two markers.
/// Track 3's clip 30 straddles the span clip 11 occupies, which is the
/// "straddling clips stay put" case (spec §11).
fn ripple_project() -> Handle {
    Handle::from_json(
        r#"{
  "version": 1,
  "canvas": {"width": 1920, "height": 1080, "fps": [30, 1], "background": [0, 0, 0, 1],
             "fit_new_clips": true, "timecode_frames": true},
  "media": [
    {"id": 1, "path": "/m/talk.mov", "kind": "video", "duration": 36000000,
     "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": true}
  ],
  "tracks": [
    {"id": 2, "name": "Picture"},
    {"id": 3, "name": "Locked", "locked": true},
    {"id": 4, "name": "Music"}
  ],
  "clips": [
    {"id": 10, "track": 2, "start": 0, "duration": 1200000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 11, "track": 2, "start": 2400000, "duration": 1200000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 12, "track": 2, "start": 4800000, "duration": 1200000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 20, "track": 3, "start": 600000, "duration": 1200000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 21, "track": 3, "start": 3000000, "duration": 1200000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 30, "track": 4, "start": 1800000, "duration": 1800000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 31, "track": 4, "start": 6000000, "duration": 600000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}}
  ],
  "markers": [
    {"id": 40, "time": 3000000, "name": "Cut"},
    {"id": 41, "time": 5400000, "name": "End"}
  ],
  "next_id": 50
}"#,
    )
}

/// A range-delete fixture where the range straddles a clip on every track:
/// clip 10 crosses its start, clip 30 crosses its end, and the LOCKED clip
/// 20 crosses both and must survive whole.
fn range_project() -> Handle {
    Handle::from_json(
        r#"{
  "version": 1,
  "canvas": {"width": 1920, "height": 1080, "fps": [30, 1], "background": [0, 0, 0, 1],
             "fit_new_clips": true, "timecode_frames": true},
  "media": [
    {"id": 1, "path": "/m/talk.mov", "kind": "video", "duration": 36000000,
     "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": true}
  ],
  "tracks": [
    {"id": 2, "name": "Picture"},
    {"id": 3, "name": "Locked", "locked": true},
    {"id": 4, "name": "Music"}
  ],
  "clips": [
    {"id": 10, "track": 2, "start": 0, "duration": 3600000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 11, "track": 2, "start": 4800000, "duration": 1200000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 20, "track": 3, "start": 1800000, "duration": 3600000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 30, "track": 4, "start": 3000000, "duration": 4200000,
     "source": {"kind": "media", "media": 1, "in": 1200000}, "video": {}, "audio": {}}
  ],
  "markers": [{"id": 40, "time": 3000000, "name": "Inside"}],
  "next_id": 50
}"#,
    )
}

/// A fixture with two closable gaps on one track and different consequences
/// for each: closing the LEADING gap (0 – 4 s, in front of clip 10) is
/// legal everywhere, while closing the one at 6 s – 8 s slides clip 22 onto
/// clip 21 by more than the overlap rule allows and must be refused whole.
///
/// Track 5 is locked and holds a gap whose closure WOULD be legal for every
/// other track, so the refusal there is the lock itself and not a collision
/// the shift would have caused anyway. (Track 4 is locked too, but its gap
/// is one the shift could not close in any case.)
///
/// Track 6's pair is placed so that closing the leading gap brings clip 35
/// onto clip 34 by a legal amount: an overlap IS a transition, so the
/// newcomer must come out of it with the default dissolve.
fn gap_project() -> Handle {
    Handle::from_json(
        r#"{
  "version": 1,
  "canvas": {"width": 1920, "height": 1080, "fps": [30, 1], "background": [0, 0, 0, 1],
             "fit_new_clips": true, "timecode_frames": true},
  "media": [
    {"id": 1, "path": "/m/talk.mov", "kind": "video", "duration": 36000000,
     "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": true}
  ],
  "tracks": [
    {"id": 2, "name": "Picture"},
    {"id": 3, "name": "Bed"},
    {"id": 4, "name": "Locked", "locked": true},
    {"id": 5, "name": "Held", "locked": true},
    {"id": 6, "name": "Bed"}
  ],
  "clips": [
    {"id": 10, "track": 2, "start": 2400000, "duration": 1200000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 11, "track": 2, "start": 4800000, "duration": 1200000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 20, "track": 3, "start": 0, "duration": 600000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 21, "track": 3, "start": 4200000, "duration": 1200000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 22, "track": 3, "start": 6000000, "duration": 600000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 30, "track": 4, "start": 0, "duration": 1200000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 31, "track": 4, "start": 3600000, "duration": 1200000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 32, "track": 5, "start": 0, "duration": 600000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 33, "track": 5, "start": 1200000, "duration": 600000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 34, "track": 6, "start": 0, "duration": 2400000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 35, "track": 6, "start": 4200000, "duration": 2400000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}}
  ],
  "markers": [{"id": 40, "time": 5000000, "name": "Mark"}],
  "next_id": 50
}"#,
    )
}

/// A clip with a scale action to freeze inside, a second unlocked track that
/// must stay in sync, a LOCKED third track that must not move, and a marker
/// past the freeze point.
fn freeze_project() -> Handle {
    Handle::from_json(
        r#"{
  "version": 1,
  "canvas": {"width": 1920, "height": 1080, "fps": [30, 1], "background": [0, 0, 0, 1],
             "fit_new_clips": true, "timecode_frames": true},
  "media": [
    {"id": 1, "path": "/m/talk.mov", "kind": "video", "duration": 36000000,
     "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": true}
  ],
  "tracks": [
    {"id": 2, "name": "Picture"},
    {"id": 3, "name": "Music"},
    {"id": 4, "name": "Locked", "locked": true}
  ],
  "clips": [
    {"id": 10, "track": 2, "start": 0, "duration": 12000000,
     "source": {"kind": "media", "media": 1, "in": 600000}, "speed": 1.0,
     "video": {}, "audio": {},
     "actions": [{"id": 11, "start": 3000000, "duration": 1200000, "curve": "linear",
                  "end": {"video": {"scale": 0.5}}}]},
    {"id": 20, "track": 3, "start": 1200000, "duration": 1200000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 21, "track": 3, "start": 6000000, "duration": 1200000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 30, "track": 4, "start": 6000000, "duration": 1200000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}}
  ],
  "markers": [{"id": 40, "time": 6000000, "name": "Beat"}],
  "next_id": 50
}"#,
    )
}

/// One clip with a placed, scaled layer and one action, plus a marker — the
/// three things `set_canvas` touches (rescale, re-snap, marker re-snap).
/// Every time is on the 30 fps grid and none of them is on the 24 fps grid.
fn canvas_project() -> Handle {
    Handle::from_json(
        r#"{
  "version": 1,
  "canvas": {"width": 1920, "height": 1080, "fps": [30, 1], "background": [0, 0, 0, 1],
             "fit_new_clips": true, "timecode_frames": true},
  "media": [
    {"id": 1, "path": "/m/talk.mov", "kind": "video", "duration": 36000000,
     "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": true}
  ],
  "tracks": [{"id": 2, "name": "A"}],
  "clips": [
    {"id": 10, "track": 2, "start": 1220000, "duration": 1180000,
     "source": {"kind": "media", "media": 1, "in": 0},
     "video": {"x": 100, "y": 50, "scale": 0.5}, "audio": {},
     "actions": [{"id": 11, "start": 140000, "duration": 60000, "curve": "linear",
                  "end": {}}]}
  ],
  "markers": [{"id": 12, "time": 1220000, "name": "M"}],
  "next_id": 20
}"#,
    )
}

// ---- local helpers -------------------------------------------------------

/// `(start, duration)` of one clip, the pair every placement table below is
/// written in.
fn placement(project: &Value, clip: u64) -> (i64, i64) {
    let found = by_id(project, "/clips", clip);
    (int(found, "/start"), int(found, "/duration"))
}

/// Every clip on one track as `(start, duration)`, ascending.
///
/// A cut that splits mints ids no test should name — the numbers depend on
/// the order the split walked the array in, which is not part of any op's
/// contract — so a lane a range op reshaped is compared as the sequence of
/// placements it left, which is.
fn lane(project: &Value, track: i64) -> Vec<(i64, i64)> {
    let mut found: Vec<(i64, i64)> = array(project, "/clips")
        .iter()
        .filter(|c| int(c, "/track") == track)
        .map(|c| (int(c, "/start"), int(c, "/duration")))
        .collect();
    found.sort_unstable();
    found
}

/// Float comparison with a stated tolerance, naming what was being checked.
fn close(actual: f64, expected: f64, what: &str) {
    assert!(
        (actual - expected).abs() < 1e-9,
        "{what}: expected {expected}, got {actual}"
    );
}

/// The inverse of `split`, written from the split's contract alone (spec §6,
/// `edit_clip::split_clip`) and never from a captured result:
///
/// - the second clip is discarded — everything it carries was derived from
///   the first half plus the cut;
/// - the first clip's duration becomes the two durations again;
/// - an action of the second half that starts at 0 is the TAIL of an action
///   the cut straddled, so it merges back into the unique action of the
///   first half that ends exactly at the cut, restoring that action's
///   duration and its original `end` patch; every other action of the second
///   half is rebased by the cut and appended;
/// - `next_id` goes back to the second clip's id, which is the first id the
///   split allocated.
///
/// The one thing this cannot reconstruct is a project where an action ends
/// exactly at the cut AND another begins exactly there: split leaves those
/// two looking exactly like a straddled pair. The assertion below catches
/// that arrangement rather than silently mis-joining, and no fixture here
/// contains one.
fn join(project: &Value, first_id: u64, second_id: u64) -> Value {
    let mut out = project.clone();
    {
        let clips = out
            .get_mut("clips")
            .and_then(Value::as_array_mut)
            .expect("a project has a clips array");

        let where_second = clips
            .iter()
            .position(|c| c["id"].as_u64() == Some(second_id))
            .unwrap_or_else(|| panic!("no clip {second_id} to join back"));
        let second = clips.remove(where_second);
        let where_first = clips
            .iter()
            .position(|c| c["id"].as_u64() == Some(first_id))
            .unwrap_or_else(|| panic!("no clip {first_id} to join into"));

        let cut = int(&clips[where_first], "/duration");
        assert_eq!(
            int(&second, "/start"),
            int(&clips[where_first], "/start") + cut,
            "the two halves must meet at the cut"
        );
        assert_eq!(
            second["track"], clips[where_first]["track"],
            "a split never moves a clip to another track"
        );

        let mut actions: Vec<Value> = array(&clips[where_first], "/actions").clone();
        for tail in array(&second, "/actions") {
            let start = int(tail, "/start");
            if start == 0 {
                let heads: Vec<usize> = actions
                    .iter()
                    .enumerate()
                    .filter(|(_, a)| int(a, "/start") + int(a, "/duration") == cut)
                    .map(|(index, _)| index)
                    .collect();
                assert!(
                    heads.len() < 2,
                    "more than one action ends at the cut: the join is ambiguous"
                );
                if let Some(&index) = heads.first() {
                    let restored = int(&actions[index], "/duration") + int(tail, "/duration");
                    actions[index]["duration"] = json!(restored);
                    actions[index]["end"] = tail["end"].clone();
                    continue;
                }
            }
            let mut moved = tail.clone();
            moved["start"] = json!(start + cut);
            actions.push(moved);
        }

        let restored = cut + int(&second, "/duration");
        let first = &mut clips[where_first];
        first["duration"] = json!(restored);
        first["actions"] = Value::Array(actions);
    }
    out["next_id"] = json!(second_id);
    out
}

/// Every op in `edit.rs`'s table, as a legal invocation against [`general`].
/// The op names itself, so there is no second spelling of the name here to
/// drift away from the envelope.
fn op_table() -> Vec<Value> {
    vec![
        json!({"op": "add_clip", "track": 4, "media": 3, "at": 12000000}),
        json!({"op": "add_text_clip", "track": 5, "at": 0, "duration": 1200000}),
        json!({"op": "add_shape_clip", "track": 5, "at": 1800000}),
        json!({"op": "add_graphic_clip", "track": 5, "at": 0, "name": "lower-third"}),
        json!({"op": "add_adjustment_clip", "track": 5, "at": 0}),
        json!({"op": "insert_clip", "track": 4, "media": 3, "at": 3000000}),
        json!({"op": "overwrite_clip", "track": 4, "media": 3, "at": 1200000}),
        json!({"op": "move_clip", "clips": [10], "delta": 600000}),
        json!({"op": "trim_start", "clip": 10, "to": 1200000}),
        json!({"op": "trim_end", "clip": 10, "to": 4800000}),
        json!({"op": "rate_stretch", "clip": 10, "to_end": 4800000}),
        json!({"op": "slip", "clip": 10, "delta": 600000}),
        json!({"op": "roll", "clip": 47, "to": 3600000}),
        json!({"op": "split", "clips": [10], "at": 3000000}),
        json!({"op": "delete", "clips": [40]}),
        json!({"op": "ripple_delete", "clips": [10]}),
        json!({"op": "ripple_delete_range", "from": 1200000, "to": 2400000}),
        json!({"op": "ripple_delete_ranges",
               "ranges": [[1200000, 1800000], [2400000, 3000000]]}),
        json!({"op": "lift_range", "from": 1200000, "to": 2400000}),
        json!({"op": "insert_time", "at": 0, "length": 600000}),
        json!({"op": "close_gap", "track": 6, "at": 3600000}),
        json!({"op": "set_speed", "clip": 10, "rate": 2.0}),
        json!({"op": "set_reversed", "clip": 10, "reversed": true}),
        json!({"op": "freeze_frame", "clip": 10, "at": 3000000}),
        json!({"op": "detach_audio", "clip": 10}),
        json!({"op": "duplicate", "clips": [10]}),
        // The two backdrop ops each mint a track as well as a clip, which is
        // why they sit beside `detach_audio` rather than with `add_clip`:
        // what the coverage check below wants from them is only that the
        // envelope parses and the dispatch arrives. `add_background` is given
        // no arguments on purpose — every one of them is optional, and the
        // no-argument form is the one the menu's Solid Color row sends.
        // `core/tests/background.rs` is where either op's answer is measured.
        json!({"op": "add_background"}),
        json!({"op": "add_blurred_background", "clip": 10}),
        // The payload's own semantics are `paste.rs`'s business; this row is
        // only here to keep the coverage check below honest.
        json!({"op": "paste", "at": 24000000,
               "payload": {"clips": [{"id": 1, "track": 0, "start": 0, "duration": 600000,
                                      "source": {"kind": "text"}}]}}),
        // Likewise: a payload clip whose video differs from clip 10's
        // defaults, so the default groups rule has something to copy.
        json!({"op": "paste_attributes", "clips": [10],
               "payload": {"clips": [{"id": 1, "track": 0, "start": 0, "duration": 600000,
                                      "source": {"kind": "text"},
                                      "video": {"opacity": 0.5}}]}}),
        json!({"op": "nest", "clips": [30]}),
        json!({"op": "unnest", "clip": 41}),
        json!({"op": "set_video", "clips": [10], "patch": {"opacity": 0.5}}),
        json!({"op": "set_audio", "clips": [10], "patch": {"volume": 0.5}}),
        json!({"op": "set_text", "clips": [30], "patch": {"content": "Bye"}}),
        json!({"op": "set_shape", "clips": [40], "patch": {"width": 400}}),
        json!({"op": "set_graphic", "clips": [48], "patch": {"props": {"title": "B"}}}),
        json!({"op": "set_clip", "clips": [10], "patch": {"name": "Talk"}}),
        json!({"op": "set_enabled", "clip": 10, "video": false}),
        json!({"op": "set_transition", "clip": 10, "kind": "wipe"}),
        json!({"op": "set_transition_duration", "clip": 40, "duration": 600000}),
        json!({"op": "add_transition", "clip": 47, "duration": 600000}),
        json!({"op": "set_transition_style", "clip": 47, "curve": "ease_in"}),
        json!({"op": "add_action", "clip": 20, "at": 0, "duration": 600000}),
        // Clip 10's own action runs 1 200 000 – 1 800 000, so this one sits
        // clear of it; the region is a quarter of the 1920×1080 source,
        // centred, which `fit` answers with a scale of 3.
        json!({"op": "add_zoom_action", "clip": 10, "at": 3000000,
               "region": {"x": 0.0, "y": 0.0, "width": 640.0, "height": 360.0}}),
        json!({"op": "set_action", "clip": 10, "action": 11, "curve": "linear"}),
        json!({"op": "set_action_end", "clip": 10, "action": 11,
               "patch": {"video": {"opacity": 0.2}}}),
        json!({"op": "remove_action", "clip": 10, "action": 11}),
        json!({"op": "add_track"}),
        json!({"op": "remove_track", "track": 5, "with_clips": true}),
        json!({"op": "move_track", "track": 4, "index": 2}),
        json!({"op": "set_track", "track": 4, "name": "Main"}),
        json!({"op": "remove_empty_tracks"}),
        json!({"op": "add_marker", "at": 1200000}),
        json!({"op": "set_marker", "marker": 50, "name": "Opening"}),
        json!({"op": "remove_marker", "marker": 50}),
        json!({"op": "set_canvas", "width": 1280, "height": 720}),
        json!({"op": "add_media",
               "descriptor": {"path": "/m/new.mov", "kind": "video", "duration": 600000,
                              "width": 640, "height": 480, "fps": [30, 1],
                              "has_video": true, "has_audio": false}}),
        json!({"op": "relink_media", "media": 1, "path": "/m/moved.mov"}),
        json!({"op": "remove_media", "media": 3, "with_clips": true}),
        json!({"op": "set_media_color", "media": 1, "color": {"log": "slog3"}}),
    ]
}

/// The ops of [`op_table`] whose answer on [`general`] is the documented
/// "valid, changes nothing" rather than an edit.
///
/// Every track in that fixture holds a clip, so there is nothing for
/// `remove_empty_tracks` to drop. It is the only row left: `roll` was the
/// other until road map 5's E1 gave `general()` an abutting pair for
/// `add_transition` to work at, which is a hard cut `roll` can move too —
/// so it now changes something here as well, and its own edits stay proved
/// against the fixture built for them in `core/tests/edge.rs`.
const UNCHANGING: [&str; 1] = ["remove_empty_tracks"];

// ---- the op table --------------------------------------------------------

#[test]
fn every_op_in_the_table_is_reachable() {
    let project = general();
    let table = op_table();
    let covered: Vec<&str> = table
        .iter()
        .map(|op| op["op"].as_str().expect("every op names itself"))
        .collect();

    // Coverage first: an op that gained a name and lost its only caller is
    // exactly the gap this file exists to close.
    for name in OP_NAMES {
        assert!(
            covered.contains(&name),
            "op \"{name}\" is in OP_NAMES but no test here applies it"
        );
    }
    for name in &covered {
        assert!(
            OP_NAMES.contains(name),
            "the table applies \"{name}\", which is not an op"
        );
    }
    assert_eq!(covered.len(), OP_NAMES.len(), "an op is covered twice");

    for (name, op) in covered.iter().zip(&table) {
        let changes = !UNCHANGING.contains(name);
        match project.try_apply(op) {
            Ok(Outcome::Applied(_)) => {
                assert!(changes, "op \"{name}\" was expected to change nothing")
            }
            Ok(Outcome::Identity) => assert!(!changes, "op \"{name}\" changed nothing: {op}"),
            Ok(Outcome::Refused(why)) => {
                assert!(!changes, "op \"{name}\" was refused: {why}\n{op}")
            }
            Err(msg) => panic!("op \"{name}\" errored: {msg}\n{op}"),
        }
    }
}

// ---- the envelope --------------------------------------------------------

#[test]
fn an_unknown_op_name_lists_the_valid_ones() {
    let project = general();
    let msg = project.errors(r#"{"op": "add_clipp", "track": 4, "media": 1, "at": 0}"#);
    assert_contains(&msg, "unknown op \"add_clipp\"");
    for name in OP_NAMES {
        assert_contains(&msg, name);
    }
}

#[test]
fn a_malformed_envelope_is_an_error() {
    let project = general();

    assert_contains(
        &project.errors(r#"{"op": "delete", "clips": ["#),
        "op is not valid json",
    );
    assert_contains(&project.errors("[1, 2]"), "an op must be a json object");
    assert_contains(
        &project.errors(r#"{"track": 4}"#),
        "an op must have an \"op\" name",
    );
    assert_contains(
        &project.errors(r#"{"op": 5}"#),
        "an op name must be a string",
    );

    // A known op with the wrong type for an argument, and one missing an
    // argument entirely: both are quoted under the op's own name.
    let wrong_type = project.errors(r#"{"op": "delete", "clips": "everything"}"#);
    assert_contains(&wrong_type, "op \"delete\" is not valid");
    let missing = project.errors(r#"{"op": "trim_start", "clip": 10}"#);
    assert_contains(&missing, "missing field `to`");
}

#[test]
fn an_unknown_field_in_a_known_op_is_an_error() {
    let project = general();
    let msg = project.errors(r#"{"op": "delete", "clips": [40], "bogus": 1}"#);
    assert_contains(&msg, "bogus");
    // The empty struct variant denies unknown fields like every other one.
    let empty = project.errors(r#"{"op": "remove_empty_tracks", "bogus": 1}"#);
    assert_contains(&empty, "bogus");
}

#[test]
fn an_unknown_id_or_an_out_of_range_value_is_an_error() {
    let project = general();

    assert_contains(
        &project.errors(&json!({"op": "delete", "clips": [999]})),
        "no clip with id 999",
    );
    assert_contains(
        &project.errors(&json!({"op": "set_track", "track": 999, "name": "x"})),
        "no track with id 999",
    );
    assert_contains(
        &project.errors(&json!({"op": "remove_marker", "marker": 999})),
        "no marker with id 999",
    );
    assert_contains(
        &project.errors(&json!({"op": "relink_media", "media": 999, "path": "/m/x.mov"})),
        "no media with id 999",
    );
    assert_contains(
        &project.errors(&json!({"op": "remove_action", "clip": 10, "action": 999})),
        "no action with id 999 on clip 10",
    );
    assert_contains(
        &project.errors(&json!({"op": "set_video", "clips": [10], "patch": {"opacity": 5}})),
        "video.opacity must be between 0 and 1, not 5",
    );
    // The key check reaches inside an optional sub-object the clip does not
    // currently have.
    assert_contains(
        &project
            .errors(&json!({"op": "set_video", "clips": [10], "patch": {"shadow": {"blurr": 8}}})),
        "unknown key \"shadow.blurr\" in a video patch",
    );
    assert_contains(
        &project.errors(&json!({"op": "set_text", "clips": [10], "patch": {"content": "x"}})),
        "clip 10 has no text properties",
    );
    assert_contains(
        &project.errors(&json!({"op": "set_speed", "clip": 30, "rate": 2.0})),
        "clip 30 is not a media clip",
    );
}

// ---- the no-change answer ------------------------------------------------

#[test]
fn an_op_that_changes_nothing_reports_no_change() {
    let project = general();

    // Clip 10's video props are the defaults, so patching them with their
    // own values must not register an undo step.
    project.refuses(&json!({"op": "set_video", "clips": [10],
                            "patch": {"opacity": 1.0, "scale": 1.0, "x": 0.0}}));
    project.refuses(&json!({"op": "move_clip", "clips": [10], "delta": 0}));
    project.refuses(&json!({"op": "set_track", "track": 4, "name": "Track 1"}));
    project.refuses(&json!({"op": "remove_empty_tracks"}));

    // A few more of the same shape, for the ops whose identity case is easy
    // to reach by accident in the UI.
    project.refuses(&json!({"op": "set_transition", "clip": 10, "kind": null}));
    project.refuses(&json!({"op": "set_enabled", "clip": 10, "video": true, "audio": true}));
    project.refuses(&json!({"op": "insert_time", "at": 0, "length": 0}));
    project.refuses(&json!({"op": "move_track", "track": 4, "index": 0}));
    project.refuses(&json!({"op": "delete", "clips": []}));
}

#[test]
fn a_documented_refusal_reports_no_change_rather_than_an_error() {
    let project = general();
    // A non-empty track without `with_clips`, and the last remaining track:
    // both are refusals, not errors (spec §6).
    project.refuses(&json!({"op": "remove_track", "track": 4}));
    // A media still in use.
    project.refuses(&json!({"op": "remove_media", "media": 1}));
    // A split where the playhead is not strictly inside the clip.
    project.refuses(&json!({"op": "split", "clips": [10], "at": 0}));
    project.refuses(&json!({"op": "split", "clips": [10], "at": 6000000}));
    // An action that would run past the clip's end.
    project.refuses(&json!({"op": "add_action", "clip": 10, "at": 5700000,
                            "duration": 600000}));
    // An action that would overlap the one already there (1 200 000 –
    // 1 800 000 in clip time).
    project.refuses(&json!({"op": "add_action", "clip": 10, "at": 1500000,
                            "duration": 600000}));
}

// ---- split is invertible -------------------------------------------------

#[test]
fn split_then_join_is_the_identity() {
    let project = split_project();
    let before = project.to_json();
    let second_id = int(&project.value(), "/next_id") as u64;

    // Cut points chosen to hit every case in `split_clip`: before an action,
    // exactly at one's start, inside one, exactly at one's end, inside the
    // second and third, and one frame before the clip ends.
    for at in [
        3_000_000i64,
        3_600_000,
        3_800_000,
        4_200_000,
        7_800_000,
        11_700_000,
        12_000_000,
        14_380_000,
    ] {
        let split = project.apply(&json!({"op": "split", "clips": [20], "at": at}));
        let after = split.value();
        assert_eq!(
            array(&after, "/clips").len(),
            3,
            "the cut at {at} did not produce a second clip"
        );

        let rebuilt = Handle::from_value(&join(&after, 20, second_id));
        assert_eq!(
            rebuilt.to_json(),
            before,
            "split at {at} then join was not the identity"
        );
    }
}

#[test]
fn nested_splits_join_back_to_the_original() {
    let project = split_project();
    let before = project.to_json();

    let first_new = int(&project.value(), "/next_id") as u64;
    let once = project.apply(&json!({"op": "split", "clips": [20], "at": 3800000}));
    let second_new = int(&once.value(), "/next_id") as u64;
    let twice = once.apply(&json!({"op": "split", "clips": [first_new], "at": 7800000}));
    assert_eq!(array(&twice.value(), "/clips").len(), 4);

    // Joined right to left, the way they were cut.
    let inner = join(&twice.value(), first_new, second_new);
    let rebuilt = Handle::from_value(&join(&inner, 20, first_new));
    assert_eq!(rebuilt.to_json(), before);
}

#[test]
fn a_split_action_meets_at_the_evaluated_state() {
    let project = split_project();
    let new_clip = int(&project.value(), "/next_id") as u64;
    // Clip time 1 400 000: one third of the way through action 21, which
    // runs 1 200 000 – 1 800 000 with an ease_in_out curve.
    let split = project.apply(&json!({"op": "split", "clips": [20], "at": 3800000}));
    let after = split.value();

    // ease_in_out(u) = u²(3 − 2u); at u = 1/3 that is 7/27.
    let eased = 7.0 / 27.0;
    let scale = 0.8 + (0.6 - 0.8) * eased;
    let x = 40.0 + (520.0 - 40.0) * eased;

    let first = by_id(&after, "/clips", 20);
    assert_eq!(int(first, "/duration"), 1_400_000);
    assert_eq!(text(first, "/transition_in/kind"), "push_left");
    // The first half's base props are untouched by a split.
    close(
        num(first, "/video/x"),
        40.0,
        "the first half keeps its base x",
    );
    close(
        num(first, "/video/scale"),
        0.8,
        "the first half keeps its base scale",
    );
    assert_eq!(
        array(first, "/actions").len(),
        1,
        "actions 22 and 23 moved on"
    );
    let head = &array(first, "/actions")[0];
    assert_eq!(int(head, "/id"), 21, "the head keeps the action's id");
    assert_eq!(int(head, "/start"), 1_200_000);
    assert_eq!(int(head, "/duration"), 200_000);
    close(
        num(head, "/end/video/scale"),
        scale,
        "the head's target scale",
    );
    close(num(head, "/end/video/x"), x, "the head's target x");

    let second = by_id(&after, "/clips", new_clip);
    assert_eq!(int(second, "/start"), 3_800_000);
    assert_eq!(int(second, "/duration"), 10_600_000);
    assert_eq!(source_in(&after, new_clip), 1_200_000 + 1_400_000);
    assert!(
        at(second, "/transition_in").is_null(),
        "the transition stays with the first half"
    );
    close(
        num(second, "/video/scale"),
        scale,
        "the second half starts where the cut was",
    );
    close(
        num(second, "/video/x"),
        x,
        "the second half starts where the cut was",
    );
    // The audio props evaluate too, and a tick field stays an integer
    // through the evaluation rather than picking up a float tail.
    close(
        num(second, "/audio/volume"),
        0.9,
        "no audio action had run yet",
    );
    assert_eq!(int(second, "/audio/fade_in"), 120_000);

    let tails = array(second, "/actions");
    assert_eq!(tails.len(), 3);
    assert_eq!(
        int(&tails[0], "/start"),
        0,
        "the straddled tail is rebased to 0"
    );
    assert_eq!(int(&tails[0], "/duration"), 400_000);
    assert_eq!(
        text(&tails[0], "/curve"),
        "ease_in_out",
        "both halves keep the curve"
    );
    assert_eq!(tails[0]["end"], json!({"video": {"scale": 0.6, "x": 520}}));
    assert_eq!(int(&tails[1], "/id"), 22);
    assert_eq!(int(&tails[1], "/start"), 4_800_000 - 1_400_000);
    assert_eq!(int(&tails[2], "/id"), 23);
    assert_eq!(int(&tails[2], "/start"), 9_000_000 - 1_400_000);
}

#[test]
fn split_under_the_playhead_cuts_every_unlocked_clip_it_is_inside() {
    let project = ripple_project();
    // 3 000 000 is inside clip 11 (2 400 000 – 3 600 000) on the unlocked
    // picture track, inside clip 21 (3 000 000 – 4 200 000)? no — that one
    // starts there — and inside clip 30 (1 800 000 – 3 600 000) on the
    // unlocked music track. The locked track is skipped entirely.
    let after = project
        .apply(&json!({"op": "split", "at": 3000000}))
        .value();
    assert_eq!(array(&after, "/clips").len(), 9, "two clips became four");
    assert_eq!(placement(&after, 11), (2_400_000, 600_000));
    assert_eq!(placement(&after, 30), (1_800_000, 1_200_000));
    // Nothing on the locked track moved or was cut.
    assert_eq!(placement(&after, 20), (600_000, 1_200_000));
    assert_eq!(placement(&after, 21), (3_000_000, 1_200_000));
}

// ---- ripple --------------------------------------------------------------

#[test]
fn ripple_delete_closes_the_hole_and_leaves_locked_tracks_alone() {
    let project = ripple_project();
    let before = project.value();
    // Clip 11 occupies 2 400 000 – 3 600 000, so every clip on an UNLOCKED
    // track whose start is at or after 3 600 000 moves left by 1 200 000.
    let after = project
        .apply(&json!({"op": "ripple_delete", "clips": [11]}))
        .value();

    assert_eq!(array(&after, "/clips").len(), 6);
    // Hand-computed table.
    assert_eq!(
        placement(&after, 10),
        (0, 1_200_000),
        "before the span: unmoved"
    );
    assert_eq!(
        placement(&after, 12),
        (3_600_000, 1_200_000),
        "after the span: shifted"
    );
    assert_eq!(
        placement(&after, 30),
        (1_800_000, 1_800_000),
        "straddling: stays put"
    );
    assert_eq!(
        placement(&after, 31),
        (4_800_000, 600_000),
        "after the span: shifted"
    );

    // The locked track is untouched, field for field.
    for locked in [20u64, 21] {
        assert_eq!(
            by_id(&after, "/clips", locked),
            by_id(&before, "/clips", locked),
            "clip {locked} is on a locked track and must not change"
        );
    }

    // Two clips that both shifted keep their distance — the sync a ripple
    // exists to preserve.
    let (before_12, _) = placement(&before, 12);
    let (before_31, _) = placement(&before, 31);
    let (after_12, _) = placement(&after, 12);
    let (after_31, _) = placement(&after, 31);
    assert_eq!(after_31 - after_12, before_31 - before_12);

    // Markers do not move (spec §6): a mark inside a removed span has
    // nowhere to go.
    assert_eq!(int(by_id(&after, "/markers", 40), "/time"), 3_000_000);
    assert_eq!(int(by_id(&after, "/markers", 41), "/time"), 5_400_000);
}

#[test]
fn ripple_delete_range_splits_every_unlocked_clip_it_straddles() {
    let project = range_project();
    let before = project.value();
    // 2 400 000 – 4 200 000: clip 10 crosses the start, clip 30 crosses the
    // end, the locked clip 20 crosses both.
    let after = project
        .apply(&json!({"op": "ripple_delete_range", "from": 2400000, "to": 4200000}))
        .value();

    // Clip 10 keeps its head; the middle piece is gone.
    assert_eq!(placement(&after, 10), (0, 2_400_000));
    // Clip 11 started after the range and moves left by its whole length.
    assert_eq!(placement(&after, 11), (3_000_000, 1_200_000));
    // Clip 30's head was inside the range and went with it; its tail moved
    // left to the range start, carrying the source it had advanced to.
    let survivors: Vec<i64> = array(&after, "/clips")
        .iter()
        .filter(|c| int(c, "/track") == 4)
        .map(|c| int(c, "/id"))
        .collect();
    assert_eq!(
        survivors.len(),
        1,
        "clip 30's head was removed, its tail kept"
    );
    let tail = by_id(&after, "/clips", survivors[0] as u64);
    assert_eq!(int(tail, "/start"), 2_400_000);
    assert_eq!(int(tail, "/duration"), 3_000_000);
    assert_eq!(int(tail, "/source/in"), 1_200_000 + 1_200_000);

    // The locked clip is neither split, removed nor moved.
    assert_eq!(by_id(&after, "/clips", 20), by_id(&before, "/clips", 20));
    // A reversed drag is the same range.
    let reversed = project
        .apply(&json!({"op": "ripple_delete_range", "from": 4200000, "to": 2400000}))
        .to_json();
    assert_eq!(
        reversed,
        project
            .apply(&json!({"op": "ripple_delete_range", "from": 2400000, "to": 4200000}))
            .to_json()
    );
    // An empty range changes nothing.
    project.refuses(&json!({"op": "ripple_delete_range", "from": 2400000, "to": 2400000}));
}

#[test]
fn ripple_delete_ranges_cuts_right_to_left_like_the_singular_op() {
    let project = range_project();
    let before = project.value();
    // Two disjoint, non-touching ranges — 2 s – 3 s and 8 s – 9 s — so the
    // merge has nothing to do and the plural op does exactly the work the
    // singular op does twice.
    let plural = project.apply(&json!({"op": "ripple_delete_ranges",
                                       "ranges": [[1200000, 1800000], [4800000, 5400000]]}));

    // The oracle: the two singular ops, LATER RANGE FIRST, because closing
    // an earlier hole moves the clips a later hole's bounds were measured
    // against. Whole documents, so ids and `next_id` are part of the claim.
    let singly = project.apply_all(&[
        json!({"op": "ripple_delete_range", "from": 4800000, "to": 5400000}),
        json!({"op": "ripple_delete_range", "from": 1200000, "to": 1800000}),
    ]);
    assert_eq!(plural.to_json(), singly.to_json());

    // The same two singular ops the other way round are a DIFFERENT
    // document, which is what makes the comparison above a claim about the
    // order rather than about two ranges that happen to commute.
    let wrong_way = project.apply_all(&[
        json!({"op": "ripple_delete_range", "from": 1200000, "to": 1800000}),
        json!({"op": "ripple_delete_range", "from": 4800000, "to": 5400000}),
    ]);
    assert_ne!(plural.to_json(), wrong_way.to_json());

    // Hand-computed from the fixture. Clip 10 (0 – 6 s) loses 2 s – 3 s and
    // its tail slides left by one second; clip 11 (8 s – 10 s) loses its
    // first second and what is left slides left by both; clip 30
    // (5 s – 12 s) is cut in two by the later range, its head sliding left
    // by one second and its tail by two.
    let after = plural.value();
    assert_eq!(
        lane(&after, 2),
        vec![(0, 1_200_000), (1_200_000, 1_800_000), (4_200_000, 600_000)],
    );
    assert_eq!(
        lane(&after, 4),
        vec![(2_400_000, 1_800_000), (4_200_000, 1_800_000)],
    );
    // Two seconds came out, so the project is two seconds shorter.
    assert_eq!(plural.duration(), project.duration() - 1_200_000);

    // The locked track is untouched in both directions: neither cut by a
    // range that covers it nor moved by a shift that passed under it.
    assert_eq!(lane(&after, 3), lane(&before, 3));
    assert_eq!(by_id(&after, "/clips", 20), by_id(&before, "/clips", 20));

    // Markers do not move, exactly as they do not for the singular op.
    assert_eq!(int(by_id(&after, "/markers", 40), "/time"), 3_000_000);
}

#[test]
fn ripple_delete_ranges_merges_overlapping_and_touching_pairs() {
    let project = range_project();
    // The range the singular op's test above uses, reached three ways.
    let merged = project.apply(&json!({"op": "ripple_delete_range",
                                       "from": 2400000, "to": 4200000}));
    let one = merged.to_json();

    // Overlapping: 4 s – 6 s and 5 s – 7 s.
    assert_eq!(
        project
            .apply(&json!({"op": "ripple_delete_ranges",
                           "ranges": [[2400000, 3600000], [3000000, 4200000]]}))
            .to_json(),
        one,
    );
    // Touching: 4 s – 5 s and 5 s – 7 s. Two quiet spans that meet leave one
    // hole, and there is no cut at 5 s in the answer.
    assert_eq!(
        project
            .apply(&json!({"op": "ripple_delete_ranges",
                           "ranges": [[2400000, 3000000], [3000000, 4200000]]}))
            .to_json(),
        one,
    );
    // Out of order and duplicated: the merge sorts and collapses both.
    assert_eq!(
        project
            .apply(&json!({"op": "ripple_delete_ranges",
                           "ranges": [[3000000, 4200000], [2400000, 3600000],
                                      [2400000, 3600000]]}))
            .to_json(),
        one,
    );

    // The same touching pair cut as two singular ops is NOT that document,
    // which is what makes the merge a behaviour and not a tidy-up: the
    // second cut splits at 5 s, mints a fragment and removes it again, so
    // the placements come out the same and `next_id` comes out one higher.
    // That burnt id is the whole visible difference, and it is why the op
    // is defined as merge-then-cut rather than as N singular ops.
    let singly = project
        .apply_all(&[
            json!({"op": "ripple_delete_range", "from": 3000000, "to": 4200000}),
            json!({"op": "ripple_delete_range", "from": 2400000, "to": 3000000}),
        ])
        .value();
    let once = merged.value();
    assert_ne!(singly, once);
    for track in [2, 4] {
        assert_eq!(lane(&singly, track), lane(&once, track));
    }
    assert_eq!(int(&singly, "/next_id"), int(&once, "/next_id") + 1);
}

#[test]
fn ripple_delete_ranges_orders_clamps_and_snaps_every_pair_first() {
    let project = range_project();
    let one = project
        .apply(&json!({"op": "ripple_delete_range", "from": 2400000, "to": 4200000}))
        .to_json();

    // A list of one IS the singular op, byte for byte.
    assert_eq!(
        project
            .apply(&json!({"op": "ripple_delete_ranges", "ranges": [[2400000, 4200000]]}))
            .to_json(),
        one,
    );
    // A reversed pair is the same range, as a reversed drag is.
    assert_eq!(
        project
            .apply(&json!({"op": "ripple_delete_ranges", "ranges": [[4200000, 2400000]]}))
            .to_json(),
        one,
    );
    // A negative bound clamps to 0 rather than erroring — a project time,
    // not a length (the envelope's rule).
    assert_eq!(
        project
            .apply(&json!({"op": "ripple_delete_ranges", "ranges": [[-1200000, 1200000]]}))
            .to_json(),
        project
            .apply(&json!({"op": "ripple_delete_range", "from": 0, "to": 1200000}))
            .to_json(),
    );
    // Snapped BEFORE merging: one frame at 30 fps is 20 000 ticks, so these
    // two pairs land on 4 s – 5 s and 5 s – 7 s and merge. Merging first
    // would leave them five ticks apart and cut twice.
    assert_eq!(
        project
            .apply(&json!({"op": "ripple_delete_ranges",
                           "ranges": [[2400001, 3000000], [3000005, 4200000]]}))
            .to_json(),
        one,
    );
}

#[test]
fn ripple_delete_ranges_with_nothing_to_cut_changes_nothing() {
    let project = range_project();
    // An empty list is "nothing to do", not a malformed argument: the
    // answer that registers no undo step, as an empty selection does for
    // `ripple_delete`.
    project.refuses(&json!({"op": "ripple_delete_ranges", "ranges": []}));
    // Every pair empty — the last one only after snapping puts both of its
    // bounds on the same frame.
    project.refuses(&json!({"op": "ripple_delete_ranges",
                            "ranges": [[2400000, 2400000], [1200000, 1200000],
                                       [3000001, 2999999]]}));
    // A range past everything: nothing to split, nothing to remove and no
    // clip beyond it to shift.
    project.refuses(&json!({"op": "ripple_delete_ranges", "ranges": [[7200000, 8400000]]}));
    // Mixed, and the dead range costs one no-op pass and nothing else — not
    // even an id.
    assert_eq!(
        project
            .apply(&json!({"op": "ripple_delete_ranges",
                           "ranges": [[2400000, 4200000], [7200000, 8400000]]}))
            .to_json(),
        project
            .apply(&json!({"op": "ripple_delete_range", "from": 2400000, "to": 4200000}))
            .to_json(),
    );
}

#[test]
fn ripple_delete_ranges_takes_pairs_and_only_pairs() {
    let project = range_project();
    // A fixed-shape array, the spelling `Color` and `Fps` already use: a
    // pair of any other length is refused rather than read short or long.
    for (wrong, length) in [(json!([[2400000]]), 1), (json!([[0, 1200000, 2400000]]), 3)] {
        let msg = project.errors(&json!({"op": "ripple_delete_ranges", "ranges": wrong}));
        assert_contains(&msg, "op \"ripple_delete_ranges\" is not valid");
        assert_contains(&msg, &format!("invalid length {length}"));
    }
    // And the list itself is required — there is no "no ranges" default.
    assert_contains(
        &project.errors(&json!({"op": "ripple_delete_ranges"})),
        "missing field `ranges`",
    );
}

#[test]
fn lift_range_removes_the_middle_and_moves_nothing() {
    let project = range_project();
    let before = project.value();
    // The same range the ripple test uses, so the difference between the
    // two ops is exactly the difference between the two results.
    let after = project
        .apply(&json!({"op": "lift_range", "from": 2400000, "to": 4200000}))
        .value();

    // Clip 10 keeps its head; the middle piece is gone.
    assert_eq!(placement(&after, 10), (0, 2_400_000));
    // And clip 11 stays exactly where it was — this is the whole point.
    assert_eq!(
        by_id(&after, "/clips", 11),
        by_id(&before, "/clips", 11),
        "a lift moved a clip after the range"
    );

    // Clip 30's head was inside the range and went with it; its tail stayed
    // where it was, carrying the source it had advanced to.
    let survivors: Vec<i64> = array(&after, "/clips")
        .iter()
        .filter(|c| int(c, "/track") == 4)
        .map(|c| int(c, "/id"))
        .collect();
    assert_eq!(
        survivors.len(),
        1,
        "clip 30's head was removed, its tail kept"
    );
    let tail = by_id(&after, "/clips", survivors[0] as u64);
    assert_eq!(int(tail, "/start"), 4_200_000);
    assert_eq!(int(tail, "/duration"), 3_000_000);
    assert_eq!(int(tail, "/source/in"), 1_200_000 + 1_200_000);

    // The locked clip is neither split, removed nor moved; the marker
    // inside the range stays, because nothing under it moved.
    assert_eq!(by_id(&after, "/clips", 20), by_id(&before, "/clips", 20));
    assert_eq!(int(by_id(&after, "/markers", 40), "/time"), 3_000_000);

    // A reversed drag is the same range.
    assert_eq!(
        project
            .apply(&json!({"op": "lift_range", "from": 4200000, "to": 2400000}))
            .to_json(),
        project
            .apply(&json!({"op": "lift_range", "from": 2400000, "to": 4200000}))
            .to_json()
    );
    // An empty range, and a range with nothing an unlocked track can give
    // up, both change nothing.
    project.refuses(&json!({"op": "lift_range", "from": 2400000, "to": 2400000}));
    project.refuses(&json!({"op": "lift_range", "from": 7200000, "to": 8400000}));
}

#[test]
fn close_gap_takes_the_whole_gap_out_of_every_unlocked_track() {
    let project = gap_project();
    let before = project.value();
    // The gap in front of clip 10 runs 0 – 4 s, so everything from 4 s on
    // moves left by four seconds and nothing before it exists to move.
    let after = project
        .apply(&json!({"op": "close_gap", "track": 2, "at": 1200000}))
        .value();
    assert_eq!(placement(&after, 10), (0, 1_200_000));
    assert_eq!(placement(&after, 11), (2_400_000, 1_200_000));
    // The shift is timeline-wide: the bed moves by the same four seconds,
    // except the clip that began before the gap's end.
    assert_eq!(by_id(&after, "/clips", 20), by_id(&before, "/clips", 20));
    assert_eq!(placement(&after, 21), (1_800_000, 1_200_000));
    assert_eq!(placement(&after, 22), (3_600_000, 600_000));
    // The locked track keeps both of its clips and its own gap.
    assert_eq!(by_id(&after, "/clips", 30), by_id(&before, "/clips", 30));
    assert_eq!(by_id(&after, "/clips", 31), by_id(&before, "/clips", 31));
    // Markers do not move, as they do not for any other ripple.
    assert_eq!(
        by_id(&after, "/markers", 40),
        by_id(&before, "/markers", 40)
    );

    // Clip 35 lands 600 000 ticks over clip 34, which is inside the overlap
    // rule's limit — and an overlap IS a transition, so the newcomer gets
    // the default dissolve rather than rendering as two stacked layers.
    assert_eq!(placement(&after, 34), (0, 2_400_000));
    assert_eq!(placement(&after, 35), (1_800_000, 2_400_000));
    assert_eq!(
        text(by_id(&after, "/clips", 35), "/transition_in/kind"),
        "cross_dissolve"
    );
}

#[test]
fn close_gap_refuses_rather_than_closing_part_of_the_way() {
    let project = gap_project();
    // Closing the 6 s – 8 s gap would slide clip 22 two seconds left, onto
    // clip 21, by more than half the shorter of the two. A gap closes fully
    // or not at all, so this is a refusal and not a partial close.
    project.refuses(&json!({"op": "close_gap", "track": 2, "at": 4200000}));

    // A locked track never moves, so the gap on it cannot be closed either.
    // Track 5's gap is the honest test of that: closing it would be legal
    // for every other track, so the ONLY reason this refuses is the lock.
    project.refuses(&json!({"op": "close_gap", "track": 5, "at": 900000}));
    project.refuses(&json!({"op": "close_gap", "track": 4, "at": 2400000}));
    // A playhead on a clip is not in a gap.
    project.refuses(&json!({"op": "close_gap", "track": 2, "at": 3000000}));
    // And a gap with nothing after it is not one to close.
    project.refuses(&json!({"op": "close_gap", "track": 2, "at": 7000000}));

    assert_contains(
        &project.errors(&json!({"op": "close_gap", "track": 99, "at": 0})),
        "no track with id 99",
    );
}

#[test]
fn insert_time_opens_a_hole_and_carries_the_markers() {
    let project = ripple_project();
    let after = project
        .apply(&json!({"op": "insert_time", "at": 3000000, "length": 1200000}))
        .value();

    // Unlocked clips at or after 3 000 000 move right; straddlers stay.
    assert_eq!(placement(&after, 10), (0, 1_200_000));
    assert_eq!(
        placement(&after, 11),
        (2_400_000, 1_200_000),
        "straddles 3 000 000"
    );
    assert_eq!(placement(&after, 12), (6_000_000, 1_200_000));
    assert_eq!(
        placement(&after, 30),
        (1_800_000, 1_800_000),
        "straddles 3 000 000"
    );
    assert_eq!(placement(&after, 31), (7_200_000, 600_000));
    // The locked track never moves.
    assert_eq!(placement(&after, 21), (3_000_000, 1_200_000));
    // Markers at or after the insert DO move — a marker names a moment in
    // the cut (spec §6).
    assert_eq!(int(by_id(&after, "/markers", 40), "/time"), 4_200_000);
    assert_eq!(int(by_id(&after, "/markers", 41), "/time"), 6_600_000);

    assert_contains(
        &project.errors(&json!({"op": "insert_time", "at": 0, "length": -600000})),
        "insert length must not be negative",
    );
}

// ---- the overlap rule ----------------------------------------------------

#[test]
fn move_clip_accepts_an_overlap_of_exactly_half_the_shorter_clip() {
    let project = overlap_project();
    // Clip 10 is 0 – 1000, clip 11 is 2000 – 3000. Both are 1000 long, so
    // the limit is 500 ticks of overlap.

    // No overlap at all: the clips meet exactly, and a zero-length overlap
    // is a cut, not a transition.
    let abutting = project.apply(&json!({"op": "move_clip", "clips": [11], "delta": -1000}));
    let after = abutting.value();
    assert_eq!(placement(&after, 11), (1000, 1000));
    assert!(
        at(by_id(&after, "/clips", 11), "/transition_in").is_null(),
        "a cut is not a transition"
    );

    // Exactly half: accepted, and the clip that GAINED a predecessor overlap
    // gets the default transition.
    let half = project.apply(&json!({"op": "move_clip", "clips": [11], "delta": -1500}));
    let after = half.value();
    assert_eq!(placement(&after, 11), (500, 1000));
    assert_eq!(
        text(by_id(&after, "/clips", 11), "/transition_in/kind"),
        "cross_dissolve"
    );

    // One tick more: refused. Clips never push (spec §11).
    project.refuses(&json!({"op": "move_clip", "clips": [11], "delta": -1501}));
}

#[test]
fn move_clip_refuses_two_neighbours_on_one_side() {
    let project = overlap_project();
    // Track C holds clip 15 (0 – 1000) and clip 16 (900 – 1300), already
    // overlapping by 100 of the 200 the shorter of them allows. Clip 17
    // (400 long) dropped at 950 would sit inside clip 16 AND still reach
    // back into clip 15: a clip may overlap at most ONE neighbour on each
    // side (spec §11), so the drop is refused rather than stacking three
    // layers at one instant.
    project.refuses(&json!({"op": "move_clip", "clips": [17], "delta": -4050}));

    // Landing at 1200 it reaches only clip 16, by 100 ticks of the 200 the
    // pair allows, and clip 15 ends before it starts.
    let ok = project
        .apply(&json!({"op": "move_clip", "clips": [17], "delta": -3800}))
        .value();
    assert_eq!(placement(&ok, 17), (1200, 400));
    assert_eq!(
        text(by_id(&ok, "/clips", 17), "/transition_in/kind"),
        "cross_dissolve"
    );
    // Clip 16 already names a kind for the overlap it had, and keeps it.
    assert_eq!(
        text(by_id(&ok, "/clips", 16), "/transition_in/kind"),
        "fade_black"
    );
}

#[test]
fn move_clip_accepts_overlaps_on_both_sides_within_the_limit() {
    let project = overlap_project();
    // Clip 14 (3000 – 4000) moves to 800: it then overlaps clip 12
    // (0 – 1000) by 200 and clip 13 (1500 – 2500) by 300, both under the
    // 500-tick limit, and clips 12 and 13 still do not touch.
    let after = project
        .apply(&json!({"op": "move_clip", "clips": [14], "delta": -2200}))
        .value();
    assert_eq!(placement(&after, 14), (800, 1000));

    // The mover gained a predecessor overlap and had no transition: it gets
    // the default.
    assert_eq!(
        text(by_id(&after, "/clips", 14), "/transition_in/kind"),
        "cross_dissolve"
    );
    // Clip 13 gained one too, but it already names a kind, which is left
    // alone.
    assert_eq!(
        text(by_id(&after, "/clips", 13), "/transition_in/kind"),
        "wipe"
    );
}

#[test]
fn move_clip_clamps_the_selection_at_zero_and_keeps_relative_offsets() {
    let project = ripple_project();
    // Clips 30 (1 800 000) and 31 (6 000 000) share the music track. Dragged
    // 3 000 000 left, the EARLIEST of them stops at 0 and the other keeps
    // its offset — the drag compresses nothing.
    let after = project
        .apply(&json!({"op": "move_clip", "clips": [30, 31], "delta": -3000000}))
        .value();
    assert_eq!(placement(&after, 30), (0, 1_800_000));
    assert_eq!(placement(&after, 31), (4_200_000, 600_000));

    // A retarget moves the whole selection by a track-INDEX delta.
    let moved = project
        .apply(&json!({"op": "move_clip", "clips": [10], "delta": 0, "track": 4}))
        .value();
    assert_eq!(int(by_id(&moved, "/clips", 10), "/track"), 4);
}

// ---- trims ---------------------------------------------------------------

#[test]
fn trim_start_clamps_at_the_source_head_and_one_frame_before_the_end() {
    let project = trim_project();
    // Clip 10: 3 000 000 – 9 000 000, source in 1 200 000 at speed 1, so
    // 1 200 000 ticks of source lie in front of it.
    let head = project
        .apply(&json!({"op": "trim_start", "clip": 10, "to": 0}))
        .value();
    assert_eq!(placement(&head, 10), (1_800_000, 7_200_000));
    assert_eq!(
        source_in(&head, 10),
        0,
        "the source head is exhausted, not passed"
    );

    // The other end: dragged past the tail, the start stops one frame short.
    let tail = project
        .apply(&json!({"op": "trim_start", "clip": 10, "to": 100000000}))
        .value();
    assert_eq!(placement(&tail, 10), (9_000_000 - FRAME, FRAME));
    assert_eq!(
        source_in(&tail, 10),
        1_200_000 + (9_000_000 - FRAME - 3_000_000)
    );

    // A clip already one frame long has no legal new start.
    project.refuses(&json!({"op": "trim_start", "clip": 11, "to": 600000}));
    // And a trim to where the clip already starts changes nothing.
    project.refuses(&json!({"op": "trim_start", "clip": 10, "to": 3000000}));
}

#[test]
fn trim_end_clamps_at_the_source_tail_and_one_frame_after_the_start() {
    let project = trim_project();
    // Source remaining from in 1 200 000 is 34 800 000 ticks at speed 1.
    let tail = project
        .apply(&json!({"op": "trim_end", "clip": 10, "to": 999999999}))
        .value();
    assert_eq!(placement(&tail, 10), (3_000_000, 34_800_000));

    // Dragged back past the start, the end stops one frame after it.
    let head = project
        .apply(&json!({"op": "trim_end", "clip": 10, "to": 0}))
        .value();
    assert_eq!(placement(&head, 10), (3_000_000, FRAME));

    // Clip 12's in point is the very end of its media: there is no legal
    // end at all, so the op refuses rather than making a sub-frame clip.
    project.refuses(&json!({"op": "trim_end", "clip": 12, "to": 4000000}));
}

// ---- speed ---------------------------------------------------------------

#[test]
fn set_speed_keeps_each_actions_clip_relative_fraction() {
    let project = speed_project();
    // The clip is 6 000 000 long; its action runs 1 200 000 – 1 800 000, so
    // it starts one fifth in and lasts one tenth of the clip.
    for (rate, duration) in [(2.0f64, 3_000_000i64), (0.5, 12_000_000)] {
        let after = project
            .apply(&json!({"op": "set_speed", "clip": 10, "rate": rate}))
            .value();
        let clip = by_id(&after, "/clips", 10);
        assert_eq!(int(clip, "/duration"), duration);
        close(num(clip, "/speed"), rate, "the new rate");

        let action = &array(clip, "/actions")[0];
        let start = int(action, "/start");
        let length = int(action, "/duration");
        assert_eq!(start * 5, duration, "the action still starts one fifth in");
        assert_eq!(length * 10, duration, "the action still lasts one tenth");
    }

    // keep_pitch rides along when the clip has audio props.
    let pitched = project
        .apply(&json!({"op": "set_speed", "clip": 10, "rate": 2.0, "keep_pitch": false}))
        .value();
    assert!(!flag(by_id(&pitched, "/clips", 10), "/audio/keep_pitch"));

    // The rate is clamped to the inspector's range rather than refused, and
    // a rate that is not a positive number is an error.
    let clamped = project
        .apply(&json!({"op": "set_speed", "clip": 10, "rate": 4000.0}))
        .value();
    close(
        num(by_id(&clamped, "/clips", 10), "/speed"),
        1000.0,
        "the clamped rate",
    );
    assert_contains(
        &project.errors(&json!({"op": "set_speed", "clip": 10, "rate": 0.0})),
        "speed must be a positive number",
    );
}

#[test]
fn rate_stretch_makes_the_content_fill_the_new_length() {
    let project = speed_project();
    // The clip holds 6 000 000 ticks of source (duration × speed).
    for to_end in [4_800_000i64, 9_000_000, 6_600_000] {
        let after = project
            .apply(&json!({"op": "rate_stretch", "clip": 10, "to_end": to_end}))
            .value();
        let clip = by_id(&after, "/clips", 10);
        let duration = int(clip, "/duration");
        assert_eq!(duration, to_end, "the end edge lands where it was dragged");
        let content = (duration as f64 * num(clip, "/speed")).round() as i64;
        assert!(
            (content - 6_000_000).abs() <= 1,
            "a stretch to {to_end} left {content} ticks of content, not 6 000 000"
        );
    }

    // Outside ×0.1 – ×1000 the drag is refused, as is a length under a frame.
    project.refuses(&json!({"op": "rate_stretch", "clip": 10, "to_end": 90000000}));
    project.refuses(&json!({"op": "rate_stretch", "clip": 10, "to_end": 9000}));
    assert_contains(
        &general().errors(&json!({"op": "rate_stretch", "clip": 30, "to_end": 1200000})),
        "clip 30 is not a media clip",
    );
}

// ---- detach audio --------------------------------------------------------

#[test]
fn detach_audio_moves_the_sound_to_the_track_below() {
    let project = detach_project();
    let new_id = int(&project.value(), "/next_id") as u64;
    let after = project
        .apply(&json!({"op": "detach_audio", "clip": 10}))
        .value();

    assert_eq!(
        array(&after, "/tracks").len(),
        2,
        "there was already a track below"
    );
    let original = by_id(&after, "/clips", 10);
    assert!(
        flag(original, "/enabled/video"),
        "the picture stays with the original"
    );
    assert!(!flag(original, "/enabled/audio"), "the original is muted");

    let twin = by_id(&after, "/clips", new_id);
    assert_eq!(int(twin, "/track"), 3, "the twin lands on the track below");
    assert_eq!(int(twin, "/start"), 0);
    assert_eq!(int(twin, "/duration"), 3_000_000);
    assert_eq!(int(twin, "/source/in"), 600_000);
    close(num(twin, "/speed"), 1.0, "the twin keeps the clip's rate");
    assert!(!flag(twin, "/enabled/video"));
    assert!(flag(twin, "/enabled/audio"));
    close(
        num(twin, "/audio/volume"),
        0.8,
        "the twin carries the audio props",
    );
    assert!(
        at(twin, "/transition_in").is_null(),
        "the transition describes the old track"
    );

    // A second detach has nothing left to move.
    let once = project.apply(&json!({"op": "detach_audio", "clip": 10}));
    once.refuses(&json!({"op": "detach_audio", "clip": 10}));
    // Neither has a clip whose media carries no audio.
    project.refuses(&json!({"op": "detach_audio", "clip": 20}));
}

#[test]
fn detach_audio_inserts_a_track_under_the_bottom_one() {
    let project = detach_project();
    let track_id = int(&project.value(), "/next_id") as u64;
    // Clip 30 is on track 3, which is the back-most track, so the audio
    // needs a track of its own beneath it.
    let after = project
        .apply(&json!({"op": "detach_audio", "clip": 30}))
        .value();

    let tracks = array(&after, "/tracks");
    assert_eq!(tracks.len(), 3);
    assert_eq!(
        int(&tracks[0], "/id"),
        track_id as i64,
        "the new track is the back-most"
    );
    // Named by the COUNT, so the tracks above it are not renumbered.
    assert_eq!(text(&tracks[0], "/name"), "Track 3");

    let twin = by_id(&after, "/clips", track_id + 1);
    assert_eq!(int(twin, "/track"), track_id as i64);
    assert_eq!(int(twin, "/start"), 12_000_000);
    assert!(flag(twin, "/enabled/audio"));
}

// ---- freeze frame --------------------------------------------------------

#[test]
fn freeze_frame_holds_the_frame_under_the_playhead_and_keeps_the_cut_in_sync() {
    let project = freeze_project();
    let first_new = int(&project.value(), "/next_id") as u64;
    // Clip 10 starts at 0 with source in 600 000; the playhead at 3 600 000
    // is one half of the way through the scale action (3 000 000 –
    // 4 200 000, linear, 1.0 → 0.5).
    let after = project
        .apply(&json!({"op": "freeze_frame", "clip": 10, "at": 3600000, "duration": 1200000}))
        .value();

    // The split, then the insert: the clip's own tail moved right by the
    // freeze length, and the hole it left is filled by the still.
    assert_eq!(placement(&after, 10), (0, 3_600_000));
    assert_eq!(placement(&after, first_new), (4_800_000, 8_400_000));

    // The still is the only clip left on the picture track, and it names the
    // source time that was under the playhead.
    let still_id = array(&after, "/clips")
        .iter()
        .find(|c| text(c, "/source/kind") == "still")
        .map(|c| int(c, "/id"))
        .expect("a still was added");
    let still = by_id(&after, "/clips", still_id as u64);
    assert_eq!(int(still, "/track"), 2);
    assert_eq!(int(still, "/start"), 3_600_000);
    assert_eq!(int(still, "/duration"), 1_200_000);
    assert_eq!(int(still, "/source/at"), 600_000 + 3_600_000);
    assert!(flag(still, "/enabled/video"));
    assert!(!flag(still, "/enabled/audio"), "a held frame has no sound");
    assert!(at(still, "/audio").is_null());
    assert!(
        array(still, "/actions").is_empty(),
        "the state is baked into the base props"
    );
    // Halfway through a linear 1.0 → 0.5 action, so the hold sits exactly
    // where the frame it froze sat.
    close(
        num(still, "/video/scale"),
        0.75,
        "the still's evaluated scale",
    );

    // Every OTHER unlocked track moved by the freeze length, so the cut
    // stays in sync (spec §11).
    assert_eq!(
        placement(&after, 20),
        (1_200_000, 1_200_000),
        "before the freeze: unmoved"
    );
    assert_eq!(placement(&after, 21), (6_000_000 + 1_200_000, 1_200_000));
    // The locked track did not.
    assert_eq!(placement(&after, 30), (6_000_000, 1_200_000));
    // Insert time carries the markers.
    assert_eq!(int(by_id(&after, "/markers", 40), "/time"), 7_200_000);
}

#[test]
fn freeze_frame_names_what_it_will_not_hold() {
    let project = freeze_project();
    assert_contains(
        &project.errors(&json!({"op": "freeze_frame", "clip": 999, "at": 0})),
        "no clip with id 999",
    );
    assert_contains(
        &project.errors(&json!({"op": "freeze_frame", "clip": 10, "at": 13000000})),
        "clip 10 does not cover 13000000",
    );
    assert_contains(
        &project.errors(&json!({"op": "freeze_frame", "clip": 10, "at": 3600000,
                                "duration": 1})),
        "freeze duration must be at least one frame",
    );
    assert_contains(
        &general().errors(&json!({"op": "freeze_frame", "clip": 30, "at": 1200000})),
        "clip 30 is not a media clip",
    );
}

// ---- canvas --------------------------------------------------------------

#[test]
fn set_canvas_rescales_placements_only_when_asked() {
    let project = canvas_project();
    // 1920 × 1080 → 960 × 1080: the width ratio is one half, the height
    // ratio is one, and `scale` follows the smaller of the two.
    let rescaled = project
        .apply(&json!({"op": "set_canvas", "width": 960, "height": 1080,
                       "rescale_clips": true}))
        .value();
    let clip = by_id(&rescaled, "/clips", 10);
    close(num(clip, "/video/x"), 50.0, "x follows the width ratio");
    close(num(clip, "/video/y"), 50.0, "y follows the height ratio");
    close(
        num(clip, "/video/scale"),
        0.25,
        "scale follows the smaller ratio",
    );

    // Without `rescale_clips` the same resize leaves the layout alone.
    let plain = project
        .apply(&json!({"op": "set_canvas", "width": 960, "height": 1080}))
        .value();
    let clip = by_id(&plain, "/clips", 10);
    close(num(clip, "/video/x"), 100.0, "x is untouched");
    close(num(clip, "/video/scale"), 0.5, "scale is untouched");

    assert_contains(
        &project.errors(&json!({"op": "set_canvas", "width": 1921})),
        "canvas width must be even",
    );
    assert_contains(
        &project.errors(&json!({"op": "set_canvas", "width": 4})),
        "canvas width must be between 16 and 16384, not 4",
    );
    assert_contains(
        &project.errors(&json!({"op": "set_canvas", "fps": [0, 1]})),
        "canvas fps must be [num, den] with non-zero terms",
    );
}

#[test]
fn changing_the_canvas_rate_resnaps_every_stored_time() {
    let project = canvas_project();
    // 30 fps frames are 20 000 ticks, 24 fps frames 25 000. Every time in
    // the fixture is on the first grid and off the second, so each one has
    // to move to its nearest new boundary:
    //   clip start    1 220 000 / 25 000 = 48.8  → 49 → 1 225 000
    //   clip duration 1 180 000 / 25 000 = 47.2  → 47 → 1 175 000
    //   action start    140 000 / 25 000 =  5.6  →  6 →   150 000
    //   action length     60 000 / 25 000 =  2.4  →  2 →    50 000
    //   marker        1 220 000                  →      1 225 000
    let after = project
        .apply(&json!({"op": "set_canvas", "fps": [24, 1]}))
        .value();
    assert_eq!(at(&after, "/canvas/fps"), &json!([24, 1]));
    assert_eq!(placement(&after, 10), (1_225_000, 1_175_000));
    let action = &array(by_id(&after, "/clips", 10), "/actions")[0];
    assert_eq!(int(action, "/start"), 150_000);
    assert_eq!(int(action, "/duration"), 50_000);
    assert_eq!(int(by_id(&after, "/markers", 12), "/time"), 1_225_000);
}

// ---- media ---------------------------------------------------------------

#[test]
fn add_media_assigns_next_id_and_ignores_a_path_already_there() {
    let project = general();
    let before = project.value();
    let expected_id = int(&before, "/next_id");

    let descriptor = json!({"path": "/m/broll.mov", "kind": "video", "duration": 12000000,
                            "width": 1280, "height": 720, "fps": [30, 1],
                            "has_video": true, "has_audio": true});
    let op = json!({"op": "add_media", "descriptor": descriptor});
    let after = project.apply(&op).value();

    assert_eq!(array(&after, "/media").len(), 4);
    let added = by_id(&after, "/media", expected_id as u64);
    assert_eq!(text(added, "/path"), "/m/broll.mov");
    assert_eq!(int(&after, "/next_id"), expected_id + 1);

    // The same file again changes nothing: two entries for one path would
    // each carry their own bookmark and caches.
    let twice = project.apply(&op);
    twice.refuses(&op);

    // The descriptor is the media element MINUS its id, and a misspelt key
    // is named rather than dropped.
    assert_contains(
        &project.errors(
            &json!({"op": "add_media", "descriptor": {"id": 99, "path": "/m/x.mov",
                                                                  "kind": "video"}}),
        ),
        "a media descriptor must not carry an id",
    );
    assert_contains(
        &project.errors(&json!({"op": "add_media",
                                "descriptor": {"path": "/m/x.mov", "kind": "video",
                                               "widht": 1920}})),
        "unknown key \"widht\" in a media descriptor",
    );
}

#[test]
fn remove_media_takes_its_clips_only_when_asked() {
    let project = general();
    project.refuses(&json!({"op": "remove_media", "media": 1}));
    let after = project
        .apply(&json!({"op": "remove_media", "media": 1, "with_clips": true}))
        .value();
    assert_eq!(array(&after, "/media").len(), 2);
    assert_eq!(
        array(&after, "/clips").len(),
        5,
        "only clip 10 used media 1"
    );
}

// ---- tracks and markers --------------------------------------------------

#[test]
fn a_project_always_keeps_one_track() {
    let project = Handle::new(1920, 1080, 30, 1);
    project.refuses(&json!({"op": "remove_track", "track": 1}));
    let two = project.apply(&json!({"op": "add_track"}));
    let after = two
        .apply(&json!({"op": "remove_track", "track": 1}))
        .value();
    assert_eq!(array(&after, "/tracks").len(), 1);

    // `remove_empty_tracks` keeps the back-most rather than emptying the
    // stack.
    let three = two.apply(&json!({"op": "add_track"}));
    let tidied = three.apply(&json!({"op": "remove_empty_tracks"})).value();
    assert_eq!(array(&tidied, "/tracks").len(), 1);
    assert_eq!(
        int(&array(&tidied, "/tracks")[0], "/id"),
        1,
        "the back-most survives"
    );
}

#[test]
fn two_markers_may_not_share_a_tick() {
    let project = general();
    // The fixture's marker 50 is at 6 000 000.
    assert_contains(
        &project.errors(&json!({"op": "add_marker", "at": 6000000})),
        "marker 50 is already at 6000000 ticks",
    );
    let second = project.apply(&json!({"op": "add_marker", "at": 1200000, "chapter": true}));
    let after = second.value();
    let added = by_id(&after, "/markers", 60);
    assert_eq!(int(added, "/time"), 1_200_000);
    assert_eq!(text(added, "/name"), "Marker 2", "named by the count");
    assert_eq!(text(added, "/color"), "red", "the default palette name");
    assert!(flag(added, "/chapter"));

    assert_contains(
        &second.errors(&json!({"op": "set_marker", "marker": 60, "time": 6000000})),
        "marker 50 is already at 6000000 ticks",
    );
    // A marker dragged left of zero clamps rather than erroring.
    let clamped = project
        .apply(&json!({"op": "add_marker", "at": -600000}))
        .value();
    assert_eq!(int(by_id(&clamped, "/markers", 60), "/time"), 0);
}

#[test]
fn set_track_solo_sets_clears_and_refuses_when_unchanged() {
    let project = general();
    let before = project.value();
    // Every fixture track starts unsoloed, so "solo off" is the identity.
    project.refuses(&json!({"op": "set_track", "track": 4, "solo": false}));

    let soloed = project.apply(&json!({"op": "set_track", "track": 4, "solo": true}));
    // The oracle: the document as it was with that ONE flag flipped — track 4
    // is the back-most, index 0.
    let mut expected = before.clone();
    expected["tracks"][0]["solo"] = json!(true);
    assert_eq!(soloed.value(), expected, "solo on track 4 and nothing else");
    soloed.refuses(&json!({"op": "set_track", "track": 4, "solo": true}));

    // Off again is the original document, and solo rides with the other
    // switches in one op.
    let back = soloed.apply(&json!({"op": "set_track", "track": 4, "solo": false}));
    assert_eq!(back.value(), before);
    let both = project
        .apply(&json!({"op": "set_track", "track": 5, "muted": true, "solo": true}))
        .value();
    assert!(flag(by_id(&both, "/tracks", 5), "/muted"));
    assert!(flag(by_id(&both, "/tracks", 5), "/solo"));
}

// ---- clip identity -------------------------------------------------------

/// The `set_clip` envelope over one clip.
fn set_clip(clip: i64, patch: Value) -> Value {
    json!({"op": "set_clip", "clips": [clip], "patch": patch})
}

/// `project` with the clip of `clip`'s id replaced by `clip` — the oracle
/// for an op that may touch one clip and nothing else.
fn with_clip(project: &Value, clip: &Value) -> Value {
    let id = clip["id"].as_u64().expect("a clip has an id");
    let mut out = project.clone();
    if let Some(slot) = out["clips"]
        .as_array_mut()
        .and_then(|clips| clips.iter_mut().find(|c| c["id"].as_u64() == Some(id)))
    {
        *slot = clip.clone();
    }
    out
}

#[test]
fn set_clip_stores_a_name_and_a_label_and_touches_nothing_else() {
    let project = general();
    let before = project.value();
    let after = project
        .apply(&set_clip(10, json!({"name": "Talk", "label": "blue"})))
        .value();
    let clip = by_id(&after, "/clips", 10);
    assert_eq!(text(clip, "/name"), "Talk");
    assert_eq!(text(clip, "/label"), "blue");

    // The oracle: the clip as it was with exactly those two keys rewritten,
    // in a document that is otherwise byte for byte the one it came from.
    let mut expected = by_id(&before, "/clips", 10).clone();
    expected["name"] = json!("Talk");
    expected["label"] = json!("blue");
    assert_eq!(after, with_clip(&before, &expected));
}

#[test]
fn a_null_or_an_empty_string_clears_and_a_name_is_trimmed() {
    let project = general();
    let named = project.apply(&set_clip(
        10,
        json!({"name": "  Talk, take 2\t", "label": " blue "}),
    ));
    let value = named.value();
    let clip = by_id(&value, "/clips", 10);
    assert_eq!(text(clip, "/name"), "Talk, take 2", "stored trimmed");
    assert_eq!(text(clip, "/label"), "blue");

    // Each of the three spellings of "none" takes the document all the way
    // back to the unnamed original — `null` because that is what the schema
    // stores, an empty or blank string because "unnamed" is `None` here and
    // a stored "" would hide the fallback name behind nothing.
    for cleared in [json!(null), json!(""), json!("   \t ")] {
        let after = named
            .apply(&set_clip(10, json!({"name": cleared, "label": cleared})))
            .value();
        assert_eq!(
            after,
            project.value(),
            "clearing with {cleared} left something"
        );
    }
}

#[test]
fn an_omitted_key_keeps_its_value() {
    let project = general();
    let named = project.apply(&set_clip(10, json!({"name": "Talk", "label": "blue"})));
    let before = named.value();

    let relabelled = named
        .apply(&set_clip(10, json!({"label": "green"})))
        .value();
    let mut expected = by_id(&before, "/clips", 10).clone();
    expected["label"] = json!("green");
    assert_eq!(
        relabelled,
        with_clip(&before, &expected),
        "the name went with the label"
    );

    let renamed = named.apply(&set_clip(10, json!({"name": "Intro"}))).value();
    let mut expected = by_id(&before, "/clips", 10).clone();
    expected["name"] = json!("Intro");
    assert_eq!(
        renamed,
        with_clip(&before, &expected),
        "the label went with the name"
    );
}

#[test]
fn set_clip_that_changes_nothing_is_a_refusal() {
    let project = general();
    // Unnamed already, so clearing is the identity — and so are an empty
    // patch and an empty selection.
    project.refuses(&set_clip(10, json!({"name": null, "label": ""})));
    project.refuses(&set_clip(10, json!({})));
    project.refuses(&json!({"op": "set_clip", "clips": [], "patch": {"name": "Talk"}}));

    let named = project.apply(&set_clip(10, json!({"name": "Talk", "label": "blue"})));
    named.refuses(&set_clip(10, json!({"name": "Talk"})));
    // What is stored is the trimmed text, so the same name with spaces
    // around it is the same name.
    named.refuses(&set_clip(10, json!({"name": "  Talk  ", "label": "blue"})));
}

#[test]
fn a_bad_clip_patch_is_an_error_naming_what_was_wrong() {
    let project = general();
    assert_eq!(
        project.errors(&set_clip(10, json!({"nmae": "Talk"}))),
        "unknown key \"nmae\" in a clip patch"
    );
    assert_eq!(
        project.errors(&set_clip(10, json!({"name": 5}))),
        "\"name\" in a clip patch must be a string or null, not 5"
    );
    assert_eq!(
        project.errors(&set_clip(10, json!({"label": ["blue"]}))),
        "\"label\" in a clip patch must be a string or null, not [\"blue\"]"
    );
    assert_eq!(
        project.errors(&json!({"op": "set_clip", "clips": [10], "patch": "Talk"})),
        "clip patch must be a json object, not \"Talk\""
    );
    assert_contains(
        &project.errors(&set_clip(999, json!({"name": "Talk"}))),
        "no clip with id 999",
    );
    // The patch is checked BEFORE the clip ids are resolved (spec §6), so an
    // unknown key is refused with an empty selection — where a valid patch
    // is the identity — and beside an unknown id, where it outranks the id
    // error. The four group patches order it the other way round; this one
    // does not, and the docs say so.
    assert_eq!(
        project.errors(&json!({"op": "set_clip", "clips": [], "patch": {"nmae": "x"}})),
        "unknown key \"nmae\" in a clip patch"
    );
    assert_eq!(
        project.errors(&json!({"op": "set_clip", "clips": [999], "patch": {"nmae": "x"}})),
        "unknown key \"nmae\" in a clip patch"
    );
    // The envelope's own rule still applies: a key the op does not take.
    assert_contains(
        &project.errors(&json!({"op": "set_clip", "clips": [10], "name": "Talk"})),
        "op \"set_clip\" is not valid",
    );
}

#[test]
fn set_clip_applies_to_every_named_clip() {
    let project = general();
    let before = project.value();
    let after = project
        .apply(&json!({"op": "set_clip", "clips": [40, 10, 30], "patch": {"label": "red"}}))
        .value();
    for id in [10, 30, 40] {
        assert_eq!(text(by_id(&after, "/clips", id), "/label"), "red");
    }
    for id in [20, 41] {
        assert_eq!(at(by_id(&after, "/clips", id), "/label"), &Value::Null);
    }
    // The selection's order is not the storage order: the clips stay where
    // they were listed.
    let order = |project: &Value| -> Vec<i64> {
        array(project, "/clips")
            .iter()
            .filter_map(|c| c["id"].as_i64())
            .collect()
    };
    assert_eq!(order(&after), order(&before));
    // A clip named twice is patched once — the same answer as naming it once.
    let twice = project
        .apply(&json!({"op": "set_clip", "clips": [10, 10], "patch": {"label": "red"}}))
        .value();
    assert_eq!(
        twice,
        project
            .apply(&set_clip(10, json!({"label": "red"})))
            .value()
    );
    // One unknown id fails the whole op, before anything is written.
    assert_contains(
        &project.errors(&json!({"op": "set_clip", "clips": [10, 999], "patch": {"label": "red"}})),
        "no clip with id 999",
    );
}

// ---- actions -------------------------------------------------------------

#[test]
fn set_action_end_merges_and_a_null_removes_a_key() {
    let project = general();
    // Clip 10's action 11 ends at {"video": {"scale": 0.6, "x": 520}}.
    let merged = project
        .apply(&json!({"op": "set_action_end", "clip": 10, "action": 11,
                       "patch": {"video": {"opacity": 0.25}}}))
        .value();
    let end = at(&array(by_id(&merged, "/clips", 10), "/actions")[0], "/end");
    assert_eq!(
        end,
        &json!({"video": {"scale": 0.6, "x": 520, "opacity": 0.25}})
    );

    // A key set to null is REMOVED from the patch, which is how the
    // inspector stops animating one property.
    let pruned = project
        .apply(&json!({"op": "set_action_end", "clip": 10, "action": 11,
                       "patch": {"video": {"x": null}}}))
        .value();
    let end = at(&array(by_id(&pruned, "/clips", 10), "/actions")[0], "/end");
    assert_eq!(end, &json!({"video": {"scale": 0.6}}));

    // An unknown key is REFUSED by its path, exactly as a `set_video` patch
    // is (D1·2, kpgalligan/reelcut#3). This case used to assert that the key
    // was kept, for forward compatibility — a project written by a newer
    // build had to survive a round trip. That promise belongs to the FILE
    // reader and is still kept there (`model_tests.rs`'s
    // `an_action_end_patch_keeps_the_keys_it_is_given`, which round-trips
    // this very key); an op is not a file, and a key an agent misspelt here
    // animated nothing and was reported as success.
    assert_eq!(
        project.errors(&json!({"op": "set_action_end", "clip": 10, "action": 11,
                               "patch": {"video": {"from_a_newer_build": 1}}})),
        "unknown key \"video.from_a_newer_build\" in an action end patch",
    );

    assert_contains(
        &project.errors(&json!({"op": "set_action_end", "clip": 10, "action": 11,
                                "patch": [1, 2]})),
        "action end patch must be a json object",
    );
}

#[test]
fn add_action_places_an_empty_patch_inside_the_clip() {
    let project = general();
    let expected_id = int(&project.value(), "/next_id") as u64;
    // Clip 20 is 3 000 000 long and carries no actions yet.
    let after = project
        .apply(&json!({"op": "add_action", "clip": 20, "at": 600000}))
        .value();
    let actions = array(by_id(&after, "/clips", 20), "/actions");
    assert_eq!(actions.len(), 1);
    assert_eq!(int(&actions[0], "/id"), expected_id as i64);
    assert_eq!(int(&actions[0], "/start"), 600_000);
    assert_eq!(
        int(&actions[0], "/duration"),
        SECOND,
        "one second by default"
    );
    assert_eq!(at(&actions[0], "/end"), &json!({}), "empty means no change");
    assert_eq!(text(&actions[0], "/curve"), "linear");

    assert_contains(
        &project.errors(&json!({"op": "add_action", "clip": 20, "at": 0, "duration": 0})),
        "action duration must be positive",
    );
}

// ---- placement -----------------------------------------------------------

#[test]
fn add_clip_places_the_whole_media_and_fits_an_oversized_source() {
    let project = general();
    let expected_id = int(&project.value(), "/next_id") as u64;
    // Media 1 is 1920 × 1080 on a 1920 × 1080 canvas, so Fit does not scale
    // it up or down. It goes on track 5 after clip 20, whose end it meets.
    let same_size = project
        .apply(&json!({"op": "add_clip", "track": 5, "media": 1, "at": 12000000}))
        .value();
    let placed = by_id(&same_size, "/clips", expected_id);
    assert_eq!(int(placed, "/start"), 12_000_000);
    assert_eq!(int(placed, "/duration"), 36_000_000, "the whole media");
    assert_eq!(int(placed, "/source/in"), 0);
    close(
        num(placed, "/video/scale"),
        1.0,
        "a source that already fits is not scaled",
    );

    // A 4K source on a 1080p canvas gets Fit: min(1920/3840, 1080/2160).
    let with_4k = project.apply(&json!({"op": "add_media",
        "descriptor": {"path": "/m/4k.mov", "kind": "video", "duration": 6000000,
                       "width": 3840, "height": 2160, "fps": [30, 1],
                       "has_video": true, "has_audio": false}}));
    let media_id = expected_id;
    let clip_id = media_id + 1;
    let after = with_4k
        .apply(&json!({"op": "add_clip", "track": 5, "media": media_id, "at": 0}))
        .value();
    close(
        num(by_id(&after, "/clips", clip_id), "/video/scale"),
        0.5,
        "the Fit scale",
    );
    // An audio-only media gets no video props, and a silent one no audio.
    let audio_only = project
        .apply(&json!({"op": "add_clip", "track": 4, "media": 2, "at": 12000000}))
        .value();
    let placed = by_id(&audio_only, "/clips", expected_id);
    assert!(
        at(placed, "/video").is_null(),
        "an audio file has nothing to draw"
    );
    assert!(!at(placed, "/audio").is_null());

    // A drag that starts left of zero lands at zero, and an image with no
    // duration of its own gets the five-second default.
    let clamped = project
        .apply(&json!({"op": "add_clip", "track": 5, "media": 3, "at": -600000}))
        .value();
    let placed = by_id(&clamped, "/clips", expected_id);
    assert_eq!(int(placed, "/start"), 0);
    assert_eq!(int(placed, "/duration"), 5 * SECOND);
}

#[test]
fn duplicate_places_the_copies_one_span_later_with_fresh_ids() {
    let project = general();
    let first_new = int(&project.value(), "/next_id") as u64;
    // Clips 30 and 40 span 0 – 7 200 000 on track 6.
    let after = project
        .apply(&json!({"op": "duplicate", "clips": [30, 40]}))
        .value();
    assert_eq!(array(&after, "/clips").len(), 10);
    assert_eq!(placement(&after, first_new), (7_200_000, 3_000_000));
    assert_eq!(
        placement(&after, first_new + 1),
        (7_200_000 + 4_200_000, 3_000_000)
    );
    // The originals are untouched.
    assert_eq!(placement(&after, 30), (0, 3_000_000));
}

/// `add_shape_clip`'s creation preset. The default is the rectangle
/// `ShapeProps::default()` describes, but an arrow inherits nothing useful
/// from a rectangle: with `arrow_end` off it draws as a plain diagonal line,
/// which is not a shape anybody asks for by name. The head therefore belongs
/// to the CREATION preset, not to `ShapeProps::default()` — which is also
/// the base a `set_shape` merges into, where re-painting an unnamed field
/// would be a bug.
#[test]
fn a_new_arrow_is_created_with_its_head_and_a_patch_still_overrides_it() {
    let project = general();

    // Omitted entirely: the default rectangle, both heads off.
    let expected_id = int(&project.value(), "/next_id") as u64;
    let bare = project
        .apply(&json!({"op": "add_shape_clip", "track": 5, "at": 18000000}))
        .value();
    let shape = by_id(&bare, "/clips", expected_id);
    assert_eq!(text(shape, "/shape/kind"), "rectangle");
    assert!(!flag(shape, "/shape/arrow_start"));
    assert!(!flag(shape, "/shape/arrow_end"));

    // Asked for by kind: the head is on, and nothing else about the preset
    // moved.
    let arrow = project
        .apply(&json!({"op": "add_shape_clip", "track": 5, "at": 18000000,
                       "shape": {"kind": "arrow"}}))
        .value();
    let shape = by_id(&arrow, "/clips", expected_id);
    assert_eq!(text(shape, "/shape/kind"), "arrow");
    assert!(
        flag(shape, "/shape/arrow_end"),
        "an arrow with no head is a diagonal line"
    );
    assert!(
        !flag(shape, "/shape/arrow_start"),
        "only the END gets a head by default — a double-headed arrow is asked for"
    );
    assert_eq!(num(shape, "/shape/width"), 320.0, "the default box");

    // The patch is merged OVER the preset, so an explicit refusal wins.
    let headless = project
        .apply(&json!({"op": "add_shape_clip", "track": 5, "at": 18000000,
                       "shape": {"kind": "arrow", "arrow_end": false}}))
        .value();
    let shape = by_id(&headless, "/clips", expected_id);
    assert!(!flag(shape, "/shape/arrow_end"));

    // The preset is chosen by the kind the patch names, not by the kind the
    // clip ends up with by accident: a line stays headless.
    let line = project
        .apply(&json!({"op": "add_shape_clip", "track": 5, "at": 18000000,
                       "shape": {"kind": "line"}}))
        .value();
    assert!(!flag(
        by_id(&line, "/clips", expected_id),
        "/shape/arrow_end"
    ));
}

/// The head is a CREATION preset and nothing else: turning an existing
/// rectangle into an arrow with `set_shape` leaves `arrow_end` exactly where
/// the caller left it, because a patch merges into the clip's own props and
/// must not repaint a field it did not name.
#[test]
fn set_shape_does_not_add_a_head_when_it_changes_the_kind() {
    let project = general();
    // Clip 40 is the fixture's shape clip.
    let changed = project
        .apply(&json!({"op": "set_shape", "clips": [40], "patch": {"kind": "arrow"}}))
        .value();
    let shape = by_id(&changed, "/clips", 40);
    assert_eq!(text(shape, "/shape/kind"), "arrow");
    assert!(
        !flag(shape, "/shape/arrow_end"),
        "set_shape merges; it does not re-preset"
    );
}
