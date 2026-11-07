#!/usr/bin/env python3
"""Docs bugs, batch b3 (#470 #486 #488 #493 #504; spec §11 #470, #486, #504, PR-14): what an export
does and answers, a deep clip above an 8-bit one, and a `.webm` path.

    python3 tools/proof/docs_bugs_b3_proof.py [--only R1,S1,…] [--app PATH] [--base-sources PATH]
                                              [--expect-red] [--mutant NAME]
    RC_PROOF_APP=<the frozen base app> python3 tools/proof/docs_bugs_b3_proof.py \
        --base-sources <a tree at the base>/app/Sources --expect-red
    RC_PROOF_APP=release python3 tools/proof/docs_bugs_b3_proof.py

The built app (`proof_app`'s choice, or `--app`) on a scratch `CFFIXED_USER_HOME` under
`work/docs-bugs-b3/`. `(c)` marks a CONTROL, which passes on the base too; every other row is red on
the frozen base app with `--base-sources` set to the base's `app/Sources`, and `--expect-red` exits 0
only when that holds. The fixtures are made here, so ffmpeg (with libx264, libx265 and prores_ks) and
`sips` are needed at proof time.

- The door, on a 1920×1080 canvas: R1 `gif` of a 60 s timeline over an existing GIF: refused at the
  call, no `export_id`, the sentence ends "Shorten the range.", the file byte-identical. R2
  `hevc_alpha`, `prores_4444`, `vp9_alpha_webm` at `[1000, 1000]` over a file: the same with the shape
  sentence. R3 (c) each at 960×540, `apng` and `h264` at `[1000, 1000]`, a 600-frame GIF: `done`. R4
  (c) good re-exports over an existing file for `h264`, `gif`, `apng`, `vp9_webm`: the new file, no
  `.framejob-replaced-*` or `.framejob-export-*` left.
- S1 `audio_wav` with `stems` over an existing mix, one stem's name a project media: `failed` with the
  stem sentence, the mix byte-identical, the folder listing unchanged: a real pipeline throw, past the
  doors.
- C1 `cancel_export` during `Measuring loudness…` over an existing file: `cancelled`, byte-identical.
  C3 (c) a cancel on a fresh path: nothing there. (C2, a cancel while writing leaving nothing at the
  path, stated the rule spec §11 #531 replaced; `ai_docs_b2_proof.py`'s K1 holds the file now.)
- Depth, `render_frame`, each layout back to front, levels the distinct greens in row 288: D1 H.264
  then HEVC 10. D2 H.264 then ProRes. D3 HEVC 8 then HEVC 10. D4 H.264, H.264, HEVC 10. D5 H.264 at
  0 s, HEVC 10 above at 6 s, the frame at 7 s. Each 16-bit, levels above 256. D6 HEIC of H.264 under
  HEVC 10: 10-bit. D7 a reversed 8-bit clip above H.264: 16-bit. D8 (c) H.264 alone, HEVC 8 alone,
  H.264 under HEVC 8 and H.264 with HEVC 10 at 6 s, t 1 s: 8-bit; HEVC 10 alone and ProRes alone
  16-bit; JPEG 8-bit.
- W1 `h264`, `prores_422`, `gif` at `.webm`, `CUT4.WEBM`, `render_frame` at `shot.webm`: `cut.mp4`,
  `cut2.mov`, `cut3.gif`, `CUT4.mp4`, `shot.png`, answer and disk agreeing. W2 (c) `av1_webm` at
  `cut5.mp4`, `h264` at `cut7.mov`, `render_frame` at `shot2.mov`, `Talk v1.2`.
- The real sheet, `-FrameJobExportChoice` in the argument domain and `snapshot_ui`, one instance a
  card, Export… never pressed: G1 GIF at Project rate: the short sentence. G2 APNG: the same. G3 GIF
  at 24 fps: the clause. G4 `hevc_alpha` at Custom 1000 × 1000: the shape sentence. G5 `prores_4444`
  and `vp9_alpha_webm` the same. G6 (c) a GIF within 600 frames and a Custom size of the canvas's
  shape show the usual readout.
- Probe, `docs_bugs_b3_probe.swift` through `swift_build.build()`, the same source on the base and
  the fix: B1 `exportButton` and `queueButton` off for GIF, GIF at 24 fps and `hevc_alpha` at
  1000 × 1000 on the 60 s project, on for a 3 s GIF and `hevc_alpha` at 960 × 540. B2 `Exporter().export`
  directly, over a file, GIF above the cap and a shape mismatch: the failure sentence, the file
  byte-identical, no aside. PB (c) the general pasteboard's change count is unchanged.
- Z1 (c) `grep "Frame Job: "` on each launch's log prints nothing.

`--mutant NAME`: the named decision broken in a `tree_copy.py` copy, whose app is built and driven
for the named rows and Z1. CAUGHT exits 1 when every named row failed, SURVIVED exits 0, and a control
that could not be performed (the copy did not build, an anchor not found once) exits 2. An instrument
that cannot run is a scored failure, never an exit.
"""

