#!/usr/bin/env python3
"""Issue #367 — many media cache passes in flight must not wedge every
`AVAssetReader` in the process: the cache lane (`MediaImporter.CacheLane`,
`app/Sources/MediaCacheLane.swift`, spec §11 #367) runs the peaks, sync and
speech decodes at most two at a time, FIFO, on its own queue, so a ramp render
keeps reading while any number of passes wait.

    env -u RC_ASSEMBLYAI_KEY python3 tools/proof/reader_wedge_proof.py
        [--groups probe,app] [--app PATH] [--mutant NAME]

The work folder is `tools/proof/work/reader-wedge/` (untracked): `probe/`
(the probe builds and their source copies), `packages/` (P1's packages),
`docs/` (W1's document), `framejob.log`, `sample-W1.txt` and the mutants'
tree copies under `mutant-<name>/`. The long fixtures are #334's, shared
through `constant_render_spike.make_long` in
`tools/proof/work/constant-render/fixtures/`.

probe  (no app) `cache_lane_probe.swift` built over `app/Sources` through
       `swift_build.build`. B0 the probe builds (a failure is a scored FAIL).
       L1 40 bodies of 20 ms submitted from 40 threads: at most exactly 2 ran
       at once. L2 40 bodies from one thread start within 1 of their
       submission index. L3 L1's 40 bodies all finish within 10 s. L4 a body
       through `MediaImporter.onCacheLane` from a `Task.detached` runs on the
       queue labelled `CacheLane.label`. C1 (reported, plain runs only, when
       the long fixtures can be made) 30 s of `long-sine` read on a GCD queue
       alone, then again while one blocking task per core holds the Swift
       cooperative pool: whether the GCD read stalls.
app    one owned instance (`mcp.launch`, stopped by its pid). F0 the long
       fixtures exist and are 48 kHz. P1 the spike's 20 W packages
       (`constant_render_spike.w_package`, `SETTLE` off), each saved and closed
       with no wait for its cache pass. W1 (scored) a fresh document: a 60 s
       long-sine clip (`long_clip`, settle off), an action over the whole
       clip, `set_action_end {speed: 2}`; a `.caf` lands in
       `cache/ramp-audio/` within W1_BOUND_S. W2 (scored, plain runs only)
       every P1 package holds `cache/{peaks,sync,speech}/<media>.complete.json`
       within W2_BOUND_S of W1's end. S0 (reported, only when W1 fails)
       `sample <pid> 5`, and the count of its lines naming each WEDGE_TOKENS
       entry. D0 the instance listened and its log holds no `Frame Job: `
       line. The group is Release-only (RELEASE_ONLY, spec §11 V-4): W1 and
       W2 bound decode work in wall seconds, and a Debug decode runs about 17×
       slower (≈ 17.5 s for one 250 s pass against ≈ 1 s on Release).

Mutants. Probe mutants are source copies (`cache_pass_probe.mutate`'s
shape) and run B0 and their row: `wide` (width 64; L1), `lifo` (the pending
list taken from its end; L2), `slot-leak` (the running count never
decremented; L3), `inline` (the body run on the submitting thread; L4). App
mutants are tree copies built by `tree_copy.build_app` (`RC_PROOF_APP`
chooses the configuration, held to Release by RELEASE_ONLY) and run F0, D0,
P1 and W1. The scored app mutant is `no-lane` (the three `onCacheLane`
call sites back to direct calls), which takes away both of the lane's guards
at once. Each guard alone keeps W1 landing on this 12-core host (spec §11
#367), so the two single-guard mutants are EXPECTED_SURVIVORS, runnable but
not scored: `unbounded` (width 64, guard 1 kept: off the pool; Release W1
1.61 s) and `app-inline` (width 2 kept, the body run on the submitting
cooperative-pool thread as the probe's `inline`; Release W1 1.37 s). The
probe mutants `wide` and `inline` score each guard on its own. Each anchor
is an exact `(file, before, after)` found exactly once.

Exit (rule R, `cache_pass_probe.py`'s): a plain run exits 0 when every
scored row passes, 1 when one fails, 2 when not performed (no ffmpeg or
ffprobe for the app group, no built app, a stale app). A mutant run exits 1
when its row failed (caught), 0 when it passed (survived), 2 when the control
was not performed (an anchor not found once, the copy did not build, F0, D0
or P1 failed, or the row was not scored).
"""

