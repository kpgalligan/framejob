# Spec §11 — decisions: Speed ramps (road map "speed-ramps", #111)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The road map that makes these is open: `designs/speed-ramps.md` holds each phase's record (SR1
the spike and these decisions; SR2 the core target and the plan; SR3 edits on a ramped clip; SR4
Swift's mappers; SR5 the UI and the close). SR-1…SR-3 were recorded in SR1, before any product
code, from the owner's decisions of 2026-10-23 on issue #111 (asked and answered in the session
that opened the road map, quoted in its "The owner's choices"); SR-4 is the working arrangement
the owner set that day; SR-5, the spike's rule, was recorded before the spike's measured run,
whose `results.json` pins this file's SHA-256 as `rule_sha256`. SR-6, the mechanism the owner
chose on SR1's STOP (2026-10-23), and SR-7, the second spike's rule, were recorded in SR1b before
its code and its measured run, whose `results.json` pins this file's SHA-256 again. SR-8, the
Keep pitch mechanism the owner chose on SR1b's SPLIT (2026-10-23), and SR-9, the third spike's
rule, were recorded in SR1c before its code and its measured run, whose `results.json` pins this
file's SHA-256 again. SR2 is split in two: SR2a (the core — `speed` as an action target, the
source map, the plan's ramped segments, C's refusals, format 27) recorded SR-10, SR-11 and SR-6's
Amended-by lines before its code; SR2b (the renderer wired into the composition and the export)
builds what those lines say Swift does, and recorded SR-12 and SR-6's third Amended-by line
before its code. SR-13, the Keep pitch mechanism the owner chose on SR1d's diagnostic STOP
(2026-10-23), SR-14, the fourth spike's rule, and the Amended-by lines on SR-6's keep-pitch arm
and on SR-8 were recorded in SR1d before its code and its measured run, whose `results.json` pins
this file's SHA-256 again. SR-15, the owner's acceptance of that run's STOP (2026-10-23), with
SR-11's lifted-by line and SR-12 (i)'s Amended-by line, was recorded after the run and before the
product switch it allows. SR-16, SR1e closed as measured on the owner's answer to its diagnostic
STOP (2026-10-23), with SR-15's Amended-by line, and SR-17, the instrument rule that trims a
corrected playback tap rather than zero-padding it, with SR-7's PT1 Amended-by line, were
recorded in SR1e before its instrument code; SR1e has no measured run, so nothing pins this
file's SHA-256 again. Later phases record their rules as new entries (SR-18 on) or as Amended-by
lines before their code.

