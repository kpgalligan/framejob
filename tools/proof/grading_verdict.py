#!/usr/bin/env python3
"""Road map "grading" GR7a — the scripted half of the verdict: every "What it
may cost" cap in `archive/grading.md` ("Worth keeping") measured for the
`grading` branch against main at the branch point `BASE`, and T4's script half.
It writes no verdict; a RECORD row prints `cap held` or `cap missed by X` and
never changes the exit status.

    python3 tools/proof/grading_verdict.py sizes [--mutant shader-not-counted]
    python3 tools/proof/grading_verdict.py main-tree make      # worktree of BASE under work/gr7/main; `make app` there
    python3 tools/proof/grading_verdict.py main-tree remove    # tree_copy.remove_tree + git worktree prune
    RC_PROOF_APP=release python3 tools/proof/grading_verdict.py measure [--main BINARY]
        [--only H0,M1,G0,E1,E2,F4,T4,Z1] [--rounds 3] [--seconds 60] [--lut PATH]
        [--mutant lut-not-applied|graded-fixture-ungraded|menus-same-app]

**sizes** (git only, no app; every command runs in this worktree; writes
`work/gr7/sizes.json`): L1 numstat over `PRODUCT` (app code, core code, the shaders), per
root and in total, and per first-parent commit in BASE..HEAD, as a record only
(no feature has a size budget: root CLAUDE.md); the header's net printed beside
the total. L2 the frozen files at BASE and HEAD.
L3 every changed `.swift`/`.rs` under `app/Sources` or `core/src` that is new
and over 400 lines or over 600, "unpaid" when it grew outside `EXEMPT` and
`FROZEN` (a frozen file is L2's). L4 `ClipSubTab`'s cases and each case's
`…Section(` calls in `ClipPane.makeSections()`, at BASE and HEAD.

**measure** (release-only: it times exports and reads the compositor's frame
times). Each instance runs under the scratch `CFFIXED_USER_HOME`
`work/gr7/run/home`, performs no menu item (M1 reads the listing only), and is
stopped by its own pid. Main's build (`--main`, default the throwaway
worktree's Release binary) is resolved, freshness-checked and launched only
when M1, E1 or E2 is selected. The movie `work/gr7/media/testsrc2_1080_10s.mp4`
is made through `bt709_fixture.make` (issue #292): `setparams` on its input
and the tags on its output, kept — a cached movie too — only when ffprobe
reads bt709 ×3 and its first frame reads back against its own graph, so a
movie tagged on the output only is refused and made again (a second refusal
is an instrument failure, Z1's FAIL). H0 the host gate (`grading_spike.host_gate`);
M1 the menu listings of main's and the branch's instances; G0 fixture G
renders more than 8 levels away from fixture U and holds one adjustment clip;
E1/E2 the ungraded export against main's and the graded against the
ungraded, rounds alternating (mU, bU, bG) then (bG, bU, mU); F4 four graded
full-frame layers and one adjustment clip at 1080p, the compositor's
120-frame windows against 8 ms; T4 a frame through `work/gr7/luts/
gr7-camera-33.cube` in Frame Job against ffmpeg's `lut3d` within ±2, with the
CONTROL T4c; Z1 every project closes and no log holds `Frame Job: `. Exit 0 when
every scored row passes, 1 when one fails, 2 when H0 is shut.

Mutants (each edits this driver's own behaviour): `shader-not-counted` drops
the shader root from `PRODUCT` (must fail L1); `lut-not-applied` skips the look
(T4); `graded-fixture-ungraded` drops every clip's grade and the adjustment
clip's colour, keeping the clip (G0); `menus-same-app` reads the branch
listing from main's instance (M1). README: `tools/proof/README.md`, "Road map
grading — GR7a, the verdict's figures".
"""

import argparse
import datetime
import json
import re
import statistics
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
sys.path.insert(0, str(HERE / "grading_spike"))
import bounded  # noqa: E402
import bt709_fixture  # noqa: E402
import grading_spike  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402

BASE = "f407f87"
PRODUCT = ("app/Sources", "core/src", "app/Resources/Shaders")
HEADER = ("core/include",)
FROZEN = ("app/Sources/EditorViewController.swift", "app/Sources/TimelineView.swift",
          "app/Sources/PreviewCanvasView.swift", "app/Sources/AgentServer.swift",
          "app/Sources/InspectorViewController.swift")
EXEMPT = ("core/src/edit.rs", "app/Sources/ReelOps.swift")
SHADER_FILE = "app/Resources/Shaders/Compositor.metal"
FROZEN_CAP = 50
FILE_CAP = 600
NEW_FILE_CAP = 400
EXPORT_CAP = 0.02
GRADED_EXPORT_CAP = 0.10
FRAME_BUDGET_MS = 8.0
T4_LEVELS = 2
F4_EXPORTS = 3
G0_LEVELS = 8

WORK = HERE / "work/gr7"
MAIN_TREE = WORK / "main"
# BASE predates rename R1 (spec §11 NM-3): the main tree builds the old product, writes
# the old log prefixes and reads the old launch argument, and its documents are `.reelcut`.
MAIN_BINARY = MAIN_TREE / "build/Build/Products/Release/Reelcut.app/Contents/MacOS/Reelcut"
OLD_NAMED = set()   # the main binaries in use (`measure`), whose documents are `.reelcut`
RUN = WORK / "run"
HOME = RUN / "home"
MEDIA = WORK / "media"
LUTS = WORK / "luts"
MOVIE = MEDIA / "testsrc2_1080_10s.mp4"
CUBE = LUTS / "gr7-camera-33.cube"
MOVIE_SECONDS = 10
F_SECONDS = 20
SEC = 600_000
T = SEC // 2
CALL_BOUND = 600
BUILD_BOUND = 1500
WIDTH, HEIGHT = 1920, 1080
# GR0's ST, the spike's toned scene.
TONE = {"exposure": 0.5, "temperature": 0.2, "tint": -0.1, "highlights": -0.2,
        "shadows": 0.2, "whites": 0.1, "blacks": -0.1, "vibrance": 0.2, "fade": 0.1}
F_LOOKS = ("warm", "cool", "teal_orange", "vivid")
TIMING = re.compile(r"\[(?:reelcut|framejob)\] compositor: ([\d.]+) ms average, ([\d.]+) ms worst")
RELEASE_ONLY = "GR7a times exports and reads the compositor's frame times"
MENU_PATHS = ("View ▸ Show Ungraded", "View ▸ Scopes", "Insert ▸ Adjustment Clip",
              "Clip ▸ Look ▸ Warm")
