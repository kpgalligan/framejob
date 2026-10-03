#!/usr/bin/env python3
"""Issue batch B72 — VP9 and AV1 in MP4 import, play and export, and what
will not decode is refused at import with a sentence naming the codec
(spec §11 #216), proved over MCP on an instance this script launches.

    python3 tools/proof/codec_import_proof.py [--mutant NAME]

Launches the Release build on a scratch socket of its own (spec §11 MC-6;
frame_grid_proof.py's launch and parity log) and kills only that process.

**Fixtures**, made with ffmpeg in a temporary directory: one 2 s AAC sine
stream, copied into a 640×360 30 fps 2 s `testsrc2` VP9 Profile 0 MP4 and
its H.264 twin; a VP9 Profile 1 (4:4:4) MP4; an AV1 MP4.

Rows:
- **R0**: no `Reelcut: ` line in the instance's log (the parity check).
- **R1**: `import_media` of the VP9 P0 file answers `has_video`, 640×360,
  `[30, 1]` and `has_audio`, and `add_clip` places it.
- **R2**: `render_frame` at 0.5 s is byte-identical twice, differs from
  1.5 s, and differs from 2.5 s, past the clip's end (the canvas). A frame
  past the timeline's end is refused, so the 2.5 s frame is taken with a
  second clip of the same media placed at 3 s, which `undo` then removes.
- **R3**: `export` h264 writes a file; ffmpeg decodes its frames at 0.5 s
  and 1.5 s to differing bytes; its audio, decoded to s16le PCM, equals the
  H.264 twin project's export sample for sample.
- **R4**: `import_media` of the P1 file errors with exactly the Profile 1
  sentence, and `get_project`'s media count is unchanged.
- **R5**: AV1, by `sysctl machdep.cpu.brand_string`: an "Apple M1"/"Apple
  M2" must error with exactly the M3 sentence; an M3 or later must import
  and pass R2's checks; any other brand is skipped by name.

Mutants, each of which must exit 1: `p1-as-p0` imports the P1 file in R1's
place (R1 FAIL); `p0-as-p1` imports the P0 file in R4's place (R4 FAIL).
Every document is closed with `close_project`. Rows print
`<ID> ok|FAIL|skip — <detail>`, then `passed n/m`; exit 0 iff none failed.
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(__file__))
from mcp import MCP, ToolError, remove_scratch, scratch_socket, wait_listening  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SEC = 600_000
RATE = 48000
VIDEO_IN = ["-f", "lavfi", "-i", "testsrc2=size=640x360:rate=30:duration=2"]

rows = []


def row(row_id, ok, detail):
    """ok is True, False or None (skipped by name)."""
    rows.append((row_id, ok))
    word = "skip" if ok is None else ("ok" if ok else "FAIL")
    print(f"{row_id} {word} — {detail}", flush=True)


def ffmpeg(*arguments, timeout=120):
    subprocess.run(["ffmpeg", "-v", "error", "-y", *arguments], check=True, timeout=timeout,
                   capture_output=True)


def make_fixtures(where):
    sine = os.path.join(where, "sine.m4a")
    ffmpeg("-f", "lavfi", "-i", f"sine=frequency=440:sample_rate={RATE}:duration=2",
           "-c:a", "aac", sine)
    paths = {}
    for name, codec in (("vp9_p0.mp4", ["-c:v", "libvpx-vp9", "-pix_fmt", "yuv420p"]),
                        ("h264_twin.mp4", ["-c:v", "libx264", "-pix_fmt", "yuv420p"])):
        paths[name] = os.path.join(where, name)
        ffmpeg(*VIDEO_IN, "-i", sine, "-map", "0:v", "-map", "1:a", *codec, "-c:a", "copy",
               paths[name])
    for name, codec in (("vp9_p1.mp4", ["-c:v", "libvpx-vp9", "-pix_fmt", "yuv444p",
                                         "-profile:v", "1"]),
                        ("av1.mp4", ["-c:v", "libsvtav1", "-pix_fmt", "yuv420p"])):
        paths[name] = os.path.join(where, name)
        ffmpeg(*VIDEO_IN, *codec, paths[name])
    return paths


def p1_sentence(name):
    return (f"{name} is VP9 Profile 1 video, which this Mac cannot decode; "
            "VP9 Profiles 0 and 2 import.")


def av1_sentence(name):
    return f"{name} is AV1 video, which needs an M3 or later Mac."


def check_parity(log_path):
    with open(log_path, encoding="utf-8", errors="replace") as stream:
        lines = stream.read().splitlines()
    return lines, [line for line in lines if "Reelcut: " in line]


def read(path):
    with open(path, "rb") as stream:
        return stream.read()


def render(mcp, project, where, name, t):
    path = os.path.join(where, f"{name}.png")
    mcp.call("render_frame", project=project, t=int(t), path=path)
    return read(path)


def frames(mcp, project, media, where, label):
    """PNG bytes at 0.5 s, 0.5 s, 1.5 s and 2.5 s. The last is in a gap: a
    second clip of `media` at 3 s keeps 2.5 s inside the timeline, and is
    undone straight after, so the project is as it was."""
    shots = [render(mcp, project, where, f"{label}-{index}", t)
             for index, t in enumerate([0.5 * SEC, 0.5 * SEC, 1.5 * SEC])]
    track = mcp.call("get_project", project=project)["project"]["tracks"][0]["id"]
    mcp.call("add_clip", project=project, track=track, media=media, at=3 * SEC)
    shots.append(render(mcp, project, where, f"{label}-3", 2.5 * SEC))
    mcp.call("undo", project=project)
    return shots


def frame_rows(row_id, shots):
    """R2's checks over [0.5 s, 0.5 s, 1.5 s, 2.5 s]."""
    row(row_id + "a", shots[0] == shots[1], "0.5 s rendered twice is byte-identical")
    row(row_id + "b", shots[0] != shots[2], "0.5 s differs from 1.5 s")
    row(row_id + "c", shots[0] != shots[3], "0.5 s differs from 2.5 s (past the clip's end)")


