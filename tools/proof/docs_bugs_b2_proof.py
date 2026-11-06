#!/usr/bin/env python3
"""Docs bugs, batch b2 (#467 #482 #498 #487 and #497's agent sentence; spec §11 #467, #498, #487):
a caption file's encodings, WebVTT, AVIF stills, an unreadable project.json, and what `import_media`
says about a folder.

    python3 tools/proof/docs_bugs_b2_proof.py [--only A1,V3,…] [--app PATH] [--base-sources PATH]
                                              [--expect-red] [--mutant NAME]
    RC_PROOF_APP=<the frozen base app> python3 tools/proof/docs_bugs_b2_proof.py \
        --base-sources <a tree at the base>/app/Sources --expect-red
    RC_PROOF_APP=release python3 tools/proof/docs_bugs_b2_proof.py

The built app (`proof_app`'s choice, or `--app`) on a scratch `CFFIXED_USER_HOME` under
`work/docs-bugs-b2/`. `(c)` marks a CONTROL, which passes on the base too; every other row is red on
the frozen base app with `--base-sources` set to the base's `app/Sources`, and `--expect-red` exits 0
only when that holds. The ffmpeg-made fixtures are made here, so ffmpeg (with libsvtav1) and `sips`
are needed at proof time.

- Encoding, text read back through `get_project`: E1 the issue's French line, cp1252. E2 Spanish and
  Italian. E3 French Latin-1. E4 French CRLF. E5 Danish. E6 (c) UTF-8, ASCII, UTF-16 with each BOM.
  E7 (c) German with no ß. E8 (c) BOM-less UTF-16 LE refused with `No captions could be read`.
- WebVTT: V1 `x.vtt`: 1 cue, no `skipped`. V2 the app's own `export_captions` `.vtt`, the same cues
  back. V3 `blocks.vtt`: 2 cues, no `skipped`. V4 a BOM and CRLF. V5 `<00:00:03.500>`, `<v Kevin>`,
  `<c.yellow>` gone from the text. V6 `WEBVTT`, `Kind: captions`, then a cue with no blank line. V7
  `tools/list` says WebVTT. V8 one broken cue: exactly one `skipped`, naming its line (the base
  answers two, the header's and the cue's). V9 (c) `clean.srt`: no `skipped`. V10 (c) an `.srt` with
  a `NOTE` block still reports it. V11 (c) `<00:00:03.500>` in an `.srt` stays. V12 (c) a first line
  `WEBVTTX` still reports it. V13 `kind_broken.vtt`: a broken cue straight after `WEBVTT` and `Kind:`
  in the first block is one `skipped` naming line 3, its own timing line, and the good cue after it
  lands.
- Package, `open_project`, one instance a row: P1 project.json a folder. P2 a link to a folder. P3 a
  link to a file opens with its clip. P4 a dangling link. P5 no project.json. P6 (c) not UTF-8. P7
  (c) a good package. Each refusing row also proves the instance alive afterwards. On a Debug build
  lldb is attached, the base included, so an abort stops under the debugger and no crash report
  window appears; a Release run has no lldb, and a dead instance scores a failure. `-NSOpen` is never
  used: on the fix its alert would reach the owner's screen, which is `docs/manual-checks.md` PB-16.
- AVIF: A1 `import_media` on the default policy: `kind: image`, 320×240, duration 0, no `original`.
  A2 the same with `-RCFFmpegPath /nonexistent/ffmpeg`. A3 the same with `-RCFFmpegImport always`.
  A4 placed, `render_frame`'s mean within 8/255 a channel of the same picture's PNG render. A5 a
  10-bit AVIF: `kind: image` and renders. A6 `bad.avif`, plain text ImageIO cannot parse: exactly
  `Could not read bad.avif.`. A7 (c) PNG and HEIC.
- Folder sentence: F1 `relink_media` of an imported `A.mov` to `Shoot`, default policy, ffmpeg
  present: no "ffmpeg" in the answer (`import_media` imports a folder's files since #497, so the F
  rows probe the folder through `relink_media`, the other door that probes it). F2 a folder named
  `Shoot.mov`. F3 (c) `import_media` on an ffmpeg-made `.flv` keeps the clause (an `.avi` opens in
  AVFoundation and is refused by its codec, with no clause). F4 a symbolic link to `Shoot`.
- Probe, `docs_bugs_b2_probe.swift` through `swift_build.build()`: D1 an AVIF dropped on the Media
  tab: `kind: image`, no consent, no sheet. D2 Add Background: `kind: image`, one clip more, no
  consent. D3 (c) a PNG dropped. C1 `importCaptionsCommand()` on the French cp1252 file: the clip
  landed, no alert. C2 on `x.vtt`: no alert. C3 (c) `clean.srt`: no alert. C4 the panel's message
  names WebVTT. PB (c) the general pasteboard's change count is unchanged.
- Z1 (c) `grep "Frame Job: "` on each launch's log prints nothing.

`--mutant NAME`: the named decision broken in a `tree_copy.py` copy, whose app is built and driven
for the named row and Z1. CAUGHT exits 1, SURVIVED exits 0, and a control that could not be performed
(the copy did not build, an anchor not found once) exits 2. An instrument that cannot run is a scored
failure, never an exit.
"""

