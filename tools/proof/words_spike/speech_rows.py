#!/usr/bin/env python3
"""Road map 8, spike W0 — q1, q2 and q3: the two speech engines, measured.

q1 and q3 cost nothing and run first. q2 is the only row that spends money:
three synthetic fixtures, about 75 seconds of audio, each uploaded once,
transcribed once and DELETED, with `Ledger.reserve` before every upload and
one `closed` event after every one. `ten.wav` is never uploaded.

Every child process is bounded (rule H): a fixed timeout, `stdin` closed,
`RC_ASSEMBLYAI_KEY` REMOVED from the environment, and a kill of that child's
own group and nothing else. An expiry is the row's ANSWER — the third-party
report that `SFSpeechRecognizer` "silently never starts" on macOS 26 is a
HANG, and a hang is only measurable if something is holding a clock. The
builds go through `local_rows.run_bounded`; every PROBE goes through
`run_drained` below, for the reason written there.
"""

import difflib
import json
import os
import re
import signal
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
CLOUD = os.path.normpath(os.path.join(HERE, "..", "cloud_spike"))
for folder in (CLOUD,):
    if folder not in sys.path:
        sys.path.append(folder)

import aai                                                           # noqa: E402
import cloud_rows                                                    # noqa: E402
import local_rows                                                    # noqa: E402

TARGET = ["-O", "-parse-as-library", "-target", "arm64-apple-macos26.0"]
LOCALE = "en-US"
PUNCTUATION = re.compile(r"[^\w']+", re.UNICODE)


def run_drained(argv, timeout, cwd=None):
    """A bounded child whose PIPES ARE DRAINED while it runs, in its own
    process group, killed by that group. Rule H's second form.

    `local_rows.run_bounded` polls `poll()` and only calls `communicate()`
    once the child is gone, so a child that writes more than the 64 KiB pipe
    buffer BLOCKS in `write` forever and the run's answer is a timeout that
    says nothing. This spike measures that: `speech_probe words` over the
    ten-minute fixture prints 1 755 runs, several hundred kilobytes, and it
    deadlocked the first two readings of q1 — which looked exactly like a
    length ceiling in the Speech framework and was not one.

    Everything else is `run_bounded`'s: `stdin` closed, `RC_ASSEMBLYAI_KEY`
    REMOVED from the environment, and nothing killed but this child's own
    group.
    """
    started = time.monotonic()
    try:
        child = subprocess.Popen(
            argv, cwd=cwd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, env=local_rows.child_env(), text=True,
            start_new_session=True)
    except OSError as error:
        return {"rc": None, "stdout": "", "stderr": f"{type(error).__name__}: {error}",
                "blocked": False, "security_agent_seen": False, "ms": 0.0}
    try:
        out, err = child.communicate(timeout=timeout)
        blocked = False
    except subprocess.TimeoutExpired:
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except OSError:
            child.kill()
        try:
            out, err = child.communicate(timeout=30)
        except subprocess.TimeoutExpired:
            out, err = "", ""
        blocked = True
    return {"rc": None if blocked else child.returncode, "stdout": out or "",
            "stderr": err or "", "blocked": blocked, "security_agent_seen": False,
            "ms": (time.monotonic() - started) * 1000.0}


def build_probe(work):
    """`tools/proof/silence_spike/level_apple.swift:7`'s line, which this host
    has already proved for a `SpeechTranscriber` in file mode."""
    out = os.path.join(work, "bin", "speech_probe")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    command = (["xcrun", "swiftc"] + TARGET
               + [os.path.join(HERE, "speech_probe.swift"), "-o", out])
    result = local_rows.run_bounded(command, timeout=600)
    if result["rc"] != 0 or not os.path.exists(out):
        return None, (result["stderr"] or result["stdout"] or "no output")[-800:]
    return out, None


def normalised(text):
    """Lower case, punctuation stripped, split on whitespace. The unit both
    engines and the script are compared in, so `Hi,` and `hi` are one word and
    a missing comma is never a word error."""
    return [w for w in PUNCTUATION.sub(" ", (text or "").lower()).split() if w]


