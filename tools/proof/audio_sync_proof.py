#!/usr/bin/env python3
"""Road map "audio-sync", AS-1 (spec §11 SY-1..SY-5) — Clip ▸ Synchronize Audio
and `sync_audio`, over MCP against a running instance, then the probe's rows
over `app/Sources`.

    python3 tools/proof/audio_sync_proof.py <dir>/agent.sock [--only S1,P3,...]
    python3 tools/proof/audio_sync_proof.py [<dir>/agent.sock] --mutants

The instance is the caller's (`proof_app.py launch`; Debug while iterating,
`RC_PROOF_APP=release` for the recorded run). Every package and fixture is
under `tools/proof/work/audio-sync/`; every project is closed (`close_project`,
discard). The only menu item performed is Clip ▸ Synchronize Audio, which
persists nothing.

Fixtures (Python `wave`, 16 kHz mono, seeded): SOURCE, 150 s of irregular
noise and tone bursts over a quiet floor; RECORDER, SOURCE delayed by
d = 50133 samples (3.1333125 s — off the 10 ms bucket grid, and chosen so S1's
and S2's starts sit within 0.01 frame of a whole 30 fps frame), −9 dB, a
one-pole low-pass and seeded noise at −40 dBFS; UNRELATED, the same made from
another seed; DRIFT, SOURCE resampled by k = 1 + 200e-6 (linear
interpolation; recorder bucket m holds source (m·160 − d)·k) and processed as
RECORDER, so the fixture's drift is (1 − 1/k)·1e6 ppm; CAMERA, ffmpeg's mux of
SOURCE (`pcm_s16le`) under `color` video (libx264, 30 fps) into a `.mov`.
Every media's `cache/peaks/<id>.bin` is waited for (60 s) before it is used.

Rows (30 fps; "unchanged" is `get_project`'s project, key-sorted, equal
before and after, and the last undo step not "Synchronize Audio"):
  S1   camera at 10 s, recorder at 0 on a second track: the recorder lands on
       exactly frame 206 (unsnapped 6.8666875 s), the camera unmoved, `moved`
       true and `anchor` the camera; one `undo` names "Synchronize Audio" and
       puts the recorder back at 0.
  S2   camera at 0, recorder at 20 s, `anchor` the recorder: the camera lands
       on exactly frame 694 (unsnapped 23.1333125 s), the recorder unmoved.
  S3   camera and UNRELATED: refused "no matching sound found", unchanged.
  S4   a still (freeze_frame) and the recorder: refused "plays no sound",
       unchanged.
  S5   the recorder's audio disabled: refused "plays no sound", unchanged.
  S6   the recorder at ×2, refused "plays at ×2"; the camera reversed,
       refused "plays reversed"; each unchanged.
  S7   camera and recorder on one track: refused "are on one track",
       unchanged.
  S8   camera at 0, recorder at 0: refused "before the timeline begins",
       unchanged.
  S9   camera trimmed to [10 s, 20 s), recorder front-trimmed to start at
       100 s: refused "would not play at any moment", unchanged.
  S10  camera at 10 s and DRIFT: `drift_ppm` within ±50 of the fixture's;
       S1's `|drift_ppm|` ≤ 50.
  S11  the recorder nested: refused "is a nest", unchanged.
  S12  one clip: refused "needs at least two clips", unchanged.
  S13  S1's call again: `moved` false, `note` "already in sync", no undo step.
  S14  `set_selection` [camera, recorder] then `perform_menu_item ["Clip",
       "Synchronize Audio"]`: the recorder lands where S1's did.
  S15  the catalog row: no `scope`; `clips` (minItems 2, required), `anchor`,
       `project`.
  S16  the recorder's track holds a 2 s text clip ending 1 s after where S1's
       recorder lands, the recorder placed after it: refused "would overlap
       clip M on its track", unchanged, no transition anywhere.
  P1–P6  `audio_sync_probe.swift`, built by `swift_build.build` over
       `app/Sources` (a failed build is a scored FAIL of all six); each row's
       sentence is the probe's.

`--mutants`: the eight below, probe-only. Each copies `app/Sources` under
`work/audio-sync/mutants/<name>/`, applies its edit (its `before` asserted to
occur exactly once), rebuilds the probe (900 s wall) and runs it (240 s wall);
killed when a named row fails; a copy that does not build or answer is a failed
control, never a kill. Exit 0 when every scored row passed (with
`--mutants`, when all eight were killed); 1 otherwise.
"""