import argparse
import hashlib
import json
import shutil
import struct
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/docs-bugs-b3"
HOME = WORK / "home"
FILES = WORK / "files"
LOGS = WORK / "logs"
OUT = WORK / "probe"
PROBE = HERE / "docs_bugs_b3_probe.swift"
CALL_BOUND = 300
JOB_BOUND = 900         # a machine shared with other builds slows a 1 s job to minutes
LONG_JOB_BOUND = 1800   # 600 full frame renders on a loaded Debug build
BUILD_BOUND = 1500
PROBE_BOUND = 400
REVERSE_BOUND = 180
SEC = 600000
SHORT = "Shorten the range."
CLAUSE = "Shorten the range, or lower the export frame rate."
SHAPE = "An export that keeps transparency has to have the canvas's own shape."
ALPHA = (("hevc_alpha", "mov"), ("prores_4444", "mov"), ("vp9_alpha_webm", "webm"))
ASIDE = ".framejob-replaced-"
SIBLING = ".framejob-export-"

DOOR_ROWS = ["R1", "R2", "R3", "R4"]
STEM_ROWS = ["S1"]
CANCEL_ROWS = ["C1", "C3"]
DEPTH_ROWS = ["D1", "D2", "D3", "D4", "D5", "D6", "D7", "D8"]
PATH_ROWS = ["W1", "W2"]
SHEET_ROWS = ["G1", "G2", "G3", "G4", "G5", "G6"]
PROBE_ROWS = ["B1", "B2", "PB"]
ROWS = (DOOR_ROWS + STEM_ROWS + CANCEL_ROWS + DEPTH_ROWS + PATH_ROWS + SHEET_ROWS + PROBE_ROWS
        + ["Z1"])
CONTROLS = {"R3", "R4", "C3", "D8", "W2", "G6", "PB", "Z1"}

EXPORT = "app/Sources/AgentServer+Export.swift"
SEQUENCE = "app/Sources/ExporterImageSequence.swift"
RESOLVE = "app/Sources/ExportSheetResolve.swift"
FRAME = "app/Sources/Exporter+Frame.swift"
DEEP = "app/Sources/DeepVideoFrame.swift"
DESTINATIONS = "app/Sources/AgentServer+Destinations.swift"
# name: (the rows it must turn red, the edits).
MUTANTS = {
    "no-door": (["R1", "R2"], [(
        EXPORT, "        if let refusal = Exporter.settingsRefusal(settings, project: project) {",
        "        if let refusal = Exporter.settingsRefusal(settings, project: project), false {")]),
    # `no-put-back` and `cancel-removes` were retired with the code they broke (spec §11 #531);
    # `ai_docs_b2_proof.py`'s mutants hold the file now.
    "clause-always": (["R1", "G1"], [(
        SEQUENCE, "+ (aboveOwn ? \", or lower the export frame rate.\" : \".\"))",
        "+ \", or lower the export frame rate.\")")]),
    "no-card-refusal": (["G1", "B1"], [(
        RESOLVE, "        let refusal = writeRefusal(for: settings)\n",
        "        let refusal: String? = nil\n")]),
    "reread-never": (["D1"], [(
        FRAME, "        if keepsDepth, let shallow = image, shallow.bitsPerComponent <= 8,\n",
        "        if false, let shallow = image, shallow.bitsPerComponent <= 8,\n")]),
    "hevc-depth-any": (["D8"], [(
        DEEP, "record[record.startIndex + 17] & 0x07 > 0", "record[record.startIndex + 17] & 0x07 >= 0")]),
    "webm-not-listed": (["W1"], [(
        DESTINATIONS, "\"png\", \"jpg\", \"jpeg\", \"heic\", \"gif\", \"webm\",",
        "\"png\", \"jpg\", \"jpeg\", \"heic\", \"gif\",")]),
}

results = {}
selected = set(ROWS)
logs = []


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'PASS' if ok else 'FAIL'} {name}: {detail}", flush=True)


def attempt(names, body):
    """`body` when any of `names` is selected; an instrument that raises fails them, never exits."""
    if not selected & set(names):
        return
    try:
        body()
    except Exception as error:  # noqa: BLE001
        for name in names:
            check(name, False, f"the row could not run: {error!r}")


