#!/usr/bin/env python3
"""Codec export C6a (spec §11 CX-18): the Export Queue's memory limit on bundled-encoder
jobs, the held job's sentence, `export_status`'s `waiting` and `estimated_seconds`, and the
export sheet's time estimate.

The probe rows run `encoder_limit_probe.swift`, built through `swift_build.build()` over
`app/Sources` with `Blank.mp4`, `Fonts` and a `default.metallib` of `Compositor.metal` and
`ExportI010.metal` beside it, into `tools/proof/work/encoder-limit/probe/` (reused when
every input is byte-identical). It needs no app and no instance: its two live projects —
A1 (`av1_export_proof.av_doc`'s: 640 × 360, AV.mov from 0 under a two-second text clip) and
W9 (`webm_export_proof.long_doc`'s: 1920 × 1080, AV.mov 24 times at scale 3) — are built in
the probe from AV.mov, as `webm_readers_probe.swift` builds A1's. Every expected value is
computed HERE from P0's dump of the tables, in this file's own arithmetic.

  B0  the probe builds and answers (a probe that does not build is B0's FAIL, and every
      probe row's)
  P0  both tables dumped: the eight keys (av1, av1_webm × faster/balanced/smaller at 10
      bits; vp9_webm at 8 and 10), each figure positive with a source, 4K above 1080p
  R1  physical 16, 24, 32, 48, 64, 96, 128 GiB: budget = physical / 4, and per key at
      1080p and 4K the identical jobs admitted in sequence = max(1, ⌊budget / cost⌋), the
      cost the table's figure at the size
  R2  a writer row with no entry (`vp9_alpha_webm`, `libvpx`) costs the whole budget: it is
      admitted alone, then neither another of it nor an av1 job; an av1 job's booking keeps
      it out
  R3  an AVFoundation row (`h264`): no key, cost 0, `begin` books nothing, admitted beside a
      full ledger
  E1  `estimatedSeconds` per key at 1280×720, 1920×1080, 2560×1440, 3840×2160, 7680×4320
      and 150 / 300 / 1800 frames, and `sheetLine` its text
  E2  `estimateText` at 0.4, 2.4, 7.4, 57.4, 59.9, 60, 89, 90, 3569, 3570, 3600, 5399, 5400
  E3  `sheetLine` and `estimatedSeconds` nil for h264, and for `av1` at a rate that cannot
      be stepped (fps 0/1: no frame count, so no estimate rather than 0 frames)
  Q1  live, the shared queue and ledger, physical = 4 × the sheet job's cost: a headless
      Export… sheet writes W9 as `av1` Smaller; A (`av1`, A1), B and C (`h264`, A1) are
      enqueued. A waits with the exact sentence while the sheet runs; B then C run and
      complete before the sheet finishes; A launches only after the sheet's finish and
      completes; every file exists
  Q2  `AgentExports.track(A)` while held: status queued, `waiting` the sentence,
      `estimated_seconds` the table's
  Q3  physical 1 TiB, a sheet writing W9 as `av1` Faster: A runs before the sheet finishes
  Q4  `ExportQueueRowView.status`: the sentence for held A, "Waiting" for C while B runs;
      `ExportQueueRowView.toolTip(for:)` ends with the whole sentence for A (the status
      label truncates its tail) and has no "Waiting for memory" line for C
  Q5  the ledger is empty after Q1 drains, after Q3, after two `av1` jobs back to back (the
      second launched inside the first's `end`), after the queue refuses an empty
      project's `av1` job synchronously, and after a sheet does
App rows (`--app`, `RC_PROOF_APP`; instances in `tools/proof/work/encoder-limit/`):
  S1  File ▸ Export… on A1's project with `{"preset_id":"av1","encoder_speed":"smaller"}`
      pinned (`av1_export_proof.sheet_reading`'s pins): the summary label's second line is
      the table's "Estimated time: …"
  S2  the same with `{"preset_id":"h264"}`: no "Estimated" anywhere on the sheet
  X1  `export` av1 of A1, then `export_status` at once: `estimated_seconds` the table's; an
      h264 export's answer has none
  Z1  no instance log carries a `Frame Job: ` line

  python3 tools/proof/encoder_limit_proof.py [--probe] [--app debug|release|<.app>]
                                             [--mutant NAME]

`--probe` runs B0–Q5 alone. `--mutant NAME` builds the probe over a copy of `app/Sources`
with the mutant's anchor replaced and runs the probe rows: exit 1 when every row it names
fails (CAUGHT), 0 when it survives, 2 when the control cannot be performed.

  no-hold           static `admits` always true: R1, Q1
  strict-order      `start()` stops at a held job: Q1
  sheet-uncounted   the sheet's `begin` removed: Q1
  no-wake           the queue's ledger observer removed: Q1
  budget-half       the budget physical / 2: R1
  estimate-flat     `value(pixels:)` answers `at1080`: E1
  no-waiting-key    `export_status`'s `waiting` dropped: Q2
  row-says-waiting  the row's `.waiting` status always "Waiting": Q4
  begin-late        the queue's `begin` after `exporter.export`: Q5
  token-overwrite   `finished` ends `ledgerToken`, then clears it: Q5
  tip-drops-hold    the tooltip's held-sentence line removed: Q4
  estimate-no-count a nil frame count estimated as 0 frames: E3
"""