def word_errors(reference, heard):
    """Substitutions, deletions and insertions between two normalised lists,
    with every substitution named so `five` → `5` is visible rather than a
    number in a column."""
    matcher = difflib.SequenceMatcher(a=reference, b=heard, autojunk=False)
    substitutions, deletions, insertions = [], [], []
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == "replace":
            for index in range(max(i2 - i1, j2 - j1)):
                substitutions.append([
                    reference[i1 + index] if i1 + index < i2 else None,
                    heard[j1 + index] if j1 + index < j2 else None])
        elif tag == "delete":
            deletions.extend(reference[i1:i2])
        elif tag == "insert":
            insertions.extend(heard[j1:j2])
    errors = len(substitutions) + len(deletions) + len(insertions)
    return {
        "reference_words": len(reference), "heard_words": len(heard),
        "substitutions": substitutions, "deletions": deletions, "insertions": insertions,
        "errors": errors,
        "wer": round(errors / len(reference), 4) if reference else None,
    }


def statistics(values):
    rows = sorted(values)
    if not rows:
        return {"count": 0, "median": None, "p95": None, "max": None}
    def at(fraction):
        return rows[min(int(round(fraction * (len(rows) - 1))), len(rows) - 1)]
    return {"count": len(rows), "median": round(at(0.5), 4), "p95": round(at(0.95), 4),
            "max": round(rows[-1], 4), "min": round(rows[0], 4)}


# ---- q1 — SpeechTranscriber over the extracted WAV ------------------------

def _word_rows(answer):
    """The probe's runs as {text, start, end}, the leading space each run
    carries taken off. That space is itself a measurement and is recorded
    beside the row rather than thrown away."""
    rows = []
    for run in answer.get("runs") or []:
        text = run.get("text") or ""
        rows.append({
            "raw": text, "text": text.strip(),
            "leading_space": text.startswith(" "),
            "start": run.get("start"), "end": run.get("end"),
            "confidence": run.get("confidence"),
        })
    return rows


def _shape(rows):
    """W-2's question, asked of what arrived: is every run exactly one
    whitespace token, and where does punctuation sit?"""
    one_token = [r for r in rows if len(r["text"].split()) != 1]
    attached = [r["text"] for r in rows
                if r["text"] and r["text"][-1] in ".,;:!?…’\"'"]
    standalone = [r["text"] for r in rows
                  if r["text"] and not PUNCTUATION.sub("", r["text"])]
    return {
        "runs": len(rows),
        "every_run_is_one_token": not one_token,
        "runs_that_are_not_one_token": [r["text"] for r in one_token][:12],
        "runs_with_a_leading_space": sum(1 for r in rows if r["leading_space"]),
        "punctuation_attached": attached[:12],
        "punctuation_attached_count": len(attached),
        "punctuation_standalone": standalone[:12],
        "punctuation_standalone_count": len(standalone),
        "zero_or_negative_length": sum(
            1 for r in rows
            if isinstance(r["start"], (int, float)) and isinstance(r["end"], (int, float))
            and r["end"] <= r["start"]),
    }


def _pause_reading(rows, pauses):
    """§5c's `breakGap` reads the PREVIOUS word's end, so both edges are
    measured: how late the first word after a pause starts, and how early the
    run that carries it begins. S0 saw ranges ABSORB the pause before them
    (`archive/roadmap-4.md:110-118`)."""
    timed = [r for r in rows
             if isinstance(r["start"], (int, float)) and isinstance(r["end"], (int, float))]
    out = []
    for start, end in pauses:
        crossing = next((r for r in timed if r["start"] < end and r["end"] > start), None)
        # The words that BORDER the pause: the last run to start before it,
        # and the first run to start at or after that run's end. Ranges tile,
        # so neither is required to stay outside the pause — that overlap is
        # what these two fields measure.
        before = None
        for row in timed:
            if row["start"] < start:
                before = row
        after = (next((r for r in timed if r["start"] >= before["end"] - 0.001), None)
                 if before else next((r for r in timed if r["start"] >= start), None))
        # What §5c's `breakGap` would actually SEE: the gap between the word
        # that ends before the pause and the next word to start, which is not
        # the pause's own length if either word has absorbed part of it.
        index = next((i for i, r in enumerate(timed) if r["start"] >= start), None)
        seen_gap = None
        if index is not None and index > 0:
            seen_gap = round(timed[index]["start"] - timed[index - 1]["end"], 3)
        out.append({
            "pause": [start, end],
            "pause_length_s": round(end - start, 3),
            "gap_breakgap_would_see_s": seen_gap,
            "pause_length_minus_gap_s":
                round((end - start) - seen_gap, 3) if seen_gap is not None else None,
            "first_word_after": after["text"] if after else None,
            "first_word_after_start_s": after["start"] if after else None,
            "start_minus_pause_end_s":
                round(after["start"] - end, 3) if after else None,
            "previous_word": before["text"] if before else None,
            "previous_word_end_minus_pause_start_s":
                round(before["end"] - start, 3) if before else None,
            "a_run_crosses_the_pause": crossing["text"] if crossing else None,
            "crossing_run_start_s": crossing["start"] if crossing else None,
        })
    return out