MENU_CAP_GROUPS = ("Clip ▸ Look", "Insert ▸ Adjustment Clip", "View ▸ Show Ungraded",
                   "View ▸ Scopes")
MEASURE_ROWS = ("H0", "M1", "G0", "E1", "E2", "F4", "T4", "Z1")
SIZES_MUTANTS = ("shader-not-counted",)
MEASURE_MUTANTS = ("lut-not-applied", "graded-fixture-ungraded", "menus-same-app")

# ---- rows (grading_spike's emit) ------------------------------------------------

ROWS = []


def emit(row, verdict, detail):
    """verdict: PASS, FAIL (scored), SKIP (named), CONTROL or RECORD (figures)."""
    ROWS.append({"row": row, "verdict": verdict, "detail": detail})
    print(f"{row:<6} {verdict:<8} {detail}", flush=True)


def cap_text(value, cap, unit=""):
    return "cap held" if value <= cap else f"cap missed by {value - cap:g}{unit}"


def finish(tag, mutant, extra_exit=None):
    failed = sorted({r["row"] for r in ROWS if r["verdict"] == "FAIL"})
    code = extra_exit if extra_exit is not None else (1 if failed else 0)
    if mutant:
        print(f"mutant {mutant}: {'killed by ' + ', '.join(failed) if failed else 'SURVIVED'}",
              flush=True)
    print(f"grading_verdict {tag}: "
          f"{'all scored rows pass' if not failed else 'FAILED ' + ', '.join(failed)}"
          f"{'; STOP: the host gate is shut' if code == 2 else ''}", flush=True)
    return code


# ---- git -------------------------------------------------------------------------

class GitError(RuntimeError):
    pass


def git(*args, seconds=120):
    ran = bounded.run(["git", "-C", str(ROOT), *args], seconds)
    if ran["expired"] or ran["rc"] != 0:
        raise GitError(f"git {' '.join(args)}: rc {ran['rc']}, expired {ran['expired']}: "
                       f"{ran['stderr'].strip()[-300:]}")
    return ran["stdout"]


def numstat(base: str, head: str, paths: tuple) -> list:
    """`git diff --numstat --no-renames base head -- paths` as (added,
    deleted, path); a binary file's `-` counts 0. No rename detection, so a
    moved file is its old path deleted and its new path added, each a path
    `git show` can read."""
    rows = []
    for line in git("diff", "--numstat", "--no-renames", base, head, "--",
                    *paths).splitlines():
        parts = line.split("\t")
        if len(parts) != 3:
            continue
        added, deleted, path = parts
        rows.append((int(added) if added.isdigit() else 0,
                     int(deleted) if deleted.isdigit() else 0, path))
    return rows


def lines_at(commit: str, path: str):
    """The line count of `path` at `commit`, or None when it is absent there."""
    ran = bounded.run(["git", "-C", str(ROOT), "show", f"{commit}:{path}"], 120)
    if ran["expired"] or ran["rc"] != 0:
        return None
    return ran["stdout"].count("\n")


def show(commit, path):
    return git("show", f"{commit}:{path}")


def sub_tabs(commit: str) -> list:
    """`ClipSubTab`'s cases at `commit`, in order (`ClipPinnedBlock.swift`)."""
    text = show(commit, "app/Sources/ClipPinnedBlock.swift")
    found = re.search(r"enum ClipSubTab\b[^{]*\{\s*case ([\w, ]+)\n", text)
    if not found:
        raise GitError(f"no `enum ClipSubTab … case …` line at {commit}")
    return [name.strip() for name in found.group(1).split(",") if name.strip()]


def tab_sections(commit: str) -> dict:
    """Each `case .X:` of `ClipPane.makeSections()`'s switch at `commit`, with
    the `…Section(` calls in its block, in order, each once."""
    text = show(commit, "app/Sources/ClipPane.swift")
    start = text.find("func makeSections() -> [InspectorSection] {")
    if start < 0:
        raise GitError(f"no `makeSections()` in ClipPane.swift at {commit}")
    end = text.find("\n    }\n", start)
    body = text[start:end if end > 0 else len(text)]
    switch = body.find("switch activeSubTab {")
    if switch < 0:
        raise GitError(f"no `switch activeSubTab` in makeSections() at {commit}")
    body = body[switch:]
    cases = list(re.finditer(r"^        case \.(\w+):", body, re.M))
    sections = {}
    for index, case in enumerate(cases):
        block = body[case.end():cases[index + 1].start() if index + 1 < len(cases) else len(body)]
        names = []
        for name in re.findall(r"\b(\w+Section)\(", block):
            if name not in names:
                names.append(name)
        sections[case.group(1)] = names
    return sections


def phase_of(subject):
    found = re.search(r"\(grading (GR\w+)\)", subject)
    return found.group(1) if found else ("merge" if subject.startswith("Merge") else "?")


# ---- sizes ---------------------------------------------------------------------------

