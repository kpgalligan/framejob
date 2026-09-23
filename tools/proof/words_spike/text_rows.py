#!/usr/bin/env python3
"""Road map 8, spike W0 — q4, q5 and q6's registration half.

q4 asks whether Rust's `str::split_whitespace` and the renderer's own
`tokens(of:)` agree, over a corpus written to disagree if anything can. q5
asks what a pop and a pill cost in ink and in milliseconds. q6's half here
fetches the four OFL display faces and reads what the registry says about
each file; its PICTURE half is `scratch_rows.q6`.

Two CONTROLS hold q4 and q5 up:

* the probe's `tokens(of:)` is asserted to be the TREE's, character for
  character, before any disagreement is believed — a drifted copy would agree
  with Rust and report an agreement the app does not have;
* every face reports the PostScript name that came back and whether it is the
  system FALLBACK (`CTFontCreateWithName` never answers nil), so a row can
  never be a measurement of Helvetica wearing another name.
"""

import hashlib
import json
import os

import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROOF = os.path.normpath(os.path.join(HERE, ".."))
ROOT = os.path.normpath(os.path.join(PROOF, "..", ".."))
CLOUD = os.path.join(PROOF, "cloud_spike")
for folder in (CLOUD,):
    if folder not in sys.path:
        sys.path.append(folder)

import local_rows                                                    # noqa: E402

APP_FONTS = os.path.join(ROOT, "app", "Resources", "Fonts")
FONTS = os.path.join(HERE, "fonts")
OFL_SENTENCE = "SIL Open Font License, Version 1.1"

# Every URL written out in full, as road map 8 §3's q6 row requires. The
# Montserrat licence is at the repository ROOT — `fonts/ttf/OFL.txt` is a 404.
FONT_FILES = [
    ("Montserrat-ExtraBold.ttf",
     "https://raw.githubusercontent.com/JulietaUla/Montserrat/master/fonts/ttf/"
     "Montserrat-ExtraBold.ttf"),
    ("Montserrat-Black.ttf",
     "https://raw.githubusercontent.com/JulietaUla/Montserrat/master/fonts/ttf/"
     "Montserrat-Black.ttf"),
    ("Anton-Regular.ttf",
     "https://raw.githubusercontent.com/google/fonts/main/ofl/anton/Anton-Regular.ttf"),
    ("BebasNeue-Regular.ttf",
     "https://raw.githubusercontent.com/google/fonts/main/ofl/bebasneue/"
     "BebasNeue-Regular.ttf"),
]
LICENCE_FILES = [
    ("OFL-Montserrat.txt",
     "https://raw.githubusercontent.com/JulietaUla/Montserrat/master/OFL.txt"),
    ("OFL-Anton.txt",
     "https://raw.githubusercontent.com/google/fonts/main/ofl/anton/OFL.txt"),
    ("OFL-BebasNeue.txt",
     "https://raw.githubusercontent.com/google/fonts/main/ofl/bebasneue/OFL.txt"),
]


# ---- Building the two probes ----------------------------------------------

def build_text_probe(work):
    """`tools/proof/peaks_probe.py:101-117`'s swiftc line: every file in
    `app/Sources` but the app's own `main.swift`, module `Reelcut`, the
    bridging header, and the staticlib."""
    folder = os.path.join(work, "bin", "text")
    os.makedirs(folder, exist_ok=True)
    entry = os.path.join(folder, "main.swift")
    shutil.copyfile(os.path.join(HERE, "text_probe.swift"), entry)
    binary = os.path.join(folder, "text_probe")
    sources = sorted(
        os.path.join(ROOT, "app", "Sources", name)
        for name in os.listdir(os.path.join(ROOT, "app", "Sources"))
        if name.endswith(".swift") and name != "main.swift")
    if len(sources) < 100:
        return None, f"app source set incomplete ({len(sources)} files)"
    sdk = local_rows.run_bounded(
        ["xcrun", "--show-sdk-path", "--sdk", "macosx"], timeout=60)["stdout"].strip()
    library = os.path.join(ROOT, "core", "target", "release")
    command = [
        "swiftc", "-sdk", sdk, "-target", "arm64-apple-macos26.0",
        "-module-name", "Reelcut", "-import-objc-header",
        os.path.join(ROOT, "app", "Bridging", "Reelcut-Bridging-Header.h"),
        "-L", library, "-lreelcut_core", *sources, entry, "-o", binary]
    result = local_rows.run_bounded(command, timeout=900)
    if result["rc"] != 0 or not os.path.exists(binary):
        lines = [line for line in (result["stderr"] or "").splitlines() if ": error:" in line]
        return None, "swiftc: " + "; ".join(lines[:8] or [(result["stderr"] or "")[-600:]])
    return binary, None


