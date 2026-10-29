#!/usr/bin/env python3
"""Codec export C6a and C6b (spec §11 CX-18): what one export costs — its resident peak
above the instance's own, and its wall time — measured over MCP, per Export Queue key and
size. `ExportEncoderCosts.swift`'s two tables are transcribed from its runs, and
`archive/codec-export.md`'s "## C6a" and "## C6b" record them.

Every run is one fresh instance of the app `proof_app` chooses (`RC_PROOF_APP`, Release for
the record), on a scratch socket, stopped by its own PID; nothing else is ever killed. Each:

  new_project; set_canvas <w>×<h> at --fps (output hlg for the HLG key); the media placed on
  the first track — `--media av` (the default, C6a's layout): AV.mov at 0 and 5 s, 10 s, the
  whole project exported; any other media (`gh5`, the GH5 borough-market 4K 25p clip, or a
  path): once at 0, `set_range` --from … --from + --seconds, and `export` with
  range "in_out"; one render_frame to warm the compositor; the baseline `ps -o rss= -p
  <pid>`; then `export` (the key's preset, encoder_speed on the AV1 rows, `size` on the
  sized rows whose default is the format's cap), one `export_status` for its
  `estimated_seconds`, then followed to `done` while a thread samples the RSS every 0.1 s.
  delta = peak − baseline; seconds = the done answer's `elapsed`; the 1-minute load average
  is read at the export's start. After the timing, `ffprobe -count_packets` counts the video
  packets the file holds (`written_frames`; an APNG's `fcTL` chunks instead); it and the
settings' own count
  (`settings_frames`) must each be within 1 of `expected_frames` (--seconds × the done
  settings' fps), else the row's error. The output is deleted once its row is recorded.

Keys: av1 and av1_webm at faster, balanced and smaller; vp9_webm in an SDR project and in
an HLG one; vp9_alpha_webm (always 8-bit SDR) in an SDR project; the AVFoundation rows
h264, hevc, hevc_alpha, hevc_10bit, prores_422 and prores_4444; gif and apng. Sizes
1920×1080, 2560×1440 and 3840×2160.

  python3 tools/proof/encoder_memory_measure.py [--app debug|release|<.app>] [--only K1,K2]
      [--sizes 1080,1440,2160] [--media av|gh5|<path>] [--fps 30] [--seconds 10] [--from 0]
      [--runs 1] [--label memory]
  python3 tools/proof/encoder_memory_measure.py --derive <long.json> <short.json>

`--runs N` runs N rounds, each every size × key once in order, and prints a medians table
per key and size after the per-run one. Writes `tools/proof/work/encoder-memory/<date>/
<label>.json` (with `uptime` at the start and end, and the argv), each instance's folder
under `<date>/<label>/<key>-<size>-r<run>/`. A run that fails is a row with its error,
never an exit; the script exits 1 when any run failed.

`--derive LONG SHORT` launches nothing: from two batches of one frame count each (a
pre-C6b row's `frames`), it fits each writer key's fixed start and per-frame time at each
size, and prints the Swift literals for `ExportEncoderCosts.time`.
"""

import argparse
import json
import os
import statistics
import subprocess
import sys
import threading
import time
from datetime import date
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402

AV = HERE / "media" / "AV.mov"
# The owner's GH5 clip (gitignored, tools/proof/media/log-samples/): H.264 High 8-bit
# 3840×2160 25p, 55.21 s — the codec spike's `gh5` source.
GH5 = HERE / "media" / "log-samples" / (
    "panasonic_lumix_gh5_sample_movie__borough_market___4k_uhd___25p___10_bit___800_iso___"
    "v_log_l_photo_style_v1 (2160p).mp4")
