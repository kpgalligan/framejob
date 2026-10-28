#!/usr/bin/env python3
"""Issue #378 — `ExportWriter`'s readers, one per output (spec §11 #378, amending G-17):
the MP4/MOV writer reads the video composition output and the audio mix output on an
`AVAssetReader` each, and each pump cancels only its own reader, on its own queue, after its
own last read — CX-15 (2) and (6) applied to `ExportWriter`, as C3 proved them for WebM.

    python3 tools/proof/export_readers_proof.py [--app debug|release|PATH]
    python3 tools/proof/export_readers_proof.py --readers       # R2, R3 alone, no app
    python3 tools/proof/export_readers_proof.py --faults        # F1–F4 alone, on the app
    python3 tools/proof/export_readers_proof.py --mutant NAME

Launches its own instances of the chosen app (`proof_app.py`: `--app`, else
`RC_PROOF_APP`, else Debug; a build older than its inputs is refused) on scratch sockets,
works under `tools/proof/work/export-readers/`, closes every project it opens with
`discard: true` and stops each instance by its own PID. It reuses `av1_export_proof.py`'s
instance, documents, exports and readers, and `webm_export_proof.py`'s projects, chapter
and sound readers, its fault row (`fault_row`) and its readers probe (`readers_rows`).
ffprobe and ffmpeg only READ the files.

Rows (`<ID> ok|FAIL — <detail>`, then `scores: n/m`; exit 0 iff all passed):

* Z1 — every instance's log is silent (no `Frame Job: `, `Svt[` or `SVT-AV1: ` line).
* C1 — A1's project with its two chapters (`webm_export_proof.a1_doc`) exported `h264` on
  an instance launched with `-RCDevExportFault audio@1000000` (a fault that never fires):
  done, 150 decoded frames, 240,000 audio samples, ffprobe's chapters "Intro" 0–2.5 s and
  "Body" 2.5–5 s, and the writer's readers line exactly `video 2, audio 2` (both readers
  read to their end, 2 = completed: a clean export cancels no reader).
* C2 — a project holding only a 5 s text clip, exported `h264` on the same instance: done,
  exactly one stream, and the readers line exactly `video 2, audio none` (a silent movie
  has no audio reader).
* R2, R3 — the measurement behind the change, `webm_readers_probe.swift` (no app; the
  tree's export shaders as its `default.metallib`): A1's project read through
  `ExportWriter`'s two outputs on one reader and on two, each on a thread of its own, from
  builds of their own, at `h264`'s settings — R2 the 16-bit decode, R3 the float mix a
  normalised export reads (8 bytes a frame): 150 frames each, every frame's 64RGBAHalf
  bytes equal, and 240,000 frames of sound equal sample for sample.
* F1–F4 — G-17's windows closed on `ExportWriter`: W9's 24-clip 1080p project
  (`webm_export_proof.long_doc`) exported on an instance launched with
  `-RCDevExportFault` (`ExportWebMDevFault.writerKey`): F1 `audio@40` on `h264` (the audio
  pump fails at its 40th read), F2 `video@30` on `h264` (the video pump fails at its 30th
  append), F3 `audio-hold@40` on `h264` (the audio pump held 3 s at its 40th read, before
  the read, and `cancel_export` sent when the hold's log line appears), F4 the same hold on
  `av1` (whose video pump is `ExportEncodePump`, its reader cancelled by the writer's block
  queued behind the pump's read loop). Each ends — F1 and F2 `failed` naming the dev fault,
  F3 and F4 `cancelled` — within 10 s of the fault's log line (F3, F4: of the cancel), with
  no file at the path, and the writer's `framejob export dev readers:` line reads exactly
  `video 4, audio 4`: both readers cancelled (status 4) by their own pumps, and two readers
  (the line adds ` (one reader)` when the outputs share one).

Mutants (`--mutant NAME`, a tree copy built as Debug with the named anchor replaced, the F
rows alone run; exit 1 and `MUTANT CAUGHT` when exactly the named rows fail):

  shared-reader          the audio output put on the video's reader: F1–F4
  no-own-cancel          the plain pump's own `cancelReading` on a stop dropped: F1–F4
  encode-cancel-dropped  the block that cancels the `av1` row's video reader dropped: F4

An instrument that cannot run is a FAIL, never an exit.
"""

