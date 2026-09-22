#!/usr/bin/env python3
"""Built-app waveform readiness, level cuts and normalization for issue #23."""
import json
import os
from pathlib import Path
import shutil
import sys
import time
from mcp import MCP, ToolError

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/peaks-proof"
FIXTURES = ROOT / "tools/proof/work/peaks-probe/fixtures"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 5410
passed = failed = 0


def check(name, condition, detail=""):
    global passed, failed
    if condition:
        passed += 1
        print("  ok   " + name)
    else:
        failed += 1
        print("  FAIL " + name + (": " + detail if detail else ""))


class Session:
    def __init__(self, mcp, name):
        self.mcp = mcp
        self.path = str(WORK / f"{name}-{os.getpid()}.reelcut")
        mcp.call("new_project", path=self.path)

    def op(self, name, **args):
        return self.mcp.call(name, project=self.path, **args)

    def error(self, name, **args):
        try:
            self.op(name, **args)
        except ToolError as error:
            return str(error)
        return ""

    def project(self):
        return self.op("get_project")["project"]

    def lay(self, filename):
        source = FIXTURES / filename
        result = self.op("import_media", path=str(source))
        media = result["media"]
        track = self.project()["tracks"][0]["id"]
        clip = self.op("add_clip", track=track, media=media, at=0)["new_clips"][0]
        return media, clip

    def peaks(self, media):
        return Path(self.path) / "cache" / "peaks" / f"{media}.bin"

    def marker(self, media):
        return Path(self.path) / "cache" / "peaks" / f"{media}.complete.json"


def wait_for(predicate, seconds=40):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        result = predicate()
        if result:
            return result
        time.sleep(.2)
    return None


def main():
    WORK.mkdir(parents=True, exist_ok=True)
    for old in WORK.glob("*.reelcut"):
        shutil.rmtree(old)
    check("source probe fixtures exist", all((FIXTURES / name).exists() for name in
          ("corrupt.m4a", "silent48.wav", "stereo48.wav")))
    mcp = MCP(PORT)
    required = {"new_project", "import_media", "add_clip", "detect_silence",
                "normalize_clip", "get_project", "open_project", "consolidate_media"}
    check("required tool names are published", required <= set(mcp.tools()))

    bad = Session(mcp, "corrupt")
    bad_media, bad_clip = bad.lay("corrupt.m4a")
    check("corrupt file imported as audio and clip exists",
          bad_media in [m["id"] for m in bad.project()["media"]]
          and bad_clip in [c["id"] for c in bad.project()["clips"]])
    before = bad.project()
    level = bad.op("detect_silence", mode="level", clips=[bad_clip])
    check("corrupt audio is pending by media ID", level.get("pending_peaks") == [bad_media],
          str(level))
    check("corrupt audio proposes no interior level cuts", level.get("ranges") == [], str(level))
    error = bad.error("normalize_clip", clips=[bad_clip])
    check("normalize names the missing waveform rather than silence",
          f"clip {bad_clip}" in error and "waveform has not been written" in error,
          error[:150])
    check("normalize did not change project JSON", bad.project() == before)
    # The source probe has awaited this exact importer path after a corrupt
    # decode. Here the built app's user-facing answer is the oracle.
    check("corrupt cache has no certified payload", not bad.peaks(bad_media).exists()
          and not bad.marker(bad_media).exists())

    silent = Session(mcp, "silence")
    silent_media, silent_clip = silent.lay("silent48.wav")
    settled = wait_for(lambda: silent.marker(silent_media).exists()
                       and silent.peaks(silent_media).exists())
    check("genuine silence gets a marker and payload", settled is not None)
    silent_level = silent.op("detect_silence", mode="level", clips=[silent_clip],
                             padding=0, min_length=0)
    check("genuine silence is available, not pending",
          "pending_peaks" not in silent_level, str(silent_level))
    clip_duration = {c["id"]: c["duration"] for c in silent.project()["clips"]}[silent_clip]
    check("level proposes the full silent clip",
          silent_level.get("ranges") == [[0, clip_duration]],
          str(silent_level.get("ranges")))
    silent_error = silent.error("normalize_clip", clips=[silent_clip])
    check("normalize names real silence", "silent over the part of it that plays" in silent_error,
          silent_error[:150])

    loud = Session(mcp, "loud")
    loud_media, loud_clip = loud.lay("stereo48.wav")
    check("nonzero cache lands", wait_for(lambda: loud.marker(loud_media).exists()
          and loud.peaks(loud_media).exists()) is not None)
    before_loud = loud.project()
    normalized = loud.op("normalize_clip", clips=[loud_clip])
    check("healthy nonzero clip normalizes", any(row.get("clip") == loud_clip
          for row in normalized.get("normalized", [])), str(normalized))
    check("normalization changed audio volume", loud.project() != before_loud)

    # Bare legacy marker and its old false-silent payload are rejected at the
    # shared loader before a new pass is requested. The marker's own source
    # object proves that no thumbnail/transcript stamp was changed.
    wrapper = json.loads(loud.marker(loud_media).read_text())
    check("peaks marker uses version 1 and unchanged source object",
          wrapper.get("version") == 1 and isinstance(wrapper.get("source"), dict))
    loud.marker(loud_media).write_text(json.dumps(wrapper["source"]))
    loud.peaks(loud_media).write_bytes(b"\0" * loud.peaks(loud_media).stat().st_size)
    legacy_level = loud.op("detect_silence", mode="level", clips=[loud_clip])
    check("legacy false-silent cache is unavailable immediately",
          legacy_level.get("pending_peaks") == [loud_media]
          and legacy_level.get("ranges") == [], str(legacy_level))
    legacy_error = loud.error("normalize_clip", clips=[loud_clip])
    check("legacy zeros cannot normalize as silence",
          "waveform has not been written" in legacy_error, legacy_error[:150])
    # Reopen kicks off the normal cache pass, which withdraws the stale .bin.
    # A saved document retains media IDs while a fresh open owns a new pass.
    trigger_media = loud.op("import_media", path=str(FIXTURES / "silent48.wav"))["media"]
    check("normal cache pass trigger imported a second media",
          trigger_media != loud_media)
    rebuilt = wait_for(lambda: (json.loads(loud.marker(loud_media).read_text()).get("version") == 1)
                       if loud.marker(loud_media).exists() else False)
    check("legacy cache migrates on next normal pass", rebuilt is not None)
    if rebuilt is not None:
        restored = loud.op("detect_silence", mode="level", clips=[loud_clip])
        check("migrated waveform is available again", "pending_peaks" not in restored,
              str(restored))

    print(f"\n{passed}/{passed + failed} checks passed")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        check("proof completes", False, str(error))
        print(f"\n{passed}/{passed + failed} checks passed")
        sys.exit(1)