def build_tokens(work):
    out = os.path.join(work, "bin", "tokens")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    result = local_rows.run_bounded(
        ["rustc", "-O", os.path.join(HERE, "tokens.rs"), "-o", out], timeout=300)
    if result["rc"] != 0 or not os.path.exists(out):
        return None, (result["stderr"] or result["stdout"] or "no output")[-600:]
    return out, None


# ---- q4 — the two tokenizers ----------------------------------------------

# The corpus, built from CODE POINTS rather than written out, so no invisible
# character ever sits in this file pretending to be a space. Every row is a
# case where the two rules could differ: a separator Unicode calls whitespace
# and `char::is_whitespace` may not, a zero-width joiner that is not a space at
# all, a script with no spaces, two right-to-left scripts that have them, and
# the three ways a line can end.
def _c(*points):
    return "".join(chr(point) for point in points)


CORPUS = [
    ("ascii", "one two three"),
    ("double_space", "one  two"),
    ("leading_trailing", "  one two  "),
    ("tab", "one" + _c(0x0009) + "two"),
    ("lf", "one" + _c(0x000A) + "two"),
    ("crlf", "one" + _c(0x000D, 0x000A) + "two"),
    ("vertical_tab_000b", "one" + _c(0x000B) + "two"),
    ("form_feed_000c", "one" + _c(0x000C) + "two"),
    ("next_line_0085", "one" + _c(0x0085) + "two"),
    ("nbsp_00a0", "one" + _c(0x00A0) + "two"),
    ("ogham_space_1680", "one" + _c(0x1680) + "two"),
    ("thin_space_2009", "one" + _c(0x2009) + "two"),
    ("figure_space_2007", "one" + _c(0x2007) + "two"),
    ("zero_width_space_200b", "one" + _c(0x200B) + "two"),
    ("narrow_nbsp_202f", "one" + _c(0x202F) + "two"),
    ("line_separator_2028", "one" + _c(0x2028) + "two"),
    ("paragraph_separator_2029", "one" + _c(0x2029) + "two"),
    ("ideographic_space_3000", "one" + _c(0x3000) + "two"),
    ("bom_feff", _c(0xFEFF) + "one two"),
    ("combining_after_space", "a " + _c(0x0301) + "b"),
    ("emoji_zwj_family",
     "before " + _c(0x1F469, 0x200D, 0x1F469, 0x200D, 0x1F467, 0x200D, 0x1F466) + " after"),
    ("cjk_no_spaces", _c(0x6211, 0x4EEC, 0x559C, 0x6B22, 0x89C6, 0x9891, 0x7F16, 0x8F91)),
    ("arabic_with_spaces",
     _c(0x0645, 0x0631, 0x062D, 0x0628, 0x0627) + " " + _c(0x0627, 0x0644, 0x0639, 0x0627,
                                                           0x0644, 0x0645)),
    ("hebrew_with_spaces",
     _c(0x05E9, 0x05DC, 0x05D5, 0x05DD) + " " + _c(0x05E2, 0x05D5, 0x05DC, 0x05DD)),
]


def _function_text(path, signature):
    """The named function's source, from `def`/`fn` line to its closing brace
    at the same indentation. Whitespace is normalised per line so an indent
    change is not a difference, and nothing else is."""
    with open(path) as handle:
        lines = handle.read().splitlines()
    start = next((i for i, line in enumerate(lines) if signature in line), None)
    if start is None:
        return None
    depth = 0
    out = []
    for line in lines[start:]:
        out.append(" ".join(line.split()))
        depth += line.count("{") - line.count("}")
        if depth == 0 and out:
            break
    return "\n".join(out)


