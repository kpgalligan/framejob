"""The clip limiter over MCP (road map "audio" AP2, spec §11 AU-20..AU-23).

Usage: python3 tools/proof/limiter_proof.py <dir>/agent.sock

Every ceiling is MEASURED on an exported WAV by limiter_probe.py's two meters
(`true_peaks`: a 4x, 64-tap-per-phase Kaiser beta 10 oversampler and BS.1770-4
Annex 2's phases, both over |x|), never read back from the app alone.

  P1  set_audio's limiter: {} stores the defaults (-1 dBTP, 60000 ticks), a
      value round-trips, each bound and an unknown key is refused by name and
      changes nothing, null clears it.
  P2  S1's crest signal (halved, stereo) at volume 8 under -1 dBTP: the export's
      true peak <= -1 + 0.001 dB by both meters (unlimited it reads about +8).
  P3  the same under -3 dBTP: <= -3 + 0.001 dB.
  P4  a clip at volume 1 then one at volume 8 abutting it, both under -1 dBTP:
      <= -1 + 0.001 dB across the cut; and a quiet clip with no limiter at
      volume 8 then the crest clip at volume 8 under -1 dBTP: <= -1 + 0.001 dB
      (the tap looks its spans up 1,975 ticks ahead, AU-23; M26 removes that
      and fails the second leg: the first cannot see it, since the fader's
      slew from 1 to 8 at the cut, #87, holds the crest clip's first 3.3 ms
      near x1).
  P5  a limiter set then cleared exports the same PCM bytes as one never set.
  P6  the saved file is at the header's RC_FORMAT_VERSION (format_version(),
      never a literal: 30 when AU-21 landed) and carries "limiter" only on the
      clip that has one; a project with none has no "limiter" key at all.
"""

import json
import os
import re
import sys
import wave

import numpy as np

import limiter_probe
import phase5_proof as p5
from mcp import MCP, ToolError
from phase5_proof import Session, pcm

HEADER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "core", "include",
                      "framejob_core.h")

checks = 0
failures = []


def format_version():
    """`RC_FORMAT_VERSION` off the tree's own header, not a copy: a copy goes stale at every bump."""
    with open(HEADER) as f:
        match = re.search(r"#define RC_FORMAT_VERSION (\d+)", f.read())
    if match is None:
        raise RuntimeError(f"{HEADER} has no `#define RC_FORMAT_VERSION <n>` line")
    return int(match.group(1))


FIXTURE = "limiter-crest.wav"
QUIET = "limiter-quiet.wav"


def check(ok, what):
    global checks
    checks += 1
    print(("  ok   " if ok else "  FAIL ") + what)
    if not ok:
        failures.append(what)
    return ok


def fixtures():
    """S1's crest signal halved (every sample inside 16 bits' range), stereo:
    left forward, right reversed."""
    os.makedirs(p5.FIXTURES, exist_ok=True)
    crest = limiter_probe.crest_signal() / 2
    stereo = np.stack([crest, crest[::-1]], axis=1)
    ints = np.clip(np.round(stereo * 32767), -32768, 32767).astype("<i2")
    with wave.open(os.path.join(p5.FIXTURES, FIXTURE), "wb") as handle:
        handle.setnchannels(2)
        handle.setsampwidth(2)
        handle.setframerate(48000)
        handle.writeframes(ints.tobytes())
    # A 1 kHz tone at 0.02 for 3 s: -16 dBFS at volume 8, nowhere near the ceiling.
    tone = 0.02 * np.sin(2 * np.pi * 1000 * np.arange(3 * 48000) / 48000)
    quiet = np.round(np.stack([tone, tone], axis=1) * 32767).astype("<i2")
    with wave.open(os.path.join(p5.FIXTURES, QUIET), "wb") as handle:
        handle.setnchannels(2)
        handle.setsampwidth(2)
        handle.setframerate(48000)
        handle.writeframes(quiet.tobytes())


def peaks(result, ceiling):
    kaiser, annex = limiter_probe.true_peaks(result["path"])
    return kaiser, annex, kaiser <= ceiling + 0.001 and annex <= ceiling + 0.001


def setting_rows(m):
    print("\nP1 — set_audio's limiter")
    s = Session(m, "limiter-set")
    clip = s.place(FIXTURE)
    s.op("set_audio", clips=[clip], patch={"limiter": {}})
    check(s.clip(clip)["audio"].get("limiter") == {"ceiling_db": -1.0, "release": 60000},
          f"P1 {{}} stores the defaults: {s.clip(clip)['audio'].get('limiter')}")
    s.op("set_audio", clips=[clip], patch={"limiter": {"ceiling_db": -2.5, "release": 30000}})
    check(s.clip(clip)["audio"].get("limiter") == {"ceiling_db": -2.5, "release": 30000},
          f"P1 a value round-trips: {s.clip(clip)['audio'].get('limiter')}")
    for patch, name in [({"ceiling_db": 0.5}, "audio.limiter.ceiling_db"),
                        ({"ceiling_db": -25}, "audio.limiter.ceiling_db"),
                        ({"release": 599}, "audio.limiter.release"),
                        ({"release": 600001}, "audio.limiter.release"),
                        ({"ceiling": -2}, "limiter.ceiling")]:
        text = s.error("set_audio", clips=[clip], patch={"limiter": patch}) or ""
        check(name in text and "made no change" not in text,
              f"P1 {patch} refused naming {name}: {text[:120]!r}")
    check(s.clip(clip)["audio"].get("limiter") == {"ceiling_db": -2.5, "release": 30000},
          "P1 and the refusals changed nothing")
    s.op("set_audio", clips=[clip], patch={"limiter": None})
    check("limiter" not in s.clip(clip)["audio"],
          f"P1 null clears it: {s.clip(clip)['audio'].get('limiter')}")
    m.call("close_project", project=s.path, discard=True)


