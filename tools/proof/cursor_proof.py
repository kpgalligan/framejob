#!/usr/bin/env python3
"""Road map creator-jobs CU1b1 — the recorder saves the cursor, on real recordings: the granted
tier of spec §11 CU-19. Every row needs the Screen Recording grant and an unlocked console and
is SKIPPED by name without them; K5 also needs this process to post input.

    RC_PROOF_APP=release python3 tools/proof/cursor_proof.py [--only K4,K5,…] [--app PATH]

`cursor_proof.swift` is built through `swift_build.py` over `app/Sources` (it links
`libframejob_core.a`) and drives `ScreenRecorder.shared` in-process, recording_probe's granted
pattern, into `tools/proof/work/cursor-proof/recordings/`. It WARPS THE POINTER and puts a grey
1001 × 701 pt window on the main display for a few seconds: keep your hands off the mouse.

Rows:
  K4  display recordings at Nominal and at Best, each paused and resumed, the pointer warped
      (`CGWarpMouseCursorPosition`) three times in each segment: each segment lands its own
      `<stem>.fjcursor` beside its movie, accepted by `ReelCursor`, with `source` display,
      `anchor` e1, `cursor_image` none, `movie_size` the movie's track size (ffprobe), and
      every point warped in that segment among its moves within 1 pt.
  K5  a mouse-down and a mouse-up posted onto the probe's window: the file's clicks hold both,
      down then up, at the posted point within 1 pt. Skipped by name without
      `CGPreflightPostEventAccess`.
  K7  a directory at `<stem>.fjcursor.partial` for the recording's stem: the movie lands, the
      segment has no cursor file, and its `cursorProblem` is the writer's sentence ("The cursor
      file <stem>.fjcursor could not be written: …"), said in the result's note.
  K8  the probe's own 1001 × 701 pt window at Nominal: `source` window, `movie_size` the
      movie's track size.
  K15 over MCP on the app (`proof_app.binary()`, `RC_PROOF_APP`, or `--app`):
      `record_screen {seconds: 2, place: false, path: <scratch>}` into a scratch project answers
      `segments[0].cursor_path` beside its movie, the file on disk, with `cursor_image` "none".
  K17 (road map creator-jobs CU3b, spec §11 CU-34 (c)) in the same launch:
      `record_screen {seconds: 2, place: true, path: <scratch>}` into a new project: the landed
      media (the one whose path is `segments[0].path`) has `cursor` with `path`
      `segments[0].cursor_path` and `in_picture` false — `saveCursor` attached the file it wrote,
      and a display recording with no `cursor` is Separate (road map creator-jobs CU3c, spec §11
      CU-36 (a); `in_picture` true before CU3c).
  B1  (CU3c, spec §11 CU-31) the probe's grey 1001 × 701 pt window recorded at Nominal with the
      pointer warped inside it, once Separate and once In the picture: in the movie's last frame,
      a 32 × 32 px box from the warped point holds no pixel more than 8/255 from the window's
      grey with Separate, and at least 20 In the picture (the control).
  B4  (CU3c) a Separate display recording at 30 fps of a red 40 pt square whose top-left corner
      the pointer holds at 8 points for 0.5 s each, imported over MCP into a canvas of the
      movie's size: the drawn tip — located as `cursor_layer_proof`'s `tip_from` locates one,
      from the render with and without `show`, the arrow's black centroid less its hot spot (the
      probe's `arrow`) — within 1.5 px of the square's corner at p95 over 3 mid-hold frames per
      hold; and at each of the 7 hold changes the first frame showing the tip at the new corner
      within one frame of the first showing the square there.
  Z1  the launch's log holds no `Frame Job: ` line.

Prints `scores: P/N` over the rows scored and each skip with its reason; exits 0 iff every
scored row passed (skips are not failures), 1 otherwise.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
import mcp  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402

WORK = ROOT / "tools/proof/work/cursor-proof"
ROWS = ["K4", "K5", "K7", "K8", "K15", "K17", "B1", "B4", "Z1"]
TIP_PX = 1.5          # B4: the drawn tip against the square's corner, p95
GREY_TOLERANCE = 8    # B1: /255 from the window's grey
FPS = 30              # B4's recording rate and canvas
WALL = 600

results = {}
skips = {}
selected = set(ROWS)


def check(row, ok, detail):
    if row not in selected:
        return
    results.setdefault(row, []).append((bool(ok), detail))
    print(f"  {'ok  ' if ok else 'FAIL'} {row} {detail}", flush=True)


def skip(row, why):
    if row in selected:
        skips[row] = why
        print(f"  skip {row} — {why}", flush=True)


def build():
    entry = WORK / "main.swift"
    shutil.copyfile(HERE / "cursor_proof.swift", entry)
    binary = WORK / "cursor-proof"
    sources = sorted(str(p) for p in (ROOT / "app/Sources").glob("*.swift")
                     if p.name != "main.swift")
    try:
        swift_build.build(sources=sources + [str(entry)], output=binary)
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + ("; ".join(error.diagnostics[:8]) or str(error))
    return binary, None


def probe(binary, *argv):
    try:
        done = subprocess.run([str(binary), *argv], capture_output=True, text=True, timeout=WALL)
    except subprocess.TimeoutExpired:
        return None, f"no answer within {WALL} s"
    (WORK / f"stderr-{argv[0]}.txt").write_text(done.stderr)
    try:
        return json.loads(done.stdout), None
    except ValueError:
        return None, f"no answer (exit {done.returncode}): {done.stderr[-300:]}"


def track_size(movie):
    done = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                           "stream=width,height", "-of", "json", movie],
                          capture_output=True, text=True, timeout=60)
    try:
        stream = json.loads(done.stdout)["streams"][0]
        return [stream["width"], stream["height"]]
    except (ValueError, KeyError, IndexError):
        return None


def cursor_file(segment):
    path = segment.get("cursor_path")
    if not path or not Path(path).exists():
        return None
    return json.loads(Path(path).read_text())


def moves(body):
    m = body.get("moves", {})
    return [(x / 100, y / 100) for x, y in zip(m.get("x", []), m.get("y", []))]


def beside(segment):
    movie = Path(segment.get("path", ""))
    return segment.get("cursor_path") == str(movie.with_suffix(".fjcursor"))


def file_rows(row, segment, source):
    """The rows every landed segment's file answers: beside its movie, accepted, the header."""
    body = cursor_file(segment)
    name = Path(segment.get("path", "?")).name
    check(row, body is not None and beside(segment) and segment.get("accepted") is True,
          f"{name}: cursor file {segment.get('cursor_path')!r} beside the movie, accepted "
          f"{segment.get('accepted')} {segment.get('refusal', '')}".rstrip())
    if body is None:
        return None
    size = track_size(segment["path"])
    check(row, body.get("source") == source and body.get("anchor") == "e1"
          and body.get("cursor_image") == "none" and segment.get("cursor_image") == "none",
          f"{name}: source {body.get('source')}, anchor {body.get('anchor')}, cursor_image "
          f"{body.get('cursor_image')} (segment {segment.get('cursor_image')})")
    check(row, size is not None and body.get("movie_size") == size,
          f"{name}: movie_size {body.get('movie_size')}, the track {size}")
    return body


