#!/usr/bin/env python3
"""Issue #295 (issue batch B101) — what colour label a rendered frame carries,
measured; no product code is changed by it.

    python3 tools/proof/frame_label_proof.py [--app PATH] [--only F1,F5,...]

`render_frame` (and Save Frame…, the same writer) labels its file from the
composition's source tags: issue #292 found a frame whose sources were all
covered carry an `iCCP` profile named `kCGColorSpaceCoreMedia709` once the
covered movie was tagged BT.709, and an `sRGB` chunk while it was untagged.
This script prints, per case, the label each written file carries, and
whether a colour-managed read tells two labels apart: each file is decoded
raw to `rgb48le` by ffmpeg (which applies no profile) and again after `sips
--matchTo` the system's sRGB profile, and the two compared (mean and max
|Δ| in 8-bit levels, the 16-bit sample / 257).

Launches the app `proof_app` picks (Debug unless `RC_PROOF_APP=release`) on
a scratch socket of its own and stops only that process. **The instance runs
in a scratch home**, `CFFIXED_USER_HOME=tools/proof/work/frame_label/run/
home`; every package, frame and export is under `tools/proof/work/
frame_label/run/`, removed at the start and at exit. The fixtures are made
once under `tools/proof/work/frame_label/media/` and kept. No menu item is
performed and no default written. Every call is bounded (`CALL_BOUND`), every
ffmpeg, ffprobe and sips too. Every project is closed (`close_project`,
discard). This script never records the screen and spends nothing.

Fixtures (320×180, 30 fps, 1 s): `h264_none.mp4` (testsrc2, libx264
yuv420p, tags unknown ×3), `h264_709.mp4` and `prores_709.mov` (through
`bt709_fixture.make`: bt709 ×3), `prores_none.mov` (prores_ks profile 3
yuv422p10le, unknown ×3), `still8.png` (an opaque rgb24 testsrc2 frame) and
`still16.png` (an rgb48be ramp, written here). A fixture is kept only when
ffprobe reads what it should; a refusal is an instrument failure (exit 2).

Rows (each scene on a 320×180 30 fps canvas, rendered at 0.5 s):
- **F1–F4**: `h264_none`, `h264_709`, `prores_none`, `prores_709` alone.
- **F5, F6**: `still8` fully covering `prores_none` / `prores_709` (#295's
  case); **F7**: `still8` over `h264_709`; **F8**: `still8` alone.
- **F9**: `still16` alone (spec §11 PR-9's reader).
- **F10**: `prores_709` with `{log: slog3}` (a converting composition).
- **F11**: F1's and F2's frames written as `jpeg` and `heic`.
- **E1**: an `h264` export of F1's and F2's projects: ffprobe's tags.
- **E2**: an `apng` export of the same two: the file's label.
- **Z1** (CONTROL): no `Frame Job: ` line, every project closed.

Each row prints the file's depth; a PNG's `sRGB` chunk or its `iCCP` and the
profile's name (or `sips -g profile` for the rest); and the raw-against-
matched mean and max |Δ|. The pairs F1/F2 and F5/F6 print the raw Δ between
the two files and the matched Δ between their matched reads. A row passes
when it was reached and read: this is a measurement, not a rule (none is
decided; README "Issue #295"). Exit 0 when every row passes.
"""

import argparse
import atexit
import json
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import bt709_fixture  # noqa: E402
import hdr_proof as hdr  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402