def ceiling_rows(m):
    for row, ceiling in (("P2", -1.0), ("P3", -3.0)):
        print(f"\n{row} — the crest signal x8 under {ceiling:g} dBTP")
        s = Session(m, f"limiter-{row.lower()}")
        clip = s.place(FIXTURE)
        s.op("set_audio", clips=[clip],
             patch={"volume": 8, "limiter": {"ceiling_db": ceiling}})
        kaiser, annex, under = peaks(s.export(row.lower()), ceiling)
        check(under, f"{row} the export's true peak {kaiser:.4f} (Kaiser) / {annex:.4f} "
              f"(Annex 2) dBTP at or under {ceiling:g} + 0.001")
        if row == "P2":
            s.op("set_audio", clips=[clip], patch={"limiter": None})
            kaiser, annex, _ = peaks(s.export("p2-unlimited"), ceiling)
            check(kaiser > 6, f"P2 and without the limiter it reads {kaiser:.2f} dBTP")
        m.call("close_project", project=s.path, discard=True)


def cut_rows(m):
    print("\nP4 — volume 1 then volume 8, abutting, both under -1 dBTP")
    s = Session(m, "limiter-cut")
    first = s.place(FIXTURE)
    end = s.clip(first)["start"] + s.clip(first)["duration"]
    second = s.place(FIXTURE, at=end)
    s.op("set_audio", clips=[first], patch={"volume": 1, "limiter": {}})
    s.op("set_audio", clips=[second], patch={"volume": 8, "limiter": {}})
    check(s.clip(second)["start"] == end, f"P4 the clips abut at {end} ticks")
    kaiser, annex, under = peaks(s.export("p4"), -1.0)
    check(under, f"P4 the export's true peak {kaiser:.4f} (Kaiser) / {annex:.4f} (Annex 2) "
          "dBTP at or under -1 + 0.001 across the cut")
    m.call("close_project", project=s.path, discard=True)

    print("\nP4 — a quiet clip with no limiter, then the crest clip, both at volume 8")
    s = Session(m, "limiter-cut-lead")
    first = s.place(QUIET)
    end = s.clip(first)["start"] + s.clip(first)["duration"]
    second = s.place(FIXTURE, at=end)
    s.op("set_audio", clips=[first], patch={"volume": 8})
    s.op("set_audio", clips=[second], patch={"volume": 8, "limiter": {}})
    kaiser, annex, under = peaks(s.export("p4-lead"), -1.0)
    check(under, f"P4 the export's true peak {kaiser:.4f} (Kaiser) / {annex:.4f} (Annex 2) "
          "dBTP at or under -1 + 0.001: the crest clip's first 3.3 ms meet its own limiter")
    m.call("close_project", project=s.path, discard=True)


def cleared_rows(m):
    print("\nP5 — set then cleared exports what never-set does")
    s = Session(m, "limiter-never")
    clip = s.place(FIXTURE)
    s.op("set_audio", clips=[clip], patch={"volume": 2})
    never = pcm(s.export("p5-never")["path"])
    m.call("close_project", project=s.path, discard=True)
    s = Session(m, "limiter-cleared")
    clip = s.place(FIXTURE)
    s.op("set_audio", clips=[clip], patch={"volume": 2, "limiter": {"ceiling_db": -6}})
    s.op("set_audio", clips=[clip], patch={"limiter": None})
    cleared = pcm(s.export("p5-cleared")["path"])
    check(len(never) > 0 and never == cleared,
          f"P5 {len(cleared)} bytes against {len(never)}: "
          f"{'identical' if never == cleared else 'DIFFERENT'}")
    m.call("close_project", project=s.path, discard=True)


def saved_rows(m):
    print("\nP6 — the saved file")
    s = Session(m, "limiter-saved")
    a = s.place(FIXTURE)
    b = s.place(FIXTURE, at=10 * p5.SEC)
    m.call("save_project", project=s.path)
    with open(os.path.join(s.path, "project.json")) as handle:
        plain = handle.read()
    s.op("set_audio", clips=[a], patch={"limiter": {"ceiling_db": -2}})
    m.call("save_project", project=s.path)
    with open(os.path.join(s.path, "project.json")) as handle:
        text = handle.read()
    saved = json.loads(text)
    clips = {c["id"]: c for c in saved["clips"]}
    check(saved.get("version") == format_version(),
          f"P6 the file is version {saved.get('version')}, the header's {format_version()}")
    check(clips[a]["audio"].get("limiter") == {"ceiling_db": -2.0, "release": 60000}
          and "limiter" not in clips[b]["audio"] and text.count('"limiter"') == 1,
          f"P6 limiter on clip {a} only ({text.count(chr(34) + 'limiter' + chr(34))} key)")
    check('"limiter"' not in plain, "P6 before it was set, the file had no limiter key")
    m.call("close_project", project=s.path, discard=True)


def main():
    os.makedirs(p5.WORK, exist_ok=True)
    fixtures()
    m = MCP(p5.SOCKET)
    for part in (setting_rows, ceiling_rows, cut_rows, cleared_rows, saved_rows):
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