def k4(answer):
    for run in answer.get("k4", []):
        label = run.get("resolution", "?")
        segments = run.get("segments") or []
        check("K4", run.get("started") and run.get("resumed") and len(segments) == 2,
              f"{label}: started {run.get('started')}, resumed {run.get('resumed')}, "
              f"{len(segments)} segments {run.get('start_error') or run.get('finish_error') or ''}")
        for k, segment in enumerate(segments[:2]):
            body = file_rows("K4", segment, "display")
            if body is None:
                continue
            got = moves(body)
            warped = (run.get("warped") or [[], []])[k]
            missing = [p for p in warped
                       if not any(abs(x - p[0]) <= 1 and abs(y - p[1]) <= 1 for x, y in got)]
            check("K4", warped and not missing,
                  f"{label} segment {k}: {len(warped)} warped points among {len(got)} moves; "
                  f"missing {missing}")
    check("K4", len(answer.get("k4", [])) == 2, "two runs, Nominal and Best")


def k5(answer):
    run = answer.get("k5", {})
    if "skipped" in run:
        return skip("K5", run["skipped"])
    segments = run.get("segments") or []
    body = cursor_file(segments[0]) if segments else None
    if body is None:
        return check("K5", False, f"no cursor file: {run}")
    clicks = body.get("clicks", {})
    at = run.get("posted", [0, 0])
    points = [(x / 100, y / 100) for x, y in zip(clicks.get("x", []), clicks.get("y", []))]
    near = all(abs(x - at[0]) <= 1 and abs(y - at[1]) <= 1 for x, y in points)
    check("K5", clicks.get("down") == [1, 0] and clicks.get("button") == [0, 0] and near,
          f"clicks down {clicks.get('down')}, button {clicks.get('button')} at {points}, "
          f"posted at {at}")