# ---- the fixtures -----------------------------------------------------------------------

def ffmpeg(*arguments):
    subprocess.run(["ffmpeg", "-y", "-v", "error", *arguments], check=True, timeout=300)


def fixtures():
    """`repro/make_fixtures.sh`: two 1920×1080 clips with sound, the 1024×576 depth sources, a tone."""
    for name, seconds in (("long60.mov", 60), ("short3.mov", 3)):
        ffmpeg("-f", "lavfi", "-i", f"testsrc2=size=1920x1080:rate=30:duration={seconds}",
               "-f", "lavfi", "-i", f"sine=frequency=440:duration={seconds}", "-pix_fmt", "yuv420p",
               "-c:v", "libx264", "-preset", "ultrafast", "-c:a", "aac", "-shortest",
               str(FILES / name))
    ramp = "nullsrc=size=1024x576:rate=30:duration=4,format=yuv444p10le," \
           "geq=lum='64+X*876/1023':cb=512:cr=512"
    ffmpeg("-f", "lavfi", "-i", ramp, "-pix_fmt", "yuv420p10le", "-c:v", "libx265", "-tag:v", "hvc1",
           "-x265-params", "log-level=error:lossless=0:crf=4", "-profile:v", "main10",
           str(FILES / "hevc10.mov"))
    ffmpeg("-f", "lavfi", "-i", ramp, "-pix_fmt", "yuv422p10le", "-c:v", "prores_ks", "-profile:v",
           "3", str(FILES / "prores.mov"))
    test = "testsrc2=size=1024x576:rate=30:duration=4"
    ffmpeg("-f", "lavfi", "-i", test, "-pix_fmt", "yuv420p", "-c:v", "libx264", "-preset",
           "ultrafast", str(FILES / "h264.mov"))
    ffmpeg("-f", "lavfi", "-i", test, "-pix_fmt", "yuv420p", "-c:v", "libx265", "-tag:v", "hvc1",
           "-x265-params", "log-level=error", str(FILES / "hevc8.mov"))
    ffmpeg("-f", "lavfi", "-i", "sine=frequency=440:duration=2", "-c:a", "pcm_s16le",
           str(FILES / "tone.wav"))


# ---- instances --------------------------------------------------------------------------

def start(binary, label, arguments=()):
    log = LOGS / f"{label}.log"
    logs.append(log)
    env = bounded.child_env({"CFFIXED_USER_HOME": str(HOME)})
    launched = mcp.launch(str(binary), list(arguments), env=env, log_path=str(log),
                          timeout=CALL_BOUND)
    print(f"  {label}: instance PID {launched.child.pid}", flush=True)
    return launched


