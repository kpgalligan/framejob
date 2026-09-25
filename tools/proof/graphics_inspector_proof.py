#!/usr/bin/env python3
"""Road map 10, G5a — the Graphic sub-tab in the clip inspector (§5j; spec
§11 G-15), against the built app, a probe and the offscreen harness.

    python3 tools/proof/graphics_inspector_proof.py [--port 4887] [--app PATH]
    python3 tools/proof/graphics_inspector_proof.py --mutant stale [--port 4887]

**The fixture, over MCP** (one owned instance on its own port, launched and
stopped by PID, its log at `work/graphics-inspector/reelcut-<port>.log`):
`new_project {path: GI}`, `write_graphic six` — a module with one entry of
every schema type: `title` a string whose default holds `{"}:`, `size` a
number 12–200 step 1, `offset` an unbounded number, `showBox` a boolean,
`color` a colour defaulting to "#FF5A36" (uppercase on purpose), `align` an
enum, `logo` an asset defaulting to null; its `render` sizes the `<svg>` from
ctx (`svg(ctx, …)`) and draws text in `'Nope Sans'` — `import_graphic_asset
graphic/tests/assets/red.png`, `add_graphic_clip`, `set_graphic {props:
{size: 90}}`, `save_project`; the instance is stopped, and `"old": 1` and
`"zzz": 2` are injected into the clip's props in `project.json` (the tool
path refuses a stranger key; this is the external edit G-4 tolerates).

**The probe**, `graphics_inspector_probe.swift`, compiled AS `main.swift` over
every file in `app/Sources` but the app's own on `harness/build.sh`'s swiftc
line (a probe that will not build is a scored FAILURE), with the app's Fonts
beside it, over a COPY of the fixture:
I1  `orderedKeys` over six's `describeJSON()` is the module's order;
I2  one row per type, with its control classes; the asset popup lists None
    and red.png;
I3  size 90 vs default 64: the gutter's default differs and its ops are
    `set_graphic {props: {size: null}}`; no stored size → no difference; the
    colour row, unstored, differs not and resets to `{color: null}`;
I4  `patchValue`'s null rule (a number, "#ff5a36" vs "#FF5A36", the unparsed
    swatch vs "white"), `defaultColor("white")`, the four hex forms
    round-tripped and `css([1, 0.353, 0.212, 1]) == "#ff5a36"`;
I5  `staleKeys` sorted; the stale rows old then zzz; a syntax error makes every
    stored key stale and the Source section's compile row names line 2; each
    ⌫ removes its key;
I6  one more schema key changes `structureSignature`; a default or a stored
    value alone does not;
I7  the tabs [graphic, picture, clip]; the four section ids; two modules →
    [graphic.source, graphic.size]; `keyedCount` 0;
I8  the report names Nope Sans and the set's families, with no size warning;
    a fixed 100×100 `<svg>` gets exactly one naming 1920×1080; a throw at
    frame 0 is an error with `frame == 0`;
I9  the TOOL's size 90 shows in the Size field; the checkbox's write lands
    under the module's spelling (`showBox`);
I10 `fitToCanvasOps`; I11 `sourceSize(of:)`; I12 after `trim_start` by 2 s
    the In readout shows the graphic's own in point.

**The harness** (`harness/build.sh`, 1440 × 1500, the clip selected, subTab
graphic, the four sections expanded):
H1  light, rendered twice: byte-identical;
H2  dark, rendered twice: byte-identical, and light ≠ dark. Both kept under
    `work/graphics-inspector/` to be LOOKED AT.
Z1  `grep "Reelcut: "` over the log prints nothing.

`--mutant stale` builds the probe over a COPY of `app/Sources` whose
`GraphicSchemaRows.staleKeys` answers `[]`, over a fresh fixture. Exit 0
means exactly `MUTANT_EXPECTED` failed and nothing else did.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import graphics_proof as gp  # noqa: E402  (Instance, attempt, complaints)

WORK = ROOT / "tools/proof/work/graphics-inspector"
APP = ROOT / "build/Build/Products/Release/Reelcut.app/Contents/MacOS/Reelcut"
PROBE_SWIFT = ROOT / "tools/proof/graphics_inspector_probe.swift"
HARNESS_BUILD = ROOT / "tools/proof/harness/build.sh"
RED_PNG = ROOT / "graphic/tests/assets/red.png"
SECTIONS = "graphic.source,graphic.properties,graphic.size,graphic.timeline"
WIDTH, HEIGHT = 1440, 1500

SIX_JS = r'''export const meta = { name: "Six", durationInFrames: 150 };
export const schema = {
  title: { type: "string", default: "Hi {\"}: there", label: "Title", help: "The words drawn" },
  size: { type: "number", default: 64, min: 12, max: 200, step: 1, label: "Size" },
  offset: { type: "number", default: 0, label: "Offset" },
  showBox: { type: "boolean", default: true, label: "Show box" },
  color: { type: "color", default: "#FF5A36", label: "Color" },
  align: { type: "enum", default: "left", options: ["left", "center", "right"], label: "Align" },
  logo: { type: "asset", default: null, label: "Logo" },
};
export function render(frame, props, ctx) {
  return svg(ctx, `<text x="100" y="300" font-family="'Nope Sans'" font-size="${props.size}" fill="${props.color}">${escapeXml(props.title)}</text>`);
}
'''

MUTANT_FILE = "GraphicSchemaRows.swift"
MUTANT_ANCHOR = "        return stored.keys.filter { !declared.contains($0) }.sorted()\n"
MUTANT_EXPECTED = [
    "I5 staleKeys is [old, zzz] from a dictionary built in the reverse order",
    "I5 the Properties section lists the stale rows old then zzz, under the schema's",
    "I5 six rewritten to a syntax error: every stored key is a stale row, sorted",
    "I5 old's ⌫ nulls it: the key leaves the stored props",
    "I5 zzz's ⌫ nulls it: the key leaves the stored props",
]

RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append((name, bool(ok)))
    print(f"  {'ok  ' if ok else 'FAIL'} {name}", flush=True)
    if detail and not ok:
        print("       " + detail, flush=True)
    elif detail:
        print("       " + detail.splitlines()[0][:300], flush=True)


# ---------------------------------------------------------------------------
# The fixture.


def fixture(app, port, work):
    """The package over MCP, then the two stale keys injected on disk. The
    package's path, or None and why; the log."""
    work.mkdir(parents=True, exist_ok=True)
    package = work / "GI.reelcut"
    shutil.rmtree(package, ignore_errors=True)
    log = work / f"reelcut-{port}.log"
    if log.exists():
        log.unlink()
    instance = gp.Instance(app, port, log)
    client = instance.start()
    try:
        if client is None:
            return None, "the instance did not start", log
        steps = []

        def step(tool, arguments):
            got = gp.attempt(client, tool, arguments)
            steps.append(f"{tool} {'ok' if got['ok'] else got['error']}")
            return got

        p = {"project": str(package)}
        step("new_project", {"path": str(package)})
        wrote = step("write_graphic", dict(p, name="six", source=SIX_JS))
        step("import_graphic_asset", dict(p, path=str(RED_PNG)))
        project = (step("get_project", p).get("reply") or {}).get("project") or {}
        track = (project.get("tracks") or [{}])[0].get("id")
        step("add_graphic_clip", dict(p, name="six", track=track, at=0))
        project = (step("get_project", p).get("reply") or {}).get("project") or {}
        clips = [c for c in project.get("clips", [])
                 if (c.get("graphic") or {}).get("name") == "six"]
        if not clips:
            return None, "no clip drawn by six: " + "; ".join(steps), log
        step("set_graphic", dict(p, clips=[clips[0]["id"]], patch={"props": {"size": 90}}))
        step("save_project", p)
        ok = (wrote.get("reply") or {}).get("ok") is True
        if not ok or any(not s.endswith(" ok") for s in steps):
            return None, "; ".join(steps) + f"; write_graphic reply {wrote}", log
    finally:
        instance.stop()
    path = package / "project.json"
    data = json.loads(path.read_text())
    for clip in data.get("clips", []):
        if (clip.get("graphic") or {}).get("name") == "six":
            clip["graphic"]["props"]["old"] = 1
            clip["graphic"]["props"]["zzz"] = 2
    path.write_text(json.dumps(data, indent=2))
    return package, None, log


