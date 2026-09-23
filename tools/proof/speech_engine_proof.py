#!/usr/bin/env python3
"""Road map 8, W2 — the on-device engine (`SpeechTranscriber`), proved.

Three parts, one score:

* **MCP rows**, against the built app on the port given (launch it first; one
  proof per fresh instance). `transcribe {engine: apple, place: false}` over
  the proof's own `say` fixtures: the pangram's words come back trimmed, a
  ten-minute file comes back WHOLE (no ceiling, no `truncated`), silence is
  the exact nothingRecognized sentence, a misspelt tag is a misspelling, and a
  supported tag with no model on this Mac is refused as not installed — by
  name, fast, twice alike, and never downloaded.
* **Probe rows** — `speech_engine_probe.swift`, compiled from `app/Sources`
  with the probe as `main.swift` (a build failure is a scored FAILURE):
  P1 cancel (at 300 ms, and again mid-analysis), P2 the lists and the
  reservations, P3 the default language, P4 an uninstalled locale refused
  before the engine, P5 the sheet's Download row (its Cancel disabled until a
  `Progress` arrives), P6 the pangram's runs trimmed, P7 ten minutes whole,
  P8 an analysis answered while a stalled holder keeps the gate (run last).
* **Mutants** — six tree copies under `work/speech_engine/mutants/`, one
  once-only anchor each, the probe rebuilt from each; a mutant passes when
  its NAMED row fails.

No model is downloaded: the not-installed rows pick fr-FR, de-DE, ja-JP and
ko-KR in order and take the first that is refused as not installed; a host
where all four are installed is a named SKIP, never a pass.

    python3 tools/proof/speech_engine_proof.py <port> [--no-mutants]
"""
import json
import os
import re
import shutil
import subprocess
import sys
import time
import wave

from mcp import MCP, ToolError
from silence2_proof import SPEECH_TEXT

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
WORK = os.path.join(HERE, "work", "speech_engine")
SEC = 600_000
UNINSTALLED_CANDIDATES = ["fr-FR", "de-DE", "ja-JP", "ko-KR"]
NOTHING = "No speech was recognised in the audio that was transcribed."
PANGRAM = [w.strip(".,").lower() for w in re.sub(r"\[\[[^]]*\]\]", "", SPEECH_TEXT).split()]

failures, checks, skips = [], 0, []


def check(ok, what):
    global checks
    checks += 1
    print(("  ok   " if ok else "  FAIL ") + what)
    if not ok:
        failures.append(what)


def skip(what):
    skips.append(what)
    print("  SKIP " + what)


def run(command, timeout):
    return subprocess.run(command, capture_output=True, text=True, timeout=timeout,
                          stdin=subprocess.DEVNULL)


# ---- Fixtures --------------------------------------------------------------


def fixture(name):
    return os.path.join(WORK, name)


def make_fixtures():
    os.makedirs(WORK, exist_ok=True)
    pangram = fixture("pangram.wav")
    if not os.path.exists(pangram):
        answer = run(["say", "-o", pangram, "--file-format=WAVE",
                      "--data-format=LEI16@16000", SPEECH_TEXT], 120)
        if answer.returncode:
            raise RuntimeError(f"say failed: {answer.stderr.strip()[:300]}")
    with wave.open(pangram, "rb") as source:
        rate, width, channels = source.getframerate(), source.getsampwidth(), source.getnchannels()
        speech = source.readframes(source.getnframes())
    gap = b"\0" * int(rate * 0.8) * width * channels
    ten = fixture("ten.wav")
    if not os.path.exists(ten):
        body, frames = bytearray(), 0
        while frames <= 600 * rate:
            body += speech + gap
            frames = len(body) // (width * channels)
        with wave.open(ten, "wb") as out:
            out.setnchannels(channels)
            out.setsampwidth(width)
            out.setframerate(rate)
            out.writeframes(bytes(body))
    silence = fixture("silence.wav")
    if not os.path.exists(silence):
        with wave.open(silence, "wb") as out:
            out.setnchannels(1)
            out.setsampwidth(2)
            out.setframerate(16000)
            out.writeframes(b"\0" * 16000 * 2 * 3)
    with wave.open(ten, "rb") as source:
        ten_seconds = source.getnframes() / source.getframerate()
    return pangram, ten, silence, ten_seconds


