#!/usr/bin/env python3
"""A cache write against a held save (spec §11 #553, #429).

    python3 tools/proof/save_hold_proof.py [--only R1] [--mutant NAME] [--app PATH]

A save of a titled document lists `cache/` and later swaps the new package in,
so a file written into the package between the two goes with the old one
(spec §11 #429). `-RCDevSaveHold <s>` holds every save of a launch on main
after the new package is written and before the swap: the window made wide
enough for a script to write into.

A save held on a launch holds every save of that launch, `new_project
{path}`'s own included, so each row's document is made, saved and closed on a
plain launch first (`prepare`) and opened on the held one.

**R1** (#553): an offline audio render that runs while a save is held lands in
the package and plays. The launch is `-RCDevRampRenderHold 3 -RCDevSaveHold
12`. The document holds 2 s of `AV.mov` at ×1 and no `cache/ramp-audio/`.
`set_speed` ×2 with Keep pitch off queues the render, held 3 s; `save_project`
is the next call, so the render runs at about 3 s inside the save's 12 s. It
passes when the render's `.caf` is not there when the save is sent, is in the
package's `cache/ramp-audio/` within `LAND_BOUND` of the save's return (so the
render overlapped the save; one that started after it could not be), nothing
else is left in that folder, and `export audio_wav` then succeeds. Before
#553 the render wrote `<name>.landing` into the old package and the export
answered "the render could not be moved into place".

**Z1**: no `Frame Job: ` line in any instance's log (the parity check).

`--mutant NAME` breaks the named decision in a copy of the tree
(`tree_copy.make_copy`), builds that copy's app and runs the mutant's rows
against it: CAUGHT (exit 0) when a row fails as the mutant says it must,
SURVIVED (exit 1) otherwise. A mutant marked as an expected survivor is run
to show a row does NOT depend on something, and exits 0 when it survives.

- `landing-in-package` (R1): the landing file beside its destination and the
  folder made before the hold, as before #553. Caught only when R1's export
  says "could not be moved into place": a mutant that died of a missing
  folder would not show that R1 sees the swap.
- `folder-before-publish` (R1, an EXPECTED SURVIVOR): the folder made before
  the hold again, the landing file still outside the package. R1 passes: it
  does not rest on where the folder is made.

Needs `tools/proof/media/AV.mov`. Debug by default (`RC_PROOF_APP=release`
for the record).
"""

import argparse
import os
import shutil
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
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/save-hold"
HOME = WORK / "home"
AV_MOV = ROOT / "tools/proof/media/AV.mov"
CALL_BOUND = 300
BUILD_BOUND = 1500
RENDER_HOLD = 3
R1_SAVE_HOLD = 12
# How long after the held save returns the render may take to appear: its
# publish only waits for the save's end.
LAND_BOUND = 2.0
R1_LENGTH = 1_200_000   # ticks: 2 s of source, 1 s at ×2
RENDER_ROWS = ["R1"]
ROWS = RENDER_ROWS + ["Z1"]
MOVED = "could not be moved into place"

RENDERS = "app/Sources/RampAudioRenders.swift"
LANDING = "app/Sources/RenderLanding.swift"
LANDING_OUTSIDE = ("        url = folder.appendingPathComponent("
                   "destination.lastPathComponent + \".landing\")\n")
LANDING_BESIDE = "        url = URL(fileURLWithPath: destination.path + \".landing\")\n"
HOLD_LINE = "            hold(cancelled: cancelled)\n"
FOLDER_FIRST = ("            try FileManager.default.createDirectory(\n"
                "                at: request.destination.deletingLastPathComponent(),\n"
                "                withIntermediateDirectories: true)\n")

# name: (rows, edits, the text a failing row must carry or None, expected to survive)
MUTANTS = {
    "landing-in-package": (["R1"], [
        (LANDING, LANDING_OUTSIDE, LANDING_BESIDE),
        (RENDERS, HOLD_LINE, FOLDER_FIRST + HOLD_LINE)], MOVED, False),
    "folder-before-publish": (["R1"], [
        (RENDERS, HOLD_LINE, FOLDER_FIRST + HOLD_LINE)], None, True),
}

results = {}
selected = set(ROWS)
state = {}


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}", flush=True)


def attempt(body, *names):
    try:
        return body()
    except Exception as error:  # noqa: BLE001 — a row's failure, never the run's
        for name in names:
            check(name, False, f"{type(error).__name__}: {error}")
        return None


class Doc:
    """One package, every call addressed to it."""

    def __init__(self, client, name, new=True):
        self.client = client
        self.path = WORK / f"{name}.framejob"
        if new:
            client.call("new_project", path=str(self.path))
            self.call("set_canvas", width=1280, height=720, fps=[30, 1])
        else:
            client.call("open_project", path=str(self.path))

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def project(self):
        return self.call("get_project")["project"]

    def media(self, source, tag):
        """A copy of `source` of the document's own (its own file, its own
        caches), imported; the media id."""
        copy = WORK / "media" / f"{tag}{Path(source).suffix}"
        copy.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, copy)
        return self.call("import_media", path=str(copy))["media"]

    def clip(self, media, at=0):
        track = self.project()["tracks"][0]["id"]
        return self.call("add_clip", track=track, media=media, at=at)["new_clips"][0]

    def files(self, folder):
        where = self.path / "cache" / folder
        return sorted(p.name for p in where.iterdir()) if where.is_dir() else []

    def export(self, tag):
        out = WORK / "exports" / f"{tag}.wav"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.unlink(missing_ok=True)
        self.client.export_with({"project": str(self.path), "preset": "audio_wav",
                                 "path": str(out)}, seconds=CALL_BOUND)
        return out

    def save_and_close(self):
        self.call("save_project")
        self.close()

    def close(self):
        try:
            self.client.call("close_project", project=str(self.path), discard=True)
        except mcp.ToolError:
            pass


