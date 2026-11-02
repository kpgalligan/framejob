"""Enhance the microphone when it lands, over MCP (road map "audio" AP6 part 3,
spec §11 AU-68, AU-69).

Usage: python3 tools/proof/audio_ap6c_proof.py <dir>/agent.sock

The recorder needs the Microphone grant and a voice, so a recording is handed
to the product's own code after `onFinish` by the dev tool `land_recording`
(AU-69 (e)): door "tool" is record_screen's landing, door "panel" the recorder
panel's `recordingEnded`. Fixtures, in tools/proof/work/audio-ap6c-proof/<pid>/:
a fresh copy of samples/Rode-usb-mic.m4a per leg (so its caches are fresh), a
5 s silent AAC and a 5 s testsrc movie with a 440 Hz track (ffmpeg). Loudness
is phase5_proof's BS.1770 on an exported WAV.

  V1  tool door, new project: the enhance row's clip is segments[0].clip; set
      holds the nine keys (isolation 0.8, a gate); get_project holds set;
      result −16 ±0.5; set equals a control enhance_voice on an imported copy
      (the volume within 0.2 dB); one undo "Enhance Voice" restores the
      landing's audio, then nothing to undo; the landing-to-answer time over 3
      runs.
  V2  tool door into a document: undo "Enhance Voice", then "Add Recording".
  V3  enhance false on both doors: no enhance keys, enhance_pending false, no
      sheet, the audio unchanged after 5 s, undo's top "Add Recording".
  V4  an instance held with -RCDevRampRenderHold 3 and Normalize's target at
      −18, the panel door: (a) new project — the Measuring Sound sheet seen
      (FAIL if never), the audio-only export −18 ±0.5 LUFS, one undo "Enhance
      Voice"; (b) into a document — undo "Enhance Voice" then "Add Recording";
      (c) cancel_sheet during the hold — unchanged, undo's top "Add
      Recording", enhance_pending false, no sheet 2 s and 5 s after.
  V5  movie + microphone: only mic_clip enhanced, the movie clip's sound not
      touched.
  V6  record_screen's refusals, exact, the project byte-identical: enhance
      "yes"; enhance true on a screen with no microphone; voice_over with place
      false; seconds 0 and rate 24 refusing first; source camera.
  V7  a silent file: enhance_error "Nothing could be enhanced. …−70 LUFS…",
      undo's top "Add Recording"; the panel door with follow_wait 30:
      enhance_pending false, the clip untouched.
  V8  record_screen declares enhance (boolean, described); land_recording's
      eight arguments (CU3b's cursor the eighth); follow_wait with door "tool" refused by name; the parity
      log clean.
"""

import json
import os
import shutil
import subprocess
import sys
import time

import mcp as mcp_module
import phase5_proof as p5
import proof_app
from mcp import MCP, ToolError
from phase5_proof import Session, channels, integrated, pcm

import numpy as np

ROOT = os.path.dirname(os.path.dirname(p5.HERE))
RODE = os.path.join(ROOT, "samples", "Rode-usb-mic.m4a")
FIX = os.path.join(p5.WORK, "audio-ap6c-proof", str(os.getpid()))
OWNED = ["compressor", "de_esser", "eq", "gate", "isolation", "leveller", "limiter",
         "noise_reduction", "volume"]
HOLD = 3
MIC_SENTENCE = ("enhance: true enhances the microphone's clip, so it needs microphone: true "
                "(or source voice_over).")
PLACE_SENTENCE = ("enhance: true needs place: true — with place: false the microphone lands as "
                  "media with no clip to enhance.")

checks = 0
failures = []
copies = 0


def check(ok, what):
    global checks
    checks += 1
    print(("  ok   " if ok else "  FAIL ") + what)
    if not ok:
        failures.append(what)
    return ok


def f(x, places=2):
    return "None" if x is None else f"{x:.{places}f}"


# ---- fixtures ---------------------------------------------------------------