def _copy_is_verbatim():
    """The CONTROL: the probe's `tokens(of:)` against the tree's."""
    tree = _function_text(
        os.path.join(ROOT, "app", "Sources", "LayerRenderersText.swift"),
        "func tokens(of content: String) -> [Range<Int>]")
    mine = _function_text(
        os.path.join(HERE, "text_probe.swift"),
        "func tokens(of content: String) -> [Range<Int>]")
    if tree is None or mine is None:
        return {"equal": False, "reason": "one of the two functions could not be found"}
    stripped = tree.replace("private static func", "func", 1)
    return {"equal": stripped == mine, "tree_lines": len(tree.splitlines()),
            "probe_lines": len(mine.splitlines()),
            "reason": None if stripped == mine else
            "the probe's copy has drifted from LayerRenderersText.swift's"}


def q4(work, say):
    control = _copy_is_verbatim()
    probe, probe_error = build_text_probe(work)
    rust, rust_error = build_tokens(work)
    if probe is None:
        return {"state": "failed", "reason": "text_probe did not build",
                "measured": {"build_error": probe_error, "copy_control": control}}
    if rust is None:
        return {"state": "failed", "reason": "tokens.rs did not build",
                "measured": {"build_error": rust_error, "copy_control": control}}
    folder = os.path.join(work, "q4")
    os.makedirs(folder, exist_ok=True)
    corpus_path = os.path.join(folder, "corpus.json")
    with open(corpus_path, "w") as handle:
        json.dump({"rows": [{"id": name, "text": text} for name, text in CORPUS]},
                  handle, indent=2)
    swift_out = os.path.join(folder, "swift.json")
    rust_out = os.path.join(folder, "rust.json")
    swift = local_rows.spoken(local_rows.run_bounded(
        [probe, "tokens", corpus_path, swift_out], timeout=120))
    rusty = local_rows.spoken(local_rows.run_bounded(
        [rust, corpus_path, rust_out], timeout=120))
    swift_rows = {row["id"]: row for row in swift.get("rows") or []}
    rust_rows = {row["id"]: row for row in rusty.get("rows") or []}
    rows = {}
    disagreements = []
    transport = []
    for name, text in CORPUS:
        swift_row = swift_rows.get(name, {})
        rust_row = rust_rows.get(name, {})
        a = [list(pair) for pair in swift_row.get("tokens", [])]
        b = [list(pair) for pair in rust_row.get("tokens", [])]
        agree = a == b
        same_string = (swift_row.get("utf16_length") == rust_row.get("utf16_length")
                       == len(text.encode("utf-16-le")) // 2)
        rows[name] = {
            "text_escaped": text.encode("unicode_escape").decode("ascii"),
            "swift": a, "rust": b, "agree": agree,
            "swift_count": len(a), "rust_count": len(b),
            # W-2 asks the core to COUNT tokens, not to place them, so the
            # count and the ranges are two different verdicts.
            "counts_agree": len(a) == len(b),
            # If the two halves did not receive the same string, a difference
            # in their tokens says nothing about their two RULES.
            "both_received_the_same_string": same_string,
            "swift_utf16_length": swift_row.get("utf16_length"),
            "rust_utf16_length": rust_row.get("utf16_length"),
            "python_utf16_length": len(text.encode("utf-16-le")) // 2,
            "swift_slices": [
                text[_u16(text, s):_u16(text, e)].encode("unicode_escape").decode("ascii")
                for s, e in a],
            "rust_slices": [
                text[_u16(text, s):_u16(text, e)].encode("unicode_escape").decode("ascii")
                for s, e in b],
        }
        if not agree and same_string:
            disagreements.append(name)
        elif not agree:
            transport.append(name)
    measured = {
        "copy_control": control, "rows": rows,
        "disagreements": disagreements,
        "rows_whose_two_halves_saw_different_strings": transport,
        "agree_everywhere": not disagreements and not transport,
        "counts_agree_everywhere": all(row["counts_agree"] for row in rows.values()),
        "rows_whose_counts_differ": [
            name for name, row in rows.items() if not row["counts_agree"]],
        "corpus_size": len(CORPUS),
    }
    say(f"  q4: {len(CORPUS)} rows, {len(disagreements)} disagreements"
        + (f" ({', '.join(disagreements)})" if disagreements else "")
        + (f", {len(transport)} transport differences ({', '.join(transport)})"
           if transport else "")
        + f"; verbatim copy: {control['equal']}")
    if not control["equal"]:
        return {"state": "failed", "measured": measured,
                "reason": "the probe's tokens(of:) is not the tree's, so q4 measures a "
                          "paraphrase of the renderer's rule"}
    return {"state": "run", "reason": None, "measured": measured}


def _u16(text, offset):
    """A UTF-16 offset back into a Python string index, so a disagreement can
    be printed as the actual characters each side claimed."""
    units = 0
    for index, character in enumerate(text):
        if units >= offset:
            return index
        units += 2 if ord(character) > 0xFFFF else 1
    return len(text)


# ---- q5 — headroom, cost and the two-thread stress ------------------------

def q5(work, say):
    probe, error = build_text_probe(work)
    if probe is None:
        return {"state": "failed", "reason": "text_probe did not build",
                "measured": {"build_error": error}}
    folder = os.path.join(work, "q5")
    os.makedirs(folder, exist_ok=True)
    fonts_argument = FONTS if os.path.isdir(FONTS) else "-"
    raster = local_rows.spoken(local_rows.run_bounded(
        [probe, "raster", APP_FONTS, fonts_argument, os.path.join(folder, "raster.json")],
        timeout=600))
    stress = local_rows.spoken(local_rows.run_bounded(
        [probe, "stress", APP_FONTS, os.path.join(folder, "stress.json")], timeout=600))

    import fixtures as words_fixtures
    same_text = stress.get("talk_text") == words_fixtures.TALK_TEXT
    fallbacks = []
    mismatched = []
    for canvas, body in (raster.get("canvases") or {}).items():
        for face in body.get("faces") or []:
            if face.get("is_fallback"):
                fallbacks.append(f"{canvas}/{face.get('requested')} -> "
                                 f"{face.get('postscript_name')}")
            elif not face.get("name_match"):
                mismatched.append(f"{canvas}/{face.get('requested')} -> "
                                  f"{face.get('postscript_name')} "
                                  f"(family {face.get('resolved_family')})")
    if stress.get("is_fallback"):
        fallbacks.append(f"stress/{stress.get('requested')} -> "
                         f"{stress.get('postscript_name')}")
    elif not stress.get("name_match"):
        mismatched.append(f"stress/{stress.get('requested')} -> "
                          f"{stress.get('postscript_name')} "
                          f"(family {stress.get('resolved_family')})")
    stress_summary = {k: v for k, v in stress.items() if k != "talk_text"}
    # `raster` is the CANVASES and nothing else, so `answers["q5"]["raster"]`
    # reads canvas → faces in one step; what the run itself reported about the
    # probe — the registrations, the page, the two roll-ups — is beside it.
    measured = {
        "raster": raster.get("canvases") or {},
        "raster_run": {k: v for k, v in raster.items() if k != "canvases"},
        "stress": stress_summary,
        "talk_text_matches_fixtures": same_text,
        "faces_that_fell_back": fallbacks,
        "faces_whose_name_did_not_round_trip": mismatched,
        "size_cache_flush_at_entries": 256,
    }
    say(f"  q5: raster ok {raster.get('ok')}, fallbacks {len(fallbacks)}, "
        f"name mismatches {len(mismatched)}; stress equal "
        f"{stress.get('sizes_equal_single_thread')}, "
        f"{round(stress.get('render_ms', 0) / 200.0, 3)} ms per render")
    if fallbacks:
        return {"state": "failed", "measured": measured,
                "reason": "a face resolved to the system fallback, so its numbers "
                          "would be Helvetica's: " + "; ".join(fallbacks)}
    # A crashed or empty probe is a FAILURE, never a `run` with nothing in it.
    faces = [f for body in (raster.get("canvases") or {}).values()
             for f in body.get("faces") or []]
    if not raster.get("ok") or not faces:
        return {"state": "failed", "measured": measured,
                "reason": "text_probe raster answered nothing: "
                          + str(raster.get("error") or "no faces")}
    if not stress.get("ok"):
        return {"state": "failed", "measured": measured,
                "reason": "text_probe stress answered nothing: "
                          + str(stress.get("error") or "ok false")}
    if not same_text:
        return {"state": "failed", "measured": measured,
                "reason": "text_probe.swift's TALK_TEXT is not fixtures.py's"}
    if not stress.get("sizes_equal_single_thread"):
        return {"state": "failed", "measured": measured,
                "reason": "measuredSize answered differently under two threads"}
    return {"state": "run", "reason": None, "measured": measured}


# ---- q6, the registration half --------------------------------------------

def _fetch(url, destination):
    result = local_rows.run_bounded(
        ["curl", "-sL", "-w", "%{http_code}", "-o", destination, url], timeout=180)
    status = (result["stdout"] or "").strip()[-3:]
    return {"url": url, "http_status": int(status) if status.isdigit() else None,
            "blocked": result["blocked"],
            "bytes": os.path.getsize(destination) if os.path.exists(destination) else 0}


def _sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(65536), b""):
            digest.update(block)
    return digest.hexdigest()