# ---------------------------------------------------------------------------
# The probe.


def build_probe(sources, out):
    """`harness/build.sh`'s swiftc line over `sources` with the probe as
    `main.swift`; the app's Fonts beside the binary. The binary, or None and
    the error lines."""
    lib = ROOT / "core/target/release/libreelcut_core.a"
    if not lib.exists():
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    source = PROBE_SWIFT.read_text()
    if not entry.exists() or entry.read_text() != source:
        entry.write_text(source)
    binary = out / "graphics-inspector-probe"
    swift = sorted(str(Path(sources) / n) for n in os.listdir(sources)
                   if n.endswith(".swift") and n != "main.swift")
    fresh = binary.exists() and all(
        os.path.getmtime(f) < binary.stat().st_mtime for f in swift + [str(entry), str(lib)])
    if not fresh:
        sdk = bounded.run(["xcrun", "--show-sdk-path", "--sdk", "macosx"], 60)["stdout"].strip()
        start = time.time()
        built = bounded.run(
            ["swiftc", "-sdk", sdk, "-target", "arm64-apple-macos26.0", "-module-name",
             "Reelcut", "-import-objc-header",
             str(ROOT / "app/Bridging/Reelcut-Bridging-Header.h"),
             "-L", str(lib.parent), "-lreelcut_core"] + swift + [str(entry), "-o", str(binary)],
            900)
        if built["rc"] != 0 or not binary.exists():
            errors = [line for line in built["stderr"].splitlines() if ": error:" in line]
            return None, "swiftc failed:\n       " + "\n       ".join(
                errors[:6] or [f"(no error lines; expired {built['expired']})"])
        print(f"  probe built in {time.time() - start:.0f} s", flush=True)
    shutil.rmtree(out / "Fonts", ignore_errors=True)
    shutil.copytree(ROOT / "app/Resources/Fonts", out / "Fonts")
    return binary, None


