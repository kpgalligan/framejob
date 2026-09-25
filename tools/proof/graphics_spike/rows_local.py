"""q2, q3, q4, q5, q6 and q8 of road map 10 §3: the spike crate built in
release and debug, its binary invoked once per row (q6: once per case),
every invocation under `bounded.run`. Each row answers
`{state, reason, measured}`."""

import glob
import json
import os
import re

import bounded

SPIKE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(SPIKE, "..", "..", ".."))
WORK = os.path.join(REPO, "tools", "proof", "work", "graphics_spike")
FONTS = os.path.join(REPO, "app", "Resources", "Fonts")
GRAPHICS = os.path.join(SPIKE, "graphics")

# The Rust side's `CASES`, in order (src/rows_stress.rs).
CASES = ["while_true", "array_1e9", "deep_recursion", "string_50mb", "string_100mb",
         "math_random", "date_now", "eval", "new_function", "date_constructor",
         "async_function_constructor", "generator_function_constructor",
         "async_generator_function_constructor", "dynamic_import",
         "static_import", "webassembly", "uint8_leak", "returns_undefined"]


def binary(profile="release"):
    return os.path.join(SPIKE, "target", profile, "graphics_spike")


def build(say):
    """`cargo build --release` then `cargo build`, each bounded at 600 s."""
    answers = {}
    for profile, argv in (("release", ["cargo", "build", "--release"]), ("debug", ["cargo", "build"])):
        result = bounded.run(argv, 600, cwd=SPIKE)
        answers[profile] = {"rc": result["rc"], "seconds": result["seconds"], "expired": result["expired"]}
        say(f"  build {profile}: rc {result['rc']} in {result['seconds']} s")
        if result["rc"] != 0:
            answers[profile]["stderr"] = result["stderr"][-4000:]
    return answers


def call(arguments, seconds, profile="release"):
    """Runs the spike binary; answers (the one JSON object it printed, the run)."""
    result = bounded.run([binary(profile)] + arguments, seconds, cwd=SPIKE)
    lines = [l for l in result["stdout"].splitlines() if l.startswith("{")]
    try:
        value = json.loads(lines[-1]) if lines else None
    except json.JSONDecodeError:
        value = None
    return value, result


def locked_versions():
    """Every package in the spike's Cargo.lock, name → [versions]."""
    versions = {}
    with open(os.path.join(SPIKE, "Cargo.lock")) as handle:
        body = handle.read()
    for name, version in re.findall(r'name = "([^"]+)"\nversion = "([^"]+)"', body):
        versions.setdefault(name, []).append(version)
    return versions


def quickjs_version():
    sys_version = locked_versions().get("rquickjs-sys", ["?"])[0]
    headers = glob.glob(os.path.expanduser(
        f"~/.cargo/registry/src/*/rquickjs-sys-{sys_version}/quickjs/quickjs.h"))
    found = {}
    if headers:
        with open(headers[0]) as handle:
            for key, value in re.findall(r"#define (QJS_VERSION_\w+) (\S+)", handle.read()):
                found[key] = value.strip('"')
    return {"rquickjs_sys": sys_version, "header": headers[0] if headers else None, "defines": found}


def failed(reason, measured=None):
    return {"state": "failed", "reason": reason, "measured": measured or {}}


def ran(measured, reason=None):
    return {"state": "run", "reason": reason, "measured": measured}


def q2(say):
    value, result = call(["q2", "--fonts", FONTS], 60)
    if value is None or "error" in value:
        return failed("q2 printed no answer", {"stderr": result["stderr"][-2000:], "value": value})
    value["quickjs"] = quickjs_version()
    say(f"  q2: userAgent {value['userAgent']!r}, QuickJS {value['quickjs']['defines']}")
    return ran(value)