def q1(work, fixtures, say):
    probe, error = build_probe(work)
    if probe is None:
        return {"state": "failed", "reason": "speech_probe did not build",
                "measured": {"build_error": error}}
    measured = {"probe_target": " ".join(TARGET), "files": {}}
    for name in ("pangram.wav", "talk.wav", "ten.wav"):
        path = fixtures.path(name)
        audio = fixtures.seconds.get(name, 0.0)
        bound = 60.0 + 2.0 * audio
        result = run_drained(
            [probe, "words", path, LOCALE, "--bounded-s", f"{bound:.0f}"],
            timeout=bound + 60.0)
        answer = local_rows.spoken(result)
        rows = _word_rows(answer)
        stages = answer.get("stages") or {}
        analyze = stages.get("analyze_s")
        measured["files"][name] = {
            "seconds_audio": answer.get("seconds_audio", audio),
            "bounded_s": bound,
            "child_blocked": result["blocked"],
            "expired": answer.get("expired"),
            "ok": answer.get("ok"),
            "error": answer.get("error"),
            "wall_s": answer.get("wall_s"),
            "stages": stages,
            "real_time_factor":
                round(audio / analyze, 1) if analyze else None,
            "real_time_factor_whole_run":
                round(audio / answer["wall_s"], 1)
                if answer.get("wall_s") else None,
            "results": answer.get("results") or [],
            "result_count": len(answer.get("results") or []),
            "runs_per_result": [r.get("run_count") for r in answer.get("results") or []],
            "shape": _shape(rows),
            "first_twelve": rows[:12],
            "zero_length": answer.get("zero_length"),
            "longest_run_s": answer.get("longest_run_s"),
            "status_before": answer.get("status_before"),
            "status_after": answer.get("status_after"),
            "text": " ".join(r["text"] for r in rows),
        }
        timed = [r for r in rows if isinstance(r.get("start"), (int, float))
                 and isinstance(r.get("end"), (int, float))]
        gaps = [round(b["start"] - a["end"], 3) for a, b in zip(timed, timed[1:])]
        measured["files"][name]["inter_word_gaps_s"] = {
            "largest": max(gaps, default=None), "smallest": min(gaps, default=None),
            "over_0_4_s": sum(1 for g in gaps if g >= 0.4),
            "negative": sum(1 for g in gaps if g < 0),
        }
        if name == "pangram.wav":
            measured["files"][name]["pauses"] = _pause_reading(rows, fixtures.pauses)
        say(f"  q1/{name}: {len(rows)} runs, "
            f"{measured['files'][name]['real_time_factor']}× real time, "
            f"expired {answer.get('expired')}")

    # No length ceiling is a claim about ten minutes, so it is read off the
    # ten-minute file and nothing else.
    ten = measured["files"]["ten.wav"]
    last = max((r.get("end") or 0) for r in (ten["results"] or [{}])) if ten["results"] else 0
    measured["ceiling"] = {
        "file_seconds": ten["seconds_audio"],
        "last_result_end_s": last,
        "covered_fraction": round(last / ten["seconds_audio"], 4)
        if ten["seconds_audio"] else None,
        "verdict": ("no ceiling: results reach the end of a ten-minute file"
                    if ten["seconds_audio"] and last >= ten["seconds_audio"] - 2.0
                    else "results stop short of the file's end"),
    }

    # The TCC question, asked twice: a bare Mach-O, and an ad-hoc-signed
    # hardened-runtime bundle with NO `NSSpeechRecognitionUsageDescription`.
    # `requestAuthorization` is never called in either.
    signed = local_rows.bundle(work, "RCWordsQ1", "com.framejob.spike.w0q1", probe, ats=False)
    bound = 60.0 + 2.0 * fixtures.seconds.get("pangram.wav", 10.0)
    bundled = local_rows.spoken(run_drained(
        [signed["executable"], "words", fixtures.path("pangram.wav"), LOCALE,
         "--bounded-s", f"{bound:.0f}"], timeout=bound + 60.0))
    measured["bundle_no_usage_key"] = {
        "flags": signed["flags"], "cdhash": signed["cdhash"],
        "sign_error": signed["sign_error"],
        "ok": bundled.get("ok"), "error": bundled.get("error"),
        "runs": len(bundled.get("runs") or []),
        "status_before": bundled.get("status_before"),
        "status_after": bundled.get("status_after"),
        "authorization_requested": False,
    }
    say(f"  q1/bundle (no usage key): {measured['bundle_no_usage_key']['runs']} runs, "
        f"status {measured['bundle_no_usage_key']['status_after']}")

    cancelled = local_rows.spoken(run_drained(
        [probe, "cancel", fixtures.path("ten.wav"), LOCALE, "2000"], timeout=180))
    measured["cancel"] = cancelled
    say(f"  q1/cancel at 2000 ms: ok {cancelled.get('ok')}, "
        f"{cancelled.get('results_before_cancel')} results by then, "
        f"{cancelled.get('wall_s')} s")
    # A probe that crashed or answered nothing is a FAILURE, never a `run`
    # with zero rows in it.
    empty = [f"words {name}: {row.get('error') or 'no runs'}"
             for name, row in measured["files"].items()
             if not row.get("ok") or not row["shape"]["runs"]]
    if not bundled.get("ok") or not measured["bundle_no_usage_key"]["runs"]:
        empty.append(f"bundle: {bundled.get('error') or 'no runs'}")
    if not cancelled.get("ok"):
        empty.append(f"cancel: {cancelled.get('error') or 'no answer'}")
    if empty:
        return {"state": "failed", "measured": measured,
                "reason": "a probe answered nothing: " + "; ".join(empty)}
    return {"state": "run", "reason": None, "measured": measured}


