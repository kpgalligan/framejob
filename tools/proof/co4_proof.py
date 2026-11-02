#!/usr/bin/env python3
"""Road map "creator-jobs" CO4 — the cutout's edges: r0 ships, CO-S3 and Best owed for S-KEY1
(spec §11 CO-40, CO-41, CO-42).

    python3 tools/proof/co4_proof.py [--only B0,E4,…] [--mutant NAME] [--app PATH]

S-KEY1 (`samples/README.md`) does not exist, so CO-S3 has not run and r0 — CO-27's smoothstep
remap in `cutoutCover` — is the edge. This proof holds Edge to its documented amount (CO-40): at
Feather 0 the outline lies where the mask is m½(e) — `0.5 − 0.5·e` for |e| ≤ 0.5,
`0.375 − 0.25·e` above, `0.625 − 0.25·e` below — so on a mask edge rising over R display
pixels Edge ±1 moves it 3R/8.

**Probe row** (`co2a_probe.swift`, built exactly as `co2a_proof.probe_rows` builds it: every
`app/Sources` file but `main.swift`, `cutout_spike/mask_track_writer.swift`, the probe as
`main.swift`, `FRAMEJOB_DEV_TOOLS`, through `swift_build.py`, into `WORK/probe`):
- B0 the probe builds. A failed build is a scored FAIL of B0 and of every app row, since the
  canned packs are the probe's.

**Owed rows** (printed `SKIP <row> <reason>` while `tools/proof/media/creator/S-KEY1/` is
absent; once it exists each is a scored FAIL until CO-S1's owed rows and CO-S3 have run):
- E1 B on S-KEY1's composites at 1080p within 10 % of CO-S3's.
- E2 the same in an HLG project within 2 %.
- E3 `play_preview`'s count within CO-S3's cost bound.

**App rows** over MCP (`proof_app.binary()`, `RC_PROOF_APP`, or `--app`) on a scratch
`CFFIXED_USER_HOME`, each document closed after its row, in two launches:
- E4 (the canned launch, `-RCDevAnalysisCanned YES -RCDevAnalysisHold 3600`, as `co2a_proof`'s:
  no job may land beside a canned marker) a 1920 × 1080, 30 fps project on a transparent
  canvas; `barcode.mov` (`co2a_proof.barcode_fixtures()`, 1920 × 1080) at 0, scale 1, with
  `cutout {edge: e, feather: 0}`; a canned `ramp` pack (every mask 512 × 288, column i
  `round(255·clamp((i − 240)/32, 0, 1))`) over its 300 frames, analysed at every frame
  (`co2a_proof.install_pack`); `render_frame` at 1 s for e in −1, −0.5, 0, 0.5, 1. On rows
  y = 100, 540 and 980 the contour X is where alpha crosses 127.5, linearly interpolated
  between pixel centres (pixel p's centre at x = p + 0.5). Passes when every row's X is
  within 1.0 px of `3.75·(240.5 + 32·m½(e))`, and X(0) − X(1) and X(−1) − X(0) are each
  45 ± 1 px (3R/8 of the ramp's 120 display pixels).
- E4r (the second launch, no flags, as `co2a_proof`'s D2) `push_1080.mov`
  (`co2a_proof.person_fixtures()`), masks made by `get_media_analysis {media, kind: "masks",
  from: 0, to: 2 s}`, on a 1920 × 1080 transparent canvas at scale 1; `render_frame` at 1.5 s
  at Edge −1, 0 and +1 (Feather 0). Passes when at every pixel alpha(+1) ≥ alpha(0) − 1 and
  alpha(0) ≥ alpha(−1) − 1 (8-bit levels), and the count of pixels with alpha ≥ 128 strictly
  increases from −1 to 0 to +1; the three counts are printed.
- Z1 each launch's `grep "Frame Job: "` prints nothing.

`--mutant NAME`: r0's arithmetic broken in a tree copy (`tree_copy.py`), the copy built as the
proof's configuration, and only its rows run; CAUGHT (exit 0) when one of them fails. The
tree's mutated file's SHA-256 is read before and after and must be unchanged.

Prints `scores: P/N`; exits 0 iff every scored row passed.
"""