BASE = ROOT / "tools/proof/work/frame_label"
WORK = BASE / "run"
HOME = WORK / "home"
MEDIA = BASE / "media"
CALL_BOUND = 300
TOOL_BOUND = 120
W, H = 320, 180
SEC = 600_000
T = SEC // 2
SRGB = "/System/Library/ColorSync/Profiles/sRGB Profile.icc"
ROWS = ["F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "E1", "E2", "Z1"]
# row: (label, [fixtures back to front], Camera Log of the first or None)
SCENES = {"F1": ("h264_none alone", ["h264_none"], None),
          "F2": ("h264_709 alone", ["h264_709"], None),
          "F3": ("prores_none alone", ["prores_none"], None),
          "F4": ("prores_709 alone", ["prores_709"], None),
          "F5": ("still8 fully covering prores_none", ["prores_none", "still8"], None),
          "F6": ("still8 fully covering prores_709", ["prores_709", "still8"], None),
          "F7": ("still8 fully covering h264_709", ["h264_709", "still8"], None),
          "F8": ("still8 alone", ["still8"], None),
          "F9": ("still16 alone", ["still16"], None),
          "F10": ("prores_709 with {log: slog3}", ["prores_709"], {"log": "slog3"})}
UNKNOWN = {"color_primaries": "unknown", "color_transfer": "unknown", "color_space": "unknown"}
rows = {}
selected = set(ROWS)
REFUSED = {}


def check(name, good, detail=""):
    key = name.split()[0]
    if key not in selected:
        return
    rows[key] = bool(good) and rows.get(key, True)
    print(("  ok   " if good else "  FAIL ") + name + (f"\n       {detail}" if detail else ""),
          flush=True)


def attempt(client, tool, arguments):
    try:
        return {"ok": True, "reply": client.call_with(tool, arguments)}
    except mcp.ToolError as error:
        return {"ok": False, "error": str(error)}
    except Exception as error:  # a socket timeout is the expiry
        return {"ok": False, "error": f"{type(error).__name__}: {error}"}


def reply(got):
    return got["reply"] if got["ok"] and isinstance(got["reply"], dict) else {}


# ---- fixtures -------------------------------------------------------------------

def tags_of(path):
    probe = bt709_fixture.stream(path)
    return {k: probe.get(k, "unknown") for k in UNKNOWN}, probe


def untagged(path, graph, codec, want):
    """`path` from ffmpeg `graph` + `codec` with every tag `unknown`, kept only
    when ffprobe reads `want` and unknown ×3; else None."""
    if not path.exists():
        made = bounded.run(["ffmpeg", "-nostdin", "-v", "error", "-y", *graph, *codec,
                            "-color_primaries", "unknown", "-color_trc", "unknown",
                            "-colorspace", "unknown", str(path)], TOOL_BOUND)
        if made["rc"] != 0 or not path.exists():
            REFUSED[path.name] = f"ffmpeg: rc {made['rc']} {made['stderr'][-300:]}"
            path.unlink(missing_ok=True)
            return None
    tags, probe = tags_of(path)
    wrong = {k: probe.get(k) for k, v in want.items() if probe.get(k) != v}
    if wrong or tags != UNKNOWN:
        REFUSED[path.name] = f"ffprobe read {wrong or 'as wanted'}, tags {tags}"
        path.unlink(missing_ok=True)
        return None
    print(f"       {path.name} kept: {probe.get('codec_name')} {probe.get('pix_fmt')}, tags "
          f"{bt709_fixture.tags(probe)}", flush=True)
    return path


def write_png16(path):
    """A 16-bit RGB (rgb48be) horizontal ramp, W×H, no colour chunk."""
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))
    row = b"".join(struct.pack(">HHH", v, v, 65535 - v)
                   for v in (round(65535 * x / (W - 1)) for x in range(W)))
    raw = b"".join(b"\x00" + row for _ in range(H))
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 16, 2,
                                                                       0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
    return path