import argparse
import json
import os
import shutil
import signal
import subprocess
import sys
import threading
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

WORK = ROOT / "tools/proof/work/docs-bugs-b2"
HOME = WORK / "home"
FILES = WORK / "files"
LOGS = WORK / "logs"
OUT = WORK / "probe"
PROBE = HERE / "docs_bugs_b2_probe.swift"
MEDIA = ROOT / "tools/proof/media"
CALL_BOUND = 120
OPEN_BOUND = 45
BUILD_BOUND = 1500
PROBE_BOUND = 240
NO_CAPTIONS = "No captions could be read"
NOT_READABLE = "does not contain a readable project.json."
AVIF_NEAR = 8 / 255

CAPTION_ROWS = ["E1", "E2", "E3", "E4", "E5", "E6", "E7", "E8",
                "V1", "V2", "V3", "V4", "V5", "V6", "V7", "V8", "V9", "V10", "V11", "V12",
                "V13"]
PACKAGE_ROWS = ["P1", "P2", "P3", "P4", "P5", "P6", "P7"]
AVIF_ROWS = ["A1", "A4", "A5", "A6", "A7"]
FOLDER_ROWS = ["F1", "F2", "F3", "F4"]
PROBE_ROWS = ["D1", "D2", "D3", "C1", "C2", "C3", "C4", "PB"]
ROWS = CAPTION_ROWS + PACKAGE_ROWS + AVIF_ROWS + ["A2", "A3"] + FOLDER_ROWS + PROBE_ROWS + ["Z1"]
CONTROLS = {"E6", "E7", "E8", "V9", "V10", "V11", "V12", "P6", "P7", "A7", "F3", "D3", "C3", "PB",
            "Z1"}

CAPTIONS = "app/Sources/CaptionImporter.swift"
AGENT = "app/Sources/AgentServer+Media.swift"
# name: (the row it must turn red, the edits).
MUTANTS = {
    "utf16-no-bom": ("E1", [(
        CAPTIONS, "let encodings: [String.Encoding] = [.utf8] + (wide ? [.utf16] : [])",
        "let encodings: [String.Encoding] = [.utf8] + (wide || true ? [.utf16] : [])")]),
    "vtt-header-kept": ("V1", [(CAPTIONS, "var inHeader = webVTT", "var inHeader = false")]),
    "vtt-aside-kept": ("V3", [(
        CAPTIONS, "} else if webVTT, isWebVTTAside(block) {", "} else if false {")]),
    "vtt-aside-in-srt": ("V10", [(
        CAPTIONS, "} else if webVTT, isWebVTTAside(block) {", "} else if isWebVTTAside(block) {")]),
    "vtt-digit-tag-in-srt": ("V11", [(
        CAPTIONS, "(webVTT && first.isASCII && first.isNumber)",
        "(first.isASCII && first.isNumber)")]),
    "avif-dropped": ("A1", [(
        "app/Sources/MediaImporter+Probe.swift", ", .webP, UTType(importedAs: \"public.avif\")]",
        ", .webP]")]),
    "filewrapper-back": ("P1", [(
        "app/Sources/ProjectDocument.swift", "guard let data = try? Data(contentsOf: jsonURL),\n",
        "guard let data = (try FileWrapper(url: jsonURL, options: .immediate))"
        ".regularFileContents,\n")]),
    "folder-clause": ("F1", [(
        AGENT, "guard invites, !isFolder, !MediaImporter.isImage(url),",
        "guard invites, !isFolder || true, !MediaImporter.isImage(url),")]),
    "folder-link-unresolved": ("F4", [(
        AGENT, "(try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]))?",
        "(try? url.resourceValues(forKeys: [.isDirectoryKey]))?")]),
    "vtt-header-line": ("V13", [(CAPTIONS, "                firstLine += header\n", "")]),
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

def srt(lines):
    return "\n".join(f"{i + 1}\n00:00:{i + 1:02d},000 --> 00:00:{i + 2:02d},000\n{line}\n"
                     for i, line in enumerate(lines))


FRENCH = ["Il a été très déçu"]
SPANISH = ["¿Dónde está el niño?", "Mañana será otro día, señor"]
ITALIAN = ["Perché è così difficile?", "Città più bella, università"]
DANISH = ["Rødgrød med fløde", "Ø og æ på øen"]
GERMAN = ["Über die Brücke", "Schöne Tür"]
CUE = "00:00:01.000 --> 00:00:02.000\n"
CUE2 = "00:00:03.000 --> 00:00:04.000\n"
VTT_BLOCKS = (f"WEBVTT - a title\n\nNOTE a comment\n\nSTYLE\n::cue {{ color: red }}\n\n"
              f"REGION\nid:one\n\n{CUE}Hello\n\nNOTE\nanother note\nover two lines\n\n"
              f"{CUE2}World\n")


def write(name, data):
    (FILES / name).write_bytes(data if isinstance(data, bytes) else data.encode("utf-8"))
    return str(FILES / name)


def ffmpeg(*arguments):
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *arguments], check=True, timeout=120)


