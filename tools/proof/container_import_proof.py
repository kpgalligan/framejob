#!/usr/bin/env python3
"""Issue batch B73 — a WebM or Matroska file imports by the built-in rewrap
(spec §11 #216-R), proved over MCP on an instance this script launches.

    python3 tools/proof/container_import_proof.py [--mutant ffmpeg-copy]

Launches the Release build on a scratch socket of its own (spec §11 MC-6)
with `-RCFFmpegImport never` (so a
codec the copy refuses is never handed to a stored "always" policy) and
kills only that process. It runs over the instance's REAL
`~/Library/Application Support/Reelcut/Rewrapped/`: cleanup removes only the
`<stem>-<16 hex>.mov` files this run created there, each parent-checked.

**Fixtures**, made with ffmpeg in a temporary directory, 640×360
`testsrc2` with a 440 Hz sine, 2 s: P1 VP9+Opus WebM, P2 the same at
30000/1001, P3 H.264+AAC MKV, P7 AV1+Opus WebM, P9 VP8 WebM, P10 VP9+Vorbis
WebM.

Rows:
- **M0**: no `Reelcut: ` line in the instance's log (the parity check).
- **M1**: `import_media` of P1 answers a `.mov` directly inside
  `Rewrapped/` named `p1-<16 hex>.mov`, 640×360, `[30, 1]`, `has_audio`.
- **M2**: on a canvas at five times the media's rate (`render_frame` snaps
  `t` to the canvas grid, so ±0.4 frame must be ON it), the frame at 47/30 s
  is byte-identical to the one 0.4 frame later and differs from the one 0.4
  frame earlier; M2b the same for P2 at 47 × 1001/30000 s.
- **M3**: importing P1 again, into a second project, answers the same
  path, its mtime unchanged.
- **M4**: P3 imports with `has_audio`; an H.264 export of its clip lasts
  2 s (±0.05) and its audio's RMS is over 0.01.
- **M5**: VP8, Vorbis and AV1 answer their exact sentences with the media
  count and the `Rewrapped/` listing unchanged; AV1 by `sysctl
  machdep.cpu.brand_string` (an M1/M2 refuses, an M3 or later imports, any
  other brand is skipped by name).
- **M6**: every document is closed with `close_project`.

`--mutant ffmpeg-copy` imports ffmpeg's `-c copy` MP4 of P1 in M2's place:
M2 must fail (that copy lands frame 47 a frame early) and nothing else, and
then it prints MUTANT PASS and exits 0. Rows print `<ID> ok|FAIL|skip —
<detail>`, then `passed n/m`; without a mutant, exit 0 iff none failed.
"""

import argparse
import math
import os
import re
import struct
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(__file__))
from mcp import MCP, ToolError, remove_scratch, scratch_socket, wait_listening  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SEC = 600_000
REWRAPPED = os.path.expanduser("~/Library/Application Support/Reelcut/Rewrapped")
DIGEST_NAME = re.compile(r"^[A-Za-z0-9_-]+-[0-9a-f]{16}\.mov$")

rows = []


def row(row_id, ok, detail):
    rows.append((row_id, ok))
    word = "skip" if ok is None else ("ok" if ok else "FAIL")
    print(f"{row_id} {word} — {detail}", flush=True)


def ffmpeg(*arguments, timeout=180):
    subprocess.run(["ffmpeg", "-v", "error", "-y", *arguments], check=True, timeout=timeout,
                   capture_output=True)


def make_fixtures(where):
    def inputs(rate="30"):
        return ["-f", "lavfi", "-i", f"testsrc2=size=640x360:rate={rate}:duration=2",
                "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=2"]
    vp9 = ["-c:v", "libvpx-vp9", "-pix_fmt", "yuv420p", "-b:v", "500k"]
    table = {
        "p1.webm": inputs() + vp9 + ["-c:a", "libopus"],
        "p2.webm": inputs("30000/1001") + vp9 + ["-c:a", "libopus"],
        "p3.mkv": inputs() + ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-bf", "2",
                              "-c:a", "aac"],
        "p7.webm": inputs() + ["-c:v", "libsvtav1", "-pix_fmt", "yuv420p", "-c:a", "libopus"],
        "p9.webm": inputs() + ["-c:v", "libvpx", "-pix_fmt", "yuv420p", "-c:a", "libopus"],
        "p10.webm": inputs() + vp9 + ["-c:a", "vorbis", "-strict", "-2", "-ac", "2"],
    }
    paths = {}
    for name, arguments in table.items():
        paths[name] = os.path.join(where, name)
        ffmpeg(*arguments, paths[name])
    paths["p1-copy.mp4"] = os.path.join(where, "p1-copy.mp4")
    ffmpeg("-i", paths["p1.webm"], "-c", "copy", paths["p1-copy.mp4"])
    return paths


