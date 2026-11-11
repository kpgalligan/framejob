"""Enhance Voice over MCP and exports (road map "audio" AP6 part 1, spec §11
AU-60..AU-65).

Usage: python3 tools/proof/audio_ap6_proof.py <dir>/agent.sock

Every claim about sound is MEASURED on an exported WAV: loudness by
phase5_proof's BS.1770 (`integrated`), true peak by limiter_probe's two meters
(`true_peaks`, ceiling + 0.001 dB), the pause floor as eq_proof's `report` (the
10th percentile of 50 ms RMS frames). Fixtures: the owner's
samples/Rode-usb-mic.m4a, and `say` speech made here — one low-passed at
3.5 kHz (no sibilance), one high-shelved +15 dB above 5 kHz (hot sibilance).

  V1   the owner's recording: enhance_voice's row (measurements, `set`,
       reasons, processed_lufs, renders) printed; `set` holds the nine keys
       and get_project holds them.
  V2   its export at −16 ±0.5 LUFS and ≤ −1 dBTP by both meters; limited_by
       null; |result_lufs − the export| ≤ 0.2 LU; renders ≥ 2 (R0 and a verify
       render); the press timed three times (this one and two fresh projects,
       each rendering its isolation window cold) and printed.
  V3   its export's pause floor at least 10 dB under a Normalize-only export's.
  V4   a second call, and normalize_clip (loudness, −16) after it: "made no change".
  V5   one undo ("Enhance Voice") restores the audio group.
  V6   the low-passed `say` speech: the de-esser off.
  V7   the high-shelved `say` speech: the de-esser on at its defaults.
  V8   Clip ▸ Enhance Voice through perform_menu_item, on an instance launched
       with a −18 target in its argument domain (`<real>-18</real>`: a bare
       −18 is read as a flag and never arrives, #404; −18 because −16 is the
       default, which an argument that did not arrive would also give). On
       that instance enhance_voice {target_lufs: −18} first, its `set` kept
       and undone; then the menu, waiting for the Measuring Sound sheet to
       go: it writes what the tool wrote (the volume within 0.05 dB).
  V9   two clips in one call: a row each, each clip its own settings, one undo.
  V10  a silent clip skipped by name beside an enhanced one; alone, "Nothing
       could be enhanced"; target_lufs −51 and −4 and an unknown key refused by
       name, changing nothing.
  V11  the parity log is clean (no "Frame Job: " line in the instance's log).
  V12  the owner's recording at ×1.5 (`set_speed`; isolated at any speed
       since #387, spec §11 AU-55 as amended): isolation 0.8, noise
       reduction 0, a gate, its export's pause floor at least
       10 dB under a Normalize-only export at the same speed, and the export
       at −16 ±0.5 LUFS.
  V13  normalize_clip alone on the owner's recording at volume 2: (a) with
       isolation 0.8 and (b) with an EQ (high-pass 80 Hz 24 dB/oct, band 3
       4 kHz +3 dB q 1, high shelf 6 kHz +6 dB), processed_lufs differs from
       measured_lufs, renders ≥ 1, the export at −16 ±0.5 and a second call
       "made no change"; (c) a plain clip: processed_lufs null, renders 0, and
       the cache plan's −16.
  V14  an instance launched with -RCDevRampRenderHold 3, each leg on its own
       fresh project whose cache/isolated/ is absent or empty: (a) Clip ▸
       Enhance Voice puts up the Measuring Sound sheet (seen in snapshot_ui,
       else FAIL), cancel_sheet, and after the hold the clip is unchanged;
       (b) the sheet seen, then set_audio {pan: 0.2} during the hold: once
       the sheet goes, the clip differs from before by the pan alone.
  V15  At volume (snapshot_ui's layout dump, the Sound sub-tab) after Enhance
       within ±0.2 of −16 LUFS with no "≈"; after an EQ change, "≈ " and the
       tooltip saying why.
  V16  a stage only at an action's end (AU-159, #402): the owner's recording
       with one action from 1 s for 2 s whose end is an EQ (band 3 and a high
       shelf), nothing on the clip. (a) At volume starts with "≈" before any press; (b)
       normalize_clip (loudness, −16): processed_lufs differs from
       measured_lufs, renders ≥ 1, the export at −16 ±0.5, a second call "made
       no change"; (c) At volume after it within ±0.2 of −16 with no "≈"; (d)
       with the end also naming a volume, At volume reads the same with the
       playhead inside the action (the action selected) as at 0; (e) another
       shelf gain at the end: "≈" again. (f) an action end that is a gate
       AND a limiter at −6 dBTP, on a clip whose own limiter is on, so the
       solve verifies by render (target −20): renders ≥ 2, |result_lufs − the
       export| ≤ 0.2, the export at −20 ±0.5 and limited_by null. (g) the same end at
       −24 dBTP on a clip with no limiter, target −30: the solve's one-render
       arm, which no render checks; renders 1, and the miss between
       result_lufs and the export PRINTED (AU-159 (b)'s recorded limit, #402's
       open half), never scored.
  V17  the clip limiter at a speed other than ×1 (#399, spec §11 AU-162): the
       owner's recording, a gate and the limiter at −1 dBTP, normalize_clip
       (loudness, −18), one fresh project per leg: (a) ×1; (b) ×1.5 and (f)
       ×0.75 Keep pitch off and (g) a Speed Dip to ×0.7 with Keep pitch on,
       all three RENDERED ahead of the tap (AU-55); (c) ×1.5, (d) ×0.5 and (e)
       ×1.02 Keep pitch on, LIVE; (h) ×1.5 Keep pitch on with #399's own chain
       (the Rumble Cut, noise reduction 0.5, Enhance's gate and compressor,
       target −16). Every leg: renders ≥ 2 and limited_by null (the reading is
       a verify render's, not the model's capped figure), the limiter has
       3 dB or more to take off (R0's peak at the solved volume over the
       ceiling), the audio_wav export ≤ −1 dBTP by both meters (its master),
       and the TAP's own output holds the ceiling: the live meter's true peak
       (AU-70: the tap's block × the fader) over a 6 s preview play around
       the pre-master stem's largest sample ≤ −1 + 0.001. (a), (b), (f), (g):
       the clip holds its ceiling, the verify render and the stem (`stems:
       tracks`, no master) ≤ −1 + 0.001. (c), (d), (e), (h): the verify
       render and the stem against the ceiling PRINTED, never scored: the
       time-pitch runs after the tap and re-shapes the peaks the limiter held,
       either way and differently from one render to the next (AU-162). A
       stem is an integer file, so it reads no sample over 0 dBFS.
       AP6_LEGS=a,c runs only those legs.
"""