def fixtures():
    plain = srt(["Plain words"])
    write("fr_cp1252.srt", srt(FRENCH).encode("cp1252"))
    write("es_cp1252.srt", srt(SPANISH).encode("cp1252"))
    write("it_cp1252.srt", srt(ITALIAN).encode("cp1252"))
    write("fr_latin1.srt", srt(FRENCH).encode("latin-1"))
    write("fr_crlf_cp1252.srt", srt(FRENCH).replace("\n", "\r\n").encode("cp1252"))
    write("da_cp1252.srt", srt(DANISH).encode("cp1252"))
    write("de_cp1252.srt", srt(GERMAN).encode("cp1252"))
    write("fr_utf8.srt", srt(FRENCH))
    write("ascii.srt", plain.encode("ascii"))
    write("fr_utf16le_bom.srt", b"\xff\xfe" + srt(FRENCH).encode("utf-16-le"))
    write("fr_utf16be_bom.srt", b"\xfe\xff" + srt(FRENCH).encode("utf-16-be"))
    write("fr_utf16le_nobom.srt", srt(FRENCH).encode("utf-16-le"))
    write("x.vtt", f"WEBVTT\n\n{CUE}Hello\n")
    write("blocks.vtt", VTT_BLOCKS)
    write("bom_crlf.vtt", f"﻿WEBVTT\n\n{CUE}Hello\n".replace("\n", "\r\n"))
    write("tags.vtt", f"WEBVTT\n\n{CUE}<v Kevin>Hello <00:00:01.500>there "
                      "<c.yellow>world</c></v>\n")
    write("kind.vtt", f"WEBVTT\nKind: captions\n{CUE}Hello\n")
    write("broken.vtt", f"WEBVTT\n\n{CUE}Good\n\nno timing here\nsecond line\n\n{CUE2}Also good\n")
    write("clean.srt", f"1\n00:00:01,000 --> 00:00:02,000\nHello\n")
    write("note.srt", "1\n00:00:01,000 --> 00:00:02,000\nHello\n\nNOTE a comment\n\n"
                      "2\n00:00:03,000 --> 00:00:04,000\nWorld\n")
    write("tag.srt", "1\n00:00:01,000 --> 00:00:02,000\nHello <00:00:03.500>there\n")
    write("notvtt.vtt", f"WEBVTTX\n\n{CUE}Hello\n")
    write("kind_broken.vtt", "WEBVTT\nKind: captions\n00:00:01.000 --> later\nBad\n\n"
                             + CUE2 + "Also good\n")
    write("bad.avif", "This is plain text with an AVIF's name, and ImageIO cannot parse it.\n" * 12)

    png = str(FILES / "still.png")
    ffmpeg("-f", "lavfi", "-i", "testsrc=size=320x240:rate=1", "-frames:v", "1", png)
    ffmpeg("-i", png, "-frames:v", "1", "-c:v", "libsvtav1", str(FILES / "x.avif"))
    shutil.copy(FILES / "x.avif", FILES / "y.avif")
    ffmpeg("-i", png, "-frames:v", "1", "-c:v", "libsvtav1", "-pix_fmt", "yuv420p10le",
           str(FILES / "deep.avif"))
    subprocess.run(["sips", "-s", "format", "heic", png, "--out", str(FILES / "still.heic")],
                   check=True, stdout=subprocess.DEVNULL, timeout=60)
    ffmpeg("-f", "lavfi", "-i", "testsrc=size=320x240:rate=30:duration=1", "-c:v", "flv1",
           str(FILES / "clip.flv"))
    shoot = FILES / "Shoot"
    shoot.mkdir()
    for name in ("A.mov", "B.mov"):
        shutil.copy(MEDIA / name, shoot / name)
    (FILES / "Shoot.mov").mkdir()
    os.symlink(shoot, FILES / "ShootLink")


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

    def __init__(self, client, name):
        self.client = client
        self.path = str(WORK / f"{name}.framejob")
        client.call_with("new_project", {"path": self.path})

    def op(self, tool, **arguments):
        return self.client.call_with(tool, dict(arguments, project=self.path))

    def state(self):
        return self.op("get_project")["project"]

    def close(self):
        self.op("close_project", discard=True)


