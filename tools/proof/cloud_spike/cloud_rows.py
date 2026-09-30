#!/usr/bin/env python3
"""Road map 6, spike C0 — the five rows that spend money: q1, q2, q5, q6, q8.

Every paid call has the same skeleton, and its ORDER is the point: reserve
before the upload (so the budget can refuse), the upload URL written before
the submit (so a lost reply still leaves a name), the transcript id written
before the first poll (so a crashed run knows what to delete), the billed
`audio_duration` when the service reports it, and one `closed` event saying
what became of it. `settle` is what reads that back at the start and the end
of a run: it DELETEs what is undeleted, and for an upload whose submit never
answered it asks `find_own` — one page of the list, matched only against an
upload URL this ledger recorded — and deletes what comes back, closing the
reservation only when every DELETE answered 2xx (`record_delete`).
"""

import os
import time

import aai

SHORT = (1.0, 300.0)      # poll interval, ceiling — the 10 s fixture
LONG = (3.0, 3600.0)      # q8's hour


def call(client, ledger, scrub, row, label, path, planned, options,
         poll=SHORT, retry_without_models=False, after_created=None):
    """One paid round trip, ledgered at every step it could be lost at."""
    out = {"row": row, "label": label, "uploaded": path.rsplit("/", 1)[-1]}
    rid = ledger.reserve(row, label, planned)
    out["rid"] = rid
    reply = client.upload(path)
    out["upload"] = {"status": reply.status, "seconds": round(reply.seconds, 3)}
    url = (reply.json or {}).get("upload_url") if isinstance(reply.json, dict) else None
    if reply.status != 200 or not url:
        out["outcome"] = "upload_only"
        out["body"] = scrub.clean(reply.body[:400].decode("utf-8", "replace"))
        ledger.closed(rid, "upload_only", reply.status)
        return out
    size = os.path.getsize(path)
    ledger.uploaded(rid, url, size)
    scrub.add(url)
    out["bytes"] = size
    out["upload"]["megabytes_per_second"] = round(size / 1e6 / max(reply.seconds, 1e-6), 3)
    try:
        submitted = client.submit(url, **options)
    except aai.TransportError as error:
        out["submit"] = {"transport_error": scrub.clean(str(error))}
        # What `recover` answered, not a fixed "recovered": a found transcript
        # whose DELETE failed stays owed (#170).
        answer = recover(client, ledger, scrub, rid, url, "proven")
        out["outcome"] = f"lost reply — find_own: {answer}"
        return out
    out["submit"] = {"status": submitted.status, "seconds": round(submitted.seconds, 3)}
    if submitted.status != 200:
        body = scrub.clean(submitted.body[:600].decode("utf-8", "replace"))
        out["submit"]["body"] = body
        if retry_without_models and "speech_models" in body:
            out["submit"]["retried_without_speech_models"] = True
            options = dict(options)
            options["speech_models"] = None
            submitted = client.submit(url, **options)
            out["submit"]["retry_status"] = submitted.status
            if submitted.status != 200:
                out["submit"]["retry_body"] = scrub.clean(
                    submitted.body[:600].decode("utf-8", "replace"))
        if submitted.status != 200:
            out["outcome"] = "no_transcript"
            ledger.closed(rid, "no_transcript", submitted.status)
            return out
    transcript_id = (submitted.json or {}).get("id")
    if not isinstance(transcript_id, str):
        out["outcome"] = "no_transcript"
        ledger.closed(rid, "no_transcript", submitted.status)
        return out
    ledger.created(rid, transcript_id)
    if after_created is not None:
        # q1's `list_match` is measured HERE, while the transcript is still
        # live: a look after the DELETE would prove nothing about recovering
        # one that was lost.
        after_created(url, transcript_id, out)
    reply, polls, seconds = client.wait(transcript_id, poll[0], poll[1])
    body = reply.json if isinstance(reply.json, dict) else {}
    out["wait"] = {"status": reply.status, "polls": polls, "seconds": round(seconds, 2),
                   "transcript_status": body.get("status"),
                   "error": scrub.clean(str(body.get("error"))) if body.get("error") else None,
                   "completed": body.get("status") == "completed"}
    for field in ("speech_model_used", "language_code", "language_confidence", "audio_duration"):
        out[field] = body.get(field)
    if isinstance(body.get("audio_duration"), (int, float)):
        ledger.billed(rid, float(body["audio_duration"]))
    out["words"] = body.get("words") or []
    if body.get("status") not in ("completed", "error"):
        out["wait"]["ceiling_hit"] = True
    deleted = client.delete(transcript_id)
    out["delete"] = {"status": deleted.status, "seconds": round(deleted.seconds, 3),
                     "body": scrub.clean(deleted.body[:200].decode("utf-8", "replace"))}
    out["outcome"] = record_delete(ledger, rid, deleted)
    out["transcript_id_ledgered"] = True
    return out