def k7(answer):
    run = answer.get("k7", {})
    segments = run.get("segments") or []
    if not segments:
        return check("K7", False, f"no landed segment: {run.get('finish_error')}")
    segment = segments[0]
    stem = Path(segment.get("path", "")).stem
    sentence = f"The cursor file {stem}.fjcursor could not be written: "
    problem = segment.get("cursor_problem", "")
    check("K7", Path(segment.get("path", "")).exists() and "cursor_path" not in segment
          and problem.startswith(sentence) and sentence in run.get("notes", ""),
          f"movie landed, no cursor file, problem {problem!r}")


def k8(answer):
    run = answer.get("k8", {})
    if "skipped" in run:
        return check("K8", False, run["skipped"])
    segments = run.get("segments") or []
    check("K8", run.get("started") and len(segments) == 1,
          f"started {run.get('started')}, {len(segments)} segments "
          f"{run.get('start_error') or run.get('finish_error') or ''}")
    if segments:
        body = file_rows("K8", segments[0], "window")
        if body is not None:
            check("K8", body.get("point_size") == [100100, 70100],
                  f"point_size {body.get('point_size')} (1001 × 701 pt × 100)")


def k17(client, folder):
    """A placed recording's media carries the cursor file its landing wrote (CU-34 (c))."""
    project = WORK / "k17.framejob"
    if project.exists():
        shutil.rmtree(project)
    client.call("new_project", path=str(project))
    try:
        try:
            answer = client.call_with("record_screen", {
                "project": str(project), "seconds": 2, "place": True, "path": str(folder)})
        except mcp.ToolError as error:
            if "Screen Recording" in str(error):
                skip("K17", f"the app holds no Screen Recording grant: {error}")
            else:
                check("K17", False, f"record_screen refused: {error}")
            return
        segment = (answer.get("segments") or [{}])[0]
        media = [m for m in client.call("get_project", project=str(project))["project"]["media"]
                 if m.get("path") == segment.get("path")]
        cursor = (media[0].get("cursor") if media else None) or {}
        check("K17", bool(segment.get("cursor_path")) and cursor.get("path") ==
              segment.get("cursor_path") and cursor.get("in_picture") is False,
              f"the landed media's cursor {cursor}, segments[0].cursor_path "
              f"{segment.get('cursor_path')!r}")
    finally:
        try:
            client.call("close_project", project=str(project), discard=True)
        except mcp.ToolError:
            pass