MEDIA = {"av": AV, "gh5": GH5}
SEC = 600_000
SIZES = {"1080": (1920, 1080), "1440": (2560, 1440), "2160": (3840, 2160)}
# name → (preset, encoder_speed or None, HLG project, passes `size`: its default is the cap)
KEYS = {
    "av1:faster": ("av1", "faster", False, False),
    "av1:balanced": ("av1", "balanced", False, False),
    "av1:smaller": ("av1", "smaller", False, False),
    "av1_webm:faster": ("av1_webm", "faster", False, False),
    "av1_webm:balanced": ("av1_webm", "balanced", False, False),
    "av1_webm:smaller": ("av1_webm", "smaller", False, False),
    "vp9_webm:sdr": ("vp9_webm", None, False, False),
    "vp9_webm:hlg": ("vp9_webm", None, True, False),
    "vp9_alpha_webm": ("vp9_alpha_webm", None, False, False),
    "h264": ("h264", None, False, False),
    "hevc": ("hevc", None, False, False),
    "hevc_alpha": ("hevc_alpha", None, False, False),
    "hevc_10bit": ("hevc_10bit", None, False, False),
    "prores_422": ("prores_422", None, False, False),
    "prores_4444": ("prores_4444", None, False, False),
    "gif": ("gif", None, False, True),
    "apng": ("apng", None, False, True),
}
EXTENSIONS = {"av1": "mp4", "av1_webm": "webm", "vp9_webm": "webm", "vp9_alpha_webm": "webm",
              "h264": "mp4", "hevc": "mp4", "hevc_alpha": "mov", "hevc_10bit": "mp4",
              "prores_422": "mov", "prores_4444": "mov", "gif": "gif", "apng": "apng"}
# The bundled-encoder rows `ExportEncoderCosts` has entries for.
WRITERS = ("av1", "av1_webm", "vp9_webm", "vp9_alpha_webm")
SAMPLE_EVERY = 0.1
EXPORT_BOUND = 900


def rss_bytes(pid):
    """The process's resident size in bytes, or None once it is gone."""
    got = subprocess.run(["ps", "-o", "rss=", "-p", str(pid)], capture_output=True, text=True)
    text = got.stdout.strip()
    return int(text) * 1024 if text.isdigit() else None


def uptime():
    return subprocess.run(["uptime"], capture_output=True, text=True).stdout.strip()


def apng_frames(path):
    """An APNG's frames as its chunks declare them: the `fcTL` chunks, walked by their
    headers (no decode), which must equal `acTL`'s count; or (None, why). ffprobe's APNG
    demuxer stops near 2 GiB (218 of 250 packets in a 2.4 GB 4K file whose acTL and fcTL
    chunks both say 250), so a 4K APNG is counted here instead."""
    controls, declared = 0, None
    try:
        with open(path, "rb") as handle:
            if handle.read(8) != b"\x89PNG\r\n\x1a\n":
                return None, "not a PNG"
            while True:
                head = handle.read(8)
                if len(head) < 8:
                    break
                length, kind = int.from_bytes(head[:4], "big"), head[4:]
                if kind == b"acTL":
                    declared = int.from_bytes(handle.read(4), "big")
                    handle.seek(length - 4 + 4, 1)
                    continue
                if kind == b"fcTL":
                    controls += 1
                if kind == b"IEND":
                    break
                handle.seek(length + 4, 1)
    except OSError as error:
        return None, f"{type(error).__name__}: {error}"
    if declared != controls:
        return None, f"acTL declares {declared} frames and {controls} fcTL chunks follow"
    return controls, ""


def video_packets(path):
    """The video packets in `path` (no decode, so a 4K file is cheap), or (None, why)."""
    if Path(path).suffix.lower() in (".png", ".apng"):
        return apng_frames(path)
    ran = bounded.run(["ffprobe", "-v", "error", "-count_packets", "-select_streams", "v:0",
                       "-show_entries", "stream=nb_read_packets", "-of",
                       "default=noprint_wrappers=1:nokey=1", str(path)], 120,
                      env=bounded.child_env())
    text = (ran["stdout"] or "").strip()
    if text.isdigit():
        return int(text), ""
    return None, (ran["stderr"] or "").strip()[-200:] or f"ffprobe answered {text!r}"