# ---- q2 — the two engines against each other and against a known start ----

def _cloud_call(client, ledger, scrub, label, path, planned, say):
    """One paid round trip, ledgered at every step it could be lost at —
    `cloud_rows.call`'s order, with the `words` kept."""
    out = {"label": label, "uploaded": os.path.basename(path)}
    rid = ledger.reserve("q2", label, planned)
    out["rid"] = rid
    reply = client.upload(path)
    out["upload"] = {"status": reply.status, "seconds": round(reply.seconds, 3)}
    url = (reply.json or {}).get("upload_url") if isinstance(reply.json, dict) else None
    if reply.status != 200 or not url:
        ledger.closed(rid, "upload_only", reply.status)
        out["outcome"] = "upload_only"
        return out, []
    ledger.uploaded(rid, url, os.path.getsize(path))
    scrub.add(url)
    submitted = client.submit(url, speech_models=aai.SPEECH_MODELS)
    out["submit"] = {"status": submitted.status, "seconds": round(submitted.seconds, 3)}
    transcript_id = (submitted.json or {}).get("id") if isinstance(submitted.json, dict) else None
    if submitted.status != 200 or not isinstance(transcript_id, str):
        out["submit"]["body"] = scrub.clean(submitted.body[:400].decode("utf-8", "replace"))
        ledger.closed(rid, "no_transcript", submitted.status)
        out["outcome"] = "no_transcript"
        return out, []
    ledger.created(rid, transcript_id)
    reply, polls, seconds = client.wait(transcript_id, 1.0, 600.0)
    body = reply.json if isinstance(reply.json, dict) else {}
    out["wait"] = {"status": reply.status, "polls": polls, "seconds": round(seconds, 2),
                   "transcript_status": body.get("status"),
                   "completed": body.get("status") == "completed"}
    for field in ("speech_model_used", "language_code", "audio_duration"):
        out[field] = body.get(field)
    if isinstance(body.get("audio_duration"), (int, float)):
        ledger.billed(rid, float(body["audio_duration"]))
    words = body.get("words") or []
    deleted = client.delete(transcript_id)
    out["delete"] = {"status": deleted.status,
                     "body": scrub.clean(deleted.body[:200].decode("utf-8", "replace"))}
    out["outcome"] = cloud_rows.record_delete(ledger, rid, deleted)
    out["word_count"] = len(words)
    say(f"  q2/{label}: {out['outcome']} {out.get('speech_model_used')} "
        f"{len(words)} words, delete {deleted.status}")
    return out, words