def sizes(mutant):
    capped = tuple(r for r in PRODUCT if not (mutant == "shader-not-counted"
                                            and r == "app/Resources/Shaders"))
    head = git("rev-parse", "--short", "HEAD").strip()
    print(f"grading_verdict sizes at {datetime.datetime.now().astimezone():%Y-%m-%d %H:%M %Z}: "
          f"BASE {BASE}, HEAD {head}; PRODUCT {capped}", flush=True)
    result = {"base": BASE, "head": head, "capped": capped, "header": HEADER}

    # L1
    rows = numstat(BASE, "HEAD", capped)
    roots = {}
    for root in capped:
        mine = [r for r in rows if r[2].startswith(root + "/")]
        roots[root] = {"added": sum(r[0] for r in mine), "deleted": sum(r[1] for r in mine),
                       "files": len(mine)}
        roots[root]["net"] = roots[root]["added"] - roots[root]["deleted"]
    total = {k: sum(v[k] for v in roots.values()) for k in ("added", "deleted", "net", "files")}
    header_rows = numstat(BASE, "HEAD", HEADER)
    header = {"added": sum(r[0] for r in header_rows), "deleted": sum(r[1] for r in header_rows)}
    header["net"] = header["added"] - header["deleted"]
    commits = []
    for commit in git("rev-list", "--first-parent", f"{BASE}..HEAD").split():
        subject = git("log", "-1", "--format=%s", commit).strip()
        mine = numstat(f"{commit}^1", commit, capped)
        added, deleted = sum(r[0] for r in mine), sum(r[1] for r in mine)
        commits.append({"commit": commit[:7], "phase": phase_of(subject), "added": added,
                        "deleted": deleted, "net": added - deleted})
    commits.reverse()
    listed = {r[2] for r in rows}
    contributes = all(roots[r]["files"] > 0 for r in PRODUCT if r in roots) and \
        all(r in roots for r in PRODUCT)
    shader_listed = SHADER_FILE in listed
    ok = contributes and shader_listed
    counts = ", ".join(f"{r} {v['files']} files" for r, v in roots.items())
    emit("L1", "PASS" if ok else "FAIL",
         f"numstat {BASE}..{head} over {', '.join(capped)}: every PRODUCT root contributes "
         f"{contributes} ({counts}); {SHADER_FILE} listed {shader_listed}")
    for root, v in roots.items():
        emit("L1", "RECORD", f"{root}: +{v['added']} −{v['deleted']}, net {v['net']} "
             f"({v['files']} files)")
    emit("L1", "RECORD", f"PRODUCT total +{total['added']} −{total['deleted']}, net "
         f"{total['net']} (a record: no feature has a size budget)")
    emit("L1", "RECORD", f"beside it, outside it and never capped: {HEADER[0]} "
         f"+{header['added']} −{header['deleted']}, net {header['net']}")
    for c in commits:
        emit("L1", "RECORD", f"{c['phase']} {c['commit']}: +{c['added']} −{c['deleted']}, "
             f"net {c['net']} (against its first parent)")
    result["L1"] = {"roots": roots, "total": total, "header": header, "commits": commits,
                    "files": [{"path": p, "added": a, "deleted": d} for a, d, p in rows]}

    # L2
    frozen = []
    for path in FROZEN:
        base, now = lines_at(BASE, path), lines_at("HEAD", path)
        mine = [r for r in numstat(BASE, "HEAD", (path,))]
        added, deleted = sum(r[0] for r in mine), sum(r[1] for r in mine)
        frozen.append({"path": path, "base": base, "head": now, "added": added,
                       "deleted": deleted, "net": added - deleted})
    read = all(f["base"] is not None and f["head"] is not None for f in frozen)
    together = sum(f["net"] for f in frozen)
    emit("L2", "PASS" if read else "FAIL",
         f"{len(FROZEN)} frozen files read at {BASE} and {head}: {read}; together net {together}")
    for f in frozen:
        emit("L2", "RECORD", f"{f['path']}: {f['base']} → {f['head']} (+{f['added']} "
             f"−{f['deleted']}, net {f['net']}) against ~{FROZEN_CAP}: "
             f"{cap_text(f['net'], FROZEN_CAP, ' lines')}")
    result["L2"] = {"files": frozen, "together": together}

    # L3
    changed = [(a, p) for a, _, p in numstat(BASE, "HEAD", ("app/Sources", "core/src"))
               if p.endswith((".swift", ".rs"))]
    over, unreadable = [], []
    for added, path in changed:
        base, now = lines_at(BASE, path), lines_at("HEAD", path)
        if now is None:
            if added == 0 and base is not None:
                continue        # deleted on the branch
            unreadable.append(path)
            continue
        new = base is None
        if not ((new and now > NEW_FILE_CAP) or now > FILE_CAP):
            continue
        net = now - (base or 0)
        if path in FROZEN:
            verdict = "frozen: see L2"
        elif path in EXEMPT:
            verdict = "exempt (a table, one row per op)"
        elif net > 0:
            verdict = "unpaid"
        else:
            verdict = "paid (net ≤ 0)"
        over.append({"path": path, "base": base, "head": now, "net": net, "new": new,
                     "verdict": verdict})
    unpaid = [o for o in over if o["verdict"] == "unpaid"]
    emit("L3", "PASS" if not unreadable else "FAIL",
         f"{len(changed)} changed .swift/.rs files under app/Sources and core/src read; "
         f"{len(over)} listed (new and over {NEW_FILE_CAP}, or over {FILE_CAP})"
         f"{'; unreadable at HEAD: ' + ', '.join(unreadable) if unreadable else ''}")
    for o in over:
        emit("L3", "RECORD", f"{o['path']}: {'new' if o['new'] else o['base']} → {o['head']} "
             f"(net {o['net']:+d}){' new file' if o['new'] else ''}: {o['verdict']}")
    emit("L3", "RECORD", f"{len(unpaid)} unpaid against none: {cap_text(len(unpaid), 0, ' files')}")
    result["L3"] = {"over": over, "unpaid": [o["path"] for o in unpaid]}

    # L4
    try:
        tabs = {c: sub_tabs(c) for c in (BASE, "HEAD")}
        sections = {c: tab_sections(c) for c in (BASE, "HEAD")}
        parsed = all(set(tabs[c]) == set(sections[c]) for c in tabs)
        why = "" if parsed else f"; cases {tabs} against switch arms { {c: list(s) for c, s in sections.items()} }"
    except GitError as error:
        tabs, sections, parsed, why = {}, {}, False, f"; {error}"
    emit("L4", "PASS" if parsed else "FAIL",
         f"ClipSubTab's cases and makeSections()'s arms read at {BASE} and {head}{why}")
    if parsed:
        added = [t for t in tabs["HEAD"] if t not in tabs[BASE]]
        removed = [t for t in tabs[BASE] if t not in tabs["HEAD"]]
        color = sections["HEAD"].get("color", [])
        lost = [s for s in sections[BASE]["picture"] if s not in sections["HEAD"]["picture"]]
        gained = [s for s in sections["HEAD"]["picture"] if s not in sections[BASE]["picture"]]
        tab_ok = added == ["color"] and not removed
        emit("L4", "RECORD", f"sub-tabs {tabs[BASE]} → {tabs['HEAD']}: added {added}, removed "
             f"{removed} against one new (Color): "
             f"{'cap held' if tab_ok else 'cap missed by ' + str(len(added) + len(removed) - 1) + ' sub-tabs'}")
        emit("L4", "RECORD", f"Color's sections {color}: {len(color)} against ≤ 4: "
             f"{cap_text(len(color), 4, ' sections')}")
        picture_ok = lost == ["colorSection"] and not gained
        emit("L4", "RECORD", f"Picture lost {lost} and gained {gained} against lost Color and "
             f"gained none: {'cap held' if picture_ok else 'cap missed'}")
        result["L4"] = {"tabs": tabs, "sections": sections, "added": added, "removed": removed,
                        "color": color, "picture_lost": lost, "picture_gained": gained}
    result["rows"] = ROWS
    WORK.mkdir(parents=True, exist_ok=True)
    out = WORK / ("sizes.json" if not mutant else f"sizes-mutant-{mutant}.json")
    out.write_text(json.dumps(result, indent=1, sort_keys=True))
    print(f"wrote {out.relative_to(ROOT)}", flush=True)
    return finish("sizes", mutant)


