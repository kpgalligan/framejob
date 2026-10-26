#!/usr/bin/env python3
"""Issue #336 — an audio track whose only clip has no source, driven against
the built binary over MCP.

An audio track whose only clip's media file is missing ("gone"), or whose
reverse is pending ("pending"), holds only empty time in its composition
track. Each shape is exported as `audio_wav` and `prores_422`, alone and
beside a track that sounds, and a missing clip with picture and sound
(`AV.mov`) alone; the constant projects' exports are compared with a
baseline this script writes under `--baseline`.

Rows (every M, R and K clip at 12 s; the timeline is 10 180 000 ticks,
16.967 s):

  D0  the instance listens; `Frame Job: ` never appears in its log (re-read
      at the end).
  X0  CONTROLs: each M document's and V0's `get_project.missing_media` is
      [the copy's id]; each R document's is empty and its `cache/reversed` is
      still a regular file after its exports; every document closes (an R
      document's reverse sheet first, through `cancel_sheet`, which must end
      on `button: "Close"` and `sheet: null`).
  M1  gone toneA alone, `audio_wav`: done, every pcm_f32le sample 0.0, frames
      ≥ control C's `audio_wav` frames − 1024 (owner, 2026-10-24: the length
      is scored against C, and the excess against the timeline reported).
      C's 814,400 frames are its whole timeline, which is 16.967 s rather
      than 17 s because `add_clip` snaps toneB down to whole frames (spec §11
      #337). On a failure the export's reason sentence is printed.
  M2  as M1 with `prores_422` (against C's `prores_422`), which must also
      have a video stream.
  M3  gone on track 1, toneB on track 2, `audio_wav`: PCM identical to C's
      `audio_wav` over min(timeline frames, both lengths); lengths reported
      (#337), not scored.
  M4  as M3 with `prores_422`: audio identical to C's `prores_422` audio, and
      its video md5 C's.
  R1–R4  M1–M4 with "pending" (an empty regular file at `<pkg>/cache/reversed`
      before `set_reversed {reversed: true}` on the present toneA clip, as
      `mixed_audio_proof.py`'s pending-first) in place of "gone".
  V0  a gone copy of `AV.mov` alone at 0, `prores_422`: done, a video
      stream, every audio sample 0.0, audio frames ≥ round(5 × rate) − 1024.
  K1  C (toneB alone on track 1): its `audio_wav` PCM, its `prores_422` PCM
      and video md5 identical to `work/missing-audio-baseline/`'s over the
      common length; a missing baseline is a FAIL. Under `--baseline` the row
      writes the baseline instead.
  K2  as K1 for T (toneA on track 1, toneB on track 2, both present).
  P1  `play_preview {seconds: 2}` on M1's document: `to − from` ≥ 900000
      ticks, the preview plays rather than stalls.

"Gone" is the fixture copied to `work/missing-audio/gone-<pid>.<ext>`,
imported, placed, and the copy then deleted. Fixtures are
`tools/proof/media/toneA.m4a`, `toneB.m4a` and `AV.mov`; an absent one is a
scored FAIL. Needs `ffmpeg` and `ffprobe`.

    env -u RC_ASSEMBLYAI_KEY python3 tools/proof/missing_audio_proof.py [--only IDS] [--baseline] [--app PATH]

It launches one instance of its own (`mcp.launch` on `proof_app.binary()`),
logging to `work/missing-audio/framejob.log`, and stops it by its PID.
`work/missing-audio/` is emptied on each run; `work/missing-audio-baseline/`
is written only by `--baseline`. Exit 0 when every scored row passes, else 1.
"""

import argparse
import json
import os
import shutil
import sys
import time
from array import array
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/missing-audio"
BASELINE = ROOT / "tools/proof/work/missing-audio-baseline"
MEDIA = ROOT / "tools/proof/media"
TONE_A = MEDIA / "toneA.m4a"
TONE_B = MEDIA / "toneB.m4a"
AV_MOV = MEDIA / "AV.mov"
SEC = 600_000
AT = 12 * SEC
TIMELINE = 17 * SEC
SLACK = 1024
CALL_BOUND = 600
PLAY_FLOOR = 900_000
ROWS = ["D0", "X0", "M1", "M2", "M3", "M4", "R1", "R2", "R3", "R4", "V0", "K1", "K2", "P1"]