import argparse
import hashlib
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
sys.path.insert(0, str(HERE / "cutout_spike"))
sys.path.insert(0, str(HERE / "creator_spike"))
import bounded  # noqa: E402
import co2a_proof  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/co4"
HOME = WORK / "home"
SKEY1 = ROOT / "tools/proof/media/creator/S-KEY1"
SEC = 600_000
CW, CH = 1920, 1080
CALL_BOUND = 300
BUILD_BOUND = 1500
EDGES = [-1.0, -0.5, 0.0, 0.5, 1.0]
E4_ROWS = [100, 540, 980]
E4_T = SEC
E4R_T = 3 * SEC // 2
# The canned ramp: 0 left of texel 240, 255 from 272, so R = 32 texels × 3.75 = 120 display px.
RAMP_START, RAMP_TEXELS, SCALE = 240.5, 32, CW / 512
POSITION_TOLERANCE = 1.0
SHIFT, SHIFT_TOLERANCE = 45.0, 1.0
CANNED = ["-RCDevAnalysisCanned", "YES", "-RCDevAnalysisHold", "3600"]
OWED = {
    "E1": "S-KEY1 is missing: CO-S3 has not run, r0 ships (CO-40); B on its composites is owed",
    "E2": "S-KEY1 is missing: CO-S3 has not run, r0 ships (CO-40); B on its composites is owed, "
          "and r0's HLG coverage equals SDR's by CO2a2's D7",
    "E3": "no refinement ships, so CO-S3's cost bound has nothing to measure; r0's playback is "
          "JOB-61's",
}
PROBE_ROWS = ["B0"]
OWED_ROWS = ["E1", "E2", "E3"]
APP_ROWS = ["E4", "E4r", "Z1"]
ROWS = PROBE_ROWS + OWED_ROWS + APP_ROWS

SHADER = "app/Resources/Shaders/Compositor.metal"
MUTANTS = {
    "edge-sign": (["E4", "E4r"], [(
        SHADER, "    float c = 0.5 - 0.5 * clamp(u.cutoutEdge, -1.0, 1.0);\n",
        "    float c = 0.5 + 0.5 * clamp(u.cutoutEdge, -1.0, 1.0);\n")]),
    "no-clamp": (["E4"], [(
        SHADER, "    float lo = clamp(c - w * 0.5, 0.0, 1.0);\n"
        "    float hi = clamp(c + w * 0.5, 0.0, 1.0);\n",
        "    float lo = c - w * 0.5;\n    float hi = c + w * 0.5;\n")]),
}

results = {}
selected = set(ROWS)
built = False


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}", flush=True)


def skip(name, why):
    if name in selected:
        print(f"  SKIP {name} {why}", flush=True)


def m_half(e):
    """r0's contour at Feather 0 (spec §11 CO-40): the mask value where coverage is 0.5."""
    if e > 0.5:
        return 0.375 - 0.25 * e
    if e < -0.5:
        return 0.625 - 0.25 * e
    return 0.5 - 0.5 * e


def expected_x(e):
    return SCALE * (RAMP_START + RAMP_TEXELS * m_half(e))


def remove_work():
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))


# ---- the probe ------------------------------------------------------------------------------

def probe_row():
    """B0: `co2a_probe.swift` built as `co2a_proof.probe_rows` builds it; on success
    `co2a_proof`'s helpers read this binary and this proof's `WORK`."""
    global built
    out = WORK / "probe"
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(HERE / "co2a_probe.swift", entry)
    sources = sorted(str(p) for p in (ROOT / "app/Sources").glob("*.swift")
                     if p.name != "main.swift")
    sources.append(str(HERE / "cutout_spike" / "mask_track_writer.swift"))
    binary = out / "co2a-probe"
    try:
        swift_build.build(sources=sources + [str(entry)], output=binary,
                          defines=["FRAMEJOB_DEV_TOOLS"])
    except swift_build.SwiftBuildFailed as error:
        detail = "the probe did not build: " + "; ".join(error.diagnostics[:6])
        for row in ["B0"] + APP_ROWS:
            check(row, False, detail)
        return
    co2a_proof.PROBE = binary
    co2a_proof.WORK = WORK
    built = True
    check("B0", True, f"built {binary.name}")


def owed_rows():
    present = SKEY1.is_dir()
    for row in OWED_ROWS:
        if present:
            check(row, False, f"S-KEY1 exists ({SKEY1}): CO-S1's owed rows and CO-S3 must run "
                  "before E1–E3 (CO-40)")
        else:
            skip(row, OWED[row])


# ---- the app rows ---------------------------------------------------------------------------