# ---- main's throwaway worktree ---------------------------------------------------------

def main_tree(action):
    if action == "make":
        if MAIN_TREE.exists():
            print(f"refusing: {MAIN_TREE.relative_to(ROOT)} exists; `main-tree remove` it first")
            return 1
        WORK.mkdir(parents=True, exist_ok=True)
        added = bounded.run(["git", "-C", str(ROOT), "worktree", "add", "--detach",
                             str(MAIN_TREE), BASE], 300)
        print(f"git worktree add --detach {MAIN_TREE.relative_to(ROOT)} {BASE}: rc {added['rc']}"
              f"{' (expired)' if added['expired'] else ''} {added['stderr'].strip()[-300:]}",
              flush=True)
        if added["rc"] != 0 or added["expired"]:
            return 1
        print(f"make app in {MAIN_TREE} (a cold build, bound {BUILD_BOUND} s); load before "
              f"{grading_spike.load()}", flush=True)
        built = bounded.run(["make", "app"], BUILD_BOUND, cwd=str(MAIN_TREE))
        app = MAIN_BINARY.parents[2]
        ok = built["rc"] == 0 and not built["expired"] and MAIN_BINARY.exists()
        if not ok:
            output = built["stdout"] + built["stderr"]
            errors = [line for line in output.splitlines() if "error:" in line]
            print("\n".join(errors[:8]) or output[-1500:])
        print(f"main-tree make: {'built' if ok else 'FAILED'} {app} in {built['seconds']:.0f} s "
              f"(rc {built['rc']}, expired {built['expired']}); load after {grading_spike.load()}",
              flush=True)
        return 0 if ok else 1
    tree_copy.remove_tree(str(MAIN_TREE))
    pruned = bounded.run(["git", "-C", str(ROOT), "worktree", "prune"], 120)
    listed = bounded.run(["git", "-C", str(ROOT), "worktree", "list"], 120)
    print(f"main-tree remove: {MAIN_TREE.relative_to(ROOT)} exists {MAIN_TREE.exists()}; "
          f"git worktree prune rc {pruned['rc']}\n{listed['stdout']}", flush=True)
    gone = not MAIN_TREE.exists() and str(MAIN_TREE) not in listed["stdout"]
    return 0 if gone and pruned["rc"] == 0 else 1


# ---- media and the LUT ----------------------------------------------------------------

def make_movie():
    """MOVIE through `bt709_fixture.make` (issue #292), or None."""
    made, why = bt709_fixture.make(
        MOVIE, ["-f", "lavfi", "-i", f"testsrc2=size={WIDTH}x{HEIGHT}:rate=30:"
                f"duration={MOVIE_SECONDS},{bt709_fixture.SETPARAMS}"],
        ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18"],
        {"codec_name": "h264", "pix_fmt": "yuv420p", "width": WIDTH, "height": HEIGHT},
        "yuv420p", 600)
    if made is None:
        print(f"instrument failure: {why}")
    return made


def camera(r, g, b):
    """GR7a's test LUT, textbook maths only (the Concat rule): a smoothstep
    S-curve mixed in at 0.5, gains (1.06, 1.0, 0.92), saturation 1.2 about the
    Rec. 709 luma, then a clamp to [0, 1]."""
    def curve(v):
        return 0.5 * v + 0.5 * (v * v * (3 - 2 * v))
    c = [curve(r) * 1.06, curve(g) * 1.0, curve(b) * 0.92]
    luma = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
    return tuple(min(max(luma + 1.2 * (v - luma), 0.0), 1.0) for v in c)


def write_cube(path: Path, size: int) -> Path:
    """A `.cube` of side `size`, red fastest (lut_proof's `cube_text` order)."""
    step = size - 1
    lines = [f"TITLE \"GR7a camera {size}\"", f"LUT_3D_SIZE {size}"]
    for b in range(size):
        for g in range(size):
            for r in range(size):
                lines.append(" ".join(f"{v:.6f}" for v in camera(r / step, g / step, b / step)))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n")
    return path


def decode_rgb(path):
    """`path`'s first frame as rgb24 bytes, or None (bounded.run; the raw frame
    goes to a scratch file beside `path`, since bounded.run's pipes are text)."""
    raw_path = Path(path).with_suffix(".rgb")
    made = bounded.run(["ffmpeg", "-nostdin", "-y", "-v", "error", "-i", str(path),
                        "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24",
                        str(raw_path)], 300)
    try:
        raw = raw_path.read_bytes() if made["rc"] == 0 and not made["expired"] else None
    except OSError:
        raw = None
    raw_path.unlink(missing_ok=True)
    return raw if raw and len(raw) == WIDTH * HEIGHT * 3 else None


def max_delta(a, b):
    """(max |Δ| over every pixel and channel, the byte index where it is)."""
    worst, at = 0, 0
    for index, (x, y) in enumerate(zip(a, b)):
        d = x - y if x > y else y - x
        if d > worst:
            worst, at = d, index
    return worst, at


def where(index):
    pixel = index // 3
    return f"({pixel % WIDTH}, {pixel // WIDTH}) channel {'rgb'[index % 3]}"


def load():
    return grading_spike.load()


# ---- the project (precision_proof's `Doc`'s shape) -----------------------------------------

def attempt(client, tool, arguments):
    """One MCP call; a refusal is an answer, and so is an expiry."""
    try:
        return {"ok": True, "reply": client.call_with(tool, arguments)}
    except mcp.ToolError as error:
        return {"ok": False, "error": str(error)}
    except Exception as error:  # a socket timeout is the expiry
        return {"ok": False, "error": f"{type(error).__name__}: {error}"}


