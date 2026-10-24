# The speed-ramp spike — road map "speed-ramps", SR1 (#111)

One question the road map asks before any ramp code is written: **do the many abutting
constant-rate segments a ramp's plan will hold click, drop out, or misplace audio or frames, in
export and in playback?** (`scaleTimeRange` is piecewise-constant, so a ramp is many segments.)
**The answers are not here**: they are in `designs/speed-ramps.md`'s "SR1 — the spike" record
(the table and the VERDICT line). The rule the run is judged by is spec §11 SR-5
(`designs/spec/11-decisions/speed-ramps.md`), fixed before the run; `results.json` stores that
file's SHA-256 as `rule_sha256`, so the rule a recorded run read is pinned. What is here is how
to run it again.

```sh
python3 tools/proof/ramp_spike/ramp_spike.py --selftest                     # the classifiers' controls; no build
python3 tools/proof/ramp_spike/ramp_spike.py --selftest --mutant click-off  # must exit 1 (S2)
python3 tools/proof/ramp_spike/ramp_spike.py --selftest --mutant dropout-off   # must exit 1 (S3)
python3 tools/proof/ramp_spike/ramp_spike.py --selftest --mutant pin-off    # must exit 1 (S4)
python3 tools/proof/ramp_spike/ramp_spike.py --selftest --mutant excuse-all # must exit 1 (S6)
python3 tools/proof/ramp_spike/ramp_spike.py --selftest --mutant kwindow-off   # must exit 1 (S7)
env -u RC_ASSEMBLYAI_KEY python3 tools/proof/ramp_spike/ramp_spike.py      # every group, every variant
env -u RC_ASSEMBLYAI_KEY python3 tools/proof/ramp_spike/ramp_spike.py --groups export --variants V1-G1,C-off-x2
python3 tools/proof/ramp_spike/ramp_spike.py --remake                       # remake the fixtures first
```