class Canvas(co2a_proof.Doc):
    """A 1920 × 1080, 30 fps project on a transparent canvas."""

    def __init__(self, client, name):
        path = WORK / f"{name}.framejob"
        if path.exists():
            shutil.rmtree(path)
        client.call("new_project", path=str(path))
        super().__init__(client, path)
        self.call("set_canvas", width=CW, height=CH, fps=[30, 1], background=[0, 0, 0, 0])
        self.call("save_project")

    def media(self, fixture, tag):
        copy = WORK / "media" / f"{tag}{fixture.suffix}"
        copy.parent.mkdir(parents=True, exist_ok=True)
        if not copy.exists():
            shutil.copyfile(fixture, copy)
        media = self.call("import_media", path=str(copy))["media"]
        duration = next(m for m in self.project()["media"] if m["id"] == media)["duration"]
        return media, copy, duration

    def clip(self, media):
        tracks = self.project()["tracks"]
        if not tracks:
            self.call("add_track")
            tracks = self.project()["tracks"]
        self.call("add_clip", track=tracks[0]["id"], media=media, at=0)
        clip = self.project()["clips"][0]["id"]
        self.call("set_video", clips=[clip], patch={"scale": 1.0, "cutout": {}})
        return clip

    def edge(self, clip, e):
        self.call("set_video", clips=[clip], patch={"cutout": {"edge": e, "feather": 0.0}})

    def alpha(self, t, tag):
        out = WORK / f"{self.path.stem}-{tag}.png"
        if out.exists():
            out.unlink()
        self.call("render_frame", t=t, path=str(out))
        raw = co2a_proof.decode_png(out) if out.exists() else None
        if raw is None or len(raw) != CW * CH * 4:
            raise RuntimeError(f"render_frame at {t} ({tag}) gave no {CW} × {CH} picture")
        return raw[3::4]


def contour(alpha, y):
    """Where row `y`'s alpha first rises through 127.5, linearly between pixel centres; None
    unless it crosses exactly once."""
    row = alpha[y * CW:(y + 1) * CW]
    crossings = [p for p in range(CW - 1) if (row[p] < 127.5) != (row[p + 1] < 127.5)]
    if len(crossings) != 1:
        return None
    p = crossings[0]
    a, b = row[p], row[p + 1]
    return p + 0.5 + (127.5 - a) / (b - a)


def e4(client):
    co2a_proof.barcode_fixtures()
    doc = Canvas(client, "e4")
    try:
        media, copy, duration = doc.media(co2a_proof.BARCODE, "barcode")
        clip = doc.clip(media)
        analysed = co2a_proof.install_pack(doc.path, media, copy, duration, kind="ramp")
        check("E4", len(analysed) == co2a_proof.FRAMES,
              f"the canned ramp pack analysed {len(analysed)} of {co2a_proof.FRAMES} frames")
        found = {}
        for e in EDGES:
            doc.edge(clip, e)
            alpha = doc.alpha(E4_T, f"edge{e:+.1f}")
            xs = [contour(alpha, y) for y in E4_ROWS]
            want = expected_x(e)
            ok = all(x is not None and abs(x - want) <= POSITION_TOLERANCE for x in xs)
            found[e] = xs
            check("E4", ok, f"edge {e:+.1f}: m½ {m_half(e):.3f}, contour X on rows {E4_ROWS} "
                  f"{[None if x is None else round(x, 3) for x in xs]} against "
                  f"{want:.3f} ± {POSITION_TOLERANCE}")
        for (a, b, what) in [(0.0, 1.0, "X(0) − X(1)"), (-1.0, 0.0, "X(−1) − X(0)")]:
            shifts = [None if x is None or z is None else z - x
                      for x, z in zip(found[b], found[a])]
            ok = all(s is not None and abs(s - SHIFT) <= SHIFT_TOLERANCE for s in shifts)
            check("E4", ok, f"{what} on rows {E4_ROWS}: "
                  f"{[None if s is None else round(s, 3) for s in shifts]} against "
                  f"{SHIFT} ± {SHIFT_TOLERANCE} px (3R/8 of 120 px)")
    finally:
        co2a_proof.close(client, doc.path)