def ffmpeg(*args):
    subprocess.run(["ffmpeg", "-v", "error", "-y", *args], check=True)


def fixtures():
    shutil.rmtree(FIX, ignore_errors=True)
    os.makedirs(FIX)
    ffmpeg("-f", "lavfi", "-i", "anullsrc=r=48000:cl=mono", "-t", "5", "-c:a", "aac",
           os.path.join(FIX, "silent.m4a"))
    ffmpeg("-f", "lavfi", "-i", "testsrc=size=640x360:rate=30", "-f", "lavfi", "-i",
           "sine=frequency=440:sample_rate=48000", "-t", "5", "-c:v", "h264_videotoolbox",
           "-b:v", "2M", "-c:a", "aac", "-shortest", os.path.join(FIX, "movie.mov"))


def rode():
    """A fresh copy of the owner's recording under a name of its own, so its
    media and caches are new."""
    global copies
    copies += 1
    path = os.path.join(FIX, f"rode-{copies}.m4a")
    shutil.copyfile(RODE, path)
    return path


# ---- a project by path --------------------------------------------------------


class Doc:
    """An open project addressed by its path (a new project's is its first
    file's)."""

    def __init__(self, client, path):
        self.mcp = client
        self.path = path

    def op(self, name, **kwargs):
        if name == "export":
            return self.mcp.export(project=self.path, **kwargs)
        return self.mcp.call(name, project=self.path, **kwargs)

    def project(self):
        return self.op("get_project")["project"]

    def clip(self, clip):
        return {c["id"]: c for c in self.project()["clips"]}[clip]

    def audio(self, clip):
        return self.clip(clip).get("audio") or {}

    def undo(self):
        try:
            return self.op("undo")["undone"]
        except ToolError as error:
            return str(error)

    def close(self):
        try:
            self.mcp.call("close_project", project=self.path, discard=True)
        except ToolError:
            pass


def close_all(client):
    for _ in range(50):
        try:
            client.call("close_project", discard=True)
        except ToolError:
            return


def touched(audio):
    """The owned keys an audio group carries off their defaults."""
    defaults = {"isolation": 0, "noise_reduction": 0, "volume": 1}
    return sorted(k for k in OWNED if audio.get(k) not in (None, defaults.get(k)))


def clean(value):
    if isinstance(value, dict):
        return {k: clean(v) for k, v in value.items()
                if v is not None and not (k == "bypass" and v is False)}
    return value


def mismatches(held_group, set_, volume_db):
    defaults = {"isolation": 0, "noise_reduction": 0}
    out = []
    for key, value in set_.items():
        held = held_group.get(key)
        if held is None:
            # A key written null (the leveller off) is absent from the held props.
            held = defaults.get(key)
        if key == "volume" and held and value and abs(20 * np.log10(held / value)) <= volume_db:
            continue
        if clean(held) != clean(value):
            out.append(f"{key}: {held!r} against {value!r}")
    return out


def sheet_texts(doc, label):
    picture = os.path.join(FIX, f"{label}.png")
    try:
        shot = doc.op("snapshot_ui", window="sheet", path=picture)
        with open(shot.get("layout_path") or "") as handle:
            views = json.load(handle)["views"]
    except (ToolError, OSError, ValueError, KeyError):
        return []
    return [v.get("text") for v in views if not v.get("hidden") and v.get("text")]


def sheet_up(doc, label):
    return any("Measuring Sound" in t for t in sheet_texts(doc, label))


def wait_sheet(doc, label, bound=90):
    began = time.monotonic()
    while time.monotonic() - began < bound:
        if sheet_up(doc, label):
            return True
        time.sleep(0.2)
    return False


def wait_no_sheet(doc, bound=600):
    began = time.monotonic()
    while time.monotonic() - began < bound:
        listing = doc.op("perform_menu_item")
        if ((listing.get("window") or {}).get("sheet")) is None:
            return time.monotonic() - began
        time.sleep(0.2)
    return None


