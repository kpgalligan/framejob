#!/usr/bin/env python3
"""Retimed-audio timing — an export's sound exactly as long as its range
(#337), a constant ×4 clip's export free of sample steps (#334), and where the
playback tap's ×1 offset comes from (#335), against the built app.

    env -u RC_ASSEMBLYAI_KEY python3 tools/proof/retimed_audio_proof.py [--only IDS]
        [--mutant plant-step|stamp-place] [--app PATH]

S1–S3 are pure (no app). Every other row needs `ffmpeg`/`ffprobe`. One owned
instance (`mcp.launch` on `proof_app`'s app — Debug by default,
`RC_PROOF_APP=release` for the record), on a scratch socket, logging to
`tools/proof/work/retimed-audio/framejob.log`, stopped by its PID; nothing
else is ever killed. Every project is written under
`tools/proof/work/retimed-audio/`, which each run empties, and closed once
built and exported. No row performs a menu item. The fixtures are
`ramp_spike.make_fixtures(False)`'s clicks and sine movies and
`tools/proof/media/toneB.m4a`; the measuring is `ramp_spike`'s,
`render_spike`'s and `ramp_proof`'s, imported, never copied. The probe reads
(`mix`, `tap`, `render`) are `ramp_spike_probe.swift`'s, built through
`ramp_spike.build_probe`, run after the instance has stopped.

Every constant clip is `ramp_proof.Doc.fixture_clip`'s: the fixture at 0 from
source in 1 s, 4 s long, on a 320 × 180 30 fps canvas. CX1 ×1; CX2 ×2 keep
pitch off; CK05 ×0.5 keep pitch on; X4 ×4 keep pitch off (`C-off-x4`), on
clicks and on sine. C is missing_audio_proof's control: toneB.m4a at 12 s on
track 1 of a 640 × 360 canvas, whose picture is the Blank placeholder; its
timeline is 10 180 000 ticks (16.967 s), not 17 s, because `add_clip` snaps
toneB's 2 986 400 ticks down to whole frames. T335 is one track: A ×1 keep pitch off over [0, 3 s) from source
1 s, B ×2 keep pitch off over [3 s, 6 s) from source 4 s, on clicks.

D0  the instance listens, and `Frame Job: ` never appears in its log.
S1  `frames_target`, the mirror of `ExportAudioEnd.frames(ofTicks:)`
    (round half up, integers only): 4 s is 192 000, 17 s 816 000, one
    29.97 fps frame (20 020 ticks) 1 602.
S2  `by_order` places a synthetic chunk list whose first half is stamped
    21 ms early exactly where its frames belong (offset 0); placing it by
    its stamps does not.
S3  a step planted into a sine is found by
    `render_spike.click_events(dense_scan(…), 0)`, and the clean sine has none.
X0  the fixtures made and read back (`ramp_spike.z0`).
A1  (#337) CX2 and CK05 each export `audio_wav` and `prores_422` twice: all
    8 decoded audio streams are exactly 192 000 frames at 48 kHz, and CX2's
    two runs per preset are PCM-identical. CK05's identity is reported (Apple's
    time-pitch has two outcomes, SR2b).
A2  (#337, the placeholder) C's `audio_wav` and `prores_422` are exactly
    `frames_target` of its timeline: 814 400 frames.
A3  (content) CX1, CX2 and C's `audio_wav` channel 0 equals the probe's
    `mix` read (variant `app`, the writer's own 16-bit read with no writer)
    over min(target, the mix's length) frames, int16 compared as float with
    no tolerance, and every frame past the mix's end is 0.0. CK05 is reported
    the same way against its two `app` mix reads (either may match). C's
    `composition_ticks` and `audio_track_ends` against its timeline are
    printed (#337's shortfall, read).
B1  (#334, reported) X4's `audio_wav` and `prores_422`: on sine no
    `click_events(dense_scan(x, rate, 4.0), 0)`; on clicks
    `varispeed_pass(place_ideal(…))` against `C-off-x4`. Its verdict is
    printed and not scored: B2 found the steps in AVFoundation's own read of
    the mix under every variant, so #334 is the owner's question (arm (c)).
    `--mutant plant-step` plants a step into the sine.
B2  (#334, reported) CK05 through `mix` twice with `app` and twice with
    `output_varispeed` (is each `output_varispeed` read PCM-identical to an
    `app` read?); X4 on sine through `mix` with `app`, `float` and
    `output_varispeed`: per read the events and their times, the chunk
    boundary nearest each, `audio_track_ends`, and max |diff| over the clip
    against `RampAudioRenderer`'s ideal (the `render` group, a constant ×4
    map, keep pitch off); and whether X4's `audio_wav` equals its `app` read
    (A3's rule) on sine and on clicks.
C1  (#335) T335 through the `playback` group's `tap` read, 3 runs. A's and
    B's clicks are placed by stamps (`ramp_spike.tap_signal`) and by order
    (`by_order`: every frame counted from the first chunk stamped ≥ 3.5 s,
    inside B), and in T335's `audio_wav` export. Instrument: B within 0.5 ms
    of the export by both placements. Score: A by order within 1.0 ms of A's
    export placement, every run. Then CX1, a track holding a ×1 clip alone
    (SR1's `C-off-x1` shape, where #335 was read), through the PreEffects
    tap (the product `AudioTap`'s flag) and the PostEffects tap, 3 runs
    each, by stamps (60 ms reach) and by SR2b's coarse method
    (`render_spike.coarse_ms`, ±200 ms), beside CX1's `audio_wav` export.
    Score: the PreEffects tap within 1.0 ms of the export by both methods,
    every run; the PostEffects offset is printed, not scored.
    `--mutant stamp-place` scores CX1's PostEffects stamps as the product's
    and must fail.
C2  (#335, reported) C1's package with `tap_flag: "pre"` (the product
    `AudioTap`'s PreEffects), 3 runs: A's and B's offsets by stamps and by
    order.

Exit 0 when every scored row passes, else 1.
"""