import argparse
import os
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
import av1_export_proof as av1  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import webm_export_proof as webm  # noqa: E402

WORK = HERE / "work" / "export-readers"
av1.WORK = WORK            # the reused Instance and mutant builder work here
FRAMES = 150
SAMPLES = 240_000          # 5 s at 48 kHz
FAULT_KEY = "RCDevExportFault"
FAULTS = {"F1": ("audio@40", "failed", "h264"), "F2": ("video@30", "failed", "h264"),
          "F3": ("audio-hold@40", "cancelled", "h264"),
          "F4": ("audio-hold@40", "cancelled", "av1")}
F_ROWS = list(FAULTS)
READER_ROWS = ("R2", "R3")

SOURCES = "app/Sources"
WRITER = f"{SOURCES}/ExporterWriter.swift"
MUTANTS = {
    "shared-reader": {"rows": F_ROWS, "anchors": [
        (WRITER,
         "            audioReader = hasAudio ? try AVAssetReader(asset: built.composition) : nil\n",
         "            audioReader = hasAudio ? videoReader : nil\n")]},
    "no-own-cancel": {"rows": F_ROWS, "anchors": [
        (WRITER, "            if self?.isStopping ?? true { reader.cancelReading() }\n",
         "            if self?.isStopping ?? true && false { reader.cancelReading() }\n")]},
    "encode-cancel-dropped": {"rows": ["F4"], "anchors": [
        (WRITER,
         "                if let self, self.isStopping { self.videoReader?.cancelReading() }\n",
         "                if let self, self.isStopping && false { self.videoReader?.cancelReading() }\n")]},
}

results = {}


def check(ident, ok, detail):
    results[ident] = bool(ok)
    print(f"{ident} {'ok' if ok else 'FAIL'} — {detail}", flush=True)


def readers_lines(instance):
    """The writer's readers lines so far, each after `readers: `."""
    try:
        lines = instance.log.read_text(errors="replace").splitlines()
    except OSError:
        return []
    return [line.split("readers: ", 1)[1] for line in lines
            if "framejob export dev readers: " in line]


# ---- the rows ----------------------------------------------------------------------

def row_c1(instance, out):
    path = out / "c1.mp4"
    doc = None
    try:
        doc = webm.a1_doc(instance, "c1")
        before = len(readers_lines(instance))
        done = av1.export(doc, path, preset="h264")
        time.sleep(0.5)    # the readers' line precedes the answer; a margin all the same
        readers = readers_lines(instance)[before:]
        frames = av1.decoded_frames(path)
        samples = webm.audio_samples(path)
        listed = webm.chapters(path)
        ok = (done.get("status") == "done" and frames == FRAMES and samples == SAMPLES
              and listed == webm.CHAPTERS and readers == ["video 2, audio 2"])
        check("C1", ok, f"status {done.get('status')}; {frames} frames (want {FRAMES}); "
              f"{samples} audio samples (want {SAMPLES}); chapters {listed} (want "
              f"{webm.CHAPTERS}); readers {readers} (want ['video 2, audio 2'], 2 = completed)")
    except (mcp.ToolError, KeyError, IndexError, ValueError) as error:
        check("C1", False, f"{type(error).__name__}: {error}")
    finally:
        if doc is not None:
            doc.close()


def row_c2(instance, out):
    path = out / "c2.mp4"
    doc = None
    try:
        doc = webm.text_doc(instance, "c2")
        before = len(readers_lines(instance))
        done = av1.export(doc, path, preset="h264")
        time.sleep(0.5)
        readers = readers_lines(instance)[before:]
        seen = [(s.get("codec_type"), s.get("codec_name")) for s in av1.streams(path)]
        ok = (done.get("status") == "done" and len(seen) == 1 and seen[0][0] == "video"
              and readers == ["video 2, audio none"])
        check("C2", ok, f"status {done.get('status')}; streams {seen} (want one, video); "
              f"readers {readers} (want ['video 2, audio none'])")
    except (mcp.ToolError, KeyError, ValueError) as error:
        check("C2", False, f"{type(error).__name__}: {error}")
    finally:
        if doc is not None:
            doc.close()