def parity():
    lines = []
    for log in logs:
        try:
            lines += [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
        except OSError:
            lines.append(f"{log} could not be read")
    check("Z1", bool(logs) and not lines,
          f"grep 'Frame Job: ' over {len(logs)} logs printed {lines[:3] or 'nothing'}")


class Project:
    """One new project in an instance; every call names it."""

    def __init__(self, client, name, media=(), canvas=None):
        self.client = client
        self.folder = WORK / f"out-{name}"
        self.folder.mkdir(parents=True, exist_ok=True)
        self.path = str(WORK / f"{name}.framejob")
        client.call_with("new_project", {"path": self.path})
        if canvas:
            self.op("set_canvas", width=canvas[0], height=canvas[1])
        self.media = {str(path): self.op("import_media", path=str(path))["media"] for path in media}

    def op(self, tool, **arguments):
        return self.client.call_with(tool, dict(arguments, project=self.path))

    def state(self):
        return self.op("get_project")["project"]

    def tracks(self):
        return [track["id"] for track in self.state()["tracks"]]

    def place(self, path, track=None, at=0):
        track = self.tracks()[0] if track is None else track
        return self.op("add_clip", track=track, media=self.media[str(path)],
                       at=round(at * SEC))["new_clips"][0]

    def close(self):
        self.op("close_project", discard=True)


def digest(path):
    path = Path(path)
    return hashlib.sha256(path.read_bytes()).hexdigest()[:12] if path.is_file() else None


def listing(folder):
    return sorted(entry.name for entry in Path(folder).iterdir())


def follow(client, export_id, bound=JOB_BOUND):
    """The job's last `export_status`, polled every 0.1 s."""
    began = time.monotonic()
    while True:
        status = client.call_with("export_status", {"export_id": export_id})
        if status.get("status") in ("done", "failed", "cancelled"):
            return status
        if time.monotonic() - began > bound:
            client.call_with("cancel_export", {"export_id": export_id})
            return status
        time.sleep(0.1)


def run_export(project, bound=JOB_BOUND, **arguments):
    """("refused", the sentence) from the call, or (the job's last word, its status), the job ended."""
    try:
        answer = project.op("export", **arguments)
    except mcp.ToolError as error:
        return "refused", str(error)
    status = follow(project.client, answer["export_id"], bound)
    return status.get("status"), status


def made(project, **arguments):
    """A file an export must write: its path, or a raise the row turns into a failure."""
    word, status = run_export(project, **arguments)
    if word != "done":
        raise RuntimeError(f"the fixture export {arguments} ended {word}: {str(status)[:200]}")
    return status["path"]


def door(row, project, want, path, **arguments):
    """Refused at the call in a sentence holding `want`, the file at `path` untouched."""
    before, names = digest(path), listing(Path(path).parent)
    word, said = run_export(project, path=str(path), **arguments)
    after, names_after = digest(path), listing(Path(path).parent)
    ok = (word == "refused" and want(said) and before is not None and after == before
          and names_after == names)
    check(row, ok, f"{arguments.get('preset')}: {word}, {str(said)[:190]}; file {before} → {after}; "
                   f"folder {names_after}")


# ---- #470, #486, #504 at the door -------------------------------------------------------

def door_rows(client):
    project = Project(client, "door", [FILES / "long60.mov"])
    project.place(FILES / "long60.mov")
    project.op("set_range", start=0, end=SEC)
    folder = project.folder

    def r1():
        gif = made(project, preset="gif", path=str(folder / "loop.gif"), range="in_out")
        door("R1", project, lambda said: said.endswith(SHORT) and "this range is 750" in said,
             gif, preset="gif")

    attempt(["R1"], r1)

    def r2():
        for preset, extension in ALPHA:
            path = made(project, preset=preset, path=str(folder / f"{preset}.{extension}"),
                        range="in_out", size=[480, 270])
            door("R2", project, lambda said: SHAPE in said, path, preset=preset,
                 range="in_out", size=[1000, 1000])

    attempt(["R2"], r2)

    def r3():
        for preset, extension in ALPHA:
            word, status = run_export(project, preset=preset, path=str(folder / f"ok-{preset}.{extension}"),
                                      range="in_out", size=[960, 540])
            check("R3", word == "done", f"{preset} at 960×540: {word} {str(status)[:120]}")
        for preset, extension in (("apng", "png"), ("h264", "mp4")):
            word, status = run_export(project, preset=preset, path=str(folder / f"ok-{preset}.{extension}"),
                                      range="in_out", size=[1000, 1000])
            check("R3", word == "done", f"{preset} at 1000×1000: {word} {str(status)[:120]}")
        project.op("set_range", start=0, end=48 * SEC)
        word, status = run_export(project, bound=LONG_JOB_BOUND, preset="gif",
                                  path=str(folder / "ok48.gif"), range="in_out", size=[160, 90])
        project.op("set_range", start=0, end=SEC)
        check("R3", word == "done", f"a 600-frame GIF: {word} {str(status)[:120]}")

    attempt(["R3"], r3)

    def r4():
        for preset, extension, first, second in (("h264", "mp4", [640, 360], [320, 180]),
                                                 ("gif", "gif", [240, 136], [160, 90]),
                                                 ("apng", "png", [240, 136], [160, 90]),
                                                 ("vp9_webm", "webm", [640, 360], [320, 180])):
            path = made(project, preset=preset, path=str(folder / f"again-{preset}.{extension}"),
                        range="in_out", size=first)
            old = digest(path)
            word, _ = run_export(project, preset=preset, path=path, range="in_out", size=second)
            left = [name for name in listing(folder) if name.startswith((ASIDE, SIBLING))]
            check("R4", word == "done" and digest(path) not in (None, old) and not left,
                  f"{preset}: {word}, {old} → {digest(path)}, asides {left}")

    attempt(["R4"], r4)
    project.close()


# ---- a real throw past the doors --------------------------------------------------------

def stem_row(client):
    def s1():
        project = Project(client, "stems")
        folder = project.folder
        media = folder / "Mix - Dialogue.wav"
        shutil.copyfile(FILES / "tone.wav", media)
        project.op("set_track", track=project.tracks()[0], name="Dialogue")
        project.media[str(media)] = project.op("import_media", path=str(media))["media"]
        project.place(media)
        mix = folder / "Mix.wav"
        mix.write_bytes(b"the mix the person already had\n")
        before, names = digest(mix), listing(folder)
        word, status = run_export(project, preset="audio_wav", path=str(mix), stems="tracks")
        reason = status.get("reason", "") if isinstance(status, dict) else status
        sentence = ("The stem “Mix - Dialogue.wav” would replace media this project uses; "
                    "export under another name.")
        ok = (word in ("failed", "refused") and sentence in reason and digest(mix) == before
              and listing(folder) == names)
        check("S1", ok, f"{word}: {reason[:120]}; mix {before} → {digest(mix)}; {listing(folder)}")
        project.close()

    attempt(["S1"], s1)


# ---- the cancel -------------------------------------------------------------------------

def cancel_when(project, wanted, **arguments):
    """A job cancelled at the first status `wanted` accepts: (the last status, whether it was)."""
    answer = project.op("export", **arguments)
    client, began, hit = project.client, time.monotonic(), False
    while time.monotonic() - began < 120:
        status = client.call_with("export_status", {"export_id": answer["export_id"]})
        if status.get("status") not in ("queued", "running"):
            break
        if wanted(status):
            client.call_with("cancel_export", {"export_id": answer["export_id"]})
            hit = True
            break
        time.sleep(0.02)
    return follow(client, answer["export_id"]), hit


def measuring(status):
    return status.get("phase") == "Measuring loudness…"


def cancel_rows(client):
    project = Project(client, "cancel", [FILES / "long60.mov"])
    project.place(FILES / "long60.mov")
    project.op("set_range", start=0, end=SEC)
    folder = project.folder

    def c1():
        path = made(project, preset="h264", path=str(folder / "over.mp4"), range="in_out",
                    size=[640, 360])
        before = digest(path)
        status, hit = cancel_when(project, measuring, preset="h264", path=path)
        check("C1", hit and status.get("status") == "cancelled" and digest(path) == before,
              f"cancelled while measuring {hit}, {status.get('status')}; {before} → {digest(path)}")

    attempt(["C1"], c1)

    def c3():
        path = str(folder / "fresh.mp4")
        status, hit = cancel_when(project, measuring, preset="h264", path=path)
        check("C3", hit and status.get("status") == "cancelled" and not Path(path).exists(),
              f"cancelled {hit}, {status.get('status')}; exists {Path(path).exists()}")

    attempt(["C3"], c3)
    project.close()


# ---- #488 -------------------------------------------------------------------------------

def bits(path):
    done = subprocess.run(["sips", "-g", "bitsPerSample", str(path)], capture_output=True, text=True,
                          timeout=60)
    return int(done.stdout.strip().split()[-1])


def levels(path, row=288):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-vf", f"crop=iw:1:0:{row}", "-f",
                          "rawvideo", "-pix_fmt", "rgb48le", "-"], capture_output=True, check=True,
                         timeout=60).stdout
    return len(set(struct.unpack(f"<{len(raw) // 2}H", raw)[1::3]))