import argparse
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof"))
import constant_render_spike as crs  # noqa: E402  (puts ramp_proof's paths in place)
import ramp_proof as rp  # noqa: E402
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/reader-wedge"
PACKAGES = WORK / "packages"
DOCS = WORK / "docs"
LOG = WORK / "framejob.log"
SAMPLE = WORK / "sample-W1.txt"
PROBE_SOURCE = ROOT / "tools/proof/cache_lane_probe.swift"
SOURCES = ROOT / "app/Sources"

SEC = crs.SEC
W1_LENGTH = 60 * SEC
W1_BOUND_S = 120
W2_BOUND_S = 180
CALL_BOUND = 300
PROBE_WALL = 180
SAMPLE_BOUND_S = 60
KINDS = ("peaks", "sync", "speech")
GROUPS = ["probe", "app"]
WEDGE_TOKENS = ("copyNextSampleBuffer", "generateCaches", "RampSourceReader",
                "readerOfflineMixer", "audioqueue.source", "cooperative")

RELEASE_ONLY = ("W1 and W2 bound decode work in wall seconds, and a Debug decode runs "
                "about 17x slower (17.5 s a pass)")

WIDTH = ("MediaCacheLane.swift", "static let width = 2", "static let width = 64")
INLINE = ("MediaCacheLane.swift", "queue.async(execute: run)", "run()")

# name: (group, the row it must fail, [(file, before, after), ...])
MUTANTS = {
    "wide": ("probe", "L1", [WIDTH]),
    "lifo": ("probe", "L2", [
        ("MediaCacheLane.swift", "return pending.removeFirst()", "return pending.removeLast()")]),
    "slot-leak": ("probe", "L3", [
        ("MediaCacheLane.swift", "running -= 1", "_ = running")]),
    "inline": ("probe", "L4", [INLINE]),
    "no-lane": ("app", "W1", [
        ("MediaImporter.swift",
         "return await onCacheLane {\n"
         "            writePeaks(for: media, asset: asset, track: track, expectedRanges: expected,\n"
         "                       stamp: stamp, into: cacheDir, pass: pass)\n"
         "        }",
         "return writePeaks(for: media, asset: asset, track: track, expectedRanges: expected,\n"
         "                       stamp: stamp, into: cacheDir, pass: pass)"),
        ("MediaImporter.swift",
         "await onCacheLane {\n"
         "            writeSyncFeatures(for: media, asset: asset, track: track, stamp: stamp,\n"
         "                              into: cacheDir, pass: pass)\n"
         "        }",
         "writeSyncFeatures(for: media, asset: asset, track: track, stamp: stamp,\n"
         "                              into: cacheDir, pass: pass)"),
        ("MediaImporter.swift",
         "await onCacheLane {\n"
         "            writeSpeech(for: media, asset: asset, track: track, stamp: stamp,\n"
         "                        into: cacheDir, pass: pass)\n"
         "        }",
         "writeSpeech(for: media, asset: asset, track: track, stamp: stamp,\n"
         "                        into: cacheDir, pass: pass)")]),
    "unbounded": ("app", "W1", [WIDTH]),
    "app-inline": ("app", "W1", [INLINE]),
}

# Single-guard app mutants: each guard alone keeps W1 landing, so these survive
# by design (spec §11 #367) and are not scored. name: the recorded Release run.
EXPECTED_SURVIVORS = {
    "unbounded": "W1 1.61 s on Release (off the pool at width 64)",
    "app-inline": "W1 1.37 s on Release (on the pool at width 2)",
}


class Run:
    def __init__(self):
        self.rows = {}           # name → (status, detail); status ok, FAIL or reported
        self.not_performed = []

    def row(self, name, status, detail):
        self.rows[name] = (status, detail)
        print(f"{name} {status} — {detail}", flush=True)

    def failed(self, name):
        return self.rows.get(name, ("FAIL",))[0] == "FAIL"


def apply_edits(root, edits):
    """Each `before` replaced once under `root`; None, or why the control
    could not be performed."""
    for file, before, after in edits:
        path = Path(root) / file
        text = path.read_text() if path.exists() else ""
        if text.count(before) != 1:
            return f"{file}: `{before.splitlines()[0]}…` found {text.count(before)} times"
        path.write_text(text.replace(before, after))
    return None