def check_parity(log_path):
    with open(log_path, encoding="utf-8", errors="replace") as stream:
        lines = stream.read().splitlines()
    return lines, [line for line in lines if "Reelcut: " in line]


def listing():
    return sorted(os.listdir(REWRAPPED)) if os.path.isdir(REWRAPPED) else []


def read(path):
    with open(path, "rb") as stream:
        return stream.read()


def new_project(mcp, where, name, opened):
    path = os.path.join(where, f"{name}.reelcut")
    mcp.call("new_project", path=path)
    opened.append(path)
    return path


def media_count(mcp, project):
    return len(mcp.call("get_project", project=project)["project"]["media"])


def place(mcp, project, media):
    track = mcp.call("get_project", project=project)["project"]["tracks"][0]["id"]
    return mcp.call("add_clip", project=project, track=track, media=media, at=0)["new_clips"]


def frame_row(mcp, where, row_id, project, path, fps, frame_ticks, step):
    """Imports `path`, sets the canvas to five times its rate, and renders
    frame 47 and ±0.4 frame (`step` ticks)."""
    answer = mcp.call("import_media", project=project, path=path)
    mcp.call("set_canvas", project=project, width=640, height=360,
             fps=[fps[0] * 5, fps[1]])
    place(mcp, project, answer["media"])
    shots = []
    for label, t in (("at", frame_ticks), ("after", frame_ticks + step),
                     ("before", frame_ticks - step)):
        target = os.path.join(where, f"{row_id}-{label}.png")
        mcp.call("render_frame", project=project, t=t, path=target)
        shots.append(read(target))
    row(row_id, shots[0] == shots[1] and shots[0] != shots[2],
        f"{os.path.basename(path)}: frame 47 (t {frame_ticks}) "
        f"{'equals' if shots[0] == shots[1] else 'differs from'} +0.4 frame and "
        f"{'differs from' if shots[0] != shots[2] else 'equals'} −0.4 frame")


def audio_rms(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-vn", "-f", "s16le", "-ac", "1",
                          "-ar", "48000", "-"], check=True, timeout=120,
                         capture_output=True).stdout
    count = len(raw) // 2
    if not count:
        return 0.0
    values = struct.unpack(f"<{count}h", raw[:count * 2])
    return math.sqrt(sum(v * v for v in values) / count) / 32768


def duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                          "-of", "csv=p=0", path], check=True, timeout=60,
                         capture_output=True, text=True).stdout.strip()
    return float(out) if out not in ("", "N/A") else None


def refusal_row(mcp, where, row_id, path, sentence, opened):
    project = new_project(mcp, where, row_id.lower(), opened)
    before, files = media_count(mcp, project), listing()
    try:
        answer = mcp.call("import_media", project=project, path=path)
        row(row_id, False, f"{os.path.basename(path)} imported as media {answer.get('media')}")
    except ToolError as error:
        message = str(error).split(": ", 1)[-1]
        after = media_count(mcp, project)
        good = message == sentence and after == before and listing() == files
        row(row_id, good, f"{os.path.basename(path)}: {message!r}; media {before} → {after}; "
            f"Rewrapped/ {'unchanged' if listing() == files else 'CHANGED'}")


