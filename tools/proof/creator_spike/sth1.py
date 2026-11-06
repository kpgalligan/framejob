"""Road map "creator-jobs" CJ7: sample S-TH1, the owner's talking head
(`samples/README.md`), as every spike's S-TH1 arm reads it.

- `movie()` is `IMG_0181.MOV`, pinned by name (case-insensitive): the movie
  the truth spans below were read from. Never a suffix pick, since the
  side-on add-on lands in the same folder.
- `addon(folder)` is the side-on add-on: the one other movie in `folder`.
- `rode()` is the RØDE's own file beside it.
- `facts()` re-measures the movie through ffprobe.
- `BEATS` are the owner's beats (`notes.txt`: lean out 3:38, stand and leave
  3:53, look away 4:09) as whole-second spans of movie time, read from
  autorotated `fps=1` frames (CJ7's record names the frames that set each
  bound). `ABSENT` are the spans with nobody in the chair: the first seconds
  before the owner sits (no face until 8 s) and the end after he stands
  (gone from 285 s). `face_present(t)` is false inside either.
- `FACING_0_60` is the part of 0–60 s with the owner's face in frame.
- `profile_span(samples)` finds the profile stretch in the add-on from the
  faces probe's yaw.
"""

import json
import math
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
ROOT_DIR = ROOT / "tools/proof/media/creator/S-TH1"
MOVIE_NAME = "img_0181.mov"
RODE_NAME = "img_0181.aifc"
MOVIE_SUFFIXES = (".mov", ".mp4", ".m4v")

# Seconds of IMG_0181.MOV, both ends inclusive, from the frames CJ7 read
# (`tools/proof/work/creator_spike/sth1_frames/`, autorotated, one a second).
BEATS = {
    "lean_out": (219.0, 220.0),   # 218 face (moving), 219 and 220 none, 221 face
    "leave": (234.0, 239.0),      # 233 seated, 234 rising, 235–238 gone, 239 sitting, 240 seated
    "look_away": (249.0, 254.0),  # 248 facing, 249 turned, 250–253 away, 254 turning, 255 facing
}
ABSENT = {
    "arrive": (0.0, 7.0),         # 0–6 an empty chair, 7 a torso, 8 the first face
    "exit": (284.0, 292.0),       # 283 face, 284 standing, 285–290 an empty chair
}
FACING_0_60 = (8.0, 60.0)

PROFILE_YAW = math.pi / 4 - 0.01
PROFILE_AFTER = 10.0
PROFILE_MIN = 2.0


def _entry(folder, name):
    if not folder.is_dir():
        return None
    for path in sorted(folder.iterdir()):
        if path.name.casefold() == name:
            return path
    return None


def movie():
    return _entry(ROOT_DIR, MOVIE_NAME)


def rode():
    return _entry(ROOT_DIR, RODE_NAME)


def addon(folder=None):
    folder = Path(folder) if folder else ROOT_DIR
    if not folder.is_dir():
        return None
    found = [p for p in sorted(folder.iterdir())
             if p.suffix.casefold() in MOVIE_SUFFIXES and p.name.casefold() != MOVIE_NAME]
    if len(found) > 1:
        raise SystemExit(f"S-TH1's side-on add-on is ambiguous in {folder}: "
                         + ", ".join(p.name for p in found))
    return found[0] if found else None


def missing_reason():
    if not ROOT_DIR.is_dir():
        return f"S-TH1 is missing: no {ROOT_DIR.relative_to(ROOT)}"
    return f"S-TH1 is missing: no IMG_0181.MOV in {ROOT_DIR.relative_to(ROOT)}"


def in_spans(t, spans):
    return any(lo - 0.5 <= t <= hi + 0.5 for lo, hi in spans)


def face_present(t):
    """True where a face is known in frame: outside every beat and every
    empty-chair span (each span widened by half a second, the frames being
    one a second)."""
    return not in_spans(t, list(BEATS.values()) + list(ABSENT.values()))


def in_beat(t, name):
    return in_spans(t, [BEATS[name]])


def profile_span(samples):
    """The longest run of consecutive samples after `PROFILE_AFTER` in which
    no face has |yaw| < `PROFILE_YAW` (no face at all counts), as (first t,
    last t); None when the longest is under `PROFILE_MIN` seconds."""
    best, run = None, []
    for sample in sorted(samples, key=lambda s: s["t"]):
        if sample["t"] <= PROFILE_AFTER:
            continue
        frontal = any(f.get("yaw") is not None and not math.isnan(f["yaw"])
                      and abs(f["yaw"]) < PROFILE_YAW for f in sample["faces"])
        if frontal:
            run = []
            continue
        run.append(sample["t"])
        if best is None or run[-1] - run[0] > best[1] - best[0]:
            best = (run[0], run[-1])
    if best is None or best[1] - best[0] < PROFILE_MIN:
        return None
    return best


def probe(path):
    done = subprocess.run(["ffprobe", "-v", "error", "-show_streams", "-show_format", "-of",
                           "json", str(path)], capture_output=True, text=True, check=True)
    return json.loads(done.stdout)


def facts(path=None):
    path = Path(path) if path else movie()
    answer = probe(path)
    streams = answer["streams"]
    video = next(s for s in streams if s["codec_type"] == "video")
    rotation = next((sd.get("rotation") for sd in video.get("side_data_list", [])
                     if "rotation" in sd), 0)
    return {
        "file": path.name, "bytes": path.stat().st_size,
        "codec": video.get("codec_name"), "profile": video.get("profile"),
        "width": video.get("width"), "height": video.get("height"),
        "color": [video.get("color_primaries"), video.get("color_transfer"),
                  video.get("color_space")],
        "rotation": rotation, "r_frame_rate": video.get("r_frame_rate"),
        "avg_frame_rate": video.get("avg_frame_rate"),
        "duration": float(answer["format"]["duration"]),
        "audio": [{"index": s["index"], "codec": s.get("codec_name"),
                   "profile": s.get("profile"), "channels": s.get("channels"),
                   "sample_rate": s.get("sample_rate"),
                   "default": s.get("disposition", {}).get("default")}
                  for s in streams if s["codec_type"] == "audio"],
        "data": [{"index": s["index"], "tag": s.get("codec_tag_string")}
                 for s in streams if s["codec_type"] == "data"],
    }


def rode_facts():
    path = rode()
    if path is None:
        return None
    stream = probe(path)["streams"][0]
    return {"file": path.name, "codec": stream.get("codec_name"),
            "channels": stream.get("channels"), "sample_rate": stream.get("sample_rate"),
            "duration": float(stream.get("duration"))}


def record():
    """What every S-TH1 results file carries: the facts and the spans."""
    return {"sth1_facts": facts(), "beats": BEATS, "absent": ABSENT,
            "facing_0_60": FACING_0_60}


if __name__ == "__main__":
    if movie() is None:
        print(missing_reason())
    else:
        print(json.dumps({**record(), "rode": rode_facts(),
                          "addon": str(addon()) if addon() else None}, indent=1))