class Sampler(threading.Thread):
    """Samples one PID's RSS every `SAMPLE_EVERY` s until stopped; keeps the peak."""

    def __init__(self, pid):
        super().__init__(daemon=True)
        self.pid, self.peak, self.samples = pid, 0, 0
        self.halt = threading.Event()

    def run(self):
        while not self.halt.is_set():
            value = rss_bytes(self.pid)
            if value is not None:
                self.peak = max(self.peak, value)
                self.samples += 1
            self.halt.wait(SAMPLE_EVERY)


def measure(app, work, key, size, run, opts):
    preset, speed, hlg, sized = KEYS[key]
    width, height = SIZES[size]
    label = f"{key.replace(':', '-')}-{size}-r{run}"
    folder = work / label
    folder.mkdir(parents=True, exist_ok=True)
    row = {"key": key, "preset": preset, "encoder_speed": speed, "hlg": hlg, "run": run,
           "width": width, "height": height, "fps": opts.fps, "media": opts.media,
           "from": opts.start, "seconds_range": opts.seconds,
           "frames": round(opts.seconds * opts.fps)}
    launched = mcp.launch(str(proof_app.executable(app)), [], env=bounded.child_env({}),
                          log_path=str(folder / "instance.log"), timeout=EXPORT_BOUND + 60)
    try:
        client = launched.client
        if client is None:
            row["error"] = f"the app did not listen ({folder / 'instance.log'})"
            return row
        pid = launched.child.pid
        doc = str(folder / f"{label}.framejob")
        client.call("new_project", path=doc)

        def call(tool, **arguments):
            return client.call_with(tool, {"project": doc, **arguments})
        canvas = {"width": width, "height": height, "fps": opts.fps}
        if hlg:
            canvas["output"] = "hlg"
        try:
            call("set_canvas", **canvas)
        except mcp.ToolError as error:
            if "made no change" not in str(error):
                raise
        media = call("import_media", path=str(opts.media_path))["media"]
        track = call("get_project")["project"]["tracks"][0]["id"]
        call("add_clip", track=track, media=media, at=0)
        if opts.media == "av":
            call("add_clip", track=track, media=media, at=5 * SEC)
            warm = 2 * SEC
        else:
            call("set_range", start=round(opts.start * SEC),
                 end=round((opts.start + opts.seconds) * SEC))
            warm = round((opts.start + min(2.0, opts.seconds / 2)) * SEC)
        call("render_frame", t=warm, path=str(folder / "warm.png"))
        time.sleep(1.0)
        baseline = rss_bytes(pid)
        if baseline is None:
            # Subtracting 0 would record the whole peak as the job's delta: a failed case,
            # never a figure for the cost table.
            row["error"] = f"the baseline RSS of pid {pid} could not be read"
            return row
        out = folder / f"out.{EXTENSIONS[preset]}"
        out.unlink(missing_ok=True)
        arguments = {"project": doc, "path": str(out), "preset": preset}
        if speed:
            arguments["encoder_speed"] = speed
        if sized:
            arguments["size"] = [width, height]
        if opts.media != "av":
            arguments["range"] = "in_out"
        row["load_1min"] = round(os.getloadavg()[0], 2)
        sampler = Sampler(pid)
        sampler.start()
        try:
            answer = client.call_with("export", arguments)
            if isinstance(answer, dict) and "export_id" in answer:
                status = client.call("export_status", export_id=answer["export_id"])
                if isinstance(status, dict) and "estimated_seconds" in status:
                    row["estimated_seconds"] = status["estimated_seconds"]
                done = client.wait_export(answer["export_id"], seconds=EXPORT_BOUND)
            else:
                done = answer
        finally:
            sampler.halt.set()
            sampler.join()
        elapsed = done.get("elapsed")
        num, den = done["fps"]
        settings_frames = done["duration"] * num / (den * SEC)
        expected = round(opts.seconds * num / den)
        # The done answer's path is the file as written (an APNG may not keep `.apng`).
        written_path = Path(done.get("path") or out)
        row["written_path"] = str(written_path)
        written, why = video_packets(written_path)
        row.update({
            "baseline_bytes": baseline, "peak_bytes": sampler.peak,
            "delta_bytes": sampler.peak - baseline, "samples": sampler.samples,
            "seconds": elapsed, "bytes": done.get("bytes"),
            "settings_frames": round(settings_frames, 3), "written_frames": written,
            "expected_frames": expected})
        if written is None:
            row["error"] = f"the written frames could not be counted: {why}"
        else:
            row["per_frame_seconds"] = round(elapsed / written, 5) if written else None
            if abs(written - expected) > 1 or abs(settings_frames - expected) > 1:
                row["error"] = (f"{written} frames written and {settings_frames:g} asked for, "
                                f"not {expected}")
        written_path.unlink(missing_ok=True)
        out.unlink(missing_ok=True)
        call("close_project", discard=True)
    except (mcp.ToolError, KeyError, ValueError, TypeError, OSError,
            proof_app.StaleApp) as error:
        row["error"] = f"{type(error).__name__}: {error}"
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
        for leftover in folder.glob("out.*"):
            leftover.unlink(missing_ok=True)
        try:
            complaints = [line.strip() for line in
                          (folder / "instance.log").read_text(errors="replace").splitlines()
                          if "Frame Job: " in line]
        except OSError:
            complaints = ["the log could not be read"]
        row["log_complaints"] = complaints
    return row