def refusal(call):
    """A tool's refusal sentence, or None when it answered."""
    try:
        call()
    except mcp.ToolError as error:
        return str(error)
    return None


# ---- captions ---------------------------------------------------------------------------

def caption_clips(project):
    found = []
    for clip in project.state()["clips"]:
        body = clip.get("source", {}).get("text") or clip.get("text")
        if body is not None:
            text = body.get("content") if isinstance(body, dict) else body
            found.append((clip.get("start"), clip.get("duration"), text))
    return sorted(found, key=lambda cue: str(cue[0]).zfill(20))


def imported(project, name):
    """(the answer, its texts, its cues), the import undone; a refusal is (the sentence, [], [])."""
    path = name if name.startswith("/") else str(FILES / name)
    try:
        answer = project.op("import_captions", path=path)
    except mcp.ToolError as error:
        return str(error), [], []
    cues = caption_clips(project)
    project.op("undo")
    return answer, [cue[2] for cue in cues], cues


def reads(row, project, name, lines):
    answer, texts, _ = imported(project, name)
    check(row, texts == lines, f"{name}: {texts}, answer {str(answer)[:160]}")


def clean(row, project, name, lines):
    answer, texts, _ = imported(project, name)
    ok = isinstance(answer, dict) and "skipped" not in answer and texts == lines
    check(row, ok, f"{name}: {texts}, answer {str(answer)[:200]}")