def probe_checks(sources, out, package):
    print("\n1 — the probe: I1–I12", flush=True)
    binary, error = build_probe(Path(sources), out)
    check("the probe builds over app/Sources", binary is not None, error or "")
    if binary is None:
        return
    copy = out / "GI-probe.reelcut"
    shutil.rmtree(copy, ignore_errors=True)
    shutil.copytree(package, copy)
    request, answer = out / "request.json", out / "answer.json"
    if answer.exists():
        answer.unlink()
    request.write_text(json.dumps({"package": str(copy)}))
    ran = bounded.run([str(binary), str(request), str(answer)], 300)
    if ran["rc"] != 0 or not answer.exists():
        check("the probe runs", False, (ran["stdout"] + ran["stderr"]).strip()[-600:])
        return
    probe_rows = json.loads(answer.read_text())["rows"]
    present = all(any(r["name"].startswith(f"I{n} ") for r in probe_rows) for n in range(1, 13))
    check("the probe answers every I-row (I1–I12 present)", present, f"{len(probe_rows)} rows")
    for row in probe_rows:
        check(row["name"], row["ok"], row["detail"])


# ---------------------------------------------------------------------------
# The harness.


def harness_checks(package):
    print("\n2 — the harness: the Graphic sub-tab, light and dark, 1440 × 1500", flush=True)
    built = bounded.run([str(HARNESS_BUILD)], 900)
    binary = built["stdout"].strip().splitlines()[-1] if built["rc"] == 0 else None
    renders, error = {}, None if binary else f"build.sh failed: {built['stderr'][-400:]}"
    for tag, look in (("light-a", "light"), ("light-b", "light"), ("dark-a", "dark"),
                      ("dark-b", "dark")):
        if error:
            break
        out = WORK / f"gi-{tag}.png"
        if out.exists():
            out.unlink()
        ran = bounded.run(
            [binary, str(package), str(out), look, str(WIDTH), str(HEIGHT), "0", "0", "1",
             "clip", "-", SECTIONS, "-", "-", "graphic"], 120)
        if ran["rc"] != 0 or not out.exists():
            error = (ran["stdout"] + ran["stderr"]).strip()[-400:] or f"rc {ran['rc']}"
        renders[tag] = out
    if error:
        check("H1 light, rendered twice: byte-identical PNGs", False, error)
        check("H2 dark, rendered twice: byte-identical PNGs, and light ≠ dark", False, error)
        return

    def data(tag):
        return renders[tag].read_bytes()
    check("H1 light, rendered twice: byte-identical PNGs", data("light-a") == data("light-b"),
          str(renders["light-a"].relative_to(ROOT)))
    check("H2 dark, rendered twice: byte-identical PNGs, and light ≠ dark",
          data("dark-a") == data("dark-b") and data("dark-a") != data("light-a"),
          str(renders["dark-a"].relative_to(ROOT)))