import argparse
import array
import json
import math
import os
import random
import re
import shutil
import subprocess
import sys
import time
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof"))
import swift_build  # noqa: E402
from mcp import MCP, ToolError  # noqa: E402

WORK = ROOT / "tools/proof/work/audio-sync"
FIXTURES = WORK / "fixtures"
PROBE = ROOT / "tools/proof/audio_sync_probe.swift"
RATE = 16_000
SECONDS = 150
DELAY = 50_133                       # samples: 3.1333125 s
DRIFT_K = 1 + 200e-6
DRIFT_PPM = (1 - 1 / DRIFT_K) * 1e6  # the fixture's drift, in the proof's sign
SEC = 600_000
FRAME = SEC // 30
BUILD_WALL = 900
RUN_WALL = 240
S_ROWS = [f"S{n}" for n in range(1, 17)]
P_ROWS = [f"P{n}" for n in range(1, 7)]

# name: (the rows it must fail, file, before, after)
MUTANTS = {
    "lag-sign": (["P1"], "AudioSync.swift",
                 "anchor.zero - mover.zero + lagTicks", "anchor.zero - mover.zero - lagTicks"),
    "anchor-inverted": (["P2"], "AudioSync.swift",
                        "if a.start != b.start { return a.start < b.start }",
                        "if a.start != b.start { return a.start > b.start }"),
    "ratio-dropped": (["P4"], "AudioSyncMatch.swift",
                      "\n                && ratio >= AudioSyncMatch.minimumPeakRatio", ""),
    "before-zero-dropped": (["P6"], "AudioSync.swift",
                            "guard start >= 0 else {", "guard start >= 0 || true else {"),
    "overlap-dropped": (["P6"], "AudioSync.swift",
                        "guard overlapStart < overlapEnd else {",
                        "guard overlapStart < overlapEnd || true else {"),
    "same-track-dropped": (["P6"], "AudioSync.swift",
                           "ids.count > 1 else { continue }", "ids.count > 99 else { continue }"),
    "neighbour-dropped": (["P6"], "AudioSync.swift",
                          "start < $0.end && $0.start < end", "false && $0.start < end"),
    "ppm-scale": (["P5"], "AudioSyncMatch.swift", "rate * 1e6", "rate * 1e9"),
}

results = {}


def score(row, ok, detail):
    results[row] = (bool(ok), detail)
    print(f"{row} {'ok' if ok else 'FAIL'} — {detail}", flush=True)


# ---- fixtures ------------------------------------------------------------------


def source_samples(seed):
    """150 s of bursts — noise or a tone, 30–400 ms, gaps of 50–600 ms — over a
    floor at about −66 dBFS."""
    rng = random.Random(seed)
    total = RATE * SECONDS
    out = array.array("d", (rng.gauss(0, 0.0005) for _ in range(total)))
    n = int(rng.uniform(0.05, 0.6) * RATE)
    while n < total:
        length = int(rng.uniform(0.03, 0.4) * RATE)
        level = rng.uniform(0.1, 0.8)
        tone = rng.random() < 0.5
        freq = rng.uniform(200, 2000)
        attack = int(0.004 * RATE)
        for i in range(min(length, total - n)):
            env = level * min(1.0, i / attack) * (1 - 0.6 * i / length)
            value = math.sin(2 * math.pi * freq * i / RATE) if tone else rng.uniform(-1, 1)
            out[n + i] += env * value
        n += length + int(rng.uniform(0.05, 0.6) * RATE)
    return out


def recorded(samples, seed, delay=DELAY, k=1.0):
    """`samples` delayed by `delay` (and read at rate `k`), −9 dB, a one-pole
    low-pass and noise at −40 dBFS."""
    rng = random.Random(seed)
    count = int(len(samples) / k) + delay
    gain = 10 ** (-9 / 20)
    alpha = 0.35
    held = 0.0
    out = array.array("d", bytes(8 * count))
    last = len(samples) - 1
    for n in range(count):
        t = (n - delay) * k
        if t < 0 or t >= last:
            x = 0.0
        else:
            i = int(t)
            f = t - i
            x = samples[i] * (1 - f) + samples[i + 1] * f
        held += alpha * (gain * x - held)
        out[n] = held + rng.gauss(0, 0.01)
    return out