import argparse
import json
import math
import os
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
import av1_export_proof as av1  # noqa: E402
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402

WORK = HERE / "work" / "encoder-limit"
PROBE_SWIFT = HERE / "encoder_limit_probe.swift"
SOURCES = ROOT / "app" / "Sources"
GIB = 1 << 30
PHYSICAL = [16, 24, 32, 48, 64, 96, 128]
SIZES_R = [(1920, 1080), (3840, 2160)]
SIZES_E = [(1280, 720), (1920, 1080), (2560, 1440), (3840, 2160), (7680, 4320)]
FRAMES_E = [150, 300, 1800]
TEXTS_E = [0.4, 2.4, 7.4, 57.4, 59.9, 60, 89, 90, 3569, 3570, 3600, 5399, 5400]
# The proof's own name for each key → (preset, speed, bits): ExportEncoderKey(settings:)'s
# rule, restated (CX-18 (4)).
KEYS = {
    "av1:faster": ("av1", "faster", 10), "av1:balanced": ("av1", "balanced", 10),
    "av1:smaller": ("av1", "smaller", 10), "av1_webm:faster": ("av1_webm", "faster", 10),
    "av1_webm:balanced": ("av1_webm", "balanced", 10),
    "av1_webm:smaller": ("av1_webm", "smaller", 10),
    "vp9_webm:sdr": ("vp9_webm", None, 8), "vp9_webm:hlg": ("vp9_webm", None, 10),
}
PROBE_ROWS = ["B0", "P0", "R1", "R2", "R3", "E1", "E2", "E3", "Q1", "Q2", "Q3", "Q4", "Q5"]
APP_ROWS = ["S1", "S2", "X1", "Z1"]

QUEUE = "ExportQueueController.swift"
MUTANTS = {
    "no-hold": (["R1", "Q1"], [
        ("ExportEncoderLedger.swift",
         "        guard !running.isEmpty else { return true }\n",
         "        return true\n")]),
    "strict-order": (["Q1"], [
        (QUEUE,
         "        while exporter == nil, let index = jobs.firstIndex(where: {\n"
         "            $0.state == .waiting && ledger.admits($0.settings)\n"
         "        }) {\n",
         "        while exporter == nil,\n"
         "            let index = jobs.firstIndex(where: { $0.state == .waiting }),\n"
         "            ledger.admits(jobs[index].settings)\n"
         "        {\n")]),
    "sheet-uncounted": (["Q1"], [
        ("ExportProgressSheetController.swift",
         "        ledgerToken = ExportEncoderLedger.shared.begin(settings)\n", "")]),
    "no-wake": (["Q1"], [
        (QUEUE,
         "        NotificationCenter.default.addObserver(\n"
         "            self, selector: #selector(ledgerChanged(_:)),\n"
         "            name: ExportEncoderLedger.didChangeNotification, object: ledger)\n",
         "")]),
    "budget-half": (["R1"], [
        ("ExportEncoderLedger.swift",
         "UInt64 { physicalMemory / 4 }", "UInt64 { physicalMemory / 2 }")]),
    "estimate-flat": (["E1"], [
        ("ExportEncoderCosts.swift",
         "        if p <= low { return at1080 * p / low }\n",
         "        if p >= 0 { return at1080 }\n")]),
    "no-waiting-key": (["Q2"], [
        ("AgentServer+ExportStatus.swift",
         "            if let held = record.message { answer[\"waiting\"] = held }\n",
         "            break\n")]),
    "row-says-waiting": (["Q4"], [
        ("ExportQueueWindowController.swift",
         "            return job.message ?? \"Waiting\"\n", "            return \"Waiting\"\n")]),
    "begin-late": (["Q5"], [
        (QUEUE, "        ledgerToken = ledger.begin(job.settings)\n", ""),
        (QUEUE,
         "            completion: { [weak self] result in self?.finished(job.id, result) })\n",
         "            completion: { [weak self] result in self?.finished(job.id, result) })\n"
         "        ledgerToken = ledger.begin(job.settings)\n")]),
    "token-overwrite": (["Q5"], [
        (QUEUE,
         "        let token = ledgerToken\n        ledgerToken = nil\n        ledger.end(token)\n",
         "        ledger.end(ledgerToken)\n        ledgerToken = nil\n")]),
    "tip-drops-hold": (["Q4"], [
        ("ExportQueueWindowController.swift",
         "        if job.state == .waiting, let held = job.message { tip += \"\\n\" + held }\n",
         "")]),
    "estimate-no-count": (["E3"], [
        ("ExportEncoderCosts.swift",
         "            let frames = settings.sequenceFrameCount\n",
         "            let frames = Optional(settings.sequenceFrameCount ?? 0)\n")]),
}