def frame_rgb(path, width, height, last=False, index=None):
    """One frame of `path` as a height × width × 3 uint8 array (the last, or `index`), or None."""
    import numpy as np
    args = ["ffmpeg", "-v", "error"]
    if last:
        args += ["-sseof", "-0.5"]
    args += ["-i", str(path)]
    if index is not None:
        args += ["-vf", f"select=eq(n\\,{index})", "-fps_mode", "passthrough"]
    args += ["-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
    try:
        raw = subprocess.run(args, capture_output=True, timeout=120).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
    size = width * height * 3
    if len(raw) < size:
        return None
    frames = len(raw) // size
    take = frames - 1 if last else 0
    return np.frombuffer(raw[take * size:(take + 1) * size], dtype=np.uint8).reshape(
        height, width, 3)


def b1(answer):
    """The grey window recorded each way: the box from the warped point."""
    run = answer.get("b1") or {}
    if "skipped" in run:
        return check("B1", False, run["skipped"])
    ox, oy = run.get("origin", [0, 0])
    wx, wy = run.get("warped", [0, 0])
    for cursor, want_clean in (("separate", True), ("in_picture", False)):
        segments = (run.get(cursor) or {}).get("segments") or []
        if not segments:
            check("B1", False, f"{cursor}: no landed segment: {run.get(cursor)}")
            continue
        movie = segments[0]["path"]
        size = track_size(movie)
        frame = frame_rgb(movie, *size, last=True) if size else None
        if frame is None:
            check("B1", False, f"{cursor}: {movie} did not decode")
            continue
        k = size[0] / run.get("points", [1001, 701])[0]
        px, py = int(round((wx - ox) * k)), int(round((wy - oy) * k))
        grey = frame[size[1] - 20, 20].astype(int)
        box = frame[py:py + 32, px:px + 32].astype(int)
        off = int((abs(box - grey).max(axis=2) > GREY_TOLERANCE).sum())
        ok = off == 0 if want_clean else off >= 20
        check("B1", ok, f"{cursor}: {off} pixel(s) beyond {GREY_TOLERANCE}/255 of the grey "
              f"{grey.tolist()} in the 32 × 32 px box at ({px}, {py}) of {Path(movie).name} "
              f"({size[0]} × {size[1]}); want {'none' if want_clean else 'at least 20'}")


def located_tip(on, off, offset, cut=0.3):
    """`cursor_layer_proof.tip_from` over arrays, the colour black: each pixel's coverage α
    is the share of (0 − background) its difference from `off` carries, clamped, below `cut` 0;
    the α-weighted centroid in continuous pixel coordinates, less the arrow's black centroid
    offset from its hot spot. None when nothing was covered."""
    import numpy as np
    a = on.astype(float)
    b = off.astype(float)
    d = -b
    norm = (d * d).sum(axis=2)
    alpha = np.where(norm >= 900, ((a - b) * d).sum(axis=2) / np.maximum(norm, 1), 0.0)
    alpha = np.clip(alpha, 0.0, 1.0)
    alpha[alpha < cut] = 0
    total = alpha.sum()
    if total < 4:
        return None
    ys, xs = np.indices(alpha.shape)
    return ((alpha * (xs + 0.5)).sum() / total - offset[0],
            (alpha * (ys + 0.5)).sum() / total - offset[1])


def square_corner(frame):
    """The red square's top-left corner in pixel edges, or None."""
    import numpy as np
    f = frame.astype(int)
    red = (f[:, :, 0] > 180) & (f[:, :, 1] < 90) & (f[:, :, 2] < 90)
    if red.sum() < 200:
        return None
    ys, xs = np.nonzero(red)
    return float(xs.min()), float(ys.min())


def b4(client, answer):
    """The Separate recording of the red square, imported and drawn."""
    import numpy as np
    run = answer.get("b4") or {}
    arrow = answer.get("arrow") or {}
    if "skipped" in run:
        return check("B4", False, run["skipped"])
    segments = run.get("segments") or []
    if not segments or "offset" not in arrow:
        return check("B4", False, f"no landed segment or arrow: {run.get('finish_error')} {arrow}")
    movie = segments[0]["path"]
    size = track_size(movie)
    holds = run.get("holds") or []
    host = run.get("screen_host")
    placed = run.get("placed_host") or []
    if not size or len(holds) != 8 or host is None or len(placed) != 8:
        return check("B4", False, f"the recording's facts are incomplete: size {size}, "
                     f"{len(holds)} holds, screen_host {host}, {len(placed)} placements")
    project = WORK / "b4.framejob"
    if project.exists():
        shutil.rmtree(project)
    client.call("new_project", path=str(project))

    def call(tool, **arguments):
        return client.call_with(tool, {"project": str(project), **arguments})

    try:
        call("set_canvas", width=size[0], height=size[1], fps=[FPS, 1])
        media = call("import_media", path=movie)["media"]
        state = call("get_project")["project"]
        cursor = next(m for m in state["media"] if m["id"] == media).get("cursor") or {}
        check("B4", cursor.get("in_picture") is False,
              f"the imported movie's cursor {cursor} (Separate: in_picture false)")
        if not state["tracks"]:
            call("add_track")
            state = call("get_project")["project"]
        call("add_clip", track=state["tracks"][0]["id"], media=media, at=0)
        clip = call("get_project")["project"]["clips"][0]["id"]
        frame_ticks = 600_000 // FPS
        times = {}
        for k in range(8):
            t0 = placed[k] - host
            for n in (0.2, 0.25, 0.3):
                times[("mid", k, n)] = int(round((t0 + n) * FPS))
            if k > 0:
                first = int((t0 - 0.2) * FPS)
                for f in range(first, first + 18):
                    times[("change", k, f)] = f
        frames = sorted(set(times.values()))

        def render(tag):
            out = {}
            for f in frames:
                png = WORK / f"b4-{tag}-{f}.png"
                if png.exists():
                    png.unlink()
                call("render_frame", t=f * frame_ticks, path=str(png))
                out[f] = frame_rgb(png, *size) if png.exists() else None
            return out

        on = render("on")
        call("set_video", clips=[clip], patch={"cursor": {"show": False}})
        off = render("off")
        # Points to the movie's pixels (1 at Nominal), the arrow drawn at that many a point.
        kx = size[0] / float((answer.get("main_bounds") or [0, 0, size[0]])[2] or size[0])
        offset = (arrow["offset"][0] * kx, arrow["offset"][1] * kx)
        holds = [(x * kx, y * kx) for x, y in holds]
        errors = []
        for k in range(8):
            corner = (holds[k][0], holds[k][1])
            for n in (0.2, 0.25, 0.3):
                f = times[("mid", k, n)]
                if on.get(f) is None or off.get(f) is None:
                    errors.append(float("inf"))
                    continue
                x0, y0 = int(corner[0]) - 24, int(corner[1]) - 24
                roi = (slice(max(y0, 0), y0 + 72), slice(max(x0, 0), x0 + 72))
                tip = located_tip(on[f][roi], off[f][roi], offset)
                sq = square_corner(off[f][roi])
                if tip is None or sq is None:
                    errors.append(float("inf"))
                    continue
                errors.append(float(np.hypot(tip[0] - sq[0], tip[1] - sq[1])))
        p95 = float(np.percentile(errors, 95)) if errors else float("inf")
        check("B4", p95 <= TIP_PX, f"the drawn tip against the square's corner over "
              f"{len(errors)} mid-hold frames: p95 {p95:.3f} px (≤ {TIP_PX}), max "
              f"{max(errors):.3f}")
        late = []
        for k in range(1, 8):
            corner = (holds[k][0], holds[k][1])
            x0, y0 = int(corner[0]) - 24, int(corner[1]) - 24
            roi = (slice(max(y0, 0), y0 + 72), slice(max(x0, 0), x0 + 72))
            local = (corner[0] - max(x0, 0), corner[1] - max(y0, 0))
            tip_at = square_at = None
            for f in sorted(v for key, v in times.items() if key[0] == "change" and key[1] == k):
                if on.get(f) is None or off.get(f) is None:
                    continue
                sq = square_corner(off[f][roi])
                if square_at is None and sq is not None and abs(sq[0] - local[0]) <= 2 \
                        and abs(sq[1] - local[1]) <= 2:
                    square_at = f
                tip = located_tip(on[f][roi], off[f][roi], offset)
                if tip_at is None and tip is not None and abs(tip[0] - local[0]) <= TIP_PX \
                        and abs(tip[1] - local[1]) <= TIP_PX:
                    tip_at = f
            if tip_at is None or square_at is None or abs(tip_at - square_at) > 1:
                late.append((k, tip_at, square_at))
        check("B4", not late, f"at the 7 hold changes the tip's first frame at the new corner "
              f"within one frame of the square's: {'every one' if not late else late}")
    finally:
        try:
            client.call("close_project", project=str(project), discard=True)
        except mcp.ToolError:
            pass


def k15(binary, cu3c=None):
    folder = WORK / "k15"
    folder.mkdir(parents=True, exist_ok=True)
    started = mcp.launch(binary, ["-RCRecordingFolder", str(folder)], seconds=60, timeout=300)
    try:
        if started.client is None:
            for row in ("K15", "K17", "B4"):
                check(row, False, f"the app did not bind its socket — {started.log_path}")
            return
        client = started.client
        if "B4" in selected and cu3c is not None:
            try:
                b4(client, cu3c)
            except Exception as error:  # noqa: BLE001 — a row's failure, never the run's
                check("B4", False, f"{type(error).__name__}: {error}")
        if "K17" in selected:
            k17(client, folder)
        if "K15" not in selected:
            return
        project = WORK / "k15.framejob"
        if project.exists():
            shutil.rmtree(project)
        client.call("new_project", path=str(project))
        try:
            answer = client.call_with("record_screen", {
                "project": str(project), "seconds": 2, "place": False, "path": str(folder)})
        except mcp.ToolError as error:
            if "Screen Recording" in str(error):
                skip("K15", f"the app holds no Screen Recording grant: {error}")
            else:
                check("K15", False, f"record_screen refused: {error}")
            return
        segment = (answer.get("segments") or [{}])[0]
        movie = Path(segment.get("path", ""))
        cursor = segment.get("cursor_path")
        check("K15", cursor == str(movie.with_suffix(".fjcursor")) and Path(cursor).exists()
              and segment.get("cursor_image") == "none" and "cursor_problem" not in segment,
              f"segments[0].cursor_path {cursor!r}, cursor_image {segment.get('cursor_image')!r}, "
              f"problem {segment.get('cursor_problem')!r}")
        try:
            client.call("close_project", project=str(project), discard=True)
        except mcp.ToolError:
            pass
    finally:
        started.stop()
        log = Path(started.log_path).read_text(errors="replace") if started.log_path else ""
        lines = [line for line in log.splitlines() if "Frame Job: " in line]
        check("Z1", not lines, f"{len(lines)} `Frame Job: ` line(s) in {started.log_path}")


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--app")
    args = parser.parse_args()
    if args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
    if WORK.exists():
        shutil.rmtree(WORK)
    WORK.mkdir(parents=True)
    print(f"CU1b1 — the recorder saves the cursor ({proof_app.config()} build for K15)", flush=True)
    binary, why = build()
    if binary is None:
        print(f"  FAIL B0 the probe did not build — {why}")
        return 1
    host, why = probe(binary, "host")
    if host is None:
        print(f"  FAIL host — {why}")
        return 1
    print(f"  host: preflight {host.get('preflight')}, post {host.get('post')}, "
          f"locked {host.get('locked')}, main display {host.get('main_bounds')}", flush=True)
    blocked = (None if host.get("preflight") and not host.get("locked") else
               "the console is locked" if host.get("locked") else
               "CGPreflightScreenCaptureAccess() is false under this process's grant")
    in_process = [r for r in ("K4", "K5", "K7", "K8") if r in selected]
    if blocked:
        for row in in_process + [r for r in ("B1", "B4", "K15", "K17", "Z1") if r in selected]:
            skip(row, blocked)
    else:
        cu3c = None
        if selected & {"B1", "B4"}:
            cu3c, why = probe(binary, "cu3c", str(WORK))
            if cu3c is None:
                for row in selected & {"B1", "B4"}:
                    check(row, False, f"CU3c's recordings did not run: {why}")
            else:
                (WORK / "answer-cu3c.json").write_text(json.dumps(cu3c, indent=1))
                if "B1" in selected:
                    b1(cu3c)
        if in_process:
            answer, why = probe(binary, "run", str(WORK))
            if answer is None or "skipped" in (answer or {}):
                reason = why or answer["skipped"]
                for row in in_process:
                    check(row, False, f"the recordings did not run: {reason}")
            else:
                (WORK / "answer.json").write_text(json.dumps(answer, indent=1))
                if "K4" in selected:
                    k4(answer)
                if "K5" in selected:
                    k5(answer)
                if "K7" in selected:
                    k7(answer)
                if "K8" in selected:
                    k8(answer)
        if selected & {"K15", "K17", "B4", "Z1"}:
            app = Path(args.app) if args.app else proof_app.binary()
            if app.suffix == ".app":
                app = proof_app.executable(app)
            k15(app, cu3c)
    failed = [row for row, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [row for row in results if row not in failed]
    print(f"\nscores: {len(passed)}/{len(results)}"
          + (f"; failed {failed}" if failed else "")
          + (f"; skipped {sorted(skips)}" if skips else ""))
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