def write_wav(path, samples):
    data = array.array("h", (max(-32767, min(32767, int(round(s * 32767)))) for s in samples))
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())


def fixtures():
    """The five files, written once per tree (the names carry their version)."""
    FIXTURES.mkdir(parents=True, exist_ok=True)
    names = {key: FIXTURES / f"{key}-v1.{ext}" for key, ext in
             [("source", "wav"), ("recorder", "wav"), ("unrelated", "wav"), ("drift", "wav"),
              ("camera", "mov")]}
    if all(p.exists() for p in names.values()):
        return names
    source = source_samples(1)
    write_wav(names["source"], source)
    write_wav(names["recorder"], recorded(source, 2))
    write_wav(names["unrelated"], recorded(source_samples(3), 4))
    write_wav(names["drift"], recorded(source, 5, k=DRIFT_K))
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
         f"color=c=gray:s=320x180:r=30:d={SECONDS}", "-i", str(names["source"]),
         "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "pcm_s16le", "-shortest",
         str(names["camera"])], check=True, timeout=300)
    return names


# ---- one project ---------------------------------------------------------------


class Session:
    def __init__(self, mcp, name, files):
        self.mcp = mcp
        self.files = files
        for stale in WORK.iterdir():
            if re.fullmatch(rf"{re.escape(name)}-\d+\.framejob", stale.name):
                shutil.rmtree(stale)
        self.path = str(WORK / f"{name}-{os.getpid()}.framejob")
        mcp.call("new_project", path=self.path)
        self.op("set_canvas", width=640, height=360, fps=30)
        self.imported = {}

    def op(self, name, **kwargs):
        return self.mcp.call(name, project=self.path, **kwargs)

    def project(self):
        return self.op("get_project")["project"]

    def text(self):
        return json.dumps(self.project(), sort_keys=True)

    def clip(self, clip):
        return {c["id"]: c for c in self.project()["clips"]}[clip]

    def start(self, clip):
        return self.clip(clip)["start"]

    def tracks(self):
        return [t["id"] for t in self.project()["tracks"]]

    def track(self, index):
        while len(self.tracks()) <= index:
            self.mcp.call_with("add_track", {"project": self.path})
        return self.tracks()[index]

    def media(self, key):
        if key in self.imported:
            return self.imported[key]
        media = self.op("import_media", path=str(self.files[key]))["media"]
        peaks = Path(self.path) / "cache" / "peaks" / f"{media}.bin"
        for _ in range(1200):
            if peaks.exists():
                self.imported[key] = media
                return media
            time.sleep(0.05)
        raise RuntimeError(f"{peaks} was never written")

    def place(self, key, at, track_index):
        media = self.media(key)
        return self.op("add_clip", track=self.track(track_index), media=media,
                       at=at)["new_clips"][0]

    def sync(self, **kwargs):
        return self.op("sync_audio", **kwargs)

    def error(self, tool, **kwargs):
        try:
            self.op(tool, **kwargs)
            return None
        except ToolError as error:
            return str(error)

    def last_step(self):
        """The undo stack's top step's name, put back with a redo."""
        try:
            name = self.op("undo")["undone"]
        except ToolError:
            return None
        self.op("redo")
        return name

    def close(self):
        try:
            self.op("close_project", discard=True)
        except ToolError:
            pass


def refused(session, label, words, **kwargs):
    """(ok, detail): sync_audio refused naming `words`, the project unchanged
    and no Synchronize Audio step on the stack."""
    before = session.text()
    message = session.error("sync_audio", **kwargs)
    after = session.text()
    step = session.last_step()
    ok = (message is not None and "Synchronize Audio was refused" in message
          and words in message and before == after and step != "Synchronize Audio")
    flat = " ".join(str(message).split())
    return ok, (f"{label}: {flat[:400]}; unchanged {before == after}; last step {step!r}")


def recorder_row(answer, clip):
    return next((r for r in answer.get("synced", []) if r["clip"] == clip), {})


# ---- the MCP rows --------------------------------------------------------------