def _matched_deltas(apple, cloud):
    """Word-start deltas on MATCHED tokens only, lined up by `difflib` over
    the normalised texts, so a substitution never contributes a delta."""
    a_words = [(normalised(r["text"])[:1] or [""])[0] for r in apple]
    c_words = [(normalised(w.get("text"))[:1] or [""])[0] for w in cloud]
    matcher = difflib.SequenceMatcher(a=a_words, b=c_words, autojunk=False)
    deltas, pairs = [], []
    for i1, j1, size in matcher.get_matching_blocks():
        for step in range(size):
            apple_start = apple[i1 + step].get("start")
            cloud_start = cloud[j1 + step].get("start")
            if apple_start is None or cloud_start is None:
                continue
            delta = apple_start * 1000.0 - float(cloud_start)
            deltas.append(delta)
            pairs.append([a_words[i1 + step], round(delta, 1)])
    unmatched = max(len(a_words), len(c_words)) - len(deltas)
    return {"deltas_ms": statistics([abs(d) for d in deltas]),
            "signed_median_ms": statistics(deltas)["median"],
            "unmatched": unmatched, "first_twelve": pairs[:12]}


def _known_start_deltas(rows, known, engine, scale):
    """Both engines against `isolated.wav`'s per-word known start — the
    onset-corrected one, with the RAW concatenation offset printed beside it so
    the synthesizer's own leading silence stays visible as a bias."""
    heard = [(normalised(r["text"])[:1] or [""])[0] for r in rows]
    truth = [(normalised(w["text"])[:1] or [""])[0] for w in known]
    matcher = difflib.SequenceMatcher(a=truth, b=heard, autojunk=False)
    corrected, raw, pairs = [], [], []
    for i1, j1, size in matcher.get_matching_blocks():
        for step in range(size):
            start = rows[j1 + step].get("start")
            if start is None:
                continue
            start_ms = start * scale
            corrected.append(start_ms - known[i1 + step]["known_start_s"] * 1000.0)
            raw.append(start_ms - known[i1 + step]["offset_s"] * 1000.0)
            pairs.append([truth[i1 + step],
                          round(corrected[-1], 1), round(raw[-1], 1)])
    return {
        "engine": engine, "matched": len(corrected),
        "onset_corrected_ms": statistics([abs(d) for d in corrected]),
        "onset_corrected_signed_median_ms": statistics(corrected)["median"],
        "raw_offset_ms": statistics([abs(d) for d in raw]),
        "raw_offset_signed_median_ms": statistics(raw)["median"],
        "first_twelve": pairs[:12],
    }