def layout(client, name, stack):
    """A project of 1024×576 tracks, back to front, each a list of (a fixture's stem, its start)."""
    keys = sorted({key for track in stack for key, _ in track})
    project = Project(client, name, [FILES / f"{key}.mov" for key in keys], canvas=(1024, 576))
    for _ in stack[1:]:
        project.op("add_track")
    for track, placed in zip(project.tracks(), stack):
        for key, at in placed:
            project.place(FILES / f"{key}.mov", track=track, at=at)
    return project


def frame(project, name, seconds, form="png"):
    out = project.folder / f"{name}.{form}"
    project.op("render_frame", t=round(seconds * SEC), path=str(out), format=form)
    return out


def deep(row, client, name, stack, seconds=1):
    project = layout(client, name, stack)
    out = frame(project, name, seconds)
    depth, count = bits(out), levels(out)
    check(row, depth == 16 and count > 256, f"{name} at {seconds} s: {depth}-bit, {count} levels")
    project.close()


def control(client, name, stack, depth, form="png", seconds=1):
    project = layout(client, name, stack)
    out = frame(project, name, seconds, form)
    got = bits(out)
    check("D8", got == depth, f"{name} {form} at {seconds} s: {got}-bit, want {depth}")
    project.close()


def wait_reverse(project, media):
    folder = Path(project.path) / "cache" / "reversed"
    began = time.monotonic()
    while time.monotonic() - began < REVERSE_BOUND:
        files = sorted(folder.glob(f"{media}-*.mov")) if folder.is_dir() else []
        partial = folder.is_dir() and any(folder.glob(f"{media}-*.partial"))
        if files and not partial:
            try:
                project.op("snapshot_ui", window="sheet", path=str(project.folder / "sheet.png"))
            except mcp.ToolError as error:
                if "no sheet attached" in str(error):
                    return
        time.sleep(0.25)
    raise RuntimeError(f"the reverse did not finish in {REVERSE_BOUND} s")


