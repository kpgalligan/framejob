# Spec §11 — decisions: Creator jobs, the cursor file onward (road map "creator-jobs", from 2026-11-01)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the series of [`creator-jobs.md`](creator-jobs.md) (CJ-, VR-, TX-, SW- and CU-),
so a citation never has to say which file; that file says what the road map builds and how its
IDs are made (CJ-7). This file is new because `creator-jobs.md` passed the road map's ~500-line
split rule with CU1a's entries (2026-11-01), which moved here; each phase's decisions are
appended here from now on, before its code.

- **CU-10 — Cursor file format v1, owned by `cursor_file.rs` (CU1a; CU-S4 `body=json`).** One UTF-8
  JSON object; `RC_CURSOR_FILE_VERSION` (1) is in the header. The header keys: `format`
  ("framejob-cursor"), `version`, `in_picture`, `source` (`display`, `window`, `picked`),
  `display_id`, `source_frame` (the SCDisplay or SCWindow frame at open, M3's input),
  `point_size`, `pixels_per_point`, `content_size` and `movie_size` (px, 1…16384), `anchor` (`e2`
  or `e1`) and `anchor_host_us`, `cursor_image` (`current-system` or `none`). The columns, every
  time integer µs from the movie's first frame and every position points × 100 in global display
  coordinates: `moves`, `images` (base64 PNG, hot spot, point size, `kind` from a closed list;
  the id is the index), `image_changes`, `hidden` spans, `clicks` (button 0…31, down 0 or 1,
  count ≥ 1), `scrolls` (`dx`/`dy` the event's signed point deltas as delivered, after the
  system's scroll direction, × 100; line deltas not stored), `geometry` (≥ 1 entry, every CU-S2
  candidate's inputs: `screen_rect`, `content_rect`, `content_scale`, `scale_factor`), `dirty`,
  and `keys` (`shortcut` {t, keys, code}, `typed` {t}). `hidden` and `dirty` stay empty until
  CU-S1 and CU-S3 pass; `keys` stays empty until CU6. **Parse order:** a loose read first — not an
  object, then `format`, then `version` (absent, not an integer, below 1 or above 1, "…is version
  N; this Frame Job reads cursor files up to version 1"), then CU-7's `typed` keys — and only
  then the strict `deny_unknown_fields` parse through `serde_path_to_error` and the check, so a
  newer file is refused by its version and a project by its format. The check refuses, each in its own sentence,
  columns of unequal length, an array over its cap (moves, scrolls and dirty 1,728,000 each;
  clicks 200,000; images 1,024; a PNG 1 MiB; image changes 1,000,000; hidden, geometry and
  shortcuts 100,000; typed 1,000,000), a negative time or one going back within a column, an
  empty, overlapping (touching allowed) or out-of-order hidden span, an image id out of range,
  base64 that does not decode or bytes without the PNG signature, a hot spot outside its image,
  images under `cursor_image: none`, a word outside its vocabulary, a float not finite and above
  0, and CU-7's rules: a `typed` entry with any key but `t`, and a shortcut whose `+`-joined
  tokens are empty, hold whitespace, or hold neither `cmd` nor `ctrl`. The core does no file I/O
  and checks a PNG by its signature only.
- **CU-14 — A cursor file that fails to write or read back is that segment's `cursorProblem` and
  the landing's note, never the recording's failure.**
- **CU-15 — One file per segment movie, `<stem>.fjcursor` beside it.** `CursorFileWriter` writes
  `<stem>.fjcursor.partial`, reads it back through `ReelCursor` (the core's `rc_cursor_open`), and
  only then `rename(2)`s it into place, replacing any file there. On a failure both paths are left
  empty and the problem carries the core's sentence.
- **CU-16 — The header's two sizes:** `content_size` (the stream's points × pixels per point) is
  the mapping's; `movie_size` (the written track's, the encoder rounding an odd side up) is
  import's match.
- **CU-17 — `CursorCaptureBuffer`'s rules: a body it writes is always one the core accepts.**
  `openSegment` resets every array and the dedupe state (the last image id, the last geometry) and
  records the start's `geometry` as the latest one before the anchor; a sample fed while closed is
  dropped. `closeSegment(movieSize:anchor:)` (beside `movieSize:` because E2 is answered or
  dropped by then) writes times `round((host − anchor) × 1e6)` µs, positions and scroll deltas
  `round(pt × 100)`. Before the anchor the latest move, image change and geometry are kept at t 0,
  every event is dropped and a hidden span is clipped at 0. Each column is stably sorted by time;
  hidden spans are then clipped, dropped when empty after rounding, and merged when they overlap
  or touch. Images are interned by their PNG bytes; an image change is recorded only when the id
  differs, a geometry entry only when it differs from the last. Under `cursor_image: none` image
  samples are dropped, and `current-system` with no image recorded writes `none`.
  `CursorAnchor.choose(e2:e1:)` picks E2 when given, else E1.
