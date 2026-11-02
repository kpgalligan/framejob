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
      `segments[0].cursor_path` and `in_picture` true — `saveCursor` attached the file it wrote.
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
ROWS = ["K4", "K5", "K7", "K8", "K15", "K17", "Z1"]
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
              segment.get("cursor_path") and cursor.get("in_picture") is True,
              f"the landed media's cursor {cursor}, segments[0].cursor_path "
              f"{segment.get('cursor_path')!r}")
    finally:
        try:
            client.call("close_project", project=str(project), discard=True)
        except mcp.ToolError:
            pass


def k15(binary):
    folder = WORK / "k15"
    folder.mkdir(parents=True, exist_ok=True)
    started = mcp.launch(binary, ["-RCRecordingFolder", str(folder)], seconds=60, timeout=300)
    try:
        if started.client is None:
            for row in ("K15", "K17"):
                check(row, False, f"the app did not bind its socket — {started.log_path}")
            return
        client = started.client
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
        for row in in_process + [r for r in ("K15", "K17", "Z1") if r in selected]:
            skip(row, blocked)
    else:
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
        if selected & {"K15", "K17", "Z1"}:
            app = Path(args.app) if args.app else proof_app.binary()
            if app.suffix == ".app":
                app = proof_app.executable(app)
            k15(app)
    failed = [row for row, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [row for row in results if row not in failed]
    print(f"\nscores: {len(passed)}/{len(results)}"
          + (f"; failed {failed}" if failed else "")
          + (f"; skipped {sorted(skips)}" if skips else ""))
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