# ---------------------------------------------------------------------------


def mutant(app, port):
    began = time.time()
    with tempfile.TemporaryDirectory(prefix="reelcut-graphics-inspector-stale-") as temp:
        temp = Path(temp)
        sources = temp / "Sources"
        shutil.copytree(ROOT / "app/Sources", sources)
        path = sources / MUTANT_FILE
        text = path.read_text()
        if text.count(MUTANT_ANCHOR) != 1:
            print(f"MUTANT FAILURE: the anchor occurs {text.count(MUTANT_ANCHOR)} times")
            return 2
        path.write_text(text.replace(
            MUTANT_ANCHOR, "        _ = declared\n        return []  // mutant: nothing is stale\n", 1))
        print(f"MUTANT stale: GraphicSchemaRows.staleKeys answers [], in {sources}", flush=True)
        package, why, _ = fixture(app, port, temp / "fixture")
        if package is None:
            print(f"MUTANT FAILURE: the fixture was not made: {why}")
            return 1
        probe_checks(sources, temp / "probe", package)
    failed = [n for n, ok in RESULTS if not ok]
    built = bool(RESULTS) and RESULTS[0][1]
    elapsed = time.time() - began
    if built and sorted(failed) == sorted(MUTANT_EXPECTED):
        print(f"MUTANT PASS: stale — exactly the {len(MUTANT_EXPECTED)} expected I5 row(s) "
              f"FAILED in the copy and nothing else did, {elapsed:.0f} s")
        return 0
    print(f"MUTANT FAILURE: stale — built {built}; missing failures "
          f"{[n for n in MUTANT_EXPECTED if n not in failed]}; unexpected failures "
          f"{[n for n in failed if n not in MUTANT_EXPECTED]}, {elapsed:.0f} s")
    return 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=4887)
    parser.add_argument("--app", default=str(APP))
    parser.add_argument("--mutant", choices=["stale"])
    args = parser.parse_args()
    app = Path(args.app)
    if args.mutant:
        return mutant(app, args.port)
    print("Road map 10, G5a — the Graphic sub-tab", flush=True)
    print("\n0 — the fixture over MCP", flush=True)
    package, why, log = fixture(app, args.port, WORK)
    check("the fixture is made over MCP (new_project, write_graphic, import_graphic_asset, "
          "add_graphic_clip, set_graphic, save_project)", package is not None, why or "")
    if package is not None:
        probe_checks(ROOT / "app/Sources", WORK / "probe", package)
        harness_checks(package)
    lines = gp.complaints(log)
    check("Z1 grep \"Reelcut: \" over the log prints nothing", not lines,
          "; ".join(lines[:4]))
    good = sum(1 for _, ok in RESULTS if ok)
    print(f"\n{good}/{len(RESULTS)} checks passed")
    return 0 if RESULTS and good == len(RESULTS) else 1


if __name__ == "__main__":
    sys.exit(main())
