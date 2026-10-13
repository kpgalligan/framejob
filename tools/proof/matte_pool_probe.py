#!/usr/bin/env python3
"""Issue batch B90 phase 3 (#253; spec §11 MT-9) — the matte pool reuses a
composite within a frame and keeps what the renderer's last 30 frames held.

    python3 tools/proof/matte_pool_probe.py
    python3 tools/proof/matte_pool_probe.py --mutant NAME

`matte_pool_probe.swift` is built as `main.swift` over every other file in
`app/Sources` through `swift_build.build` (reused when every input is
byte-identical), in `tools/proof/work/matte_pool_probe/`, and asks the app's
own `MattePlan` and `MattePool` (`Compositor+Matte.swift`) what they answer.
No app is launched, no shader or metallib is built, and nothing is written
outside the work folder; the probe binary has no bundle id and sets no
default. **A build failure is a scored FAILURE (B0), never an exit.**

- **B0**: the probe builds over `app/Sources`.
- **P1**, plans (`MattePlan(groups:cuts:)`):
  - groups 0–9, each cut by its own set [[0]]…[[9]]: each step resolves its
    own set and gives its own composite back, so one composite is live and
    ten coverages are resolved; the bytes that holds at 3840×2160 are printed
    beside MT-6's pool (ten composites and ten coverages);
  - [0, 1] with [[0, 1]]: step 0 resolves nothing and gives nothing back,
    step 1 resolves the set and gives both back: two live, one coverage;
  - [0, 1] with [[0], [1]]: one live, two coverages;
  - [0] with [[7]] (a set naming a group no step draws): no coverage, and
    group 0 given back at step 0.
- **P2**, a pool on the real device at 64×64:
  - take, give, take returns the same texture (`===`), and two takes without
    a give return two;
  - frame 1 holds 3 composites and coverages 0–1, then frames that use
    nothing: `held` is (3, 2) after frame 30's `endFrame` and (0, 0) after
    frame 31's;
  - a fresh pool used (1, 1) at frame 20 alone holds (1, 1) after frame 49
    and (0, 0) after frame 50.
- **P3**: a new destination size empties the pool, and the targets taken
  after it are that size.

`--mutant NAME` builds the probe over a COPY of one Swift file with one
anchor replaced (asserted to occur exactly once), in place of the tree's,
into its own folder, and runs every row:
  no-release     (`MattePlan.swift`) no step gives a composite back: P1
  give-ignored   (`Compositor+Matte.swift`) `giveComposite` frees nothing: P2
  trim-never     (`Compositor+Matte.swift`) `endFrame` releases nothing: P2
  trim-early     (`Compositor+Matte.swift`) the window is `keepFrames − 1`
                 frames: P2
(`matte_proof.py`'s `free-ignores-liveness` and `early-resolve` edit
`MattePlan.swift` too, and are scored by its N5 against the app.)
Rule R: exit 0 = every named row FAILED (caught), 1 = one passed (survived),
2 = the control could not be performed (B0 failed). A plain run exits 0 iff
every scored row passed.
"""

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import swift_build  # noqa: E402

WORK = ROOT / "tools/proof/work/matte_pool_probe"
PROBE_SOURCE = ROOT / "tools/proof/matte_pool_probe.swift"
UHD = 3840 * 2160
# name: (file under app/Sources, anchor, replacement, the rows that must fail)
MUTANTS = {
    "no-release": (
        "MattePlan.swift",
        "            if let last = lastRead[group] { releases[last].append(group) }\n",
        "            if let last = lastRead[group] { _ = last }\n", ["P1"]),
    "give-ignored": (
        "Compositor+Matte.swift",
        "        taken[index] = false\n",
        "        _ = index\n", ["P2"]),
    "trim-never": (
        "Compositor+Matte.swift",
        "        if list.count > count { list.removeLast(list.count - count) }\n",
        "        _ = (list, count)\n", ["P2"]),
    "trim-early": (
        "Compositor+Matte.swift",
        "        let window = MattePool.keepFrames\n",
        "        let window = MattePool.keepFrames - 1\n", ["P2"]),
}
rows = {}


def check(name, good, detail=""):
    key = name.split()[0]
    rows[key] = rows.get(key, True) and bool(good)
    print(("  ok   " if good else "  FAIL ") + name + (f"\n       {detail}" if detail else ""),
          flush=True)


def build(mutant):
    """The probe binary, over the tree's sources or over the mutant's copy of
    one file. (binary, "") or (None, why)."""
    built_dir = WORK / ("probe" if not mutant else f"mutant/{mutant}")
    built_dir.mkdir(parents=True, exist_ok=True)
    entry = built_dir / "main.swift"
    if not entry.exists() or entry.read_text() != PROBE_SOURCE.read_text():
        entry.write_text(PROBE_SOURCE.read_text())
    sources = swift_build.app_sources()
    if mutant:
        name, anchor, replacement, _ = MUTANTS[mutant]
        original = ROOT / "app/Sources" / name
        text = original.read_text()
        if text.count(anchor) != 1:
            return None, f"the mutant's anchor occurs {text.count(anchor)} times in {name}"
        copy_dir = built_dir / "sources"
        copy_dir.mkdir(exist_ok=True)
        copy = copy_dir / name
        mutated = text.replace(anchor, replacement)
        if not copy.exists() or copy.read_text() != mutated:
            copy.write_text(mutated)
        sources = [s for s in sources if s.name != name] + [copy]
    binary = built_dir / "matte_pool_probe"
    try:
        made = swift_build.build(sources=sources + [entry], output=binary,
                                 defines=["FRAMEJOB_DEV_TOOLS"], timeout=900)
    except swift_build.SwiftBuildFailed as error:
        return None, (f"swiftc rc {error.rc if error.rc is not None else 'before running'}: "
                      f"{(error.diagnostics or ['(no output)'])[:6]}")
    print(f"  probe: {'up to date' if made.reused else f'built in {made.seconds:.0f} s'} — "
          f"{binary}", flush=True)
    return binary, ""