results = {}


def check(ident, ok, detail=""):
    results[ident] = bool(ok)
    print(f"{'ok  ' if ok else 'FAIL'} {ident}  {detail}"[:1600], flush=True)


# ---- the arithmetic, restated ---------------------------------------------------------

def swift_round(x):
    """Swift's `rounded()` (to nearest, halves away from zero)."""
    return math.floor(x + 0.5) if x >= 0 else -math.floor(-x + 0.5)


def figure_value(figure, pixels, p1080, p2160):
    low, high, p = float(p1080), float(p2160), float(max(0, pixels))
    if p <= low:
        return figure["at1080"] * p / low
    return figure["at1080"] + (figure["at2160"] - figure["at1080"]) * (p - low) / (high - low)


class Tables:
    def __init__(self, answer):
        self.p1080, self.p2160 = answer["pixels1080"], answer["pixels2160"]
        self.memory = {self.key(e["key"]): e["figure"] for e in answer["memory"]}
        self.time = {self.key(e["key"]): e for e in answer["time"]}

    @staticmethod
    def key(raw):
        return (raw["preset"], raw["speed"], raw["bits"])

    def cost(self, name, pixels, budget):
        figure = self.memory.get(KEYS[name])
        if figure is None:
            return budget
        return int(swift_round(max(0.0, figure_value(figure, pixels, self.p1080, self.p2160))))

    def seconds(self, name, pixels, frames):
        entry = self.time.get(KEYS[name])
        if entry is None:
            return None
        return entry["setupSeconds"] + frames * figure_value(
            entry["perFrame"], pixels, self.p1080, self.p2160)


def estimate_text(s):
    if s < 60:
        return f"about {max(5, int(swift_round(s / 5)) * 5)} s"
    if s < 3600:
        return f"about {max(1, int(swift_round(s / 60)))} min"
    m = int(swift_round(s / 60))
    return f"about {m // 60} h {m % 60} min"


def gigabytes(b):
    return "%.1f GB" % (b / 1_073_741_824)


def sentence(cost, running, budget):
    return (f"Waiting for memory: AV1 and VP9 exports running now hold about "
            f"{gigabytes(sum(running))} of the {gigabytes(budget)} this Mac allows them, and "
            f"this one needs about {gigabytes(cost)}.")


def name_of(described):
    """The proof's key name for the probe's `describe(settings)`."""
    if described["preset"] in ("av1", "av1_webm"):
        return f"{described['preset']}:{described['speed'] or 'balanced'}"
    return f"vp9_webm:{'hlg' if described['color'] in ('hlg', 'pq') else 'sdr'}"


# ---- the probe ------------------------------------------------------------------------