def reply(got):
    return got["reply"] if got["ok"] and isinstance(got["reply"], dict) else {}


class Doc:
    """One open project in `Doc.folder` and the calls the rows make on it."""

    made = 0
    folder = RUN
    closed = []

    def __init__(self, client, name, width=WIDTH, height=HEIGHT, ext: str = ".framejob"):
        Doc.made += 1
        self.client, self.path = client, Doc.folder / f"{Doc.made:02d}-{name}{ext}"
        self.width, self.height = width, height
        self.ok, self.why = True, None
        self.media = {}
        self.note("new_project", attempt(client, "new_project", {"path": str(self.path)}))
        sized = self.call("set_canvas", width=width, height=height, fps=[30, 1],
                          background=[0, 0, 0, 1])
        if "made no change" not in sized.get("error", ""):   # a new project's own canvas
            self.note("set_canvas", sized)

    def note(self, tool, got):
        """Records the first failed step: `ok` false and `why` its tool and error."""
        if not got["ok"] and self.ok:
            self.ok, self.why = False, f"{tool}: {got.get('error', '')[:300]}"
        return got

    def call(self, tool, **arguments):
        return attempt(self.client, tool, dict(arguments, project=str(self.path)))

    def project(self):
        return reply(self.call("get_project")).get("project") or {}

    def clips(self):
        return self.project().get("clips") or []

    def first_track(self):
        return (self.project().get("tracks") or [{}])[0].get("id")

    def new_track(self):
        before = {t.get("id") for t in self.project().get("tracks") or []}
        self.call("add_track")
        made = [t.get("id") for t in self.project().get("tracks") or []
                if t.get("id") not in before]
        return made[0] if len(made) == 1 else None

    def place(self, tool, **arguments):
        before = {c["id"] for c in self.clips()}
        got = self.call(tool, **arguments)
        new = [c["id"] for c in self.clips() if c["id"] not in before]
        if not (got["ok"] and len(new) == 1):
            self.note(tool, got if not got["ok"] else {"ok": False, "error": f"{len(new)} new"})
            return None
        return new[0]

    def step(self, tool, **arguments):
        return self.note(tool, self.call(tool, **arguments))

    def import_media(self, path):
        """`path` imported once; its row's id, read back by path."""
        if path not in self.media:
            got = self.call("import_media", path=str(path))
            rows = self.project().get("media") or []
            self.media[path] = next((m.get("id") for m in rows if m.get("path") == str(path)),
                                    None)
            if self.media[path] is None:
                self.note("import_media", got if not got["ok"] else {"ok": False, "error": "no id"})
        return self.media[path]

    def movie(self, track, path, repeats=1, seconds=MOVIE_SECONDS):
        """`path` imported once, then placed `repeats` times back to back."""
        media = self.import_media(path)
        if media is None:
            return []
        return [self.place("add_clip", track=track, media=media, at=i * seconds * SEC)
                for i in range(repeats)]

    def render(self, out, t=T):
        """`render_frame` at `t` into `out`; the path, or None."""
        out = Path(out)
        if out.exists():
            out.unlink()
        got = self.call("render_frame", t=t, path=str(out))
        if not (got["ok"] and out.exists()):
            print(f"       render {out.name}: {got.get('error', 'no file')}", flush=True)
            return None
        return out

    def export(self, preset, out, **extra):
        out = Path(out)
        if out.exists():
            out.unlink()
        got = self.call("export", preset=preset, path=str(out), size="document", **extra)
        if not (got["ok"] and out.exists()):
            print(f"       export {out.name}: {got.get('error', 'no file')}", flush=True)
            return None
        return out

    def close(self):
        ok = attempt(self.client, "close_project", {"project": str(self.path), "discard": True})["ok"]
        Doc.closed.append((self.path.name, ok))
        return ok


# ---- fixtures ------------------------------------------------------------------------

MUTANT = None