def mcp_rows(sock, wanted, files):
    mcp = MCP(sock)
    want = set(wanted)
    s1_drift = None

    if want & {"S1", "S10", "S13", "S14"}:
        a = Session(mcp, "sync-a", files)
        try:
            cam = a.place("camera", 10 * SEC, 0)
            rec = a.place("recorder", 0, 1)
            answer = a.sync(clips=[cam, rec])
            row = recorder_row(answer, rec)
            s1_drift = row.get("drift_ppm")
            landed = a.start(rec)
            undone = a.op("undo")["undone"]
            back = a.start(rec)
            if "S1" in want:
                score("S1", answer.get("moved") is True and answer.get("anchor") == cam
                      and landed == 206 * FRAME and a.start(cam) == 10 * SEC
                      and undone == "Synchronize Audio" and back == 0,
                      f"recorder at {landed} (want {206 * FRAME}, frame 206), camera at "
                      f"{a.start(cam)}, offset {row.get('offset')} (unsnapped "
                      f"{-DELAY / RATE * SEC:.1f}), r {row.get('correlation')}, confidence "
                      f"{row.get('confidence')}; undo {undone!r} → {back}")
            if "S13" in want:
                a.op("redo")
                again = a.sync(clips=[cam, rec])
                step = a.last_step()
                score("S13", again.get("moved") is False and again.get("note") == "already in sync"
                      and step == "Synchronize Audio" and a.start(rec) == 206 * FRAME,
                      f"moved {again.get('moved')}, note {again.get('note')!r}, top step "
                      f"{step!r} (S1's, not a second)")
                a.op("undo")
            if "S14" in want:
                a.op("set_selection", clips=[cam, rec])
                menu = a.op("perform_menu_item", path=["Clip", "Synchronize Audio"])
                score("S14", a.start(rec) == landed == 206 * FRAME
                      and a.start(cam) == 10 * SEC,
                      f"menu → recorder at {a.start(rec)} (S1 {landed}); "
                      f"answer keys {sorted(menu) if isinstance(menu, dict) else menu}")
        finally:
            a.close()

    if "S10" in want:
        h = Session(mcp, "sync-h", files)
        try:
            cam = h.place("camera", 10 * SEC, 0)
            drift = h.place("drift", 0, 1)
            answer = h.sync(clips=[cam, drift])
            row = recorder_row(answer, drift)
            ppm = row.get("drift_ppm")
            ok = (ppm is not None and abs(ppm - DRIFT_PPM) <= 50 and s1_drift is not None
                  and abs(s1_drift) <= 50)
            score("S10", ok, f"drift fixture {ppm} ppm (want {DRIFT_PPM:.2f} ±50), "
                  f"{row.get('drift_ms')} ms, note {row.get('drift_note')!r}, r "
                  f"{row.get('correlation')}, confidence {row.get('confidence')}; S1 {s1_drift} "
                  "ppm (want |·| ≤ 50)")
        finally:
            h.close()

    if "S2" in want or "S12" in want:
        b = Session(mcp, "sync-b", files)
        try:
            cam = b.place("camera", 0, 0)
            rec = b.place("recorder", 20 * SEC, 1)
            if "S12" in want:
                ok, detail = refused(b, "one clip", "needs at least two clips", clips=[cam])
                score("S12", ok, detail)
            if "S2" in want:
                answer = b.sync(clips=[cam, rec], anchor=rec)
                score("S2", answer.get("anchor") == rec and b.start(cam) == 694 * FRAME
                      and b.start(rec) == 20 * SEC,
                      f"camera at {b.start(cam)} (want {694 * FRAME}, frame 694), recorder at "
                      f"{b.start(rec)}, anchor {answer.get('anchor')}, r "
                      f"{recorder_row(answer, cam).get('correlation')}, confidence "
                      f"{recorder_row(answer, cam).get('confidence')}")
        finally:
            b.close()

    if "S3" in want:
        c = Session(mcp, "sync-c", files)
        try:
            cam = c.place("camera", 10 * SEC, 0)
            other = c.place("unrelated", 0, 1)
            ok, detail = refused(c, "unrelated", "no matching sound found", clips=[cam, other])
            score("S3", ok, detail)
        finally:
            c.close()

    if want & {"S4", "S5", "S6"}:
        d = Session(mcp, "sync-d", files)
        try:
            cam = d.place("camera", 10 * SEC, 0)
            rec = d.place("recorder", 0, 1)
            if "S4" in want:
                d.op("freeze_frame", clip=cam, at=12 * SEC, duration=SEC)
                still = next(c["id"] for c in d.project()["clips"]
                             if c["source"]["kind"] == "still")
                ok, detail = refused(d, "still", f"clip {still}: plays no sound",
                                     clips=[still, rec])
                d.op("undo")
                score("S4", ok, detail)
            if "S5" in want:
                d.op("set_enabled", clip=rec, audio=False)
                ok, detail = refused(d, "audio off", f"clip {rec}: plays no sound",
                                     clips=[cam, rec])
                d.op("undo")
                score("S5", ok, detail)
            if "S6" in want:
                d.op("set_speed", clip=rec, rate=2)
                ok1, detail1 = refused(d, "×2", f"clip {rec}: plays at ×2", clips=[cam, rec])
                d.op("undo")
                d.op("set_reversed", clip=cam, reversed=True)
                ok2, detail2 = refused(d, "reversed", f"clip {cam}: plays reversed",
                                       clips=[cam, rec])
                d.op("undo")
                score("S6", ok1 and ok2, f"{detail1}; {detail2}")
        finally:
            d.close()

    if "S7" in want:
        e = Session(mcp, "sync-e", files)
        try:
            cam = e.place("camera", 0, 0)
            rec = e.place("recorder", 160 * SEC, 0)
            ok, detail = refused(e, "one track", "are on one track", clips=[cam, rec])
            score("S7", ok, detail)
        finally:
            e.close()

    if "S8" in want:
        f = Session(mcp, "sync-f", files)
        try:
            cam = f.place("camera", 0, 0)
            rec = f.place("recorder", 0, 1)
            ok, detail = refused(f, "before 0", f"clip {rec}: would have to start",
                                 clips=[cam, rec])
            score("S8", ok and "before the timeline begins" in detail, detail)
        finally:
            f.close()

    if "S9" in want:
        g = Session(mcp, "sync-g", files)
        try:
            cam = g.place("camera", 10 * SEC, 0)
            rec = g.place("recorder", 0, 1)
            g.op("trim_end", clip=cam, to=20 * SEC)
            g.op("trim_start", clip=rec, to=100 * SEC)
            ok, detail = refused(g, "never meet", "would not play at any moment",
                                 clips=[cam, rec])
            score("S9", ok, detail)
        finally:
            g.close()

    if "S11" in want:
        i = Session(mcp, "sync-i", files)
        try:
            cam = i.place("camera", 10 * SEC, 0)
            rec = i.place("recorder", 0, 1)
            nest = i.op("nest", clips=[rec])["new_clips"][0]
            ok, detail = refused(i, "nest", f"clip {nest}: is a nest", clips=[cam, nest])
            score("S11", ok, detail)
        finally:
            i.close()

    if "S15" in want:
        tool = mcp.schemas().get("sync_audio", {})
        schema = tool.get("inputSchema", {})
        props = schema.get("properties", {})
        ok = (set(props) == {"clips", "anchor", "project"} and "scope" not in props
              and schema.get("required") == ["clips"] and props["clips"].get("minItems") == 2
              and props["anchor"].get("type") == "integer"
              and "Synchronize Audio" in tool.get("description", ""))
        score("S15", ok, f"properties {sorted(props)}, required {schema.get('required')}, clips "
              f"minItems {props.get('clips', {}).get('minItems')}")

    if "S16" in want:
        j = Session(mcp, "sync-j", files)
        try:
            cam = j.place("camera", 10 * SEC, 0)
            lane = j.track(1)
            land = 206 * FRAME
            filler = j.op("add_text_clip", track=lane, at=land + SEC - 2 * SEC,
                          duration=2 * SEC)["new_clips"][0]
            rec = j.place("recorder", land + SEC + 2 * FRAME, 1)
            ok, detail = refused(j, "neighbour", f"clip {rec}: would overlap clip {filler} on "
                                 "its track", clips=[cam, rec])
            transitions = [c["id"] for c in j.project()["clips"] if c.get("transition_in")]
            score("S16", ok and not transitions, f"{detail}; transitions {transitions}")
        finally:
            j.close()