def record_delete(ledger, rid, reply, *more):
    """What a reservation's DELETEs got, in the ledger (#82, #170).

    One reply per transcript DELETEd for it. When every one is 2xx the
    reservation closes `deleted` with the last reply's status. Anything else
    leaves it OPEN, so `undeleted()` (or, for a lost submit, `lost()`) still
    owes it and the next `settle` retries it, and answers `delete_failed`."""
    replies = (reply,) + more
    if all(200 <= each.status < 300 for each in replies):
        ledger.closed(rid, "deleted", replies[-1].status)
        return "deleted"
    return "delete_failed"


def delete_found(client, ledger, rid, ids):
    """A lost submit's transcripts, found by `find_own`, DELETEd — every id,
    even after one failed — and recorded through `record_delete` (#170): the
    reservation closes `deleted` only when every DELETE answered 2xx."""
    replies = [client.delete(found) for found in ids]
    return record_delete(ledger, rid, *replies)


def recover(client, ledger, scrub, rid, url, list_match, uploaded_at=None):
    """An upload whose submit was lost: find it by ITS OWN url, delete it.
    A found transcript whose DELETE failed answers `delete_failed` and leaves
    the reservation in `lost()`, for the next `settle` (#170)."""
    status, ids = client.find_own({url})
    if ids:
        return delete_found(client, ledger, rid, ids)
    young = uploaded_at is not None and (time.time() - uploaded_at) < 60
    if list_match == "proven" and status == 200 and not young:
        ledger.closed(rid, "no_transcript", status)
        return "no_transcript"
    if list_match == "proven" and status == 200:
        return "open"
    ledger.closed(rid, "unresolved", status)
    return "unresolved"


def settle(client, ledger, scrub, list_match, say):
    """The first and last act of every run that has a key."""
    counts = {}
    for rid, transcript_id in ledger.undeleted():
        answer = record_delete(ledger, rid, client.delete(transcript_id))
        counts[answer] = counts.get(answer, 0) + 1
    for rid in ledger.unsent():
        ledger.closed(rid, "upload_only")
        counts["upload_only"] = counts.get("upload_only", 0) + 1
    for rid, url, at in ledger.lost():
        outcome = recover(client, ledger, scrub, rid, url, list_match, at)
        counts[outcome] = counts.get(outcome, 0) + 1
    say("settled: " + (", ".join(f"{k} {v}" for k, v in sorted(counts.items())) or "nothing open"))
    return counts


# ---- The rows --------------------------------------------------------------

def overlaps(words, pauses):
    """Per word, its overlap in ms with each truth pause. A crossing is > 33 ms."""
    rows = []
    for word in words:
        start, end = word.get("start", 0), word.get("end", 0)
        worst = 0.0
        for pause_start, pause_end in pauses:
            overlap = min(end, pause_end * 1000.0) - max(start, pause_start * 1000.0)
            worst = max(worst, overlap)
        if worst > 0:
            rows.append({"text": word.get("text"), "start": start, "end": end,
                         "overlap_ms": round(worst, 1), "crosses": worst > 33})
    return rows


def q1(client, ledger, scrub, work, seconds, pauses, say):
    fixture = f"{work}/fixtures/speech.wav"
    rows = {}
    list_match = "absent"
    seen = {}

    def look(url, transcript_id, out):
        status, ids = client.find_own({url}, own_id=transcript_id)
        out["own_entry_at_once"] = dict(client.last_own_entry)
        if not ids:
            # A page that has not caught up yet is a different answer from a
            # page that does not carry the URL, and C1's recovery depends on
            # which one this is. Five seconds, once.
            time.sleep(5.0)
            status, ids = client.find_own({url}, own_id=transcript_id)
            # Written ONLY when this second look ran, so the key's presence
            # is itself the answer to "did the page lag".
            out["own_entry_after_5s"] = dict(client.last_own_entry)
        seen["list_match"] = ("proven" if status == 200 and ids == [transcript_id]
                              else ("absent" if status == 200 else f"error:{status}"))
        out["list_match_ids_returned"] = len(ids)
        out["list_status"] = status

    for label, options in (("plain", {}),
                           ("speaker_labels", {"speaker_labels": True}),
                           ("language_code_en", {"language_code": "en"})):
        answer = call(client, ledger, scrub, "q1", label, fixture, seconds, options,
                      retry_without_models=True,
                      after_created=look if label == "plain" else None)
        list_match = seen.get("list_match", list_match)
        text = [w.get("text") for w in answer.get("words") or []]
        answer["word_count"] = len(text)
        # 5f's fifth rule needs to know whether a speaker ever arrives, and
        # §2 says `speaker` is null unless `speaker_labels` was asked for.
        answer["speakers_seen"] = sorted(
            {str(w.get("speaker")) for w in answer.get("words") or []})
        answer["confidence_range"] = [
            min((w.get("confidence", 0) for w in answer.get("words") or []), default=None),
            max((w.get("confidence", 0) for w in answer.get("words") or []), default=None)]
        answer["text_in_order"] = " ".join(text)
        answer["pause_overlaps"] = overlaps(answer.get("words") or [], pauses)
        answer["crossings"] = sum(1 for row in answer["pause_overlaps"] if row["crosses"])
        answer.pop("words", None)
        rows[label] = answer
        say(f"  q1/{label}: {answer.get('outcome')} "
            f"{answer.get('speech_model_used')} {answer.get('word_count')} words "
            f"{answer['crossings']} crossings")
    rows["list_match"] = list_match
    return {"state": "run", "reason": None, "measured": rows}


