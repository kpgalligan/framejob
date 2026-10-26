#!/usr/bin/env python3
"""#334 option (a), spec §11 SR-28 — a constant Keep pitch off time-scaled
clip's sound is rendered offline through SR-6's `RampAudioRenderer` and played
as one ×1 segment: a render lands, the export has no #334 step and is placed
at +0.000 ms, Keep pitch on and ×1 render nothing, the silent-until-rendered
window is held to `window_ok`, and a render still lands with many cache passes
in flight.

    env -u RC_ASSEMBLYAI_KEY python3 tools/proof/constant_render_proof.py [--selftest]
        [--groups app,window,wedge] [--only IDS] [--runs N] [--app PATH]

The work folder is `tools/proof/work/constant-render-proof/` (untracked):
`docs/` (the C and E documents), `packages/` (the W packages), `window/` (per-run
copies), `wedge/` (U1's packages and documents), `exports/`, `probe-window/`
and `framejob.log`; each run empties it. The long fixtures are #334's spike's,
shared through `constant_render_spike.make_long` in
`tools/proof/work/constant-render/fixtures/`; the 20 s sine and clicks movies are
`ramp_spike.make_fixtures(False)`'s. A constant clip is
`ramp_proof.Doc.fixture_clip`'s: the fixture at 0 from source in 1 s.

One owned instance (`mcp.launch` on `proof_app.binary()`, stopped by its pid)
serves every MCP row of the app, window and wedge groups; no row performs a
menu item or writes a default. The window group's reads are
`ramp_spike_probe.swift`'s `window` read, built as the spike builds it
(`constant_render_spike.probe`), run after the instance has stopped.

S1  (`--selftest`) the E judge passes the clean `ideal_sine(4, n)` over 4 s and
    fails it with a 0.2 step planted at 2 s.
S2  (`--selftest`) the placement judge passes a median of 0.000 ms and fails
    +0.010 and −0.010 ms.
X0  `ramp_spike.make_fixtures(False)`, `z0()` and `make_long()` (instrument).
D0  the instance listened, and `Frame Job: ` never appears in its log.
C1  (app, scored) per ×0.25, ×0.5, ×2, ×4: `fixture_clip("sine", 4 s, N,
    False)` in a fresh document; a `*.caf` lands in `<pkg>/cache/ramp-audio/`
    within C_BOUND_S.
C2  (app, scored) ×2 Keep pitch on and ×1 Keep pitch off, the same way: no
    `*.caf` there C2_WAIT_S after the edit.
E-x0.25, E-x0.5, E-x2, E-x4  (app, scored) the plain `set_speed {rate: N,
    keep_pitch: false}` clip over `ramp_spike.CONTROLS`' C-off length,
    exported `audio_wav` on sine and on clicks and read on channel 0
    (`ramp_spike.read_channel0`): frames == `frames_target(length)`; on sine
    no `sine_events` and max |x − ideal_sine| ≤ MAX_DIFF over [0.05 s,
    D − 0.05 s]; on clicks (`render_spike.place_ideal` against
    `RC-off-x<N>`) every click found, |median| ≤ PLACE_MS and spread ≤
    PLACE_MS.
W-<sine|speech>-x<N>-<10|60>  (window, reported) a long-fixture clip from in
    1 s at ×N, Keep pitch ON, cut to 10 s or 60 s, saved with its cache pass
    settled (no render before); per run a fresh copy, the probe's `window`
    read with `edit: "set_speed"` (×N, Keep pitch off): landed_s, audible_s,
    caf_bytes and their medians over `--runs`.
WOK (window, scored) `constant_render_spike.window_ok` on every W line.
U1  (wedge, scored; Release-only, `reader_wedge_proof`'s reason) per run 20
    `constant_render_spike.w_package`s made with `SETTLE` off (their passes in
    flight, each now a constant Keep pitch off clip queuing its own render),
    then a fresh document with a 60 s long-sine ×2 Keep pitch off clip: a
    `*.caf` lands within U1_BOUND_S, every run.

`--only` names rows (`E` all four E rows, `W` every W row); D0 and X0 always
run. Exit (rule R, `reader_wedge_proof.py`'s): 0 when every scored row
passes, 1 when one fails (an instrument check — X0, D0, the probe build or a
probe crash — is a failure), 2 when not performed (no ffmpeg or ffprobe, no
built app, a stale app). `--selftest` exits 0 when S1 and S2 pass, else 1.
"""