import argparse
import array
import json
import statistics
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof"))
import ramp_proof as rp  # noqa: E402  (puts graphics_spike and ramp_spike on the path)
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import ramp_spike as rs  # noqa: E402
import render_spike as rsp  # noqa: E402
import tree_copy  # noqa: E402
from export_offset_proof import read_ffmpeg  # noqa: E402

WORK = ROOT / "tools/proof/work/retimed-audio"
PROBE_WORK = WORK / "probe"
RENDERS = WORK / "renders"
TONE_B = ROOT / "tools/proof/media/toneB.m4a"
SEC = 600_000
RATE = 48_000
CALL_BOUND = 600
LENGTH = 4 * SEC
C_AT = 12 * SEC
T335_A = 3 * SEC
T335_B_IN = 4 * SEC
T335_LENGTH = 6 * SEC
ORDER_FROM = 2_100_000          # 3.5 s: the first chunk inside B
A_TOLERANCE_MS = 1.0
B_TOLERANCE_MS = 0.5
TIMING_RUNS = 3
STEP_AT_S = 2.0
STEP = 0.2
WALLS = {"export": 1500, "playback": 1800, "render": 900}
ROWS = ["D0", "S1", "S2", "S3", "X0", "A1", "A2", "A3", "B1", "B2", "C1", "C2"]
# B1 is reported, not scored: #334's steps are in AVFoundation's own read
# of the mix, every variant (B2), so #334 is arm (c), the owner's question.
REPORTED = {"B1", "B2", "C2"}
MUTANTS = ["plant-step", "stamp-place"]
# name: (fixture, rate, keep pitch or None)
CONSTANTS = {"CX1": ("clicks", 1.0, None), "CX2": ("clicks", 2.0, False),
             "CK05": ("clicks", 0.5, True), "X4S": ("sine", 4.0, False),
             "X4C": ("clicks", 4.0, False)}

rows = {}
MUTANT = None


def check(row, good, detail=""):
    rows[row] = bool(good)
    print(f"{row} {'pass' if good else 'fail'} — {detail}", flush=True)


def report(row, detail):
    rows[row] = True
    print(f"{row} reported — {detail}", flush=True)


# ---- pure ------------------------------------------------------------------------