def fixtures():
    """{name: path}; a refused fixture is missing and named in REFUSED."""
    MEDIA.mkdir(parents=True, exist_ok=True)
    source = ["-f", "lavfi", "-i", f"testsrc2=size={W}x{H}:rate=30:duration=1"]
    tagged = ["-f", "lavfi", "-i",
              f"testsrc2=size={W}x{H}:rate=30:duration=1,{bt709_fixture.SETPARAMS}"]
    x264 = ["-c:v", "libx264", "-pix_fmt", "yuv420p"]
    prores = ["-c:v", "prores_ks", "-profile:v", "3", "-pix_fmt", "yuv422p10le"]
    made = {
        "h264_none": untagged(MEDIA / "h264_none.mp4", source, x264,
                              {"codec_name": "h264", "pix_fmt": "yuv420p"}),
        "prores_none": untagged(MEDIA / "prores_none.mov", source, prores,
                                {"codec_name": "prores", "pix_fmt": "yuv422p10le"}),
    }
    for name, codec, want, pix_fmt in (
            ("h264_709.mp4", x264, {"codec_name": "h264", "pix_fmt": "yuv420p"}, "yuv420p"),
            ("prores_709.mov", prores, {"codec_name": "prores", "pix_fmt": "yuv422p10le"},
             "yuv422p10le")):
        path, why = bt709_fixture.make(MEDIA / name, tagged, codec, want, pix_fmt, TOOL_BOUND)
        made[name.split(".")[0]] = path
        if path is None:
            REFUSED[name] = why
    still8 = MEDIA / "still8.png"
    if not still8.exists():
        bounded.run(["ffmpeg", "-nostdin", "-v", "error", "-y", *source, "-frames:v", "1",
                     "-pix_fmt", "rgb24", str(still8)], TOOL_BOUND)
    probe = bt709_fixture.stream(still8) if still8.exists() else {}
    made["still8"] = still8 if probe.get("pix_fmt") == "rgb24" else None
    if made["still8"] is None:
        REFUSED["still8.png"] = f"ffprobe read {probe}"
    still16 = MEDIA / "still16.png"
    if not still16.exists():
        write_png16(still16)
    probe = bt709_fixture.stream(still16)
    made["still16"] = still16 if probe.get("pix_fmt") == "rgb48be" else None
    if made["still16"] is None:
        REFUSED["still16.png"] = f"ffprobe read {probe}"
    return {k: v for k, v in made.items() if v is not None}


# ---- reading a written file -----------------------------------------------------

def png_chunks(path):
    """[(kind, data)] of a PNG (an APNG too), or [] when it is not one."""
    data = Path(path).read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return []
    chunks, at = [], 8
    while at + 8 <= len(data):
        length, kind = struct.unpack(">I4s", data[at:at + 8])
        chunks.append((kind.decode("latin-1"), data[at + 8:at + 8 + length]))
        at += 12 + length
    return chunks


def label(path):
    """(depth, the label) of a written file."""
    chunks = png_chunks(path)
    if chunks:
        kinds = [k for k, _ in chunks]
        ihdr = dict(chunks).get("IHDR", b"")
        depth = ihdr[8] if len(ihdr) > 8 else None
        if "iCCP" in kinds:
            name = dict(chunks)["iCCP"].split(b"\0", 1)[0].decode("latin-1")
            text = f"iCCP '{name}'"
        elif "sRGB" in kinds:
            text = f"sRGB chunk (intent {dict(chunks)['sRGB'][0]})"
        else:
            text = "no colour chunk"
        extra = [k for k in kinds if k in ("cHRM", "gAMA", "cICP", "eXIf")]
        return depth, text + (f"; also {extra}" if extra else "")
    ran = bounded.run(["sips", "-g", "profile", "-g", "bitsPerSample", str(path)], TOOL_BOUND)
    lines = dict(line.strip().split(": ", 1) for line in ran["stdout"].splitlines()
                 if ": " in line)
    return lines.get("bitsPerSample"), f"sips profile '{lines.get('profile')}'"


def decoded(path):
    """`path`'s first frame as rgb48le samples (ffmpeg applies no profile); a
    JPEG or HEIC goes through `sips -s format png` first, which keeps its
    profile and its values. None when it does not read."""
    source = Path(path)
    if not png_chunks(source):
        source = WORK / f"{Path(path).stem}-{Path(path).suffix[1:]}-plain.png"
        bounded.run(["sips", "-s", "format", "png", str(path), "--out", str(source)], TOOL_BOUND)
    data = bt709_fixture.decode(source, "rgb48le") if source.exists() else None
    return data[:W * H * 6] if data and len(data) >= W * H * 6 else None


def matched(path):
    """`path` after `sips --matchTo` the system sRGB profile, as a PNG."""
    out = WORK / f"{Path(path).stem}-{Path(path).suffix[1:]}-matched.png"
    out.unlink(missing_ok=True)
    ran = bounded.run(["sips", "-s", "format", "png", "--matchTo", SRGB, str(path), "--out",
                       str(out)], TOOL_BOUND)
    return out if ran["rc"] == 0 and out.exists() else None