def export_lufs(doc, label):
    result = doc.op("export", preset="audio_wav", path=os.path.join(FIX, label))
    return integrated(channels(pcm(result["path"])))


# ---- V1 the tool door, a new project --------------------------------------------


def tool_new_project(m):
    print("\nV1 — the tool door, a new project")
    close_all(m)
    voice = rode()
    began = time.monotonic()
    answer = m.call("land_recording", voice=[voice], enhance=True)
    first = time.monotonic() - began
    doc = Doc(m, voice)
    clip = (answer.get("segments") or [{}])[0].get("clip")
    enhance = answer.get("enhance") or {}
    rows = enhance.get("enhanced") or []
    row = rows[0] if rows else {}
    print(f"  note landed {answer.get('landed')}, clip {clip}, enhance_error "
          f"{answer.get('enhance_error')!r}")
    print(f"  note set {json.dumps(row.get('set'), sort_keys=True)}")
    print(f"  note result {f(row.get('result_lufs'))} LUFS, volume {f(row.get('volume'), 4)}, "
          f"renders {row.get('renders')}")
    check(answer.get("landed") == "new_project" and len(rows) == 1 and row.get("clip") == clip,
          f"V1 the enhance row's clip is segments[0].clip ({row.get('clip')} against {clip})")
    set_ = row.get("set") or {}
    check(sorted(set_) == sorted(OWNED) and set_.get("isolation") == 0.8
          and set_.get("gate") is not None,
          f"V1 set holds the nine keys, isolation 0.8 and a gate: {sorted(set_)}")
    held = doc.audio(clip) if clip else {}
    check(not mismatches(held, set_, 1e-6),
          f"V1 get_project holds set: {mismatches(held, set_, 1e-6)}")
    result = row.get("result_lufs")
    check(result is not None and abs(result + 16) <= 0.5, f"V1 result {f(result)} LUFS, −16 ±0.5")
    check(answer.get("project", {}).get("path") == voice,
          f"V1 project read again, the new project's: {answer.get('project', {}).get('path')}")

    # The control: enhance_voice on an imported copy.
    s = Session(m, "ap6c-control")
    media = s.op("import_media", path=rode())["media"]
    control_clip = s.op("add_clip", track=s.project()["tracks"][0]["id"], media=media,
                        at=0)["new_clips"][0]
    for _ in range(6000):
        markers = [os.path.join(s.path, "cache", k, f"{media}.complete.json")
                   for k in ("loudness", "speech")]
        if all(os.path.exists(p) for p in markers):
            break
        time.sleep(0.05)
    control = s.op("enhance_voice", clips=[control_clip])["enhanced"][0]["set"]
    differ = mismatches(control, set_, 0.2)
    check(not differ, f"V1 set equals a control enhance_voice on an imported copy (volume within "
                      f"0.2 dB): {differ or 'equal'}")
    s.op("close_project", discard=True)

    undone = doc.undo()
    after = doc.audio(clip) if clip else {}
    check(undone == "Enhance Voice" and not touched(after),
          f"V1 one undo ({undone!r}) restores the landing's audio: {touched(after)}")
    nothing = doc.undo()
    check("There is nothing to undo" in nothing, f"V1 then nothing to undo: {nothing!r}")
    doc.close()

    times = [first]
    for _ in range(2):
        close_all(m)
        voice = rode()
        began = time.monotonic()
        again = m.call("land_recording", voice=[voice], enhance=True)
        times.append(time.monotonic() - began)
        if "enhance" not in again:
            check(False, f"V1 a timing run enhanced: {again.get('enhance_error')!r}")
        Doc(m, voice).close()
    print(f"  note landing to answer: {', '.join(f'{t:.2f}' for t in times)} s (3 runs)")
    check(len(times) == 3, "V1 three timed runs")


# ---- V2 the tool door, into a document ---------------------------------------