rows = {}
controls = []   # (ok, what) for X0


def check(row, good, detail=""):
    rows[row] = bool(good)
    print(f"{row} {'pass' if good else 'fail'} — {detail}", flush=True)


def control(good, what):
    controls.append((bool(good), what))
    print(f"  X0 {'ok' if good else 'FAIL'} {what}", flush=True)


def attempt(client, tool, arguments):
    """One MCP call: a refusal or an error is an answer, not an exception."""
    try:
        return {"ok": True, "reply": client.call_with(tool, arguments)}
    except mcp.ToolError as error:
        return {"ok": False, "error": str(error)}


def must(client, tool, arguments):
    got = attempt(client, tool, arguments)
    if not got["ok"]:
        raise RuntimeError(f"{tool} {arguments}: {got['error']}")
    return got["reply"]


def run(argv, seconds=300):
    ran = bounded.run([str(a) for a in argv], seconds)
    if ran["expired"]:
        raise RuntimeError(f"{Path(str(argv[0])).name} ran past {seconds} s and was killed")
    if ran["rc"] != 0:
        raise RuntimeError(f"{Path(str(argv[0])).name} exited {ran['rc']}: "
                           f"{(ran['stderr'] or ran['stdout']).strip()[-300:]}")
    return ran


# ---- one document ---------------------------------------------------------------

class Doc:
    """One project file, every call addressed to it (`ramp_proof.Doc`'s shape)."""

    def __init__(self, client, name):
        self.client = client
        self.name = name
        self.path = str(WORK / f"{name}.framejob")
        must(client, "new_project", {"path": self.path})
        self.must("set_canvas", width=640, height=360)

    def call(self, tool, **arguments):
        return attempt(self.client, tool, dict(arguments, project=self.path))

    def must(self, tool, **arguments):
        return must(self.client, tool, dict(arguments, project=self.path))

    def project(self):
        return self.must("get_project")["project"]

    def missing(self):
        return self.must("get_project").get("missing_media")

    def tracks(self, count):
        """The first `count` track ids, adding the second as `mixed_audio_proof` does."""
        if count > 1 and len(self.project()["tracks"]) < 2:
            self.must("add_track", index=1)
        return [t["id"] for t in self.project()["tracks"]][:count]

    def place(self, path, track, at):
        media = self.must("import_media", path=str(path))["media"]
        clip = self.must("add_clip", track=track, media=media, at=int(at))["new_clips"][0]
        return media, clip

    def gone(self, fixture, track, at):
        """`fixture` copied to `gone-<pid>.<ext>`, imported, placed, the copy deleted."""
        copy = WORK / f"gone-{os.getpid()}{fixture.suffix}"
        shutil.copyfile(fixture, copy)
        try:
            media, clip = self.place(copy, track, at)
        finally:
            copy.unlink(missing_ok=True)
        return media, clip

    def pending(self, track, at):
        """toneA placed and its reverse held PENDING: an empty regular file at
        `cache/reversed` before `set_reversed`, so the render can never write."""
        media, clip = self.place(TONE_A, track, at)
        cache = Path(self.path) / "cache"
        cache.mkdir(parents=True, exist_ok=True)
        self.hold = cache / "reversed"
        self.hold.write_bytes(b"")
        self.must("set_reversed", clip=clip, reversed=True)
        return media, clip

    def export(self, preset):
        """(path, None) for a finished export, or (None, the reason sentence)."""
        out = WORK / f"{self.name}-{preset}.{'wav' if preset == 'audio_wav' else 'mov'}"
        out.unlink(missing_ok=True)
        try:
            self.client.export_with({"project": self.path, "preset": preset, "path": str(out)},
                                    seconds=CALL_BOUND)
        except mcp.ToolError as error:
            return None, str(error)
        if not out.exists():
            return None, f"the export answered done but {out.name} does not exist"
        return out, None

    def close(self):
        got = self.call("close_project", discard=True)
        control(got["ok"], f"{self.name}: close_project succeeds"
                           + ("" if got["ok"] else f" ({got['error']})"))