def delta(a, b):
    """(mean, max) |a − b| over every sample, in 8-bit levels."""
    if a is None or b is None or len(a) != len(b):
        return None
    va = struct.unpack(f"<{len(a) // 2}H", a)
    vb = struct.unpack(f"<{len(b) // 2}H", b)
    gaps = [abs(x - y) for x, y in zip(va, vb)]
    return round(sum(gaps) / len(gaps) / 257, 3), round(max(gaps) / 257, 3)


def read(path):
    """A written file's figures: depth, label, raw, matched, raw → matched Δ."""
    depth, text = label(path)
    raw = decoded(path)
    match = matched(path)
    match_raw = decoded(match) if match else None
    return {"depth": depth, "label": text, "raw": raw, "matched": match_raw,
            "delta": delta(raw, match_raw), "matched_label": label(match) if match else None}


def shown(figures):
    depth, text = figures["matched_label"] or (None, None)
    return (f"depth {figures['depth']}, {figures['label']}; matched to sRGB: depth {depth}, "
            f"{text}; raw → matched |Δ| mean/max {figures['delta']}")


# ---- the scenes -----------------------------------------------------------------

class Doc:
    def __init__(self, client, name):
        self.client = client
        self.path = WORK / f"{name}.framejob"
        self.made = attempt(client, "new_project", {"path": str(self.path)})["ok"]
        self.call("set_canvas", width=W, height=H, fps=[30, 1])
        canvas = self.project().get("canvas") or {}
        self.ok = self.made and canvas.get("width") == W and canvas.get("height") == H
        self.why = None if self.ok else "the project or its canvas was not made"

    def call(self, tool, **arguments):
        return attempt(self.client, tool, dict(arguments, project=str(self.path)))

    def project(self):
        return reply(self.call("get_project")).get("project") or {}

    def track(self, index):
        """The index-th track's id, adding tracks as needed."""
        while len(self.project().get("tracks") or []) <= index:
            if not self.call("add_track")["ok"]:
                return None
        return (self.project().get("tracks") or [])[index].get("id")

    def place(self, path, index, color=None):
        media = reply(self.call("import_media", path=str(path))).get("media")
        track = self.track(index) if media is not None else None
        if track is None:
            self.ok, self.why = False, f"import {Path(path).name}"
            return None
        if color is not None and not self.call("set_media_color", media=media,
                                                 color=color)["ok"]:
            self.ok, self.why = False, f"set_media_color on {Path(path).name}"
        before = {c["id"] for c in self.project().get("clips") or []}
        got = self.call("add_clip", track=track, media=media, at=0)
        new = [c["id"] for c in self.project().get("clips") or [] if c["id"] not in before]
        if not got["ok"] or len(new) != 1:
            self.ok, self.why = False, f"add_clip {Path(path).name}: {got.get('error')}"
            return None
        return new[0]

    def render(self, tag, **extra):
        suffix = {"jpeg": "jpg", "heic": "heic"}.get(extra.get("format"), "png")
        out = WORK / f"{tag}.{suffix}"
        out.unlink(missing_ok=True)
        got = self.call("render_frame", t=T, path=str(out), **extra)
        if not (got["ok"] and out.exists()):
            print(f"       render {tag}: {got.get('error', 'no file')}", flush=True)
            return None
        return out

    def export(self, tag, preset, suffix):
        out = WORK / f"{tag}.{suffix}"
        out.unlink(missing_ok=True)
        got = self.call("export", preset=preset, path=str(out))
        if not (got["ok"] and out.exists()):
            print(f"       export {tag}: {got.get('error', 'no file')}", flush=True)
            return None
        return out

    def close(self):
        return attempt(self.client, "close_project", {"project": str(self.path),
                                                       "discard": True})["ok"]


