#!/usr/bin/env python3
"""A cache write against a held save (spec §11 #553, #552, #429).

    python3 tools/proof/save_hold_proof.py [--only R1,M2] [--mutant NAME] [--app PATH]

A save of a titled document lists `cache/` and later swaps the new package in,
so a file written into the package between the two goes with the old one
(spec §11 #429). `-RCDevSaveHold <s>` holds every save of a launch on main
after the new package is written and before the swap: the window made wide
enough for a script to write into.

A save held on a launch holds every save of that launch, `new_project
{path}`'s own included, so each row's document is made, saved and closed on a
plain launch first (`prepare`) and opened on the held one.

Every cache file is published through `CacheLedger.publish` under its
writer's name, and the dev tool `cache_ledger` answers, per cache folder,
`save_waits` (the publishes of each writer that found a save in flight and
waited it out) and arms a GATE that holds a named writer's next publish until
a save of that folder is inside its hold (spec §11 #552). So a row says its
publish met a save from a fact of that run, never from two clocks.

**R1** (#553): an offline audio render that runs while a save is held lands in
the package and plays. The launch is `-RCDevRampRenderHold 3 -RCDevSaveHold
12`. The document holds 2 s of `AV.mov` at ×1 and no `cache/ramp-audio/`.
`set_speed` ×2 with Keep pitch off queues the render, held 3 s; `save_project`
is the next call, so the render runs at about 3 s inside the save's 12 s. It
passes when the render's `.caf` is not there when the save is sent, is in the
package's `cache/ramp-audio/` within `LAND_BOUND` of the save's return (so the
render overlapped the save; one that started after it could not be), nothing
else is left in that folder, `save_waits["ramp-audio"]` rose by one, and
`export audio_wav` then succeeds. Before #553 the render wrote
`<name>.landing` into the old package and the export answered "the render
could not be moved into place".

**The gate rows** (#552), one per writer, on one launch with `-RCDevSaveHold
3`. A row arms its writers' gates, triggers them with a call that returns at
once, and then, while a gate is armed or waiting, polls `cache_ledger` and
sends `save_project` whenever one is `waiting`. A row passes when its gate
ended `save`, its `save_waits` rose by exactly one, and its files are in the
package afterwards.

- **M1–M5**, the media passes, from one `import_media` of `AV.mov` into a
  saved document: `thumbs` (`thumbs/<id>/complete.json`), `peaks`,
  `loudness`, `sync-features` (`sync/<id>.bin`, `.pcm`) and `speech` (each
  its `.bin` and `.complete.json`).
- **D1**, `device-transcript`: a document holding 2 s of `speech.mov`, its
  Transcript tab shown (`select_inspector_tab`), whose fill reads the media
  on this Mac and stores it: `device-transcripts/<id>-<language>.json`. A Mac
  with no on-device model (`transcript_view` answers `no_model`) is a named
  skip, never a pass.
- **O1–O3**, the offline renders, by folder: `ramp-audio` (a clip set to ×2
  with Keep pitch off), `isolated` and `voiced` (a second clip given
  isolation 1 and the echo voice effect; the voice render is wanted only
  once the isolated one lands). Each folder holds one `.caf` and nothing else.

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
- `thumbs-outside` (M1), `peaks-outside` (M2), `loudness-outside` (M3),
  `sync-outside` (M4), `speech-outside` (M5), `transcript-outside` (D1),
  `render-move-outside` (O1–O3, one site): the writer's one publish keeps its
  gate and drops the ledger (`CacheLedger.outside`, added by the mutant), so
  its write falls inside the held save and is lost at the swap. Caught when
  the row fails with its count unchanged.
- `transcript-no-model` (D1's host-skip arm, #571): the Transcript tab's
  fill resolves its language against an empty list, which is what a Mac with
  no on-device model answers, so `transcript_view` says `no_model`. It has a
  verdict of its own, SKIPPED BY NAME (exit 0): D1 must be skipped with
  `no_model` in its sentence and never scored, and every other row must be
  scored and pass; anything else exits 1. The arm's other status, `failed`,
  takes the same branch and is not forced separately.

Needs `tools/proof/media/AV.mov` and `speech.mov`. Debug by default
(`RC_PROOF_APP=release` for the record).
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
SPEECH_MOV = ROOT / "tools/proof/media/speech.mov"
CALL_BOUND = 300
BUILD_BOUND = 1500
RENDER_HOLD = 3
R1_SAVE_HOLD = 12
# How long after the held save returns the render may take to appear: its
# publish only waits for the save's end.
LAND_BOUND = 2.0
R1_LENGTH = 1_200_000   # ticks: 2 s of source, 1 s at ×2
RENDER_ROWS = ["R1"]
GATE_SAVE_HOLD = 3
# How long one row may take from its trigger to its last gate's end, and each
# writer may wait at its gate; then how long a released publish has to land.
GATE_BOUND = 240
FILE_BOUND = 15
# writer: (row, the files its publish writes under cache/, `{m}` the media id;
# a name ending `/` is a folder that must hold one `.caf` and nothing else)
MEDIA_WRITERS = {
    "thumbs": ("M1", ["thumbs/{m}/complete.json"]),
    "peaks": ("M2", ["peaks/{m}.bin", "peaks/{m}.complete.json"]),
    "loudness": ("M3", ["loudness/{m}.bin", "loudness/{m}.complete.json"]),
    "sync-features": ("M4", ["sync/{m}.bin", "sync/{m}.pcm", "sync/{m}.complete.json"]),
    "speech": ("M5", ["speech/{m}.bin", "speech/{m}.complete.json"]),
}
TRANSCRIPT_WRITERS = {"device-transcript": ("D1", ["device-transcripts/{m}-*.json"])}
OFFLINE_WRITERS = {
    "ramp-audio": ("O1", ["ramp-audio/"]),
    "isolated": ("O2", ["isolated/"]),
    "voiced": ("O3", ["voiced/"]),
}
MEDIA_ROWS = [row for row, _ in MEDIA_WRITERS.values()]
TRANSCRIPT_ROWS = ["D1"]
OFFLINE_ROWS = [row for row, _ in OFFLINE_WRITERS.values()]
GATE_ROWS = MEDIA_ROWS + TRANSCRIPT_ROWS + OFFLINE_ROWS
ROWS = RENDER_ROWS + GATE_ROWS + ["Z1"]
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

LEDGER = "app/Sources/MediaCacheLedger.swift"
PUBLISH_HEAD = "        @discardableResult\n        func publish(\n"
# The gate kept, the ledger dropped: what a write outside the ledger is.
OUTSIDE = ("        @discardableResult\n"
           "        func outside(\n"
           "            in cacheDir: URL, for pass: CachePass?, as writer: String, "
           "_ body: () -> Void\n"
           "        ) -> Bool {\n"
           "            CacheLedgerDev.shared.arrive(cacheDir.standardizedFileURL.path, writer)\n"
           "            body()\n"
           "            return true\n"
           "        }\n\n")
UNCHANGED = "did NOT wait"
TAB_SOURCE = "app/Sources/TranscriptTabSource.swift"
# The Transcript fill's one resolve of its language; an empty list is a Mac with no model.
RESOLVE = ("                if language == nil { language = Self.resolve(wanted, "
           "in: Transcriber.languages()) }\n")
NO_LANGUAGES = "                if language == nil { language = Self.resolve(wanted, in: []) }\n"


def outside(rows, path, anchor):
    """A mutant that sends one publish site through `outside`."""
    assert anchor.count("publish(") == 1, anchor
    return (rows, [(LEDGER, PUBLISH_HEAD, OUTSIDE + PUBLISH_HEAD),
                   (path, anchor, anchor.replace("publish(", "outside("))], UNCHANGED, False)


def pass_site(writer, tail=""):
    return f'CacheLedger.shared.publish(in: cacheDir, for: pass, as: "{writer}") {{\n' + tail


# name: (rows, edits, the text a failing row must carry or None, expected to survive)
MUTANTS = {
    "thumbs-outside": outside(["M1"], "app/Sources/MediaImporter+Thumbnails.swift", pass_site(
        "thumbs", "                guard stripHolds(written, in: directory) else { return }\n")),
    "peaks-outside": outside(["M2"], "app/Sources/MediaImporter+Peaks.swift",
                             pass_site("peaks")),
    "loudness-outside": outside(["M3"], "app/Sources/MediaImporter+Loudness.swift",
                                pass_site("loudness")),
    "sync-outside": outside(["M4"], "app/Sources/MediaImporter+SyncFeatures.swift",
                            pass_site("sync-features")),
    "speech-outside": outside(["M5"], "app/Sources/MediaImporter+Speech.swift",
                              pass_site("speech")),
    "transcript-outside": outside(
        ["D1"], "app/Sources/DeviceTranscriptCache.swift",
        "MediaImporter.CacheLedger.shared.publish(\n"
        "            in: cacheDir, for: nil, as: \"device-transcript\"\n"),
    "render-move-outside": outside(
        OFFLINE_ROWS, RENDERS,
        "MediaImporter.CacheLedger.shared.publish(in: cache, for: nil, as: writer) {\n"),
    "landing-in-package": (["R1"], [
        (LANDING, LANDING_OUTSIDE, LANDING_BESIDE),
        (RENDERS, HOLD_LINE, FOLDER_FIRST + HOLD_LINE)], MOVED, False),
    "folder-before-publish": (["R1"], [
        (RENDERS, HOLD_LINE, FOLDER_FIRST + HOLD_LINE)], None, True),
    "transcript-no-model": (RENDER_ROWS + GATE_ROWS, [
        (TAB_SOURCE, RESOLVE, NO_LANGUAGES)], None, False),
}
# A mutant whose verdict is a named skip (#571): name: (the row that must be skipped and
# never scored, the text its skip must carry). Every other row must be scored and pass.
SKIPS = {"transcript-no-model": ("D1", "no_model")}

results = {}
skipped = {}
selected = set(ROWS)
state = {}


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}", flush=True)


def skip(name, why):
    if name in selected:
        skipped[name] = why
        print(f"  skip {name} {why}", flush=True)


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

    def ledger(self, **arguments):
        return self.call("cache_ledger", **arguments)

    def waits(self, writer):
        return self.ledger()["save_waits"].get(writer, 0)

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
            waits = doc.waits("ramp-audio")
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
            waited = doc.waits("ramp-audio")
            try:
                out = doc.export("r1")
                exported = f"exported {out.stat().st_size} bytes"
                played = out.stat().st_size > 44
            except mcp.ToolError as error:
                exported, played = f"the export FAILED: {error}", False
            clean = len(after) == 1 and after[0].endswith(".caf")
            met = (not any(n.endswith(".caf") for n in early) and landed is not None
                   and held >= R1_SAVE_HOLD and waited == waits + 1)
            check("R1", not before and met and clean and played,
                  f"save_waits {waits} → {waited} "
                  f"({'the publish met the held save and waited' if waited == waits + 1 else 'the publish ' + UNCHANGED + ' for a save'}); "
                  f"cache/ramp-audio/ {before} before; {early} when the save was sent; the "
                  f"save held {held:.1f} s (every save {R1_SAVE_HOLD} s, the render "
                  f"{RENDER_HOLD} s); the render "
                  + ("NOT there" if landed is None else f"there {landed:.2f} s")
                  + f" after it returned (bound {LAND_BOUND} s); then {after}; {exported}")
        finally:
            doc.close()
    attempt(r1, "R1")


# ---- the gate rows --------------------------------------------------------------

def gate_prepare(client):
    def media_doc():
        Doc(client, "m").save_and_close()

    def transcript_doc():
        doc = Doc(client, "d")
        media = doc.media(SPEECH_MOV, "d-speech")
        doc.call("trim_end", clip=doc.clip(media), to=R1_LENGTH)
        state["d"] = media
        doc.save_and_close()

    def offline_doc():
        doc = Doc(client, "o")
        ramped = doc.clip(doc.media(AV_MOV, "o-av"))
        doc.call("trim_end", clip=ramped, to=R1_LENGTH)
        voiced = doc.clip(doc.media(SPEECH_MOV, "o-speech"), at=3 * R1_LENGTH)
        doc.call("trim_end", clip=voiced, to=R1_LENGTH)
        state["o"] = (ramped, voiced)
        doc.save_and_close()
    if selected & set(MEDIA_ROWS):
        attempt(media_doc, *MEDIA_ROWS)
    if selected & set(TRANSCRIPT_ROWS):
        attempt(transcript_doc, *TRANSCRIPT_ROWS)
    if selected & set(OFFLINE_ROWS):
        attempt(offline_doc, *OFFLINE_ROWS)


def present(doc, patterns, media):
    """Which of a writer's files are missing from the package now."""
    missing = []
    for pattern in patterns:
        if pattern.endswith("/"):
            names = doc.files(pattern[:-1])
            if len(names) != 1 or not names[0].endswith(".caf"):
                missing.append(f"{pattern} holds {names}")
        elif not list((doc.path / "cache").glob(pattern.format(m=media))):
            missing.append(pattern.format(m=media))
    return missing