# ---- measuring ------------------------------------------------------------------

def md5_of(path, stream):
    """The md5 of `path`'s decoded audio (pcm_f32le) or video stream."""
    argv = ["ffmpeg", "-v", "error", "-i", str(path), "-map", f"0:{stream}"]
    argv += (["-c:a", "pcm_f32le"] if stream == "a" else []) + ["-f", "md5", "-"]
    return run(argv)["stdout"].strip().split("=", 1)[-1]


def streams(path):
    probe = run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_type",
                 "-of", "json", str(path)], 120)
    return [s["codec_type"] for s in json.loads(probe["stdout"]).get("streams", [])]


def pcm_of(path):
    """`path`'s decoded audio, interleaved pcm_f32le at its own channels:
    (bytes, channels, rate)."""
    probe = run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
                 "stream=channels,sample_rate", "-of", "json", str(path)], 120)
    found = json.loads(probe["stdout"]).get("streams", [])
    if not found:
        raise RuntimeError(f"{Path(path).name} has no audio stream")
    out = Path(str(path) + ".pcm.f32")
    run(["ffmpeg", "-v", "error", "-y", "-i", str(path), "-map", "0:a:0", "-c:a",
         "pcm_f32le", "-f", "f32le", str(out)])
    data = out.read_bytes()
    out.unlink(missing_ok=True)
    return data, int(found[0]["channels"]), int(found[0]["sample_rate"])


def pcm_compare(got, base, length):
    """`ramp_proof.pcm_compare`: identical over min(round(length × rate), both
    lengths); each length against the timeline reported (#337), not scored."""
    (a, ca, ra), (b, cb, rb) = got, base
    if (ca, ra) != (cb, rb):
        return False, f"{ca} ch {ra} Hz ≠ {cb} ch {rb} Hz"
    width = 4 * ca
    n = round(length / SEC * ra)
    fa, fb = len(a) // width, len(b) // width
    m = min(n, fa, fb)
    same = m > 0 and a[:m * width] == b[:m * width]
    return same, (f"{'=' if same else '≠'} over {m} frames; against the timeline's {n}: run "
                  f"{fa - n:+d}, control {fb - n:+d} (#337, not scored)")


def frames_of(pcm):
    data, channels, _ = pcm
    return len(data) // (4 * channels)


def silent(pcm, seconds, control_frames=None):
    """(ok, detail): every sample 0.0 and frames ≥ the floor — control C's
    frames − SLACK when `control_frames` is given (M1, M2, R1, R2: C's
    export is its whole 16.967 s timeline, toneB snapped down to whole
    frames, #337), else round(seconds × rate) − SLACK."""
    data, channels, rate = pcm
    values = array("f")
    values.frombytes(data[:len(data) - len(data) % 4])
    loud = sum(1 for v in values if v != 0.0)
    peak = max((abs(v) for v in values), default=0.0)
    frames = len(values) // channels
    timeline = round(seconds * rate)
    if control_frames is None:
        floor, against = timeline - SLACK, "the timeline"
    else:
        floor, against = control_frames - SLACK, f"C's {control_frames}"
    ok = loud == 0 and frames >= floor
    return ok, (f"{loud} non-zero samples (peak {peak:.6g}); {frames} frames at {rate} Hz × "
                f"{channels} ch ≥ {floor} ({against} − {SLACK}) {frames >= floor}; against "
                f"the timeline's {timeline}: {frames - timeline:+d} (#337, not scored)")


