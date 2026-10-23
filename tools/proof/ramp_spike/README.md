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