import json
import os
import subprocess
import sys
import time

import limiter_probe
import mcp as mcp_module
import phase5_proof as p5
import proof_app
from eq_proof import report
from mcp import MCP, ToolError
from phase5_proof import Session, channels, integrated, pcm

import numpy as np

ROOT = os.path.dirname(os.path.dirname(p5.HERE))
RODE = os.path.join(ROOT, "samples", "Rode-usb-mic.m4a")
RATE = 48000
# The leveller since AP6b (AU-67): every V-row that checks the set (V1, the owner's
# recording) has over 3 s of speech.
OWNED = ["compressor", "de_esser", "eq", "gate", "isolation", "leveller", "limiter",
         "noise_reduction", "volume"]
# V13 (b)'s and V15's EQ: high-pass 80 Hz 24 dB/oct, band 3 4 kHz +3 dB q 1, high
# shelf 6 kHz +6 dB, every slot named as the patch writes it.
EQ = {"high_pass": {"frequency": 80, "slope": 24}, "low_shelf": None, "band_1": None,
      "band_2": None, "band_3": {"frequency": 4000, "gain_db": 3, "q": 1},
      "high_shelf": {"frequency": 6000, "gain_db": 6}, "low_pass": None, "bypass": False}
SENTENCE = ("She sells seashells by the seashore, and the shells she sells are surely "
            "seashells. Six slippery snails slid slowly seaward. Sister Suzy sat on the sofa "
            "sewing shirts for soldiers, sixty-six of them, so she says.")

checks = 0
failures = []


def check(ok, what):
    global checks
    checks += 1
    print(("  ok   " if ok else "  FAIL ") + what)
    if not ok:
        failures.append(what)
    return ok


def f(x, places=2):
    return "None" if x is None else f"{x:.{places}f}"


def fixtures():
    os.makedirs(p5.FIXTURES, exist_ok=True)
    out = p5.FIXTURES

    def ffmpeg(*args):
        subprocess.run(["ffmpeg", "-v", "error", "-y", *args], check=True)

    ffmpeg("-i", RODE, "-c:a", "pcm_s16le", "-ar", str(RATE), "-ac", "1",
           os.path.join(out, "ap6-rode.wav"))
    aiff = os.path.join(out, "ap6-say.aiff")
    subprocess.run(["say", "-o", aiff, SENTENCE], check=True)
    ffmpeg("-i", aiff, "-af",
           "volume=-6dB,lowpass=f=3500,lowpass=f=3500,lowpass=f=3500,lowpass=f=3500",
           "-c:a", "pcm_s16le", "-ar", str(RATE), "-ac", "1", os.path.join(out, "ap6-dull.wav"))
    ffmpeg("-i", aiff, "-af", "volume=-18dB,highshelf=f=5000:g=15", "-c:a", "pcm_s16le",
           "-ar", str(RATE), "-ac", "1", os.path.join(out, "ap6-hiss.wav"))
    ffmpeg("-f", "lavfi", "-i", f"anullsrc=r={RATE}:cl=mono", "-t", "2", "-c:a", "pcm_s16le",
           os.path.join(out, "ap6-silence.wav"))


def ready(s, clip):
    """Waits for the clip's media's loudness and speech caches (the import
    makes both on the cache lane)."""
    media = s.clip(clip)["source"]["media"]
    markers = [os.path.join(s.path, "cache", kind, f"{media}.complete.json")
               for kind in ("loudness", "speech")]
    p5.wait_for_files(markers, f"{s.name}: media {media}'s loudness or speech cache")
    return clip


def place(s, name, at=0, track=None):
    return ready(s, s.place(name, at=at, track=track))


def mono(path):
    return np.array(channels(pcm(path))[0])


def floor_of(path):
    return report(mono(path))[0]


def measure(path):
    """(integrated LUFS, Kaiser dBTP, Annex 2 dBTP, pause floor dBFS)."""
    lufs = integrated(channels(pcm(path)))
    kaiser, annex = limiter_probe.true_peaks(path)
    return lufs, kaiser, annex, floor_of(path)


def enhance(s, clips, **kwargs):
    return s.op("enhance_voice", clips=clips, **kwargs)


def audio(s, clip):
    return s.clip(clip).get("audio") or {}


def clean(value):
    """A value with its null keys dropped, at every depth, and the EQ's
    `bypass: false`: the model writes an off slot and an unbypassed EQ by
    leaving the key out."""
    if isinstance(value, dict):
        return {k: clean(v) for k, v in value.items()
                if v is not None and not (k == "bypass" and v is False)}
    return value


def holds(audio_group, set_):
    """Each key Enhance set, read back from get_project (a null as absent, and
    isolation 0 as absent: the model writes it only when not 0)."""
    return not mismatches(audio_group, set_)


def mismatches(audio_group, set_, volume_db=1e-6):
    """The keys of `set_` that get_project's group does not hold; the volume
    within `volume_db` dB (by default 1e-6 dB, a JSON round trip)."""
    defaults = {"isolation": 0, "noise_reduction": 0}
    out = []
    for key, value in set_.items():
        held = audio_group.get(key)
        if held is None:
            held = defaults.get(key)
        if key == "volume" and volume_db and held and value:
            if abs(20 * np.log10(held / value)) <= volume_db:
                continue
        if clean(held) != clean(value):
            out.append(f"{key}: {held!r} against {value!r}")
    return out