def q6_registration(work, say):
    os.makedirs(FONTS, exist_ok=True)
    fetched = {}
    failures = []
    for name, url in FONT_FILES + LICENCE_FILES:
        destination = os.path.join(FONTS, name)
        row = _fetch(url, destination)
        if row["http_status"] != 200 or row["bytes"] == 0:
            failures.append(f"{name}: {url} answered {row['http_status']}")
            row["sha256"] = None
        else:
            row["sha256"] = _sha256(destination)
        fetched[name] = row
    licences = {}
    for name, _ in LICENCE_FILES:
        path = os.path.join(FONTS, name)
        text = ""
        if os.path.exists(path):
            with open(path, encoding="utf-8", errors="replace") as handle:
                text = handle.read()
        licences[name] = {
            "is_ofl_1_1": OFL_SENTENCE in text,
            "bytes": len(text.encode("utf-8")),
            "first_line": text.splitlines()[0] if text.splitlines() else "",
        }
    kept = all(row["is_ofl_1_1"] for row in licences.values()) and not failures
    measured = {"fetched": fetched, "licences": licences, "kept": kept,
                "ofl_sentence": OFL_SENTENCE, "directory": FONTS}
    if not kept:
        # Only a LICENCE that is not the OFL 1.1 deletes the faces. A non-200
        # is a failure naming the URL, and the bytes it did fetch stay put so
        # the next run can see what arrived.
        if not failures:
            for name, _ in FONT_FILES:
                path = os.path.join(FONTS, name)
                if os.path.exists(path):
                    os.remove(path)
            measured["deleted"] = [name for name, _ in FONT_FILES]
            measured["deletion_reason"] = (
                "a fetched licence is not the SIL Open Font License, Version 1.1, "
                "so the faces may not be redistributed in this tree")
    probe, error = build_text_probe(work)
    if probe is None:
        measured["build_error"] = error
        return {"state": "failed", "reason": "text_probe did not build",
                "measured": measured}
    folder = os.path.join(work, "q6")
    os.makedirs(folder, exist_ok=True)
    measured["registry"] = local_rows.spoken(local_rows.run_bounded(
        [probe, "fonts", FONTS, os.path.join(folder, "fonts.json")], timeout=300))
    say(f"  q6/fetch: {len(fetched)} files, {len(failures)} failures, "
        f"licences OFL 1.1: {[n for n, r in licences.items() if r['is_ofl_1_1']]}")
    if failures:
        return {"state": "failed", "measured": measured,
                "reason": "a fetch did not answer 200: " + "; ".join(failures)}
    return {"state": "run", "reason": None, "measured": measured}
