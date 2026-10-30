"""Normalize's Loudness mode over MCP (road map "audio" AP1, spec §11 AU-13..AU-16).

Usage: python3 tools/proof/loudness_normalize_proof.py <dir>/agent.sock

Every level is MEASURED on an exported WAV with phase5_proof.py's own BS.1770-4
arithmetic (`integrated`, `true_peak`), never read back from the app alone.

  N1   normalize_clip's schema: mode (peak|loudness), target_lufs (-50..-5).
  N2   refusals by name: target_lufs -51 and -4, mode "rms", target_lufs with
       peak, peak_db with loudness.
  N3   steady fixtures (stereo and mono) to -16, -14 and -23: each export within
       0.5 LU of the target and of result_lufs.
  N4   a peaky fixture: limited_by true_peak, export TP <= -0.9 dBTP, the note
       names the clip.
  N5   two clips of different levels in one call land within 0.5 LU of each other.
  N6   the owner's recording (samples/Rode-usb-mic.m4a): measured about -41.7,
       limited by true peak, the export at result_lufs +-0.5 (reported).
  N7   a reversed clip and a x2 Keep pitch clip of a steady fixture within 0.5 LU.
  N8   measured_lufs / true_peak_dbtp against this script's measurement of a
       volume-1 export of the same window (0.5 LU, 0.5 dB).
  N9   a second identical call "made no change".
  N10  Clip > Normalize on an instance launched with -FrameJobNormalizeMode
       loudness (and target -16) lands at -16 +-0.5 LUFS; on one launched with
       -FrameJobNormalizeMode peak at -1 dBFS peak.

The two instances N10 needs are launched here, each on its own socket, with the
mode in the argument domain (nothing persists, and the shared domain's own
choice is never read), and stopped at the end.
"""

import math
import os
import shutil
import subprocess
import sys
import time

import mcp as mcp_module
import phase5_proof as p5
import proof_app
from mcp import MCP, ToolError
from phase5_proof import Session, channels, integrated, pcm, true_peak

ROOT = os.path.dirname(os.path.dirname(p5.HERE))
RODE = os.path.join(ROOT, "samples", "Rode-usb-mic.m4a")
FIXTURES = p5.FIXTURES

checks = 0
failures = []


def check(ok, what):
    global checks
    checks += 1
    print(("  ok   " if ok else "  FAIL ") + what)
    if not ok:
        failures.append(what)
    return ok


def near(value, wanted, tolerance):
    return value is not None and math.isfinite(value) and abs(value - wanted) <= tolerance


def f(value):
    return "absent" if value is None else f"{value:.2f}"


def db(x):
    return 20 * math.log10(x) if x > 0 else -math.inf


FIXTURE_EXPRESSIONS = {
    "steady.wav": ("0.1*sin(2*PI*1000*t)", "0.1*sin(2*PI*1000*t+PI/3)", 6),
    "steady-quiet.wav": ("0.03*sin(2*PI*700*t)", "0.03*sin(2*PI*700*t)", 6),
    # A quiet tone with a 1 ms 3 kHz burst at 0.9 every second: loud peaks, low loudness.
    "peaky.wav": ("0.02*sin(2*PI*1000*t)+0.9*lt(mod(t,1),0.001)*sin(2*PI*3000*t)",
                  "0.02*sin(2*PI*1000*t)+0.9*lt(mod(t,1),0.001)*sin(2*PI*3000*t)", 6),
}


def fixtures():
    os.makedirs(FIXTURES, exist_ok=True)
    for name, (left, right, seconds) in FIXTURE_EXPRESSIONS.items():
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
                        f"aevalsrc='{left}|{right}':s=48000:d={seconds}", "-c:a", "pcm_s16le",
                        os.path.join(FIXTURES, name)], check=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
                    "aevalsrc='0.1*sin(2*PI*1000*t)':s=48000:d=6", "-c:a", "pcm_s16le",
                    os.path.join(FIXTURES, "steady-mono.wav")], check=True)
    if os.path.exists(RODE):
        shutil.copyfile(RODE, os.path.join(FIXTURES, "rode.m4a"))


def measure(s, label, window=None):
    """(integrated LUFS, true peak dBTP, sample peak dBFS) of a WAV export of the
    whole timeline, or of `window` = (from_s, to_s) of it."""
    _, data, _ = s.wav(label)
    chans = channels(data)
    if window:
        a, b = (int(x * 48000) for x in window)
        chans = [c[a:b] for c in chans]
    peak = max(max(abs(x) for x in c) for c in chans)
    return integrated(chans), db(true_peak(chans)), db(peak)