def score_alone(row, doc, preset, seconds, control_set=None):
    """M1/M2/R1/R2/V0: the export done, (a video stream,) silent and long
    enough. `control_set` given (M1, M2, R1, R2): the floor is C's frames."""
    control_frames = None
    if control_set is not None:
        if preset not in control_set:
            check(row, False, f"control C's {preset} export is not there to measure against")
            return
        control_frames = frames_of(control_set[preset]["pcm"])
    path, why = doc.export(preset)
    if path is None:
        check(row, False, f"the {preset} export failed: {why}")
        return
    try:
        kinds = streams(path)
        video = preset == "audio_wav" or "video" in kinds
        ok, detail = silent(pcm_of(path), seconds, control_frames)
    except Exception as error:  # an unreadable file is a FAIL, not an exit
        check(row, False, f"the {preset} export is done but could not be read: {error}")
        return
    check(row, ok and video, f"{preset} done; streams {kinds}"
                             + ("" if video else " (no video stream)") + f"; {detail}")


def score_pair(row, doc, preset, control_set):
    """M3/M4/R3/R4: the export against C's, audio (and video md5) identical."""
    if control_set is None or preset not in control_set:
        check(row, False, f"control C's {preset} export is not there to compare with")
        return
    path, why = doc.export(preset)
    if path is None:
        check(row, False, f"the {preset} export failed: {why}")
        return
    base = control_set[preset]
    try:
        same, detail = pcm_compare(pcm_of(path), base["pcm"], TIMELINE)
        if preset != "audio_wav":
            video = md5_of(path, "v")
            same = same and video == base["video"]
            detail += f"; video md5 {video} {'=' if video == base['video'] else '≠'} C's"
    except Exception as error:
        check(row, False, f"the {preset} export is done but could not be read: {error}")
        return
    check(row, same, f"{preset} done; audio {detail}")


# ---- documents ------------------------------------------------------------------

def missing_control(doc, media):
    got = doc.missing()
    control(got == [media], f"{doc.name}: get_project's missing_media is the copy's id "
                            f"({got} == {[media]})")


def pending_control(doc):
    got = doc.missing()
    control(not got, f"{doc.name}: get_project has no missing_media ({got})")


def hold_control(doc):
    hold = doc.hold
    held = hold.is_file() and not hold.is_symlink()
    control(held, f"{doc.name}: after its exports cache/reversed is still a regular file "
                  f"({'file' if held else 'directory' if hold.is_dir() else 'absent'})")


def close_sheet(doc):
    """The reverse render's sheet off the window: `cancel_sheet` at most twice,
    the last answering `button: "Close"` and `sheet: null`."""
    last = None
    for _ in range(2):
        got = doc.call("cancel_sheet")
        if not got["ok"]:
            control(False, f"{doc.name}: cancel_sheet refused ({got['error']})")
            return
        last = got["reply"]
        if last.get("button") != "Cancel":
            break
    ok = last.get("button") == "Close" and "sheet" in last and last["sheet"] is None
    control(ok, f"{doc.name}: cancel_sheet ends on button {last.get('button')!r}, "
                f"sheet {last.get('sheet')!r}")


def p1(doc):
    """`play_preview {seconds: 2}`, retried while the preview's build is in flight."""
    deadline = time.monotonic() + 60
    while True:
        got = doc.call("play_preview", seconds=2)
        if got["ok"] or "nothing to play" not in got["error"] or time.monotonic() > deadline:
            break
        time.sleep(0.5)
    if not got["ok"]:
        check("P1", False, f"play_preview refused: {got['error']}")
        return
    answer = got["reply"]
    span = answer["to"] - answer["from"]
    check("P1", span >= PLAY_FLOOR, f"from {answer['from']} to {answer['to']}: {span} ticks "
                                    f"≥ {PLAY_FLOOR}; {answer.get('frames_composed')} of "
                                    f"{answer.get('frames_expected')} frames composed")