import argparse
import shutil
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof"))
import constant_render_spike as crs  # noqa: E402  (puts ramp_proof's paths in place)
from constant_render_spike import (  # noqa: E402
    LONG, Run, ideal_sine, label, make_long, new_doc, probe, probe_run, settle, sine_events,
    spread, w_package, window_ok)
import ramp_proof as rp  # noqa: E402
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import ramp_spike as rs  # noqa: E402
import reader_wedge_proof  # noqa: E402
import render_spike as rsp  # noqa: E402
import tree_copy  # noqa: E402
from retimed_audio_proof import frames_target  # noqa: E402

WORK = ROOT / "tools/proof/work/constant-render-proof"
DOCS = WORK / "docs"
PACKAGES = WORK / "packages"
WINDOW = WORK / "window"
WEDGE = WORK / "wedge"
EXPORTS = WORK / "exports"
LOG = WORK / "framejob.log"

SEC = crs.SEC
HZ = crs.HZ
RATES = crs.RATES
MEDIA = crs.MEDIA
WINDOW_S = crs.WINDOW_S
RUNS = 3
C_LENGTH = 4 * SEC
C_BOUND_S = 120
C2_WAIT_S = 5
U1_LENGTH = 60 * SEC
U1_BOUND_S = 120
WINDOW_BOUND_S = 120
CALL_BOUND = 600
EDGE_S = crs.EDGE_S
MAX_DIFF = 5e-4
PLACE_MS = 0.005
GROUPS = ["app", "window", "wedge"]
RELEASE_ONLY = reader_wedge_proof.RELEASE_ONLY

ONLY = None


def wanted(name):
    if ONLY is None:
        return True
    return name in ONLY or any(name.startswith(o + "-") for o in ONLY)


# ---- the judges (pure) -----------------------------------------------------------


def judge_sine(x, rate, length):
    """(ok, sentence): frames == target, no step event, max |x − ideal| ≤
    MAX_DIFF over [EDGE_S, D − EDGE_S]."""
    target = frames_target(length)
    length_s = length / SEC
    steps = sine_events(x, length_s)
    lo, hi = int(EDGE_S * HZ), min(len(x), int((length_s - EDGE_S) * HZ))
    worst = max((abs(x[n] - ideal_sine(rate, n)) for n in range(lo, hi)), default=None)
    ok = len(x) == target and not steps and worst is not None and worst <= MAX_DIFF
    return ok, (f"frames {len(x)} of {target}, {len(steps)} step events "
                f"{[round(t, 3) for t, _, _ in steps[:5]]}, max |diff| "
                + ("—" if worst is None else f"{worst:.6f}") + f" (≤ {MAX_DIFF})")


def judge_place(s):
    """(ok, sentence): every click found, |median| ≤ PLACE_MS, spread ≤ PLACE_MS."""
    ok = (s is not None and s["of"] > 0 and s["found"] == s["of"]
          and s["median_ms"] is not None and abs(s["median_ms"]) <= PLACE_MS
          and s["spread_ms"] <= PLACE_MS)
    return ok, ("—" if s is None else rp.place_text(s)) + f" (|median|, spread ≤ {PLACE_MS} ms)"


def judge_clicks(x, rate, length):
    target = frames_target(length)
    s = rsp.place_ideal(x, HZ, rsp.variants()[f"RC-off-{label(rate)}"])
    placed, sentence = judge_place(s)
    return len(x) == target and placed, f"frames {len(x)} of {target}, {sentence}"


def selftest():
    results = []
    length = 4 * SEC
    clean = [ideal_sine(4.0, n) for n in range(frames_target(length))]
    stepped = clean[:2 * HZ] + [v + 0.2 for v in clean[2 * HZ:]]
    good, good_text = judge_sine(clean, 4.0, length)
    bad, bad_text = judge_sine(stepped, 4.0, length)
    results.append(("S1", good and not bad, f"clean: {good_text}; stepped: {bad_text}"))
    base = {"found": 80, "of": 80, "spread_ms": 0.0}
    passes = judge_place(dict(base, median_ms=0.0))[0]
    late = judge_place(dict(base, median_ms=0.010))[0]
    early = judge_place(dict(base, median_ms=-0.010))[0]
    results.append(("S2", passes and not late and not early,
                    f"0.000 ms {passes}; +0.010 ms {late}; −0.010 ms {early}"))
    for row, ok, detail in results:
        print(f"{row} {'pass' if ok else 'fail'} — {detail}", flush=True)
    passed = sum(1 for _, ok, _ in results if ok)
    print(f"{passed}/{len(results)}")
    return 0 if passed == len(results) else 1