def gate_rows_of(doc, writers, trigger, media=None, stopped=None):
    """Arms `writers`, runs `trigger` (which answers the media id when the
    rows have one), saves once for each writer found at its gate, and scores
    a row per writer. `stopped()` answers why the rows cannot run on this
    host, or None."""
    names = list(writers)
    before = doc.ledger(gate=names, seconds=GATE_BOUND)["save_waits"]
    triggered = trigger()
    media = triggered if triggered is not None else media
    saves = 0
    deadline = time.monotonic() + GATE_BOUND
    while time.monotonic() < deadline:
        gates = doc.ledger()["gate"]
        if any(gates.get(w) == "waiting" for w in names):
            doc.call("save_project")
            saves += 1
            continue
        if not any(gates.get(w) == "armed" for w in names):
            break
        why = stopped() if stopped else None
        if why:
            doc.ledger(gate=[])
            for writer in names:
                skip(writers[writer][0], why)
            return
        time.sleep(0.1)
    # A released publish lands only after its save has ended.
    settle = time.monotonic() + FILE_BOUND
    while time.monotonic() < settle:
        answer = doc.ledger()
        if all(answer["save_waits"].get(w, 0) > before.get(w, 0)
               and not present(doc, writers[w][1], media) for w in names):
            break
        time.sleep(0.2)
    answer = doc.ledger(gate=[])
    for writer in names:
        row, patterns = writers[writer]
        was, now = before.get(writer, 0), answer["save_waits"].get(writer, 0)
        gate = answer["gate"].get(writer)
        missing = present(doc, patterns, media)
        check(row, gate == "save" and now == was + 1 and not missing,
              f"{writer}: its gate ended {gate}; save_waits {was} → {now} "
              f"({'the publish met the held save and waited' if now == was + 1 else 'the publish ' + UNCHANGED + ' for a save'}); "
              + ("its files are in the package" if not missing else f"MISSING {missing}")
              + f"; {saves} saves sent, each held {GATE_SAVE_HOLD} s")