def caption_rows(client):
    project = Project(client, "captions")
    attempt(["E1"], lambda: reads("E1", project, "fr_cp1252.srt", FRENCH))

    def e2():
        for name, lines in (("es_cp1252.srt", SPANISH), ("it_cp1252.srt", ITALIAN)):
            reads("E2", project, name, lines)

    attempt(["E2"], e2)
    attempt(["E3"], lambda: reads("E3", project, "fr_latin1.srt", FRENCH))
    attempt(["E4"], lambda: reads("E4", project, "fr_crlf_cp1252.srt", FRENCH))
    attempt(["E5"], lambda: reads("E5", project, "da_cp1252.srt", DANISH))

    def e6():
        for name, lines in (("fr_utf8.srt", FRENCH), ("ascii.srt", ["Plain words"]),
                            ("fr_utf16le_bom.srt", FRENCH), ("fr_utf16be_bom.srt", FRENCH)):
            reads("E6", project, name, lines)

    attempt(["E6"], e6)
    attempt(["E7"], lambda: reads("E7", project, "de_cp1252.srt", GERMAN))

    def e8():
        answer, texts, _ = imported(project, "fr_utf16le_nobom.srt")
        check("E8", isinstance(answer, str) and NO_CAPTIONS in answer and not texts, str(answer))

    attempt(["E8"], e8)
    attempt(["V1"], lambda: clean("V1", project, "x.vtt", ["Hello"]))

    def v2():
        project.op("import_captions", path=str(FILES / "clean.srt"))
        before = caption_clips(project)
        track = project.state()["tracks"][-1]["id"]
        written = str(WORK / "own.vtt")
        project.op("export_captions", path=written, format="vtt", track=track)
        project.op("undo")
        answer, _, after = imported(project, written)
        ok = isinstance(answer, dict) and "skipped" not in answer and after == before and before
        check("V2", ok, f"written {before}, back {after}, answer {str(answer)[:200]}")

    attempt(["V2"], v2)
    attempt(["V3"], lambda: clean("V3", project, "blocks.vtt", ["Hello", "World"]))
    attempt(["V4"], lambda: clean("V4", project, "bom_crlf.vtt", ["Hello"]))
    attempt(["V5"], lambda: clean("V5", project, "tags.vtt", ["Hello there world"]))
    attempt(["V6"], lambda: clean("V6", project, "kind.vtt", ["Hello"]))

    def v7():
        tool = client.schemas()["import_captions"]
        path = tool["inputSchema"]["properties"]["path"]["description"]
        check("V7", "WebVTT" in tool["description"] and ".vtt" in path,
              f"{tool['description'][:80]!r}, path {path!r}")

    attempt(["V7"], v7)

    def v8():
        answer, texts, _ = imported(project, "broken.vtt")
        skipped = answer.get("skipped") if isinstance(answer, dict) else None
        ok = (texts == ["Good", "Also good"] and skipped is not None and len(skipped) == 1
              and skipped[0].startswith("line 6:"))
        check("V8", ok, f"{texts}, skipped {skipped}")

    attempt(["V8"], v8)
    attempt(["V9"], lambda: clean("V9", project, "clean.srt", ["Hello"]))

    def reported(row, name, line, lines):
        answer, texts, _ = imported(project, name)
        skipped = answer.get("skipped") if isinstance(answer, dict) else None
        ok = (texts == lines and skipped is not None and len(skipped) == 1
              and skipped[0].startswith(f"line {line}:"))
        check(row, ok, f"{name}: {texts}, skipped {skipped}")

    attempt(["V10"], lambda: reported("V10", "note.srt", 5, ["Hello", "World"]))
    attempt(["V11"], lambda: clean("V11", project, "tag.srt", ["Hello <00:00:03.500>there"]))
    attempt(["V12"], lambda: reported("V12", "notvtt.vtt", 1, ["Hello"]))
    attempt(["V13"], lambda: reported("V13", "kind_broken.vtt", 3, ["Also good"]))
    project.close()


# ---- AVIF and folders -------------------------------------------------------------------

def is_still(answer):
    return (isinstance(answer, dict) and answer.get("kind") == "image" and answer.get("width") == 320
            and answer.get("height") == 240 and answer.get("duration") == 0
            and "original" not in answer)


def brief(answer):
    keys = ("kind", "width", "height", "duration", "original")
    return {key: answer.get(key) for key in keys} if isinstance(answer, dict) else answer


def try_import(project, name):
    try:
        return project.op("import_media", path=str(FILES / name))
    except mcp.ToolError as error:
        return str(error)


def means(path):
    """The mean of R, G and B over the picture, 0 to 1: 320×240, unscaled, at the canvas's centre."""
    done = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-vf", "crop=320:240", "-f",
                           "rawvideo", "-pix_fmt", "rgb24", "-"], capture_output=True, check=True,
                          timeout=120)
    data = done.stdout
    pixels = len(data) // 3
    return [sum(data[channel::3]) / pixels / 255 for channel in range(3)]


def rendered(client, label, media_name):
    """`render_frame`'s means with `media_name` alone on a new project, or the refusal."""
    project = Project(client, f"render-{label}")
    try:
        answer = try_import(project, media_name)
        if not isinstance(answer, dict):
            return answer
        track = project.state()["tracks"][0]["id"]
        project.op("add_clip", track=track, media=answer["media"], at=0)
        out = WORK / f"render-{label}.png"
        project.op("render_frame", t=0, path=str(out))
        return means(out)
    finally:
        project.close()


def avif_rows(client):
    project = Project(client, "avif")

    def a1():
        answer = try_import(project, "x.avif")
        check("A1", is_still(answer), str(brief(answer))[:200])

    attempt(["A1"], a1)

    def a4():
        avif, png = rendered(client, "avif", "x.avif"), rendered(client, "png", "still.png")
        ok = (isinstance(avif, list) and isinstance(png, list) and max(png) > 0.1
              and all(abs(a - b) <= AVIF_NEAR for a, b in zip(avif, png)))
        check("A4", ok, f"AVIF {avif}, PNG {png}")

    attempt(["A4"], a4)

    def a5():
        answer = try_import(project, "deep.avif")
        image = rendered(client, "deep", "deep.avif")
        ok = is_still(answer) and isinstance(image, list) and max(image) > 0.1
        check("A5", ok, f"{str(brief(answer))[:160]}, means {image}")

    attempt(["A5"], a5)

    def a6():
        answer = try_import(project, "bad.avif")
        check("A6", answer == "import_media: Could not read bad.avif.", str(answer)[:240])

    attempt(["A6"], a6)

    def a7():
        for name in ("still.png", "still.heic"):
            answer = try_import(project, name)
            check("A7", is_still(answer), f"{name}: {str(brief(answer))[:160]}")

    attempt(["A7"], a7)
    project.close()


