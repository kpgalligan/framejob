#!/usr/bin/env python3
"""Issue batch B80 — the opt-in ffmpeg conversion records its original (spec
§11 #233) and copies a constant-rate VP9 Profile 0/2 stream, kept only when
every frame of the copy is on its rate's grid (#227).

    python3 tools/proof/ffmpeg_rewrap_proof.py [--mutant NAME]

Builds `ffmpeg_rewrap_probe.swift` over app/Sources (minus `main.swift`) on
harness/build.sh's swiftc line, rebuilt only when stale, under
`tools/proof/work/ffmpeg-rewrap-build/`, and runs it once. No app instance is
launched and nothing is activated: the probe is a `.prohibited` process that
imports on background threads while main spins its run loop. Needs `ffmpeg`
and `ffprobe` (with libvpx-vp9) on the PATH; not a line of `make test`.

**Scratch home.** `tools/proof/work/ffmpeg-rewrap/` is removed at start and
at exit. It holds the fixtures, the wrapper, `home/` and `t/`, and the probe
runs with `CFFIXED_USER_HOME=<work>/home` and the launch arguments
`-RCFFmpegImport always -RCFFmpegPath <work>/tools/ffmpeg` (it writes no
`UserDefaults`), so nothing this proof converts lands in the owner's
`~/Library/Application Support/Reelcut/Rewrapped/`. Nothing outside
`tools/proof/work/` is written or deleted.

**The wrapper**, `<work>/tools/ffmpeg`, made here with the real ffmpeg's path
baked in: it appends its argv as a JSON line to `<work>/ffmpeg.log` and reads
`<work>/mode` — `pass` execs the real ffmpeg; `fail-copy` exits 1 when argv
holds `-f mp4`; `swap-copy` runs the real ffmpeg with the `-i` value replaced
by `p1.ivf` when argv holds `-f mp4`. It has no sibling `ffprobe`: the
product finds the real one. Fixtures are made with the real ffmpeg, never
the wrapper. A V row's run count ignores log lines whose last argument is
under `<work>/t/` (the T rows' own runs).

**Fixtures** (128x72 `testsrc2` + a 440 Hz sine of 1 s, `-frames:v 30`, made
at proof time; each must hold 30 video packets, else exit 2): `v0.mkv` VP9
`yuv420p` 30 fps + FLAC; `v2.mkv` VP9 `yuv420p10le -profile:v 2` + FLAC;
`vn.mkv` as `v0.mkv` at 30000/1001; `vj.mkv`, `v0.mkv` through `-c copy
-bsf:v setts=ts=TS+mod(N\\,3)*9` (times jittered by 0/9/18 ms); `vg.mkv` as
`v0.mkv` with every fifth frame dropped (`select`, `-fps_mode vfr`);
`v0a.mkv`, `v0b.mkv`, `v0c.mkv`, byte copies of `v0.mkv`; `p1.ivf`, VP9
`yuv444p -profile:v 1`, no sound.

**The count** (`exactFrames` in the probe): after `DecoderSupport.enable()`,
an `AVAssetImageGenerator` with both tolerances zero is asked for frame k at
`CMTime(value: k*D, timescale: N)`, k in 0..<30; a RIGHT answer is one whose
actual time compares equal to the request. A row prints right/30 and
distinct-actual-times/30 and passes only at 30/30 and 30/30.

Rows:

- **F0** the probe built (a failed build is a scored FAILURE);
  `AppSupport.subdirectory("Rewrapped")` lies inside `<work>/home` (else
  nothing else runs); `FFmpegRewrap.tools()?.ffmpeg` is the wrapper.
- **O1** `MediaImporter.probeBlocking(url: v0.mkv)`: the path is directly in
  the scratch `Rewrapped/`, `original.path` is v0.mkv and its bookmark
  resolves to v0.mkv. **O2** through `AgentLane.shared.serve`: `new_project`,
  `import_media {v0a.mkv}` answers `original` = v0a.mkv, `get_project`'s
  media has `original.path`, `close_project`. **O3** O1's descriptor added
  to a project: `MediaSnapshot.name` is `v0.mkv`, the tooltip's first line
  is "`<v0.mkv's path>` — copied into Reelcut's Rewrapped folder." and
  `revealURL(for:)` is v0.mkv.
- **O4** a project of O1's descriptor with its path `/nonexistent-b80/<name>`,
  no bookmark, and the conversion discarded:
  `ProjectDocument.recopyingMissingCopies(_, watch: nil)` answers the same
  JSON, `ffmpeg.log` gains no line and `Rewrapped/` no file. **O5** the same
  with the conversion still on disk: the media's path becomes the digest
  file, `original` is kept, and the log gains no line.
- **T1 / T2 / T3** the command's own output, no check between, for `v0.mkv`
  (30/1), `vn.mkv` (30000/1001) and `v2.mkv` (30/1): `plan(for:with:)` is
  `copiesVP9`; `run(tools.ffmpeg, arguments(for:with:writing:
  <work>/t/<name>.mov), timeout: 120)` exits 0; the count on that file.
- **V1** v0.mkv's product file (O1's): video `vp09` (CoreMedia's subtype)
  and the sound's sample entry `mp4a` (the real ffprobe's
  `codec_tag_string`; CoreMedia's subtype for it is `aac `, printed beside
  it); the first frame decodes to a 128x72 BGRA buffer and
  `DecoderSupport.decodesFirstFrame` is true; exactly one `-i` run, with
  `-c:v copy` and `-f mp4`; the count. **V2** the same for v2.mkv.
- **V3** p1.ivf imports; video `avc1`; one `-i` run, no `-c:v copy`.
- **V4** mode `fail-copy`, v0b.mkv: imports with `original`; video `avc1`;
  two `-i` runs (the first `-c:v copy`, the second `-f mov` with an
  encoder); exactly one file for it in `Rewrapped/` and no partial. **V5**
  mode `swap-copy`, v0c.mkv: the same four facts.
- **V6** vn.mkv through the product: `vp09`, one `-i` run, the count at
  30000/1001.
- **V7** vj.mkv (jitter): the same four facts as V4, in mode `pass` — its
  copy is made, fails the frame check and is re-encoded. **V8** vg.mkv
  (gaps): the same.

`--mutant NAME` builds the probe over a copy of app/Sources with one text
replaced, exactly once, and must fail exactly `EXPECTED[NAME]` (then MUTANT
PASS, exit 0): `no-original` (the conversion records none), `recopy-ffmpeg`
(the re-copy on open goes through the whole import funnel), `vp9-encode`
(no VP9 profile is copied), `no-fallback` (no second attempt), `no-snap`
(the copy is not snapped: T1–T3 fail ON THE COUNT) and `no-check` (the frame
check always answers true). Exit 2 when the control could not be performed.
"""