def gate_rows(client):
    def media_rows():
        doc = Doc(client, "m", new=False)
        try:
            gate_rows_of(doc, MEDIA_WRITERS, lambda: doc.media(AV_MOV, "m-av"))
        finally:
            doc.close()

    def transcript_rows():
        if "d" not in state:
            return
        doc = Doc(client, "d", new=False)
        try:
            def no_model():
                shown = doc.call("transcript_view")
                if shown.get("status") in ("no_model", "failed"):
                    return (f"this Mac's Transcript tab answered {shown.get('status')}: "
                            f"{shown.get('status_text')}")
                return None
            gate_rows_of(doc, TRANSCRIPT_WRITERS,
                         lambda: doc.call("select_inspector_tab", tab="transcript") and None,
                         media=state["d"], stopped=no_model)
        finally:
            doc.close()

    def offline_rows():
        if "o" not in state:
            return
        doc = Doc(client, "o", new=False)
        try:
            ramped, voiced = state["o"]

            def trigger():
                doc.call("set_speed", clip=ramped, rate=2, keep_pitch=False)
                doc.call("set_audio", clips=[voiced],
                         patch={"isolation": 1, "voice": {"kind": "echo"}})
            gate_rows_of(doc, OFFLINE_WRITERS, trigger)
        finally:
            doc.close()
    if selected & set(MEDIA_ROWS):
        attempt(media_rows, *MEDIA_ROWS)
    if selected & set(TRANSCRIPT_ROWS):
        attempt(transcript_rows, *TRANSCRIPT_ROWS)
    if selected & set(OFFLINE_ROWS):
        attempt(offline_rows, *OFFLINE_ROWS)


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
        ("gate-prepare", [], gate_prepare, set(GATE_ROWS)),
        ("gate", ["-RCDevSaveHold", str(GATE_SAVE_HOLD)], gate_rows, set(GATE_ROWS)),
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
    for needed in (AV_MOV, SPEECH_MOV):
        if not needed.exists():
            print(f"{needed} is missing (tools/proof/README.md says how to make the test media)")
            return 2
    binary = Path(args.app) if args.app else None
    if args.mutant:
        named, _, needle, survivor = MUTANTS[args.mutant]
        if args.mutant in SKIPS:
            print(f"save holds — the {args.mutant} MUTANT ({SKIPS[args.mutant][0]} must be "
                  "SKIPPED by name, every other row scored)", flush=True)
        else:
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
    print(f"\n{len(passed)}/{len(results)} rows passed" + (f"; failed {failed}" if failed else "")
          + (f"; skipped {sorted(skipped)}" if skipped else ""))
    if args.mutant:
        named, _, needle, survivor = MUTANTS[args.mutant]
        if args.mutant in SKIPS:
            row, text = SKIPS[args.mutant]
            others = sorted(selected - {row})
            wrong = ([f"{row} was scored"] if row in results else []) + (
                [f"{row} was not skipped"] if row not in skipped else
                [] if text in skipped[row] else [f"{row}'s skip does not say {text!r}"]) + [
                f"{n} was not scored" for n in others if n not in results] + [
                f"{n} failed" for n in others if n in failed]
            if wrong:
                print(f"MUTANT {args.mutant} did NOT show the skip: {'; '.join(wrong)}")
                return 1
            print(f"MUTANT {args.mutant} SKIPPED {row} BY NAME: {skipped[row]}; "
                  f"{len(others)} other rows scored")
            return 0
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