def run(mcp, where, fixtures, mutant):
    opened = []
    try:
        # M1
        p1 = new_project(mcp, where, "p1", opened)
        copy_path = None
        try:
            answer = mcp.call("import_media", project=p1, path=fixtures["p1.webm"])
            copy_path = answer["path"]
            shape = (os.path.dirname(copy_path) == REWRAPPED,
                     bool(re.match(r"^p1-[0-9a-f]{16}\.mov$", os.path.basename(copy_path))),
                     answer["width"], answer["height"], answer["fps"], answer["has_audio"])
            row("M1", shape == (True, True, 640, 360, [30, 1], True),
                f"path {copy_path}; in Rewrapped, named, size, fps, has_audio = {shape}")
        except ToolError as error:
            row("M1", False, f"import refused: {error}")
        # M2
        source = fixtures["p1-copy.mp4" if mutant == "ffmpeg-copy" else "p1.webm"]
        m2 = new_project(mcp, where, "m2", opened)
        frame_row(mcp, where, "M2", m2, source, [30, 1], 47 * SEC // 30, SEC * 4 // 300)
        m2b = new_project(mcp, where, "m2b", opened)
        frame_row(mcp, where, "M2b", m2b, fixtures["p2.webm"], [30000, 1001], 47 * 20020, 8008)
        # M3
        if copy_path:
            stamp = os.stat(copy_path).st_mtime_ns
            # Into another project: the same path twice in one project is an
            # identity, which says nothing about the copy.
            m3 = new_project(mcp, where, "m3", opened)
            again = mcp.call("import_media", project=m3, path=fixtures["p1.webm"])
            row("M3", again["path"] == copy_path and os.stat(copy_path).st_mtime_ns == stamp,
                f"second import answered {again['path']}; mtime "
                f"{'unchanged' if os.stat(copy_path).st_mtime_ns == stamp else 'CHANGED'}")
        else:
            row("M3", False, "M1 made no copy")
        # M4
        p3 = new_project(mcp, where, "p3", opened)
        try:
            answer = mcp.call("import_media", project=p3, path=fixtures["p3.mkv"])
            place(mcp, p3, answer["media"])
            target = os.path.join(where, "p3-export.mp4")
            movie = mcp.call("export", project=p3, preset="h264", path=target,
                             size=[640, 360])["path"]
            seconds, rms = duration(movie), audio_rms(movie)
            row("M4", answer["has_audio"] and seconds is not None
                and abs(seconds - 2.0) <= 0.05 and rms > 0.01,
                f"has_audio {answer['has_audio']}; export {seconds} s, audio RMS {rms:.4f}")
        except ToolError as error:
            row("M4", False, f"refused: {error}")
        # M5
        refusal_row(mcp, where, "M5a", fixtures["p9.webm"],
                    "p9.webm is VP8 video, which this Mac cannot decode.", opened)
        refusal_row(mcp, where, "M5b", fixtures["p10.webm"],
                    "p10.webm has Vorbis audio, which Reelcut cannot copy out of a WebM or "
                    "Matroska file.", opened)
        brand = subprocess.run(["sysctl", "-n", "machdep.cpu.brand_string"], timeout=30,
                               capture_output=True, text=True).stdout.strip()
        family = re.match(r"Apple M(\d+)", brand)
        if family is None:
            row("M5c", None, f"CPU {brand!r} is not an Apple M-series chip")
        elif int(family.group(1)) <= 2:
            refusal_row(mcp, where, "M5c", fixtures["p7.webm"],
                        "p7.webm is AV1 video, which needs an M3 or later Mac.", opened)
        else:
            p7 = new_project(mcp, where, "p7", opened)
            try:
                answer = mcp.call("import_media", project=p7, path=fixtures["p7.webm"])
                row("M5c", answer["has_video"], f"{brand}: AV1 imported, {answer['path']}")
            except ToolError as error:
                row("M5c", False, f"{brand}: AV1 refused: {error}")
    finally:
        closed = True
        for path in opened:
            try:
                mcp.call("close_project", project=path, discard=True)
            except ToolError as error:
                closed = False
                print(f"close_project {path}: {error}")
        row("M6", closed, f"{len(opened)} documents closed")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mutant", choices=["ffmpeg-copy"])
    parser.add_argument("--app", default=os.path.join(ROOT, "build", "Build", "Products",
                                                     "Release", "Reelcut.app"))
    args = parser.parse_args()
    binary = os.path.join(args.app, "Contents", "MacOS", "Reelcut")
    if not os.path.isfile(binary):
        print("instrument failure: no app binary at " + binary)
        return 2
    before = set(listing())
    with tempfile.TemporaryDirectory(prefix="reelcut-container-import-") as work:
        fixtures = make_fixtures(work)
        log_path = os.path.join(work, "app.log")
        socket_path = scratch_socket()
        with open(log_path, "w", encoding="utf-8") as log:
            env = os.environ.copy()
            env["RC_AGENT_SOCKET"] = socket_path
            app = subprocess.Popen([binary, "-ApplePersistenceIgnoreState", "YES", "-RCFFmpegImport", "never"],
                                   stdout=log, stderr=subprocess.STDOUT, env=env)
            try:
                if not wait_listening(log_path, socket_path, child=app, seconds=20):
                    print(f"instrument failure: the app did not listen at {socket_path}")
                    return 2
                run(MCP(socket_path, timeout=300), work, fixtures, args.mutant)
                complaints = check_parity(log_path)[1]
                row("M0", not complaints,
                    "no `Reelcut: ` line in the log" if not complaints
                    else " | ".join(complaints))
            finally:
                if app.poll() is None:
                    app.terminate()
                    try:
                        app.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        app.kill()
                        app.wait(timeout=5)
                remove_scratch(socket_path)
                # Only the digest names this run created, directly inside
                # Rewrapped/ (parent-checked), go.
                for name in sorted(set(listing()) - before):
                    path = os.path.join(REWRAPPED, name)
                    if DIGEST_NAME.match(name) and os.path.dirname(path) == REWRAPPED:
                        os.remove(path)
                        print(f"cleanup: removed Rewrapped/{name}")
    passed = sum(1 for _, ok in rows if ok)
    scored = sum(1 for _, ok in rows if ok is not None)
    failed = {row_id for row_id, ok in rows if ok is False}
    print(f"passed {passed}/{scored}" + (f" (mutant {args.mutant})" if args.mutant else ""))
    if args.mutant:
        good = failed == {"M2"}
        print(f"{'MUTANT PASS' if good else 'MUTANT FAIL'}: {args.mutant} failed "
              f"{sorted(failed)}, expected ['M2']")
        return 0 if good else 1
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