import argparse
import atexit
import json
import os
import shutil
import stat
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(HERE, "graphics_spike"))
import bounded  # noqa: E402

WORK = os.path.join(HERE, "work", "ffmpeg-rewrap")
BUILD = os.path.join(HERE, "work", "ffmpeg-rewrap-build")
HOME = os.path.join(WORK, "home")
SOURCES = os.path.join(ROOT, "app", "Sources")
PROBE_SWIFT = os.path.join(HERE, "ffmpeg_rewrap_probe.swift")
LIB = os.path.join(ROOT, "core", "target", "release", "libreelcut_core.a")
WALL_BUILD, WALL_RUN, WALL_FFMPEG = 900, 900, 120
ROWS = ["F0", "O1", "O2", "O3", "O4", "O5", "T1", "T2", "T3",
        "V1", "V2", "V3", "V4", "V5", "V6", "V7", "V8"]

# name: (file in app/Sources, before — exactly once, after)
MUTANTS = {
    "no-original": ("MediaImporter+Probe.swift",
                    "descriptor.original = MediaOriginal(of: url)", "_ = url"),
    "recopy-ffmpeg": ("ProjectDocument+MissingCopies.swift",
                      "try? MediaImporter.probeBuiltInCopy(of: source, watch: shown)",
                      "try? MediaImporter.probeBlocking(url: source)"),
    "vp9-encode": ("FFmpegRewrap+Plan.swift", "vp9CopyProfiles: Set<Int> = [0, 2]",
                   "vp9CopyProfiles: Set<Int> = []"),
    "no-fallback": ("MediaImporter+Probe.swift",
                    "try FFmpegRewrap.assist(url, mayAsk: mayAsk, reencodingVP9: true)",
                    "nil as URL?"),
    "no-snap": ("FFmpegRewrap+Plan.swift",
                'args += ["-bsf:v", "setts=time_base=\\(rate.den)/\\(rate.num):prescale=1"]',
                "_ = rate"),
    "no-check": ("FFmpegRewrap.swift",
                 "let exact = !plan.copiesVP9 || keepsFrameGrid(partial, of: plan, with: tools)",
                 "let exact = true"),
}