def policy_row(binary, row, arguments):
    def body():
        launched = start(binary, row, arguments)
        try:
            if launched.client is None:
                check(row, False, "the app did not listen")
                return
            project = Project(launched.client, f"policy-{row}")
            answer = try_import(project, "x.avif")
            check(row, is_still(answer), f"{arguments}: {str(brief(answer))[:200]}")
            project.close()
        finally:
            launched.stop()

    attempt([row], body)


def folder_rows(client):
    project = Project(client, "folders")
    media = {}

    def plain(row, name):
        if "id" not in media:
            media["id"] = project.op("import_media", path=str(MEDIA / "A.mov"))["media"]
        try:
            answer = project.op("relink_media", media=media["id"], path=str(FILES / name))
        except mcp.ToolError as error:
            answer = str(error)
        ok = isinstance(answer, str) and f"Could not read {name}." in answer \
            and "ffmpeg" not in answer
        check(row, ok, str(answer)[:240])

    attempt(["F1"], lambda: plain("F1", "Shoot"))
    attempt(["F2"], lambda: plain("F2", "Shoot.mov"))

    def f3():
        answer = try_import(project, "clip.flv")
        check("F3", isinstance(answer, str) and "An installed ffmpeg could convert it" in answer,
              str(answer)[:240])

    attempt(["F3"], f3)
    attempt(["F4"], lambda: plain("F4", "ShootLink"))
    project.close()


# ---- packages ---------------------------------------------------------------------------

def make_packages(client, packages):
    """One real project saved by the app under test, and its damaged copies."""
    good = packages / "good.framejob"
    packages.mkdir()
    client.call_with("new_project", {"path": str(good)})
    args = {"project": str(good)}
    answer = client.call_with("import_media", dict(args, path=str(MEDIA / "AV.mov")))
    state = client.call_with("get_project", args)
    client.call_with("add_clip", dict(args, track=state["project"]["tracks"][0]["id"],
                                      media=answer["media"], at=0))
    client.call_with("save_project", args)
    client.call_with("close_project", args)

    outside = packages / "a-folder"
    outside.mkdir()
    real = packages / "real-project.json"
    shutil.copy(good / "project.json", real)

    def variant(name, change):
        path = packages / f"{name}.framejob"
        shutil.copytree(good, path, symlinks=True)
        target = path / "project.json"
        target.unlink()
        change(target)

    variant("folder", lambda t: t.mkdir())
    variant("linkfolder", lambda t: os.symlink(outside, t))
    variant("linkfile", lambda t: os.symlink(real, t))
    variant("dangling", lambda t: os.symlink(packages / "gone.json", t))
    variant("missing", lambda t: None)
    variant("notutf8", lambda t: t.write_bytes(b"\xff\xfe\x00not json \xe9"))


def attach(pid, transcript):
    """lldb on `pid`, running: an abort stops there and is killed, so no crash report window."""
    with open(transcript, "w") as out:
        debugger = subprocess.Popen(
            ["lldb", "--batch", "-p", str(pid), "-o", "continue", "-k", "thread backtrace -c 16",
             "-k", "process kill"],
            stdin=subprocess.DEVNULL, stdout=out, stderr=subprocess.STDOUT)
    began = time.monotonic()
    while time.monotonic() - began < 30:
        if "(lldb) continue" in open(transcript, errors="replace").read():
            time.sleep(1.5)
            return debugger
        time.sleep(0.1)
    debugger.terminate()
    raise RuntimeError("lldb did not attach: " + open(transcript, errors="replace").read()[-300:])


def alive(pid):
    """`Popen.poll` cannot answer this: a debugger's attach makes `waitpid` fail, read as exit 0."""
    state = subprocess.run(["ps", "-p", str(pid), "-o", "stat="], capture_output=True, text=True,
                           timeout=30).stdout.strip()
    return bool(state) and not state.startswith("Z")