def gib(value):
    return f"{value / 1_073_741_824:.2f}" if isinstance(value, (int, float)) else "—"


def size_name(row):
    for name, (w, h) in SIZES.items():
        if (row["width"], row["height"]) == (w, h):
            return name
    return f"{row['width']}x{row['height']}"


def span(values, digits=2):
    values = [v for v in values if isinstance(v, (int, float))]
    if not values:
        return "—"
    low, high = min(values), max(values)
    return f"{low:.{digits}f}" if low == high else f"{low:.{digits}f}–{high:.{digits}f}"


def medians(rows):
    """Per (key, size), in first-seen order: the ok runs' medians and ranges."""
    groups = {}
    for row in rows:
        groups.setdefault((row["key"], size_name(row)), []).append(row)
    print("\n| Key | Size | n ok | Median s | Min–max s | Median s/frame | Max Δ GiB | "
          "Median MB | Median est. s | Est. error | Load |")
    print("|---|---|---|---|---|---|---|---|---|---|---|")
    for (key, size), group in groups.items():
        ok = [r for r in group if "error" not in r]
        if not ok:
            print(f"| {key} | {size} | 0/{len(group)} | " + "; ".join(
                r["error"] for r in group) + " |")
            continue
        seconds = [r["seconds"] for r in ok]
        median = statistics.median(seconds)
        estimates = [r["estimated_seconds"] for r in ok if "estimated_seconds" in r]
        est = statistics.median(estimates) if estimates else None
        error = f"{(median - est) / median * 100:+.1f} %" if est is not None and median else "—"
        print(f"| {key} | {size} | {len(ok)}/{len(group)} | {median:.3f} | "
              f"{span(seconds, 3)} | "
              f"{statistics.median(r['per_frame_seconds'] for r in ok):.5f} | "
              f"{gib(max(r['delta_bytes'] for r in ok))} | "
              f"{statistics.median(r['bytes'] for r in ok) / 1e6:.2f} | "
              f"{est if est is not None else '—'} | {error} | "
              f"{span(r['load_1min'] for r in ok)} |")


def frame_count(row):
    """A row's frame count: C6b's `expected_frames`, a pre-C6b row's `frames`."""
    return row["expected_frames"] if "expected_frames" in row else row["frames"]