The probe links the core's staticlib, so `make rust` comes first; `ffmpeg` and `ffprobe` are
proof-time dependencies (the fixtures and the reads). Without either the runner prints `NOT
PERFORMED` and exits **2**. A whole run takes about a quarter of an hour, most of it the
playback group playing every variant in real time (aloud: the editor's own player is driven).

**Exit codes.** **0**: every requested row answered, whatever the VERDICT. **1**: an instrument
check failed — Z0 (the fixtures read back), a `C-off-*` control failing placement, click or
dropout in export, F1 not clicking at its 2 s boundary alone or not failing placement, PT0's tap
never called, a variant whose written source end passes 19 s of the 20 s fixture (W0, before any
build), the probe's build (B1, B2), a probe crash or expiry, or a read that failed (R-*). **2**:
not performed. Under `--selftest --mutant`: 1 caught, 0 survived.

## The instruments

| File | What it is |
|---|---|
| `ramp_spike.py` | the runner: the fixtures, the map S and the variants' projects, the build, the probe groups, the classifiers (SR-5), the rows, the table, the VERDICT, `results.json`, the selftest and its mutants |
| `ramp_spike_probe.swift` | compiled AS `main.swift` over every file in `app/Sources` but the app's own, through `swift_build.build` (`-D FRAMEJOB_DEV_TOOLS`), `Blank.mp4` and the app's `default.metallib` beside it; `ramp-spike-probe <plan\|export\|playback> <work-dir> <job.json>` |

**The probe** reads, per job, what `job.json` asks: `plan` (`ReelProject.from(json:)`, its
`planJSON` verbatim), `wav` and `prores` (`Exporter().export` with the `audio_wav` and
`prores_422` presets, `export_offset_probe.swift`'s loop), and in the playback group `tap` and
`frames` on the package opened as a `ProjectDocument` in a real editor window
(`media_less_playback_probe.swift`'s `Opened`). `tap` replaces the editor's item's `audioMix`
with `CompositionBuilder.audioParameters(…, dsp: nil, meter: nil)` per composition audio track
carrying the probe's own PostEffects `MTAudioProcessingTap`, plays the item from 0 to the clip's
end + 0.5 s and keeps channel 0 of every buffer stamped with its source-audio time; `frames`
seeks every timeline frame and reads the item's `AVPlayerItemVideoOutput`, the mean luma of each
bar's centre 16 × 16 block. Each job's document is closed before the next opens. Every child
(ffmpeg, the build, each probe group) runs under `graphics_spike/bounded.py`: build 900 s, plan
120 s, export 900 s, playback 1800 s; an expiry is that group's FAIL.

**The runner** works in `tools/proof/work/ramp-spike/` (untracked): `fixtures/`, `projects/`
(a `<variant>@<fixture>.framejob` package per pair), `probe/`, `runs/` (what the probe wrote),
`jobs-<group>.json`, `stderr-<group>.txt` and `results.json`. It imports `click_value`,
`template`, `summary` and `read_ffmpeg` from `export_offset_proof.py` and `build_shader` from
`media_less_playback_probe.py`. Nothing here opens an app instance, a socket or MCP, performs a
menu item, writes `UserDefaults` (the probe pins Preview Quality in the volatile argument
domain), touches the network or reads the owner's media.

## The fixtures and the variants

`ramp-clicks-v1.mov` and `ramp-sine-v1.mov`, made once (`--remake` redoes them): 20 s, 320 × 180,
30 fps ProRes 422 (`prores_ks`, BT.709 tags), frame i showing i in 10 bars 32 px wide (MSB left,
white = 1); audio mono 48 kHz `pcm_s16le` — the clicks are `export_offset_proof.click_value`'s
1 ms Hann, amplitude 0.5, centred at 0.1 s + 0.2 s·n (n = 0…99), the sine 220 Hz at 0.5.

Every variant is one track on a 320 × 180, 30 fps canvas, written at format 26 as abutting media
clips (one per segment) from source 1 s: boundaries every G frames inside the ramp from its start,
one segment before and one after; segment k reads `in_k = in + round(S(t_k))` at `speed_k =
(in_k+1 − in_k)/(t_k+1 − t_k)`, S the ramp's map in closed form (`actions.rs`'s `ease`
integrated).

| Variant | Keep pitch | Ramp | Length |
|---|---|---|---|
| V1-G1, -G4, -G15 | off | ×1 → ×2 linear over [1 s, 3 s) | 8 s |
| V2-G* | off | ×2 → ×0.5 ease in-out over [1 s, 4 s) | 8 s |
| V3-G* | off | ×0.25 → ×4 ease in over [0.5 s, 4.5 s) | 6 s |
| K1-G* | on | ×1.1 → ×2 linear over [1 s, 3 s) | 8 s |
| K2-G* | on | ×0.9 → ×0.5 ease out over [1 s, 3 s) | 8 s |
| V1L | off | V1-G1 with its ×1 head one source tick longer, so it is time-scaled and takes SY-24's lead | 8 s |
| F1 | off | the planted fault: V1-G1 with every segment from 2 s reading 2 400 ticks later, judged against V1-G1's segments | 8 s |
| C-off-x1, -x0.25, -x0.5, -x2 | off | one clip at that rate | 6 s |
| C-off-x4 | off | one clip at ×4 (its source ends at 17 s) | 4 s |
| C-on-x0.5, -x0.9, -x1.1, -x2 | on | one clip at that rate (K1's and K2's end-rate controls) | 6 s |

Each variant is read over both fixtures: `plan` (both), `wav` (both), `prores` (clicks), `tap`
(both) and `frames` (clicks; V1…K2 at G1, V1L, C-off-x1 and C-off-x2 only).

## The rows

H0 the host (model, macOS, load, any Frame Job running) and `rule_sha256`; B0 the staticlib; W0
the source-end check; Z0 the fixtures read back (every frame's bars decode to its index, every
click within 0.05 ms, no click at fake boundaries every 33.3 ms on the sine); B1 the shader; B2
the probe build; R-plan, R-export, R-playback each group's reads; Q-<v> the plan (one video and
one audio composition track, the segments exactly as written, one pitch name); E-<v> export and
P-<v> playback (placement, click, dropout, video, by SR-5); PT0 the tap of C-off-x2 against the
varispeed pin (missed: every P audio row is unmeasured, the frames still scored); A-<v> playback
against export; I0 the instrument checks. Then the table and `VERDICT: GO | GO-UNIFORM-LEAD |
GO-EXPORT-ONLY | STOP — …`. The keep-pitch controls' rows print `measured`: reported, not scored.

**`--selftest`** (no build, no fixture): S1 clean sines at 220, 55 and 880 Hz and a 55→880 Hz
glide with fake boundaries every 33.3 ms — no click, no dropout; S2 a 4 ms phase jump at one
boundary — it alone clicks; S3 a 2 ms zero gap at 220 and at 55 Hz — a dropout (b) each — and a
10 ms stretch at 0.3 × at 220 Hz — a dropout (a); S4 a click train shifted 2 ms from one point
on — placement fails; S5 unshifted — passes; S6 bar lumas with one wrong frame fail and a
within-2-ticks frame read as its neighbour is excused; S7 keep pitch on, W = 15 ms, a clean
220 Hz sine as both end-rate controls, a phase jump 10 ms after the boundary — it clicks. The
mutants: `click-off` (the threshold infinite: S2), `dropout-off` (neither dropout test fires:
S3), `pin-off` (placement always passes: S4), `excuse-all` (every frame may read a neighbour:
S6), `kwindow-off` (the keep-pitch D window ±2 ms: S7).

## SR1b — the rendered-ramp spike (`render_spike.py`)

SR1 stopped, and the owner chose to render a ramped clip's audio offline (spec §11 SR-6):
`RampAudioRenderer` (`app/Sources/RampAudioRenderer*.swift`, `RampAudioResampler.swift`,
`RampCAFWriter.swift`) writes it into a CAF that the composition carries as ONE ×1 clip. **Is
that rendered audio free of clicks and dropouts, and placed on the ideal map, in export and in
playback?** The rule is spec §11 SR-7, fixed before the run and pinned by `rule_sha256` in
`results.json`; the answers are in
`designs/speed-ramps.md`'s "SR1b — the rendered-audio spike" record.

```sh
python3 tools/proof/ramp_spike/render_spike.py --selftest                       # S8–S13; no build
python3 tools/proof/ramp_spike/render_spike.py --selftest --mutant dense-off    # must exit 1 (S9)
python3 tools/proof/ramp_spike/render_spike.py --selftest --mutant merge-all    # must exit 1 (S9)
python3 tools/proof/ramp_spike/render_spike.py --selftest --mutant pt1-off      # must exit 1 (S10)
python3 tools/proof/ramp_spike/render_spike.py --selftest --mutant identity-off # must exit 1 (S12)
python3 tools/proof/ramp_spike/render_spike.py --selftest --mutant on-anchor-off  # must exit 1 (S13)
env -u RC_ASSEMBLYAI_KEY python3 tools/proof/ramp_spike/render_spike.py        # every group, every variant
env -u RC_ASSEMBLYAI_KEY python3 tools/proof/ramp_spike/render_spike.py --groups render,plan,export --variants RV1,RF1,RC-off-x1
```

It reuses SR1's fixtures (`work/ramp-spike/fixtures/`), Z0, classifiers and probe; the probe is
built `-O` as `work/ramp-spike/probe/ramp-render-probe` (render time is measured so), and its
fourth group, `render`, calls `RampAudioRenderer.render` per job (`{name, source, clip_ticks,
source_ticks, keep_pitch, destination}`, one stdout line per job with the report and the
process's peak RSS). Everything else is in `tools/proof/work/ramp-render-spike/` (untracked):
`renders/` (the CAFs), `projects/`, `runs/`, `r44.wav`, the job and stderr files and
`results.json`. Groups: `render`, `plan`, `export`, `playback` (bounds 900, 120, 1500 and 2700 s).
A whole run takes about a quarter of an hour, most of it playback (aloud). Exit codes as SR1's:
**0** every requested row answered, whatever the VERDICT; **1** an instrument check failed (Z0,
a render not answered, R44, ID1, a `C-off-*` control in export but C-off-x4's click, F1, PT1's
tap never called, W0, B1, B2, R-*); **2** not performed.

**The variants** (SR-7). Rendered ramps RV1–RV3 (keep pitch off) and RK1, RK2 (on) are SR1's
V1–V3 and K1, K2; RF1 is RV1 with every map breakpoint from 2 s reading 2 400 ticks later, judged
against RV1's map; RV1-edit (RV1 ending ×2.5) is rendered only; RC-off-x0.25…x4 and
RC-on-x0.5…x2 are rendered constant controls; SR1's composition controls C-off-* and C-on-* run
unchanged. A rendered variant's map has a breakpoint every 600 ticks; its project holds the
fixture's video as SR1's G1 segments with `enabled.audio` false and one ×1 clip of the CAF on a
second track. Playback reads frames for RV1–RV3, RK1, RK2 and every RC-off control.

**The rows.** H0, W0, Z0, B1, B2 as SR1's; R-render (every render answered) and R44 (a 44.1 kHz
WAV refused as `unreadable`); R-plan, R-export, R-playback; Q-<v> (a rendered variant: the
written video segments and one ×1 audio segment of the render, pitch `off`); ID1 (RC-off-x1's
render equals the fixture's samples within 1e-6, both fixtures); RS-<v> (render seconds per audio
second, bytes per audio second, peak RSS, and with keep pitch on the unit's latency and pulled −
map frames); RE1 (RV1-edit's render time and how many leading samples equal RV1's); PT1
(RC-off-x1's tap, the ×1 offset m1 every rendered playback is corrected by, #335); E-<v>, P-<v>
(placement against the ideal map, the dense click scan, dropout, video), A-<v> (corrected
playback against export); XR-<v> (export WAV − render at offset 0); PT0 and T335 (C-off-x2's and
C-off-x1's raw taps); I334 (C-off-x4's export click, #334, reported); F1 (RF1: one click event
within ±5 ms of 2 s, placement failing); I0. Then the table and `VERDICT: GO | SPLIT — off GO,
on STOP — … | SPLIT — off STOP, on GO — … | STOP — …`.

**`--selftest`** (no build, no fixture): S8 clean 220, 55 and 880 Hz sines and a 55→880 Hz
glide — the dense scan finds nothing; S9 4 ms phase jumps at 1.0 and 1.5 s — exactly two events,
there; S10 a ×1 click train 21 ms early in playback, on time in export — agreement passes with
PT1's correction and fails without; S11 RF1's shape (1 ms at ×6 phase advance in a 220 Hz sine)
— one event at its place; S12 a ×1 render one sample late fails the identity check; S13 RC-on
controls 43 ms late against their C-on reading, the ramps late by the same — the ramps' own rule
passes and arm ON stops on the anchors. The mutants: `dense-off` (no centre clicks: S9),
`merge-all` (every clicking centre one event: S9), `pt1-off` (m1 forced to 0: S10),
`identity-off` (the identity always holds: S12), `on-anchor-off` (the anchor always passes:
S13).

## SR1c — Keep pitch as resample, then pitch-shift (`render_spike.py --verdict on`)

SR-8 remade the Keep pitch arm as three stages (the glide at 48 kHz × K, Apple's time-pitch unit
held at ×1 with `pitch` = −1200·log₂ rate cents, a decimation by K; `RampVarispeedStream.swift`,
`RampAudioRenderer+TimePitch.swift`). SR1c re-runs SR-7's arm ON on it and scores the rendered
pitch, by spec §11 SR-9 (fixed before the run, pinned by `rule_sha256`); the answers are in
`designs/speed-ramps.md`'s SR1c record.

```sh
python3 tools/proof/ramp_spike/render_spike.py --selftest                          # S8–S17
python3 tools/proof/ramp_spike/render_spike.py --selftest --mutant pitch-flat      # must exit 1 (S14)
python3 tools/proof/ramp_spike/render_spike.py --selftest --mutant lag-zero        # must exit 1 (S15)
python3 tools/proof/ramp_spike/render_spike.py --selftest --mutant on-verdict-off  # must exit 1 (S16)
python3 tools/proof/ramp_spike/render_spike.py --selftest --mutant pitch-rule-off  # must exit 1 (S17)
env -u RC_ASSEMBLYAI_KEY python3 tools/proof/ramp_spike/render_spike.py --variants RK1,RK2,RC-on-x0.5,RC-on-x0.9,RC-on-x1.1,RC-on-x2,C-on-x0.5,C-on-x0.9,C-on-x1.1,C-on-x2,RC-off-x1,RC-on-x1,RC-on-x3,RC-on-x6,RC-on-x0.2,RB-on-x2 --verdict on
env -u RC_ASSEMBLYAI_KEY python3 tools/proof/ramp_spike/render_spike.py --groups render --variants RC-on-x0.5,RC-on-x0.9,RC-on-x1,RC-on-x1.1,RC-on-x2,RC-on-x3,RC-on-x6,RB-on-x2   # K, D_K, pitch, band
```

**`--verdict`** `both` (the default) prints SR-7's verdict unchanged; `on` prints SR-9's,
`VERDICT: GO — arm ON …` or `VERDICT: STOP — …`, from `decide_on`: SR-7's arm ON rule (RK1, RK2
and every RC-on anchor) plus pitch — each anchor's, RK1's and RK2's PR |median cents| ≤ 25 and
RK1's and RK2's LG RMS at the best τ ≤ 25, a failure naming `pitch` or `pitch lag`.

**The variants added.** Kind `aux`, keep pitch on, rendered from both fixtures and never staged
into a project: RC-on-x1 (×1, 6 s), RC-on-x3 (×3, 4 s), RC-on-x6 (×6, 2 s), RC-on-x0.2 (×0.2,
6 s). Kind `band`: RB-on-x2 (×2, 6 s, keep pitch on), rendered only from `band.wav` (a 20 s
48 kHz mono 15 kHz sine at amplitude 0.5 the runner writes into the work folder).

**The rows added** (read from the renders themselves, so a `--groups render` run has them):
RS-<v> now reads K, the unit's reported latency, D_K and pulled − K · frames (the probe's
render line carries `oversampling` and `delay_frames`); RP-<v> (a keep-pitch render's clicks
against the ideal map: found, signed median ms, max |diff| ms — D_K comes from these); PR-<v>
(40 ms windows every 10 ms over the clip less 50 ms each end, f = (positive-going zero crossings
− 1) / (last − first crossing time), against f_e = 220 · r · 2^(c/1200), c the clamped command:
median f, signed median cents, median and max |cents|) for every keep-pitch sine render, and
PR-source (the fixture over [1 s, 7 s)); LG-RK1, LG-RK2 (the τ in [−100, 300] ms minimising the
RMS cents against 220 · r(t) · 2^(c(t − τ)/1200), with the RMS at τ and at 0); BW-RB-on-x2 (the
15 kHz level over [1 s, 5 s) of the render, dB re `band.wav` over [1 s, 11 s), by Goertzel).