def stop_pid(pid, debugger):
    """The instance `package_row` launched, ended by its pid; lldb goes with it."""
    if alive(pid):
        os.kill(pid, signal.SIGTERM)
    began = time.monotonic()
    while alive(pid) and time.monotonic() - began < 15:
        time.sleep(0.1)
    if alive(pid):
        os.kill(pid, signal.SIGKILL)
    if debugger is not None:
        try:
            debugger.wait(timeout=30)
        except subprocess.TimeoutExpired:
            debugger.kill()


def package_row(binary, packages, row, name, opens):
    launched = start(binary, row)
    debugger = None
    pid = launched.child.pid
    try:
        if launched.client is None:
            check(row, False, "the app did not listen")
            return
        if "Debug" in Path(binary).name:
            debugger = attach(pid, LOGS / f"{row}.lldb.txt")
        client = mcp.MCP(launched.socket_path, timeout=OPEN_BOUND)
        path = str(packages / f"{name}.framejob")
        answer = {}

        def send():
            try:
                answer["project"] = client.call_with("open_project", {"path": path})
            except mcp.ToolError as error:
                answer["refused"] = str(error)
            except Exception as error:  # noqa: BLE001  the connection going is the crash's trace
                answer["transport"] = f"{type(error).__name__}: {error}"

        sender = threading.Thread(target=send, daemon=True)
        sender.start()
        sender.join(OPEN_BOUND + 5)
        dead = not alive(pid) or (debugger is not None and debugger.poll() is not None)
        said = str(answer.get("refused") or answer.get("transport") or answer.get("project"))[:200]
        if dead or "transport" in answer or not answer:
            stopped = ""
            if debugger is not None:
                text = open(LOGS / f"{row}.lldb.txt", errors="replace").read()
                stopped = [line.strip() for line in text.splitlines() if "stop reason" in line]
                stopped = stopped[-1] if stopped else ""
            check(row, False, f"the instance died: {said} {stopped[:120]}")
            return
        if opens:
            state = client.call_with("get_project", {"project": path})
            clips = len(state["project"]["clips"])
            client.call_with("close_project", {"project": path, "discard": True})
            check(row, "project" in answer and clips == 1, f"{name}: {clips} clip, {said[:80]}")
            return
        want = f"open_project: {name}.framejob {NOT_READABLE}"
        answers = bool(client.tools())
        check(row, answer.get("refused") == want and answers and alive(pid),
              f"{name}: {said}, a later call answers {answers}")
    finally:
        stop_pid(pid, debugger)


PACKAGES = {"P1": ("folder", False), "P2": ("linkfolder", False), "P3": ("linkfile", True),
            "P4": ("dangling", False), "P5": ("missing", False), "P6": ("notutf8", False),
            "P7": ("good", True)}


def package_rows(binary, packages):
    for row, (name, opens) in PACKAGES.items():
        attempt([row], lambda row=row, name=name, opens=opens:
                package_row(binary, packages, row, name, opens))


# ---- the probe --------------------------------------------------------------------------

def build_probe(sources):
    """(binary, None) or (None, why): a probe that will not build fails its rows."""
    OUT.mkdir(parents=True, exist_ok=True)
    entry = OUT / "main.swift"
    shutil.copyfile(PROBE, entry)
    binary = OUT / "docs-bugs-b2-probe"
    try:
        swift_build.build(sources=swift_build.app_sources(sources) + [entry], output=binary)
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + "; ".join([str(error)] + list(error.diagnostics[:8]))
    return binary, None