def control_exports(doc):
    """{preset: {"pcm": pcm_of, "video": md5 or None, "path": path}}; a failed
    export is left out."""
    got = {}
    for preset in ("audio_wav", "prores_422"):
        path, why = doc.export(preset)
        if path is None:
            print(f"  {doc.name}: the {preset} export failed: {why}", flush=True)
            continue
        got[preset] = {"pcm": pcm_of(path), "path": path,
                       "video": None if preset == "audio_wav" else md5_of(path, "v")}
    return got


def write_baseline(tag, exports):
    BASELINE.mkdir(parents=True, exist_ok=True)
    table = {}
    for preset, e in exports.items():
        data, channels, rate = e["pcm"]
        (BASELINE / f"{tag}-{preset}.f32").write_bytes(data)
        table[preset] = {"channels": channels, "rate": rate, "video": e["video"]}
    (BASELINE / f"{tag}.json").write_text(json.dumps(table, indent=1))
    return table


def score_baseline(row, tag, exports, writing):
    if writing:
        if set(exports) != {"audio_wav", "prores_422"}:
            check(row, False, f"{tag}'s exports did not both finish ({sorted(exports)}); "
                              f"no baseline written")
            return
        table = write_baseline(tag, exports)
        check(row, True, f"--baseline: {tag} written to {BASELINE} ({table})")
        return
    table_file = BASELINE / f"{tag}.json"
    if not table_file.exists():
        check(row, False, f"no baseline at {table_file} (run --baseline first)")
        return
    table = json.loads(table_file.read_text())
    good, details = True, []
    for preset in ("audio_wav", "prores_422"):
        if preset not in exports:
            good = False
            details.append(f"{preset} export failed")
            continue
        base = table[preset]
        data = (BASELINE / f"{tag}-{preset}.f32").read_bytes()
        same, detail = pcm_compare(exports[preset]["pcm"],
                                   (data, base["channels"], base["rate"]), TIMELINE)
        details.append(f"{preset} audio {detail}")
        good = good and same
        if preset != "audio_wav":
            video = exports[preset]["video"]
            details.append(f"video md5 {video} {'=' if video == base['video'] else '≠'} "
                           f"baseline")
            good = good and video == base["video"]
    check(row, good, f"{tag}: " + "; ".join(details))


def guarded(rows_named, body):
    """Run one document's rows; an instrument that breaks fails its rows."""
    try:
        body()
    except Exception as error:  # a broken instrument is a FAIL, not an exit
        for name in rows_named:
            if name not in rows:
                check(name, False, f"the row could not run: {type(error).__name__}: {error}")


