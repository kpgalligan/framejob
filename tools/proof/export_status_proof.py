#!/usr/bin/env python3
"""Spec §11 #326, against the built app: an agent's `export` keeps its
refusals synchronous, enqueues a job in the Export Queue and answers
`{export_id, path, status}` at once; `export_status` follows the job and
`cancel_export` stops it.

One owned instance (`mcp.launch` on `proof_app`'s app, or `--app PATH`), on
a scratch socket, logging to `tools/proof/work/export-status/framejob.log`,
stopped by its PID; nothing else is ever killed. Every file is written under
`tools/proof/work/export-status/`, which each run empties. No row presses
Add to Queue or performs a persisting menu item.

A1  P1 — `AV.mov` on track 1 and a 2 s text clip on a second track: its
    `export h264` answers EXACTLY `{export_id, path, status}`, an integer id
    and `queued` or `running`.
A2  `MCP.wait_export` on that id reaches `done` within A2_BOUND s, with the
    same `export_id` and path and every key `export` answered before #326
    (ok, bytes, preset, container, codec, width, height, fps, start,
    duration, burn_in_timecode, and — the AV clip has sound — loudness with
    its summary); `bytes` equals the file's size.
A3  P2 — a 240 s text clip: its `export h264` answers within 5 s with
    `running`, and `export_status` then reads `running` with
    0 ≤ progress ≤ 1.
A4  a second export of P2 behind it answers, and `export_status` reads,
    `queued`.
A5  `cancel_export` of the queued one answers `cancelled`; of the running
    one, `export_status` reaches `cancelled` within 10 s; neither file
    exists afterwards.
A6  `export_status` and `cancel_export` each refuse an id no `export`
    returned ("No export this launch has export_id …") and a call without
    `export_id`, by name.
A7  `export` to a folder that does not exist is refused ("There is no
    folder"), and of P3, whose graphic clip's module no longer compiles
    (export_cancel_proof G2's shape, one level), is refused "The export was
    not started:" naming "gate" — both synchronously: the next export's id
    is A4's plus one, so nothing was enqueued.
A8  `cancel_export` of that next export, once done, answers `done` and the
    file is intact (same size and SHA-256).
Z1  no `Frame Job: ` in the log.

    python3 tools/proof/export_status_proof.py [--app PATH]
    python3 tools/proof/export_status_proof.py --mutant NAME

`--mutant NAME` copies the tree (`tree_copy.make_copy`), replaces one anchor
exactly once, builds the copy's app (`tree_copy.build_app`) and runs every
row against it; its named row must FAIL: `waiting-as-running` (A4: a waiting
job's word is `running`), `no-cancel` (A5: `cancel_export` never calls the
queue's `cancel`), `no-graphics-gate` (A7: the handler's graphics gate does
not refuse), `no-observer` (A2: `AgentExports` never copies the queue's
changes) and `loudness-dropped` (A2: the queue never keeps a finished job's
loudness). Exit 1 when the named row FAILED (caught), 0 when it passed
(survived), 2 when the control could not be performed (the copy, an anchor,
the build or the launch failed, or the row was never scored).

Rows print `<ID> ok|FAIL — <detail>`, then `n/m`; exit 0 iff every row
passes.
"""

import argparse
import hashlib
import os
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402
from export_cancel_proof import BROKEN_JS, GATE_JS  # noqa: E402  — G2's fixture, one home

WORK = ROOT / "tools/proof/work/export-status"
APP = proof_app.binary()
AV_MOV = ROOT / "tools/proof/media/AV.mov"
SEC = 600_000
CALL_BOUND = 600
A2_BOUND = 120
LONG_SECONDS = 240
ANSWER_BOUND = 5.0
CANCEL_BOUND = 10.0
ROWS = ["A1", "A2", "A3", "A4", "A5", "A6", "A7", "A8", "Z1"]
PRE_326_KEYS = {"ok", "bytes", "preset", "container", "codec", "width", "height", "fps",
                "start", "duration", "burn_in_timecode"}
UNKNOWN = "No export this launch has export_id"

# name: (file in app/Sources, anchor — exactly once, replacement, the row it must fail)
MUTANTS = {
    "waiting-as-running": ("AgentServer+ExportStatus.swift",
                           '        case .waiting: return "queued"\n',
                           '        case .waiting: return "running"\n', "A4"),
    "no-cancel": ("AgentServer+ExportStatus.swift",
                  "            ExportQueueController.shared.cancel(id)\n", "", "A5"),
    "no-graphics-gate": ("AgentServer+Export.swift",
                         "            throw ToolError(message: refusal.localizedDescription)\n",
                         "            _ = refusal\n", "A7"),
    "no-observer": ("AgentServer+ExportStatus.swift",
                    "        ) { [weak self] _ in self?.refresh() }\n",
                    "        ) { _ in }\n", "A2"),
    "loudness-dropped": ("ExportQueueController.swift",
                         "                jobs[index].loudness = report\n", "", "A2"),
}

