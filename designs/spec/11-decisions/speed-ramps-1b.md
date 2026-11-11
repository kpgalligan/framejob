# Spec §11 — decisions: Speed ramps, the core target and the render wired in (road map "speed-ramps", #111)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the SR- series of [`speed-ramps.md`](speed-ramps.md), so a citation never has to
say which file; that file names the condensed record and the original, says when each entry was
recorded, and holds what stands beneath every SR- decision. This file holds SR-10…SR-12 (SR2a,
SR2b). The series goes on in [`speed-ramps-2.md`](speed-ramps-2.md), which is why this file is
lettered. It is new because `speed-ramps.md` had passed the spec's ~500-line split rule (#585,
2026-11-11); the entries moved here unchanged, and an "above" or "below" in one may now point into
a sibling file.

- **SR-10 — A clip's rate is an action target: `speed`, a number in an action's `end`; the source
  map S is its integral, and the plan carries a ramped clip as per-frame video segments and ONE
  audio segment holding the map (SR2a).** The road map's A–D, as built.
  - **The target.** `end.speed` is a finite number clamped to ×0.1–×1000 as `set_speed` clamps;
    any other JSON kind is an `Err` (`speed must be a number, not …`), and on a clip that is not a
    media clip an `Err` naming it; `null` removes it; `off` cannot name it (a path is
    `group.key`). Only a `media` clip is RAMPED: one whose actions' ends name a speed. Every other
    clip — no speed end, or a source that is not media — plans, sizes and sounds exactly as
    before, byte for byte.
  - **The rate rule** (§5.4 on one number). A ramped clip's span `[0, D)` splits at 0, D and every
    speed action's start and end clipped to `[0, D)`. In a piece the rate is the merged-ended
    rate (the base `speed`, then each ended action's `end.speed` in start order) — HELD — unless
    the first action spanning the piece names a speed: then it RAMPS, r = r_from + (r_to −
    r_from)·ease(u) over the action's own span. A spanned piece whose two rates are equal is held.
    S(t) = ∫₀ᵗ r, in closed form per curve (∫₀ᵘ ease: u²/2, u³/3, u² − u³/3, u³ − u⁴/2). The
    clip's source length is `round(S(D))` (D4-1's one reader, `content_length_in_source`).
  - **The video.** One segment per held piece, and inside every ramp piece one per canvas frame
    (G = 1: SR1 read 0 wrong frames at every G, and one segment a frame samples S exactly at every
    frame start); segment k reads `in + round(S(t_k))` for `round(S(t_k+1)) − round(S(t_k))`
    (at least 1), clamped into the file as a constant segment is. All of one clip's segments are
    placed as ONE unit on one composition track, so the recipe names one track.
  - **The audio.** One segment over the clip's slot, `pitch` `off`, no SY-24 lead, with a `ramp`
    object: `keep_pitch`, `glide` (the ramp pieces' spans, abutting ones merged, clip ticks; only
    with keep pitch on) and `map` (breakpoints `[clip tick, source tick]` at 0, D, every piece
    edge and every 600 ticks from each ramp piece's start, each source strictly above the one
    before). It is left out when the clip's PEAK rate (the greatest rate at any piece edge of its
    own, unlifted map, the figure `SpeedAudioDrop` reads) is above ×12 (#190). Until SR2b renders
    it the segment is empty time.
    *Amended by SR-19 (SR3b):* the peak is SR-19 (d)'s named figure, `peak_rate`: the base and
    every end rate the clip names, reached inside [0, D) or not, the figure `SpeedAudioDrop`
    reads.
  - **The road map's "Swift lead rule" is moot**: SR1's STOP ruled out GO-UNIFORM-LEAD, and SR-6
    carries ramp audio as one ×1 segment, which takes no lead.
  - **The slot (SR-2, the road map's C).** `set_action_end` refuses an end rate that would read
    past the media's end, naming the largest end rate that fits (floored to 0.001, S being affine
    in one action's end rate) or, when none down to ×0.1 does, the latest clip end that fits at
    ×0.1; `set_action` and `remove_action` on an action whose end names a speed, and a `null`
    removing an end rate, refuse naming the latest clip end that fits.
  - **Format 27**: a ramp in an older build would play at its base rate and lose nothing visible
    on save, so the older build must refuse the file; there is no migration step.
  - **Why:** the action lane already holds a value ramped over a span (SR-1); a closed-form S
    gives every reader one exact answer; per-frame video segments are what SR1 measured clean;
    one audio segment carrying the map is SR-6's mechanism; and keeping every constant clip's
    plan text unchanged means no project without a ramp rebuilds or sounds different.
  - Risk accepted: a long ramp is many video segments (30 a second at 30 fps); until SR2b a
    ramped clip is silent; until SR3 an edit other than the action ops on a ramped clip uses the
    one-rate arithmetic.
  - *Amended by SR-18 (SR3a):* the trims, `roll`, `slip`, every splitter, `freeze_frame` and
    `add_transition`'s handles measure and move a ramped clip's window through S; until SR3b,
    `set_speed`/`rate_stretch` scaling, `detach_audio`, `paste` and the re-snaps keep their
    interim (SR-18 (h)).
  - *Amended by SR-19 (SR3b):* the interim is ended: `set_speed` and `rate_stretch` scale the whole
    profile, and `detach_audio`, `paste`, `paste_attributes`, `relink_media` and the re-snaps
    carry it (SR-19).
- **SR-11 — Keep pitch inside a ramp is a known limit until SR1d: the held spans keep pitch, the
  ramp spans glide like tape.** The owner's SR1c answer ("SR2 now, fix after").
  - The whole clip is rendered as ONE file. With keep pitch on, SR-8's arm renders the held
    spans and the keep-pitch-off arm each `glide` span, joined by a linear crossfade of 480
    output frames (10 ms) — or half the held span when that is shorter — lying in the held span.
    The pitch steps by 1200·log₂ r cents at each join, r the rate there.
  - **Why:** SR1c's arm ON stopped on dropouts while the pitch moves, a placement count, an
    anchor and a lag; the held rates are what SR-8 rendered cleanly at constant rates, and the
    glide is what SR1b measured exact.
  - Risk accepted: a pitch step at each ramp edge with keep pitch on; SR1d lifts it.
  - *Lifted by SR-13 and SR-15 (SR1d):* keep pitch on renders the whole map through SR-13's
    rate-mode arm, ramps and held spans alike; the `glide` spans shape nothing, the crossfade and
    `RampAudioRenderer+Hybrid.swift` are gone, and there is no pitch step at a ramp's edge.
- **SR-12 — The render wired in (SR2b): a ramped clip's audio is rendered off the main thread,
  one file per plan ramp segment, played as one ×1 segment at the clip's start, silent while
  pending, and waited for by every export.**
  - **(a) The file.** One per plan ramp SEGMENT, named `cache/ramp-audio/<media>-<16 hex>.caf`,
    the hex FNV-1a 64 (`ReverseCache.digest`'s) over `<path>|<size>|<mtime second>|v<version>|
    r<0|1>|k<0|1>|g<glide pairs>|m<map pairs>`, path, size and modification second the MEDIA
    file's (never `AudioRateCopy`'s copy, never the reversed file), `r` the clip's reversal, `k`
    its Keep pitch; so two instances of one nest clip with different cuts are two files. The
    builder looks a segment's render up by `RampSegmentKey` (clip, Keep pitch, glide, map), never
    by its start.
  - **(b) Ready or pending.** The document publishes `cache/ramp-audio/` beside the plan as
    `ReverseResolution.rampAudio`, captured and pinned with it by the export queue. A ramp segment
    is READY iff its file exists when the composition is built; otherwise it is empty time and
    its picture plays.
  - **(c) Who wants a render.** Renders run one at a time on one serial `.utility` queue, wanted
    by owners: a document (its `recipeKey`) wants its whole-timeline plan's ramp segments and,
    with a nest open, the edited plan's; an export (its own key) wants its plan's while it
    writes. None is wanted during a live gesture. A queued render no owner wants is dropped, a
    running one cancelled.
  - **(d) The source.** The media file, or `AudioRateCopy`'s 48 kHz copy where it `needsCopy`; for
    a reversed clip its ready reversed file. A clip whose reverse is pending, or whose media is
    missing, is empty time as its picture is slated, and an export does not wait for it.
  - **(e) Landing.** The renderer writes `<name>.landing`, renamed to `<name>` inside
    `MediaImporter.CacheLedger.shared.publish(in: cache, for: nil)`, so never during a save. A
    refused publish removes it and puts the render straight back at the queue's end while any
    owner still wants that name, so a waiting export and the document's want finish with no
    further edit; it is not a failure.
    *Amended by #553:* the renderer writes `<name>.landing` OUTSIDE the package, in a folder of
    its own (`RenderLanding`: the system's item-replacement folder for the package's volume,
    else one under the temporary directory), and the one `publish` both makes
    `cache/<folder>/` and moves the file in (a rename; across volumes a copy beside the name,
    then a rename). So a render writes nothing into the package outside the ledger, for all four
    offline jobs (a ramp, an isolation, its mix, a voice effect). **Why:** a file written into
    the package between a save's listing and its swap goes with the old package (#429), and the
    folder made before the dev hold and the landing file written during the render were both
    such writes: a save that met either failed the render for the launch ((g)), "the CAF could
    not be created" or "could not be moved into place", and every later export of that clip
    with it. A retry would repeat a render that can take minutes and still write outside the
    ledger. Row: `save_hold_proof.py` R1, a render held into a held save, with the mutants
    `landing-in-package` and `folder-before-publish` (an expected survivor).
  - **(f) After a landing** the document calls `packageContentsDidChangeOnDisk()`, prunes every
    file in the folder whose name no owner wants and no in-flight render's name prefixes, and
    posts `.reversedMediaDidChange`, so the editor rebuilds. An undone ramp is rendered again.
  - **(g) A failure** is not retried for that name in the launch (one `NSLog` line, never the
    parity prefix): playback stays silent there, and an export fails `rampAudioFailed`, naming
    the clip.
  - **(h) The export waits**, before its build, for every renderable ramp segment of its plan
    (an image sequence does not wait), reading "Preparing…"; a ramp segment with no cache folder
    to render into fails it.
  - **(i) Keep pitch on with glide spans** renders SR-11's mix: SR-6's off arm over the whole map,
    each held span alone by SR-8's arm on its own two-point map, joined by the crossfade, the
    temporaries streamed and removed; `RampAudioRenderer.version` 3.
    *Amended by SR-15 (SR1d):* keep pitch on renders the whole map through SR-13's arm whatever its
    `glide` spans, with no mix and no temporaries; `RampAudioRenderer.version` 4. The key still
    names `g<glide pairs>`.
  - **(j) The dev hold.** `-RCDevRampRenderHold <s>` (dev tools only) holds each render s seconds,
    polling cancellation, so a proof sees the wait.
  - **Why:** a file per segment keyed by everything that shapes it is reusable and
    self-invalidating as the reversed clip's is; owners make "nothing wants it" a fact the queue
    can act on, so an edit storm costs at most the one render in flight; a ready-iff-exists rule
    needs no second state to keep in step with the disk; and an export that waits never writes a
    silent ramp.
  - Risk accepted: every edit of a map renders the whole clip again (no partial re-render), one at
    a time, and an undone map's file is not kept; a failure stays failed until relaunch.