def depth_rows(client):
    h264, hevc8, hevc10, prores = "h264", "hevc8", "hevc10", "prores"
    attempt(["D1"], lambda: deep("D1", client, "h264-hevc10", [[(h264, 0)], [(hevc10, 0)]]))
    attempt(["D2"], lambda: deep("D2", client, "h264-prores", [[(h264, 0)], [(prores, 0)]]))
    attempt(["D3"], lambda: deep("D3", client, "hevc8-hevc10", [[(hevc8, 0)], [(hevc10, 0)]]))
    attempt(["D4"], lambda: deep("D4", client, "h264-h264-hevc10",
                                 [[(h264, 0)], [(h264, 0)], [(hevc10, 0)]]))
    attempt(["D5"], lambda: deep("D5", client, "apart", [[(h264, 0)], [(hevc10, 6)]], seconds=7))

    def d6():
        project = layout(client, "heic", [[(h264, 0)], [(hevc10, 0)]])
        out = frame(project, "heic", 1, "heic")
        depth = bits(out)
        check("D6", depth == 10, f"HEIC of H.264 under HEVC 10: {depth}-bit")
        project.close()

    attempt(["D6"], d6)

    def d7():
        project = layout(client, "reversed", [[(h264, 0)], [(h264, 0)]])
        front = [clip["id"] for clip in project.state()["clips"]
                 if clip.get("track") == project.tracks()[1]][0]
        project.op("set_reversed", clip=front, reversed=True)
        wait_reverse(project, project.media[str(FILES / "h264.mov")])
        out = frame(project, "reversed", 1)
        depth = bits(out)
        check("D7", depth == 16, f"a reversed 8-bit clip above H.264: {depth}-bit")
        project.close()

    attempt(["D7"], d7)

    def d8():
        control(client, "h264-alone", [[(h264, 0)]], 8)
        control(client, "hevc8-alone", [[(hevc8, 0)]], 8)
        control(client, "h264-hevc8", [[(h264, 0)], [(hevc8, 0)]], 8)
        control(client, "elsewhere", [[(h264, 0)], [(hevc10, 6)]], 8)
        control(client, "hevc10-alone", [[(hevc10, 0)]], 16)
        control(client, "prores-alone", [[(prores, 0)]], 16)
        control(client, "jpeg", [[(h264, 0)], [(hevc10, 0)]], 8, form="jpg")

    attempt(["D8"], d8)


# ---- #493 -------------------------------------------------------------------------------