def derive(long_path, short_path):
    """Fits each writer key's setup and per-frame time from a long and a short batch."""
    batches = []
    for path in (long_path, short_path):
        try:
            rows = json.loads(Path(path).read_text())["rows"]
        except (OSError, ValueError, KeyError) as error:
            print(f"{path}: cannot be read ({type(error).__name__}: {error})")
            return 2
        ok = [r for r in rows if "error" not in r]
        counts = sorted({frame_count(r) for r in ok})
        if len(counts) != 1:
            print(f"{path}: its ok rows must share one frame count, and they have {counts}")
            return 2
        batches.append((ok, counts[0]))
    (long_rows, n_long), (short_rows, n_short) = batches
    if n_long == n_short:
        print(f"the two batches have the same frame count ({n_long}), so the intercept "
              "cannot be fitted")
        return 2
    literals = []
    keys = [k for k in dict.fromkeys(r["key"] for r in long_rows)
            if r_preset(k) in WRITERS and any(r["key"] == k for r in short_rows)]
    print(f"long batch {n_long} frames, short batch {n_short} frames")
    for key in keys:
        fits = {}
        for size in SIZES:
            long_at = [r for r in long_rows if r["key"] == key and size_name(r) == size]
            short_at = [r for r in short_rows if r["key"] == key and size_name(r) == size]
            if not long_at or not short_at:
                continue
            e_l = statistics.median(r["seconds"] for r in long_at)
            e_s = statistics.median(r["seconds"] for r in short_at)
            intercept = e_s - n_short * (e_l - e_s) / (n_long - n_short)
            fits[size] = {"e_l": e_l, "e_s": e_s, "s": intercept,
                          "delta": max(r["delta_bytes"] for r in long_at + short_at),
                          "loads": [r["load_1min"] for r in long_at + short_at]}
        if not fits:
            continue
        intercepts = [f["s"] for f in fits.values()]
        setup = min(intercepts) if all(s > 0.5 for s in intercepts) else 0.0
        print(f"\n{key}")
        for size, fit in fits.items():
            fit["per_frame"] = (fit["e_l"] - setup) / n_long
            print(f"  {size}: e_L {fit['e_l']:.3f} s (n_L {n_long}), e_S {fit['e_s']:.3f} s "
                  f"(n_S {n_short}), intercept {fit['s']:.3f} s, perFrame "
                  f"{fit['per_frame']:.6f} s, max Δ {fit['delta']} B ({gib(fit['delta'])} GiB),"
                  f" load {span(fit['loads'])}")
        print(f"  setupSeconds {setup:.3f}")
        literals.append(swift_literal(key, fits, setup, n_long))
    print("\n// ExportEncoderCosts.time, from --derive:")
    print("\n".join(literals))
    return 0


def r_preset(key):
    return KEYS[key][0] if key in KEYS else key.split(":")[0]


def swift_literal(key, fits, setup, n_long):
    preset, speed, hlg, _ = KEYS[key]
    bits = 10 if preset in ("av1", "av1_webm") or hlg else 8
    speed_text = f".{speed}" if speed else "nil"
    at = {s: f"{fits[s]['per_frame'] * n_long:.3f} / {n_long}" if s in fits else "?"
          for s in ("1080", "2160")}
    loads = ", ".join(f"{span(fits[s]['loads'])} at {'4K' if s == '2160' else s + 'p'}"
                      for s in fits)
    return (f"        ExportEncoderKey(preset: \"{preset}\", speed: {speed_text}, bits: {bits}): "
            f"ExportTimeEntry(\n"
            f"            perFrame: ExportEncoderFigure(\n"
            f"                at1080: {at['1080']}, at2160: {at['2160']},\n"
            f"                source: run + \"{key}; load {loads}; C6b\"),\n"
            f"            setupSeconds: {setup:.3f}),")