def q3(say):
    csv = os.path.join(WORK, "q3.csv")
    value, result = call(["q3", "--graphics", GRAPHICS, "--fonts", FONTS, "--frames", "300",
                          "--csv", csv], 1800)
    if result["expired"]:
        return {"state": "expired", "reason": "q3 ran past 1800 s", "measured": {}}
    if value is None or "error" in value:
        return failed("q3 printed no answer", {"stderr": result["stderr"][-2000:], "value": value})
    value["csv"] = os.path.relpath(csv, REPO)
    value["seconds"] = result["seconds"]
    for row in value["rows"]:
        say(f"  q3 {row['graphic']:<13} {row['width']}×{row['height']}: total p50 "
            f"{row['total']['p50']:.2f} p95 {row['total']['p95']:.2f} max {row['total']['max']:.2f} ms")
    return ran(value)


def q4(say):
    value, result = call(["q4", "--fonts", FONTS], 600)
    if value is None or "error" in value:
        return failed("q4 printed no answer", {"stderr": result["stderr"][-2000:], "value": value})
    say(f"  q4: flat within 1 px {value['all']['flat_within_1px']}/{value['all']['n']}, "
        f"bbox within 1 px {value['all']['bbox_within_1px']}/{value['all']['n']}")
    return ran(value)


def q5(say, mutant=False):
    arguments = ["q5", "--graphics", GRAPHICS, "--fonts", FONTS] + (["--mutant"] if mutant else [])
    value, result = call(arguments, 900)
    if result["expired"]:
        return {"state": "expired", "reason": "q5 ran past 900 s", "measured": {}}
    if value is None or "error" in value:
        return failed("q5 printed no answer", {"stderr": result["stderr"][-2000:], "value": value})
    value["seconds"] = result["seconds"]
    say(f"  q5{' MUTANT' if mutant else ''}: {value['renders']} renders, "
        f"{value['sha256_mismatches']} raster and {value['svg_mismatches']} SVG mismatches")
    return ran(value)


def q6(say):
    cases = []
    for case in CASES:
        value, result = call(["q6", "--case", case, "--graphics", GRAPHICS, "--fonts", FONTS], 30)
        entry = value if isinstance(value, dict) and "case" in value else {"case": case, "outcome": None}
        entry["process"] = {"rc": result["rc"], "expired": result["expired"],
                            "seconds": result["seconds"], "stderr": result["stderr"][-600:]}
        if result["expired"]:
            entry["outcome"] = "expired"
        cases.append(entry)
        say(f"  q6 {case:<18} {entry.get('outcome')} in {entry.get('ms', 0):.1f} ms, "
            f"control {entry.get('control_ok')}, rc {result['rc']}")
    survived = sum(1 for c in cases if c["process"]["rc"] == 0 and not c["process"]["expired"])
    controls = sum(1 for c in cases if c.get("control_ok"))
    return ran({"cases": cases, "processes_survived": survived, "controls_ok": controls,
                "n": len(cases), "budget_ms": 250})


def q8(say):
    answers = {}
    for profile in ("release", "debug"):
        value, result = call(["q8"], 120, profile)
        answers[f"bin_{profile}"] = value
    for label, argv in (("test_release", ["cargo", "test", "--release", "--test", "q8", "--", "--nocapture"]),
                        ("test_debug", ["cargo", "test", "--test", "q8", "--", "--nocapture"])):
        result = bounded.run(argv, 600, cwd=SPIKE)
        lines = [l for l in result["stdout"].splitlines() if l.startswith('{"profile"') or l.startswith('{"sha256"')]
        answers[label] = json.loads(lines[-1]) if lines else {"rc": result["rc"], "stderr": result["stderr"][-1500:]}
    hashes = {k: (v or {}).get("sha256") for k, v in answers.items()}
    identical = len(set(hashes.values())) == 1 and None not in hashes.values()
    say(f"  q8: {'IDENTICAL' if identical else 'DIFFERENT'} {hashes}")
    if None in hashes.values():
        return failed("a q8 hash was not printed", {"answers": answers})
    return ran({"answers": answers, "hashes": hashes, "identical": identical})