# The rows each mutant must fail, and only those: what a run printed
# (2026-10-03; the proof README's B80 section has each run). `no-original`
# also fails O5 (with no original there is nothing to re-copy from) and the
# four fallback rows, which import with an original. `vp9-encode` also fails
# V4, V5, V7 and V8: with no copy tried there is one run, not two. `no-snap`
# fails T1–T3 on the count and V1, V2 and V6 on `vp09`: the frame check
# sends each unsnapped copy to the re-encode.
EXPECTED = {
    "no-original": {"O1", "O2", "O3", "O5", "V4", "V5", "V7", "V8"},
    "recopy-ffmpeg": {"O4"},
    "vp9-encode": {"T1", "T2", "T3", "V1", "V2", "V4", "V5", "V6", "V7", "V8"},
    "no-fallback": {"V4", "V5", "V7", "V8"},
    "no-snap": {"T1", "T2", "T3", "V1", "V2", "V6"},
    "no-check": {"V7", "V8"},
}

WRAPPER = '''#!{python}
import json
import os
import sys

WORK = {work!r}
REAL = {real!r}
argv = sys.argv[1:]
with open(os.path.join(WORK, "ffmpeg.log"), "a", encoding="utf-8") as log:
    log.write(json.dumps(argv) + "\\n")
try:
    with open(os.path.join(WORK, "mode"), encoding="utf-8") as stream:
        mode = stream.read().strip()
except OSError:
    mode = "pass"
copies = any(argv[i] == "-f" and argv[i + 1] == "mp4" for i in range(len(argv) - 1))
if copies and mode == "fail-copy":
    sys.exit(1)
if copies and mode == "swap-copy" and "-i" in argv[:-1]:
    argv[argv.index("-i") + 1] = os.path.join(WORK, "p1.ivf")
os.execv(REAL, [REAL] + argv)
'''


def child_env(scratch_home):
    env = bounded.child_env()
    env.pop("ANTHROPIC_API_KEY", None)
    if scratch_home:
        env["CFFIXED_USER_HOME"] = HOME
    return env


def run(argv, seconds, cwd=None, scratch_home=False):
    """A bounded child. Only the probe runs with the scratch home: swiftc and
    ffmpeg keep the caller's."""
    return bounded.run(argv, seconds, cwd=cwd, env=child_env(scratch_home))


def remove_work():
    shutil.rmtree(WORK, ignore_errors=True)


def make_wrapper(real):
    """`<work>/tools/ffmpeg`, with `real` baked in; its path."""
    folder = os.path.join(WORK, "tools")
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, "ffmpeg")
    with open(path, "w", encoding="utf-8") as stream:
        stream.write(WRAPPER.format(python=sys.executable, work=WORK, real=real))
    os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    with open(os.path.join(WORK, "mode"), "w", encoding="utf-8") as stream:
        stream.write("pass")
    return path


def video_packets(path):
    counted = run(["ffprobe", "-v", "error", "-count_packets", "-select_streams", "v:0",
                   "-show_entries", "stream=nb_read_packets", "-of", "csv=p=0", path], WALL_FFMPEG)
    try:
        return int(counted["stdout"].strip().strip(","))
    except ValueError:
        return -1