def print_row(row):
    measured = {k: row[k] for k in ("measured_lufs", "true_peak_dbtp", "speech_seconds",
                                    "floor_lufs", "floor_gap_db", "pause_peak_dbfs",
                                    "sibilance_share")}
    print(f"  note measured {json.dumps(measured)}")
    print(f"  note set {json.dumps(row['set'], sort_keys=True)}")
    for reason in row["reasons"]:
        print(f"  note reason {reason}")
    print(f"  note volume {f(row['volume'], 4)}, processed {f(row.get('processed_lufs'))} LUFS, "
          f"renders {row.get('renders')}, result {f(row['result_lufs'])} LUFS, "
          f"{f(row['result_true_peak_dbtp'])} dBTP, limited_by {row['limited_by']}")


def timed(call):
    """(answer, seconds) of one call."""
    began = time.monotonic()
    answer = call()
    return answer, time.monotonic() - began


def wait_no_sheet(s, bound=600):
    """Seconds until the project's window has no sheet (perform_menu_item's
    listing, polled every 0.1 s), or None past `bound`."""
    began = time.monotonic()
    while time.monotonic() - began < bound:
        listing = s.op("perform_menu_item")
        if ((listing.get("window") or {}).get("sheet")) is None:
            return time.monotonic() - began
        time.sleep(0.1)
    return None


def layout(s, window, label):
    """snapshot_ui's layout views for `window` ("editor" or "sheet"), or []."""
    picture = os.path.join(p5.WORK, f"ap6-{label}-{os.getpid()}.png")
    try:
        shot = s.op("snapshot_ui", window=window, path=picture)
        with open(shot.get("layout_path") or "") as handle:
            return json.load(handle)["views"]
    except (ToolError, OSError, ValueError, KeyError):
        return []


def sheet_texts(s):
    return [v.get("text") for v in layout(s, "sheet", "sheet")
            if not v.get("hidden") and v.get("text")]


def at_volume(s):
    """(text, tooltip) of the Volume section's At volume read-out: the first
    `option.display` part after the "At volume" label, and its control's
    tooltip; (None, None) when not found."""
    views = layout(s, "editor", "editor")
    start = next((i for i, v in enumerate(views) if v.get("text") == "At volume"), None)
    if start is None:
        return None, None
    for v in views[start + 1:]:
        if v.get("class") == "UISnapshotPart" and v.get("id") == "option.display":
            control = views[v["parent"]] if 0 <= v.get("parent", -1) < len(views) else {}
            return v.get("text"), control.get("tooltip")
    return None, None


def lufs_of(text):
    """The LUFS figure in a read-out's text, or None."""
    try:
        return float(text.replace("≈ ", "").split(" LUFS")[0].replace("−", "-"))
    except (AttributeError, ValueError):
        return None


# ---- V1–V5 the owner's recording ----------------------------------------------

def owner_rows(m):
    print("\nV1–V5, V15 — the owner's recording")
    s = Session(m, "ap6-owner")
    clip = place(s, "ap6-rode.wav")
    before = audio(s, clip)
    s.op("normalize_clip", clips=[clip], mode="loudness", target_lufs=-16)
    plain = measure(s.export("normalized")["path"])
    answer, seconds = timed(lambda: enhance(s, [clip]))
    row = answer["enhanced"][0]
    print_row(row)
    print(f"  note press 1 (cold, its isolation window rendered): {seconds:.2f} s")
    check(answer.get("target_lufs") == -16 and answer.get("ceiling_dbtp") == -1
          and sorted(row["set"]) == OWNED and holds(audio(s, clip), row["set"])
          and len(row["reasons"]) >= 6,
          f"V1 the row sets exactly {OWNED}, get_project holds them, one reason per rule "
          f"{mismatches(audio(s, clip), row['set'])}")
    lufs, kaiser, annex, floor = measure(s.export("enhanced")["path"])
    check(abs(lufs + 16) <= 0.5 and row["limited_by"] is None,
          f"V2 the export at {f(lufs)} LUFS (−16 ±0.5), limited_by {row['limited_by']}")
    check(kaiser <= -1 + 0.001 and annex <= -1 + 0.001,
          f"V2 true peak {f(kaiser, 4)} (Kaiser) / {f(annex, 4)} (Annex 2) dBTP ≤ −1")
    check(abs(row["result_lufs"] - lufs) <= 0.2 and (row.get("renders") or 0) >= 2
          and row.get("processed_lufs") is not None,
          f"V2 result_lufs {f(row['result_lufs'])} against the export {f(lufs)} "
          f"({f(row['result_lufs'] - lufs)} LU, ≤ 0.2); renders {row.get('renders')} (≥ 2); "
          f"processed {f(row.get('processed_lufs'))} against measured "
          f"{f(row.get('measured_lufs'))}")
    check(floor <= plain[3] - 10,
          f"V3 pause floor {f(floor)} dBFS against Normalize-only {f(plain[3])} "
          f"({f(floor - plain[3])} dB, ≤ −10); Normalize-only at {f(plain[0])} LUFS")
    s.op("set_selection", clips=[clip])
    s.op("select_inspector_tab", tab="clip", sub_tab="sound")
    text, tip = at_volume(s)
    shown = lufs_of(text)
    check(shown is not None and abs(shown + 16) <= 0.2 and "≈" not in (text or ""),
          f"V15 At volume after Enhance {text!r} (−16 ±0.2, no ≈)")
    second, warm = timed(lambda: s.error("enhance_voice", clips=[clip]) or "")
    normal = s.error("normalize_clip", clips=[clip], mode="loudness", target_lufs=-16) or ""
    print(f"  note a second press (warm, its isolation window cached): {warm:.2f} s")
    check("made no change" in second and "made no change" in normal,
          f"V4 a second call and Normalize after it: {second[:70]!r} / {normal[:70]!r}")
    undone = s.undo()
    restored = audio(s, clip)
    s.undo()
    check(undone == "Enhance Voice" and restored.get("volume") != row["set"]["volume"]
          and restored.get("compressor") is None and restored.get("gate") is None,
          f"V5 one undo ({undone!r}) takes the audio group back to Normalize's: "
          f"{sorted(restored)}")
    check(audio(s, clip) == before, "V5 and a second undo to the import's")
    s.op("set_audio", clips=[clip], patch={"eq": EQ})
    text, tip = at_volume(s)
    check((text or "").startswith("≈ ") and (tip or "").startswith("≈ before the clip's"),
          f"V15 after an EQ change At volume {text!r}, tooltip {tip!r}")
    m.call("close_project", project=s.path, discard=True)
    return row, seconds