def e4r(client):
    push, _ = co2a_proof.person_fixtures()
    doc = Canvas(client, "e4r")
    try:
        media, _, _ = doc.media(push, "push")
        clip = doc.clip(media)
        answer = None
        for _ in range(60):
            try:
                answer = doc.call("get_media_analysis", media=media, kind="masks",
                                  **{"from": 0, "to": 2 * SEC})
                break
            except mcp.ToolError as error:
                if "call again to continue" not in str(error):
                    raise
        if answer is None:
            raise RuntimeError("the masks analysis did not finish in 60 calls")
        check("E4r", answer.get("subject_found") is True,
              f"get_media_analysis over 0–2 s: subject_found {answer.get('subject_found')}, "
              f"{answer.get('frames')} frames, mask_size {answer.get('mask_size')}")
        alphas = {}
        for e in (-1.0, 0.0, 1.0):
            doc.edge(clip, e)
            alphas[e] = doc.alpha(E4R_T, f"edge{e:+.0f}")
        counts = {e: sum(1 for v in a if v >= 128) for e, a in alphas.items()}
        for lower, upper in [(-1.0, 0.0), (0.0, 1.0)]:
            a, b = alphas[lower], alphas[upper]
            worse = sum(1 for i in range(len(a)) if b[i] < a[i] - 1)
            check("E4r", worse == 0,
                  f"edge {upper:+.0f} against {lower:+.0f}: {worse} pixels whose alpha fell by "
                  f"more than one level")
        check("E4r", counts[-1.0] < counts[0.0] < counts[1.0],
              f"pixels with alpha ≥ 128 at edge −1, 0, +1: {counts[-1.0]}, {counts[0.0]}, "
              f"{counts[1.0]} (strictly increasing)")
    finally:
        co2a_proof.close(client, doc.path)


def launch_rows(binary, arguments, log, bodies):
    launched = mcp.launch(str(binary), arguments,
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            for names, _ in bodies:
                for name in names & selected:
                    check(name, False, "the app did not listen")
            return
        print(f"  instance PID {launched.child.pid} ({' '.join(arguments) or 'no flags'})",
              flush=True)
        for names, body in bodies:
            if not names & selected:
                continue
            try:
                body(launched.client)
            except Exception as error:  # noqa: BLE001 — a row's failure, never the run's
                for name in names & selected:
                    check(name, False, f"{type(error).__name__}: {error}")
    finally:
        launched.stop()
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z1", not lines, f"{log.name}: grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")


def app_rows(binary):
    if "E4" in selected:
        launch_rows(binary, CANNED, WORK / "instance.log", [({"E4"}, e4)])
    if "E4r" in selected:
        launch_rows(binary, [], WORK / "instance-real.log", [({"E4r"}, e4r)])


# ---- mutants and main -----------------------------------------------------------------------

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def mutant_app(name):
    made, reason = tree_copy.make_copy(str(WORK.parent / "co4-mutant"))
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
        selected = set(MUTANTS[args.mutant][0])
    elif args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
    if selected & (set(APP_ROWS) - {"Z1"}):
        selected |= {"B0", "Z1"}
    remove_work()
    HOME.mkdir(parents=True)
    binary = Path(args.app) if args.app else None
    before = {}
    if args.mutant:
        print(f"CO4 — the {args.mutant} MUTANT ({', '.join(MUTANTS[args.mutant][0])} must "
              f"FAIL, {proof_app.config()} build)", flush=True)
        before = {p: sha(ROOT / p) for p, _, _ in MUTANTS[args.mutant][1]}
        binary, why = mutant_app(args.mutant)
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
    else:
        print(f"CO4 — the cutout's edges, r0 ({proof_app.config()} build)", flush=True)
    if "B0" in selected:
        probe_row()
    owed_rows()
    if built and selected & set(APP_ROWS):
        binary = binary or proof_app.binary()
        if binary.suffix == ".app":
            binary = proof_app.executable(binary)
        app_rows(binary)
    failed = [name for name, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [name for name in results if name not in failed]
    print(f"\nscores: {len(passed)}/{len(results)}" + (f"; failed {failed}" if failed else ""))
    if args.mutant:
        after = {p: sha(ROOT / p) for p in before}
        restored = before == after
        print(f"the tree's mutated files' SHA-256 unchanged: {restored}")
        named = set(MUTANTS[args.mutant][0])
        caught = bool(named & set(failed)) and restored
        print(f"MUTANT {args.mutant} {'CAUGHT' if caught else 'SURVIVED'}: "
              f"{', '.join(sorted(named))} {'failed' if named & set(failed) else 'passed'}")
        return 0 if caught else 1
    return 0 if not failed and results else 1


if __name__ == "__main__":
    sys.exit(main())