def run_rows(client, chosen, writing):
    want = set(chosen)
    found = {"C": None}

    def doc_c():
        c = Doc(client, "C")
        (track,) = c.tracks(1)
        c.place(TONE_B, track, AT)
        found["C"] = control_exports(c)
        if "K1" in want:
            score_baseline("K1", "C", found["C"], writing)
        c.close()

    if want & {"K1", "M1", "M2", "M3", "M4", "R1", "R2", "R3", "R4"}:
        guarded(["K1"] if "K1" in want else [], doc_c)

    if want & {"M1", "M2", "P1"}:
        def m_alone():
            d = Doc(client, "M-alone")
            (track,) = d.tracks(1)
            media, _ = d.gone(TONE_A, track, AT)
            missing_control(d, media)
            if "M1" in want:
                score_alone("M1", d, "audio_wav", 17, found["C"] or {})
            if "M2" in want:
                score_alone("M2", d, "prores_422", 17, found["C"] or {})
            if "P1" in want:
                p1(d)
            d.close()
        guarded([r for r in ("M1", "M2", "P1") if r in want], m_alone)

    if want & {"M3", "M4"}:
        def m_pair():
            d = Doc(client, "M-pair")
            first, second = d.tracks(2)
            media, _ = d.gone(TONE_A, first, AT)
            d.place(TONE_B, second, AT)
            missing_control(d, media)
            if "M3" in want:
                score_pair("M3", d, "audio_wav", found["C"])
            if "M4" in want:
                score_pair("M4", d, "prores_422", found["C"])
            d.close()
        guarded([r for r in ("M3", "M4") if r in want], m_pair)

    if want & {"R1", "R2"}:
        def r_alone():
            d = Doc(client, "R-alone")
            (track,) = d.tracks(1)
            d.pending(track, AT)
            pending_control(d)
            if "R1" in want:
                score_alone("R1", d, "audio_wav", 17, found["C"] or {})
            if "R2" in want:
                score_alone("R2", d, "prores_422", 17, found["C"] or {})
            hold_control(d)
            close_sheet(d)
            d.close()
        guarded([r for r in ("R1", "R2") if r in want], r_alone)

    if want & {"R3", "R4"}:
        def r_pair():
            d = Doc(client, "R-pair")
            first, second = d.tracks(2)
            d.pending(first, AT)
            d.place(TONE_B, second, AT)
            pending_control(d)
            if "R3" in want:
                score_pair("R3", d, "audio_wav", found["C"])
            if "R4" in want:
                score_pair("R4", d, "prores_422", found["C"])
            hold_control(d)
            close_sheet(d)
            d.close()
        guarded([r for r in ("R3", "R4") if r in want], r_pair)

    if "V0" in want:
        def v0():
            d = Doc(client, "V-alone")
            (track,) = d.tracks(1)
            media, _ = d.gone(AV_MOV, track, 0)
            missing_control(d, media)
            score_alone("V0", d, "prores_422", 5)
            d.close()
        guarded(["V0"], v0)

    if "K2" in want:
        def doc_t():
            t = Doc(client, "T")
            first, second = t.tracks(2)
            t.place(TONE_A, first, AT)
            t.place(TONE_B, second, AT)
            score_baseline("K2", "T", control_exports(t), writing)
            t.close()
        guarded(["K2"], doc_t)


def complaints(log):
    try:
        with open(log, errors="replace") as handle:
            return [line.rstrip() for line in handle if "Frame Job: " in line]
    except OSError as error:
        return [f"the log could not be read: {error}"]


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--app", type=Path, default=None)
    parser.add_argument("--only", default="")
    parser.add_argument("--baseline", action="store_true")
    args = parser.parse_args()
    binary = args.app or proof_app.binary()
    tree_copy.remove_tree(str(WORK))
    WORK.mkdir(parents=True)
    started = time.monotonic()
    only = [r for r in args.only.split(",") if r]
    chosen = [r for r in ROWS[2:] if not only or r in only]
    print(f"#336 — an audio track whose only clip has no source — {binary}"
          + (" — writing the baseline" if args.baseline else ""), flush=True)
    absent = [p for p in (TONE_A, TONE_B, AV_MOV) if not p.exists()]
    log = WORK / "framejob.log"
    up = False
    if absent:
        for name in chosen:
            check(name, False, f"the fixture is missing: {absent[0]}")
    elif not Path(binary).exists():
        for name in chosen:
            check(name, False, f"the app is not built: {binary}")
    else:
        launched = mcp.launch(str(binary), env=bounded.child_env(), log_path=str(log),
                              timeout=CALL_BOUND)
        up = launched.client is not None
        try:
            if not up:
                for name in chosen:
                    check(name, False, f"the app did not listen at {launched.socket_path}")
            else:
                print(f"  instance PID {launched.child.pid} at {launched.socket_path}",
                      flush=True)
                run_rows(launched.client, chosen, args.baseline)
        finally:
            launched.stop()
            mcp.remove_scratch(launched.socket_path)
    bad = [what for ok, what in controls if not ok]
    check("X0", up and not absent and controls and not bad,
          f"{len(controls) - len(bad)}/{len(controls)} controls" + (f"; failed {bad}" if bad else ""))
    found = complaints(log)
    check("D0", up and found == [], f"listening {up}; complaints {found[:5]}")
    scored = ["D0", "X0"] + chosen
    passed = sum(1 for name in scored if rows.get(name))
    print(f"{passed}/{len(scored)} in {time.monotonic() - started:.0f} s")
    return 0 if passed == len(scored) else 1


if __name__ == "__main__":
    sys.exit(main())