def plan(answer, tag):
    for row in (answer or {}).get("plans", []):
        if row.get("tag") == tag:
            return row
    return None


def described(row):
    if row is None:
        return "no answer"
    steps = "; ".join(f"g{s['group']} resolve {s['resolve']} release {s['release']}"
                      for s in row["steps"])
    return (f"groups {row['groups']} cuts {row['cuts']}: live {row['composites_live']}, "
            f"coverages {row['coverages']} — {steps}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    named = MUTANTS[args.mutant][3] if args.mutant else []
    print("B90 phase 3 — the matte pool probe (spec §11 MT-9)"
          + (f", the {args.mutant} MUTANT ({' '.join(named)} must FAIL)" if args.mutant else ""),
          flush=True)
    WORK.mkdir(parents=True, exist_ok=True)
    binary, why = build(args.mutant)
    check("B0 the probe builds over app/Sources", binary is not None, why or str(binary))
    answer = None
    if binary is not None:
        out = binary.parent / "answer.json"
        if out.exists():
            out.unlink()
        ran = bounded.run([str(binary), str(out)], 300)
        if out.exists():
            answer = json.loads(out.read_text())
        else:
            print(f"  the probe wrote no answer: rc {ran['rc']} expired {ran['expired']} "
                  f"{(ran['stdout'] + ran['stderr'])[-400:]}", flush=True)

    ten = plan(answer, "ten")
    ok = (ten is not None and ten["composites_live"] == 1 and ten["coverages"] == 10
          and all(s["resolve"] == [[s["group"]]] and s["release"] == [s["group"]]
                  for s in ten["steps"]))
    if ten is not None:
        pooled = ten["composites_live"] * UHD * 4 + ten["coverages"] * UHD
        before = 10 * UHD * 4 + 10 * UHD
        print(f"       at 3840x2160: {pooled:,} B held, where MT-6's pool held {before:,} B",
              flush=True)
    check("P1 ten mattes each cutting its own set: one composite live, ten coverages", ok,
          described(ten))
    shared = plan(answer, "shared")
    ok = (shared is not None and shared["composites_live"] == 2 and shared["coverages"] == 1
          and [(s["resolve"], s["release"]) for s in shared["steps"]]
          == [([], []), ([[0, 1]], [0, 1])])
    check("P1 two mattes in one set: step 0 resolves nothing, two live, one coverage", ok,
          described(shared))
    separate = plan(answer, "separate")
    ok = (separate is not None and separate["composites_live"] == 1
          and separate["coverages"] == 2)
    check("P1 two mattes in two sets: one live, two coverages", ok, described(separate))
    unlisted = plan(answer, "unlisted")
    ok = (unlisted is not None and unlisted["coverages"] == 0
          and [s["release"] for s in unlisted["steps"]] == [[0]]
          and [s["resolve"] for s in unlisted["steps"]] == [[]])
    check("P1 a set naming an undrawn group: no coverage, group 0 given back at step 0", ok,
          described(unlisted))

    pool = (answer or {}).get("pool") or {"error": "no answer"}
    if "error" in pool:
        check("P2 the pool on the device", False, pool["error"])
        check("P3 a new size", False, pool["error"])
    else:
        print(f"       device: {pool.get('device')}", flush=True)
        check("P2 take, give, take is the same texture; two takes are two",
              pool.get("take_give_take_same") is True and pool.get("two_takes_distinct") is True,
              f"same {pool.get('take_give_take_same')}, distinct "
              f"{pool.get('two_takes_distinct')}")
        a = pool.get("window_from_1") or {}
        check("P2 used (3, 2) at frame 1: held (3, 2) after frame 30, (0, 0) after frame 31",
              a.get("1") == [3, 2] and a.get("30") == [3, 2] and a.get("31") == [0, 0],
              f"after frame 1 {a.get('1')}, 29 {a.get('29')}, 30 {a.get('30')}, "
              f"31 {a.get('31')}")
        b = pool.get("window_from_20") or {}
        check("P2 used (1, 1) at frame 20: held (1, 1) after frame 49, (0, 0) after frame 50",
              b.get("19") == [0, 0] and b.get("20") == [1, 1] and b.get("49") == [1, 1]
              and b.get("50") == [0, 0],
              f"after frame 19 {b.get('19')}, 20 {b.get('20')}, 49 {b.get('49')}, "
              f"50 {b.get('50')}")
        r = pool.get("resize") or {}
        check("P3 a new size empties the pool and makes targets of that size",
              r.get("before") == [1, 1] and r.get("after_begin") == [0, 0]
              and r.get("old_size") == [64, 64] and r.get("composite_size") == [32, 16]
              and r.get("coverage_size") == [32, 16] and r.get("composite_is_new") is True,
              json.dumps(r, sort_keys=True))

    scored = ["B0", "P1", "P2", "P3"]
    passed = sum(1 for name in scored if rows.get(name))
    print(f"{passed}/{len(scored)}")
    if args.mutant:
        if not rows.get("B0"):
            print(f"mutant {args.mutant}: the control could not be performed")
            return 2
        survived = [name for name in named if rows.get(name)]
        print(f"{'MUTANT PASS' if not survived else 'MUTANT FAILURE'}: {args.mutant} — "
              f"{' '.join(named)} {'all FAILED' if not survived else 'did not all fail'}")
        return 0 if not survived else 1
    return 0 if passed == len(scored) else 1


if __name__ == "__main__":
    sys.exit(main())