# ---- the probe group --------------------------------------------------------------


def build_probe(sources, here):
    """(binary, None) or (None, why): `swift_build.build` over `sources`."""
    entry = here / "main.swift"
    shutil.copyfile(PROBE_SOURCE, entry)
    binary = here / "cache-lane-probe"
    swift = sorted(str(p) for p in Path(sources).glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    try:
        swift_build.build(sources=swift + [entry], output=binary)
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + "; ".join(error.diagnostics[:8])
    return binary, None


def probe_group(run, mutant):
    """B0 and L1–L4 (a mutant: B0 and its row). False when a mutant's control
    could not be performed."""
    here = WORK / "probe" / (f"mutant-{mutant}" if mutant else "tree")
    shutil.rmtree(here, ignore_errors=True)
    here.mkdir(parents=True)
    sources = SOURCES
    if mutant:
        shutil.copytree(SOURCES, here / "Sources")
        why = apply_edits(here / "Sources", MUTANTS[mutant][2])
        if why:
            run.not_performed.append(f"mutant {mutant}: {why}")
            return False
        sources = here / "Sources"
    binary, why = build_probe(sources, here)
    run.row("B0", "ok" if binary else "FAIL", why or f"built from {sources}")
    arguments, c1_why = [], None
    if binary and not mutant:
        try:
            crs.make_long()
            arguments = [str(crs.LONG["sine"])]
        except Exception as error:  # C1 is reported only; no fixture, no measurement
            c1_why = f"not measured: no long fixture ({type(error).__name__}: {error})"
    wanted = [MUTANTS[mutant][1]] if mutant else ["L1", "L2", "L3", "L4"]
    if binary is None:
        for name in wanted:
            run.row(name, "FAIL", "not run: the probe did not build")
        if mutant:
            run.not_performed.append(f"mutant {mutant}: the copy did not build")
        return not mutant
    answered, why = {}, None
    try:
        done = subprocess.run([str(binary)] + arguments, capture_output=True, text=True,
                              timeout=PROBE_WALL)
        (here / "stderr.txt").write_text(done.stderr)
        answered = {r["id"]: r for r in json.loads(done.stdout)["rows"]}
    except subprocess.TimeoutExpired:
        why = f"no answer within {PROBE_WALL} s"
    except (ValueError, KeyError) as error:
        why = f"no answer: {error}"
    for name in wanted:
        got = answered.get(name)
        if got is None:
            run.row(name, "FAIL", f"not scored: {why or 'the probe did not answer it'}")
            if mutant:
                run.not_performed.append(f"mutant {mutant}: {name} not scored")
        else:
            run.row(name, "ok" if got["pass"] else "FAIL", got["detail"])
    if not mutant:
        got = answered.get("C1")
        run.row("C1", "reported", got["detail"] if got else (c1_why or f"not measured: {why}"))
    return True


# ---- the app group ----------------------------------------------------------------


def f0(run):
    problems, parts = [], []
    try:
        crs.make_long()
        for media in crs.MEDIA:
            rate, channels, duration = crs.probe_stream(crs.LONG[media])
            parts.append(f"{media} {rate} Hz {channels} ch {duration:.3f} s")
            if rate != crs.HZ:
                problems.append(f"{media}: {rate} Hz")
    except Exception as error:  # a broken instrument is a FAIL
        problems.append(f"{type(error).__name__}: {error}")
    run.row("F0", "FAIL" if problems else "ok", "; ".join(problems or parts))
    return not problems


def media_id(package):
    project = json.loads((Path(package) / "project.json").read_text())
    return project["media"][0]["id"]


def p1(run, client):
    """The 20 W packages, none waiting for its cache pass: [(package, media id)]."""
    made, errors = [], []
    started = time.monotonic()
    for media in crs.MEDIA:
        for rate in list(crs.RATES) + [None]:
            for length_s in crs.WINDOW_S:
                try:
                    _, got = crs.w_package(client, media, rate, length_s, folder=PACKAGES)
                    made.append((got["package"], media_id(got["package"])))
                except Exception as error:  # an instrument that breaks is a FAIL
                    errors.append(f"W {media} {rate} {length_s}: {type(error).__name__}: {error}")
    want = len(crs.MEDIA) * (len(crs.RATES) + 1) * len(crs.WINDOW_S)
    ok = not errors and len(made) == want
    run.row("P1", "ok" if ok else "FAIL",
            f"{len(made)} of {want} packages saved and closed in "
            f"{time.monotonic() - started:.1f} s, none waiting for its pass"
            + (f"; {'; '.join(errors[:4])}" if errors else ""))
    return made, ok


def w1(run, client):
    """The ramp render with every P1 pass in flight: (landed, the monotonic
    time W1 ended)."""
    doc = crs.new_doc(client, DOCS, "W1")
    try:
        clip, _ = crs.long_clip(doc, crs.LONG["sine"], W1_LENGTH, 1.0)
        action = doc.action(clip, 0, W1_LENGTH)
        started = time.monotonic()
        rp.ramp_end(doc, clip, action, speed=2)
        landed = []
        while time.monotonic() - started < W1_BOUND_S:
            landed = [n for n in doc.renders() if n.endswith(".caf")]
            if landed:
                break
            time.sleep(0.05)
        seconds = time.monotonic() - started
        if landed:
            run.row("W1", "ok", f"the ramp's .caf landed {seconds:.2f} s after the edit "
                    f"(bound {W1_BOUND_S} s): {landed[0]}")
        else:
            run.row("W1", "FAIL", f"no .caf within {W1_BOUND_S} s; ramp-audio holds "
                    f"{doc.renders()}")
        return bool(landed), time.monotonic()
    except Exception as error:  # an instrument that breaks is a FAIL
        run.row("W1", "FAIL", f"{type(error).__name__}: {error}")
        return False, time.monotonic()
    finally:
        doc.close()


def w2(run, packages, ended):
    """Every P1 package's three markers within W2_BOUND_S of W1's end."""
    def missing():
        out = {kind: 0 for kind in KINDS}
        for package, media in packages:
            for kind in KINDS:
                if not (Path(package) / "cache" / kind / f"{media}.complete.json").exists():
                    out[kind] += 1
        return out

    while True:
        gone = missing()
        if not any(gone.values()) or time.monotonic() - ended >= W2_BOUND_S:
            break
        time.sleep(0.25)
    took = time.monotonic() - ended
    want = len(packages) * len(KINDS)
    have = want - sum(gone.values())
    ok = not any(gone.values()) and len(packages) == 20
    run.row("W2", "ok" if ok else "FAIL",
            f"{have} of {want} markers {took:.1f} s after W1 ended (bound {W2_BOUND_S} s); "
            f"missing per kind {gone}")


def s0(run, pid):
    """`sample <pid> 5`, and the count of lines naming each wedge token."""
    SAMPLE.unlink(missing_ok=True)
    done = bounded.run(["sample", str(pid), "5", "-file", str(SAMPLE)], SAMPLE_BOUND_S)
    try:
        lines = SAMPLE.read_text(errors="replace").splitlines()
    except OSError as error:
        run.row("S0", "reported", f"no sample (rc {done['rc']}, expired {done['expired']}): "
                f"{error}")
        return
    counts = {token: sum(1 for line in lines if token in line) for token in WEDGE_TOKENS}
    run.row("S0", "reported", f"{SAMPLE}: {len(lines)} lines; {counts}")


def app_group(run, binary, plain):
    """F0, P1, W1, W2 (plain runs only), S0 on a W1 failure, D0. False when
    the group was not performed."""
    if not f0(run):
        return True
    for folder in (PACKAGES, DOCS):
        tree_copy.remove_tree(str(folder))
    LOG.unlink(missing_ok=True)
    crs.SETTLE = False
    rp.EXPORTS = WORK / "exports"
    try:
        launched = mcp.launch(str(binary), env=bounded.child_env(), log_path=str(LOG),
                              timeout=CALL_BOUND)
    except proof_app.StaleApp as error:
        run.not_performed.append(f"app: {error}")
        return False
    up = launched.client is not None
    try:
        if up:
            client = launched.client
            print(f"  instance PID {launched.child.pid} at {launched.socket_path}", flush=True)
            packages, _ = p1(run, client)
            landed, ended = w1(run, client)
            if not landed:
                s0(run, launched.child.pid)
            if plain:
                w2(run, packages, ended)
        else:
            for name in ("P1", "W1") + (("W2",) if plain else ()):
                run.row(name, "FAIL", f"not run: the app did not listen at {launched.socket_path}")
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    found = rp.complaints(LOG)
    run.row("D0", "ok" if up and not found else "FAIL",
            f"listening {up}; complaints {found[:5]}")
    return True


def build_mutant_app(name):
    """A tree copy with the mutant's anchors replaced once, built by its own
    `tree_copy.build_app`: (binary, None) or (None, why)."""
    tree = WORK / f"mutant-{name}" / "tree"
    made, reason = tree_copy.make_copy(str(tree))
    if made is None:
        return None, reason
    why = apply_edits(Path(made) / "app/Sources", MUTANTS[name][2])
    if why:
        return None, why
    print(f"  mutant {name}: building {made}", flush=True)
    app, reason = tree_copy.build_app(made, 1500, release_only=RELEASE_ONLY)
    if app is None:
        return None, reason
    return proof_app.executable(app), None


def unregister(name):
    """`lsregister -u` on a mutant copy's built app, when there is one."""
    tree_copy.unregister_apps(str(WORK / f"mutant-{name}" / "tree"))


# ---- main -------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--groups", default=",".join(GROUPS))
    parser.add_argument("--app", type=Path, default=None)
    parser.add_argument("--mutant", choices=sorted(MUTANTS), default=None)
    args = parser.parse_args()
    mutant = args.mutant
    chosen = ([MUTANTS[mutant][0]] if mutant
              else [g for g in GROUPS if g in args.groups.split(",")])
    WORK.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    run = Run()
    print(f"#367 reader wedge — groups {chosen}"
          + (f", mutant {mutant} ({MUTANTS[mutant][1]} must FAIL)" if mutant else ""), flush=True)

    if "app" in chosen and not all(shutil.which(t) for t in ("ffmpeg", "ffprobe")):
        print("not performed: ffmpeg and ffprobe are needed")
        return 2
    binary = None
    if "app" in chosen and not mutant:
        binary = args.app or proof_app.binary(release_only=RELEASE_ONLY)
        if not Path(binary).exists():
            print(f"not performed: the app is not built: {binary}")
            return 2

    try:
        if "probe" in chosen:
            print("-- probe", flush=True)
            probe_group(run, mutant)
        if "app" in chosen:
            print("-- app", flush=True)
            if mutant:
                binary, why = build_mutant_app(mutant)
                if binary is None:
                    run.not_performed.append(f"mutant {mutant}: {why}")
            if binary is not None:
                app_group(run, binary, plain=not mutant)
    except Exception as error:  # a broken instrument is a FAIL, not an exit
        run.row("G", "FAIL", f"{type(error).__name__}: {error}")
    finally:
        if mutant and MUTANTS[mutant][0] == "app":
            unregister(mutant)

    print("\n| row | status |")
    print("|---|---|")
    for name, (status, _) in run.rows.items():
        print(f"| {name} | {status} |")
    failed = [name for name, (status, _) in run.rows.items() if status == "FAIL"]
    print(f"{len(run.rows)} rows in {time.monotonic() - started:.0f} s; failed {failed}; "
          f"not performed {run.not_performed}")
    if not mutant:
        if run.not_performed:
            return 2
        return 1 if failed else 0
    named = MUTANTS[mutant][1]
    controls = ["B0"] if MUTANTS[mutant][0] == "probe" else ["F0", "D0", "P1"]
    lost = [c for c in controls if run.failed(c)]
    if run.not_performed or lost or named not in run.rows:
        print(f"mutant {mutant}: the control could not be performed — "
              f"{run.not_performed or lost or [named + ' not scored']}")
        return 2
    if run.failed(named):
        print(f"mutant {mutant}: caught — {named} failed")
        return 1
    print(f"mutant {mutant}: SURVIVED — {named} passed")
    if mutant in EXPECTED_SURVIVORS:
        print(f"mutant {mutant}: an expected survivor, not scored (spec §11 #367; "
              f"recorded {EXPECTED_SURVIVORS[mutant]})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