def q2(work, fixtures, client, ledger, scrub, say):
    if client is None:
        return {"state": "skipped", "measured": {},
                "reason": f"{aai.KEY_ENV} is not set"}
    probe, error = build_probe(work)
    if probe is None:
        return {"state": "failed", "reason": "speech_probe did not build",
                "measured": {"build_error": error}}
    signed = local_rows.bundle(work, "RCWordsQ2", "com.framejob.spike.w0q2", probe, ats=False)
    scripts = {
        "pangram.wav": fixtures_text("pangram"),
        "talk.wav": fixtures_text("talk"),
        "isolated.wav": fixtures_text("isolated"),
    }
    measured = {"files": {}, "bundle": {"flags": signed["flags"], "cdhash": signed["cdhash"]}}
    for name in ("pangram.wav", "talk.wav", "isolated.wav"):
        path = fixtures.path(name)
        audio = fixtures.seconds.get(name, 0.0)
        reference = normalised(scripts[name])
        bound = 60.0 + 2.0 * audio
        apple_answer = local_rows.spoken(run_drained(
            [probe, "words", path, LOCALE, "--bounded-s", f"{bound:.0f}"],
            timeout=bound + 60.0))
        apple_rows = _word_rows(apple_answer)
        # The shipped engine, inside a BUNDLE: the status is read, and the run
        # is attempted whatever it says. A hang is the expiry.
        sf_answer = local_rows.spoken(run_drained(
            [signed["executable"], "sf", path, LOCALE, "--bounded-s", "120"], timeout=180))
        sf_rows = [{"text": s.get("text"), "start": s.get("start"),
                    "end": (s.get("start") or 0) + (s.get("duration") or 0)}
                   for s in sf_answer.get("segments") or []]
        cloud_out, cloud_words = _cloud_call(
            client, ledger, scrub, name.replace(".wav", ""), path, audio, say)
        row = {
            "seconds_audio": audio,
            "speechtranscriber": {
                "ok": apple_answer.get("ok"), "expired": apple_answer.get("expired"),
                "error": apple_answer.get("error"),
                "words": len(apple_rows), "wall_s": apple_answer.get("wall_s"),
                "stages": apple_answer.get("stages"),
                "real_time_factor": round(audio / apple_answer["stages"]["analyze_s"], 1)
                if (apple_answer.get("stages") or {}).get("analyze_s") else None,
                "text": " ".join(r["text"] for r in apple_rows),
                "wer": word_errors(reference, normalised(
                    " ".join(r["text"] for r in apple_rows))),
            },
            "sfspeechrecognizer": {
                "ok": sf_answer.get("ok"), "expired": sf_answer.get("expired"),
                "error": sf_answer.get("error"),
                "status_before": sf_answer.get("status_before"),
                "status_after": sf_answer.get("status_after"),
                "any_result_delivered": sf_answer.get("any_result_delivered"),
                "is_available": sf_answer.get("is_available"),
                "supports_on_device": sf_answer.get("supports_on_device"),
                "segments": len(sf_rows), "wall_s": sf_answer.get("wall_s"),
                "real_time_factor": round(audio / sf_answer["wall_s"], 1)
                if sf_answer.get("wall_s") else None,
                "text": " ".join(r["text"] or "" for r in sf_rows),
                "wer": word_errors(reference, normalised(
                    " ".join(r["text"] or "" for r in sf_rows))),
                # Every callback the engine made, so the final-only reading
                # above can be told apart from what the engine delivered.
                "callbacks": [{k: v for k, v in c.items() if k != "segments"}
                              for c in sf_answer.get("callbacks") or []],
                "callback_count": len(sf_answer.get("callbacks") or []),
                "final_callbacks": sum(1 for c in sf_answer.get("callbacks") or []
                                       if c.get("is_final")),
                "metadata_callbacks": sum(1 for c in sf_answer.get("callbacks") or []
                                          if c.get("has_metadata")),
                "segments_accumulated": len(sf_answer.get("segments_accumulated") or []),
                "wer_accumulated": word_errors(reference, normalised(" ".join(
                    s.get("text") or ""
                    for s in sf_answer.get("segments_accumulated") or []))),
            },
            "assemblyai": {
                **cloud_out,
                "real_time_factor": round(audio / cloud_out["wait"]["seconds"], 1)
                if cloud_out.get("wait", {}).get("seconds") else None,
                "text": " ".join(w.get("text") or "" for w in cloud_words),
                "wer": word_errors(reference, normalised(
                    " ".join(w.get("text") or "" for w in cloud_words))),
            },
            "start_delta_speechtranscriber_vs_assemblyai":
                _matched_deltas(apple_rows, cloud_words),
        }
        if name == "isolated.wav":
            row["known_start"] = {
                "note": "isolated.wav is words said one at a time, an approximation "
                        "of speech; `say` publishes no word timing",
                "median_leading_silence_s": fixtures._median(
                    [w["onset_leading_s"] for w in fixtures.isolated]),
                "speechtranscriber": _known_start_deltas(
                    apple_rows, fixtures.isolated, "SpeechTranscriber", 1000.0),
                "assemblyai": _known_start_deltas(
                    [{"text": w.get("text"), "start": w.get("start")} for w in cloud_words],
                    fixtures.isolated, "AssemblyAI", 1.0),
            }
        measured["files"][name] = row
        say(f"  q2/{name}: WER apple {row['speechtranscriber']['wer']['wer']}, "
            f"sf {row['sfspeechrecognizer']['wer']['wer']} "
            f"(accumulated {row['sfspeechrecognizer']['wer_accumulated']['wer']} over "
            f"{row['sfspeechrecognizer']['callback_count']} callbacks, "
            f"{row['sfspeechrecognizer']['final_callbacks']} final), "
            f"cloud {row['assemblyai']['wer']['wer']}")
    return q2_verdict(measured)