def place(s, name, at=0):
    """`Session.place`, then the media's loudness marker waited for: the cache is
    written by the import's background pass, after the waveform."""
    clip = s.place(name, at=at)
    media = s.clip(clip)["source"]["media"]
    marker = os.path.join(s.path, "cache", "loudness", f"{media}.complete.json")
    for _ in range(600):
        if os.path.exists(marker):
            return clip
        time.sleep(0.05)
    raise RuntimeError(f"{s.name}: the loudness cache of media {media} was never written")


def loud(s, clips, **kwargs):
    return s.op("normalize_clip", clips=clips, mode="loudness", **kwargs)


def schema_rows(m):
    print("\nN1 — the schema")
    schema = m.schemas()["normalize_clip"]["inputSchema"]
    props = schema["properties"]
    check(set(props) == {"clips", "peak_db", "mode", "target_lufs", "project"},
          f"N1 normalize_clip declares clips, peak_db, mode, target_lufs ({sorted(props)})")
    check(props.get("mode", {}).get("enum") == ["peak", "loudness"]
          and props["mode"].get("type") == "string", "N1 mode is the string enum peak|loudness")
    t = props.get("target_lufs", {})
    check(t.get("type") == "number" and t.get("minimum") == -50 and t.get("maximum") == -5,
          f"N1 target_lufs is a number bounded -50..-5 ({t.get('minimum')}..{t.get('maximum')})")
    check(schema.get("required") == ["clips"], "N1 and only clips is required")


def refusal_rows(m):
    print("\nN2 — refusals by name")
    s = Session(m, "loudness-refusals")
    clip = place(s, "steady.wav")
    cases = [
        ({"mode": "loudness", "target_lufs": -51}, "target_lufs"),
        ({"mode": "loudness", "target_lufs": -4}, "target_lufs"),
        ({"mode": "rms"}, "mode"),
        ({"mode": "peak", "target_lufs": -16}, "target_lufs"),
        ({"target_lufs": -16}, "target_lufs"),
        ({"mode": "loudness", "peak_db": -1}, "peak_db"),
    ]
    for args, name in cases:
        text = s.error("normalize_clip", clips=[clip], **args) or ""
        check(name in text and "made no change" not in text,
              f"N2 {args} refused naming {name}: {text[:140]!r}")
    check(near(s.clip(clip)["audio"]["volume"], 1.0, 1e-12), "N2 and the volume is untouched")
    m.call("close_project", project=s.path, discard=True)


def steady_rows(m):
    print("\nN3 — steady fixtures to three targets")
    for fixture in ("steady.wav", "steady-mono.wav"):
        for target in (-16, -14, -23):
            s = Session(m, f"loudness-steady-{target}")
            clip = place(s, fixture)
            row = loud(s, [clip], target_lufs=target)["normalized"][0]
            lufs, tp, _ = measure(s, f"{fixture}-{target}")
            check(near(lufs, target, 0.5) and near(lufs, row["result_lufs"], 0.5)
                  and row["limited_by"] is None,
                  f"N3 {fixture} to {target}: export {f(lufs)} LUFS, result_lufs "
                  f"{f(row['result_lufs'])}, measured {f(row['measured_lufs'])}, "
                  f"volume {row['volume']:.4f}")
            m.call("close_project", project=s.path, discard=True)


def peaky_rows(m):
    print("\nN4 — a peaky fixture stops at the true-peak ceiling")
    s = Session(m, "loudness-peaky")
    clip = place(s, "peaky.wav")
    answer = loud(s, [clip])
    row = answer["normalized"][0]
    lufs, tp, _ = measure(s, "peaky")
    check(row["limited_by"] == "true_peak" and near(row["result_true_peak_dbtp"], -1, 1e-6),
          f"N4 limited_by {row['limited_by']}, result_true_peak_dbtp "
          f"{f(row['result_true_peak_dbtp'])}, result_lufs {f(row['result_lufs'])}")
    check(tp <= -0.9, f"N4 the export's true peak {f(tp)} dBTP is at or under -0.9")
    check(str(clip) in (answer.get("note") or ""), f"N4 the note names clip {clip}: "
          f"{(answer.get('note') or '')[:120]!r}")
    m.call("close_project", project=s.path, discard=True)


def match_rows(m):
    print("\nN5 — two clips of different levels in one call")
    s = Session(m, "loudness-match")
    a = place(s, "steady.wav", at=0)
    b = place(s, "steady-quiet.wav", at=6 * p5.SEC)
    rows = {r["clip"]: r for r in loud(s, [a, b])["normalized"]}
    first, _, _ = measure(s, "match", window=(0.5, 5.5))
    second, _, _ = measure(s, "match2", window=(6.5, 11.5))
    check(first is not None and second is not None and abs(first - second) <= 0.5,
          f"N5 {f(first)} and {f(second)} LUFS (volumes {rows[a]['volume']:.3f}, "
          f"{rows[b]['volume']:.3f})")
    m.call("close_project", project=s.path, discard=True)