def run_c_rows(app, logs):
    out = WORK / "out"
    out.mkdir(parents=True, exist_ok=True)
    instance = av1.Instance("c", app, arguments=[f"-{FAULT_KEY}", "audio@1000000"])
    logs.append(instance)
    try:
        if instance.client is None:
            for ident in ("C1", "C2"):
                check(ident, False, f"the app did not listen ({instance.log})")
            return
        row_c1(instance, out)
        row_c2(instance, out)
    finally:
        instance.stop()


def run_reader_rows():
    for ident, ok, detail in webm.readers_rows(READER_ROWS, ROOT / SOURCES,
                                               WORK / "readers-probe"):
        check(ident, ok, detail)


def run_fault_rows(app, logs):
    for ident, (spec, want, preset) in FAULTS.items():
        ok, detail = webm.fault_row(
            ident, app, logs, spec=spec, want=want, preset=preset, word="export",
            default=FAULT_KEY, cancel=spec.startswith("audio-hold"), out=WORK / "out",
            suffix=".mp4")
        check(ident, ok, f"{preset}, {detail}")


# ---- the mutants -------------------------------------------------------------------

def run_mutant(name):
    if name not in MUTANTS:
        print(f"unknown mutant {name}; the mutants are {sorted(MUTANTS)}")
        return 2
    named = sorted(MUTANTS[name]["rows"])
    print(f"mutant {name}: building the copy", flush=True)
    av1.MUTANTS = MUTANTS
    app, copy = av1.build_mutant(name)
    if app is None:
        print(f"mutant {name}: the control could not be performed — {copy}")
        return 2
    logs = []
    try:
        run_fault_rows(app, logs)
    except Exception as error:  # an instrument that cannot run is the control's failure
        print(f"mutant {name}: the control could not be performed — {error}")
        return 2
    failing = sorted(k for k, v in results.items() if not v)
    print(f"mutant {name}: named {named}, failing {failing}")
    if named == failing:
        print(f"MUTANT CAUGHT: {name}")
        return 1
    if not set(named) & set(failing):
        print(f"MUTANT SURVIVED: {name}")
        return 0
    print(f"MUTANT CAUGHT, NOT EXACTLY: {name}")
    return 3


# ---- main --------------------------------------------------------------------------

def scores():
    print(f"scores: {sum(results.values())}/{len(results)}")
    return 0 if all(results.values()) else 1


def main(argv=None):
    parser = argparse.ArgumentParser(description="ExportWriter's readers, one per output (#378)")
    parser.add_argument("--app", help="debug, release or a .app path (default RC_PROOF_APP)")
    parser.add_argument("--mutant", help="one of " + ", ".join(MUTANTS))
    parser.add_argument("--readers", action="store_true",
                        help="R2 and R3 alone: two readers against one, no app")
    parser.add_argument("--faults", action="store_true", help="F1–F4 alone, on the app")
    args = parser.parse_args(argv)
    if args.app:
        os.environ[proof_app.ENV] = args.app
    WORK.mkdir(parents=True, exist_ok=True)
    if args.mutant:
        return run_mutant(args.mutant)
    if args.readers:
        run_reader_rows()
        return scores()
    try:
        app = proof_app.bundle()
        proof_app.require_fresh(proof_app.executable(app))
    except (proof_app.StaleApp, ValueError, OSError) as error:
        check("Z0", False, f"the app cannot be driven: {error}")
        return scores()
    print(f"app {app}", flush=True)
    logs = []
    if args.faults:
        run_fault_rows(app, logs)
        return scores()
    run_c_rows(app, logs)
    run_reader_rows()
    run_fault_rows(app, logs)
    found = [(i.label, line) for i in logs for line in i.complaints()]
    check("Z1", not found, f"{len(logs)} instance logs; complaints {found[:4]}")
    return scores()


if __name__ == "__main__":
    sys.exit(main())