def path_rows(client):
    project = Project(client, "paths", [FILES / "short3.mov"])
    project.place(FILES / "short3.mov")
    project.op("set_range", start=0, end=SEC // 2)
    folder = project.folder

    def exported(row, preset, name, want, **more):
        word, status = run_export(project, preset=preset, path=str(folder / name), range="in_out",
                                  **more)
        written = status.get("path") if isinstance(status, dict) else None
        doubled = [entry for entry in listing(folder) if entry.startswith(f"{name}.")]
        check(row, word == "done" and written == str(folder / want) and (folder / want).exists()
              and doubled in ([], [want]),
              f"{preset} at {name}: {word}, answered {written and Path(written).name}, want {want}, "
              f"doubled {doubled}")

    def rendered(row, name, want):
        answer = project.op("render_frame", t=0, path=str(folder / name))
        check(row, (folder / want).exists() and want in str(answer),
              f"render_frame at {name}: {str(answer)[-80:]}, {want} on disk "
              f"{(folder / want).exists()}")

    def w1():
        exported("W1", "h264", "cut.webm", "cut.mp4")
        exported("W1", "prores_422", "cut2.webm", "cut2.mov")
        exported("W1", "gif", "cut3.webm", "cut3.gif", size=[160, 90])
        exported("W1", "h264", "CUT4.WEBM", "CUT4.mp4")
        rendered("W1", "shot.webm", "shot.png")

    attempt(["W1"], w1)

    def w2():
        exported("W2", "av1_webm", "cut5.mp4", "cut5.webm")
        exported("W2", "h264", "cut7.mov", "cut7.mp4")
        exported("W2", "h264", "Talk v1.2", "Talk v1.2.mp4")
        rendered("W2", "shot2.mov", "shot2.png")

    attempt(["W2"], w2)
    project.close()


# ---- the sheet --------------------------------------------------------------------------

def texts(node, out):
    if isinstance(node, dict):
        if isinstance(node.get("text"), str):
            out.append(node["text"])
        for value in node.values():
            texts(value, out)
    elif isinstance(node, list):
        for value in node:
            texts(value, out)
    return out


def card(binary, label, media, choice):
    """The readout's lines of the real sheet opened on `choice`: every text in its layout dump."""
    literal = '"' + json.dumps(choice).replace("\\", "\\\\").replace('"', '\\"') + '"'
    launched = start(binary, label, ["-FrameJobExportChoice", literal])
    try:
        if launched.client is None:
            raise RuntimeError("the app did not listen")
        project = Project(launched.client, f"sheet-{label}", [media])
        project.place(media)
        project.op("perform_menu_item", path=["File", "Export…"])
        png = project.folder / "sheet.png"
        project.op("snapshot_ui", window="sheet", path=str(png))
        dump = texts(json.load(open(png.with_suffix(".layout.json"))), [])
        project.op("cancel_sheet")
        project.close()
        return dump
    finally:
        launched.stop()


def reads(row, binary, label, media, choice, want):
    dump = card(binary, label, media, choice)
    found = [line for line in dump if "frames" in line or "shape" in line or " fps" in line]
    check(row, want(dump), f"{label}: {[line[:96] for line in found]}")


def short_sentence(dump):
    return any(line.endswith(SHORT) and "limited to 600 frames" in line for line in dump)


def clause_sentence(dump):
    return any(line.endswith(CLAUSE) and "limited to 600 frames" in line for line in dump)


def shape_sentence(dump):
    return any(SHAPE in line for line in dump)


def usual_readout(dump):
    return not any("limited to 600" in line or SHAPE in line for line in dump) \
        and any(" fps · " in line for line in dump)


def sheet_rows(binary):
    long, short = FILES / "long60.mov", FILES / "short3.mov"
    attempt(["G1"], lambda: reads("G1", binary, "gif", long, {"preset_id": "gif"}, short_sentence))
    attempt(["G2"], lambda: reads("G2", binary, "apng", long, {"preset_id": "apng"}, short_sentence))
    attempt(["G3"], lambda: reads("G3", binary, "gif24", long, {"preset_id": "gif", "fps": [24, 1]},
                                  clause_sentence))
    attempt(["G4"], lambda: reads("G4", binary, "hevc-alpha", short,
                                  {"preset_id": "hevc_alpha", "custom_size": [1000, 1000]},
                                  shape_sentence))

    def g5():
        for preset in ("prores_4444", "vp9_alpha_webm"):
            reads("G5", binary, preset, short, {"preset_id": preset, "custom_size": [1000, 1000]},
                  shape_sentence)

    attempt(["G5"], g5)

    def g6():
        reads("G6", binary, "gif-fits", short, {"preset_id": "gif"}, usual_readout)
        reads("G6", binary, "alpha-fits", short,
              {"preset_id": "hevc_alpha", "custom_size": [960, 540]}, usual_readout)

    attempt(["G6"], g6)


# ---- the probe --------------------------------------------------------------------------

def save_packages(client):
    packages = {}
    for name, source in (("long", FILES / "long60.mov"), ("short", FILES / "short3.mov")):
        project = Project(client, f"package-{name}", [source])
        project.place(source)
        project.op("save_project")
        packages[name] = project.path
        project.op("close_project")
    return packages


def build_probe(sources):
    """(binary, None) or (None, why): a probe that will not build fails its rows."""
    OUT.mkdir(parents=True, exist_ok=True)
    entry = OUT / "main.swift"
    shutil.copyfile(PROBE, entry)
    binary = OUT / "docs-bugs-b3-probe"
    try:
        swift_build.build(sources=swift_build.app_sources(sources) + [entry], output=binary)
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + "; ".join([str(error)] + list(error.diagnostics[:8]))
    return binary, None


def probe_rows(binary, packages):
    env = bounded.child_env({"CFFIXED_USER_HOME": str(HOME)})
    done = subprocess.run([str(binary), packages["long"], packages["short"], str(OUT)],
                          capture_output=True, text=True, env=env, timeout=PROBE_BOUND, cwd=OUT,
                          stdin=subprocess.DEVNULL)
    rows = {}
    for line in done.stdout.splitlines():
        if line.startswith("{"):
            answer = json.loads(line)
            rows[answer["row"]] = answer
    if done.returncode != 0 or "PB" not in rows:
        raise RuntimeError(f"exit {done.returncode}, rows {sorted(rows)}: {done.stderr[-300:]}")

    for side, want in (("off", False), ("on", True)):
        for answer in rows["B1"][side]:
            check("B1", answer["export"] is want and answer["queue"] is want,
                  f"{side}, {answer['name']}: Export… {answer['export']}, Add to Queue "
                  f"{answer['queue']}, {answer['summary'][:90]!r}")
    for answer, want in zip(rows["B2"]["exports"], ("limited to 600 frames", SHAPE)):
        ok = (answer.get("finished") and want in answer.get("failed", "") and answer.get("same")
              and answer.get("listing") == ["old.bin"])
        check("B2", ok, f"{answer['name']}: {str(answer.get('failed'))[:90]!r}, the file the same "
                        f"{answer.get('same')}, folder {answer.get('listing')}")
    check("PB", rows["PB"]["unchanged"], f"unchanged {rows['PB']['unchanged']}")


# ---- the run ----------------------------------------------------------------------------

def run(binary, sources):
    probe, why = (None, None)
    if selected & set(PROBE_ROWS):
        probe, why = build_probe(sources)
        if why:
            for row in sorted(selected & set(PROBE_ROWS)):
                check(row, False, f"the probe did not build: {why}")
    packages = None
    launched = start(binary, "main")
    try:
        if launched.client is None:
            for row in sorted(selected - {"Z1"}):
                check(row, False, "the app did not listen")
            return
        client = launched.client
        if selected & set(DOOR_ROWS):
            door_rows(client)
        if selected & set(STEM_ROWS):
            stem_row(client)
        if selected & set(CANCEL_ROWS):
            cancel_rows(client)
        if selected & set(DEPTH_ROWS):
            depth_rows(client)
        if selected & set(PATH_ROWS):
            path_rows(client)
        if probe is not None:
            def keep():
                nonlocal packages
                packages = save_packages(client)

            attempt(PROBE_ROWS, keep)
    finally:
        launched.stop()
    if selected & set(SHEET_ROWS):
        sheet_rows(binary)
    if probe is not None and packages is not None:
        attempt(PROBE_ROWS, lambda: probe_rows(probe, packages))


def mutate(name):
    """(the copy, None) or (None, why): the tree copy with the mutant's edits."""
    made_copy, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made_copy is None:
        return None, reason
    for path, anchor, replacement in MUTANTS[name][1]:
        target = Path(made_copy) / path
        text = target.read_text()
        if text.count(anchor) != 1:
            return None, f"the anchor occurs {text.count(anchor)} times in {path}: {anchor[:60]!r}"
        target.write_text(text.replace(anchor, replacement))
    return Path(made_copy), None


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--app")
    parser.add_argument("--base-sources")
    parser.add_argument("--expect-red", action="store_true")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    if args.mutant:
        selected = set(MUTANTS[args.mutant][0]) | {"Z1"}
    elif args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
        selected.add("Z1")
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))
    for folder in (FILES, HOME, LOGS):
        folder.mkdir(parents=True)

    binary = Path(args.app) if args.app else None
    sources = Path(args.base_sources) if args.base_sources else ROOT / "app/Sources"
    if args.mutant:
        named = " ".join(MUTANTS[args.mutant][0])
        print(f"docs bugs b3 — the {args.mutant} MUTANT ({named} must FAIL)", flush=True)
        copy, why = mutate(args.mutant)
        if why is None:
            app, why = tree_copy.build_app(copy, BUILD_BOUND)
            binary = proof_app.executable(app) if app else None
            sources = copy / "app/Sources"
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
    if binary is None:
        binary = proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    print(f"docs bugs b3 — what an export does and answers ({binary.name})", flush=True)

    try:
        fixtures()
    except (OSError, subprocess.SubprocessError) as error:
        for row in sorted(selected):
            check(row, False, f"the fixtures were not made: {error!r}")
    else:
        run(binary, sources)
        parity()

    failed = [name for name in ROWS if name in results and not all(ok for ok, _ in results[name])]
    passed = [name for name in ROWS if name in results and name not in failed]
    print(f"\n{len(passed)}/{len(passed) + len(failed)} rows passed"
          + (f"; failed {failed}" if failed else ""), flush=True)
    if args.mutant:
        rows = MUTANTS[args.mutant][0]
        missing = [row for row in rows if row not in results]
        if missing:
            print(f"mutant {args.mutant}: the control could not be performed — {missing} never "
                  f"scored")
            return 2
        caught = all(row in failed for row in rows)
        print(f"MUTANT {args.mutant} {'CAUGHT' if caught else 'SURVIVED'}: "
              + ", ".join(f"{row} {'failed' if row in failed else 'passed'}" for row in rows),
              flush=True)
        return 1 if caught else 0
    if args.expect_red:
        wrong = [r for r in failed if r in CONTROLS] + [r for r in passed if r not in CONTROLS]
        print("expected red, every row not marked (c) failing and every (c) passing: "
              + ("held" if not wrong else f"NOT held for {wrong}"), flush=True)
        return 1 if wrong else 0
    return 0 if not failed and results else 1


if __name__ == "__main__":
    sys.exit(main())