def make_fixtures(real):
    """None, or the reason a fixture could not be made (exit 2)."""
    def picture(rate):
        return ["-f", "lavfi", "-i", f"testsrc2=size=128x72:rate={rate}"]
    sound = ["-f", "lavfi", "-i", "sine=frequency=440:duration=1"]
    vp9 = ["-frames:v", "30", "-c:v", "libvpx-vp9"]
    head = [real, "-y", "-v", "error"]
    recipes = [
        ("v0.mkv", head + picture("30") + sound + vp9 + ["-pix_fmt", "yuv420p", "-c:a", "flac"]),
        ("v2.mkv", head + picture("30") + sound + vp9
         + ["-pix_fmt", "yuv420p10le", "-profile:v", "2", "-c:a", "flac"]),
        ("vn.mkv", head + picture("30000/1001") + sound + vp9
         + ["-pix_fmt", "yuv420p", "-c:a", "flac"]),
        ("vj.mkv", head + ["-i", os.path.join(WORK, "v0.mkv"), "-c", "copy",
                           "-bsf:v", "setts=ts=TS+mod(N\\,3)*9"]),
        ("vg.mkv", head + picture("30") + sound
         + ["-vf", "select=not(eq(mod(n\\,5)\\,2))", "-fps_mode", "vfr"] + vp9
         + ["-pix_fmt", "yuv420p", "-c:a", "flac"]),
        ("p1.ivf", head + picture("30") + vp9 + ["-pix_fmt", "yuv444p", "-profile:v", "1"]),
    ]
    for name, argv in recipes:
        path = os.path.join(WORK, name)
        made = run(argv + [path], WALL_FFMPEG)
        if made["rc"] or made["expired"] or not os.path.exists(path):
            return f"{name} was not made: " + (
                "ffmpeg expired" if made["expired"] else made["stderr"].strip()[-300:])
        packets = video_packets(path)
        if packets != 30:
            return f"{name} holds {packets} video packets, not 30"
    for name in ("v0a.mkv", "v0b.mkv", "v0c.mkv"):
        shutil.copyfile(os.path.join(WORK, "v0.mkv"), os.path.join(WORK, name))
    return None


def mutant_sources(name):
    """(a copy of app/Sources with the mutant's text replaced once, None), or
    (None, reason)."""
    file, before, after = MUTANTS[name]
    target = os.path.join(BUILD, "mutants", name, "Sources")
    shutil.rmtree(target, ignore_errors=True)
    try:
        os.makedirs(target)
        for entry in sorted(os.listdir(SOURCES)):
            if entry.endswith(".swift"):
                shutil.copy2(os.path.join(SOURCES, entry), os.path.join(target, entry))
        path = os.path.join(target, file)
        with open(path, encoding="utf-8") as stream:
            text = stream.read()
        count = text.count(before)
        if count != 1:
            return None, f"{file} holds {before!r} {count} times, not once"
        with open(path, "w", encoding="utf-8") as stream:
            stream.write(text.replace(before, after))
    except OSError as error:
        return None, f"the copy could not be made: {error}"
    return target, None


