#!/usr/bin/env python3
"""Road map 10 G0 — the graphics spike (archive/reelcut-roadmap-10.md §3).

Nine rows, run in the order q2, q8, q3, q4, q5, q6, q1, q9, q7: q1 and q9
patch and rebuild the core and are REVERTED before q7, which launches the
app built from the reverted tree. Every child is bounded (`bounded.py`).
The answers go to tools/proof/work/graphics_spike/answers.json; nothing
here is a pass or a fail except an instrument that did not run.

    python3 tools/proof/graphics_spike/graphics_spike.py                 # all nine
    python3 tools/proof/graphics_spike/graphics_spike.py --only q4,q5    # a subset; the rest carry forward
    python3 tools/proof/graphics_spike/graphics_spike.py --only q5 --mutant   # the on-purpose failure
    python3 tools/proof/graphics_spike/graphics_spike.py --skip-build ...     # reuse the spike's target/
"""

import argparse
import datetime
import json
import os
import platform
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bounded  # noqa: E402
import rows_app  # noqa: E402
import rows_build  # noqa: E402
import rows_local  # noqa: E402

ORDER = ["q2", "q8", "q3", "q4", "q5", "q6", "q1", "q9", "q7"]
ANSWERS = os.path.join(rows_local.WORK, "answers.json")
CRATES = ["rquickjs", "rquickjs-core", "rquickjs-sys", "resvg", "usvg", "tiny-skia", "fontdb",
          "harfrust", "skrifa", "roxmltree", "svgtypes", "serde_json", "sha2", "cc"]


def say(line):
    print(line, flush=True)


def first_line(argv):
    result = bounded.run(argv, 60)
    return (result["stdout"] or result["stderr"]).strip().splitlines()[0] if result["rc"] == 0 else None


def host():
    return {
        "hw_model": first_line(["sysctl", "-n", "hw.model"]),
        "cpu": first_line(["sysctl", "-n", "machdep.cpu.brand_string"]),
        "ncpu": first_line(["sysctl", "-n", "hw.ncpu"]),
        "macos": first_line(["sw_vers", "-productVersion"]),
        "macos_build": first_line(["sw_vers", "-buildVersion"]),
        "xcode": " ".join((bounded.run(["xcodebuild", "-version"], 60)["stdout"] or "").split()),
        "swiftc": first_line(["xcrun", "swiftc", "--version"]),
        "rustc": first_line(["rustc", "--version"]),
        "cargo": first_line(["cargo", "--version"]),
        "python": platform.python_version(),
        "date": datetime.datetime.now().isoformat(timespec="seconds"),
    }


def load_previous():
    try:
        with open(ANSWERS) as handle:
            return json.load(handle)
    except (OSError, json.JSONDecodeError):
        return {}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", help="comma-separated rows, e.g. q4,q5")
    parser.add_argument("--mutant", action="store_true",
                        help="run q5 over the module-level-counter copy of counter.js")
    parser.add_argument("--skip-build", action="store_true")
    options = parser.parse_args()
    selected = [r.strip() for r in options.only.split(",")] if options.only else list(ORDER)
    if options.mutant:
        selected = ["q5"]
    unknown = [r for r in selected if r not in ORDER]
    if unknown:
        parser.error(f"unknown rows {unknown}")
    os.makedirs(rows_local.WORK, exist_ok=True)
    answers = load_previous()
    answers["host"] = host()
    versions = rows_local.locked_versions()
    answers["crate_versions"] = {name: versions.get(name) for name in CRATES}
    answers.setdefault("rows", {})
    say(f"graphics spike: {', '.join(selected)} on {answers['host']['hw_model']} "
        f"macOS {answers['host']['macos']}")

    if not options.skip_build and any(r in selected for r in ("q2", "q3", "q4", "q5", "q6", "q8", "q9")):
        answers["spike_build"] = rows_local.build(say)
        if any(v["rc"] != 0 for v in answers["spike_build"].values()):
            say("SPIKE BUILD FAILED")
            write(answers)
            return 1

    if options.mutant:
        result = rows_local.q5(say, mutant=True)
        answers.setdefault("mutants", {})["q5"] = result
        write(answers)
        caught = result["state"] == "run" and result["measured"]["sha256_mismatches"] > 0
        say(f"q5 MUTANT: {'CAUGHT' if caught else 'NOT CAUGHT'} "
            f"({result['measured'].get('sha256_mismatches')} raster mismatches)")
        return 0 if caught else 1

    local = {"q2": rows_local.q2, "q8": rows_local.q8, "q3": rows_local.q3, "q4": rows_local.q4,
             "q5": rows_local.q5, "q6": rows_local.q6}
    for row in [r for r in ORDER if r in local and r in selected]:
        say(f"{row}:")
        answers["rows"][row] = local[row](say)
        write(answers)

    if "q1" in selected or "q9" in selected:
        try:
            if "q1" in selected:
                say("q1:")
                answers["rows"]["q1"] = rows_build.q1(say)
                write(answers)
            else:
                before = rows_build.git_check()
                if not before["clean"]:
                    raise RuntimeError("core/ or app/ differs from c874069 before q9")
                rows_build.patch(say)
            if "q9" in selected and answers["rows"].get("q1", {}).get("state") != "failed":
                say("q9:")
                answers["rows"]["q9"] = rows_build.q9(say)
                write(answers)
        finally:
            say("revert:")
            answers["revert"] = rows_build.revert(say)
            answers["git_check"] = answers["revert"]["git_check"]
            write(answers)

    if "q7" in selected:
        say("q7:")
        answers["rows"]["q7"] = rows_app.q7(say)
        answers["git_check"] = rows_build.git_check()
        write(answers)

    answers["git_check"] = rows_build.git_check()
    answers["carried_forward"] = [r for r in ORDER if r not in selected and r in answers["rows"]]
    write(answers)
    states = {r: answers["rows"].get(r, {}).get("state", "absent") for r in ORDER}
    say("rows: " + ", ".join(f"{r} {s}" for r, s in states.items()))
    say(f"git check clean: {answers.get('git_check', {}).get('clean')}")
    not_run = [r for r in selected if states[r] != "run"]
    if not_run:
        say(f"SPIKE INCOMPLETE: {', '.join(not_run)}")
        return 1
    if not answers.get("git_check", {}).get("clean", False):
        say("GIT CHECK NOT CLEAN")
        return 1
    return 0


def write(answers):
    with open(ANSWERS, "w") as handle:
        json.dump(answers, handle, indent=2, sort_keys=False)


if __name__ == "__main__":
    sys.exit(main())
