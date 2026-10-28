#!/usr/bin/env python3
"""Codec export C6a (spec §11 CX-18): what one bundled-encoder export costs — its resident
peak above the instance's own, and its wall time — measured over MCP, per Export Queue key,
at 1080p and 4K. `ExportEncoderCosts.swift`'s two tables are transcribed from its table,
and `designs/codec-export.md`'s "## C6a" records the run.

Every run is one fresh instance of the app `proof_app` chooses (`RC_PROOF_APP`, Release for
the record), on a scratch socket, stopped by its own PID; nothing else is ever killed. Each:

  new_project; set_canvas <w>×<h> at 30 fps (output hlg for the HLG key); AV.mov imported
  and placed twice on the first track (0 and 5 s: 10 s, 300 frames); one render_frame to
  warm the compositor; the baseline `ps -o rss= -p <pid>`; then `export` (the key's preset,
  and encoder_speed on the AV1 rows) followed to `done` while a thread samples the RSS every
  0.1 s. delta = peak − baseline; seconds = the done answer's `elapsed`; the 1-minute load
  average is read at the export's start.

Keys: av1 and av1_webm at faster, balanced and smaller; vp9_webm in an SDR project and in
an HLG one; h264 as the AVFoundation control. Sizes 1920×1080 and 3840×2160.

  python3 tools/proof/encoder_memory_measure.py [--app debug|release|<.app>]
                                                [--only av1:balanced,h264] [--sizes 1080,2160]

Writes `tools/proof/work/encoder-memory/<date>/memory.json` and prints the table. A run
that fails is a row with its error, never an exit; the script exits 1 when any run failed.
"""

import argparse
import json
import os
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
SEC = 600_000
FRAMES = 300
SIZES = {"1080": (1920, 1080), "2160": (3840, 2160)}
# name → (preset, encoder_speed or None, HLG project)
KEYS = {
    "av1:faster": ("av1", "faster", False),
    "av1:balanced": ("av1", "balanced", False),
    "av1:smaller": ("av1", "smaller", False),
    "av1_webm:faster": ("av1_webm", "faster", False),
    "av1_webm:balanced": ("av1_webm", "balanced", False),
    "av1_webm:smaller": ("av1_webm", "smaller", False),
    "vp9_webm:sdr": ("vp9_webm", None, False),
    "vp9_webm:hlg": ("vp9_webm", None, True),
    "h264": ("h264", None, False),
}
EXTENSIONS = {"av1": "mp4", "av1_webm": "webm", "vp9_webm": "webm", "h264": "mp4"}
SAMPLE_EVERY = 0.1
EXPORT_BOUND = 900


def rss_bytes(pid):
    """The process's resident size in bytes, or None once it is gone."""
    got = subprocess.run(["ps", "-o", "rss=", "-p", str(pid)], capture_output=True, text=True)
    text = got.stdout.strip()
    return int(text) * 1024 if text.isdigit() else None


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


def measure(app, work, key, size):
    preset, speed, hlg = KEYS[key]
    width, height = SIZES[size]
    label = f"{key.replace(':', '-')}-{size}"
    folder = work / label
    folder.mkdir(parents=True, exist_ok=True)
    row = {"key": key, "preset": preset, "encoder_speed": speed, "hlg": hlg,
           "width": width, "height": height, "frames": FRAMES}
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
        canvas = {"width": width, "height": height, "fps": 30}
        if hlg:
            canvas["output"] = "hlg"
        try:
            call("set_canvas", **canvas)
        except mcp.ToolError as error:
            if "made no change" not in str(error):
                raise
        media = call("import_media", path=str(AV))["media"]
        track = call("get_project")["project"]["tracks"][0]["id"]
        call("add_clip", track=track, media=media, at=0)
        call("add_clip", track=track, media=media, at=5 * SEC)
        call("render_frame", t=2 * SEC, path=str(folder / "warm.png"))
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
        row["load_1min"] = round(os.getloadavg()[0], 2)
        sampler = Sampler(pid)
        sampler.start()
        try:
            done = client.export_with(arguments, seconds=EXPORT_BOUND)
        finally:
            sampler.halt.set()
            sampler.join()
        frames = (done.get("duration", 0) * 30) // SEC if isinstance(done, dict) else None
        row.update({
            "baseline_bytes": baseline, "peak_bytes": sampler.peak,
            "delta_bytes": sampler.peak - baseline, "samples": sampler.samples,
            "seconds": done.get("elapsed"), "bytes": done.get("bytes"),
            "written_frames": frames,
            "per_frame_seconds": round(done.get("elapsed", 0) / FRAMES, 5)})
        call("close_project", discard=True)
    except (mcp.ToolError, KeyError, OSError, proof_app.StaleApp) as error:
        row["error"] = f"{type(error).__name__}: {error}"
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
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


def main(argv=None):
    parser = argparse.ArgumentParser(description="encoder memory and time (codec-export C6a)")
    parser.add_argument("--app", help="debug, release or a .app path (default RC_PROOF_APP)")
    parser.add_argument("--only", help="comma-separated keys, of " + ", ".join(KEYS))
    parser.add_argument("--sizes", default="1080,2160", help="comma-separated, of 1080,2160")
    args = parser.parse_args(argv)
    if args.app:
        os.environ[proof_app.ENV] = args.app
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
    work = HERE / "work" / "encoder-memory" / date.today().isoformat()
    work.mkdir(parents=True, exist_ok=True)
    physical = int(subprocess.run(["sysctl", "-n", "hw.memsize"], capture_output=True,
                                  text=True).stdout.strip() or 0)
    machine = subprocess.run(["sysctl", "-n", "machdep.cpu.brand_string"], capture_output=True,
                             text=True).stdout.strip()
    print(f"app {app}\nmachine {machine}, {physical / 1_073_741_824:.0f} GiB", flush=True)
    rows = []
    for size in sizes:
        for key in keys:
            row = measure(app, work, key, size)
            rows.append(row)
            print(f"  {key:18} {size}: " + (row["error"] if "error" in row else
                  f"Δ {gib(row['delta_bytes'])} GiB (base {gib(row['baseline_bytes'])}, peak "
                  f"{gib(row['peak_bytes'])}), {row['seconds']} s, load {row['load_1min']}"),
                  flush=True)
            (work / "memory.json").write_text(json.dumps(
                {"app": str(app), "machine": machine, "physical_bytes": physical,
                 "date": date.today().isoformat(), "rows": rows}, indent=2) + "\n")
    print(f"\n| Key | Size | Δ RSS GiB | Baseline GiB | Peak GiB | Seconds | s/frame | Load |")
    print("|---|---|---|---|---|---|---|---|")
    for row in rows:
        if "error" in row:
            print(f"| {row['key']} | {row['width']}×{row['height']} | {row['error']} |")
            continue
        print(f"| {row['key']} | {row['width']}×{row['height']} | {gib(row['delta_bytes'])} | "
              f"{gib(row['baseline_bytes'])} | {gib(row['peak_bytes'])} | {row['seconds']} | "
              f"{row['per_frame_seconds']} | {row['load_1min']} |")
    print(f"\n{work / 'memory.json'}")
    failed = [r for r in rows if "error" in r or r.get("log_complaints")]
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