def q2(client, ledger, scrub, work, seconds, formats, say):
    """WAV twice (the control), then each smaller format once."""
    rows = {}
    order = [("wav_1", "speech.wav"), ("wav_2", "speech.wav")]
    order += [(name, path.rsplit("/", 1)[-1]) for name, path in formats]
    for label, name in order:
        answer = call(client, ledger, scrub, "q2", label, f"{work}/fixtures/{name}",
                      seconds, {})
        rows[label] = answer
        say(f"  q2/{label} ({name}): {answer.get('outcome')} "
            f"{len(answer.get('words') or [])} words")
    reference = rows.get("wav_1", {}).get("words") or []
    for label, answer in rows.items():
        words = answer.get("words") or []
        deltas = []
        for index, word in enumerate(words):
            if index < len(reference) and word.get("text") == reference[index].get("text"):
                deltas.append(word.get("start", 0) - reference[index].get("start", 0))
        answer["delta_start_ms"] = deltas
        answer["max_abs_delta_ms"] = max((abs(d) for d in deltas), default=None)
        answer["word_count"] = len(words)
        answer["texts_line_up"] = len(deltas) == len(words) == len(reference)
        answer.pop("words", None)
    return {"state": "run", "reason": None, "measured": rows}


def q5(client, ledger, scrub, work, seconds, say):
    answer = call(client, ledger, scrub, "q5", "language_xx", f"{work}/fixtures/speech.wav",
                  seconds, {"language_code": "xx"})
    answer.pop("words", None)
    refused = answer.get("submit", {}).get("status", 0)
    answer["verdict"] = ("refused at submission" if 400 <= refused < 500
                         else "accepted at submission" if refused == 200 else "no answer")
    say(f"  q5: {answer['verdict']} ({refused})")
    return {"state": "run", "reason": None, "measured": answer}


def q6(client, ledger, scrub, work, seconds, say):
    """A transcript of the spike's own, deleted, then asked for twice."""
    answer = call(client, ledger, scrub, "q6", "own", f"{work}/fixtures/speech.wav",
                  seconds, {})
    answer.pop("words", None)
    measured = {"round_trip": answer}
    rid = answer.get("rid")
    transcript_id = ledger.reservations().get(rid, {}).get("transcript_id")
    if transcript_id:
        after = client.get(transcript_id)
        measured["get_after_delete"] = {
            "status": after.status, "seconds": round(after.seconds, 3),
            "body": scrub.clean(after.body[:300].decode("utf-8", "replace"))}
        again = client.delete(transcript_id)
        measured["second_delete"] = {
            "status": again.status, "seconds": round(again.seconds, 3),
            "body": scrub.clean(again.body[:300].decode("utf-8", "replace"))}
        say(f"  q6: first delete {answer.get('delete', {}).get('status')}, "
            f"GET after {after.status}, second delete {again.status}")
    return {"state": "run", "reason": None, "measured": measured}


def q8(client, ledger, scrub, work, loop_seconds, say):
    """The hour. Upload rate, processing rate, and the drift across 346 loops."""
    answer = call(client, ledger, scrub, "q8", "hour", f"{work}/fixtures/hour.wav",
                  3600.0, {}, poll=LONG)
    words = answer.get("words") or []
    answer["word_count"] = len(words)
    # Each occurrence of the loop's first word is placed at the NEAREST loop
    # index rather than at a running counter: one missed or one extra
    # occurrence would otherwise desynchronise the count and leave every
    # later loop outside the window, which is what the first reading of this
    # row did — six loops of three hundred and forty-six.
    period = loop_seconds * 1000.0
    first = words[0].get("text") if words else None
    residuals = {}
    for word in words:
        if word.get("text") != first:
            continue
        index = int(round(word.get("start", 0) / period))
        residuals.setdefault(index, round(word.get("start", 0) - index * period, 1))
    drifts = [residuals[index] for index in sorted(residuals)]
    answer["loop_period_ms"] = round(period, 3)
    answer["first_word"] = first
    answer["loops_expected"] = int(3600.0 / loop_seconds) + 1
    answer["loops_found"] = len(drifts)
    answer["drift_ms"] = {"min": min(drifts, default=None), "max": max(drifts, default=None),
                          "first_ten": drifts[:10], "last_ten": drifts[-10:],
                          "ambiguous": [d for d in drifts if abs(d) > period / 4]}
    answer.pop("words", None)
    say(f"  q8: {answer.get('outcome')} audio_duration {answer.get('audio_duration')} "
        f"{answer['word_count']} words, drift {answer['drift_ms']['min']}…"
        f"{answer['drift_ms']['max']} ms")
    return {"state": "run", "reason": None, "measured": answer}