def run(client, media, state):
    """Every selected row; True when every project closed."""
    closed = True
    frames = {}
    keep = {"F1", "F2"} if selected & {"F11", "E1", "E2"} else set()
    docs = {}
    for row, (title, names, color) in SCENES.items():
        if row not in selected and row not in keep:
            continue
        missing = [n for n in names if n not in media]
        if missing:
            check(f"{row} {title}", False, f"fixtures refused: {missing}")
            continue
        doc = Doc(client, row.lower())
        for index, name in enumerate(names):
            if doc.ok:
                doc.place(media[name], index, color if index == 0 else None)
        png = doc.render(row.lower()) if doc.ok else None
        if row in keep:
            docs[row] = doc
        else:
            closed = doc.close() and closed
        figures = read(png) if png else None
        frames[row] = figures
        good = figures is not None and figures["raw"] is not None and figures["delta"] is not None
        check(f"{row} {title}: the frame's label and its colour-managed read",
              good, shown(figures) if figures else f"not reached: {doc.why or 'no render'}")
    for first, second in (("F1", "F2"), ("F5", "F6")):
        a, b = frames.get(first), frames.get(second)
        if a and b and (first in selected or second in selected):
            print(f"       pair {first}/{second}: raw |Δ| mean/max {delta(a['raw'], b['raw'])}; "
                  f"matched |Δ| mean/max {delta(a['matched'], b['matched'])}", flush=True)
    if "F11" in selected:
        figures, misses = {}, []
        for row in ("F1", "F2"):
            for kind in ("jpeg", "heic"):
                doc = docs.get(row)
                out = doc.render(f"{row.lower()}-{kind}", format=kind) if doc else None
                got = read(out) if out else None
                figures[f"{row} {kind}"] = shown(got) if got else None
                if got is None or got["raw"] is None:
                    misses.append(f"{row} {kind}")
        check("F11 F1's and F2's frames as jpeg and heic: their labels", not misses,
              "; ".join(f"{k}: {v}" for k, v in figures.items()) + (
                  f"; not read {misses}" if misses else ""))
    if "E1" in selected:
        figures = {}
        for row in ("F1", "F2"):
            out = docs[row].export(f"{row.lower()}-h264", "h264", "mp4") if row in docs else None
            figures[row] = bt709_fixture.tags(bt709_fixture.stream(out)) if out else None
        check("E1 an h264 export of F1's and F2's projects: ffprobe's tags (transfer/primaries/"
              "matrix)", all(figures.values()), f"{figures}")
    if "E2" in selected:
        figures = {}
        for row in ("F1", "F2"):
            out = docs[row].export(f"{row.lower()}-apng", "apng", "png") if row in docs else None
            figures[row] = (f"{label(out)}; chunks {[k for k, _ in png_chunks(out)][:8]}"
                            if out else None)
        check("E2 an apng export of F1's and F2's projects: the file's label", all(
            figures.values()), f"{figures}")
    for doc in docs.values():
        closed = doc.close() and closed
    state["closed"] = closed
    return closed


def remove_work():
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", default=None)
    parser.add_argument("--only", help="comma-separated rows to run and score")
    args = parser.parse_args()
    if args.only:
        selected = {name.strip() for name in args.only.split(",") if name.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
    remove_work()
    atexit.register(remove_work)
    HOME.mkdir(parents=True)
    binary = Path(args.app) if args.app else proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    print(f"B101 #295 — a rendered frame's colour label ({proof_app.config()} build {binary})",
          flush=True)
    if not binary.is_file():
        print(f"instrument failure: no app binary at {binary}")
        return 2
    media = fixtures()
    if REFUSED:
        print(f"instrument failure: fixtures refused {REFUSED}")
        return 2
    log = WORK / "instance.log"
    state = {}
    launched = mcp.launch(str(binary), [], env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    closed = True
    try:
        if launched.client is None:
            print(f"instrument failure: the app did not listen at {launched.socket_path}")
            return 2
        print(f"  instance PID {launched.child.pid} at {launched.socket_path}", flush=True)
        try:
            closed = run(launched.client, media, state)
        except Exception as error:  # a row that could not run is a failure
            import traceback
            traceback.print_exc()
            print(f"  instrument error: {type(error).__name__}: {error}", flush=True)
            closed = False
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    found = hdr.complaints(log)
    check("Z1 CONTROL: every project closed and the log holds no `Frame Job: ` line",
          closed and not found, f"closed {closed}; complaints {found}")
    print(f"  {log.name} tail:\n    " + "\n    ".join(hdr.tail(log)), flush=True)
    scored = [name for name in ROWS if name in rows]
    passed = sum(1 for name in scored if rows.get(name))
    print(f"{passed}/{len(scored)}")
    return 0 if passed == len(scored) else 1


if __name__ == "__main__":
    sys.exit(main())
