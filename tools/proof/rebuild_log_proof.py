#!/usr/bin/env python3
"""Road map "creator-jobs" SW0 — the preview's rebuilds counted and timed
(spec §11 SW-1, SW-4): `PlaybackRebuildLog` and the dev tool
`playback_rebuilds {reset?}`, against the built app.

    python3 tools/proof/rebuild_log_proof.py [--only R1,R3] [--app PATH]
    python3 tools/proof/rebuild_log_proof.py --mutant NAME

Each instance runs on a scratch `CFFIXED_USER_HOME` under
`tools/proof/work/rebuild-log/`, launched and stopped by its own PID; nothing
else is killed. The project is one 20 s clip of `analysis_fixtures.h264_1080()`
on one track, made fresh in each instance. "Settled" is `rebuilding` false with
the last entry landed, twice 0.5 s apart (bound 60 s).

R0  every log's `grep "Frame Job: "` prints nothing; `playback_rebuilds` is in
    the catalog with exactly the properties `reset` and `project`; the dev
    marker's count equals `len(dev_tools.DEV_TOOLS)`.
R1  on an unheld instance: the project open and settled, `reset`, one
    `trim_end` to 10 s, settled plus 1 s: exactly one entry (`count` 1), with
    0 < `built_ms` <= `landed_ms`. (`set_clip` would not do: it only names or
    labels a clip, which the plan does not carry, so it never rebuilds.)
R2  then `reset: true` answers `count` 0 and `rebuilds` []; the next
    `trim_end` (to 8 s) gives exactly one landed entry.
R3  on an instance launched with `-RCDevRebuildHold 2`: the project open and
    settled, `reset`, two `trim_end`s (15 s, then 12 s) sent within 0.5 s;
    `rebuilding` false, then 3 s more: `count` 1 and that entry's `built_ms`
    >= 2000 — the first edit's generation, superseded inside the held flight,
    is never an entry.

`--mutant NAME` builds the named break in a tree copy (`tree_copy.py`, the
configuration `RC_PROOF_APP` chooses) and runs only its row and R0; CAUGHT
(exit 0) when that row fails, SURVIVED (exit 1) otherwise, 2 when the control
could not be performed: `built-before-guard` (the entry kept before
`finishRebuild`'s generation guard) → R3; `reset-ignored` (`reset: true` does
nothing) → R2.

Rows print `ok|FAIL <row> <detail>`, then `n/m rows passed`; exit 0 iff every
row passes.
"""

import argparse
import shutil
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
import analysis_fixtures  # noqa: E402
import bounded  # noqa: E402
import dev_tools  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/rebuild-log"
HOME = WORK / "home"
SEC = 600_000
CALL_BOUND = 300
BUILD_BOUND = 1500
ROWS = ["R0", "R1", "R2", "R3"]

PLAYBACK = "app/Sources/Playback.swift"
TOOL = "app/Sources/AgentServer+PlaybackRebuilds.swift"
MUTANTS = {
    "built-before-guard": (["R3"], [
        (PLAYBACK,
         "        guard generation == self.generation else { return }\n",
         "        #if FRAMEJOB_DEV_TOOLS\n"
         "        rebuildLog.built(generation: generation)\n"
         "        #endif\n"
         "        guard generation == self.generation else { return }\n"),
        (PLAYBACK,
         "            #if FRAMEJOB_DEV_TOOLS\n"
         "            rebuildLog.built(generation: generation)\n"
         "            #endif\n"
         "            holding = false\n",
         "            holding = false\n"),
    ]),
    "reset-ignored": (["R2"], [
        (TOOL, "        if reset { log.reset() }\n", "        _ = reset\n"),
    ]),
}

results = {}
selected = set(ROWS)
logs = []


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append(bool(ok))
    print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}", flush=True)


def attempt(body, name):
    try:
        return body()
    except Exception as error:  # noqa: BLE001 — a row's failure, never the run's
        check(name, False, f"{type(error).__name__}: {error}")
        return None


class Doc:
    """One fresh project in one instance: a track and one 20 s clip."""

    def __init__(self, client, name):
        self.client = client
        self.path = WORK / f"{name}.framejob"
        if self.path.exists():
            shutil.rmtree(self.path)
        client.call("new_project", path=str(self.path))
        movie = analysis_fixtures.h264_1080()
        media = self.call("import_media", path=str(movie))["media"]
        tracks = self.call("get_project")["project"]["tracks"]
        if not tracks:
            self.call("add_track")
            tracks = self.call("get_project")["project"]["tracks"]
        self.clip = self.call("add_clip", track=tracks[0]["id"], media=media,
                              at=0)["new_clips"][0]
        self.call("save_project")

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def log(self, reset=False):
        return self.call("playback_rebuilds", **({"reset": True} if reset else {}))

    def settled(self, bound=60):
        """Waits for `rebuilding` false and the last entry landed, seen twice
        0.5 s apart; answers the last reading (or raises at the bound)."""
        deadline = time.monotonic() + bound
        calm = 0
        last = None
        while time.monotonic() < deadline:
            last = self.log()
            rows = last["rebuilds"]
            quiet = not last["rebuilding"] and (not rows or rows[-1]["landed_ms"] is not None)
            calm = calm + 1 if quiet else 0
            if calm >= 2:
                return last
            time.sleep(0.5)
        raise RuntimeError(f"the preview did not settle in {bound} s: {last}")

    def close(self):
        try:
            self.client.call("close_project", project=str(self.path), discard=True)
        except mcp.ToolError:
            pass


