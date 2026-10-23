# Spec §11 — decisions: Speed ramps (road map "speed-ramps", #111)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The road map that makes these is open: `designs/speed-ramps.md` holds each phase's record (SR1
the spike and these decisions; SR2 the core target and the plan; SR3 edits on a ramped clip; SR4
Swift's mappers; SR5 the UI and the close). SR-1…SR-3 were recorded in SR1, before any product
code, from the owner's decisions of 2026-10-23 on issue #111 (asked and answered in the session
that opened the road map, quoted in its "The owner's choices"); SR-4 is the working arrangement
the owner set that day; SR-5, the spike's rule, was recorded before the spike's measured run,
whose `results.json` pins this file's SHA-256 as `rule_sha256`. Later phases record their rules
as new entries (SR-6 on) or as Amended-by lines before their code.

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