# ---- the instrument --------------------------------------------------------------


def x0(run):
    problems, parts = [], []
    try:
        rs.make_fixtures(False)
        ok, detail = rs.z0()
        parts.append(f"z0: {detail}")
        if not ok:
            problems.append(f"z0: {detail}")
        make_long()
        for media in MEDIA:
            rate, channels, duration = crs.probe_stream(LONG[media])
            parts.append(f"{media} {rate} Hz {channels} ch {duration:.3f} s")
            if rate != HZ or duration < 241:
                problems.append(f"{media}: {rate} Hz, {duration} s")
    except Exception as error:  # a broken instrument is a FAIL
        problems.append(f"{type(error).__name__}: {error}")
    run.row("X0", "FAIL" if problems else "ok", "; ".join(problems or parts))
    return not problems


def landed(doc):
    return [n for n in doc.renders() if n.endswith(".caf")]


def constant_doc(client, name, fixture, length, rate, keep):
    """A fresh document holding `fixture_clip(fixture, length, rate, keep)`,
    its cache pass settled: (doc, clip, the monotonic time of the last edit)."""
    doc = new_doc(client, DOCS, name)
    clip, media = doc.fixture_clip(fixture, length, rate, keep)
    edited = time.monotonic()
    settle(doc, media)
    return doc, clip, edited


# ---- the app group ---------------------------------------------------------------


def c1(run, client):
    parts, ok = [], True
    for rate in RATES:
        doc = None
        try:
            doc, _, edited = constant_doc(client, f"C1-{label(rate)}", "sine", C_LENGTH, rate,
                                          False)
            got = []
            while time.monotonic() - edited < C_BOUND_S:
                got = landed(doc)
                if got:
                    break
                time.sleep(0.05)
            took = time.monotonic() - edited
            ok = ok and bool(got)
            parts.append(f"{label(rate)} " + (f"landed {took:.2f} s: {got[0]}" if got else
                                              f"no .caf within {C_BOUND_S} s ({doc.renders()})"))
        except Exception as error:  # an instrument that breaks fails the row
            ok = False
            parts.append(f"{label(rate)}: {type(error).__name__}: {error}")
        finally:
            if doc is not None:
                doc.close()
    run.row("C1", "ok" if ok else "FAIL", "; ".join(parts))


def c2(run, client):
    parts, ok = [], True
    for rate, keep in ((2.0, True), (1.0, False)):
        name = f"{label(rate)}-{'keep' if keep else 'off'}"
        doc = None
        try:
            doc, _, edited = constant_doc(client, f"C2-{name}", "sine", C_LENGTH, rate, keep)
            time.sleep(max(0.0, C2_WAIT_S - (time.monotonic() - edited)))
            got = landed(doc)
            ok = ok and not got
            parts.append(f"{name}: {len(got)} .caf after {C2_WAIT_S} s {doc.renders()}")
        except Exception as error:  # an instrument that breaks fails the row
            ok = False
            parts.append(f"{name}: {type(error).__name__}: {error}")
        finally:
            if doc is not None:
                doc.close()
    run.row("C2", "ok" if ok else "FAIL", "; ".join(parts))


def e_row(run, client, rate):
    row = f"E-{label(rate)}"
    length = round(rs.CONTROLS[f"C-off-{label(rate)}"][2] * SEC)
    parts, ok = [], True
    for fixture in ("sine", "clicks"):
        doc = None
        try:
            doc, _, _ = constant_doc(client, f"{row}-{fixture}", fixture, length, rate, False)
            path = doc.export("audio_wav", f"{row}-{fixture}")
            doc.close()
            doc = None
            x, _ = rs.read_channel0(Path(path))
            judge = judge_sine if fixture == "sine" else judge_clicks
            good, sentence = judge(x, rate, length)
            ok = ok and good
            parts.append(f"{fixture}: {sentence}")
        except Exception as error:  # an instrument that breaks fails the row
            ok = False
            parts.append(f"{fixture}: {type(error).__name__}: {error}")
        finally:
            if doc is not None:
                doc.close()
    run.row(row, "ok" if ok else "FAIL", "; ".join(parts))


def app_rows(run, client):
    if wanted("C1"):
        c1(run, client)
    if wanted("C2"):
        c2(run, client)
    for rate in RATES:
        if wanted(f"E-{label(rate)}"):
            e_row(run, client, rate)


# ---- the window group: its packages (instance) and reads (probe) -----------------


def w_name(media, rate, length_s):
    return f"W-{media}-{label(rate)}-{length_s}"