def one_landed(reading):
    rows = reading["rebuilds"]
    if reading["count"] != 1 or len(rows) != 1:
        return False
    built, landed = rows[0]["built_ms"], rows[0]["landed_ms"]
    return landed is not None and 0 < built <= landed


def plain_rows(client):
    doc = Doc(client, "plain")
    try:
        first = doc.settled()
        print(f"  the open settled: {first}", flush=True)
        if "R1" in selected:
            def r1():
                doc.log(reset=True)
                doc.call("trim_end", clip=doc.clip, to=10 * SEC)
                doc.settled()
                time.sleep(1)
                reading = doc.log()
                check("R1", one_landed(reading),
                      f"after one trim_end: {reading} (want count 1, one entry, "
                      f"0 < built_ms <= landed_ms)")
            attempt(r1, "R1")
        if "R2" in selected:
            def r2():
                emptied = doc.log(reset=True)
                doc.call("trim_end", clip=doc.clip, to=8 * SEC)
                doc.settled()
                time.sleep(1)
                reading = doc.log()
                ok = (emptied["count"] == 0 and emptied["rebuilds"] == []
                      and one_landed(reading))
                check("R2", ok,
                      f"reset: true answered {emptied} (want count 0, []); the next trim_end "
                      f"{reading} (want one landed entry)")
            attempt(r2, "R2")
    finally:
        doc.close()


def held_row(client):
    doc = Doc(client, "held")
    try:
        doc.settled()
        doc.log(reset=True)
        sent = time.monotonic()
        doc.call("trim_end", clip=doc.clip, to=15 * SEC)
        doc.call("trim_end", clip=doc.clip, to=12 * SEC)
        within = time.monotonic() - sent
        deadline = time.monotonic() + 60
        while doc.log()["rebuilding"] and time.monotonic() < deadline:
            time.sleep(0.1)
        time.sleep(3)
        reading = doc.log()
        rows = reading["rebuilds"]
        ok = (within <= 0.5 and reading["count"] == 1 and len(rows) == 1
              and rows[0]["built_ms"] >= 2000)
        check("R3", ok,
              f"two trim_ends sent {within:.2f} s apart (want <= 0.5) under "
              f"-RCDevRebuildHold 2: {reading} (want count 1 and built_ms >= 2000)")
    finally:
        doc.close()


def launch(binary, arguments, name):
    log = WORK / f"{name}.log"
    logs.append(log)
    launched = mcp.launch(str(binary), list(arguments),
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    return launched, log


def catalog_row(client, log):
    schema = client.schemas().get("playback_rebuilds")
    props = sorted((schema or {}).get("inputSchema", {}).get("properties", {}))
    count = dev_tools.dev_marker_count(str(log))
    check("R0", schema is not None and props == ["project", "reset"]
          and count == len(dev_tools.DEV_TOOLS),
          f"playback_rebuilds {'in' if schema else 'NOT in'} the catalog, properties {props} "
          f"(want ['project', 'reset']); the dev marker counts {count} "
          f"(want {len(dev_tools.DEV_TOOLS)})")


def app_rows(binary):
    plain = selected & {"R0", "R1", "R2"}
    if plain:
        launched, log = launch(binary, [], "instance")
        try:
            if launched.client is None:
                for row in plain:
                    check(row, False, "the app did not listen")
            else:
                print(f"  instance PID {launched.child.pid}", flush=True)
                if "R0" in selected:
                    attempt(lambda: catalog_row(launched.client, log), "R0")
                if selected & {"R1", "R2"}:
                    plain_rows(launched.client)
        finally:
            launched.stop()
    if "R3" in selected:
        launched, _ = launch(binary, ["-RCDevRebuildHold", "2"], "instance-held")
        try:
            if launched.client is None:
                check("R3", False, "the held app did not listen")
            else:
                print(f"  held instance PID {launched.child.pid}", flush=True)
                attempt(lambda: held_row(launched.client), "R3")
        finally:
            launched.stop()
    if "R0" in selected:
        found = []
        for log in logs:
            try:
                found += [line.strip() for line in open(log, errors="replace")
                          if "Frame Job: " in line]
            except OSError:
                found.append(f"{log} could not be read")
        check("R0", not found,
              f"grep 'Frame Job: ' over {[log.name for log in logs]} printed "
              f"{found[:3] or 'nothing'}")


def mutant_app(name):
    made, reason = tree_copy.make_copy(str(WORK.parent / "rebuild-log-mutant"))
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
        selected = set(MUTANTS[args.mutant][0]) | {"R0"}
    elif args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))
    HOME.mkdir(parents=True)
    binary = Path(args.app) if args.app else None
    if args.mutant:
        named = MUTANTS[args.mutant][0]
        print(f"SW0 — the {args.mutant} MUTANT ({', '.join(named)} must FAIL)", flush=True)
        binary, why = mutant_app(args.mutant)
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
    else:
        print(f"SW0 — the rebuild log ({proof_app.config()} build)", flush=True)
    if binary is None:
        binary = proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    app_rows(binary)
    failed = [name for name, runs in results.items() if not all(runs)]
    passed = [name for name in results if name not in failed]
    print(f"\n{len(passed)}/{len(results)} rows passed" + (f"; failed {failed}" if failed else ""))
    if args.mutant:
        named = set(MUTANTS[args.mutant][0])
        caught = bool(named & set(failed))
        print(f"MUTANT {args.mutant} {'CAUGHT' if caught else 'SURVIVED'}: "
              f"{', '.join(sorted(named))} {'failed' if caught else 'passed'}")
        return 0 if caught else 1
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
