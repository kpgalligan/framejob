#!/usr/bin/env python3
"""Sequential FFI argument-contract suites and isolated negative controls."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SUITES = ("op_nullability", "op_default_booleans", "op_ticks", "op_tick_payloads")


def cargo(core, suite, test=None, target=None):
    command = ["cargo", "test", "--release", "--test", suite]
    if test:
        command += [test]
    environment = os.environ.copy()
    if target:
        environment["CARGO_TARGET_DIR"] = str(target)
    print("RUN", " ".join(command), "in", core, flush=True)
    result = subprocess.run(command, cwd=core, env=environment, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    print(result.stdout, flush=True)
    return result


def replace_once(path, before, after):
    text = path.read_text()
    count = text.count(before)
    if count != 1:
        raise RuntimeError(f"mutation anchor {path.name}: expected once, found {count}: {before!r}")
    path.write_text(text.replace(before, after))


# The negative controls: each mutant's edits (a file from the repo root, the text that must
# occur there exactly once, its replacement), the tests that must then fail, and the text their
# failure must carry. `mutate` and `negative` read this table and `mutant_anchors.py` counts
# its anchors in `make test`.
SERDE_USE = "use crate::time::{Fps, Ticks};\n"
MUTANTS = {
    "null-as-absent": {
        "edits": [
            ("core/src/edit.rs", "        #[serde(default)]\n        ripple: bool,",
             "        #[serde(default, deserialize_with = \"null_is_false\")]\n        ripple: bool,"),
            ("core/src/edit.rs", SERDE_USE,
             SERDE_USE + "\nfn null_is_false<'de, D: serde::Deserializer<'de>>(source: D) "
             "-> Result<bool, D::Error> {\n"
             "    Ok(Option::<bool>::deserialize(source)?.unwrap_or(false))\n}\n"),
        ],
        "tests": [("op_nullability", "every_optional_field_has_its_real_null_contract")],
        "signature": '"ripple":null}: no clip with id 1',
    },
    "unsnapped-marker": {
        "edits": [
            ("core/src/edit_track.rs",
             "        let at = self.snapped(at).max(0);\n        if let Some(existing) = self.markers.iter().find(|m| m.time == at) {",
             "        let at = at.max(0);\n        if let Some(existing) = self.markers.iter().find(|m| m.time == at) {"),
        ],
        "tests": [("op_ticks", "marker_off_grid_rounds_before_storage")],
        "signature": "assertion `left == right` failed",
    },
    "nearest-transition": {
        "edits": [
            # Round to nearest instead of counting down: half a frame added before the count.
            ("core/src/edit_transition.rs", "        let requested = frames_in(duration, fps);",
             "        let requested = frames_in(duration + crate::time::one_frame(fps) / 2, fps);"),
            ("core/src/edit_transition_shift.rs", "        let asked = frames_in(duration, fps);",
             "        let asked = frames_in(duration + crate::time::one_frame(fps) / 2, fps);"),
        ],
        "tests": [("op_ticks", "transition_floor_handle_mode"),
                  ("op_ticks", "transition_floor_ripple_mode")],
        "signature": "assertion `left == right` failed",
    },
}


def mutate(root, name):
    """Apply a mutant's edits under `root`, a folder holding a copy of `core/`."""
    for file, before, after in MUTANTS[name]["edits"]:
        replace_once(root / file, before, after)
    return MUTANTS[name]["tests"]


def positive():
    total = 0
    for suite in SUITES:
        result = cargo(ROOT / "core", suite)
        if result.returncode:
            raise RuntimeError(f"{suite}: baseline failed ({result.returncode})")
        count = re.search(r"test result: ok\. (\d+) passed; 0 failed", result.stdout)
        if not count:
            raise RuntimeError(f"{suite}: no completed test count")
        total += int(count.group(1))
    print(f"BASELINE PASS: {len(SUITES)} suites, {total} tests", flush=True)


def negative(name):
    signature = MUTANTS[name]["signature"]
    with tempfile.TemporaryDirectory(prefix=f"framejob-contract-{name}-") as temp:
        temp = Path(temp)
        core = temp / "core"
        # `core/Cargo.toml` names `../graphic` and its vendored tiny-skia by path, so the copy
        # holds both crates side by side as the tree does.
        for crate in ("core", "graphic"):
            shutil.copytree(ROOT / crate, temp / crate,
                            ignore=shutil.ignore_patterns("target", ".git", ".DS_Store"))
        commands = mutate(temp, name)
        for suite, test in commands:
            result = cargo(core, suite, test, target=temp / "target")
            if "Finished `release` profile" not in result.stdout:
                raise RuntimeError(f"{name}/{test}: compile did not succeed")
            if "Running tests/" not in result.stdout or f"test {test} ... FAILED" not in result.stdout:
                raise RuntimeError(f"{name}/{test}: expected behavioral assertion did not fail")
            if result.returncode == 0 or signature not in result.stdout:
                raise RuntimeError(f"{name}/{test}: no targeted assertion failure")
            print(f"NEGATIVE CONTROL PASS: {name}/{test} failed its assertion", flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mutant", choices=tuple(MUTANTS))
    args = parser.parse_args()
    try:
        if args.mutant:
            negative(args.mutant)
        else:
            positive()
    except RuntimeError as error:
        print("PROOF FAILURE:", error, file=sys.stderr)
        return 2
    return 1 if args.mutant else 0


if __name__ == "__main__":
    sys.exit(main())