def tool_document(m):
    print("\nV2 — the tool door, into a document")
    s = Session(m, "ap6c-v2")
    answer = m.call("land_recording", voice=[rode()], enhance=True, project=s.path)
    doc = Doc(m, s.path)
    first, second = doc.undo(), doc.undo()
    check("enhance" in answer and first == "Enhance Voice" and second == "Add Recording",
          f"V2 undo {first!r} then {second!r} (enhance error {answer.get('enhance_error')!r})")
    doc.close()


# ---- V3 enhance false -----------------------------------------------------------


def enhance_off(m):
    print("\nV3 — enhance false on both doors")
    for door in ("tool", "panel"):
        s = Session(m, f"ap6c-v3-{door}")
        doc = Doc(m, s.path)
        args = {"voice": [rode()], "project": s.path}
        if door == "panel":
            args["door"] = "panel"
        else:
            args["enhance"] = False
        answer = m.call_with("land_recording", args)
        voice_clips = [c["id"] for c in doc.project()["clips"]]
        landed = {c: doc.audio(c) for c in voice_clips}
        keys = [k for k in ("enhance", "enhance_error") if k in answer]
        pending = answer.get("enhance_pending", False)
        check(not keys and pending is False and voice_clips,
              f"V3 {door}: no enhance keys ({keys}), enhance_pending {pending}")
        check(not sheet_up(doc, f"v3-{door}-0"), f"V3 {door}: no sheet")
        time.sleep(5)
        later = {c: doc.audio(c) for c in voice_clips}
        check(later == landed and not any(touched(a) for a in later.values())
              and not sheet_up(doc, f"v3-{door}-5"),
              f"V3 {door}: the audio is the landing's after 5 s, no sheet: "
              f"{[touched(a) for a in later.values()]}")
        top = doc.undo()
        check(top == "Add Recording", f"V3 {door}: undo's top {top!r}")
        doc.close()


# ---- V4 the panel door under a hold -------------------------------------------


def panel_rows():
    print("\nV4 — the panel door under -RCDevRampRenderHold 3, Normalize's target −18")
    launched = mcp_module.launch(
        proof_app.binary(),
        # A bare "-18" would read as a flag, not a value: the argument domain
        # takes a plist fragment for a number.
        arguments=["-RCDevRampRenderHold", str(HOLD), "-FrameJobNormalizeTargetLUFS",
                   "<real>-18</real>"])
    try:
        if not check(launched.client is not None, "V4 the held instance comes up"):
            return
        h = launched.client
        close_all(h)

        # (a) a new project.
        voice = rode()
        answer = h.call("land_recording", voice=[voice], door="panel", enhance=True,
                        follow_wait=90)
        doc = Doc(h, voice)
        seen = sheet_up(doc, "v4a") or wait_sheet(doc, "v4a", bound=10)
        check(answer.get("landed") == "new_project" and seen,
              f"V4 (a) landed {answer.get('landed')}, the Measuring Sound sheet seen: {seen}")
        gone = wait_no_sheet(doc)
        clip = next(c["id"] for c in doc.project()["clips"])
        set_keys = touched(doc.audio(clip))
        lufs = export_lufs(doc, "v4a-export")
        print(f"  note V4 (a) the sheet gone after {f(gone)} s, the export {f(lufs)} LUFS")
        check(gone is not None and len(set_keys) >= 6 and abs(lufs + 18) <= 0.5,
              f"V4 (a) enhanced ({set_keys}), the audio-only export {f(lufs)} LUFS, −18 ±0.5")
        first, second = doc.undo(), doc.undo()
        check(first == "Enhance Voice" and "There is nothing to undo" in second,
              f"V4 (a) one undo {first!r}, then {second!r}")
        doc.close()

        # (b) into a document.
        s = Session(h, "ap6c-v4b")
        doc = Doc(h, s.path)
        answer = h.call("land_recording", voice=[rode()], door="panel", enhance=True,
                        follow_wait=90, project=s.path)
        seen = sheet_up(doc, "v4b") or wait_sheet(doc, "v4b", bound=10)
        gone = wait_no_sheet(doc)
        first, second = doc.undo(), doc.undo()
        check(answer.get("landed") == "document" and seen and gone is not None
              and first == "Enhance Voice" and second == "Add Recording",
              f"V4 (b) sheet seen {seen}, undo {first!r} then {second!r}")
        doc.close()

        # (c) Cancel during the hold.
        s = Session(h, "ap6c-v4c")
        doc = Doc(h, s.path)
        answer = h.call("land_recording", voice=[rode()], door="panel", enhance=True,
                        follow_wait=90, project=s.path)
        clips = [c["id"] for c in doc.project()["clips"]]
        landed = {c: doc.audio(c) for c in clips}
        seen = sheet_up(doc, "v4c") or wait_sheet(doc, "v4c", bound=10)
        cancelled = {}
        if seen:
            cancelled = doc.op("cancel_sheet")
        time.sleep(2)
        at2 = sheet_up(doc, "v4c-2")
        time.sleep(3)
        at5 = sheet_up(doc, "v4c-5")
        time.sleep(HOLD)
        after = {c: doc.audio(c) for c in clips}
        top = doc.undo()
        check(seen and answer.get("enhance_pending") is False and not at2 and not at5
              and after == landed and top == "Add Recording",
              f"V4 (c) sheet seen {seen}, cancel_sheet {json.dumps(cancelled)[:80]}, "
              f"enhance_pending {answer.get('enhance_pending')}, a sheet at 2 s {at2} and 5 s "
              f"{at5}, unchanged {after == landed}, undo's top {top!r}")
        doc.close()
    finally:
        launched.stop()