# ---- R1 -------------------------------------------------------------------------

def render_prepare(client):
    def body():
        doc = Doc(client, "r1")
        clip = doc.clip(doc.media(AV_MOV, "r1"))
        doc.call("trim_end", clip=clip, to=R1_LENGTH)   # a short render, well inside the save
        state["r1"] = clip
        doc.save_and_close()
    attempt(body, "R1")


def render_rows(client):
    def r1():
        if "r1" not in state:
            return  # the prepare launch already failed the row
        doc = Doc(client, "r1", new=False)
        try:
            before = doc.files("ramp-audio")
            doc.call("set_speed", clip=state["r1"], rate=2, keep_pitch=False)
            early = doc.files("ramp-audio")
            began = time.monotonic()
            doc.call("save_project")
            held = time.monotonic() - began
            landed = None
            while time.monotonic() - began < held + LAND_BOUND:
                if any(n.endswith(".caf") for n in doc.files("ramp-audio")):
                    landed = time.monotonic() - began - held
                    break
                time.sleep(0.05)
            after = doc.files("ramp-audio")
            try:
                out = doc.export("r1")
                exported = f"exported {out.stat().st_size} bytes"
                played = out.stat().st_size > 44
            except mcp.ToolError as error:
                exported, played = f"the export FAILED: {error}", False
            clean = len(after) == 1 and after[0].endswith(".caf")
            met = (not any(n.endswith(".caf") for n in early) and landed is not None
                   and held >= R1_SAVE_HOLD)
            check("R1", not before and met and clean and played,
                  f"cache/ramp-audio/ {before} before; {early} when the save was sent; the "
                  f"save held {held:.1f} s (every save {R1_SAVE_HOLD} s, the render "
                  f"{RENDER_HOLD} s); the render "
                  + ("NOT there" if landed is None else f"there {landed:.2f} s")
                  + f" after it returned (bound {LAND_BOUND} s); then {after}; {exported}")
        finally:
            doc.close()
    attempt(r1, "R1")


# ---- the launches ---------------------------------------------------------------

def launch(binary, arguments, tag):
    log = WORK / f"instance-{tag}.log"
    launched = mcp.launch(str(binary), arguments,
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    return launched, log


def parity(log, tag):
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z1", not lines, f"{tag}: grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")


def app_rows(binary):
    plans = [
        ("render-prepare", [], render_prepare, set(RENDER_ROWS)),
        ("render", ["-RCDevRampRenderHold", str(RENDER_HOLD),
                    "-RCDevSaveHold", str(R1_SAVE_HOLD)], render_rows, set(RENDER_ROWS)),
    ]
    for tag, arguments, body, rows in plans:
        if not selected & rows:
            continue
        launched, log = launch(binary, arguments, tag)
        try:
            if launched.client is None:
                for row in selected & rows:
                    check(row, False, f"the app did not listen ({tag})")
                continue
            print(f"  {tag}: instance PID {launched.child.pid}", flush=True)
            body(launched.client)
        finally:
            launched.stop()
        parity(log, tag)


# ---- mutants --------------------------------------------------------------------

def mutant_app(name):
    made, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made is None:
        return None, reason
    for path, anchor, replacement in MUTANTS[name][1]:
        target = Path(made) / path
        text = target.read_text()
        if text.count(anchor) != 1:
            return None, f"the anchor occurs {text.count(anchor)} times in {path}"
        target.write_text(text.replace(anchor, replacement))
    app, reason = tree_copy.build_app(Path(made), BUILD_BOUND)
    return (proof_app.executable(app), None) if app else (None, reason)


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--app")
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
    HOME.mkdir(parents=True)
    if not AV_MOV.exists():
        print(f"{AV_MOV} is missing (tools/proof/README.md says how to make the test media)")
        return 2
    binary = Path(args.app) if args.app else None
    if args.mutant:
        named, _, needle, survivor = MUTANTS[args.mutant]
        print(f"save holds — the {args.mutant} MUTANT ({', '.join(named)} must "
              f"{'PASS: an expected survivor' if survivor else 'FAIL'})", flush=True)
        binary, why = mutant_app(args.mutant)
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
    else:
        print(f"save holds — a cache write against a held save ({proof_app.config()} build)",
              flush=True)
        if binary is None:
            binary = proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    app_rows(binary)
    failed = [name for name, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [name for name in results if name not in failed]
    print(f"\n{len(passed)}/{len(results)} rows passed" + (f"; failed {failed}" if failed else ""))
    if args.mutant:
        named, _, needle, survivor = MUTANTS[args.mutant]
        hit = [n for n in named if n in failed]
        said = [n for n in hit if needle is None
                or any(needle in detail for ok, detail in results[n] if not ok)]
        if survivor:
            print(f"MUTANT {args.mutant} {'SURVIVED, as expected' if not hit else 'CAUGHT'}: "
                  f"{', '.join(sorted(named))} {'passed' if not hit else 'failed'}")
            return 0 if not hit else 1
        caught = bool(said)
        why = ("failed" if caught else
               "failed, but not for the mutant's reason" if hit else "passed")
        print(f"MUTANT {args.mutant} {'CAUGHT' if caught else 'SURVIVED'}: "
              f"{', '.join(sorted(named))} {why}"
              + (f" (wants {needle!r})" if needle and not caught else ""))
        return 0 if caught else 1
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