def build_fixture(client, kind: str, seconds: int, ext: str = ".framejob") -> Doc:
    """U, G, F or T (the module doc); 1920×1080, 30 fps, black."""
    doc = Doc(client, f"{kind}-{seconds}s", ext=ext)
    first = doc.first_track()
    if kind == "T":
        doc.movie(first, MOVIE)
        return doc
    if kind == "F":
        tracks = [first] + [doc.new_track() for _ in F_LOOKS[1:]]
        for track, look in zip(tracks, F_LOOKS):
            clips = [c for c in doc.movie(track, MOVIE, repeats=F_SECONDS // MOVIE_SECONDS)
                     if c is not None]
            doc.step("set_video", clips=clips,
                     patch={"color": TONE, "look": {"kind": look, "amount": 0.8}})
        front = doc.new_track()
        adjustment = doc.place("add_adjustment_clip", track=front, at=0,
                               duration=F_SECONDS * SEC)
        if adjustment is not None:
            doc.step("set_video", clips=[adjustment], patch={"color": {"exposure": 0.2}})
        return doc
    repeats = max(1, seconds // MOVIE_SECONDS)
    doc.movie(first, MOVIE, repeats=repeats)
    small = [c for c in doc.movie(doc.new_track(), MOVIE, repeats=repeats) if c is not None]
    doc.step("set_video", clips=small, patch={"scale": 0.5, "x": 480, "y": -270})
    if kind == "G":
        graded = MUTANT != "graded-fixture-ungraded"
        every = [c["id"] for c in doc.clips()]
        if graded:
            doc.step("set_video", clips=every,
                     patch={"color": TONE, "look": {"kind": "teal_orange", "amount": 0.8}})
        front = doc.new_track()
        adjustment = doc.place("add_adjustment_clip", track=front, at=0, duration=seconds * SEC)
        if adjustment is not None and graded:
            doc.step("set_video", clips=[adjustment],
                     patch={"color": {"exposure": 0.2, "vibrance": 0.2}})
    return doc


# ---- instances ---------------------------------------------------------------------------

LOGS = []


def launch(binary, label):
    log = Doc.folder / f"{label}.log"
    LOGS.append(log)
    return mcp.launch(str(binary), ["-ReelcutCompositorTiming", "YES",
                                    "-FrameJobCompositorTiming", "YES"],
                      env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                      log_path=str(log), timeout=CALL_BOUND)


def stop(launched):
    launched.stop()
    mcp.remove_scratch(launched.socket_path)


def timed_export(binary: Path, kind: str, seconds: int, label: str) -> dict:
    """One h264 export of fixture `kind` on a fresh instance of `binary`."""
    launched = launch(binary, label)
    figures = {"label": label, "kind": kind, "seconds": seconds, "binary": str(binary)}
    try:
        if launched.client is None:
            figures.update(fixture=f"the app did not listen at {launched.socket_path}",
                           exported=False, windows=0, closed=False)
            return figures
        ext = ".reelcut" if Path(binary) in OLD_NAMED else ".framejob"
        doc = build_fixture(launched.client, kind, seconds, ext)
        figures["fixture"] = doc.why or "ok"
        log = Path(launched.log_path)
        offset = log.stat().st_size
        out = Doc.folder / f"{label}.mp4"
        figures["load_before"] = load()
        started = time.monotonic()
        movie = doc.export("h264", out)
        figures["export_s"] = round(time.monotonic() - started, 2)
        figures["load_after"] = load()
        figures["exported"] = movie is not None
        with open(log, errors="replace") as handle:
            handle.seek(offset)
            windows = [(float(a), float(w)) for a, w in TIMING.findall(handle.read())]
        figures["windows"] = len(windows)
        if windows:
            figures["average_ms"] = round(sum(a for a, _ in windows) / len(windows), 3)
            figures["worst_ms"] = max(w for _, w in windows)
        if out.exists():
            out.unlink()
        figures["closed"] = doc.close()
        return figures
    finally:
        stop(launched)
        print(f"       {label}: export {figures.get('export_s')} s, average "
              f"{figures.get('average_ms')} ms, worst {figures.get('worst_ms')} ms, "
              f"{figures.get('windows')} windows, fixture {figures.get('fixture')}, load "
              f"{figures.get('load_before')} → {figures.get('load_after')}", flush=True)


def menu_paths(client) -> list:
    """Every leaf of `perform_menu_item {}`'s listing (no project, no item run)."""
    items = client.call_with("perform_menu_item", {}).get("items") or []
    paths = []
    for item in items:
        path = item.get("path")
        paths.append(" ▸ ".join(path) if isinstance(path, list) else str(path))
    return paths


# ---- the rows ---------------------------------------------------------------------------

def timed(ok):
    return ok.get("fixture") == "ok" and ok.get("exported") and "export_s" in ok


def series_line(name, runs, key):
    values = [r.get(key) for r in runs]
    good = [v for v in values if v is not None]
    if not good:
        return f"{name} {values}", None
    median = statistics.median(good)
    spread = (max(good) - min(good)) / median if median else 0.0
    return f"{name} {values} (median {median:g}, spread {spread:.1%})", median


def run_m1(main_binary, branch_binary):
    listings = {}
    for side, binary in (("main", main_binary), ("branch", branch_binary)):
        source = main_binary if MUTANT == "menus-same-app" else binary
        launched = launch(source, f"m1-{side}")
        try:
            listings[side] = menu_paths(launched.client) if launched.client else None
        except Exception as error:  # an instrument that could not read is a FAIL
            print(f"       M1 {side}: {type(error).__name__}: {error}", flush=True)
            listings[side] = None
        finally:
            stop(launched)
    if listings["main"] is None or listings["branch"] is None:
        emit("M1", "FAIL", f"a listing could not be read: main {listings['main'] is not None}, "
             f"branch {listings['branch'] is not None}")
        return {"listings": listings}
    main, branch = set(listings["main"]), set(listings["branch"])
    missing = [p for p in MENU_PATHS if p not in branch]
    emit("M1", "PASS" if not missing else "FAIL",
         f"main {len(main)} leaves, branch {len(branch)}; the branch holds "
         f"{', '.join(MENU_PATHS)}: missing {missing or 'none'}")
    added, removed = sorted(branch - main), sorted(main - branch)

    def groups(paths):
        out = {}
        for p in paths:
            key = " ▸ ".join(p.split(" ▸ ")[:2])
            out.setdefault(key, []).append(p)
        return out

    added_g, removed_g = groups(added), groups(removed)
    outside = [g for g in added_g if g not in MENU_CAP_GROUPS]
    over = len(outside) + len(removed_g)
    emit("M1", "RECORD", "added " + ("; ".join(f"{g}: {len(v)} ({', '.join(x.split(' ▸ ')[-1] for x in v)})"
                                                for g, v in added_g.items()) or "none")
         + f"; removed {removed_g or 'none'}; against the cap's four "
         f"({', '.join(MENU_CAP_GROUPS)}), nothing else: "
         + ("cap held" if not over else f"cap missed by {over} groups ({outside + list(removed_g)})"))
    return {"main": len(main), "branch": len(branch), "added": added, "removed": removed}


def run_g0(branch_binary, seconds, closed):
    launched = launch(branch_binary, "g0")
    figures = {}
    try:
        if launched.client is None:
            emit("G0", "FAIL", f"the branch did not listen at {launched.socket_path}")
            return figures
        frames = {}
        for kind in ("U", "G"):
            doc = build_fixture(launched.client, kind, seconds)
            figures[f"{kind}_fixture"] = doc.why or "ok"
            if kind == "G":
                figures["adjustment_clips"] = sum(
                    1 for c in doc.clips() if c.get("source") == {"kind": "adjustment"})
            png = doc.render(Doc.folder / f"g0-{kind}.png")
            frames[kind] = decode_rgb(png) if png else None
            closed.append(doc.close())
        if frames["U"] is None or frames["G"] is None:
            emit("G0", "FAIL", f"a frame was not rendered or decoded: {figures}")
            return figures
        worst, at = max_delta(frames["G"], frames["U"])
        figures["max_delta"] = worst
        ok = worst > G0_LEVELS and figures.get("adjustment_clips") == 1 and \
            figures["G_fixture"] == "ok" and figures["U_fixture"] == "ok"
        emit("G0", "PASS" if ok else "FAIL",
             f"render_frame at 0.5 s of G against U ({seconds} s fixtures): max |Δ| {worst} "
             f"levels at {where(at)} (must exceed {G0_LEVELS}); G holds "
             f"{figures.get('adjustment_clips')} adjustment clip (must be 1); fixtures "
             f"U {figures['U_fixture']}, G {figures['G_fixture']}")
        return figures
    finally:
        stop(launched)


def run_e(main_binary, branch_binary, selected, rounds, seconds, closed):
    order = []
    if "E1" in selected:
        order.append(("mU", main_binary, "U"))
    order.append(("bU", branch_binary, "U"))
    if "E2" in selected:
        order.append(("bG", branch_binary, "G"))
    runs = {label: [] for label, _, _ in order}
    for n in range(rounds):
        for label, binary, kind in (order if n % 2 == 0 else order[::-1]):
            figures = timed_export(binary, kind, seconds, f"{label}-{n}")
            closed.append(figures.get("closed", False))
            runs[label].append(figures)
    medians = {}
    for label, done in runs.items():
        line, medians[label] = series_line(label, done, "export_s")
        print(f"       {line} s; averages {[r.get('average_ms') for r in done]} ms", flush=True)
    for row, top, bottom, cap in (("E1", "bU", "mU", EXPORT_CAP),
                                  ("E2", "bG", "bU", GRADED_EXPORT_CAP)):
        if row not in selected:
            continue
        every = all(timed(r) for r in runs[top] + runs[bottom])
        emit(row, "PASS" if every else "FAIL",
             f"{len(runs[top])} {top} and {len(runs[bottom])} {bottom} exports of {seconds} s "
             f"at 1080p, every one timed: {every}; "
             + "; ".join(series_line(x, runs[x], "export_s")[0] + " s" for x in (bottom, top)))
        if every and medians[bottom]:
            ratio = medians[top] / medians[bottom] - 1
            emit(row, "RECORD", f"median({top}) / median({bottom}) − 1 = {ratio:+.2%} against "
                 f"≤ {cap:.0%}: " + ("cap held" if ratio <= cap
                                     else f"cap missed by {ratio - cap:.2%}"))
    return runs


def run_f4(branch_binary, rounds, closed):
    runs = []
    for n in range(rounds):
        figures = timed_export(branch_binary, "F", F_SECONDS, f"F-{n}")
        closed.append(figures.get("closed", False))
        runs.append(figures)
    every = all(timed(r) and r.get("windows", 0) > 0 for r in runs)
    scored = len(runs) >= F4_EXPORTS
    if not scored:
        emit("F4", "SKIP", f"not scored: the spec scores F4 when {F4_EXPORTS} exports are "
             f"timed, and --rounds {rounds} timed {len(runs)}; the figures below are a record")
    emit("F4", ("PASS" if every else "FAIL") if scored else "RECORD",
         f"{len(runs)} exports of fixture F (four graded full-frame layers — warm, cool, "
         f"teal_orange, vivid at 0.8 over GR0's ST — and one adjustment clip, {F_SECONDS} s at "
         f"1080p), every one timed with compositor windows: {every}; per run average "
         f"{[r.get('average_ms') for r in runs]} ms, worst {[r.get('worst_ms') for r in runs]} ms, "
         f"windows {[r.get('windows') for r in runs]}, export {[r.get('export_s') for r in runs]} s")
    if every:
        median = statistics.median(r["average_ms"] for r in runs)
        emit("F4", "RECORD", f"median average {median:.3f} ms against ≤ {FRAME_BUDGET_MS} ms: "
             + cap_text(round(median, 3), FRAME_BUDGET_MS, " ms"))
    return runs


def lut3d(source, cube, out):
    """ffmpeg's `lut3d` (trilinear) over `source` into `out`. The filter reads
    a copy of `cube` named `<out's stem>.cube` beside `out`, by that bare name
    from `out`'s folder, so no character of the owner's path (a `:`, a `'`, a
    `\\`) ever reaches the filter graph's parser."""
    out = Path(out)
    safe = out.with_suffix(".cube")
    try:
        safe.write_bytes(Path(cube).read_bytes())
    except OSError:
        return None
    made = bounded.run(["ffmpeg", "-nostdin", "-y", "-v", "error", "-i", str(source), "-vf",
                        f"lut3d=file={safe.name}:interp=trilinear", str(out)], 120,
                       cwd=str(out.parent))
    return out if made["rc"] == 0 and not made["expired"] and out.exists() else None


def run_t4(branch_binary, owner_lut, closed):
    launched = launch(branch_binary, "t4")
    figures = {}
    try:
        if launched.client is None:
            emit("T4", "FAIL", f"the branch did not listen at {launched.socket_path}")
            return figures
        doc = build_fixture(launched.client, "T", MOVIE_SECONDS)
        clip = next((c["id"] for c in doc.clips()), None)
        neutral = doc.render(Doc.folder / "t4-neutral.png")

        def through(cube, tag):
            media = doc.import_media(cube)
            if MUTANT != "lut-not-applied" and media is not None:
                doc.step("set_video", clips=[clip],
                         patch={"look": {"kind": "lut", "media": media, "amount": 1}})
            got = doc.render(Doc.folder / f"t4-{tag}.png")
            want = lut3d(neutral, cube, Doc.folder / f"t4-{tag}-ffmpeg.png") if neutral else None
            return (decode_rgb(got) if got else None), (decode_rgb(want) if want else None)

        lut, ffmpeg = through(CUBE, "lut")
        base = decode_rgb(neutral) if neutral else None
        if lut is None or ffmpeg is None or base is None or doc.why:
            emit("T4", "FAIL", f"a frame was missing: neutral {base is not None}, Frame Job "
                 f"{lut is not None}, ffmpeg {ffmpeg is not None}; fixture {doc.why or 'ok'}")
        else:
            worst, at = max_delta(lut, ffmpeg)
            control, cat = max_delta(base, ffmpeg)
            figures.update(max_delta=worst, control=control)
            emit("T4", "PASS" if worst <= T4_LEVELS else "FAIL",
                 f"{CUBE.name} (33³) at amount 1 on the movie's frame at 0.5 s: Frame Job's "
                 f"render_frame against ffmpeg's lut3d (trilinear) on the neutral frame, max |Δ| "
                 f"{worst} levels at {where(at)} over {WIDTH}×{HEIGHT}×3 (bound ±{T4_LEVELS})")
            emit("T4c", "PASS" if control > T4_LEVELS else "FAIL",
                 f"CONTROL: the neutral frame against ffmpeg's, max |Δ| {control} levels at "
                 f"{where(cat)} (must exceed {T4_LEVELS}: the LUT moves the frame)")
        if owner_lut is not None:
            mine, theirs = through(owner_lut, "owner")
            if mine is None or theirs is None:
                emit("T4", "RECORD", f"the owner's {owner_lut}: a frame was missing (Frame Job "
                     f"{mine is not None}, ffmpeg {theirs is not None}; {doc.why or 'no refusal'})")
            else:
                worst, at = max_delta(mine, theirs)
                figures["owner"] = worst
                emit("T4", "RECORD", f"the owner's {owner_lut}: max |Δ| {worst} levels at "
                     f"{where(at)} against ±{T4_LEVELS}: {cap_text(worst, T4_LEVELS, ' levels')}")
        closed.append(doc.close())
        return figures
    finally:
        stop(launched)


def complaints(log):
    try:
        return [line.strip() for line in open(log, errors="replace")
                if "Reelcut: " in line or "Frame Job: " in line]
    except OSError:
        return [f"{log} could not be read"]


def measure(args):
    global MUTANT
    MUTANT = args.mutant
    selected = set(MEASURE_ROWS if not args.only else args.only.split(","))
    unknown = selected - set(MEASURE_ROWS)
    if unknown:
        print(f"unknown rows {sorted(unknown)}; rows are {', '.join(MEASURE_ROWS)}")
        return 1
    started = datetime.datetime.now().astimezone()
    stamp = f"{started:%Y%m%d-%H%M%S}"
    Doc.folder = RUN / stamp
    Doc.folder.mkdir(parents=True, exist_ok=True)
    HOME.mkdir(parents=True, exist_ok=True)
    tag = "measure" + (f" --only {','.join(r for r in MEASURE_ROWS if r in selected)}"
                       if args.only else "") + (f" --mutant {MUTANT}" if MUTANT else "")
    print(f"grading_verdict {tag} at {started:%Y-%m-%d %H:%M %Z}: rounds {args.rounds}, "
          f"seconds {args.seconds}; work {Doc.folder.relative_to(ROOT)}", flush=True)
    branch = Path(proof_app.binary(release_only=RELEASE_ONLY))
    main_binary = None
    try:
        proof_app.require_fresh(branch)
        if selected & {"M1", "E1", "E2"}:
            main_binary = Path(args.main) if args.main else MAIN_BINARY
            OLD_NAMED.add(main_binary)
            if not main_binary.is_file():
                raise proof_app.StaleApp(f"no main build at {main_binary}; run `main-tree make`")
            proof_app.require_fresh(main_binary)
    except (proof_app.StaleApp, ValueError) as error:
        print(f"instrument failure: {error}")
        return 1
    print(f"branch {branch}" + (f"; main {main_binary}" if main_binary else "; main not used"),
          flush=True)
    result = {"tag": tag, "started": started.isoformat(), "branch": str(branch),
              "main": str(main_binary) if main_binary else None, "rounds": args.rounds,
              "seconds": args.seconds}
    facts = None
    if "H0" in selected:
        ok, facts = grading_spike.host_gate()
        detail = (f"powermode {facts['powermode']}; drawing from {facts['power']}; "
                  f"{facts['cpu']}; macOS {facts['macos']}; load before {facts['load_before']}")
        emit("H0", "PASS" if ok else "SKIP", detail if ok else
             f"{detail}: the host gate is shut, so every timing row is skipped")
        result["host"] = facts
        if not ok:
            for row in sorted(selected - {"H0"}):
                emit(row, "SKIP", "the host gate is shut (H0)")
            return finish(tag, MUTANT, extra_exit=2)
    if make_movie() is None:
        emit("Z1", "FAIL", "the fixture movie could not be made")
        return finish(tag, MUTANT)
    if not CUBE.exists():
        write_cube(CUBE, 33)
    closed = []
    try:
        if "M1" in selected:
            result["M1"] = run_m1(main_binary, branch)
        if "G0" in selected:
            result["G0"] = run_g0(branch, args.seconds, closed)
        if selected & {"E1", "E2"}:
            result["E"] = run_e(main_binary, branch, selected, args.rounds, args.seconds, closed)
        if "F4" in selected:
            result["F4"] = run_f4(branch, args.rounds, closed)
        if "T4" in selected:
            result["T4"] = run_t4(branch, args.lut, closed)
    except proof_app.StaleApp as error:
        emit("Z1", "FAIL", f"instrument failure: {error}")
    except Exception as error:  # a row that could not run is a failure
        emit("Z1", "FAIL", f"instrument error: {type(error).__name__}: {error}")
    if "Z1" in selected:
        found = [line for log in LOGS for line in complaints(log)]
        every = all(closed) and all(ok for _, ok in Doc.closed)
        emit("Z1", "PASS" if every and not found else "FAIL",
             f"{len(Doc.closed)} projects, every one closed {every}; {len(LOGS)} logs, "
             f"`Frame Job: ` lines {found or 'none'}")
    if facts is not None:
        facts["load_after"] = load()
        emit("H0", "RECORD", f"load after {facts['load_after']}")
    result["rows"] = ROWS
    path = WORK / ("measure.json" if not MUTANT else f"measure-mutant-{MUTANT}.json")
    try:
        everything = json.loads(path.read_text()) if path.exists() else {}
    except ValueError:
        everything = {}
    everything[tag] = result
    path.write_text(json.dumps(everything, indent=1, sort_keys=True, default=str))
    print(f"wrote {path.relative_to(ROOT)}; logs under {Doc.folder.relative_to(ROOT)}", flush=True)
    return finish(tag, MUTANT)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    s = sub.add_parser("sizes")
    s.add_argument("--mutant", choices=SIZES_MUTANTS)
    t = sub.add_parser("main-tree")
    t.add_argument("action", choices=("make", "remove"))
    m = sub.add_parser("measure")
    m.add_argument("--main", default=None)
    m.add_argument("--only", default=None)
    m.add_argument("--rounds", type=int, default=3)
    m.add_argument("--seconds", type=int, default=60)
    m.add_argument("--lut", default=None)
    m.add_argument("--mutant", choices=MEASURE_MUTANTS)
    args = parser.parse_args()
    if args.command == "sizes":
        return sizes(args.mutant)
    if args.command == "main-tree":
        return main_tree(args.action)
    if args.seconds % MOVIE_SECONDS or args.seconds <= 0:
        parser.error(f"--seconds is a multiple of {MOVIE_SECONDS}")
    if args.lut is not None:
        args.lut = Path(args.lut).expanduser().resolve()
        if not args.lut.is_file():
            parser.error(f"--lut {args.lut} is not a file")
    return measure(args)


if __name__ == "__main__":
    sys.exit(main())