# ---- the probe -----------------------------------------------------------------


def probe_rows(sources, here):
    """{row: (ok, detail)} from the probe built over `sources`, or a FAIL of
    every row when it does not build or answer."""
    if here.exists():
        shutil.rmtree(here)
    here.mkdir(parents=True)
    entry = here / "main.swift"
    shutil.copyfile(PROBE, entry)
    binary = here / "audio-sync-probe"
    try:
        swift_build.build(sources=swift_build.app_sources(sources) + [entry], output=binary,
                          timeout=BUILD_WALL)
    except swift_build.SwiftBuildFailed as error:
        why = "the probe did not build: " + "; ".join(error.diagnostics[:6])
        return {row: (False, why) for row in P_ROWS}
    try:
        ran = subprocess.run([str(binary)], capture_output=True, text=True, timeout=RUN_WALL)
    except subprocess.TimeoutExpired:
        return {row: (False, f"no answer within {RUN_WALL} s") for row in P_ROWS}
    (here / "stderr.txt").write_text(ran.stderr)
    try:
        answered = {r["id"]: (r["pass"], r["detail"]) for r in json.loads(ran.stdout)["rows"]}
    except (ValueError, KeyError):
        why = f"no answer (exit {ran.returncode}): {ran.stderr[-300:]}"
        return {row: (False, why) for row in P_ROWS}
    return {row: answered.get(row, (False, "the probe did not answer it")) for row in P_ROWS}