def main(argv=None):
    parser = argparse.ArgumentParser(description="encoder memory and time (codec-export C6a, C6b)")
    parser.add_argument("--app", help="debug, release or a .app path (default RC_PROOF_APP)")
    parser.add_argument("--only", help="comma-separated keys, of " + ", ".join(KEYS))
    parser.add_argument("--sizes", default="1080,2160",
                        help="comma-separated, of " + ",".join(SIZES))
    parser.add_argument("--media", default="av",
                        help="av (AV.mov twice, C6a's layout), gh5 or a media path")
    parser.add_argument("--fps", type=int, default=30, help="the canvas rate (default 30)")
    parser.add_argument("--seconds", type=float, default=10.0,
                        help="the exported length (default 10)")
    parser.add_argument("--from", dest="start", type=float, default=0.0,
                        help="where the in/out range starts in the media, s (default 0)")
    parser.add_argument("--runs", type=int, default=1, help="rounds of every size × key")
    parser.add_argument("--label", default="memory", help="the JSON's and folder's name")
    parser.add_argument("--derive", nargs=2, metavar=("LONG", "SHORT"),
                        help="fit setup and per-frame times from two batches; launches nothing")
    args = parser.parse_args(argv)
    if args.derive:
        return derive(*args.derive)
    if args.app:
        os.environ[proof_app.ENV] = args.app
    if args.media == "av" and (args.seconds != 10 or args.start != 0):
        print("--media av is C6a's fixed 10 s layout: --seconds 10 and --from 0 only")
        return 2
    args.media_path = MEDIA.get(args.media, Path(args.media))
    if not args.media_path.is_file():
        print(f"no media at {args.media_path}")
        return 2
    if args.runs < 1 or args.seconds <= 0 or args.fps <= 0:
        print("--runs, --seconds and --fps must be positive")
        return 2
    keys = args.only.split(",") if args.only else list(KEYS)
    sizes = args.sizes.split(",")
    unknown = [k for k in keys if k not in KEYS] + [s for s in sizes if s not in SIZES]
    if unknown:
        print(f"unknown keys or sizes: {unknown}")
        return 2
    try:
        app = proof_app.bundle()
        proof_app.require_fresh(proof_app.executable(app))
    except (proof_app.StaleApp, ValueError, OSError) as error:
        print(f"the app cannot be driven: {error}")
        return 1
    day = date.today().isoformat()
    base = HERE / "work" / "encoder-memory" / day
    work = base / args.label
    work.mkdir(parents=True, exist_ok=True)
    report = base / f"{args.label}.json"
    physical = int(subprocess.run(["sysctl", "-n", "hw.memsize"], capture_output=True,
                                  text=True).stdout.strip() or 0)
    machine = subprocess.run(["sysctl", "-n", "machdep.cpu.brand_string"], capture_output=True,
                             text=True).stdout.strip()
    started = uptime()
    print(f"app {app}\nmachine {machine}, {physical / 1_073_741_824:.0f} GiB\n{started}",
          flush=True)
    header = {"app": str(app), "machine": machine, "physical_bytes": physical, "date": day,
              "argv": sys.argv if argv is None else ["encoder_memory_measure.py", *argv],
              "uptime_start": started}
    rows = []
    for run in range(1, args.runs + 1):
        for size in sizes:
            for key in keys:
                row = measure(app, work, key, size, run, args)
                rows.append(row)
                print(f"  r{run} {key:18} {size}: " + (row["error"] if "error" in row else
                      f"Δ {gib(row['delta_bytes'])} GiB (base {gib(row['baseline_bytes'])}, "
                      f"peak {gib(row['peak_bytes'])}), {row['seconds']} s (est. "
                      f"{row.get('estimated_seconds', '—')}), {row['written_frames']} frames, "
                      f"load {row['load_1min']}"), flush=True)
                report.write_text(json.dumps({**header, "rows": rows}, indent=2) + "\n")
    report.write_text(json.dumps({**header, "uptime_end": uptime(), "rows": rows},
                                 indent=2) + "\n")
    print("\n| Run | Key | Size | Δ RSS GiB | Baseline GiB | Peak GiB | Seconds | Est. s | "
          "Frames | s/frame | MB | Load |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|")
    for row in rows:
        if "error" in row:
            print(f"| {row['run']} | {row['key']} | {row['width']}×{row['height']} | "
                  f"{row['error']} |")
            continue
        print(f"| {row['run']} | {row['key']} | {row['width']}×{row['height']} | "
              f"{gib(row['delta_bytes'])} | {gib(row['baseline_bytes'])} | "
              f"{gib(row['peak_bytes'])} | {row['seconds']} | "
              f"{row.get('estimated_seconds', '—')} | {row['written_frames']} | "
              f"{row['per_frame_seconds']} | {row['bytes'] / 1e6:.2f} | {row['load_1min']} |")
    medians(rows)
    print(f"\n{uptime()}\n{report}")
    failed = [r for r in rows if "error" in r or r.get("log_complaints")]
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