def frames_target(ticks):
    """`ExportAudioEnd.frames(ofTicks:)`: ⌊(ticks · 48 000 + SEC/2) / SEC⌋."""
    return (ticks * RATE + SEC // 2) // SEC


def by_order(chunks, data, length, rate, from_ticks=ORDER_FROM):
    """The tap's samples placed by ORDER: the first chunk stamped ≥
    `from_ticks` fixes where its first frame sits, and every other frame sits
    its count of frames before or after it. Stamps elsewhere are not read."""
    n = int(length * rate / SEC)
    out = [0.0] * n
    anchor = next((i for i, (t, _) in enumerate(chunks)
                   if t is not None and t >= from_ticks), None)
    if anchor is None:
        return out
    first = int(round(chunks[anchor][0] * rate / SEC)) - sum(f for _, f in chunks[:anchor])
    for i in range(max(0, -first), min(len(data), n - first)):
        out[first + i] = data[i]
    return out


def plant_step(x, rate, at_s=STEP_AT_S, step=STEP):
    k = int(round(at_s * rate))
    return x[:k] + [v + step for v in x[k:]]


def s1():
    got = {"4 s": frames_target(4 * SEC), "17 s": frames_target(17 * SEC),
           "20 020 ticks": frames_target(20_020)}
    want = {"4 s": 192_000, "17 s": 816_000, "20 020 ticks": 1_602}
    check("S1", got == want, f"{got} (want {want})")


def s2():
    rate, n, size, jump = RATE, RATE, 512, 1008          # 1008 frames = 21 ms
    data = [float(i + 1) for i in range(n)]
    chunks = []
    for start in range(0, n, size):
        early = jump if start < n // 2 else 0
        chunks.append(((start - early) * SEC // rate, min(size, n - start)))
    line = {"format": {"rate": rate}, "chunks": [list(c) for c in chunks]}
    placed = by_order(chunks, data, SEC, rate, from_ticks=(n // 2) * SEC // rate)
    path = WORK / "s2.f32"
    path.write_bytes(array.array("f", data).tobytes())
    stamped, _ = rs.tap_signal(dict(line, path=str(path)), SEC)
    ok = placed == data and stamped != data
    first_wrong = next((i for i, (a, b) in enumerate(zip(placed, data)) if a != b), None)
    check("S2", ok, f"by order exact {placed == data} (first wrong {first_wrong}); by stamps "
                    f"exact {stamped == data} (must not be)")


def s3():
    x = rs.sine(rs.SINE_HZ, 2 * STEP_AT_S)
    clean = rsp.click_events(rsp.dense_scan(x, RATE, 2 * STEP_AT_S), 0)
    stepped = rsp.click_events(rsp.dense_scan(plant_step(x, RATE), RATE, 2 * STEP_AT_S), 0)
    near = [t for t, _, _ in stepped if abs(t - STEP_AT_S) <= 0.005]
    check("S3", not clean and bool(near),
          f"clean sine {len(clean)} events; stepped {[(t, round(r, 2)) for t, _, r in stepped]}")


# ---- the app ---------------------------------------------------------------------


def x0(state):
    try:
        rs.make_fixtures(False)
        ok, detail = rs.z0()
    except Exception as error:  # an instrument that breaks is a FAIL
        ok, detail = False, f"{type(error).__name__}: {error}"
    state["fixtures"] = ok
    check("X0", ok, detail)


def wanted_docs(chosen):
    """{doc: [(preset, tag)…]} the chosen rows need exported."""
    need = {}

    def add(name, *exports):
        need.setdefault(name, [])
        for e in exports:
            if e not in need[name]:
                need[name].append(e)

    if "A1" in chosen:
        for name in ("CX2", "CK05"):
            add(name, *[(p, f"{name}-{p}-{k}") for p in ("audio_wav", "prores_422")
                        for k in (1, 2)])
    if "A2" in chosen:
        add("C", ("audio_wav", "C-audio_wav-1"), ("prores_422", "C-prores_422-1"))
    if "A3" in chosen:
        for name in ("CX1", "CX2", "CK05", "C"):
            add(name, ("audio_wav", f"{name}-audio_wav-1"))
    if "B1" in chosen:
        for name in ("X4S", "X4C"):
            add(name, ("audio_wav", f"{name}-audio_wav-1"), ("prores_422", f"{name}-prores_422-1"))
    if "B2" in chosen:
        add("CK05")
        for name in ("X4S", "X4C"):
            add(name, ("audio_wav", f"{name}-audio_wav-1"))
    if "C1" in chosen or "C2" in chosen:
        add("T335", ("audio_wav", "T335-audio_wav-1"))
    if "C1" in chosen:
        add("CX1", ("audio_wav", "CX1-audio_wav-1"))
    return need


def timeline(doc):
    return max(c["start"] + c["duration"] for c in doc.project()["clips"])


def build_doc(client, name):
    """(doc, timeline ticks) with the document's clips placed."""
    doc = rp.Doc(client, name.lower())
    if name == "C":
        doc.must("set_canvas", width=640, height=360)
        track = doc.project()["tracks"][0]["id"]
        media = doc.must("import_media", path=str(TONE_B))["media"]
        doc.must("add_clip", track=track, media=media, at=C_AT)
        doc.media_duration = next(m["duration"] for m in doc.project()["media"]
                                  if m["id"] == media)
    elif name == "T335":
        doc.canvas()
        _, media = doc.fixture_clip("clicks", T335_A, 1.0, False)
        track = doc.project()["tracks"][0]["id"]
        b = doc.must("add_clip", track=track, media=media, at=T335_A)["new_clips"][0]
        doc.must("trim_start", clip=b, to=T335_A + T335_B_IN)
        doc.must("move_clip", clips=[b], delta=-T335_B_IN)
        doc.must("set_speed", clip=b, rate=2.0, keep_pitch=False)
        doc.must("trim_end", clip=b, to=T335_LENGTH)
        placed = doc.clip(b)
        if (placed["start"], placed["duration"], placed["source"].get("in")) != (
                T335_A, T335_LENGTH - T335_A, T335_B_IN):
            raise RuntimeError(f"T335's B landed as {placed}")
    else:
        fixture, rate, keep = CONSTANTS[name]
        doc.canvas()
        doc.fixture_clip(fixture, LENGTH, rate, keep)
    return doc, timeline(doc)


def run_app(binary, chosen, state):
    log = WORK / "framejob.log"
    launched = mcp.launch(str(binary), env=bounded.child_env(), log_path=str(log),
                          timeout=CALL_BOUND)
    up = launched.client is not None
    try:
        if not up:
            state["app_error"] = f"the app did not listen at {launched.socket_path}"
        else:
            print(f"  instance PID {launched.child.pid} at {launched.socket_path}", flush=True)
            for name, exports in wanted_docs(chosen).items():
                doc = None
                try:
                    doc, length = build_doc(launched.client, name)
                    doc.must("save_project")
                    got = {"package": doc.path, "length": length, "exports": {},
                           "media_duration": getattr(doc, "media_duration", None)}
                    for preset, tag in exports:
                        got["exports"][tag] = doc.export(preset, tag)
                    state.setdefault("docs", {})[name] = got
                    print(f"  {name}: {length} ticks, {len(exports)} exports", flush=True)
                except Exception as error:  # an instrument that breaks is a FAIL
                    state.setdefault("doc_errors", {})[name] = f"{type(error).__name__}: {error}"
                    print(f"  {name}: could not be made: {error}", flush=True)
                finally:
                    if doc is not None:
                        try:
                            doc.close()
                        except OSError:
                            pass
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    found = rp.complaints(log)
    check("D0", up and found == [], f"listening {up}; complaints {found[:5]}")


# ---- the probe -------------------------------------------------------------------


def mix_jobs(state, chosen):
    docs = state.get("docs", {})
    jobs = []

    def job(tag, name, variant):
        if name in docs:
            jobs.append({"name": tag, "project": str(Path(docs[name]["package"]) / "project.json"),
                         "fixture": "clicks", "reads": ["mix"], "length": docs[name]["length"],
                         "mix_variant": variant})

    if "A3" in chosen:
        for name in ("CX1", "CX2", "C"):
            job(f"{name}-app-1", name, "app")
    if "A3" in chosen or "B2" in chosen:
        for k in (1, 2):
            job(f"CK05-app-{k}", "CK05", "app")
    if "B2" in chosen:
        for k in (1, 2):
            job(f"CK05-output_varispeed-{k}", "CK05", "output_varispeed")
        for variant in ("app", "float", "output_varispeed"):
            job(f"X4S-{variant}-1", "X4S", variant)
        job("X4C-app-1", "X4C", "app")
    return jobs


def tap_jobs(state, chosen):
    docs = state.get("docs", {})
    jobs = []
    wanted = [("T335", "post", "C1"), ("T335", "pre", "C2"), ("CX1", "post", "C1"),
              ("CX1", "pre", "C1")]
    for name, flag, row in wanted:
        if row in chosen and name in docs:
            jobs += [{"name": f"{name}-{flag}-{k}", "project": docs[name]["package"],
                      "fixture": "clicks", "reads": ["tap"], "length": docs[name]["length"],
                      "tap_flag": flag} for k in range(1, TIMING_RUNS + 1)]
    return jobs


def render_jobs():
    RENDERS.mkdir(parents=True, exist_ok=True)
    clip, source = rsp.rendered_map(rsp.control_ramp(False, 4.0, LENGTH / SEC), LENGTH)
    return [{"name": "X4S-ideal", "source": str(rs.FIXTURES / rs.FIXTURE_FILES["sine"]),
             "clip_ticks": clip, "source_ticks": source, "keep_pitch": False,
             "destination": str(RENDERS / "X4S-ideal.caf")}]


def run_probe(chosen, state):
    groups = []
    if any(r in chosen for r in ("A3", "B2")):
        groups.append(("export", mix_jobs(state, chosen)))
    if "B2" in chosen:
        groups.append(("render", render_jobs()))
    if "C1" in chosen or "C2" in chosen:
        groups.append(("playback", tap_jobs(state, chosen)))
    groups = [(g, j) for g, j in groups if j]
    if not groups:
        return
    rs.PROBE_DIR.mkdir(parents=True, exist_ok=True)
    binary, why = rp.probe()
    if binary is None:
        state["probe_error"] = why
        return
    PROBE_WORK.mkdir(parents=True, exist_ok=True)
    lines = state.setdefault("lines", {})
    for group, jobs in groups:
        got, why = rs.run_group(binary, group, jobs, work=PROBE_WORK, walls=WALLS)
        (PROBE_WORK / f"{group}-lines.json").write_text(
            json.dumps({f"{n}|{r}": line for (n, r), line in got.items()}))
        lines.update(got)
        if why:
            state.setdefault("probe_errors", []).append(why)
            print(f"  probe {group}: {why}", flush=True)


def line(state, name, read):
    got = state.get("lines", {}).get((name, read))
    return got if got and got.get("ok") else None


def mix_samples(state, name):
    got = line(state, name, "mix")
    return (list(array.array("f", Path(got["path"]).read_bytes())), got) if got else (None, None)


# ---- measuring -------------------------------------------------------------------


def export_path(state, name, tag):
    return state.get("docs", {}).get(name, {}).get("exports", {}).get(tag)


def frames_of(pcm):
    data, channels, _ = pcm
    return len(data) // (4 * channels)


def need(state, names, row):
    missing = [n for n in names if n not in state.get("docs", {})]
    if missing:
        errors = state.get("doc_errors", {})
        check(row, False, f"not made: {[(n, errors.get(n, state.get('app_error'))) for n in missing]}")
        return False
    return True


def a1(state):
    if not need(state, ["CX2", "CK05"], "A1"):
        return
    ok, parts = True, []
    for name in ("CX2", "CK05"):
        target = frames_target(state["docs"][name]["length"])
        for preset in ("audio_wav", "prores_422"):
            pcms = [rp.pcm_of(export_path(state, name, f"{name}-{preset}-{k}")) for k in (1, 2)]
            lengths = [frames_of(p) for p in pcms]
            rates = [p[2] for p in pcms]
            same = pcms[0][0] == pcms[1][0]
            exact = all(n == target for n in lengths) and all(r == RATE for r in rates)
            ok = ok and exact and (same or name != "CX2")
            parts.append(f"{name} {preset} {lengths} of {target} at {rates} Hz, runs "
                         + ("identical" if same else "differ")
                         + (" (reported, SR2b)" if name == "CK05" else ""))
    check("A1", ok, "; ".join(parts))


def a2(state):
    if not need(state, ["C"], "A2"):
        return
    target = frames_target(state["docs"]["C"]["length"])
    parts, ok = [f"toneB's media {state['docs']['C']['media_duration']} ticks"], True
    for preset in ("audio_wav", "prores_422"):
        pcm = rp.pcm_of(export_path(state, "C", f"C-{preset}-1"))
        n = frames_of(pcm)
        ok = ok and n == target and pcm[2] == RATE
        parts.append(f"{preset} {n} frames at {pcm[2]} Hz")
    check("A2", ok, f"timeline {state['docs']['C']['length']} ticks, target {target}; "
                    + "; ".join(parts))


def against_mix(export, mix, target):
    """(ok, detail): A3's rule — equal over min(target, mix) frames, zero after."""
    m = min(target, len(mix))
    differ = next((i for i in range(m) if i >= len(export) or export[i] != mix[i]), None)
    tail = [i for i in range(m, len(export)) if export[i] != 0.0]
    ok = differ is None and not tail and len(export) >= m
    return ok, (f"export {len(export)}, mix {len(mix)}, target {target}: "
                + ("equal" if differ is None else f"differs first at frame {differ}")
                + f" over {m}; {len(tail)} non-zero frames past the mix")


def a3(state):
    if not need(state, ["CX1", "CX2", "C"], "A3"):
        return
    ok, parts = True, []
    for name in ("CX1", "CX2", "C"):
        mix, got = mix_samples(state, f"{name}-app-1")
        if mix is None:
            ok = False
            parts.append(f"{name}: no mix read ({state.get('probe_error') or state.get('probe_errors')})")
            continue
        export, _ = rs.read_channel0(export_path(state, name, f"{name}-audio_wav-1"))
        good, detail = against_mix(export, mix, frames_target(state["docs"][name]["length"]))
        ok = ok and good
        parts.append(f"{name} {detail}")
        if name == "C":
            parts.append(f"C composition {got['composition_ticks']} ticks, range "
                         f"{got['range_ticks']}, audio track ends {got['audio_track_ends']}, "
                         f"timeline {state['docs']['C']['length']}")
    if "CK05" in state.get("docs", {}):
        export, _ = rs.read_channel0(export_path(state, "CK05", "CK05-audio_wav-1"))
        target = frames_target(state["docs"]["CK05"]["length"])
        verdicts = []
        for k in (1, 2):
            mix, _ = mix_samples(state, f"CK05-app-{k}")
            verdicts.append("no read" if mix is None else against_mix(export, mix, target))
        parts.append(f"CK05 (reported): {verdicts}")
    check("A3", ok, "; ".join(parts))


def b1(state):
    if not need(state, ["X4S", "X4C"], "B1"):
        return
    v = rsp.variants()["C-off-x4"]
    ok, parts = True, []
    for preset in ("audio_wav", "prores_422"):
        x, rate = read_ffmpeg(export_path(state, "X4S", f"X4S-{preset}-1"))
        if MUTANT == "plant-step":
            x = plant_step(x, rate)
        events = rsp.click_events(rsp.dense_scan(x, rate, LENGTH / SEC), 0)
        c, crate = read_ffmpeg(export_path(state, "X4C", f"X4C-{preset}-1"))
        placed = rsp.place_ideal(c, crate, v)
        ok = ok and not events and rs.varispeed_pass(placed)
        parts.append(f"{preset}: sine {len(events)} events "
                     f"{[(t, round(r, 2)) for t, _, r in events[:8]]}; clicks "
                     f"{rp.place_text(placed)}, varispeed_pass {rs.varispeed_pass(placed)}")
    report("B1", f"verdict {'pass' if ok else 'fail'} (#334, arm (c): not scored); "
           + "; ".join(parts))


def nearest_boundary(chunks, t_s):
    starts = [c[0] / SEC for c in chunks if c[0] is not None]
    best = min(starts, key=lambda s: abs(s - t_s), default=None)
    return None if best is None else round((t_s - best) * 1000, 3)


def b2(state):
    parts = []
    ck = {}
    for variant in ("app", "output_varispeed"):
        for n in (1, 2):
            ck[f"{variant}-{n}"] = mix_samples(state, f"CK05-{variant}-{n}")[0]
    apps = [ck["app-1"], ck["app-2"]]
    for n in (1, 2):
        ov = ck[f"output_varispeed-{n}"]
        same = [ov is not None and a is not None and ov == a for a in apps]
        parts.append(f"CK05 output_varispeed-{n} {None if ov is None else len(ov)} frames, "
                     f"identical to app-1 {same[0]}, app-2 {same[1]}")
    parts.append(f"CK05 app-1 = app-2 {apps[0] is not None and apps[0] == apps[1]}")
    ideal = None
    path = RENDERS / "X4S-ideal.caf"
    if path.exists():
        ideal, _ = read_ffmpeg(path)
    n = frames_target(LENGTH)
    for variant in ("app", "float", "output_varispeed"):
        mix, got = mix_samples(state, f"X4S-{variant}-1")
        if mix is None:
            parts.append(f"X4S {variant}: no read")
            continue
        events = rsp.click_events(rsp.dense_scan(mix, RATE, LENGTH / SEC), 0)
        near = [nearest_boundary(got["chunks"], t) for t, _, _ in events]
        diff = (max(abs(a - b) for a, b in zip(mix[:n], ideal[:n]))
                if ideal is not None else None)
        parts.append(f"X4S {variant}: {len(mix)} frames, {len(events)} events at "
                     f"{[t for t, _, _ in events]} (ratios "
                     f"{[round(r, 2) for _, _, r in events]}), nearest chunk boundary ms "
                     f"{near}, audio_track_ends {got['audio_track_ends']}, composition "
                     f"{got['composition_ticks']}, max |diff| vs ideal "
                     f"{'—' if diff is None else f'{diff:.6f}'}")
    for name in ("X4S", "X4C"):
        mix, _ = mix_samples(state, f"{name}-app-1")
        tag = f"{name}-audio_wav-1"
        if mix is None or export_path(state, name, tag) is None:
            parts.append(f"{name} export vs app mix: not read")
            continue
        export, _ = rs.read_channel0(export_path(state, name, tag))
        good, detail = against_mix(export, mix, n)
        parts.append(f"{name} export vs app mix {good} ({detail})")
    if state.get("probe_errors"):
        parts.append(f"probe: {state['probe_errors']}")
    report("B2", "; ".join(parts))


def t335_variant():
    segs = [rs.seg(0, T335_A, rs.SOURCE_IN, T335_A),
            rs.seg(T335_A, T335_LENGTH - T335_A, T335_B_IN, 2 * (T335_LENGTH - T335_A))]
    return {"keep": False, "segs": segs, "ref": segs, "length": T335_LENGTH, "kind": "ramp"}


def halves(x, rate, v):
    """(A's, B's) (median offset ms, found, of) of a clicks signal."""
    s = rs.place(x, rate, v)
    expected = [t for _, t, _ in rs.expected_clicks(v)]
    out = []
    for inside in (lambda t: t < T335_A / SEC, lambda t: t >= T335_A / SEC):
        diffs = [(f - t) * 1000 for f, t in zip(s["times"], expected)
                 if inside(t) and f is not None]
        of = sum(1 for t in expected if inside(t))
        out.append((statistics.median(diffs) if diffs else None, len(diffs), of))
    return out


def fmt(h):
    return "—" if h[0] is None else f"{h[0]:+.3f} ms ({h[1]}/{h[2]})"


def cx1_variant():
    segs = [rs.seg(0, LENGTH, rs.SOURCE_IN, LENGTH)]
    return {"keep": False, "segs": segs, "ref": segs, "length": LENGTH, "kind": "control"}


def tap_readings(state, flag, name="T335"):
    v = t335_variant() if name == "T335" else cx1_variant()
    out = []
    for k in range(1, TIMING_RUNS + 1):
        got = line(state, f"{name}-{flag}-{k}", "tap")
        if got is None or not got.get("chunks"):
            raw = state.get("lines", {}).get((f"{name}-{flag}-{k}", "tap"))
            out.append({"error": (raw or {}).get("error") or state.get("probe_error")
                        or state.get("probe_errors") or "no line"})
            continue
        stamped, rate = rs.tap_signal(got, v["length"])
        if name != "T335":
            s = rs.place(stamped, rate, v)
            coarse = rsp.coarse_ms(stamped, rate, {
                "ideal": rsp.control_ramp(False, 1.0, LENGTH / SEC), "length": LENGTH,
                "keep": False})
            out.append({"whole": (s["median_ms"], s["found"], s["of"]), "coarse": coarse})
            continue
        data = list(array.array("f", Path(got["path"]).read_bytes()))
        ordered = by_order(got["chunks"], data, v["length"], rate)
        out.append({"stamp": halves(stamped, rate, v), "order": halves(ordered, rate, v),
                    "rate": rate, "calls": got.get("calls")})
    return out


def c_export(state):
    path = export_path(state, "T335", "T335-audio_wav-1")
    x, rate = read_ffmpeg(path)
    return halves(x, rate, t335_variant())


def cx1_export(state):
    x, rate = read_ffmpeg(export_path(state, "CX1", "CX1-audio_wav-1"))
    s = rs.place(x, rate, cx1_variant())
    return (s["median_ms"], s["found"], s["of"])


def cx1_scored(state, exported):
    """(ok, parts): CX1's product tap (PreEffects; the PostEffects tap under
    `--mutant stamp-place`) within 1.0 ms of CX1's export by stamps and by
    the coarse method, every run; the PostEffects offset printed."""
    product = "post" if MUTANT == "stamp-place" else "pre"
    ok = exported[0] is not None
    parts = [f"CX1 (×1 alone, SR1's C-off-x1 shape) export {fmt(exported)}; product tap "
             f"{'PostEffects (mutant)' if product == 'post' else 'PreEffects'}"]
    for flag in ("pre", "post"):
        for k, r in enumerate(tap_readings(state, flag, "CX1"), 1):
            if "error" in r:
                ok = ok and flag != product
                parts.append(f"CX1 {flag} tap run {k}: {r['error']}")
                continue
            good = (r["whole"][0] is not None and exported[0] is not None
                    and abs(r["whole"][0] - exported[0]) <= A_TOLERANCE_MS
                    and abs(r["coarse"] - exported[0]) <= A_TOLERANCE_MS)
            if flag == product:
                ok = ok and good
            parts.append(f"CX1 {flag} tap run {k}: by stamps {fmt(r['whole'])} (reach 60 ms), "
                         f"coarse {r['coarse']:+.3f} ms (SR2b's method, ±200 ms)"
                         + (f"; scored {good}" if flag == product else "; reported"))
    return ok, parts


def c1(state):
    if not need(state, ["T335", "CX1"], "C1"):
        return
    exported = c_export(state)
    runs = tap_readings(state, "post")
    ok, parts = exported[0][0] is not None and exported[1][0] is not None, []
    parts.append(f"export A {fmt(exported[0])}, B {fmt(exported[1])}")
    for k, r in enumerate(runs, 1):
        if "error" in r:
            ok = False
            parts.append(f"run {k}: {r['error']}")
            continue
        a_scored = r["order"][0]
        b_ok = all(h[1][0] is not None and exported[1][0] is not None
                   and abs(h[1][0] - exported[1][0]) <= B_TOLERANCE_MS
                   for h in (r["stamp"], r["order"]))
        a_ok = (a_scored[0] is not None and exported[0][0] is not None
                and abs(a_scored[0] - exported[0][0]) <= A_TOLERANCE_MS)
        ok = ok and a_ok and b_ok
        parts.append(f"run {k}: A by stamps {fmt(r['stamp'][0])} (#335's reading), by order "
                     f"{fmt(r['order'][0])}; B by stamps {fmt(r['stamp'][1])}, by order "
                     f"{fmt(r['order'][1])}; instrument B {b_ok}; A by order {a_ok}")
    cx_ok, cx_parts = cx1_scored(state, cx1_export(state))
    ok = ok and cx_ok
    parts += cx_parts
    check("C1", ok, "; ".join(parts))


def c2(state):
    if not need(state, ["T335"], "C2"):
        return
    parts = []
    for k, r in enumerate(tap_readings(state, "pre"), 1):
        if "error" in r:
            parts.append(f"run {k}: {r['error']}")
            continue
        parts.append(f"run {k}: A by stamps {fmt(r['stamp'][0])}, by order {fmt(r['order'][0])}; "
                     f"B by stamps {fmt(r['stamp'][1])}, by order {fmt(r['order'][1])}")
    report("C2", "; ".join(parts))


SCORERS = {"A1": a1, "A2": a2, "A3": a3, "B1": b1, "B2": b2, "C1": c1, "C2": c2}


def main():
    global MUTANT
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--app", type=Path, default=None)
    parser.add_argument("--only", default="")
    parser.add_argument("--mutant", choices=MUTANTS, default=None)
    args = parser.parse_args()
    MUTANT = args.mutant
    chosen = [r for r in ROWS if not args.only or r in args.only.split(",")]
    tree_copy.remove_tree(str(WORK))
    WORK.mkdir(parents=True)
    rp.WORK = WORK
    rp.EXPORTS = WORK / "exports"
    started = time.monotonic()
    print("retimed-audio timing (#337, #334, #335)"
          + (f" — mutant {MUTANT}" if MUTANT else ""), flush=True)
    for name, body in (("S1", s1), ("S2", s2), ("S3", s3)):
        if name in chosen:
            body()
    app_rows = [r for r in chosen if r in SCORERS]
    scored = [r for r in chosen if r in ("S1", "S2", "S3")]
    if app_rows:
        binary = args.app or proof_app.binary()
        if not Path(binary).exists():
            print(f"the app is not built: {binary}")
            return 1
        print(f"  app {binary}", flush=True)
        state = {}
        x0(state)                   # always, before the fixtures are used
        scored.append("X0")
        if state.get("fixtures"):
            run_app(binary, app_rows, state)
            scored.append("D0")
            run_probe(app_rows, state)
        for name in app_rows:
            if not state.get("fixtures"):
                check(name, False, "the fixtures are not there (X0)")
                continue
            try:
                SCORERS[name](state)
            except Exception as error:  # a broken instrument is a FAIL, not an exit
                check(name, False, f"the row could not run: {type(error).__name__}: {error}")
        scored += app_rows
    passed = sum(1 for name in scored if rows.get(name))
    print(f"{passed}/{len(scored)} in {time.monotonic() - started:.0f} s")
    return 0 if passed == len(scored) else 1


if __name__ == "__main__":
    sys.exit(main())