# ---- V5 a movie and its microphone ---------------------------------------------


def movie_rows(m):
    print("\nV5 — a movie and its microphone")
    s = Session(m, "ap6c-v5")
    doc = Doc(m, s.path)
    answer = m.call("land_recording", voice=[rode()], movie=os.path.join(FIX, "movie.mov"),
                    enhance=True, project=s.path)
    mic, picture = answer.get("mic_clip"), answer.get("clip")
    rows = (answer.get("enhance") or {}).get("enhanced") or []
    enhanced = [r.get("clip") for r in rows]
    check(mic is not None and enhanced == [mic],
          f"V5 only mic_clip ({mic}) enhanced: {enhanced} (error "
          f"{answer.get('enhance_error')!r})")
    check(picture is not None and not touched(doc.audio(picture)),
          f"V5 the movie clip ({picture})'s sound untouched: "
          f"{touched(doc.audio(picture)) if picture else None}")
    doc.close()


# ---- V6 record_screen's refusals ------------------------------------------------


def refusal_rows(m):
    print("\nV6 — record_screen's refusals")
    s = Session(m, "ap6c-v6")
    before = json.dumps(s.project(), sort_keys=True)
    rows = [
        ({"seconds": 1, "enhance": "yes"}, "enhance must be true or false."),
        ({"seconds": 1, "enhance": True}, MIC_SENTENCE),
        ({"seconds": 1, "source": "voice_over", "place": False, "enhance": True}, PLACE_SENTENCE),
        ({"seconds": 0, "enhance": "yes"}, "seconds must be 1…600 (got 0)."),
        ({"seconds": 1, "rate": 24, "enhance": "yes"}, "rate must be 30 or 60 (got 24)."),
        ({"seconds": 1, "source": "camera", "enhance": True}, MIC_SENTENCE),
    ]
    for args, want in rows:
        try:
            m.call_with("record_screen", {**args, "project": s.path})
            got = "(no refusal)"
        except ToolError as error:
            got = str(error)
        check(got == f"record_screen: {want}", f"V6 {json.dumps(args)}: {got!r}")
    after = json.dumps(s.project(), sort_keys=True)
    check(after == before, "V6 the project is byte-identical")
    s.op("close_project", discard=True)