rows = {}
broken = []  # why the instrument could not run, for a mutant's exit 2


def check(row, good, detail=""):
    rows[row] = bool(good)
    print(f"{row} {'ok' if good else 'FAIL'} — {detail}", flush=True)


def attempt(client, tool, arguments):
    """One MCP call, raw (no export helper): a refusal is an answer."""
    try:
        return {"ok": True, "reply": client.call_with(tool, arguments)}
    except mcp.ToolError as error:
        return {"ok": False, "error": str(error)}
    except Exception as error:  # a socket timeout is the expiry
        return {"ok": False, "error": f"{type(error).__name__}: {error}"}


def must(client, tool, arguments):
    got = attempt(client, tool, arguments)
    if not got["ok"]:
        raise RuntimeError(f"{tool} {arguments}: {got['error']}")
    return got["reply"]


def digest(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


def first_track(client, project):
    return must(client, "get_project", {"project": project})["project"]["tracks"][0]["id"]


def text_project(client, name, seconds):
    project = str(WORK / f"{name}.framejob")
    must(client, "new_project", {"path": project})
    must(client, "add_text_clip", {"project": project, "track": first_track(client, project),
                                   "at": 0, "duration": seconds * SEC})
    return project


def av_project(client):
    """P1: AV.mov on the first track and a 2 s text clip on a second."""
    project = str(WORK / "p1.framejob")
    must(client, "new_project", {"path": project})
    media = must(client, "import_media", {"project": project, "path": str(AV_MOV)})["media"]
    must(client, "add_clip", {"project": project, "track": first_track(client, project),
                              "media": media, "at": 0})
    must(client, "add_track", {"project": project})
    tracks = must(client, "get_project", {"project": project})["project"]["tracks"]
    must(client, "add_text_clip", {"project": project, "track": tracks[-1]["id"], "at": 0,
                                   "duration": 2 * SEC})
    return project


def graphic_project(client):
    """P3: a `gate` graphic clip whose module is then rewritten not to
    compile, polled until the store sees it fail. (project, why)."""
    project = str(WORK / "p3.framejob")
    must(client, "new_project", {"path": project})
    must(client, "write_graphic", {"project": project, "name": "gate", "source": GATE_JS})
    track = first_track(client, project)
    deadline, placed, last = time.monotonic() + 5, False, ""
    while time.monotonic() < deadline and not placed:
        got = attempt(client, "add_graphic_clip",
                      {"project": project, "name": "gate", "track": track, "at": 0})
        placed, last = got["ok"], got.get("error", "")
        if not placed:
            time.sleep(0.2)
    if not placed:
        return project, f"add_graphic_clip never landed: {last}"
    must(client, "write_graphic", {"project": project, "name": "gate", "source": BROKEN_JS})
    deadline, seen = time.monotonic() + 5, None
    while time.monotonic() < deadline:
        graphics = must(client, "get_project", {"project": project}).get("graphics") or []
        seen = [g.get("ok") for g in graphics if g.get("name") == "gate"]
        if seen == [False]:
            return project, ""
        time.sleep(0.2)
    return project, f"the store saw gate as {seen}"


def status(client, export_id):
    return attempt(client, "export_status", {"export_id": export_id})


def run_rows(client):
    # ---- A1, A2 ---------------------------------------------------------------
    p1 = av_project(client)
    a1_path = WORK / "a1.mp4"
    started = time.monotonic()
    a1 = attempt(client, "export", {"project": p1, "preset": "h264", "path": str(a1_path)})
    took = time.monotonic() - started
    answer = a1.get("reply") if a1["ok"] and isinstance(a1.get("reply"), dict) else {}
    a1_id = answer.get("export_id")
    check("A1", a1["ok"] and set(answer) == {"export_id", "path", "status"}
          and isinstance(a1_id, int) and not isinstance(a1_id, bool)
          and answer.get("status") in ("queued", "running") and answer.get("path") == str(a1_path),
          f"answered in {took:.2f} s: {answer if a1['ok'] else a1['error']!r}")

    done, why = {}, ""
    if isinstance(a1_id, int):
        try:
            done = client.wait_export(a1_id, seconds=A2_BOUND)
        except mcp.ToolError as error:
            why = str(error)
    size = a1_path.stat().st_size if a1_path.exists() else None
    loudness = done.get("loudness") or {}
    missing = sorted(PRE_326_KEYS - set(done))
    check("A2", done.get("status") == "done" and done.get("export_id") == a1_id
          and done.get("path") == str(a1_path) and not missing and done.get("ok") is True
          and done.get("bytes") == size and size and isinstance(loudness, dict)
          and bool(loudness.get("summary")),
          f"done {done.get('status')!r} id {done.get('export_id')} (want {a1_id}), missing "
          f"{missing}, bytes {done.get('bytes')} vs file {size}, loudness "
          f"{sorted(loudness) if isinstance(loudness, dict) else loudness!r}, elapsed "
          f"{done.get('elapsed')} {why!r}")

    # ---- A3, A4, A5 -------------------------------------------------------------
    p2 = text_project(client, "p2", LONG_SECONDS)
    a3_path, a4_path = WORK / "a3.mp4", WORK / "a4.mp4"
    started = time.monotonic()
    a3 = attempt(client, "export", {"project": p2, "preset": "h264", "path": str(a3_path)})
    took = time.monotonic() - started
    a3_answer = a3.get("reply") if a3["ok"] and isinstance(a3.get("reply"), dict) else {}
    a3_id = a3_answer.get("export_id")
    now = status(client, a3_id) if a3_id is not None else {"ok": False, "error": "no id"}
    now_reply = now.get("reply") if now["ok"] else {}
    progress = now_reply.get("progress")
    check("A3", a3["ok"] and took < ANSWER_BOUND and a3_answer.get("status") == "running"
          and now_reply.get("status") == "running" and isinstance(progress, (int, float))
          and 0 <= progress <= 1,
          f"answered in {took:.2f} s (bound {ANSWER_BOUND}): "
          f"{a3_answer if a3['ok'] else a3['error']!r}; export_status {now_reply or now}")

    a4 = attempt(client, "export", {"project": p2, "preset": "h264", "path": str(a4_path)})
    a4_answer = a4.get("reply") if a4["ok"] and isinstance(a4.get("reply"), dict) else {}
    a4_id = a4_answer.get("export_id")
    queued = status(client, a4_id) if a4_id is not None else {"ok": False, "error": "no id"}
    queued_reply = queued.get("reply") if queued["ok"] else {}
    check("A4", a4["ok"] and a4_answer.get("status") == "queued"
          and queued_reply.get("status") == "queued",
          f"answered {a4_answer if a4['ok'] else a4['error']!r}; export_status "
          f"{queued_reply or queued}")

    cancelled_queued = attempt(client, "cancel_export", {"export_id": a4_id}) \
        if a4_id is not None else {"ok": False, "error": "no id"}
    cq = cancelled_queued.get("reply") if cancelled_queued["ok"] else {}
    word = None
    if a3_id is not None:
        attempt(client, "cancel_export", {"export_id": a3_id})
        deadline = time.monotonic() + CANCEL_BOUND
        while time.monotonic() < deadline:
            got = status(client, a3_id)
            word = (got.get("reply") or {}).get("status") if got["ok"] else got["error"]
            if word in ("cancelled", "done", "failed"):
                break
            time.sleep(0.2)
    time.sleep(1.0)
    check("A5", cq.get("status") == "cancelled" and word == "cancelled"
          and not a3_path.exists() and not a4_path.exists(),
          f"queued one answered {cq or cancelled_queued}; running one reads {word!r} within "
          f"{CANCEL_BOUND} s; files a3 {a3_path.exists()} a4 {a4_path.exists()}")

    # ---- A6 -----------------------------------------------------------------------
    unknown = 900_000 + os.getpid() % 1000
    notes, good = [], True
    for tool in ("export_status", "cancel_export"):
        absent = attempt(client, tool, {"export_id": unknown})
        bare = attempt(client, tool, {})
        right = (not absent["ok"] and f"{UNKNOWN} {unknown}" in absent["error"]
                 and not bare["ok"] and "export_id" in bare["error"])
        good = good and right
        notes.append(f"{tool}: unknown {absent.get('error', absent.get('reply'))!r}; bare "
                     f"{bare.get('error', bare.get('reply'))!r}")
    check("A6", good, "; ".join(notes))

    # ---- A7, A8 -------------------------------------------------------------------
    p3, p3_why = graphic_project(client)
    nowhere = WORK / "no-such-folder" / "a7.mp4"
    folder = attempt(client, "export", {"project": p1, "preset": "h264", "path": str(nowhere)})
    gate = attempt(client, "export", {"project": p3, "preset": "h264",
                                      "path": str(WORK / "a7-gate.mp4")})
    gate_message = gate.get("error", "")
    a7_path = WORK / "a7.mp4"
    after = attempt(client, "export", {"project": p1, "preset": "h264", "path": str(a7_path)})
    after_id = (after.get("reply") or {}).get("export_id") if after["ok"] else None
    want = a4_id + 1 if isinstance(a4_id, int) else None
    check("A7", not p3_why and not folder["ok"] and "There is no folder" in folder["error"]
          and not gate["ok"] and "The export was not started:" in gate_message
          and '"gate"' in gate_message and after_id is not None and after_id == want,
          f"P3 {p3_why or 'gate does not compile'}; missing folder "
          f"{folder.get('error', folder.get('reply'))!r}; gate "
          f"{gate_message or gate.get('reply')!r}; next id {after_id} (want {want})")

    intact = False
    detail = "no export to cancel"
    if after_id is not None:
        try:
            finished = client.wait_export(after_id, seconds=A2_BOUND)
            before_size, before_sum = a7_path.stat().st_size, digest(a7_path)
            cancelled = attempt(client, "cancel_export", {"export_id": after_id})
            reply = cancelled.get("reply") if cancelled["ok"] else {}
            time.sleep(0.5)
            same = (a7_path.exists() and a7_path.stat().st_size == before_size
                    and digest(a7_path) == before_sum)
            intact = finished.get("status") == "done" and reply.get("status") == "done" and same
            detail = (f"cancel_export of a done export answered "
                      f"{reply.get('status') if cancelled['ok'] else cancelled['error']!r}; "
                      f"file intact {same} ({before_size} bytes)")
        except (mcp.ToolError, OSError) as error:
            detail = f"the export did not finish: {error}"
    check("A8", intact, detail)


def complaints(log):
    try:
        with open(log, errors="replace") as handle:
            return [line.rstrip() for line in handle if "Frame Job: " in line]
    except OSError as error:
        return [f"the log could not be read: {error}"]


def run_all(binary):
    log = WORK / "framejob.log"
    launched = mcp.launch(str(binary), env=bounded.child_env(), log_path=str(log),
                          timeout=CALL_BOUND)
    try:
        if launched.client is None:
            broken.append("the app did not listen")
            for name in ROWS[:-1]:
                check(name, False, f"the app did not listen at {launched.socket_path}")
        else:
            print(f"  instance PID {launched.child.pid} at {launched.socket_path}", flush=True)
            try:
                run_rows(launched.client)
            except Exception as error:  # an instrument that breaks is a FAIL, not an exit
                broken.append(f"{type(error).__name__}: {error}")
                for name in ROWS[:-1]:
                    if name not in rows:
                        check(name, False, f"the row could not run: "
                                           f"{type(error).__name__}: {error}")
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    found = complaints(log)
    check("Z1", found == [], f"{found[:5]}")


def build_mutant(name):
    """The copy's app with the mutant's anchor replaced once: its
    executable, or None and why."""
    file, anchor, replacement, _ = MUTANTS[name]
    made, reason = tree_copy.make_copy(str(WORK.parent / "export-status-mutant"))
    if made is None:
        return None, reason
    target = Path(made) / "app/Sources" / file
    text = target.read_text()
    if text.count(anchor) != 1:
        return None, f"{file} holds {anchor!r} {text.count(anchor)} times, not once"
    target.write_text(text.replace(anchor, replacement))
    app, reason = tree_copy.build_app(made, 1500)
    if app is None:
        return None, reason
    return proof_app.executable(app), ""


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--app", type=Path, default=APP)
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    tree_copy.remove_tree(str(WORK))
    WORK.mkdir(parents=True)
    started = time.monotonic()
    if args.mutant:
        named = MUTANTS[args.mutant][3]
        print(f"#326 export status — the {args.mutant} MUTANT ({named} must FAIL)", flush=True)
        binary, why = build_mutant(args.mutant)
        if binary is None:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
        run_all(binary)
        tree_copy.remove_tree(str(WORK.parent / "export-status-mutant"))
        if named not in rows or broken:
            print(f"mutant {args.mutant}: the control could not be performed — "
                  f"{broken[0] if broken else named + ' was not scored'}")
            return 2
        if rows[named]:
            print(f"mutant {args.mutant}: SURVIVED — {named} passed")
            return 0
        print(f"mutant {args.mutant}: caught — {named} failed in "
              f"{time.monotonic() - started:.0f} s")
        return 1
    if not args.app.exists():
        print(f"the app is not built: {args.app}")
        return 1
    print(f"#326 export status — export answers at once, export_status, cancel_export — "
          f"{args.app}", flush=True)
    run_all(args.app)
    passed = sum(1 for name in ROWS if rows.get(name))
    print(f"{passed}/{len(ROWS)} in {time.monotonic() - started:.0f} s")
    return 0 if passed == len(ROWS) else 1


if __name__ == "__main__":
    sys.exit(main())