def build_probe(sources, probe_dir):
    """(binary, None) or (None, reason). Rebuilt only when stale."""
    os.makedirs(probe_dir, exist_ok=True)
    binary = os.path.join(probe_dir, "ffmpeg_rewrap_probe")
    entry = os.path.join(probe_dir, "main.swift")
    with open(PROBE_SWIFT, encoding="utf-8") as stream:
        source = stream.read()
    if not os.path.exists(entry) or open(entry, encoding="utf-8").read() != source:
        with open(entry, "w", encoding="utf-8") as stream:
            stream.write(source)
    for name in ("Fonts", "Models"):
        src = os.path.join(ROOT, "app", "Resources", name)
        dst = os.path.join(probe_dir, name)
        if not os.path.isdir(dst) or os.path.getmtime(src) > os.path.getmtime(dst):
            shutil.rmtree(dst, ignore_errors=True)
            shutil.copytree(src, dst)
    if not os.path.exists(LIB):
        return None, f"{LIB} is missing — run `make rust` first"
    swift = sorted(os.path.join(sources, n) for n in os.listdir(sources)
                   if n.endswith(".swift") and n != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    stamp = os.path.join(probe_dir, "sources.txt")
    listing = "\n".join(swift)
    same_set = os.path.exists(stamp) and open(stamp, encoding="utf-8").read() == listing
    headers = [os.path.join(ROOT, "app", "Bridging", "Reelcut-Bridging-Header.h"),
               os.path.join(ROOT, "core", "include", "reelcut_core.h")]
    if same_set and os.path.exists(binary) and all(
            os.path.getmtime(f) < os.path.getmtime(binary)
            for f in swift + [entry, LIB, os.path.abspath(__file__)] + headers):
        print(f"probe: {binary} (up to date)", flush=True)
        return binary, None
    sdk = run(["xcrun", "--show-sdk-path", "--sdk", "macosx"], 60)["stdout"].strip()
    if os.path.exists(binary):
        os.remove(binary)
    print(f"probe: building over {len(swift)} sources (up to {WALL_BUILD} s)…", flush=True)
    started = time.time()
    built = run(["swiftc", "-D", "REELCUT_DEV_TOOLS", "-sdk", sdk,
                 "-target", "arm64-apple-macos26.0", "-module-name", "Reelcut",
                 "-import-objc-header", headers[0],
                 "-L", os.path.dirname(LIB), "-lreelcut_core"] + swift + [entry, "-o", binary],
                WALL_BUILD)
    if built["rc"] != 0 or not os.path.exists(binary):
        errors = [line for line in built["stderr"].splitlines() if ": error:" in line]
        tail = [line for line in built["stderr"].strip().splitlines()[-4:] if line.strip()]
        return None, (f"swiftc exited {built['rc']} (expired {built['expired']}): "
                      + " | ".join(errors[:6] or tail or ["(no output)"]))
    with open(stamp, "w", encoding="utf-8") as stream:
        stream.write(listing)
    print(f"probe: built in {time.time() - started:.0f} s", flush=True)
    return binary, None


def run_probe(binary, wrapper):
    """(answer, None) or (None, reason)."""
    ran = run([binary, WORK, HOME, "-RCFFmpegImport", "always", "-RCFFmpegPath", wrapper],
              WALL_RUN, cwd=os.path.dirname(binary), scratch_home=True)
    if ran["expired"]:
        return None, f"the probe ran past {WALL_RUN} s and was killed"
    for line in ran["stdout"].splitlines():
        if line.startswith("ANSWER "):
            return json.loads(line[len("ANSWER "):]), None
    return None, f"no answer (exit {ran['rc']}): {ran['stderr'].strip()[-400:]}"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()

    results = []

    def row(row_id, ok, detail):
        results.append((row_id, bool(ok)))
        print(("  ok   " if ok else "  FAIL ") + f"{row_id} {detail}", flush=True)

    remove_work()
    atexit.register(remove_work)
    real = shutil.which("ffmpeg")
    if real is None or shutil.which("ffprobe") is None:
        print("instrument failure: ffmpeg and ffprobe are not both on the PATH")
        return 2
    real = os.path.realpath(real)

    sources, probe_dir = SOURCES, os.path.join(BUILD, "probe")
    if args.mutant:
        sources, why = mutant_sources(args.mutant)
        if sources is None:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
        probe_dir = os.path.join(BUILD, "mutants", args.mutant, "probe")
    binary, why = build_probe(sources, probe_dir)
    if binary is None:
        if args.mutant:
            print(f"mutant {args.mutant}: the control could not be performed — the probe "
                  f"did not build: {why}")
            return 2
        row("F0", False, f"the probe builds from {sources}: {why}")
        print("passed 0/1")
        return 1

    os.makedirs(os.path.join(HOME, "Library", "Application Support"))
    wrapper = make_wrapper(real)
    why = make_fixtures(real)
    if why is not None:
        print(f"instrument failure: {why}")
        return 2
    print(f"fixtures: v0, v2, vn, vj, vg (.mkv) and p1.ivf, 30 video packets each; the real "
          f"ffmpeg is {real}; scratch home {HOME}", flush=True)

    answer, why = run_probe(binary, wrapper)
    got = {r["id"]: r for r in (answer or {}).get("rows", [])}
    if answer is None and args.mutant:
        print(f"mutant {args.mutant}: the control could not be performed — {why}")
        return 2
    f0 = got.get("F0")
    if f0 is None:
        row("F0", False, f"the probe built; no F0 row: {why or 'the probe did not answer it'}")
    else:
        row("F0", f0["ok"], "the probe built; " + f0["detail"])
    for row_id in ROWS[1:]:
        r = got.get(row_id)
        if r is None:
            unrun = f0 is None or not f0["ok"]
            row(row_id, False, "not run: " + ((why or "F0 failed") if unrun
                                             else "the probe did not answer it"))
        else:
            row(row_id, r["ok"], r["detail"])
    if answer is not None:
        print("measure: " + json.dumps(answer.get("measure", {}), sort_keys=True), flush=True)

    failed = {row_id for row_id, ok in results if not ok}
    print(f"passed {len(results) - len(failed)}/{len(results)}")
    if not args.mutant:
        return 1 if failed else 0
    expected = EXPECTED[args.mutant]
    verdict = "MUTANT PASS" if failed == expected else "MUTANT FAIL"
    print(f"{verdict}: {args.mutant} failed {sorted(failed)}, expected {sorted(expected)}")
    return 0 if failed == expected else 1


if __name__ == "__main__":
    sys.exit(main())