# ---- V7 a silent file -------------------------------------------------------------


def silent_rows(m):
    print("\nV7 — a silent file")
    silent = os.path.join(FIX, "silent.m4a")
    s = Session(m, "ap6c-v7-tool")
    doc = Doc(m, s.path)
    answer = m.call("land_recording", voice=[silent], enhance=True, project=s.path)
    error = answer.get("enhance_error") or ""
    top = doc.undo()
    check(error.startswith("Nothing could be enhanced.") and "−70 LUFS" in error
          and "enhance" not in answer and top == "Add Recording",
          f"V7 tool: enhance_error {error!r}, undo's top {top!r}")
    doc.close()
    s = Session(m, "ap6c-v7-panel")
    doc = Doc(m, s.path)
    answer = m.call("land_recording", voice=[silent], door="panel", enhance=True, follow_wait=30,
                    project=s.path)
    clips = [c["id"] for c in doc.project()["clips"]]
    untouched = not any(touched(doc.audio(c)) for c in clips)
    top = doc.undo()
    check(answer.get("enhance_pending") is False and clips and untouched
          and top == "Add Recording",
          f"V7 panel: enhance_pending {answer.get('enhance_pending')}, the clip untouched, "
          f"undo's top {top!r}")
    doc.close()


# ---- V8 the catalog and the log -------------------------------------------------


def catalog_rows(m):
    print("\nV8 — the catalog and the log")
    schemas = m.schemas()
    record = (schemas.get("record_screen") or {}).get("inputSchema", {}).get("properties", {})
    enhance = record.get("enhance") or {}
    check(enhance.get("type") == "boolean" and bool(enhance.get("description")),
          f"V8 record_screen declares enhance, boolean and described: {enhance.get('type')}")
    land = (schemas.get("land_recording") or {}).get("inputSchema", {})
    names = sorted(land.get("properties") or {})
    want = sorted(["voice", "movie", "door", "enhance", "place", "project", "follow_wait",
                   "cursor"])
    check(names == want and land.get("required") == ["voice"],
          f"V8 land_recording's eight arguments: {names}, required {land.get('required')}")
    try:
        m.call("land_recording", voice=[os.path.join(FIX, "silent.m4a")], follow_wait=5)
        got = "(no refusal)"
    except ToolError as error:
        got = str(error)
    check("follow_wait" in got and "door" in got, f"V8 follow_wait with door tool refused: {got!r}")
    log = os.path.join(os.path.dirname(p5.SOCKET), "framejob.log")
    with open(log, encoding="utf-8", errors="replace") as handle:
        lines = [line.rstrip() for line in handle if "Frame Job: " in line]
    check(not lines, f"V8 no \"Frame Job: \" line in {log}: {lines[:3]}")


def main():
    os.makedirs(p5.WORK, exist_ok=True)
    fixtures()
    m = MCP(p5.SOCKET)
    # AP6C_ONLY=v1,v4,… runs only those parts while iterating; a recorded run
    # sets nothing and runs them all.
    only = set(filter(None, os.environ.get("AP6C_ONLY", "").split(",")))
    errors = (ToolError, KeyError, IndexError, RuntimeError, OSError, ValueError, TypeError,
              StopIteration)
    parts = (("v1", lambda: tool_new_project(m)), ("v2", lambda: tool_document(m)),
             ("v3", lambda: enhance_off(m)), ("v5", lambda: movie_rows(m)),
             ("v6", lambda: refusal_rows(m)), ("v7", lambda: silent_rows(m)),
             ("v4", panel_rows), ("v8", lambda: catalog_rows(m)))
    for name, part in parts:
        if only and name not in only:
            continue
        try:
            part()
        except errors as error:
            check(False, f"{name} aborted: {type(error).__name__}: {error}")
    print(f"\n{checks - len(failures)}/{checks} checks passed")
    for line in failures:
        print(f"  FAILED: {line}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