def keep_on_package(client, media, rate, length_s):
    """A pristine W package: the long fixture from in 1 s at ×rate, Keep pitch
    ON, cut to `length_s`, settled and saved: its {package, clip}."""
    name = w_name(media, rate, length_s)
    doc = new_doc(client, PACKAGES, name)
    try:
        media_id = doc.must("import_media", path=str(LONG[media]))["media"]
        settle(doc, media_id)
        track = doc.project()["tracks"][0]["id"]
        clip = doc.must("add_clip", track=track, media=media_id, at=0)["new_clips"][0]
        doc.must("trim_start", clip=clip, to=crs.SOURCE_IN)
        doc.must("move_clip", clips=[clip], delta=-crs.SOURCE_IN)
        doc.must("set_speed", clip=clip, rate=rate, keep_pitch=True)
        doc.must("trim_end", clip=clip, to=length_s * SEC)
        placed = doc.clip(clip)
        if (placed["start"], placed["duration"], placed["source"].get("in")) != (
                0, length_s * SEC, crs.SOURCE_IN):
            raise RuntimeError(f"the clip landed as {placed}")
        doc.must("save_project")
        return name, {"package": doc.path, "clip": clip, "speed": rate}
    finally:
        doc.close()


def w_packages(run, client):
    made, errors = {}, []
    for media in MEDIA:
        for rate in RATES:
            for length_s in WINDOW_S:
                if not wanted(w_name(media, rate, length_s)) and not wanted("WOK"):
                    continue
                try:
                    name, got = keep_on_package(client, media, rate, length_s)
                    made[name] = got
                except Exception as error:  # an instrument that breaks is a FAIL
                    errors.append(f"{w_name(media, rate, length_s)}: "
                                  f"{type(error).__name__}: {error}")
    if errors:
        run.row("WP", "FAIL", "; ".join(errors[:6]))
    print(f"  {len(made)} W packages", flush=True)
    return made


def window_rows(run, binary, runs, packages):
    WINDOW.mkdir(parents=True, exist_ok=True)
    jobs, rows = [], {}
    for k in range(1, runs + 1):
        for name, made in packages.items():
            copy = WINDOW / f"{name}-{k}.framejob"
            shutil.rmtree(copy, ignore_errors=True)
            shutil.copytree(made["package"], copy)
            shutil.rmtree(copy / "cache" / "ramp-audio", ignore_errors=True)
            jobs.append({"name": f"{name}-{k}", "project": str(copy), "clip": made["clip"],
                         "edit": "set_speed", "speed": made["speed"],
                         "bound_s": WINDOW_BOUND_S})
            rows.setdefault(name, []).append(f"{name}-{k}")
    lines = probe_run(run, binary, "window", "window", jobs)
    bad = []
    for row, names in rows.items():
        got = []
        for n in names:
            line = lines.get((n, "window"))
            if line is None:
                bad.append(f"{n}: no line")
                continue
            line = dict(line, bound_s=WINDOW_BOUND_S)
            ok, why = window_ok(line)
            if not ok:
                bad.append(f"{n}: {why}")
            got.append(line)
        fields = {f: [line.get(f) for line in got] for f in ("landed_s", "audible_s", "caf_bytes")}
        med = {f: spread(v) for f, v in fields.items()}

        def rounded(values):
            return [None if v is None else round(v, 3) for v in values]

        audible = (med["audible_s"] or {}).get("median")
        landed_med = (med["landed_s"] or {}).get("median")
        run.row(row, "reported",
                f"landed {rounded(fields['landed_s'])} s (median "
                f"{'—' if landed_med is None else f'{landed_med:.3f}'}), audible "
                f"{rounded(fields['audible_s'])} s (median "
                f"{'—' if audible is None else f'{audible:.3f}'}), caf {fields['caf_bytes']} "
                f"bytes over {len(got)} runs", median=med, **fields)
    run.row("WOK", "FAIL" if bad else "ok",
            "; ".join(bad[:10]) if bad else f"window_ok holds for all {len(jobs)} lines")


# ---- the wedge group -------------------------------------------------------------