def timing_rows(m, first):
    """V2's press time: the first press and two more on fresh projects, each
    rendering its isolation window cold."""
    print("\nV2 — the press, timed three times")
    times = [first]
    for run in (2, 3):
        s = Session(m, f"ap6-time{run}")
        clip = place(s, "ap6-rode.wav")
        answer, seconds = timed(lambda: enhance(s, [clip]))
        times.append(seconds)
        print(f"  note press {run} (cold): {seconds:.2f} s, renders "
              f"{answer['enhanced'][0].get('renders')}")
        m.call("close_project", project=s.path, discard=True)
    check(len(times) == 3, "V2 press times (s): " + ", ".join(f"{t:.2f}" for t in times))


# ---- V6, V7 sibilance --------------------------------------------------------

def sibilance_rows(m):
    print("\nV6, V7 — the de-esser off and on")
    for name, label, want in (("ap6-dull.wav", "V6 low-passed at 3.5 kHz", None),
                              ("ap6-hiss.wav", "V7 high-shelved +15 dB at 5 kHz",
                               {"frequency": 6000.0, "threshold_db": 0.0, "range_db": 6.0})):
        s = Session(m, f"ap6-{name[4:8]}")
        clip = place(s, name)
        row = enhance(s, [clip])["enhanced"][0]
        check(row["set"]["de_esser"] == want and audio(s, clip).get("de_esser") == want,
              f"{label}: sibilant share {f(row['sibilance_share'], 3)}, de_esser "
              f"{row['set']['de_esser']}")
        m.call("close_project", project=s.path, discard=True)


# ---- V8 the menu --------------------------------------------------------------

# V8's target: not the default (−16), so a launch argument that never reached
# the app is a volume about 2 dB from the tool's (#404).
MENU_TARGET = -18
MENU_ARGUMENT = f"<real>{MENU_TARGET}</real>"


def menu_rows(m):
    print(f"\nV8 — Clip ▸ Enhance Voice writes what the tool writes, at {MENU_TARGET} LUFS")
    launched = mcp_module.launch(
        proof_app.binary(), arguments=["-FrameJobNormalizeTargetLUFS", MENU_ARGUMENT])
    try:
        if not check(launched.client is not None,
                     f"V8 an instance with the {MENU_TARGET} target comes up"):
            return
        other = launched.client
        s = Session(other, "ap6-menu")
        clip = place(s, "ap6-rode.wav")
        before = audio(s, clip)
        answer = enhance(s, [clip], target_lufs=MENU_TARGET)
        tool_row = answer["enhanced"][0]
        undone = s.undo()
        check(answer.get("target_lufs") == MENU_TARGET and undone == "Enhance Voice"
              and audio(s, clip) == before,
              f"V8 the tool at target_lufs {answer.get('target_lufs')} (volume "
              f"{tool_row['set']['volume']}), then one undo ({undone!r}) back to the clip "
              f"as placed")
        s.op("set_selection", clips=[clip])
        menu = s.op("perform_menu_item", path=["Clip", "Enhance Voice"])
        gone = wait_no_sheet(s)
        held = audio(s, clip)
        check(gone is not None and not mismatches(held, tool_row["set"], volume_db=0.05),
              f"V8 the menu (sheet {menu.get('sheet')!r}, gone after "
              f"{gone if gone is None else round(gone, 2)} s) holds the tool's set: volume "
              f"{held.get('volume')} against {tool_row['set']['volume']} (±0.05 dB) "
              f"{mismatches(held, tool_row['set'], volume_db=0.05)}")
        other.call("close_project", project=s.path, discard=True)
    finally:
        launched.stop()


# ---- V9, V10 two clips, skips and refusals ----------------------------------

def selection_rows(m):
    print("\nV9, V10 — two clips; skips and refusals")
    s = Session(m, "ap6-two")
    a = place(s, "ap6-rode.wav")
    b = place(s, "ap6-hiss.wav", track=s.add_track())
    answer = enhance(s, [a, b])
    rows = {r["clip"]: r for r in answer["enhanced"]}
    check(sorted(rows) == sorted([a, b]) and rows[a]["volume"] != rows[b]["volume"]
          and holds(audio(s, a), rows[a]["set"]) and holds(audio(s, b), rows[b]["set"]),
          f"V9 a row each, each its own: volumes {f(rows.get(a, {}).get('volume'), 3)} and "
          f"{f(rows.get(b, {}).get('volume'), 3)}")
    undone = s.undo()
    check(undone == "Enhance Voice" and audio(s, a).get("compressor") is None
          and audio(s, b).get("compressor") is None, f"V9 one undo ({undone!r}) takes back both")
    silent = place_silent(s)
    answer = enhance(s, [a, silent])
    skipped = answer.get("skipped") or []
    check(len(answer["enhanced"]) == 1 and len(skipped) == 1
          and skipped[0].startswith(f"clip {silent}: is under −70 LUFS"),
          f"V10 the silent clip skipped by name: {skipped}")
    alone = s.error("enhance_voice", clips=[silent]) or ""
    check("Nothing could be enhanced." in alone and f"clip {silent}" in alone,
          f"V10 alone: {alone[:90]!r}")
    project = s.project()
    for kwargs, name in (({"target_lufs": -51}, "target_lufs"),
                         ({"target_lufs": -4}, "target_lufs"), ({"mode": "loudness"}, "mode")):
        text = s.error("enhance_voice", clips=[a], **kwargs) or ""
        check(name in text and "made no change" not in text,
              f"V10 {kwargs} refused naming {name}: {text[:90]!r}")
    check(s.project() == project, "V10 and the refusals changed nothing")
    m.call("close_project", project=s.path, discard=True)