def probe_rows(binary, packages):
    env = bounded.child_env({"CFFIXED_USER_HOME": str(HOME)})
    done = subprocess.run([str(binary), str(FILES), str(packages / "good.framejob")],
                          capture_output=True, text=True, env=env, timeout=PROBE_BOUND, cwd=OUT,
                          stdin=subprocess.DEVNULL)
    rows = {}
    for line in done.stdout.splitlines():
        if line.startswith("{"):
            answer = json.loads(line)
            rows[answer["row"]] = answer
    if done.returncode != 0 or "PB" not in rows:
        raise RuntimeError(f"exit {done.returncode}, rows {sorted(rows)}: {done.stderr[-300:]}")
    if not rows["policy"]["tools_found"]:
        raise RuntimeError("the probe found no ffmpeg, so its rows would not reach the consent")

    def landed(row, name):
        return next((m for m in rows[row]["media_after"] if m["name"] == name), None)

    def still(row, name, *more):
        answer, media = rows[row], landed(row, name)
        ok = (media is not None and media["kind"] == "image" and not answer["alerts"]
              and not answer["modals"] and all(more))
        check(row, ok, f"{media}, alerts {answer['alerts']}, consent "
                       f"{[m['message'] for m in answer['modals']]}")

    still("D1", "x.avif", rows["D1"]["performDragOperation"])
    still("D2", "y.avif", rows["D2"]["clips_after"] == rows["D2"]["clips_before"] + 1)
    still("D3", "still.png", rows["D3"]["performDragOperation"])

    def imported_quietly(row):
        answer = rows[row]
        ok = not answer["alerts"] and answer["clips_after"] == answer["clips_before"] + 1
        check(row, ok, f"clips {answer['clips_before']} → {answer['clips_after']}, alerts "
                       f"{answer['alerts']}")

    for row in ("C1", "C2", "C3"):
        imported_quietly(row)
    message = rows["C2"]["panel_message"]
    check("C4", "WebVTT" in message, repr(message))
    check("PB", rows["PB"]["unchanged"], f"unchanged {rows['PB']['unchanged']}")


# ---- the run ----------------------------------------------------------------------------

def run(binary, sources):
    packages = WORK / "packages"
    probe, why = (None, None)
    if selected & set(PROBE_ROWS):
        probe, why = build_probe(sources)
        if why:
            for row in sorted(selected & set(PROBE_ROWS)):
                check(row, False, f"the probe did not build: {why}")
    needs_packages = selected & (set(PACKAGE_ROWS) | set(PROBE_ROWS))
    launched = start(binary, "main")
    try:
        if launched.client is None:
            for row in sorted(selected - {"Z1"}):
                check(row, False, "the app did not listen")
            return
        client = launched.client
        if selected & set(CAPTION_ROWS):
            caption_rows(client)
        if selected & set(AVIF_ROWS):
            avif_rows(client)
        if selected & set(FOLDER_ROWS):
            folder_rows(client)
        if needs_packages:
            attempt(sorted(needs_packages), lambda: make_packages(client, packages))
    finally:
        launched.stop()
    policy_row(binary, "A2", ["-RCFFmpegPath", "/nonexistent/ffmpeg"])
    policy_row(binary, "A3", ["-RCFFmpegImport", "always"])
    package_rows(binary, packages)
    if probe is not None:
        attempt(sorted(set(PROBE_ROWS)), lambda: probe_rows(probe, packages))


def mutate(name):
    """(the copy, None) or (None, why): the tree copy with the mutant's edits."""
    made, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made is None:
        return None, reason
    for path, anchor, replacement in MUTANTS[name][1]:
        target = Path(made) / path
        text = target.read_text()
        if text.count(anchor) != 1:
            return None, f"the anchor occurs {text.count(anchor)} times in {path}: {anchor[:60]!r}"
        target.write_text(text.replace(anchor, replacement))
    return Path(made), None


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
        selected = {MUTANTS[args.mutant][0], "Z1"}
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
        print(f"docs bugs b2 — the {args.mutant} MUTANT ({MUTANTS[args.mutant][0]} must FAIL)",
              flush=True)
        made, why = mutate(args.mutant)
        if why is None:
            app, why = tree_copy.build_app(made, BUILD_BOUND)
            binary = proof_app.executable(app) if app else None
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
    if binary is None:
        binary = proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    print(f"docs bugs b2 — caption files, AVIF, an unreadable project.json ({binary.name})",
          flush=True)

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
        row = MUTANTS[args.mutant][0]
        if row not in results:
            print(f"mutant {args.mutant}: the control could not be performed — its row was "
                  f"never scored")
            return 2
        caught = row in failed
        print(f"MUTANT {args.mutant} {'CAUGHT' if caught else 'SURVIVED'}: {row} "
              f"{'failed' if caught else 'passed'}", flush=True)
        return 1 if caught else 0
    if args.expect_red:
        wrong = [r for r in failed if r in CONTROLS] + [r for r in passed if r not in CONTROLS]
        print("expected red, every row not marked (c) failing and every (c) passing: "
              + ("held" if not wrong else f"NOT held for {wrong}"), flush=True)
        return 1 if wrong else 0
    return 0 if not failed and results else 1


if __name__ == "__main__":
    sys.exit(main())