def _cloud_error(cloud):
    """The call's own error, from the fields `_cloud_call` recorded."""
    outcome = cloud.get("outcome")
    if outcome == "upload_only":
        return f"upload_only (upload HTTP {(cloud.get('upload') or {}).get('status')})"
    if outcome == "no_transcript":
        submit = cloud.get("submit") or {}
        return (f"no_transcript (submit HTTP {submit.get('status')}"
                f"{': ' + submit['body'] if submit.get('body') else ''})")
    if outcome != "deleted":
        return f"outcome {outcome}"
    wait = cloud.get("wait") or {}
    return (f"deleted with no words (transcript status {wait.get('transcript_status')}, "
            f"wait HTTP {wait.get('status')})")


def q2_verdict(measured):
    """q2's score, from its `measured` block alone, so it can be asked of a
    RECORDED answer without spending anything. A `words` probe that crashed or
    heard nothing, or a cloud call that did not end `deleted` with words in
    it, is a FAILURE, never a `run` with an empty column. The `sf` half is
    not gated: its expiry is the row's measured answer."""
    empty = []
    files = measured.get("files") or {}
    if not files:
        empty.append("no file was measured")
    for name, row in files.items():
        apple = row.get("speechtranscriber") or {}
        if not apple.get("ok") or not apple.get("words"):
            empty.append(f"words {name}: {apple.get('error') or 'no words'}")
        cloud = row.get("assemblyai") or {}
        if cloud.get("outcome") != "deleted" or not cloud.get("word_count"):
            empty.append(f"assemblyai {name}: {_cloud_error(cloud)}")
    if empty:
        return {"state": "failed", "measured": measured,
                "reason": "a probe or a call answered nothing: " + "; ".join(empty)}
    return {"state": "run", "reason": None, "measured": measured}


def fixtures_text(which):
    """The script a file is compared against. Imported late so this module can
    be read without building anything."""
    import fixtures as words_fixtures
    if which == "talk":
        return words_fixtures.TALK_TEXT
    return words_fixtures.ISOLATED_TEXT


# ---- q3 — AssetInventory, read only ---------------------------------------

def q3(work, say):
    probe, error = build_probe(work)
    if probe is None:
        return {"state": "failed", "reason": "speech_probe did not build",
                "measured": {"build_error": error}}
    first = local_rows.spoken(run_drained([probe, "assets", LOCALE], timeout=120))
    supported = first.get("supported") or []
    installed = set(first.get("installed") or [])
    other = next((code for code in supported if code not in installed), None)
    answer = first if other is None else local_rows.spoken(
        run_drained([probe, "assets", LOCALE, other], timeout=120))
    measured = {
        "supported_count": len(supported),
        "supported": supported,
        "installed": sorted(installed),
        "reserved": answer.get("reserved"),
        "max_reserved": answer.get("max_reserved"),
        "status_installed": answer.get("status_installed"),
        "status_other": answer.get("status_other"),
        "other_locale": answer.get("other_locale"),
        "request_nil_for_installed": answer.get("request_nil"),
        "request_nil_for_other": answer.get("other_request_nil"),
        "progress_before_any_download": answer.get("progress"),
        "download_and_install_called": False,
        "no_network_case": {
            "state": "not_run",
            "reason": "would change host network state",
        },
    }
    say(f"  q3: {len(supported)} supported, {len(installed)} installed, "
        f"status {answer.get('status_installed')} / {answer.get('status_other')} "
        f"for {answer.get('other_locale')}")
    if not first.get("ok") or not answer.get("ok") or not supported:
        return {"state": "failed", "measured": measured,
                "reason": "the assets probe answered nothing: "
                          + str(answer.get("error") or first.get("error")
                                or "no supported locales")}
    return {"state": "run", "reason": None, "measured": measured}