def place_silent(s):
    """The silent fixture on a track of its own: its loudness cache is waited
    for, and its speech cache (made too, empty of speech) as well."""
    return place(s, "ap6-silence.wav", track=s.add_track())


# ---- V12 the owner's recording at ×1.5 --------------------------------------

def speed_rows(m):
    print("\nV12 — the owner's recording at ×1.5")
    s = Session(m, "ap6-speed")
    clip = place(s, "ap6-rode.wav")
    s.op("set_speed", clip=clip, rate=1.5, keep_pitch=True)
    s.op("normalize_clip", clips=[clip], mode="loudness", target_lufs=-16)
    plain = floor_of(s.export("normalized")["path"])
    row = enhance(s, [clip])["enhanced"][0]
    print_row(row)
    print(f"  note V12 NOT SCORED (AU-162, #399): a live retimed clip, its verify render "
          f"{f(row['result_true_peak_dbtp'], 4)} dBTP, "
          f"{f(row['result_true_peak_dbtp'] - row['set']['limiter']['ceiling_db'], 4)} dB "
          f"against its limiter's ceiling")
    got = row["set"]
    check(got.get("noise_reduction") == 0 and got.get("isolation") == 0.8
          and isinstance(got.get("gate"), dict),
          f"V12 at ×1.5: isolation {got.get('isolation')}, noise_reduction "
          f"{got.get('noise_reduction')}, gate {got.get('gate')}")
    lufs, _, _, floor = measure(s.export("enhanced")["path"])
    check(floor <= plain - 10,
          f"V12 pause floor {f(floor)} dBFS against Normalize-only {f(plain)} "
          f"({f(floor - plain)} dB, ≤ −10)")
    check(abs(lufs + 16) <= 0.5,
          f"V12 the export at {f(lufs)} LUFS (−16 ±0.5); result_lufs {f(row['result_lufs'])}, "
          f"renders {row.get('renders')}")
    m.call("close_project", project=s.path, discard=True)


# ---- V17 the clip limiter at a speed other than ×1 (#399, AU-162) -------------

CEILING = -1.0
LIMITER_TARGET = -18
LIMITER_CHAIN = {"gate": {"threshold_db": -30}, "limiter": {"ceiling_db": CEILING}}
# #399's own chain, as Enhance Voice wrote it at ×1.5 before #387: the Rumble Cut,
# noise reduction 0.5, Enhance's gate and compressor for this recording, the limiter.
ISSUE_CHAIN = {"eq": {"high_pass": {"frequency": 80, "slope": 24}}, "noise_reduction": 0.5,
               "gate": {"threshold_db": -6, "ratio": 4, "range_db": 20},
               "compressor": {"threshold_db": -40, "ratio": 3, "makeup_db": 9},
               "limiter": {"ceiling_db": CEILING}}
ISSUE_TARGET = -16
PLAY_SECONDS = 6
TAP_TOLERANCE = 0.001
# (leg, what it is, the speed op or None, the chain, rendered ahead of the tap?)
LIMITER_LEGS = (
    ("a", "×1", None, LIMITER_CHAIN, True),
    ("b", "×1.5 Keep pitch off (rendered)", {"rate": 1.5, "keep_pitch": False},
     LIMITER_CHAIN, True),
    ("c", "×1.5 Keep pitch on (live)", {"rate": 1.5, "keep_pitch": True}, LIMITER_CHAIN, False),
    ("d", "×0.5 Keep pitch on (live)", {"rate": 0.5, "keep_pitch": True}, LIMITER_CHAIN, False),
    ("e", "×1.02 Keep pitch on (live, time-domain)", {"rate": 1.02, "keep_pitch": True},
     LIMITER_CHAIN, False),
    ("f", "×0.75 Keep pitch off (rendered)", {"rate": 0.75, "keep_pitch": False},
     LIMITER_CHAIN, True),
    ("g", "a Speed Dip to ×0.7, Keep pitch on (a ramp, rendered)",
     {"ramp": {"shape": "speed_dip", "rate": 0.7}}, LIMITER_CHAIN, True),
    ("h", "×1.5 Keep pitch on (live), #399's chain", {"rate": 1.5, "keep_pitch": True},
     ISSUE_CHAIN, False),
)


def stem_peak(path, start=None, seconds=None):
    """(Kaiser dBTP, Annex 2 dBTP, the largest sample's time in s) of a file's
    first channel, over `[start, start + seconds)` when given."""
    x = limiter_probe.channels_of(path)[0]
    if start is not None:
        x = x[max(0, int(start * RATE)):int((start + seconds) * RATE)]
    if not len(x):
        return -np.inf, -np.inf, 0.0
    return (limiter_probe.db(limiter_probe.kaiser_true_peak(x)),
            limiter_probe.db(limiter_probe.annex2_true_peak(x)),
            float(np.argmax(np.abs(x))) / RATE)