**`--selftest`** adds S14 (the pitch reader reads 220 Hz and 220 · 2^(50/1200) Hz sines within
0.5 cents), S15 (a synthetic RK1 track lagging 40 ms reads 40 ± 1 ms; a flat 220 Hz track
0 ± 1 ms), S16 (`decide_on` answers GO on passing arm-ON results with no OFF member, STOP naming
the anchor when one RC-on anchor's placement fails) and S17 (STOP naming `pitch` for an anchor's
PR median 100 cents off, `pitch lag` for RK1's LG RMS of 40 cents). The mutants: `pitch-flat`
(the reader answers 220 Hz: S14), `lag-zero` (τ always 0: S15), `on-verdict-off` (the anchors
ignored: S16), `pitch-rule-off` (pitch never fails: S17).

Before the measured run SR1b's work folder was copied once to
`tools/proof/work/ramp-render-spike-sr1b/` (never written; its `results.json` is SR1b's record),
and the off arm's renders compared with it byte for byte:

```sh
env -u RC_ASSEMBLYAI_KEY python3 tools/proof/ramp_spike/render_spike.py --groups render --variants RV1,RV2,RV3,RF1,RV1-edit,RC-off-x0.25,RC-off-x0.5,RC-off-x1,RC-off-x2,RC-off-x4
for f in tools/proof/work/ramp-render-spike-sr1b/renders/R{V,F,C-off}*.caf; do cmp "$f" "tools/proof/work/ramp-render-spike/renders/$(basename "$f")" || echo "DIFF $f"; done
```

## SR1d — Keep pitch as Apple's time-pitch in rate mode, led (`--lead-sweep`, `--verdict rate`)

SR-13 put the Keep pitch arm back to SR-6's rate-driven unit with its rate read a lead L ahead
(`RampAudioRenderer+TimePitch.swift`, `rateLeadFrames`); SR-8's three stages are gone, and
`RampVarispeedStream` and `position`/`chunk` lost their `per` parameter. SR1d measures the lead
first and then judges it by spec §11 SR-14 (fixed before the run, pinned by `rule_sha256`); the
answers are in `designs/speed-ramps.md`'s SR1d record.

```sh
python3 tools/proof/ramp_spike/render_spike.py --selftest                           # S8–S21
python3 tools/proof/ramp_spike/render_spike.py --selftest --mutant rk3-off          # must exit 1 (S18)
python3 tools/proof/ramp_spike/render_spike.py --selftest --mutant sweep-drop-off   # must exit 1 (S19)
python3 tools/proof/ramp_spike/render_spike.py --selftest --mutant lead-pick-max    # must exit 1 (S20)
env -u RC_ASSEMBLYAI_KEY python3 tools/proof/ramp_spike/render_spike.py --lead-sweep
env -u RC_ASSEMBLYAI_KEY python3 tools/proof/ramp_spike/render_spike.py --variants RK1,RK2,RK3,RC-on-x0.5,RC-on-x0.9,RC-on-x1.1,RC-on-x2,C-on-x0.5,C-on-x0.9,C-on-x1.1,C-on-x2,RC-off-x1,RC-on-x1,RC-on-x3,RC-on-x6,RC-on-x0.2,RB-on-x2,RW-on-x0.9,RW-on-x1.1,RW-on-x2 --verdict rate
```

**`--lead-sweep`** renders RK1 and RK2 from the clicks fixture at every lead in 0, 2, …, 100 ms
(round(L · 48) output frames, passed as the render job's `lead_frames`) into
`tools/proof/work/ramp-render-spike/lead/` (it writes nothing else), places each render's clicks
against the ideal map (found, of, max |diff|; SR-7's keep-pitch method) and prints the table,
each ramp's own best lead and `L*: <ms> ms = <frames> frames`, or `STOP — lead: no lead finds
every click`. `pick_lead` takes only the leads at which both ramps find every click and picks
the one with the least greater maximum, a tie going to the smaller lead. `lead/sweep.json` keeps
the rows. Exit 0 with an L*, 1 without. L* is then written into `rateLeadFrames` by hand.

**`--verdict rate`** prints SR-14's verdict, `VERDICT: GO — arm ON (rate) …` or `VERDICT: STOP
— …`, from `decide_rate`: SR-7's arm ON rule over RK1, RK2 and RK3 (`RATE_ON_RAMPS`), every RC-on
anchor, SR-9's pitch rows (PR for the ramps and anchors, LG for the ramps) with the command
clamped at ±6000 cents (the unit's 1/32…32 bound, so f_e = 220 Hz everywhere; `CENTS_BOUND`),
and no dropout in any RW render. `both` and `on` are unchanged but for PT1's coarse alignment
below, which applies under every `--verdict`.

**The variants added.** RK3 (keep pitch on, ×2 → ×0.5 ease in-out over 1–3 s, 8 s), rendered
and staged as RK1, its frames read in playback, its end-rate controls RC-on-x2 and RC-on-x0.5;
the sweep never renders it. Kind `sweep`, keep pitch on, 6 s, rendered only from `glide.wav` (20 s,
48 kHz, mono, amplitude 0.5, phase-continuous: 220 Hz to 2 s, exponential to 440 Hz at 4 s, then
440 Hz; the runner writes it into the work folder): RW-on-x0.9, RW-on-x1.1, RW-on-x2.

**The rows added or changed.** RS-<v> with keep pitch on now reads the lead, the unit's latency
and pulled − map frames (the map frames from the variant's own map; the probe's render line
carries `lead_frames` in place of SR1c's `oversampling` and `delay_frames`); RW-on-x0.9,
RW-on-x1.1, RW-on-x2 (SR-5's (a) and (b) on the render, the local period 1 / glide_hz(1 + r · t),
scored); LG-RK3; PR-source reads "no window read" rather than failing on an empty fixture track;
PT1 now aligns RC-off-x1's tap coarsely first (`coarse_ms`, as `ramp_proof.py`'s P1: the tap
moved by whole samples to its nearest click peaks), then `pt1` reads the rest, m1 = coarse +
fine, and its row is guarded against a tap that finds no click.

**`--selftest`** adds S18 (`decide_rate` answers GO on passing results and STOP naming RK3 when
its export placement fails), S19 (a synthetic ×2 render of the glide is clean, and the same with a
20 ms dip to 0.03 is one dropout), S20 (`pick_lead` takes the least greater maximum with ties to
the smaller lead; a lead with a lower maximum but one click missed loses; no eligible lead answers
None) and S21 (the rate-mode command expects 220 Hz at ×0.2 and ×6, where SR-9's expected 330 Hz
at ×6). The mutants: `rk3-off` (RK3 left out of `decide_rate`: S18), `sweep-drop-off` (an RW
render never fails: S19), `lead-pick-max` (the greatest maximum picked: S20).

Before the sweep SR1c's work folder was copied once to
`tools/proof/work/ramp-render-spike-sr1c/` (never written; its `results.json` is SR1c's record),
and the off arm's renders were compared byte for byte with SR1b's by SR1c's two commands above.

## SR1e — a corrected playback tap trimmed, not zero-padded (spec §11 SR-17)

SR1e closed as measured (spec §11 SR-16: the 56 ms lead kept, no product change); its diagnostic
is in `designs/speed-ramps.md`'s SR1e record. What it changed here is the instrument: PT1's
whole-sample correction of a playback tap (#335) used to move the samples with `shift_signal` and
zero-fill the head (k < 0) or tail (k > 0), which SR1d's m1 of −86.333 ms turned into a 0.05 s
"dropout" and a 36.3 ms placement out of zeros. Now `trim_shift(x, k)` cuts that span off and
answers where the samples start; `corrected_signal(x, rate, k)` answers `(samples, rate, window)`,
the window `(first / rate, (first + len) / rate)` s, None at k = 0; and `place_corrected` places
the trimmed samples. Every corrected playback signal (`signals_of`), PT1 and `ramp_proof.py`'s P1
go through it. `place_ideal(…, window=)` puts samples[0] at the window's start and counts a click
expected outside [lo + EDGE_SKIP_S, hi − EDGE_SKIP_S] as **unobserved**: None in `times` (so
`agreement` still pairs by index), out of `of` and the found share, counted in `unobserved`.
`side_rules` runs the dense scan and SR-5's dropouts over the trimmed samples with the window's
span as their length and reports every event time + lo. With no window (export, k = 0, the
composition controls) every result is as before. `shift_signal` stays, for S10 and
`ramp_proof.py`'s `placement()` (the `expect-shift` / `keep-shift` mutants' moved expectation).

```sh
python3 tools/proof/ramp_spike/render_spike.py --selftest                       # S8–S22, 15/15
python3 tools/proof/ramp_spike/render_spike.py --selftest --mutant trim-off     # must exit 1 (S22)
python3 tools/proof/ramp_spike/render_spike.py --selftest --mutant window-off   # must exit 1 (S22)
```

**`--selftest`** adds S22: a ×2 keep-pitch control (6 s) whose synthetic tap sits m1 = −86.333
and +86.333 ms off, corrected by `correction(m1)`. Trimmed, `side_rules` must place every
observed click (found = of > 0), count at least one unobserved, read max |diff| ≤ 0.5 ms, find no
dropout, and agree with the export's placement; padded the old way (`shift_signal`, no window),
the same call must show a dropout (at 0.05 s for −86 ms, near 5.914 s for +86 ms). Both halves,
both signs, or the row fails. The mutants: `trim-off` (`trim_shift` zero-pads again, window
starting at 0: S22's trimmed half drops out) and `window-off` (every click counted as observed:
the click outside the window is missed rather than unobserved). No measured run was made: the
selftest reproduces the −86.333 ms case, and SR1d's `results.json` stands as run.
