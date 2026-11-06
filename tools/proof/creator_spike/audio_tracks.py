#!/usr/bin/env python3
"""Road map "creator-jobs" CJ7: spike SW-S1 (f) on a real file — every audio
track's codec, channels, title, track ID and whether one buffer decodes.

    python3 tools/proof/creator_spike/audio_tracks.py [--movie PATH]

The movie defaults to S-TH1's (`sth1.movie()`, an iPhone movie recorded with
Spatial Audio on, so it answers S-IP1's question: how many audio tracks the
phone writes, their channels, and whether each decodes). The probe is
`audio_tracks_probe.swift`, built alone; ffprobe's audio streams are set
beside its rows as the cross-check (ffprobe's stream id is the track ID).
Writes `tools/proof/work/creator_spike/SW-S1-f/results.json`.
"""

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROOF = HERE.parent
sys.path.insert(0, str(PROOF))
sys.path.insert(0, str(HERE))
import rule  # noqa: E402
import sth1  # noqa: E402
import swift_build  # noqa: E402

WORK = rule.WORK / "SW-S1-f"


def build():
    WORK.mkdir(parents=True, exist_ok=True)
    entry = WORK / "main.swift"
    shutil.copyfile(HERE / "audio_tracks_probe.swift", entry)
    binary = WORK / "audio-tracks-probe"
    swift_build.build(sources=[entry], output=binary, optimize=True)
    return binary


def ffprobe_audio(movie):
    answer = sth1.probe(movie)
    return [{"index": s["index"], "id": int(s["id"], 16) if str(s.get("id", "")).startswith("0x")
             else s.get("id"), "codec": s.get("codec_name"), "tag": s.get("codec_tag_string"),
             "channels": s.get("channels"), "sample_rate": s.get("sample_rate"),
             "default": s.get("disposition", {}).get("default")}
            for s in answer["streams"] if s["codec_type"] == "audio"]


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--movie")
    args = parser.parse_args(argv)
    movie = Path(args.movie) if args.movie else sth1.movie()
    if movie is None:
        print(f"SKIP SW-S1 (f) on S-TH1: {sth1.missing_reason()}")
        return 0
    rule.check_rule("SW-S1")
    binary = build()
    done = subprocess.run([str(binary), str(movie)], capture_output=True, text=True,
                          timeout=600)
    if done.returncode != 0:
        raise SystemExit(f"audio_tracks_probe: {(done.stderr or done.stdout)[-600:]}")
    answer = json.loads(done.stdout.strip().splitlines()[-1])
    streams = ffprobe_audio(movie)
    for row in answer["audio"]:
        print(f"track {row['track_id']}: {row.get('codec')} {row.get('channels')} ch "
              f"{row.get('sample_rate')} Hz title {row['title']!r} enabled {row['enabled']} "
              f"decodes {row['decodes']}" + (f" ({row['decodes_error']})"
                                             if row["decodes_error"] else ""))
    for s in streams:
        print(f"ffprobe stream {s['index']} id {s['id']}: {s['codec']} ({s['tag']}) "
              f"{s['channels']} ch {s['sample_rate']} Hz default {s['default']}")
    print(f"other tracks: {answer['other']}")
    ids = [row["track_id"] for row in answer["audio"]]
    agree = (len(ids) == len(streams)
             and all(r.get("channels") == s["channels"] for r, s in
                     zip(answer["audio"], sorted(streams, key=lambda s: s["index"]))))
    line = (f"VERDICT audio_tracks={len(ids)} "
            + " ".join(f"{r['track_id']}:{r.get('codec')}/{r.get('channels')}ch/"
                       f"{'decodes' if r['decodes'] else 'NO-DECODE'}" for r in answer["audio"])
            + f" ffprobe_agrees={'yes' if agree else 'no'}")
    results = {"movie": str(movie), "probe": answer, "ffprobe_audio": streams,
               "ffprobe_agrees": agree, "verdict_line": line}
    if movie == sth1.movie():
        results.update(sth1.record())
    written = rule.write_results("SW-S1", results, folder="SW-S1-f")
    print(line)
    print(f"results: {written}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