def rode_rows(m):
    print("\nN6, N8, N9 — the owner's recording")
    if not os.path.exists(RODE):
        check(False, f"N6 {RODE} is present")
        return
    s = Session(m, "loudness-rode")
    clip = place(s, "rode.m4a")
    lufs1, tp1, _ = measure(s, "rode-v1")
    answer = loud(s, [clip])
    row = answer["normalized"][0]
    check(near(row["measured_lufs"], -41.7, 0.3) and row["limited_by"] == "true_peak",
          f"N6 measured {f(row['measured_lufs'])} LUFS, true peak "
          f"{f(row['true_peak_dbtp'])} dBTP, limited_by {row['limited_by']}, volume "
          f"{row['volume']:.3f}, result_lufs {f(row['result_lufs'])}")
    lufs2, tp2, _ = measure(s, "rode-normalized")
    check(near(lufs2, row["result_lufs"], 0.5),
          f"N6 the export lands at {f(lufs2)} LUFS ({f(tp2)} dBTP) against result_lufs "
          f"{f(row['result_lufs'])}: short of -16 because the true peak holds it")
    check(near(row["measured_lufs"], lufs1, 0.5) and near(row["true_peak_dbtp"], tp1, 0.5),
          f"N8 measured_lufs {f(row['measured_lufs'])} / true_peak_dbtp "
          f"{f(row['true_peak_dbtp'])} against the volume-1 export's {f(lufs1)} / {f(tp1)}")
    text = s.error("normalize_clip", clips=[clip], mode="loudness") or ""
    check("made no change" in text, f"N9 a second call: {text[:100]!r}")
    m.call("close_project", project=s.path, discard=True)


def kinds_rows(m):
    print("\nN7 — reversed and x2 Keep pitch")
    for kind in ("reversed", "speed"):
        s = Session(m, f"loudness-{kind}")
        clip = place(s, "steady.wav")
        if kind == "reversed":
            s.op("set_reversed", clip=clip, reversed=True)
        else:
            s.op("set_speed", clip=clip, rate=2, keep_pitch=True)
        row = loud(s, [clip])["normalized"][0]
        lufs, _, _ = measure(s, kind)
        check(near(lufs, -16, 0.5), f"N7 {kind}: export {f(lufs)} LUFS, measured "
              f"{f(row['measured_lufs'])}, result_lufs {f(row['result_lufs'])}")
        m.call("close_project", project=s.path, discard=True)


def menu_leg(mode, label):
    """Clip > Normalize on an instance launched with the mode (and the -16
    target) in the argument domain, so the row never reads whatever mode the
    shared defaults domain holds (spec §11 AU-15 makes the choice persist).
    Answers the measured (lufs, peak) of the export, or None when the instance
    did not come up."""
    launched = mcp_module.launch(
        proof_app.binary(),
        arguments=["-FrameJobNormalizeMode", mode, "-FrameJobNormalizeTargetLUFS", "-16"])
    try:
        if not check(launched.client is not None, f"N10 a {mode}-mode instance comes up"):
            return None
        other = launched.client
        s = Session(other, label)
        clip = place(s, "steady.wav")
        s.op("set_selection", clips=[clip])
        s.op("perform_menu_item", path=["Clip", "Normalize"])
        lufs, _, peak = measure(s, label)
        other.call("close_project", project=s.path, discard=True)
        return lufs, peak
    finally:
        launched.stop()


def menu_rows(m):
    print("\nN10 — Clip > Normalize follows the chosen mode")
    measured = menu_leg("peak", "loudness-menu-peak")
    if measured is not None:
        check(near(measured[1], -1, 0.1),
              f"N10 launched in Peak mode: {f(measured[1])} dBFS")
    measured = menu_leg("loudness", "loudness-menu-loudness")
    if measured is not None:
        check(near(measured[0], -16, 0.5),
              f"N10 launched in Loudness mode: {f(measured[0])} LUFS")


def main():
    os.makedirs(p5.WORK, exist_ok=True)
    fixtures()
    m = MCP(p5.SOCKET)
    for part in (schema_rows, refusal_rows, steady_rows, peaky_rows, match_rows, rode_rows,
                 kinds_rows, menu_rows):
        try:
            part(m)
        except (ToolError, KeyError, IndexError, RuntimeError, OSError) as error:
            check(False, f"{part.__name__} aborted: {type(error).__name__}: {error}")
    print(f"\n{checks - len(failures)}/{checks} checks passed")
    for line in failures:
        print(f"  FAILED: {line}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
