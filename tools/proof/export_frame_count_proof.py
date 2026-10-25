#!/usr/bin/env python3
"""kpgalligan/framejob#350 — the export sheet's "N frames" readout and the
image-sequence writer count frames with one function,
`ExportSettings.sequenceFrameCount` (floor, at least one, nil when the rate
cannot step), so a range shorter than one GIF frame reads "1 frames" on the
sheet and writes one frame.

    python3 tools/proof/export_frame_count_proof.py
    python3 tools/proof/export_frame_count_proof.py --only probe|mcp
    python3 tools/proof/export_frame_count_proof.py --only probe --mutant no-min-one

Two instruments.

The probe `export_frame_count_probe.swift`, compiled AS `main.swift` over
every file in `app/Sources` but the app's own `main.swift` on
`swift_build.py`'s line (a probe that will not build is a scored FAILURE,
never an exit): S0 every fixture decodes its rate, S1–S6 the count, W1–W3 the
writer's refusals and acceptance on it.

The MCP rows, on the built app `proof_app` picks (Debug unless
`RC_PROOF_APP=release`), launched in a scratch home with every `screens.py`
pin as an argument and the export choice pinned to the GIF preset: M0 the
parity check is silent; on a 320 × 180, 30 fps project holding one shape clip
40 000 ticks long (two 30 fps frames, shorter than one 12.5 fps GIF frame),
M1 `export` preset `gif` writes a GIF ffprobe counts one frame in, and M2
File ▸ Export…'s sheet (captured, then `cancel_sheet`) reads
"· 1 frames, no audio" and nowhere "0 frames". Nothing on the sheet is
pressed, the project is closed discarded, and only this instance is stopped.

`--mutant no-min-one` copies `app/Sources` and drops the `max(1, …)` from the
copy's `sequenceFrameCount`; it exits 0 (MUTANT PASS) only when exactly S1, S2
and S5 fail over the copy.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / "tools/proof"
sys.path.insert(0, str(HERE / "graphics_spike"))
sys.path.insert(0, str(HERE))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import reference_build  # noqa: E402
import swift_build  # noqa: E402
import v2_snapshot  # noqa: E402
from screens import PINS  # noqa: E402

WORK = HERE / "work/export-frame-count"
PROBE_SWIFT = HERE / "export_frame_count_probe.swift"
CHOICE = '<string>{"preset_id":"gif"}</string>'
CALL_BOUND = 120
CLIP = 40_000  # two 30 fps frames; a 12.5 fps frame is 48 000 ticks

PROBE_ROWS = ["S0", "S1", "S2", "S3", "S4", "S5", "S6", "W1", "W2", "W3"]
MUTANTS = {
    "no-min-one": ("ExporterImageSequence.swift",
                   "max(1, Int(max(0, duration) / step))",
                   "Int(max(0, duration) / step)",
                   ["S1", "S2", "S5"]),
}

RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append((name, bool(ok)))
    print(f"  {'ok  ' if ok else 'FAIL'} {name}")
    if detail:
        print("       " + detail)


# ---- the probe -------------------------------------------------------------------

def build_probe(sources, out):
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    source = PROBE_SWIFT.read_text()
    if not entry.exists() or entry.read_text() != source:
        entry.write_text(source)
    binary = out / "export-frame-count-probe"
    defines = reference_build.tree_defines(sources.parent.parent, ["FRAMEJOB_DEV_TOOLS"])
    try:
        built = swift_build.build(sources=swift_build.app_sources(sources) + [entry],
                                  output=binary, defines=defines)
    except swift_build.SwiftBuildFailed as error:
        errors = [line for line in error.diagnostics if ": error:" in line]
        return None, "swiftc failed:\n       " + "\n       ".join(
            errors[:6] or error.diagnostics[:6] or ["(no error lines)"])
    if not built.reused:
        print(f"  probe built in {built.seconds:.0f} s")
    return binary, None


def probe_checks(sources, out):
    print("\n1 — the probe: S0–S6 the count, W1–W3 the writer")
    binary, error = build_probe(sources, out)
    check("the probe builds over app/Sources", binary is not None, error or "")
    if binary is None:
        return None
    answer = out / "answer.json"
    if answer.exists():
        answer.unlink()
    ran = bounded.run([str(binary), str(answer)], 120, env=bounded.child_env())
    if ran["expired"] or ran["rc"] != 0 or not answer.exists():
        check("the probe runs", False, (ran["stdout"] + ran["stderr"]).strip()[-400:])
        return None
    rows = json.loads(answer.read_text())["rows"]
    labels = [r["name"].split(" ")[0] for r in rows]
    check(f"the probe answers every row ({', '.join(PROBE_ROWS)}, one each)",
          sorted(labels) == sorted(PROBE_ROWS), f"{labels}")
    for row in rows:
        check(row["name"], row["ok"], row["detail"])
    return rows


def mutant(name):
    file, find, replace, expected = MUTANTS[name]
    tree = WORK / "mutant"
    if tree.exists():
        shutil.rmtree(tree)
    sources = tree / "Sources"
    shutil.copytree(ROOT / "app/Sources", sources)
    target = sources / file
    text = target.read_text()
    if text.count(find) != 1:
        print(f"MUTANT FAILURE: {name}: `{find}` appears {text.count(find)} times in "
              f"{file}, not once")
        return 1
    target.write_text(text.replace(find, replace))
    print(f"MUTANT {name}: `{find}` → `{replace}` in the copy's {file}")
    rows = probe_checks(sources, tree / "out")
    if rows is None:
        print(f"MUTANT FAILURE: {name}: the probe did not build or run over the copy")
        return 1
    failed = sorted({r["name"].split(" ")[0] for r in rows if not r["ok"]})
    if failed == sorted(expected):
        print(f"MUTANT PASS: {name}: exactly {', '.join(expected)} FAILED")
        return 0
    print(f"MUTANT FAILURE: {name}: failed {failed}, want {sorted(expected)}")
    return 1


# ---- the MCP rows ----------------------------------------------------------------

def attempt(client, name, arguments):
    try:
        answer = (client.export_with(arguments) if name == "export"
                  else client.call_with(name, arguments))
        return {"ok": True, "reply": answer}
    except mcp.ToolError as error:
        return {"ok": False, "error": str(error)}
    except Exception as error:  # a socket timeout is the expiry
        return {"ok": False, "error": f"{type(error).__name__}: {error}"}


def must(client, name, arguments):
    got = attempt(client, name, arguments)
    if not got["ok"]:
        raise RuntimeError(f"{name} {arguments}: {got['error']}")
    return got["reply"]


def frames_in(path):
    ran = bounded.run(["ffprobe", "-v", "error", "-count_frames", "-select_streams", "v:0",
                       "-show_entries", "stream=nb_read_frames", "-of",
                       "default=noprint_wrappers=1:nokey=1", str(path)], 60,
                      env=bounded.child_env())
    text = (ran["stdout"] or "").strip()
    return (int(text) if text.isdigit() else None), (ran["stderr"] or "").strip()[-200:]


def sheet_texts(client, project, out):
    """File ▸ Export… on `project`, the sheet's layout dump, then
    `cancel_sheet`: every non-hidden view's text, and the cancel's answer."""
    shown = attempt(client, "perform_menu_item", {"project": project,
                                                  "path": ["File", "Export…"]})
    if not shown["ok"]:
        return None, shown["error"], attempt(client, "cancel_sheet", {"project": project})
    try:
        answer = v2_snapshot.snap(client, window="sheet", project=project,
                                  path=str(out / "sheet.png"))
        v2_snapshot.captures.clear()
        with open(answer["layout_path"]) as handle:
            layout = json.load(handle)
        texts = [v.get("text") for v in layout["views"]
                 if isinstance(v.get("text"), str) and not v.get("hidden")]
        return texts, "", attempt(client, "cancel_sheet", {"project": project})
    except Exception as error:  # a capture that failed is the row's answer
        return None, f"{type(error).__name__}: {error}", attempt(
            client, "cancel_sheet", {"project": project})


def mcp_checks():
    print("\n2 — the app over MCP: M0 the parity check, M1 the GIF, M2 the sheet")
    session = WORK / "mcp"
    if session.exists():
        shutil.rmtree(session)
    home, out = session / "home", session / "out"
    home.mkdir(parents=True)
    out.mkdir()
    log = session / "framejob.log"
    app = proof_app.bundle()
    arguments = ["-NSRecentDocumentsLimit", "0"]
    for key, value in PINS:
        arguments += [f"-{key}", CHOICE if key == "FrameJobExportChoice" else value]
    try:
        launched = mcp.launch(str(proof_app.executable(app)), arguments=arguments,
                              env=bounded.child_env({"CFFIXED_USER_HOME": str(home)}),
                              log_path=str(log), timeout=CALL_BOUND)
    except proof_app.StaleApp as error:
        check("the app is fresh", False, str(error))
        return
    try:
        client = launched.client
        check(f"the instance comes up ({app})", client is not None, f"log {log}")
        if client is None:
            return
        parity = [line for line in log.read_text(errors="replace").splitlines()
                  if "Frame Job: " in line]
        check("M0 no `Frame Job: ` line in the log", not parity, "; ".join(parity[:3]))

        path = session / "short.framejob"
        project = str(path)
        try:
            must(client, "new_project", {"path": project})
            must(client, "set_canvas", {"project": project, "width": 320, "height": 180,
                                        "fps": [30, 1]})
            got = must(client, "get_project", {"project": project})["project"]
            must(client, "add_shape_clip",
                 {"project": project, "track": got["tracks"][0]["id"], "at": 0,
                  "duration": CLIP,
                  "shape": {"kind": "rectangle", "width": 200, "height": 120,
                            "stroke": None, "fill": [1, 0, 0, 1]}})
            must(client, "save_project", {"project": project})
            canvas = must(client, "get_project", {"project": project})["project"]["canvas"]
            check("the fixture: 320 × 180 at 30 fps, one shape clip 40 000 ticks long",
                  canvas.get("width") == 320 and canvas.get("height") == 180
                  and canvas.get("fps") == [30, 1], f"canvas {canvas}")
        except RuntimeError as error:
            check("the fixture is made", False, str(error))
            return

        gif = out / "short.gif"
        exported = attempt(client, "export", {"project": project, "preset": "gif",
                                              "path": str(gif)})
        count, why = (frames_in(gif) if exported["ok"] and gif.exists() else (None, ""))
        check("M1 export preset gif of the 40 000-tick project is done and ffprobe counts "
              "1 frame in the GIF", exported["ok"] and count == 1,
              f"export {exported.get('error') or exported.get('reply')}; nb_read_frames "
              f"{count} {why}")

        texts, problem, cancelled = sheet_texts(client, project, out)
        readout = [t for t in texts or [] if "frames, no audio" in t]
        check("M2 File ▸ Export…'s sheet: some text contains \"· 1 frames, no audio\" and "
              "none contains \"· 0 frames\"; the sheet is cancelled",
              texts is not None and any("· 1 frames, no audio" in t for t in texts)
              and not any("· 0 frames" in t for t in texts) and cancelled["ok"],
              f"{problem or 'captured'}; readout {readout}; cancel_sheet "
              f"{cancelled.get('error', 'ok')}")
        closed = attempt(client, "close_project", {"project": project, "discard": True})
        check("the project is closed, discarded", closed["ok"], closed.get("error", ""))
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--only", choices=["probe", "mcp"])
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    if args.mutant:
        if args.only == "mcp":
            parser.error("--mutant runs the probe alone")
        return mutant(args.mutant)
    print("#350 — the sheet's frame readout and the writer share sequenceFrameCount")
    if args.only in (None, "probe"):
        probe_checks(ROOT / "app/Sources", WORK / "probe")
    if args.only in (None, "mcp"):
        mcp_checks()
    good = sum(1 for _, ok in RESULTS if ok)
    print(f"\n{good}/{len(RESULTS)} checks passed")
    return 0 if RESULTS and good == len(RESULTS) else 1


if __name__ == "__main__":
    sys.exit(main())