# ---- MCP rows ---------------------------------------------------------------


class Session:
    def __init__(self, mcp, name):
        self.mcp = mcp
        for stale in os.listdir(WORK):
            if re.fullmatch(rf"{re.escape(name)}-\d+\.reelcut", stale):
                shutil.rmtree(os.path.join(WORK, stale))
        self.path = os.path.join(WORK, f"{name}-{os.getpid()}.reelcut")
        mcp.call("new_project", path=self.path)

    def op(self, tool, **kwargs):
        return self.mcp.call(tool, project=self.path, **kwargs)

    def project(self):
        return self.op("get_project")["project"]

    def text(self):
        return json.dumps(self.project(), sort_keys=True, separators=(",", ":"))

    def clip_of(self, path):
        media = self.op("import_media", path=path)["media"]
        track = self.project()["tracks"][0]["id"]
        return self.op("add_clip", track=track, media=media, at=0)["new_clips"][0]

    def frame(self):
        fps = self.project()["canvas"]["fps"]
        return SEC * fps[1] // fps[0]

    def transcribe(self, clip, **kwargs):
        return self.op("transcribe", clips=[clip], place=False, **kwargs)

    def refusal(self, clip, **kwargs):
        try:
            self.transcribe(clip, **kwargs)
            return None
        except ToolError as error:
            return str(error)


def cue_rules(cues, frame):
    """The four cue rules plus order — every cue, not a sample."""
    bad = []
    for index, cue in enumerate(cues):
        lines = cue["text"].split("\n")
        if len(lines) > 2 or any(len(line) > 42 for line in lines):
            bad.append(f"cue {index} shape {lines!r}")
        if cue["end"] - cue["start"] > 6 * SEC:
            bad.append(f"cue {index} lasts {(cue['end'] - cue['start']) / SEC:.2f} s")
        if index and cue["start"] < cues[index - 1]["start"]:
            bad.append(f"cue {index} out of order")
        if index and cue["start"] - cues[index - 1]["end"] < frame:
            bad.append(f"cue {index} is {cue['start'] - cues[index - 1]['end']} ticks after the last")
    return bad