def new_project(mcp, where, name):
    path = os.path.join(where, f"{name}.reelcut")
    mcp.call("new_project", path=path)
    return path


def media_count(mcp, project):
    return len(mcp.call("get_project", project=project)["project"]["media"])


def place(mcp, project, media):
    track = mcp.call("get_project", project=project)["project"]["tracks"][0]["id"]
    return mcp.call("add_clip", project=project, track=track, media=media, at=0)["new_clips"]


def video_frame(path, seconds):
    return subprocess.run(
        ["ffmpeg", "-v", "error", "-ss", str(seconds), "-i", path, "-frames:v", "1",
         "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        check=True, timeout=120, capture_output=True).stdout


def pcm(path):
    return subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-vn", "-f", "s16le", "-acodec", "pcm_s16le",
         "-ar", str(RATE), "-ac", "2", "-"],
        check=True, timeout=120, capture_output=True).stdout


def export(mcp, project, where, label):
    target = os.path.join(where, f"{label}.mp4")
    result = mcp.call("export", project=project, preset="h264", path=target, size=[640, 360])
    return result["path"]


def run(mcp, where, fixtures, mutant):
    p0 = fixtures["vp9_p1.mp4" if mutant == "p1-as-p0" else "vp9_p0.mp4"]
    p1 = fixtures["vp9_p0.mp4" if mutant == "p0-as-p1" else "vp9_p1.mp4"]
    vp9 = new_project(mcp, where, "vp9")
    twin = new_project(mcp, where, "twin")
    opened = [vp9, twin]
    try:
        # R1
        placed = False
        media = None
        try:
            answer = mcp.call("import_media", project=vp9, path=p0)
            shape = (answer["has_video"], answer["width"], answer["height"], answer["fps"],
                     answer["has_audio"])
            media = answer["media"]
            clips = place(mcp, vp9, media)
            placed = bool(clips)
            row("R1", shape == (True, 640, 360, [30, 1], True) and placed,
                f"has_video, size, fps, has_audio = {shape}; add_clip placed {clips}")
        except ToolError as error:
            row("R1", False, f"import refused: {error}")
        # R2
        if placed:
            frame_rows("R2", frames(mcp, vp9, media, where, "vp9"))
        else:
            for suffix in "abc":
                row("R2" + suffix, False, "R1 placed no clip")
        # R3
        if placed:
            movie = export(mcp, vp9, where, "vp9-export")
            row("R3a", os.path.getsize(movie) > 0, f"export h264 wrote {os.path.getsize(movie)} "
                f"bytes")
            early, late = video_frame(movie, 0.5), video_frame(movie, 1.5)
            row("R3b", bool(early) and early != late,
                f"decoded frames at 0.5 s and 1.5 s: {len(early)} and {len(late)} bytes, "
                f"{'differ' if early != late else 'identical'}")
            twin_media = mcp.call("import_media", project=twin,
                                  path=fixtures["h264_twin.mp4"])["media"]
            place(mcp, twin, twin_media)
            ours, theirs = pcm(movie), pcm(export(mcp, twin, where, "twin-export"))
            row("R3c", bool(ours) and ours == theirs,
                f"audio s16le: {len(ours)} vs the H.264 twin's {len(theirs)} bytes, "
                f"{'equal' if ours == theirs else 'different'}")
        else:
            for suffix in "abc":
                row("R3" + suffix, False, "R1 placed no clip")
        # R4
        before = media_count(mcp, vp9)
        expected = p1_sentence(os.path.basename(fixtures["vp9_p1.mp4"]))
        try:
            answer = mcp.call("import_media", project=vp9, path=p1)
            row("R4", False, f"imported as media {answer.get('media')}")
        except ToolError as error:
            message = str(error).split(": ", 1)[-1]
            after = media_count(mcp, vp9)
            row("R4", message == expected and after == before,
                f"error {message!r}; media {before} → {after}")
        # R5
        brand = subprocess.run(["sysctl", "-n", "machdep.cpu.brand_string"], timeout=30,
                               capture_output=True, text=True).stdout.strip()
        family = re.match(r"Apple M(\d+)", brand)
        av1 = fixtures["av1.mp4"]
        if family is None:
            row("R5", None, f"CPU {brand!r} is not an Apple M-series chip")
        elif int(family.group(1)) <= 2:
            check = new_project(mcp, where, "av1")
            opened.append(check)
            before = media_count(mcp, check)
            try:
                answer = mcp.call("import_media", project=check, path=av1)
                row("R5", False, f"{brand}: AV1 imported as media {answer.get('media')}")
            except ToolError as error:
                message = str(error).split(": ", 1)[-1]
                expected = av1_sentence(os.path.basename(av1))
                after = media_count(mcp, check)
                row("R5", message == expected and after == before,
                    f"{brand}: error {message!r}; media {before} → {after}")
        else:
            check = new_project(mcp, where, "av1")
            opened.append(check)
            try:
                answer = mcp.call("import_media", project=check, path=av1)
                clips = place(mcp, check, answer["media"])
                row("R5", bool(clips), f"{brand}: AV1 imported and placed {clips}")
                frame_rows("R5", frames(mcp, check, answer["media"], where, "av1"))
            except ToolError as error:
                row("R5", False, f"{brand}: AV1 refused: {error}")
    finally:
        for path in opened:
            mcp.call("close_project", project=path, discard=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mutant", choices=["p1-as-p0", "p0-as-p1"])
    parser.add_argument("--app", default=os.path.join(ROOT, "build", "Build", "Products",
                                                     "Release", "Reelcut.app"))
    args = parser.parse_args()
    binary = os.path.join(args.app, "Contents", "MacOS", "Reelcut")
    if not os.path.isfile(binary):
        print("instrument failure: no app binary at " + binary)
        return 2
    with tempfile.TemporaryDirectory(prefix="reelcut-codec-import-") as work:
        fixtures = make_fixtures(work)
        log_path = os.path.join(work, "app.log")
        socket_path = scratch_socket()
        with open(log_path, "w", encoding="utf-8") as log:
            env = os.environ.copy()
            env["RC_AGENT_SOCKET"] = socket_path
            app = subprocess.Popen([binary, "-ApplePersistenceIgnoreState", "YES"],
                                   stdout=log, stderr=subprocess.STDOUT, env=env)
            try:
                if not wait_listening(log_path, socket_path, child=app, seconds=20):
                    print(f"instrument failure: the app did not listen at {socket_path}")
                    return 2
                run(MCP(socket_path, timeout=180), work, fixtures, args.mutant)
                complaints = check_parity(log_path)[1]
                row("R0", not complaints,
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
    passed = sum(1 for _, ok in rows if ok)
    scored = sum(1 for _, ok in rows if ok is not None)
    failed = sum(1 for _, ok in rows if ok is False)
    print(f"passed {passed}/{scored}" + (f" (mutant {args.mutant})" if args.mutant else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