def build_probe(sources, folder):
    """The probe built over `sources` in `folder`: (binary, "") or (None, why)."""
    folder.mkdir(parents=True, exist_ok=True)
    entry = folder / "main.swift"
    text = PROBE_SWIFT.read_text()
    if not entry.exists() or entry.read_text() != text:
        entry.write_text(text)
    resources = ROOT / "app" / "Resources"
    shutil.copy2(resources / "Blank.mp4", folder / "Blank.mp4")
    shutil.copytree(resources / "Fonts", folder / "Fonts", dirs_exist_ok=True)
    airs = []
    for shader in ("Compositor", "ExportI010"):
        air = folder / f"{shader}.air"
        step = bounded.run(["xcrun", "-sdk", "macosx", "metal", "-c",
                            str(resources / "Shaders" / f"{shader}.metal"), "-o", str(air)], 300)
        if step["rc"] != 0:
            return None, f"{shader}.metal did not build: {step['stderr'][-300:]}"
        airs.append(str(air))
    step = bounded.run(["xcrun", "-sdk", "macosx", "metallib", *airs, "-o",
                        str(folder / "default.metallib")], 300)
    if step["rc"] != 0:
        return None, f"the metallib did not build: {step['stderr'][-300:]}"
    binary = folder / "encoder-limit-probe"
    try:
        built = swift_build.build(sources=swift_build.app_sources(sources) + [entry],
                                  output=binary, defines=["FRAMEJOB_DEV_TOOLS"], timeout=900)
    except swift_build.SwiftBuildFailed as error:
        lines = [line for line in error.diagnostics if ": error:" in line]
        return None, "the probe did not build: " + " | ".join(
            lines[:3] or list(error.diagnostics[:3]) or [str(error)])
    print(f"  probe: up to date — {binary}" if built.reused
          else f"  probe: built in {built.seconds:.0f} s — {binary}", flush=True)
    return binary, ""


def run_probe(sources=SOURCES, folder=None):
    """B0 and every probe row, from one probe run over `sources`."""
    folder = folder or WORK / "probe"
    binary, why = build_probe(Path(sources), folder)
    if binary is None:
        for ident in PROBE_ROWS:
            check(ident, False, why)
        return None
    answer_path, out = folder / "answer.json", folder / "out"
    answer_path.unlink(missing_ok=True)
    ran = bounded.run([str(binary), str(av1.AV), str(out), str(answer_path)], 1500,
                      cwd=str(folder))
    if ran["expired"] or ran["rc"] != 0 or not answer_path.exists():
        why = "the probe did not run: " + (ran["stdout"] + ran["stderr"]).strip()[-400:]
        for ident in PROBE_ROWS:
            check(ident, False, why)
        return None
    answer = json.loads(answer_path.read_text())
    check("B0", True, f"built and answered ({folder})")
    score_probe(answer)
    return answer