def mcp_part(port, pangram, ten, silence, ten_seconds):
    print("\nMCP rows — transcribe under engine apple")
    mcp = MCP(port)
    s = Session(mcp, "pangram")
    clip = s.clip_of(pangram)
    before = s.text()
    answer = s.transcribe(clip, engine="apple", language="en-US")
    after = s.text()
    cues = answer.get("cues", [])
    words = [w.strip(".,!?").lower() for c in cues for w in c["text"].split()]
    left, hits = list(PANGRAM), 0
    for word in words:
        if word in left:
            left.remove(word)
            hits += 1
    spaced = [c["text"] for c in cues
              if any(line != line.strip() or "  " in line for line in c["text"].split("\n"))]
    check(hits >= 20, f"pangram: {hits} of {len(PANGRAM)} words recognised: "
          f"{' | '.join(c['text'] for c in cues)!r}")
    check(not spaced, f"no cue text with a leading, trailing or double space ({spaced[:2]})")
    check("truncated" not in answer and "note" not in answer,
          f"no `truncated` and no `note` key: keys {sorted(answer)}")
    check(answer.get("engine") == "apple" and answer.get("language") == "en-US"
          and answer.get("placed") is False and answer.get("clips_read") == [clip],
          f"engine, language, placed and clips_read: {answer.get('engine')}, "
          f"{answer.get('language')}, {answer.get('placed')}, {answer.get('clips_read')}")
    check(before == after, "place: false changed nothing — the project JSON is identical")

    t = Session(mcp, "ten")
    long_clip = t.clip_of(ten)
    began = time.time()
    answer = t.transcribe(long_clip, language="en-US")
    wall = time.time() - began
    cues = answer.get("cues", [])
    end = ten_seconds * SEC
    check(len(cues) >= 100 and cues[0]["start"] <= 5 * SEC and cues[-1]["end"] >= end - 5 * SEC,
          f"ten.wav ({ten_seconds:.1f} s) came back WHOLE in {wall:.1f} s: {len(cues)} cues, "
          f"first at {cues[0]['start'] / SEC if cues else -1:.2f} s, last ending "
          f"{cues[-1]['end'] / SEC if cues else -1:.2f} s")
    bad = cue_rules(cues, t.frame())
    check(not bad, f"every cue ≤ 2 lines × ≤ 42 chars, ≤ 6 s, sorted, a frame apart ({bad[:3]})")
    check("truncated" not in answer, "and no `truncated` key on a ten-minute run")

    q = Session(mcp, "silence")
    quiet = q.clip_of(silence)
    message = q.refusal(quiet, language="en-US") or ""
    check(message.endswith(NOTHING), f"silence.wav answers the exact sentence: {message[:110]!r}")

    message = s.refusal(clip, language="zz-ZZ") or ""
    tags = re.findall(r"\b[a-z]{2,3}-[A-Z0-9]{2,3}\b", message)
    check("zz-ZZ" in message and "spelling" in message and len(tags) >= 10
          and "not installed" not in message,
          f"zz-ZZ is a misspelling, listing {len(tags)} tags: {message[:100]!r}")

    for tag in UNINSTALLED_CANDIDATES:
        began = time.time()
        first = s.refusal(clip, language=tag)
        wall = time.time() - began
        if first is None or "not installed" not in first:
            print(f"  note {tag} was not refused as not installed: {str(first)[:90]!r}")
            continue
        second = s.refusal(clip, language=tag)
        check("not installed" in first and "a person has to install it" in first.lower()
              and wall < 5,
              f"{tag} is refused as not installed, by name, in {wall:.2f} s: {first[:150]!r}")
        check(second == first, f"and identically the second time ({second == first})")
        break
    else:
        skip(f"not-installed rows: every one of {UNINSTALLED_CANDIDATES} is installed here")
    # Last on this session, because the undo takes its clip away.
    undone = s.op("undo").get("undone", "")
    check("Caption" not in undone, f"no transcribe pushed an undo step — undo took “{undone}”")


# ---- The probe and its mutants ---------------------------------------------


def build_probe(sources, out):
    os.makedirs(out, exist_ok=True)
    entry = os.path.join(out, "main.swift")
    shutil.copyfile(os.path.join(HERE, "speech_engine_probe.swift"), entry)
    swift = sorted(os.path.join(sources, n) for n in os.listdir(sources)
                   if n.endswith(".swift") and n != "main.swift")
    if len(swift) < 100:
        return None, f"app source set incomplete ({len(swift)} files)"
    sdk = run(["xcrun", "--show-sdk-path", "--sdk", "macosx"], 60).stdout.strip()
    binary = os.path.join(out, "speech-engine-probe")
    answer = run(["swiftc", "-sdk", sdk, "-target", "arm64-apple-macos26.0",
                  "-module-name", "Reelcut", "-import-objc-header",
                  os.path.join(ROOT, "app", "Bridging", "Reelcut-Bridging-Header.h"),
                  "-L", os.path.join(ROOT, "core", "target", "release"), "-lreelcut_core",
                  *swift, entry, "-o", binary], 900)
    if answer.returncode:
        errors = [line for line in answer.stderr.splitlines() if ": error:" in line]
        return None, "swiftc: " + "; ".join(errors[:6] or [answer.stderr[-400:]])
    return binary, ""


def run_probe(binary, pangram, ten):
    answer = run([binary, pangram, ten], 900)
    rows = {}
    for line in answer.stdout.splitlines():
        found = re.match(r"\s+(ok|FAIL|SKIP)\s+(P\d [^—]+?) —", line)
        if found:
            rows[found.group(2).strip()] = found.group(1)
    return answer, rows