def mutants():
    killed = []
    for name, (named, file, before, after) in MUTANTS.items():
        here = WORK / "mutants" / name
        if here.exists():
            shutil.rmtree(here)
        sources = here / "Sources"
        shutil.copytree(ROOT / "app/Sources", sources)
        path = sources / file
        text = path.read_text()
        if text.count(before) != 1:
            print(f"mutant {name}: CONTROL FAILED — `{before}` found {text.count(before)} times")
            continue
        path.write_text(text.replace(before, after))
        rows = probe_rows(sources, here / "probe")
        why = rows[named[0]][1]
        if why.startswith(("the probe did not build", "no answer")):
            print(f"mutant {name}: CONTROL FAILED — {why[:300]}")
            continue
        failed = [row for row in named if not rows[row][0]]
        others = [row for row in P_ROWS if row not in named and not rows[row][0]]
        caught = len(failed) == len(named)
        if caught:
            killed.append(name)
        print(f"mutant {name}: {'killed' if caught else 'SURVIVED'} — named {named} failed "
              f"{failed}; other rows failing {others}", flush=True)
        for row in named:
            print(f"    {row}: {rows[row][1][:300]}")
    print(f"mutants: {len(killed)}/{len(MUTANTS)} killed")
    return 0 if len(killed) == len(MUTANTS) else 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("socket", nargs="?")
    parser.add_argument("--only", help="comma-separated row ids")
    parser.add_argument("--mutants", action="store_true")
    args = parser.parse_args()
    WORK.mkdir(parents=True, exist_ok=True)
    if args.mutants:
        return mutants()
    wanted = args.only.split(",") if args.only else S_ROWS + P_ROWS
    unknown = [row for row in wanted if row not in S_ROWS + P_ROWS]
    if unknown:
        print("unknown row " + ", ".join(unknown))
        return 2
    s_wanted = [row for row in wanted if row in S_ROWS]
    if s_wanted:
        if not args.socket:
            print("the S rows need the running instance's socket path")
            return 2
        files = fixtures()
        try:
            mcp_rows(args.socket, s_wanted, files)
        except Exception as error:  # an instrument failure is a scored FAIL of the rest
            for row in s_wanted:
                if row not in results:
                    score(row, False, f"not run: {type(error).__name__}: {error}")
    p_wanted = [row for row in wanted if row in P_ROWS]
    if p_wanted:
        rows = probe_rows(ROOT / "app/Sources", WORK / "probe")
        for row in p_wanted:
            score(row, *rows[row])
    passed = sum(1 for row in wanted if results.get(row, (False,))[0])
    print(f"scores: {passed}/{len(wanted)}")
    return 0 if passed == len(wanted) else 1


if __name__ == "__main__":
    sys.exit(main())