def score_probe(answer):
    tables = Tables(answer)
    # P0
    want = set(KEYS.values())
    problems = []
    for label, table in (("memory", tables.memory), ("time", tables.time)):
        if set(table) != want:
            problems.append(f"{label} keys {sorted(map(str, table))}")
    for key, figure in tables.memory.items():
        if not (0 < figure["at1080"] < figure["at2160"]) or not figure["source"]:
            problems.append(f"memory {key} {figure}")
    for key, entry in tables.time.items():
        f = entry["perFrame"]
        if not (0 < f["at1080"] < f["at2160"]) or "provisional" not in f["source"]:
            problems.append(f"time {key} {f}")
    check("P0", not problems, f"{len(tables.memory)} memory and {len(tables.time)} time "
          f"entries; {problems or 'all positive, 4K above 1080p, sourced'}")

    # R1
    misses, seen = [], set()
    for row in answer["r1"]:
        budget = row["physicalGiB"] * GIB // 4
        cost = tables.cost(row["key"], row["width"] * row["height"], budget)
        admitted = max(1, budget // cost) if cost else None
        seen.add((row["physicalGiB"], row["key"], row["width"]))
        if (row["budget"], row["cost"], row["admitted"]) != (budget, cost, admitted):
            misses.append(f"{row['physicalGiB']} GiB {row['key']} {row['width']}: "
                          f"{(row['budget'], row['cost'], row['admitted'])} ≠ "
                          f"{(budget, cost, admitted)}")
    full = len(seen) == len(PHYSICAL) * len(KEYS) * len(SIZES_R)
    sample = [r for r in answer["r1"] if r["physicalGiB"] == 32 and r["width"] == 3840]
    check("R1", full and not misses,
          f"{len(answer['r1'])} cases; misses {misses[:4]}; at 32 GiB and 4K "
          + ", ".join(f"{r['key']} {r['admitted']}" for r in sample))

    # R2
    r2 = answer["r2"]
    ok = (r2["alphaCost"] == r2["budget"] == 64 * GIB // 4 and r2["firstAdmitted"]
          and not r2["secondAdmitted"] and not r2["av1BesideAlpha"]
          and not r2["alphaBesideAV1"] and r2["idle"])
    check("R2", ok, json.dumps(r2))

    # R3
    r3 = answer["r3"]
    check("R3", r3["token"] is None and r3["admittedBesideFull"] and r3["costsUnchanged"]
          and r3["cost"] == 0 and r3["key"], json.dumps(r3))

    # E1
    misses = []
    for row in answer["e1"]:
        expected = tables.seconds(row["key"], row["width"] * row["height"], row["frames"])
        got = row["seconds"]
        line = None if expected is None else "Estimated time: " + estimate_text(expected)
        if got is None or expected is None or abs(got - expected) > 1e-9 * max(1.0, expected) \
                or row["line"] != line:
            misses.append(f"{row['key']} {row['width']}×{row['height']} {row['frames']}: "
                          f"{got} {row['line']!r} ≠ {expected} {line!r}")
    count = len(SIZES_E) * len(FRAMES_E) * len(KEYS)
    sample = [f"{r['key']} {r['line']}" for r in answer["e1"]
              if r["frames"] == 1800 and r["width"] == 3840][:3]
    check("E1", len(answer["e1"]) == count and not misses,
          f"{len(answer['e1'])}/{count} cases; misses {misses[:4]}; 1800 frames at 4K: {sample}")

    # E2
    misses = [f"{r['seconds']}: {r['text']!r} ≠ {estimate_text(r['seconds'])!r}"
              for r in answer["e2"] if r["text"] != estimate_text(r["seconds"])]
    check("E2", len(answer["e2"]) == len(TEXTS_E) and not misses,
          f"misses {misses}; " + ", ".join(f"{r['seconds']}→{r['text']}" for r in answer["e2"]))

    # E3
    e3 = answer["e3"]
    check("E3", e3["line"] is None and e3["seconds"] is None
          and e3["unsteppedFrames"] is None and e3["unsteppedLine"] is None
          and e3["unsteppedSeconds"] is None, json.dumps(e3))

    q = answer["q"]
    if "error" in q:
        for ident in ("Q1", "Q2", "Q3", "Q4", "Q5"):
            check(ident, False, f"the live rows could not run: {q['error']}")
        return
    sheet_name, a_name = name_of(q["sheetSettings"]), name_of(q["aSettings"])
    sheet_pixels = q["sheetSettings"]["width"] * q["sheetSettings"]["height"]
    a_pixels = q["aSettings"]["width"] * q["aSettings"]["height"]
    sheet_cost = tables.cost(sheet_name, sheet_pixels, 0)
    budget = q["q1Physical"] // 4
    a_cost = tables.cost(a_name, a_pixels, budget)
    held = sentence(a_cost, [sheet_cost], budget)

    # Q1
    q1 = q["q1"]
    a, b, c, finished = q1["a"], q1["b"], q1["c"], q1["sheetFinishedAt"]

    def before(x, y):
        return x is not None and y is not None and x < y
    problems = []
    if q["q1Physical"] != 4 * sheet_cost or q["q1Booked"] != [sheet_cost]:
        problems.append(f"physical {q['q1Physical']} booked {q['q1Booked']} (the sheet's cost "
                        f"{sheet_cost})")
    if q["q1HeldMessage"] != held:
        problems.append(f"A's message {q['q1HeldMessage']!r}")
    if not (q1["sheetDone"] and q1["drained"] and finished is not None):
        problems.append(f"sheet done {q1['sheetDone']}, drained {q1['drained']}")
    if not q1["sheetStatus"].startswith("Exported"):
        problems.append(f"the sheet's line {q1['sheetStatus']!r}")
    if not (before(b["completed"], finished) and before(c["completed"], finished)
            and before(b["completed"], c["running"]) and before(b["running"], b["completed"])):
        problems.append(f"B {b} and C {c} not run in order before the sheet's finish {finished}")
    if a["running"] is None or finished is None or a["running"] < finished \
            or a["state"] != "completed":
        problems.append(f"A {a} against the sheet's finish {finished}")
    if q1["files"] != [True, True, True]:
        problems.append(f"files {q1['files']}")
    check("Q1", not problems,
          f"{problems or 'held, passed over, launched after the sheet'}; sheet {sheet_name} "
          f"cost {sheet_cost}, budget {budget}, A {a_name} cost {a_cost}; seqs A {a['running']}"
          f"/{a['completed']}, B {b['running']}/{b['completed']}, C {c['running']}/"
          f"{c['completed']}, sheet finished {finished}; sentence {held!r}")

    # Q2
    q2 = q["q2"] or {}
    a_seconds = tables.seconds(a_name, a_pixels, q["aSettings"]["frames"])
    want_seconds = None if a_seconds is None else int(swift_round(a_seconds))
    check("Q2", q2.get("status") == "queued" and q2.get("waiting") == held
          and q2.get("estimated_seconds") == want_seconds,
          f"status {q2.get('status')!r}, waiting {q2.get('waiting')!r}, estimated_seconds "
          f"{q2.get('estimated_seconds')} (want {want_seconds})")

    # Q3
    q3 = q["q3"]
    check("Q3", q3["sheetDone"] and q3["drained"] and q3["file"]
          and before(q3["a"]["running"], q3["sheetFinishedAt"])
          and q3["a"]["state"] == "completed",
          f"A running at {q3['a']['running']}, the sheet finished at {q3['sheetFinishedAt']}, "
          f"A {q3['a']['state']}, file {q3['file']}")

    # Q4
    a_tip, c_tip = q["q4ATip"] or "", q["q4CTip"] or ""
    check("Q4", q["q4BRunning"] and q["q4A"] == held and q["q4C"] == "Waiting"
          and a_tip.endswith("\n" + held) and "Waiting for memory" not in c_tip,
          f"B running {q['q4BRunning']}; A {q['q4A']!r}; C {q['q4C']!r}; "
          f"A tip {a_tip!r}; C tip {c_tip!r}")

    # Q5
    b2b, refusal, sheet = q["q5BackToBack"], q["q5QueueRefusal"], q["q5SheetRefusal"]
    ok = (q["q5Drained"] == [] and q["q5AfterQ3"] == [] and b2b["drained"]
          and b2b["x"] == b2b["y"] == "completed" and b2b["costs"] == []
          and refusal["state"] == "failed" and refusal["costs"] == []
          and sheet["finished"] and sheet["costs"] == [])
    check("Q5", ok, f"after Q1 {q['q5Drained']}, after Q3 {q['q5AfterQ3']}, back to back "
          f"{b2b}, queue refusal {refusal}, sheet refusal {sheet}")


# ---- the app rows ---------------------------------------------------------------------

def sheet_texts(app, label, choice):
    """One pinned instance (`av1_export_proof.sheet_reading`'s pins): File ▸ Export… on
    A1's project, every visible view's text, and the instance."""
    from screens import PINS
    arguments = ["-RCDevAppearance", "light"]
    for key, value in PINS:
        arguments += [f"-{key}", f"<string>{choice}</string>"
                      if key == "FrameJobExportChoice" else value]
    instance = av1.Instance(label, app, arguments, home=True)
    reading = {"instance": instance, "texts": []}
    try:
        if instance.client is None:
            reading["error"] = "the app did not listen"
            return reading
        doc = av1.av_doc(instance, "sheet")
        try:
            doc.call("perform_menu_item", path=["File", "Export…"])
            try:
                got = doc.call("snapshot_ui", window="sheet",
                               path=str(instance.dir / "sheet.png"))
            finally:
                doc.call("cancel_sheet")
            dump = json.loads(Path(got["layout_path"]).read_text())
        finally:
            doc.close()
        reading["texts"] = [v["text"] for v in dump.get("views", [])
                            if not v.get("hidden") and v.get("text")]
    except (mcp.ToolError, OSError, ValueError, KeyError) as error:
        reading["error"] = f"{type(error).__name__}: {error}"
    finally:
        instance.stop()
    return reading


def run_app_rows(app, tables, logs):
    a1_pixels = 640 * 360
    smaller = tables.seconds("av1:smaller", a1_pixels, av1.FRAMES)
    balanced = tables.seconds("av1:balanced", a1_pixels, av1.FRAMES)
    want_line = "Estimated time: " + estimate_text(smaller)

    one = sheet_texts(app, "s1", '{"preset_id":"av1","encoder_speed":"smaller"}')
    logs.append(one["instance"])
    summaries = [t for t in one["texts"] if "Estimated time" in t]
    second = [t.split("\n")[1] if "\n" in t else None for t in summaries]
    check("S1", not one.get("error") and second == [want_line],
          f"{one.get('error') or ''} summary {summaries!r}; want second line {want_line!r}")

    two = sheet_texts(app, "s2", '{"preset_id":"h264"}')
    logs.append(two["instance"])
    estimated = [t for t in two["texts"] if "Estimated" in t]
    check("S2", not two.get("error") and two["texts"] and not estimated,
          f"{two.get('error') or ''} {len(two['texts'])} texts; with 'Estimated': {estimated}")

    instance = av1.Instance("x1", app)
    logs.append(instance)
    try:
        if instance.client is None:
            check("X1", False, "the app did not listen")
            return
        doc = av1.av_doc(instance, "x1")
        try:
            answers = {}
            for preset in ("av1", "h264"):
                path = instance.dir / f"x1-{preset}.mp4"
                path.unlink(missing_ok=True)
                started = doc.client.call_with("export", {"project": doc.path,
                                                          "path": str(path), "preset": preset})
                status = doc.client.call("export_status", export_id=started["export_id"])
                done = doc.client.wait_export(started["export_id"], seconds=300)
                answers[preset] = (status, done.get("status"))
        finally:
            doc.close()
        want = int(swift_round(balanced))
        (first, first_done), (second, second_done) = answers["av1"], answers["h264"]
        check("X1", first.get("estimated_seconds") == want
              and first.get("status") in ("queued", "running")
              and "estimated_seconds" not in second and first_done == second_done == "done",
              f"av1 at once {first.get('status')} estimated_seconds "
              f"{first.get('estimated_seconds')} (want {want}), then {first_done}; h264 keys "
              f"{sorted(second)}, then {second_done}")
    except (mcp.ToolError, KeyError) as error:
        check("X1", False, f"{type(error).__name__}: {error}")
    finally:
        instance.stop()


# ---- mutants and main -----------------------------------------------------------------

def run_mutant(name):
    if name not in MUTANTS:
        print(f"unknown mutant {name}; the mutants are {sorted(MUTANTS)}")
        return 2
    named, edits = MUTANTS[name]
    copy = WORK / "mutant" / name
    sources = copy / "Sources"
    shutil.rmtree(copy, ignore_errors=True)
    shutil.copytree(SOURCES, sources)
    for file, anchor, replacement in edits:
        target = sources / file
        text = target.read_text()
        if text.count(anchor) != 1:
            print(f"mutant {name}: the control could not be performed — the anchor occurs "
                  f"{text.count(anchor)} times in {file}")
            return 2
        target.write_text(text.replace(anchor, replacement))
    answer = run_probe(sources, WORK / "mutant-probe" / name)
    if answer is None:
        print(f"mutant {name}: the control could not be performed — the probe failed whole")
        return 2
    failing = sorted(k for k, v in results.items() if not v)
    print(f"mutant {name}: named {named}, failing {failing}")
    if all(results.get(row) is False for row in named):
        print(f"MUTANT CAUGHT: {name}")
        return 1
    print(f"MUTANT SURVIVED: {name}")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description="the encoder memory limit (codec-export C6a)")
    parser.add_argument("--app", help="debug, release or a .app path (default RC_PROOF_APP)")
    parser.add_argument("--mutant", help="one of " + ", ".join(MUTANTS))
    parser.add_argument("--probe", action="store_true", help="B0–Q5 alone, no app")
    args = parser.parse_args(argv)
    if args.app:
        os.environ[proof_app.ENV] = args.app
    WORK.mkdir(parents=True, exist_ok=True)
    av1.WORK = WORK
    if args.mutant:
        return run_mutant(args.mutant)
    answer = run_probe()
    if not args.probe:
        logs = []
        try:
            app = proof_app.bundle()
            proof_app.require_fresh(proof_app.executable(app))
        except (proof_app.StaleApp, ValueError, OSError) as error:
            for ident in APP_ROWS:
                check(ident, False, f"the app cannot be driven: {error}")
        else:
            print(f"app {app}", flush=True)
            if answer is None:
                for ident in ("S1", "S2", "X1"):
                    check(ident, False, "no tables: the probe did not answer")
            else:
                run_app_rows(app, Tables(answer), logs)
            found = [(i.label, line) for i in logs for line in i.complaints()]
            check("Z1", not found, f"{len(logs)} instance logs; complaints {found[:4]}")
    passed = sum(results.values())
    print(f"scores: {passed}/{len(results)}")
    return 0 if all(results.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