def u1(run, client, runs):
    """Per run, 20 unsettled W packages, then a fresh 60 s long-sine ×2 Keep
    pitch off clip: the seconds until its `.caf` lands."""
    kept = crs.SETTLE
    crs.SETTLE = False
    seconds, problems = [], []
    try:
        for k in range(1, runs + 1):
            folder = WEDGE / f"run-{k}"
            made = 0
            for media in MEDIA:
                for rate in list(RATES) + [None]:
                    for length_s in WINDOW_S:
                        w_package(client, media, rate, length_s, folder=folder)
                        made += 1
            doc = new_doc(client, folder, "U1")
            try:
                crs.long_clip(doc, LONG["sine"], U1_LENGTH, 2.0)
                started = time.monotonic()
                got = []
                while time.monotonic() - started < U1_BOUND_S:
                    got = landed(doc)
                    if got:
                        break
                    time.sleep(0.05)
                took = time.monotonic() - started
                if got:
                    seconds.append(took)
                else:
                    problems.append(f"run {k}: no .caf within {U1_BOUND_S} s after {made} "
                                    f"packages ({doc.renders()})")
            finally:
                doc.close()
    except Exception as error:  # an instrument that breaks fails the row
        problems.append(f"{type(error).__name__}: {error}")
    finally:
        crs.SETTLE = kept
    run.row("U1", "FAIL" if problems else "ok",
            f"landed {[round(s, 3) for s in seconds]} s over {len(seconds)} of {runs} runs "
            f"(spread {spread(seconds)}; bound {U1_BOUND_S} s)"
            + (f"; {'; '.join(problems[:4])}" if problems else ""), seconds=seconds)


# ---- main ------------------------------------------------------------------------


def instance_phase(run, binary, chosen, runs):
    """The app rows, the W packages and U1 on one owned instance; the W
    packages made (empty when the window group is not chosen)."""
    packages = {}
    launched = mcp.launch(str(binary), env=bounded.child_env(), log_path=str(LOG),
                          timeout=CALL_BOUND)
    up = launched.client is not None
    try:
        if not up:
            run.row("APP", "FAIL", f"the app did not listen at {launched.socket_path}")
        else:
            client = launched.client
            print(f"  instance PID {launched.child.pid} at {launched.socket_path}", flush=True)
            if "app" in chosen:
                print("-- app", flush=True)
                app_rows(run, client)
            if "window" in chosen:
                print("-- window packages", flush=True)
                packages = w_packages(run, client)
            if "wedge" in chosen and wanted("U1"):
                print("-- wedge", flush=True)
                u1(run, client, runs)
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    found = rp.complaints(LOG)
    run.row("D0", "ok" if up and not found else "FAIL",
            f"listening {up}; complaints {found[:5]}")
    return packages


def main():
    global ONLY
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--groups", default=",".join(GROUPS))
    parser.add_argument("--only", default=None)
    parser.add_argument("--runs", type=int, default=RUNS)
    parser.add_argument("--app", type=Path, default=None)
    args = parser.parse_args()
    if args.selftest:
        return selftest()
    ONLY = set(args.only.split(",")) if args.only else None
    chosen = [g for g in GROUPS if g in args.groups.split(",")]
    if not all(shutil.which(t) for t in ("ffmpeg", "ffprobe")):
        print("not performed: ffmpeg and ffprobe are needed")
        return 2
    try:
        binary = args.app or (proof_app.binary(release_only=RELEASE_ONLY) if "wedge" in chosen
                              else proof_app.binary())
    except ValueError as error:
        print(f"not performed: {error}")
        return 2
    if not Path(binary).exists():
        print(f"not performed: the app is not built: {binary}")
        return 2
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))
    WORK.mkdir(parents=True, exist_ok=True)
    crs.WORK = WORK            # the probe's work folder (`probe_run`) is this proof's
    rp.EXPORTS = EXPORTS
    started = time.monotonic()
    run = Run()
    print(f"#334 SR-28 constant render — groups {chosen}, {args.runs} runs, app {binary}",
          flush=True)
    try:
        if x0(run):
            packages = {}
            try:
                packages = instance_phase(run, binary, chosen, args.runs)
            except proof_app.StaleApp as error:
                print(f"not performed: {error}")
                run.not_performed.append(f"app: {error}")
            if "window" in chosen and packages:
                print("-- window", flush=True)
                probe_binary = probe(run)
                if probe_binary is not None:
                    window_rows(run, probe_binary, args.runs, packages)
    except Exception as error:  # a broken instrument is a FAIL, not an exit
        run.row("G", "FAIL", f"{type(error).__name__}: {error}")
    print("\n| row | status |")
    print("|---|---|")
    for name, row in run.rows.items():
        print(f"| {name} | {row['status']} |")
    failed = [name for name, row in run.rows.items() if row["status"] == "FAIL"]
    print(f"{len(run.rows)} rows in {time.monotonic() - started:.0f} s; failed {failed}; "
          f"not performed {run.not_performed}")
    if run.not_performed:
        return 2
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