def probe_part(pangram, ten):
    print("\nProbe rows — speech_engine_probe.swift over app/Sources")
    binary, problem = build_probe(os.path.join(ROOT, "app", "Sources"), os.path.join(WORK, "probe"))
    check(binary is not None, f"the probe builds from app/Sources {problem}")
    if binary is None:
        return
    answer, rows = run_probe(binary, pangram, ten)
    print("\n".join("  | " + line for line in answer.stdout.splitlines()))
    for row, state in sorted(rows.items()):
        if state == "SKIP":
            skip(f"probe {row}")
        else:
            check(state == "ok", f"probe {row}")
    check(answer.returncode == 0 and len(rows) >= 14,
          f"the probe exited {answer.returncode} with {len(rows)} rows")


MUTANTS = [
    ("keep-last-result-only", "SpeechEngine.swift",
     "            collected.append(contentsOf: found)\n",
     "            collected = found\n", "P7 ten minutes"),
    ("drop-the-trim", "SpeechEngine.swift",
     "                let text = String(result.text[run.range].characters)\n"
     "                    .trimmingCharacters(in: .whitespacesAndNewlines)\n",
     "                let text = String(result.text[run.range].characters)\n", "P6 pangram"),
    ("skip-installed-check", "Transcriber.swift",
     "        case .some(false):\n            throw TranscribeError.notInstalled(language.displayName)\n",
     "        case .some(false):\n            break\n", "P4 not installed"),
    ("raw-compare-default", "Transcriber+Languages.swift",
     "        let current = Locale.current.identifier(.bcp47)\n",
     "        let current = Locale.current.identifier\n", "P3 default"),
    ("cancel-live-before-progress", "TranscribeSheetController+Download.swift",
     "        button.isEnabled = downloadProgress != nil\n",
     "        button.isEnabled = true\n", "P5 awaiting progress"),
    ("release-before-signal", "SpeechEngine.swift",
     "        sink.finish(failure)\n        await release(locale)\n",
     "        await release(locale)\n        sink.finish(failure)\n", "P8 gate stalled"),
]


def mutant_part(pangram, ten):
    print("\nMutants — each must fail its named row")
    for name, file, anchor, replacement, row in MUTANTS:
        tree = os.path.join(WORK, "mutants", name)
        shutil.rmtree(tree, ignore_errors=True)
        sources = os.path.join(tree, "Sources")
        shutil.copytree(os.path.join(ROOT, "app", "Sources"), sources)
        path = os.path.join(sources, file)
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        if text.count(anchor) != 1:
            check(False, f"{name}: the anchor is in {file} exactly once "
                  f"(found {text.count(anchor)})")
            continue
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text.replace(anchor, replacement))
        binary, problem = build_probe(sources, os.path.join(tree, "build"))
        if binary is None:
            check(False, f"{name}: the mutant probe builds {problem}")
            continue
        _, rows = run_probe(binary, pangram, ten)
        check(rows.get(row) == "FAIL",
              f"{name}: “{row}” FAILED ({rows.get(row, 'absent')}); "
              f"rows failed: {sorted(r for r, s in rows.items() if s == 'FAIL')}")


def main():
    arguments = [a for a in sys.argv[1:] if not a.startswith("--")]
    port = int(arguments[0]) if arguments else 4871
    pangram, ten, silence, ten_seconds = make_fixtures()
    mcp_part(port, pangram, ten, silence, ten_seconds)
    probe_part(pangram, ten)
    if "--no-mutants" not in sys.argv:
        mutant_part(pangram, ten)
    summary()


def summary(aborted=None):
    tail = f" — ABORTED by {aborted}" if aborted else ""
    print(f"\n{checks - len(failures)}/{checks} checks passed, {len(skips)} skipped{tail}")
    for line in failures:
        print(f"  FAILED: {line}")
    for line in skips:
        print(f"  SKIPPED: {line}")
    if failures or aborted:
        sys.exit(1)


if __name__ == "__main__":
    try:
        main()
    except (ToolError, AssertionError, KeyError, IndexError, RuntimeError, OSError,
            subprocess.TimeoutExpired) as error:
        summary(aborted=f"{type(error).__name__}: {error}")