**Stands, and nothing here re-litigates it:** SY-24 (the varispeed lead: a time-scaled segment
on an `off` track reads its source 575 ticks earlier; ×1 untouched); SY-26 (one pitch name per
plan audio track); SY-27 (the export's tolerance, |median| ≤ 1.0 ms and spread ≤ 0.5 ms); SY-39
(keep pitch within ±0.1 % of ×1 plays `off`); SY-40 (the time-pitch survey: `spectral` drifts);
SY-41 (keep pitch outside the band stays on Apple's time-pitch, no own time-stretch, #299 open);
D4-1 (a clip's content length is one function, and the plan obeys it); D4-3 (`set_speed` snaps
nearest and is held to the bound at the new rate); #190 (a speed runs ×0.1–×1000, above ×12 the
plan leaves the audio out, one pitch per plan audio track).

- **SR-1 — A speed ramp is a Speed ACTION on the existing action lane.** The owner's decision 1
  (2026-10-23), verbatim in the road map: speed becomes an action target, like zoom or opacity;
  an action ramps from the rate in force to its end rate over its span along its curve and
  holds after (spec §5.4's evaluation rule). It reuses the action inspector, band drags and
  `add_action` / `set_action` (the MCP mirror).
  - **Why:** the lane already carries a value that changes over a span along a curve, with its
    inspector, its drags, its undo and its tools; a rate is one more such value, and a second
    mechanism (keyframes, a rate graph) would duplicate all of it.
  - Risk accepted: a rate is not a property drawn at one instant — it is integrated into the
    source the clip reads — so every reader of a clip's source window must learn the map
    (the road map's B, K, N), and a ramp's look on the lane is a band, not a graph.
- **SR-2 — The clip keeps its slot: a ramp never changes the clip's timeline length; it changes
  how much SOURCE the clip plays, and an edit whose ramp would read past the media's end is
  REFUSED, naming the rate or the end that fits.** The owner's decision 2.
  - The source out point moves (`in + S(duration)`); later clips and the clip's other actions
    stay put. The refusal is the crate's own sentence, naming the largest end rate that fits or
    the latest clip end that fits (the road map's C).
  - **Why:** a ramp that rippled the timeline would move everything after it on every drag of
    its band; a ramp edit that silently clamped would answer a different ramp than the one asked.
  - Risk accepted: a fast ramp near the media's end is refused rather than shortened, and the
    person or agent must pick the rate the refusal names.
- **SR-3 — Audio follows the clip under the clip's own Keep pitch: off, the pitch glides like
  tape (varispeed); on, Apple's time-pitch as `set_speed` uses now; no own time-stretch.** The
  owner's decision 3, under SY-41.
  - Sample agreement between playback, export and expectation is claimed for keep pitch off;
    keep pitch on is measured against constant-rate controls at the ramp's end rates, and its
    own drift stays SY-40's and SY-41's (#299 open).
  - **Why:** a ramp is many constant-rate segments (`scaleTimeRange` is piecewise-constant), and
    each already plays under the clip's pitch mode; a time-stretch of Frame Job's own is #299's,
    not this road map's.
  - Risk accepted: whether many abutting segments click, drop out or misplace audio is unknown
    until SR-5's spike has measured it; the road map stops for the owner if it does.
- **SR-4 — The working arrangement: the `framejob-ramps` worktree, each phase gated, committed
  and merged into main alone.** The owner's ask of 2026-10-23.
  - The worktree is `~/devel/framejob-ramps` on branch `speed-ramps`, from `81900d9`; each phase
    passes `make gate`, is committed and is merged into main alone, with main's next numbers if
    main moved.
  - Fixtures are synthetic; the owner's `tools/proof/media/owner-sync*` and `filler-sample/` are
    never read for this road map, never committed and never copied out. Every proof runs under
    `env -u RC_ASSEMBLYAI_KEY`, and none runs `--live` (AssemblyAI or Anthropic).
  - Agents edit no `CLAUDE.md`; each phase's handback lists the edits owed.
  - Risk accepted: no owner recording is measured with a ramp; whether a ramp sounds right and
    looks smooth is a person's check (`docs/manual-checks.md`, SR5).
- **SR-5 — The spike's rule (SR1), fixed before its run: what a click, a dropout, a misplaced
  sample and a misplaced frame are, and the verdict that decides whether SR2 starts.**
  `tools/proof/ramp_spike/` measures a ramp's plan written today as abutting constant-rate
  media clips (segment k reads `in_k = in + round(S(t_k))`, `speed_k = (in_k+1 − in_k) /
  (t_k+1 − t_k)`, boundaries every G frames inside the ramp, G ∈ {1, 4, 15}), through the app's
  own `CompositionBuilder`, `Exporter` and editor player, on synthetic 20 s ProRes fixtures (a
  click train and a 220 Hz sine, each frame showing its index in 10 bars), against constant-rate
  controls and a planted fault (F1: every segment from 2 s reading 2 400 ticks later).
  - **Placement.** A click at source c is expected at the inverse of the WRITTEN segments,
    `t_j + (c − in_j)/speed_j` (F1 is judged against V1-G1's segments, the ramp it was meant to
    be); clicks within 2 ms of the clip's edges are skipped. Each is located by
    `export_offset_proof.locate`'s method with the template's width ÷ the local rate when keep
    pitch is off, reach = min(60 ms, 0.4 × the least expected spacing). **Varispeed placement**:
    ≥ 90 % found, |median| ≤ 1.0 ms, spread ≤ 0.5 ms (SY-27). **Keep-pitch placement**: found ≥
    (the lower of its two end-rate controls' found fraction) − 0.10, and max |diff| ≤ (the
    greater of their max |diff|) + 5.0 ms.
  - **Click** (the sine, channel 0). For each segment boundary b ≥ 5 ms inside the clip, D = max
    |x[n] − 2x[n−1] + x[n−2]| over ±2 ms of b; L = the median of that statistic over 4 ms windows
    centred every 2 ms within ±100 ms of b whose centres are ≥ 5 ms from every boundary; it
    clicks when D > 4·L. With keep pitch ON (the K variants and `C-on-*`), D is taken over
    [b − 2 ms − W, b + 2 ms + W], W = the greater of its two end-rate controls' max |diff| on the
    click fixture + 5.0 ms, and the threshold is max(4·L_c, D_c): L_c the median 4 ms statistic
    over both end-rate controls' sine output (the clip less 50 ms each end), D_c the greatest D
    the same window finds at fake boundaries every 33.3 ms in those controls. A `C-on-*` control
    is its own end-rate control. A control (one clip, no boundary of its own) is judged at fake
    boundaries every 33.3 ms.
  - **Dropout** (the sine, the clip less 50 ms each end), either of: (a) the RMS over one local
    output period — 1/(220·r) s with keep pitch off, r the written speed at the window's centre;
    1/220 s with it on — is < 0.7 × the median of that statistic within ±50 ms; (b) a run of ≥ 48
    consecutive samples (1 ms at 48 kHz) with every |x| < 0.02.
  - **Video.** Timeline frame k decodes to ⌊s_k ÷ 20 000⌋, s_k the source under T = k·20 000 by
    the written segments; a frame whose s_k is within 2 ticks of a multiple of 20 000 may read
    either neighbour.
  - **Agreement.** Playback minus export click times: |median| ≤ 1.0 ms and spread ≤ 0.5 ms with
    keep pitch off, max |diff| ≤ 5.0 ms with it on. Playback is read by a PostEffects
    `MTAudioProcessingTap` on the editor's own item, each buffer placed at its source-audio time
    (PT0: `C-off-x2`'s tap must meet the varispeed placement, else every playback audio row is
    unmeasured and the frames are still scored).
  - Reported, not scored: the ideal-map error (max |written − continuous-S inverse| over the
    clicks, ms) per variant, and the keep-pitch controls' own rows.
  - **Instrument checks** (the run fails, exit 1, rather than judge): the fixtures read back
    (every frame's bars decode to its index, every click within 0.05 ms, no click at fake
    boundaries on the sine); every `C-off-*` passes varispeed placement, click and dropout in
    export; F1 clicks at its 2 s boundary and at no other, and fails varispeed placement; PT0's
    tap was called.
  - **The verdict.** GO: every V and K variant at G1 (V1 ×1→×2 linear, V2 ×2→×0.5 ease in-out,
    V3 ×0.25→×4 ease in, all keep pitch off; K1 ×1.1→×2 linear, K2 ×0.9→×0.5 ease out, keep
    pitch on) passes placement, click, dropout and video in export and, where PT0 passed, in
    playback, plus agreement. GO-UNIFORM-LEAD: GO but for V1-G1 failing only at its 1 s boundary
    (its ×1 head, which SY-24 gives no lead, meeting the first time-scaled segment) while V1L
    (V1-G1 with its head time-scaled by one tick, so it takes the lead) passes everything V1-G1
    failed. GO-EXPORT-ONLY: GO's export half holds and PT0 failed. STOP: anything else, naming
    each failing variant and rule. Only GO and GO-UNIFORM-LEAD let SR2 start.
  - **Why:** the owner's decision 3 asked for the measurement before any product code, and a
    rule written after the numbers would be fitted to them; the controls and the planted fault
    show the instrument can see a click, a dropout and a misplacement and does not see one in
    clean constant-rate output.
  - Risk accepted: the fixtures are synthetic (a click train and one sine), so a real voice's
    artifacts at a boundary are a person's check (SR5); playback is measured at the tap, not at
    the speaker, so device latency stays SY-27's unmeasured part.
- **SR-6 — A ramped clip's audio is rendered offline by Swift into a cached file, and the
  composition carries it as ONE ×1 segment over the clip's slot: no rate boundary inside the
  clip and no SY-24 lead.** The owner's answer to SR1's STOP (2026-10-23, "Render it
  ourselves"), quoted in the road map; it amends the road map's D and E, and SR-3 stands.
  - **Where it lives.** In the package's `cache/ramp-audio/` (§5.6, beside `cache/reversed/`):
    regenerable, never required to open. Swift resolves the file as `ReverseResolution` resolves
    a reversed clip (`ReverseCache.swift`). Its key is the MEDIA file's (path, size, modification
    second) as `ReverseCache.digest` keys it — never the file the renderer reads, which may be
    `AudioRateCopy`'s temporary copy — plus the map, Keep pitch and `RampAudioRenderer.version`.
    What plays while a render is pending, and the plan's form for the rendered audio, are SR2's,
    recorded here as Amended-by lines before SR2's code.
    *Amended by SR2a:* the plan names no file — a ramped clip's one audio segment carries its map
    (`ramp.map`, SR-10). Swift resolves the render per clip beside the plan as `ReverseResolution`
    resolves a reversed asset (ready or pending, published and pinned with the plan), as
    `cache/ramp-audio/<media>-<digest>.caf`, the digest over the media file's (path, size,
    modification second), `RampAudioRenderer.version`, Keep pitch, the `glide` spans and the map.
    *Amended by SR2a:* while a clip's render is pending its audio is empty time (silent) and its
    picture plays; an export waits for every pending render and never writes a placeholder.
    *Amended by SR2b:* the key also carries whether the clip is reversed — a forward and a
    reversed clip with one map are two files (SR-12), the reversed one rendered from the clip's
    reversed file.
  - **The renderer** (`RampAudioRenderer`, `app/Sources/`) takes the source file, Keep pitch and
    the clip's map: breakpoints of clip ticks → source ticks (media time in the direction the
    clip plays), linear between them, sampled by the caller (SR2: the core). It reads only a
    48 kHz source with no MP3 trim and throws `unreadable` for one that fails
    `AudioRateCopy.needsCopy(CompositionBuilder.audioFormatSignature(of:),
    trim: MP3Gapless.leadingTrim(of:track:))`, so the caller hands it `AudioRateCopy`'s copy
    where one is needed. It streams the source in chunks and drops what is behind the kernel's
    reach, never holding the clip's whole window (memory is relative to RAM). Its output is
    32-bit float LPCM CAF at 48 kHz with the source's channels clamped to 1…2,
    round(duration × 48 000 / 600 000) frames, written as `<destination>.partial` and renamed.
  - **Keep pitch off: a variable-rate band-limited interpolator, a true tape glide.** Output
    frame n is at clip tick 12.5·n; p(n) = map(12.5·n) / 12.5 source frames, linear between
    breakpoints; the local rate r(n) = p(n+1) − p(n). y(n) = Σₖ x[k]·fc·sinc(fc·(p − k))·
    kaiser((p − k)·fc / Z, β) over |p − k| ≤ Z / fc, fc = min(1, 1/r(n)), Z = 32 zero
    crossings, β = 9, read from a table of 512 phases per crossing with linear interpolation
    between phases; a position before the file's frame 0 or past its end reads zero.
  - **Why that kernel:** a windowed sinc whose cutoff follows the local rate is the standard
    band-limited resampler — it anti-aliases as the ramp speeds up (fc < 1) and interpolates
    without imaging as it slows; Kaiser β = 9 puts the stop band near −90 dB, under the 16-bit
    export's own floor; 32 crossings keep the transition band narrow; and the table's exact
    zeros make it the identity at ×1 on integer positions, so a constant ×1 render is the
    source's own samples. A polynomial interpolator (cubic, Lagrange) was not taken: it aliases on
    a speed-up, and its error on a sine at ×4 is well above that floor.
  - **Keep pitch on: Apple's time-pitch unit, driven offline.** `AVAudioSourceNode` →
    `AVAudioUnitTimePitch` (pitch 0, the default overlap) → the main mixer, in `AVAudioEngine`'s
    offline manual rendering mode (at most 4 096 frames a call). The source is fed sequentially
    from p(0) − P, P = 4 800 frames always, a position before frame 0 read as zero, so a clip at
    source 0 runs the same path. Before each 256-frame `renderOffline` the unit's rate is
    (p(n+256) − p(n)) / 256 clamped to 1/32…32, n counted from output frame round(P / r(0)) (p
    extended before 0 at r(0) and past the end at the last breakpoint's slope), and the first
    round(P / r(0)) + the unit's reported latency output frames are discarded. Still Apple's
    algorithm (SY-41: no own time-stretch).
    *Amended by SR-8 (SR1c):* keep pitch on is three stages — the keep-pitch-off interpolator at
    48 kHz × K, the time-pitch unit held at ×1 shifting the pitch by −1200·log₂(rate) cents, and a
    fixed decimation by K — with the delay D_K discarded; the rate-driven unit above is replaced.
    *Amended by SR-13 (SR1d):* SR-8's three stages are withdrawn and the rate-driven unit above is
    restored, its rate read at n + L rather than at n (L = `rateLeadFrames`, the lead SR-14's
    sweep measures); held spans render through it too.
  - **Why:** SR1 measured that abutting time-scaled segments click and misplace audio in export
    and in playback (V1-G1 30 of 61 boundaries clicking in export, a 1.4 ms placement spread);
    a rendered file has no rate boundary, so the composition plays one ×1 segment, the case
    SR1's ×1 control showed clean in export. A pre-rendered file in the package's `cache/` is the
    reversed clip's precedent.
  - Risk accepted: a ramp's sound waits for a render after every edit of its map (SR1b measures
    the cost; a partial re-render is not built); the cache holds 192 000 bytes per second of mono
    audio (384 000 stereo) per rendered map; keep pitch on inherits Apple's unit's own drift and
    latency, measured against constant-rate controls rather than claimed sample-exact.
- **SR-7 — The second spike's rule (SR1b), fixed before its run: rendered ramp audio, carried as
  one ×1 segment, judged against the ideal map, with a verdict per Keep pitch arm.**
  `tools/proof/ramp_spike/render_spike.py` renders each variant's audio through
  `RampAudioRenderer` (SR-6; the probe's `render` group, built `-O`), writes it into a project
  as one ×1 audio clip, and reads that project through the app's own `CompositionBuilder`,
  `Exporter` and editor player as SR-5's instrument does (export `audio_wav` and `prores_422`;
  playback the tap and the frames).
  - **Variants**, on SR-5's fixtures from source `in` 1 s. Rendered ramps RV1, RV2, RV3 (keep
    pitch off) and RK1, RK2 (on): SR-5's V1–V3 and K1–K2 ramps. RF1, the planted fault: RV1 with
    every map breakpoint from 2 s reading 2 400 ticks later, judged against RV1's map. Rendered
    constant controls RC-off-x0.25, -x0.5, -x1, -x2, -x4 and RC-on-x0.5, -x0.9, -x1.1, -x2, at
    SR-5's control lengths (6 s; ×4 4 s). SR-5's composition controls C-off-* and C-on-*,
    unchanged (one media clip at the rate). RV1-edit (RV1 ending ×2.5) is rendered only. A
    rendered variant's map has breakpoints every 600 ticks reading `in + S(t)` in closed form; its
    project (format 26) holds the fixture's video as SR-5's G1 segments (a control: one segment)
    with `enabled.audio` false and, on a second track, one ×1 media clip `[0, length)` of the
    rendered CAF (media `kind` `audio`). Playback reads the frames of RV1–RV3, RK1, RK2 and every
    RC-off control.
  - **Placement**, against the ideal map: a click at source c is expected at t = S⁻¹(c − in),
    clicks within 2 ms of the clip's edges skipped, located by SR-5's method (reach min(60 ms,
    0.4 × the least expected spacing)) with the template's width ÷ S′(t) when keep pitch is off
    and unscaled when it is on. **Off**: ≥ 90 % found, |median| ≤ 1.0 ms, spread ≤ 0.5 ms
    (SY-27). **On, a ramp**: found ≥ (the lower of its two RC-on end-rate controls' found
    fraction; RK1's are RC-on-x1.1 and -x2, RK2's -x0.9 and -x0.5) − 0.10, and max |diff| ≤ (the
    greater of their max |diff|) + 5.0 ms. **On, an RC-on-x control (the anchor)**: found ≥
    C-on-x's (the same rate's composition control) − 0.10 and max |diff| ≤ C-on-x's + 5.0 ms, in
    the same run and the same output (export or playback), so a renderer-wide offset fails
    rather than widening the ramps' tolerance. A C-* control's ideal map is its one segment.
  - **Click** (the sine, channel 0), dense: centres every 2 ms over the clip less 50 ms each end;
    D(c) = max |x[n] − 2x[n−1] + x[n−2]| over c ± 2 ms; L(c) = the median D over the centres
    within ±100 ms of c. Keep pitch off, c clicks when D(c) > 4·L(c); keep pitch on, when D(c) >
    max(4·L(c), D_c), D_c the greatest D the same scan finds over its two RC-on end-rate
    controls' sine output in the same output (an RC-on or C-on control is its own: reported).
    Clicking centres within 10 ms of the one before merge into one event, placed at its greatest
    D. The same scan judges every variant, the C-* controls included.
  - **Dropout** (the sine): SR-5's (a) and (b), the local output period 1/(220·S′(t)) s with
    keep pitch off and 1/220 s with it on. **Video**: SR-5's rule, on the written video
    segments.
  - **PT1**, the ×1 tap offset (#335): RC-off-x1's playback tap must find ≥ 90 % of its clicks
    with a spread ≤ 0.5 ms; m1 = its playback median − its export median, and every rendered
    variant's playback click times are taken − m1 (its playback sine moved by m1 rounded to a
    sample). When PT1 fails, every rendered variant's playback audio row is unmeasured; the
    frames are still scored.
    *Amended by SR-17 (SR1e):* "its playback sine moved by m1 rounded to a sample" now trims, not
    pads: the head (k < 0) or tail (k > 0) a whole-sample correction would zero-fill is cut off,
    and every rule reads the samples left as the signal's extent.
  - **Agreement**, every rendered variant, both arms (one rendered file plays in both outputs):
    corrected playback minus export click times, |median| ≤ 1.0 ms and spread ≤ 0.5 ms. The C-*
    controls' agreement is SR-5's, reported.
  - **Instrument checks** (the run exits 1 and judges nothing): Z0 (SR-5's); every render
    answered; R44, a 44.1 kHz WAV the runner writes, answers `ok: false` with an `unreadable`
    error (whenever the `render` group runs); RC-off-x1's render equals the fixture's samples over
    `[in, in + length)` within 1e-6 on both fixtures; every C-off-* passes placement and dropout in
    export, and the click rule but for C-off-x4, whose export steps are #334 (reported, never a
    failure); RF1 in export has exactly one click event, within ±5 ms of 2.000 s, and fails off
    placement; PT1's tap was called.
  - **The verdict**, per arm. Arm OFF: RV1, RV2, RV3 and RC-off-*. Arm ON: RK1, RK2, and each
    RC-on-x's anchor placement (export and playback). An arm is GO when each of its ramps and
    RC-off controls passes placement, click, dropout and video in export and in playback, plus
    agreement, and (ON) every anchor passes; a rule not measured fails. `VERDICT: GO` (both
    arms), `VERDICT: SPLIT — off GO, on STOP — …` or `VERDICT: SPLIT — off STOP, on GO — …`, or
    `VERDICT: STOP — …`, naming each failing variant and rule. SR2 starts with the renderer for a
    GO arm only.
  - Reported, not scored: render wall seconds per audio second, bytes per audio second, the
    probe's peak RSS, the time-pitch unit's latency and pulled − map frames (on); RV1-edit's
    render time and how many of its leading samples equal RV1's; the export WAV against the
    render, max |diff| at offset 0; SR-5's C-on and C-off rows; PT0 (C-off-x2's tap); C-off-x1's
    raw tap reading (#335); the RC-on rows but for their anchor placement.
  - **Why:** the owner chose the renderer on SR1's measurement, and this rule reads it through
    the instrument SR-5 validated, against the continuous map the product will ask for rather
    than written segments. SR1's two failed checks are answered: F1 is re-pinned on a rendered
    ramp, where its planted fault must be the only click, and C-off-x4's steps (#334) stay outside
    the ramp verdict. The dense scan replaces SR-5's boundary windows because a rendered file has
    no boundary to look at.
  - Risk accepted: the fixtures are synthetic, so whether a ramp sounds right is a person's check
    (SR5); the ×1 tap offset is corrected by its own control rather than explained (#335); keep
    pitch on is measured against controls rendered by the same unit, anchored to the
    composition's constant-rate `spectral` controls.
- **SR-8 — Keep pitch on is resample, then pitch-shift: the keep-pitch-off glide sets the timing
  at 48 kHz × K, Apple's time-pitch unit held at ×1 shifts the pitch back, and a fixed decimation
  by K returns 48 kHz.** The owner's answer to SR1b's SPLIT (2026-10-23, "Resample, then
  pitch-shift"), quoted in the road map; it replaces SR-6's keep-pitch arm (its Amended-by line),
  and SR-6's keep-pitch-off arm, the file, the cache and SR-3 stand.
  - **K**, the oversampling: `oversampling(map)` = min(4, max(1, ⌈the map's steepest slope −
    1e−9⌉)), so every stage below runs at 48 kHz × K (48–192 kHz).
  - **Stage 1** is SR-6's keep-pitch-off interpolator on the same map at 48 kHz × K: stage-1
    frame j is the kernel at p(j / K) (p in 48 kHz source frames, the map read at clip tick
    12.5 · j / K) with the rate p((j+1)/K) − p(j/K), from j = −P·K, P = 4 800 output frames
    (100 ms); the map extrapolates before 0 at its first slope and a file frame before 0 reads
    zero. Below ×K the cutoff stays at the source's 24 kHz. The source reader opens at the first
    4 096-frame chunk's reach, `chunk(map, from: −P·K, count: 4096, per: K).lo`, so the
    pre-roll reads the file, not zeros.
  - **Stage 2**: `AVAudioSourceNode` (stage 1) → `AVAudioUnitTimePitch` (rate 1, the default
    overlap) → the main mixer, in `AVAudioEngine`'s offline manual rendering at 48 kHz × K, at
    most 4 096 frames a call. Before each 256-frame `renderOffline` producing stage-2 frames
    s … s + 255: k = s − P·K − D_K, r = K · (p((k + 256)/K) − p(k/K)) / 256, and the unit's
    `pitch` = clamp(−1200·log₂ r, −2400 … 2400) cents.
  - **Discard**: kept stage-2 frame i is stage-2 frame i + P·K + D_K. D_K
    (`timePitchDelayFrames[K − 1]`, stage-2 frames) is the unit's own delay at ×1, measured by
    SR1c's render-only run as max(0, round(the median, over that K's constant RC-on renders, of
    each render's signed median click offset in ms × 48·K)), 0 where every such median is within
    0.1 ms; the unit's reported latency is reported only. A constant is sound because the unit's
    rate never changes.
  - **Stage 3** (K > 1): output frame m is SR-6's kernel at rate K at kept position K·m — a fixed
    decimation, cut at 24 kHz — the pre-roll supplying the kept frames before 0. K = 1 has no
    stage 3: output frame m is kept frame m.
  - **Past ×0.25–×4 the excess glides like tape**: the owner's tape-glide option, applied
    continuously from the bound so there is no jump. The command is clamped at ±2400 cents, so
    timing stays exact and the pitch moves by 1200·log₂(r/4) cents above ×4 and 1200·log₂(r/0.25)
    below ×0.25. Nothing is refused.
  - **Why:** the unit's rate never changes, so it cannot drift as SR1b's rate-driven unit did
    (RK1 about +21 ms late, RK2 about −46 ms early); the timing is the glide SR1b measured exact.
    Oversampling keeps a speed-up's band to 24 kHz up to ×4 — at 48 kHz everything above
    24 kHz / r would be lost (12 kHz at ×2, 6 kHz at ×4) — and the decimation is SR-6's own
    kernel. Still Apple's algorithm (SY-41: no own time-stretch).
  - **Cost:** stage 1 about 64·K kernel taps per output frame per channel, stage 2 K times the
    48 kHz unit's work, stage 3 64·K taps; measured in SR1c's RS rows.
  - Risk accepted: the pitch command may lag the content (SR1c's LG rows; not compensated);
    past ×4 the band above 24 kHz · 4 / r is lost and the pitch rises by the excess; the unit at
    96–192 kHz is proven only by SR1c's run.
  - *Amended by SR-13 (SR1d):* superseded whole. Stage 2's pitch mode drops out once each time a
    gliding partial crosses one of the unit's analysis bins (SR1d's diagnostic), which no setting
    of the unit removes, and rate mode makes stages 1 and 3 moot; the ±2400-cent clamp, the tape
    excess past ×0.25–×4, K and D_K go with it.
- **SR-9 — The third spike's rule (SR1c), fixed before its run: SR-7's arm ON re-run on the SR-8
  renderer, plus the rendered pitch, with a verdict for arm ON alone.**
  `tools/proof/ramp_spike/render_spike.py --verdict on` with `--variants RK1,RK2,RC-on-x0.5,
  RC-on-x0.9,RC-on-x1.1,RC-on-x2,C-on-x0.5,C-on-x0.9,C-on-x1.1,C-on-x2,RC-off-x1,RC-on-x1,
  RC-on-x3,RC-on-x6,RC-on-x0.2,RB-on-x2`, every group, through SR-7's instrument.
  - **Variants.** SR-7's RK1, RK2, RC-on-x0.5…x2, C-on-x0.5…x2 and RC-off-x1 (PT1), unchanged.
    Rendered only, both fixtures, never staged into a project: RC-on-x1 (×1, 6 s), RC-on-x3 (×3,
    4 s), RC-on-x6 (×6, 2 s), RC-on-x0.2 (×0.2, 6 s), keep pitch on. RB-on-x2 (×2, 6 s, keep pitch
    on), rendered only, from `band.wav`, a 20 s 48 kHz mono 15 kHz sine at amplitude 0.5 the
    runner writes.
  - **Scoring**: SR-7's arm ON rule unchanged — RK1 and RK2 against their RC-on end-rate
    controls (placement, click, dropout, video, in export and in playback, plus agreement), each
    RC-on anchor against its C-on control in export and in playback — **plus pitch**, read from
    the sine render's channel 0: each RC-on anchor's, RK1's and RK2's PR |median cents| ≤ 25, and
    RK1's and RK2's LG RMS cents at the best τ ≤ 25. A rule not measured fails. A failure names
    the variant and `pitch` or `pitch lag`.
  - **The pitch reading (PR)**: 40 ms windows every 10 ms over the clip less 50 ms each end; in
    each, f = (the positive-going zero crossings − 1) / (the last crossing's time − the first's),
    each crossing linearly interpolated; f_e(t) = 220 · r(t) · 2^(c(t)/1200), r the ideal map's
    rate and c = clamp(−1200·log₂ r, ±2400) the command; per window the cents
    1200·log₂(f / f_e); PR's median cents is the median of those (signed), reported with the
    median f and the median and max |cents|. PR-source reads the sine fixture over [1 s, 7 s)
    against 220 Hz.
  - **The lag (LG)**, RK1 and RK2: over τ ∈ [−100, 300] ms in 1 ms steps, the τ minimising the
    RMS of PR's windows' cents against 220 · r(t) · 2^(c(t − τ)/1200); the RMS at that τ and at 0.
  - **PT1** from RC-off-x1, as in SR-7. **Instrument checks** (exit 1, nothing judged): Z0, every
    render answered, R44 refused as `unreadable`, ID1 (RC-off-x1's render is the fixture's
    samples), PT1's tap called.
  - **The verdict**: `VERDICT: GO — arm ON …` when arm ON has no failure, else `VERDICT: STOP —
    <each failing variant and rule>`. GO lets SR2 start with both arms.
  - **Off-arm identity**, before the measured run: a render-only run of RV1, RV2, RV3, RF1,
    RV1-edit and RC-off-*, both fixtures, each CAF equal byte for byte to SR1b's
    (`ramp-render-spike-sr1b/renders/`), or the phase stops.
  - Reported, not scored: RS (render seconds per audio second, bytes, peak RSS, K, the unit's
    reported latency, D_K, pulled − K · frames); RP-<name> (a keep-pitch render's clicks against
    the ideal map: found, signed median ms, max |diff| ms); PR-<name> for every keep-pitch sine
    render and PR-source; LG-RK1, LG-RK2; BW-RB-on-x2 (the 15 kHz level over [1 s, 5 s) of the
    render, in dB re `band.wav`'s over [1 s, 11 s)); SR-7's other rows.
  - **Why:** SR-7's arm ON rule is what stopped SR1b, so it is re-run as it stands; it never
    looked at pitch, which is the point of Keep pitch, so pitch is scored here, before the run,
    with a lag reading because a pitch command can only follow the rate behind the unit's
    window.
  - Risk accepted: a 25-cent bound is a quarter of a semitone, tighter than the ear on speech and
    looser than on a held tone; the pitch reader is a zero-crossing count on a pure sine, so a
    real voice's pitch is a person's check (SR5).
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
- **SR-13 — Keep pitch on is Apple's time-pitch unit in RATE mode, its rate commanded a measured
  lead ahead: SR-6's arm plus the lead, for ramps and held spans alike; it supersedes SR-8 whole.**
  The owner's answer to SR1d's diagnostic STOP (2026-10-23, "Rate mode + 60 ms lead"), quoted in
  the road map; SR-6's keep-pitch-off arm, the file, the cache and SR-3 stand.
  - **Feeding.** `AVAudioSourceNode` → `AVAudioUnitTimePitch` (pitch 0, the default overlap) →
    the main mixer, in `AVAudioEngine`'s offline manual rendering at 48 kHz (at most 4 096 frames
    a call). The source is fed as is, sequentially, from ⌊p(0)⌋ − P, P = 4 800 frames, a position
    before frame 0 read as zero.
  - **The rate.** Before each 256-frame `renderOffline`, with n = rendered − round(P / r(0)), the
    unit's rate is (p̃(n + L + 256) − p̃(n + L)) / 256 clamped to 1/32…32, p̃ being p extended
    before 0 at r(0) and past the end at the last breakpoint's slope, and L =
    `RampAudioRenderer.rateLeadFrames` (output frames), the lead SR-14's sweep picks.
  - **Discard.** The first round(P / r(0)) + the unit's reported latency output frames are
    discarded, so kept frame 0 is p(0).
  - **The bound is 1/32…32.** It contains every rate a ramp sounds at (the ×0.1 floor, and the
    ×12 peak above which the plan leaves the audio out, #190), so Keep pitch holds the source's
    pitch everywhere: SR-8's ±2400-cent clamp and its tape excess past ×0.25–×4 are gone.
  - **Held spans** render through the same arm. Once SR-14's run answers GO, keep pitch on
    renders the whole map through it and the plan's `glide` spans are ignored (SR-11 lifted); the
    core still writes `glide` and the cache key still names it, a harmless redundancy.
  - **Why:** SR1d's diagnostic (the road map's SR1d record) found SR-8's dropouts are the unit's
    own in pitch mode: one at each crossing of an 11.7 Hz analysis bin (FFT 4096 at 48 kHz) by a
    gliding partial — RK1's 17 crossings gave 17 dropouts, and no block size, flag, smoothness or
    K removed them — while the unit in rate mode gave none. SR1b's rate-driven arm misplaced
    clicks only because its rate was read at n while the unit's window follows behind it; read
    60 ms ahead, RK1's placement max was 8.86 ms (71/71 found) and RK2's 2.92 ms (23/23), with 0
    dropouts, inside SR-7's ceilings (17.60 and 19.14 ms). Apple's other unit (`AUTimePitch`,
    'tmpt') was not taken: its latency moves with the pitch and its timing jitters 7–15 ms. Still
    Apple's algorithm (SY-41: no own time-stretch).
  - Risk accepted: **the lead rests on Apple's unpublished internal behaviour** — a macOS change
    to the unit's window could move it — so `ramp_proof.py`'s L1 and L2 (Release, no spike) pin a
    Keep pitch ramp's placement under ceilings from SR-14's run and fail when the lead stops
    fitting. **The constant-rate finding:** SR-8's arm dropped out on gliding content at CONSTANT
    rates too (18 dropouts at ×2 on a 220→440 Hz sweep, where the composition's `spectral` gave
    0), and so did SR2b's held spans until this phase. One lead serves every map; keep pitch on
    stays measured against controls, never claimed sample-exact.
- **SR-14 — The fourth spike's rule (SR1d), fixed before its run: the lead swept first, then
  SR-7's arm ON over RK1, RK2 and a held-out RK3, SR-9's pitch rows under the rate-mode command,
  and a gliding fixture's dropouts, with a verdict for arm ON alone.**
  `tools/proof/ramp_spike/render_spike.py --lead-sweep`, then `--verdict rate` with `--variants
  RK1,RK2,RK3,RC-on-x0.5,RC-on-x0.9,RC-on-x1.1,RC-on-x2,C-on-x0.5,C-on-x0.9,C-on-x1.1,C-on-x2,
  RC-off-x1,RC-on-x1,RC-on-x3,RC-on-x6,RC-on-x0.2,RB-on-x2,RW-on-x0.9,RW-on-x1.1,RW-on-x2`, every
  group, through SR-7's instrument.
  - **The lead, first.** A render-only sweep over L ∈ {0, 2, …, 100} ms (round(L · 48) output
    frames): RK1 and RK2 rendered from the clicks fixture into the work folder's `lead/`, each
    render's clicks placed against the ideal map by SR-7's keep-pitch method (the template
    unscaled), reading found, of and max |diff|. Only a lead at which BOTH ramps find every click
    (found = of, of > 0) is eligible; L* is the eligible lead minimising the greater of the two
    maxima, a tie going to the smaller lead. No eligible lead is a STOP (`STOP — lead: no lead
    finds every click`). Each ramp's own best lead is reported. Per K is not applicable: there is
    one rate, 48 kHz. L* is written into `rateLeadFrames` before the measured run.
  - **Variants.** SR-9's, unchanged, plus RK3 (keep pitch on, ×2 → ×0.5 ease in-out over 1–3 s,
    8 s; rendered and staged as RK1 is, its frames read in playback, its end-rate controls
    RC-on-x2 and RC-on-x0.5), which the sweep never renders, so the lead is not fitted to
    everything scored; and RW-on-x0.9, RW-on-x1.1, RW-on-x2 (keep pitch on, constant, 6 s),
    rendered only, from `glide.wav`: 20 s, 48 kHz, mono, amplitude 0.5, phase-continuous, 220 Hz
    to 2 s, an exponential sweep to 440 Hz at 4 s, then 440 Hz — the content that made SR-8's
    held spans drop out.
  - **Scoring.** SR-7's arm ON rule unchanged over RK1, RK2 and RK3 — placement against their
    RC-on end-rate controls, click, dropout and video in export and in playback, plus agreement —
    and each RC-on anchor's placement against its C-on control in export and in playback. **Pitch**
    is SR-9's with c the rate-mode command, c = clamp(−1200 · log₂ r, ±6000) cents (the rate's
    1/32…32 bound), so f_e = 220 Hz at every rate a variant sounds: PR |median cents| ≤ 25 for
    RK1, RK2, RK3 and each RC-on anchor, and LG RMS at the best τ ≤ 25 for RK1, RK2 and RK3.
    **The sweep:** each RW-on-* render shows no dropout by SR-5's (a) and (b), its local period
    1 / glide_hz(1 + r · t) s, glide_hz the fixture's frequency at source second 1 + r · t. A rule
    not measured fails.
  - **The template.** SR-7's unscaled template stands: SR1c's slowed-click problem does not
    arise in rate mode (SR1b's rate-driven RC-on controls found 15/15 at ×0.5), and RC-on-x0.5's
    anchor row confirms it in this run.
  - **Instrument checks** (exit 1, nothing judged): as SR-9 — Z0, every render answered, R44
    refused as `unreadable`, ID1, PT1's tap called. **Off-arm identity**, before the measured run:
    a render-only run of RV1, RV2, RV3, RF1, RV1-edit and RC-off-*, both fixtures, each CAF equal
    byte for byte to SR1b's (`ramp-render-spike-sr1b/renders/`), or the phase stops.
  - **The verdict**: `VERDICT: GO — arm ON (rate) …` when nothing above fails, else `VERDICT:
    STOP — <each failing variant and rule>`. GO lifts SR-11 (SR-13); a STOP lands nothing and goes
    to the owner with the measurement.
  - Reported, not scored: RS (render seconds per audio second, bytes, peak RSS, the lead, the
    unit's reported latency, and pulled − map frames, the map frames read from the variant's
    map); RP-<name>; PR-<name> for every keep-pitch sine render (RC-on-x0.2 and RC-on-x6 now
    expect 220 Hz) and PR-source; LG-RK1…RK3; BW-RB-on-x2; RW-<name>'s dropout events; the
    sweep's table; SR-7's other rows.
  - **Why:** the lead is a fitted constant, so it is fitted first, on two ramps only, and the
    rule then judges it on a third ramp it never saw and on constant renders of a gliding source,
    the case the diagnostic found SR-8 failing at constant rates; SR-9's pitch rows still apply
    because keeping the pitch is the point, and the rate-mode command makes their expectation the
    source's own 220 Hz.
  - Risk accepted: the fixtures stay synthetic (a click train, one sine, one sweep), so whether a
    ramp sounds right is a person's check (SR5); one lead is fitted for every map, so a ramp much
    steeper than RK1–RK3 is judged only by L1 and L2's ceilings after the switch.
- **SR-15 — SR-13's arm lands with L* = 56 ms though SR-14's run stopped: a deep slow-down plays
  up to about 22 ms late, accepted by the owner as a known limit until SR1e.** The owner's answer to
  SR1d's measured STOP (2026-10-23, "Land it, then tighten"), quoted in the road map; SR-14's text
  and its verdict stand as recorded.
  - **What lands.** Keep pitch on renders every ramped clip through SR-13's arm at
    `rateLeadFrames` = 2 688 (56 ms, the sweep's L*), ramps and held spans alike: SR-11 is lifted,
    `+Hybrid` is deleted, `RampAudioRenderer.version` is 4.
  - **The limit, measured.** RK3 (×2 → ×0.5 ease in-out over 1–3 s), which the sweep never saw,
    placed its export clicks up to 22.10 ms from the ideal map against SR-14's ceiling of 19.14 ms
    (RC-on-x0.5's 14.14 + 5.0): −1.7 to +12.9 ms through the ×2 head, climbing through the
    slow-down, +18.2 to +22.1 ms late through the held ×0.5 tail, where a constant ×0.5 render sits
    12.6 ms early — the unit about 33 ms behind after a ×4 slow-down, which one constant lead cannot
    correct. RK1 (8.06 ms against 17.60) and RK2 (5.55 against 19.14) passed, with no dropout and
    every pitch reading within 0.01 cents of 220 Hz.
  - **The run's playback failures are the instrument's.** That session's ×1 tap read 86.333 ms
    early (#335), so PT1's correction moved every corrected playback signal 4 144 samples later and
    its first 86 ms are zeros: SR-5's dropout rule (b) reads them as a dropout at 0.05 s, and a
    click expected at 0.050 s is matched to the onset at 0.086 s (36.3 ms). RC-off-x1, a keep-pitch-
    off ×1 render, showed the same 0.05 s "dropout"; so RK1's, RK2's and RK3's playback dropouts,
    RC-on-x2's playback anchor and RK3's agreement are not the arm.
  - **The guard.** `ramp_proof.py`'s L1 (RK1) and L2 (RK2) hold a Keep pitch ramp's export under
    SR-7's floor and ceiling from that run's export controls; L3 holds RK3's case under its measured
    worst plus a stated margin, so a macOS change to the unit that moves the lead fails a Release
    row rather than passing unseen.
  - **SR1e follows**, in its own handoff: a closed-loop correction that steers the rate from how
    much source the unit has actually consumed, so the lag cannot accumulate; if it passes, it
    replaces the constant lead and L3 tightens to SR-7's ceiling.
  - **Why:** the owner judged a ≤ 22 ms lag after a deep slow-down, with the pitch kept and no
    dropout, better than SR-11's tape glide inside every Keep pitch ramp.
  - Risk accepted: a Keep pitch clip that slows hard plays its audio up to about 22 ms behind its
    picture after the slow-down, until SR1e; a ramp steeper than RK3 may lag more, and only L3's
    pinned case is guarded.
  - *Amended by SR-16 (SR1e):* SR1e did not tighten, and the 56 ms lead stays. The limit, as SR1e
    measured it at 56 ms (render-only): ×2 → ×0.5 linear (H7) and ease-out (H8) over 1–3 s read
    22.47 and 23.90 ms against SR-7's 19.14 ms, and RK3 reads 22.10. ×4 → ×1 linear over 1–3 s
    (H3) finds 44/70 clicks. SR-7's reach there is 20 ms (0.4 × the 50 ms click spacing at ×4),
    and the constant ×4 render sits at that edge (92/95, max 21.00 ms). The loss depends on the
    lead (68–69/70 at 46–52 ms, 42/70 at 53, 44/70 at 56) with the same template on the same
    content, so it is the render's output at that lead, not the template failing on ×4 content.
    The diagnostic does not separate misplacement past 20 ms from a smeared click found at r < 0.5,
    so about 26 of H3's 70 clicks are **unmeasured**: each either more than 20 ms off or found at
    r < 0.5, and the diagnostic does not say which. ×3 → ×0.5 linear over 0.5 s (H5) drops out
    once (1.452 s) with a 150-cent window at both 50 and 56 ms: the unit's own behaviour, which
    SR-15's "no dropout" did not cover. L3 stays the one pinned case.
- **SR-16 — SR1e closes as measured: the 56 ms lead stays, no closed loop and no re-fit lands, and
  product behaviour is unchanged.** The owner's answer to SR1e's diagnostic STOP (2026-10-23,
  "Keep 56 ms, close SR1e"), quoted in the road map: `rateLeadFrames` stays 2 688,
  `RampAudioRenderer.version` stays 4, no product code changes; SR-13's mechanism and SR-15's
  acceptance stand, SR-15's risk line widened by its Amended-by line.
  - **The diagnostic** (render-only, a scratch probe of SR-13's `renderTimePitch` loop compiled
    from b4b63c9's `app/Sources` with `-O`, scored by SR-7's reach and edge rules, `ramp_spike`'s
    dropouts and `render_spike.pitch_track`, imported unchanged; not run under a SHA-pinned rule).
    Its sources are at `~/.claude/litecode/framejob/speed-ramps-sr1e/diag/` (`main.swift`,
    `build.py`, `run.py`, `look.py`, `dlag.py`, `tail.py`, `series.py`, `grid.py`, `ilc.py`); their
    `H` names that session's scratchpad, where the outputs went. **The replica is exact**: at
    56 ms it reads RK1 71/71 max 8.06 ms, RK2 23/23 5.55 ms and RK3 35/35 22.10 ms, SR1d's measured
    run to the hundredth.
  - **The look-ahead.** At a constant rate the unit pulls exactly r × 256 frames a block, and
    fed − p(output) holds constant: 3 264, 3 456, 3 840, 5 632, 7 424 and 9 216 frames at ×0.25,
    ×0.5, ×1, ×2, ×3 and ×4, which is A(r) = 3 072 + 768·r for r ≤ 1 and 2 048 + 1 792·r for
    r ≥ 1, exact at constant rates and the same on either fixture. **While the rate moves it pulls
    on its own**: RK3 at lead 0, commanded r(n) exactly, climbs from 5 632 to 6 718 (+1 086 frames
    beyond the command, in lumps). **What it pulls depends on the content**: the same map and
    commands pull 512 frames apart on the clicks and the sine by RK3's end, 768 on the dip (H2).
  - **Consumed input does not fix placement; it is path-dependent.** In the held ×1 tail, X1
    (constant) has fed − p 3 840 and places at 0.00 ms; the dip at 56 ms 4 896 (+1 056) and
    0.00 ms; the dip with a loop holding fed at p + A(r) 3 837 (−3) and +20 ms (17–23). RK3's ×0.5
    tails follow no one curve: lead 0 excess +3 262 at −41 ms, the loop 0 at −5 to −8 ms, lead 56
    −759 at +20 ms, the ×0.5 control 0 at −12 ms.
  - **The controller fails.** Target fed(m) = p(m + tl) + A(r(m + tl)), a proportional correction
    cmd = ff + (need − ff)·256/horizon bounded to ±bound × ff, ff = r(n + lead); swept horizon 5,
    10, 20, 40, 80, 320 ms, bound 0.1, 0.25, 0.5, feed-forward lead 0, 28, 56 ms and tl 0, 28,
    56 ms. Its best rows (max |diff| ms, RK1 / RK2 / RK3 / H1 / H2 / H4 / H5), against the
    product's 8.06 / 5.55 / 22.10 / 20.56 / 2.08 / 14.14 / 27.54: h 20 b 0.25 ff 28 16.02 / 14.06
    / 18.54 / 27.66 / 33.44 / 35.48 / 26.62; h 40 b 0.1 ff 0 14.86 / 14.61 / 20.05 (34/35) / 26.68
    / 55.96 / 24.99 / 25.68; deadbeat h 5.3 b 0.5 ff 0 16.86 / 14.19 / 20.08 / 27.66 / 55.23 /
    33.96 / 26.16. It fixes the ×2 → ×0.5 tails (RK3, H7, H8 end within 0–2 ms) and costs
    everything else; every loop row rides its bound, 10–25 % around the map's rate, and tl > 0
    makes every row worse (RK1 29–41 ms, RK2 42–60 ms).
  - **The oracle loop does not converge.** The true click error of each pass, warped into the map
    as r·e·48 source frames at 56 ms, over passes 0–3: RK1 8.06 → 5.44 → 18.31 → 21.97; RK3 22.10
    → 19.06 → 17.86 → 21.90; H5 27.54 → 27.67 → 27.67 → 27.67 (≈ 27.6).
  - **The re-fit, not taken.** SR-14's sweep rule over RK1, RK2 and RK3 together (2 ms grid, every
    click found, minimax, a tie to the smaller lead) picks 50 ms (2 400 frames), minimax 11.38 ms,
    with every held-out shape H1–H8 under its SR-7 ceiling; RK3 is flat at 11.38 ms over 46–52 ms
    and meets a cliff at 53 (15.01, then 22.10 at 56, 36.60 at 60). The owner chose not to take it.
  - **The guard: no new `ramp_proof.py` L row.** H7 and H8 are the same deep ×2 → ×0.5 slow-down
    L3 already pins: at 53 → 60 ms all three move together across one cliff (RK3 15.01 → 36.60,
    H7 14.30 → 33.81, H8 14.09 → 33.94), so L3 already fails when they would. H3's 44/70 is below
    any found floor an L row can hold.
  - **Why:** the closed loop the request named cannot pass on this unit (its consumed input does
    not fix where its output sits), and the owner judged the measured 56 ms limit acceptable
    rather than re-fitting a constant that sits 3 ms from a cliff.
  - Risk accepted: SR-15's, as widened by its Amended-by line — a deep slow-down plays up to about
    24 ms late, a ×4 → ×1 ramp's placement is partly unmeasured, a 0.5 s ×3 → ×0.5 slow-down (H5) can drop out
    once; only L3's case is pinned.
- **SR-17 — A corrected playback tap holds only the samples the tap carried: the whole-sample
  correction trims, never zero-pads.** The instrument rule for #335's artifact, fixed in SR1e.
  - **The rule.** PT1's correction by k = round(m1 · rate / 1000) samples cuts off the head
    (k < 0) or the tail (k > 0) that a shift would zero-fill. Every SR-5/SR-7 rule reads the
    trimmed window as the signal's extent, with its own edges: EDGE_SKIP_S for placement, the
    50 ms dense-scan and dropout edges. A click expected outside the window is **unobserved**, not
    missed: it is out of the found share, counted apart, and agreement still pairs by index. k = 0
    is unchanged.
  - **Where.** PT1, every corrected playback signal in `render_spike.py`, and `ramp_proof.py`'s
    P1.
  - **Why:** SR1d's m1 of −86.333 ms zero-filled every corrected playback signal's first 86 ms,
    which SR-5's dropout rule (b) read as a 0.05 s "dropout" and placement matched to a 36.3 ms
    miss, out of zeros (SR-15).
  - **Shown by** `render_spike.py --selftest`'s S22 (a synthetic ±86.333 ms tap, trimmed and
    padded) and the mutants `trim-off` and `window-off`. No measured re-run: the selftest
    reproduces the −86.333 ms case synthetically, and SR-14's text and SR1d's `results.json` stand
    as run.
  - Risk accepted: clicks in the trimmed span plus its edge go unscored.