def tap_peak(s, at):
    """The live meter's true peak (the tap's own output × the fader, AU-70)
    over a preview play of PLAY_SECONDS from `at` seconds, and the seconds it
    measured; (None, 0) when the meter measured nothing."""
    s.op("set_playhead", t=int(round(at * 30)) * (SECOND // 30))
    s.op("loudness_meter", reset=True)
    deadline = time.monotonic() + 60
    while True:
        try:
            s.op("play_preview", seconds=PLAY_SECONDS)
            break
        except ToolError as error:
            if "nothing to play" not in str(error) or time.monotonic() > deadline:
                raise
            time.sleep(0.5)
    got = s.op("loudness_meter")
    peak = got.get("true_peak_dbtp")
    frames = (got.get("to_frame") or 0) - (got.get("from_frame") or 0)
    return (peak if isinstance(peak, (int, float)) else None,
            frames / (got.get("sample_rate") or RATE))


def limiter_speed_rows(m):
    print("\nV17 — the clip limiter at a speed other than ×1 (#399, AU-162)")
    only = set(filter(None, os.environ.get("AP6_LEGS", "").split(",")))
    for leg, what, speed, chain, rendered in LIMITER_LEGS:
        if only and leg not in only:
            continue
        s = Session(m, f"ap6-limit-{leg}")
        clip = place(s, "ap6-rode.wav")
        if speed and "ramp" in speed:
            s.op("add_speed_ramp", clip=clip, **speed["ramp"])
        elif speed:
            s.op("set_speed", clip=clip, **speed)
        s.op("set_audio", clips=[clip], patch=chain)
        row = s.op("normalize_clip", clips=[clip], mode="loudness",
                   target_lufs=ISSUE_TARGET if chain is ISSUE_CHAIN
                   else LIMITER_TARGET)["normalized"][0]
        volume, renders = row["volume"], row.get("renders") or 0
        # What the limiter has to take off: R0's pre-fader peak (no limiter) at
        # the solved volume, over the ceiling.
        work = row["true_peak_dbtp"] + 20 * np.log10(volume) - CEILING
        result = row["result_true_peak_dbtp"]
        exported = s.export("limited", stems="tracks")
        mix = limiter_probe.true_peaks(exported["path"])
        stems = exported.get("stems") or []
        kaiser, annex, peak_at = stem_peak(stems[0]["path"]) if stems else (None, None, 0.0)
        # The tap's side: the preview played around the stem's largest sample.
        at = max(0.0, peak_at - PLAY_SECONDS / 2)
        tap, measured = tap_peak(s, at)
        window = stem_peak(stems[0]["path"], at, PLAY_SECONDS) if stems else (None, None, 0.0)
        duration = s.clip(clip)["duration"] / SECOND
        m.call("close_project", project=s.path, discard=True)
        label = f"V17 ({leg}) {what}"
        print(f"  note {label}: {f(duration)} s, volume {f(volume, 4)}, renders {renders}, "
              f"limited_by {row['limited_by']}, the limiter's work {f(work)} dB; the verify "
              f"render {f(result, 4)} dBTP ({f(result - CEILING, 4)} dB against the ceiling); "
              f"the stem (pre-master) {f(kaiser, 4)} (Kaiser) / {f(annex, 4)} (Annex 2) dBTP, "
              f"its largest sample at {f(peak_at)} s; the preview from {f(at)} s: the tap "
              f"{f(tap, 4)} dBTP over {f(measured)} s, the stem there {f(window[0], 4)} / "
              f"{f(window[1], 4)} dBTP")
        check(renders >= 2 and row["limited_by"] is None and work >= 3,
              f"{label}: the reading is a verify render's and the limiter is working "
              f"(renders {renders} ≥ 2, limited_by {row['limited_by']}, {f(work)} dB to take "
              f"off, ≥ 3)")
        check(max(mix) <= CEILING + 0.001,
              f"{label}: the export (its master) {f(mix[0], 4)} / {f(mix[1], 4)} dBTP ≤ −1")
        check(tap is not None and measured >= PLAY_SECONDS / 2 and tap <= CEILING + TAP_TOLERANCE,
              f"{label}: the tap's own output holds the ceiling in the preview "
              f"({f(tap, 4)} dBTP over {f(measured)} s, ≤ −1 + {TAP_TOLERANCE})")
        if rendered:
            check(result <= CEILING + 0.001 and kaiser is not None
                  and max(kaiser, annex) <= CEILING + 0.001,
                  f"{label}: the clip holds its ceiling: the verify render "
                  f"{f(result, 4)} dBTP, the stem {f(kaiser, 4)} / {f(annex, 4)} dBTP (≤ −1)")
        else:
            print(f"  note {label} NOT SCORED (AU-162, #399): the verify render "
                  f"{f(result - CEILING, 4)} dB and the stem "
                  f"{f(max(kaiser, annex) - CEILING, 4)} dB against the ceiling (the stem is "
                  f"another render and an integer file, with no sample over 0 dBFS)")


# ---- V13 normalize_clip through the chain ------------------------------------

def normalize_rows(m):
    print("\nV13 — normalize_clip on a processed clip, and a plain one")
    for leg, patch in (("(a) isolation 0.8", {"volume": 2, "isolation": 0.8}),
                       ("(b) the EQ", {"volume": 2, "eq": EQ})):
        s = Session(m, f"ap6-norm-{leg[1]}")
        clip = place(s, "ap6-rode.wav")
        s.op("set_audio", clips=[clip], patch=patch)
        answer, seconds = timed(lambda: s.op("normalize_clip", clips=[clip], mode="loudness",
                                             target_lufs=-16))
        row = answer["normalized"][0]
        processed, measured = row.get("processed_lufs"), row.get("measured_lufs")
        lufs = integrated(channels(pcm(s.export("normalized")["path"])))
        again = s.error("normalize_clip", clips=[clip], mode="loudness", target_lufs=-16) or ""
        check(processed is not None and abs(processed - measured) > 0.01
              and (row.get("renders") or 0) >= 1 and abs(lufs + 16) <= 0.5
              and "made no change" in again,
              f"V13 {leg}: processed {f(processed)} against measured {f(measured)} LUFS, "
              f"renders {row.get('renders')} in {seconds:.2f} s, volume {f(row['volume'], 4)}, "
              f"result {f(row['result_lufs'])}, the export at {f(lufs)} LUFS (−16 ±0.5); "
              f"again {again[:60]!r}")
        m.call("close_project", project=s.path, discard=True)
    s = Session(m, "ap6-norm-c")
    clip = place(s, "ap6-rode.wav")
    s.op("set_audio", clips=[clip], patch={"volume": 2})
    row = s.op("normalize_clip", clips=[clip], mode="loudness", target_lufs=-16)["normalized"][0]
    check(row.get("processed_lufs") is None and row.get("renders") == 0
          and abs(row["result_lufs"] + 16) <= 0.05 and row["limited_by"] is None,
          f"V13 (c) a plain clip: processed {row.get('processed_lufs')}, renders "
          f"{row.get('renders')}, the cache plan's volume {f(row['volume'], 4)} to "
          f"{f(row['result_lufs'])} LUFS")
    m.call("close_project", project=s.path, discard=True)


# ---- V16 a stage only at an action's end (AU-159, #402) ----------------------

SECOND = 600_000
# V16's end EQ: band 3 4 kHz +3 dB q 1 and a high shelf 6 kHz +6 dB.
END_EQ = {"band_3": {"frequency": 4000, "gain_db": 3, "q": 1},
          "high_shelf": {"frequency": 6000, "gain_db": 6}}


def keyed(s, clip, end, at=SECOND, duration=2 * SECOND):
    """One action on `clip` from `at` for `duration` whose end's audio is `end`;
    its id."""
    s.op("add_action", clip=clip, at=at, duration=duration)
    action = s.clip(clip)["actions"][-1]["id"]
    s.op("set_action_end", clip=clip, action=action, patch={"audio": end})
    return action


def action_rows(m):
    print("\nV16 — a stage only at an action's end")
    s = Session(m, "ap6-action")
    clip = place(s, "ap6-rode.wav")
    action = keyed(s, clip, {"eq": END_EQ})
    s.op("set_playhead", t=0)
    s.op("set_selection", clips=[clip])
    s.op("select_inspector_tab", tab="clip", sub_tab="sound")
    text, tip = at_volume(s)
    check((text or "").startswith("≈ ") and (tip or "").startswith("≈ before the clip's")
          and audio(s, clip).get("eq") is None,
          f"V16 (a) an EQ only at an action's end: At volume {text!r} before any press")
    answer, seconds = timed(lambda: s.op("normalize_clip", clips=[clip], mode="loudness",
                                         target_lufs=-16))
    row = answer["normalized"][0]
    processed, measured = row.get("processed_lufs"), row.get("measured_lufs")
    lufs = integrated(channels(pcm(s.export("normalized")["path"])))
    again = s.error("normalize_clip", clips=[clip], mode="loudness", target_lufs=-16) or ""
    check(processed is not None and abs(processed - measured) > 0.01
          and (row.get("renders") or 0) >= 1 and abs(lufs + 16) <= 0.5
          and "made no change" in again,
          f"V16 (b) normalize_clip: processed {f(processed)} against measured {f(measured)} "
          f"LUFS, renders {row.get('renders')} in {seconds:.2f} s, volume {f(row['volume'], 4)}, "
          f"result {f(row['result_lufs'])}, the export at {f(lufs)} LUFS (−16 ±0.5); again "
          f"{again[:60]!r}")
    text, _ = at_volume(s)
    shown = lufs_of(text)
    check(shown is not None and abs(shown + 16) <= 0.2 and "≈" not in (text or ""),
          f"V16 (c) At volume after it {text!r} (−16 ±0.2, no ≈)")
    s.op("set_action_end", clip=clip, action=action, patch={"audio": {"volume": 0.5}})
    outside, _ = at_volume(s)
    s.op("set_playhead", t=2 * SECOND)
    inside, _ = at_volume(s)
    s.op("set_playhead", t=0)
    check(outside is not None and outside == inside and "≈" not in outside,
          f"V16 (d) the end also naming volume 0.5: At volume {outside!r} with the playhead "
          f"at 0 and {inside!r} inside the action")
    s.op("set_action_end", clip=clip, action=action,
         patch={"audio": {"eq": {"high_shelf": {"frequency": 6000, "gain_db": 3}}}})
    text, _ = at_volume(s)
    check((text or "").startswith("≈ "),
          f"V16 (e) another shelf gain at the end: At volume {text!r}")
    m.call("close_project", project=s.path, discard=True)

    # (f) the verify arm: the clip's own limiter is on, so the solve checks by render.
    s = Session(m, "ap6-action-f")
    clip = place(s, "ap6-rode.wav")
    keyed(s, clip, {"gate": {"threshold_db": -30}, "limiter": {"ceiling_db": -6}})
    s.op("set_audio", clips=[clip], patch={"limiter": {"ceiling_db": -1}})
    row = s.op("normalize_clip", clips=[clip], mode="loudness",
               target_lufs=-20)["normalized"][0]
    lufs = integrated(channels(pcm(s.export("normalized")["path"])))
    check((row.get("renders") or 0) >= 2 and abs(row["result_lufs"] - lufs) <= 0.2
          and abs(lufs + 20) <= 0.5 and row["limited_by"] is None,
          f"V16 (f) an end gate and limiter at −6 dBTP under the clip's own limiter, target "
          f"−20: the export at {f(lufs)} LUFS (−20 ±0.5), renders "
          f"{row.get('renders')} (≥ 2), volume {f(row['volume'], 4)}, result "
          f"{f(row['result_lufs'])} against the export {f(lufs)} LUFS "
          f"({f(row['result_lufs'] - lufs)} LU, ≤ 0.2), limited_by {row['limited_by']}")
    m.call("close_project", project=s.path, discard=True)

    # (g) the one-render arm: no limiter on the clip and a target low enough that the
    # solve adds none, so nothing renders the action's limiter at the solved volume.
    s = Session(m, "ap6-action-g")
    clip = place(s, "ap6-rode.wav")
    keyed(s, clip, {"gate": {"threshold_db": -30}, "limiter": {"ceiling_db": -24}})
    row = s.op("normalize_clip", clips=[clip], mode="loudness",
               target_lufs=-30)["normalized"][0]
    lufs = integrated(channels(pcm(s.export("normalized")["path"])))
    check(row.get("renders") == 1 and row.get("limiter") is None,
          f"V16 (g) an end gate and limiter at −24 dBTP, no limiter on the clip, target −30: "
          f"the one-render arm (renders {row.get('renders')}, limiter {row.get('limiter')})")
    print(f"  note V16 (g) NOT SCORED (AU-159 (b), #402): volume {f(row['volume'], 4)}, "
          f"processed {f(row.get('processed_lufs'))}, result {f(row['result_lufs'])} against "
          f"the export {f(lufs)} LUFS: {f(row['result_lufs'] - lufs)} LU")
    m.call("close_project", project=s.path, discard=True)


# ---- V14 the sheet, cancelled and stale -------------------------------------

HOLD = 3


def held_session(client, name):
    """A fresh project with the owner's recording, its cache/isolated/
    asserted absent or empty (the hold acts only on a render job)."""
    s = Session(client, name)
    clip = place(s, "ap6-rode.wav")
    isolated = os.path.join(s.path, "cache", "isolated")
    empty = not os.path.isdir(isolated) or not os.listdir(isolated)
    check(empty, f"V14 {name}: cache/isolated/ absent or empty before the press")
    s.op("set_selection", clips=[clip])
    return s, clip


def press_and_see(s, leg):
    """Clip ▸ Enhance Voice, then the sheet's texts: the row FAILS unless they
    hold "Measuring Sound"."""
    menu = s.op("perform_menu_item", path=["Clip", "Enhance Voice"])
    texts = sheet_texts(s)
    seen = any("Measuring Sound" in t for t in texts)
    check(seen, f"V14 {leg}: the Measuring Sound sheet is up (sheet {menu.get('sheet')!r}, "
                f"texts {texts[:4]})")
    return seen


def hold_rows():
    print("\nV14 — the Measuring Sound sheet under -RCDevRampRenderHold 3")
    launched = mcp_module.launch(proof_app.binary(), arguments=["-RCDevRampRenderHold", str(HOLD)])
    try:
        if not check(launched.client is not None, "V14 an instance with the hold comes up"):
            return
        other = launched.client
        s, clip = held_session(other, "ap6-hold-a")
        before = audio(s, clip)
        if press_and_see(s, "(a)"):
            cancelled = s.op("cancel_sheet")
            time.sleep(HOLD + 3)
            after = audio(s, clip)
            changed = {k for k in set(before) | set(after) if before.get(k) != after.get(k)}
            check(not changed,
                  f"V14 (a) cancel_sheet ({json.dumps(cancelled)[:120]}), and after the hold "
                  f"the clip is unchanged: {sorted(changed)}")
        other.call("close_project", project=s.path, discard=True)
        s, clip = held_session(other, "ap6-hold-b")
        before = audio(s, clip)
        if press_and_see(s, "(b)"):
            s.op("set_audio", clips=[clip], patch={"pan": 0.2})
            gone = wait_no_sheet(s)
            after = audio(s, clip)
            changed = {k for k in set(before) | set(after) if before.get(k) != after.get(k)}
            check(gone is not None and changed == {"pan"} and after.get("pan") == 0.2,
                  f"V14 (b) set_audio pan during the hold; the sheet gone after "
                  f"{gone if gone is None else round(gone, 2)} s and only the pan changed: "
                  f"{sorted(changed)}")
        other.call("close_project", project=s.path, discard=True)
    finally:
        launched.stop()


# ---- V11 the log ----------------------------------------------------------------

def log_rows():
    print("\nV11 — the parity log")
    log = os.path.join(os.path.dirname(p5.SOCKET), "framejob.log")
    if not os.path.exists(log):
        check(False, f"V11 {log} exists")
        return
    with open(log, encoding="utf-8", errors="replace") as handle:
        lines = [line.rstrip() for line in handle if "Frame Job: " in line]
    check(not lines, f"V11 no \"Frame Job: \" line in {log}: {lines[:3]}")


def main():
    os.makedirs(p5.WORK, exist_ok=True)
    fixtures()
    m = MCP(p5.SOCKET)
    # AP6_ONLY=owner,hold,… runs only those parts while iterating; a recorded
    # run sets nothing and runs them all.
    only = set(filter(None, os.environ.get("AP6_ONLY", "").split(",")))
    errors = (ToolError, KeyError, IndexError, RuntimeError, OSError, ValueError, TypeError)
    parts = (("owner", owner_rows), ("sibilance", sibilance_rows),
             ("selection", selection_rows), ("speed", speed_rows),
             ("normalize", normalize_rows), ("actions", action_rows),
             ("limiter", limiter_speed_rows))
    for name, part in parts:
        if only and name not in only:
            continue
        try:
            result = part(m)
            if part is owner_rows:
                _tool_row, first = result
                timing_rows(m, first)
        except errors as error:
            check(False, f"{part.__name__} aborted: {type(error).__name__}: {error}")
    if not only or "menu" in only:
        try:
            menu_rows(m)
        except errors as error:
            check(False, f"menu_rows aborted: {type(error).__name__}: {error}")
    if not only or "hold" in only:
        try:
            hold_rows()
        except errors as error:
            check(False, f"hold_rows aborted: {type(error).__name__}: {error}")
    log_rows()
    print(f"\n{checks - len(failures)}/{checks} checks passed")
    for line in failures:
        print(f"  FAILED: {line}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
