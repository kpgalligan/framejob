#!/usr/bin/env python3
"""Road map 6, C1 pipeline 3 — the cloud engine through the BUILT binary.

Drives `make app`'s Reelcut over MCP against `assemblyai_fake.py` on a
loopback socket. Nothing here calls AssemblyAI: every instance is launched
with `-RCAssemblyAIEndpoint http://127.0.0.1:<the fake's port>` and
`-RCSecretFolder <a folder under work/>` (spec §11's R6-9), and the only
credential any of them can have is the dummy `proof-key` this file puts in
the environment — or, for row 1's no-key arm, nothing at all.

    env -u RC_ASSEMBLYAI_KEY python3 tools/proof/cloud_captions_proof.py
    env -u RC_ASSEMBLYAI_KEY python3 tools/proof/cloud_captions_proof.py --mutant no-hold

Road map 6 §5i's rows 1–11, plus five of this pipeline's own:

* **1** the caller's own mistakes — a misspelt `engine`, a cloud-only
  argument under `apple`, and the cloud engine with no key at all — each
  refused BY NAME with the fake's log still empty.
* **2** a two-clip project over ONE media uploads ONCE, as a FLAC whose body
  decodes to the same audio the on-device engine's WAV holds. Written as a
  POPULATION and not as one comparison: this host's 16 kHz extract is not
  bit-deterministic (`archive/reelcut-remaining.md` §5), so what is asserted
  is one length, at most two distinct strings differing in a single sample,
  with a CONTROL that says the instrument would notice a third. The
  result's `endpoint` is the fake's host alone, `127.0.0.1` (#94).
* **LOG** every request the client made is in the instance's redirected
  log, in the fake's order, as soon as `transcribe` answers (#116).
* **3** the placed cues, tick for tick, against an ORACLE computed in Python
  from the served words and the clips' own `in`, `speed` and `start`, with
  the harness's `cues` mode doing the line-breaking.
* **4** the cache file's `words` byte-equal to what the fake served, its
  marker equal to the stamp this script computes from `os.stat` and
  `get_project`, and `remote_deleted` true.
* **5** the cache, `refresh`, a relink and a relink back, a split pair
  partitioning the words, a later `in`, and the two clips `Transcriber.jobs`
  refuses by name.
* **6** a 401, a transcript that ends in `error`, a 5xx once and a 5xx
  always.
* **7** `speakers`, `vocabulary`, and every new reader at its extremes.
* **8** `transcribe` with no `engine` leaves the fake's log EMPTY.
* **9** `truncated` is never present for the cloud engine.
* **10** plain HTTP to loopback with no `NSAppTransportSecurity` key in
  `project.yml` or in the BUILT `Info.plist` (C0's q3).
* **11** a failed DELETE is retried FIRST by the next run — and R6-11's
  HOLD: a media whose delete is still unconfirmed is not uploaded again,
  even under `refresh`, and its cache file is left byte for byte.
* **H** a media over AssemblyAI's ten-hour limit, refused by name before a
  byte is extracted.
* **T** no `reelcut-upload-*` survives a cancelled, a failed or a refused
  run, with a CONTROL that one is there while the body is going out.
* **K** the dummy key appears in no app log, no MCP answer and no file this
  run wrote but the fake's own request log.
* **X** no logged header or body holds this host's user name or home path.
* **RP** (issue batch B24, #80; spec §11 R6-17) the 21 pairs of `transcribe`'s
  seven refusals, each cell ONE check — the winner's own sentence line for
  line, no loser's words, and the fake's log delta — after seven
  single-ingredient CONTROLS.

Five instances, each on its own port with its own fake, each killed by its
own PID in a `finally`, each with a row that `grep "Reelcut: "` finds nothing
in its log: A, B and C, then **RP** (`port_base + 3`, keyed) and **RQ**
(`port_base + 4`, no key, its own loopback fake) for row RP. Host-state
inputs: `media/speech.mov` and `media/AV.mov`, `say`
for the second fixture, `ffmpeg` for row 2's second decoder (the row names which decoders
answered and `AVAudioFile` always runs), and free loopback ports.

`--mutant <name>` builds a COPY of the tree with `tree_copy.make_copy` —
`app/` and `agent/` copied, every other build input `project.yml` names a
SYMLINK to the tree's, `core` already built — patches one text asserted to
occur exactly once, runs the copy's `make app` under a 900 s wall, and runs every row
against that binary on `--port-base 4960`. A mutant that survives is a
finding about the ROW, not about the mutant. A mutant (or `--fake-mutant`)
whose control could not be performed — the text to replace not found
exactly once, or the copy not built — prints `mutant <name>: the control
could not be performed — <why>` and exits 2 (rule R, issue batch B13).
"""

import argparse
import getpass
import glob
import hashlib
import json
import os
import pty
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import threading
import time

from mcp import MCP, ToolError

# The probe's instruments, imported rather than copied (road map 6 §10.9
# built them; a second spelling of any of them is the drift this tree warns
# about).
# The MODULE as well as the names: `--fake-mutant` rebinds the probe's one
# `FAKE` global, and `Fake.__enter__` reads it off the module, so the
# rebinding has to happen there and not on a copy of the name here.
import cloud_captions_probe
import tree_copy

from cloud_captions_probe import (
    HARNESS_MAIN, PROBE_SOURCE, TREE_SOURCES, Fake, MUTANTS, build, child_env,
    differences_between, make_fixture, population, run_cues, run_probe, wav_samples, word)

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.join(ROOT, "tools", "proof")
MEDIA = os.path.join(HERE, "media")
WORK = os.path.join(HERE, "work", "cloudproof")

DUMMY = "proof-key"
SEC = 600_000

# The `key=` sentinel for a LIVE instance: the variable is copied by
# INHERITANCE, out of `os.environ` into the child's environment, and is never
# bound to a name in this process. `None` is "no credential at all" (row 1's
# second instance) and a string is a dummy; this is neither.
INHERIT = object()

# Set by `cloud_captions_live.run` before the first live instance: the
# `Scrubber` `client_from_env` filled (`cloud_spike/aai.py:207`, the key's one
# reader), so the pty reader below can TEST a line for the key and clean it
# before anything is kept. `None` everywhere else, and the fake's dummy needs
# no scrubbing.
live_scrubber = None
BOUND_PORT = re.compile(r"listening on http://127\.0\.0\.1:(\d+)/mcp")

# The words the fake serves for every row that needs a transcript. Five of
# them, inside the first five seconds of the fixture, spread so a split at
# 3.0 s puts some either side.
WORDS = [
    {"text": "Hello", "start": 600, "end": 1120, "confidence": 0.98, "speaker": None},
    {"text": "there", "start": 1180, "end": 1600, "confidence": 0.96, "speaker": None},
    {"text": "everyone", "start": 1700, "end": 2400, "confidence": 0.91, "speaker": None},
    {"text": "welcome", "start": 3000, "end": 3600, "confidence": 0.93, "speaker": None},
    {"text": "back", "start": 3700, "end": 4100, "confidence": 0.95, "speaker": None},
]

passed = 0
failed = 0
skipped = 0
skips = []
# Everything an MCP call answered, for row K and row X.
transcript_of_the_run = []
logs = {}


def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print(f"  ok   {name}")
    else:
        failed += 1
        print(f"  FAIL {name}" + (f"\n       {detail}" if detail else ""))


def run_row(row, *arguments):
    """One row's function, with anything it throws scored as that row's
    failure rather than ending the run.

    A mutant is the reason: `no-delete` leaves every transcript undeleted, so
    R6-11 HOLDS every later run and a call three rows away throws where the
    tree's build answers. A traceback there would take the score with it, and
    a mutant's score is the measurement."""
    try:
        row(*arguments)
    except Exception as problem:  # noqa: BLE001 — a row's throw is its answer
        detail = f"{type(problem).__name__}: {problem}"
        if live_scrubber is not None:
            detail = live_scrubber.clean(detail)
        check(f"{row.__name__} ran to its end", False, detail)


def skip_rows(count, reason):
    global skipped
    skipped += count
    skips.append((count, reason))
    print(f"  SKIPPED by name: {reason} — {count} rows did not run")


def fresh(*parts):
    path = os.path.join(WORK, *parts)
    shutil.rmtree(path, ignore_errors=True)
    os.makedirs(path)
    return path


def read(path):
    try:
        with open(path, "rb") as handle:
            return handle.read()
    except OSError:
        return b""


# --------------------------------------------------------------------------
# One instance, launched by this script and killed by this script


class Instance:
    """One Reelcut on a port of its own, pointed at one fake.

    **It kills only what it started** — `Popen`'s own pid, SIGTERM then
    SIGKILL. Nothing here reads `pgrep`: another session's instance is none
    of this script's business.
    """

    def __init__(self, tag, port, fake, binary, key=DUMMY, live=False, endpoint=None):
        self.tag = tag
        self.fake = fake
        self.live = live
        self.secrets = fresh("secrets-" + tag)
        self.log = f"/tmp/reelcut-{port}.log"
        logs[tag] = self.log
        if os.path.exists(self.log):
            os.remove(self.log)
        self.handle = open(self.log, "wb")
        # The pty reader's state. Empty and unused for a fake-backed instance.
        self.captured = []
        self.lock = threading.Lock()
        self.leaked = False
        self.reader_failed = False
        self.master = None
        self.reader = None
        if key is INHERIT:
            # Copied, never read: `dict(os.environ)` carries
            # `RC_ASSEMBLYAI_KEY` into the child without this process ever
            # naming its value.
            env = dict(os.environ)
        else:
            env = child_env()
            if key is not None:
                # The dummy, never the person's own: `child_env()` has already
                # taken `RC_ASSEMBLYAI_KEY` out.
                env["RC_ASSEMBLYAI_KEY"] = key
        env["RC_AGENT_PORT"] = str(port)
        # `-ReelcutCaptionEngine assemblyai` pins the SHEET's memory of
        # what a person last chose to the wrong answer for a tool, which
        # is what makes row 8 a real row: R6-2 says an agent call reads
        # that key never, and an instance where it reads "apple" could
        # not tell a build that obeys R6-2 from one that does not.
        argv = [binary, "-ApplePersistenceIgnoreState", "YES", "-AgentServerEnabled", "YES",
                "-ReelcutCaptionEngine", "assemblyai", "-RCSecretFolder", self.secrets]
        if live:
            # NO endpoint override, so the client speaks to the region's own
            # host — and the secret folder above is an EMPTY directory, which
            # is what keeps the person's real store closed (R6-9) and leaves
            # the environment as the only credential.
            argv += ["-ReelcutAssemblyAIRegion", "us"]
        else:
            argv += ["-RCAssemblyAIEndpoint", endpoint or fake.base]
        if live:
            # A pty, because `note`'s `print` is BLOCK-buffered under a file
            # redirect: an instance whose stdout is a file writes its client
            # lines 4096 bytes at a time and cuts the last one in half, and
            # the live rows COUNT those lines.
            self.master, slave = pty.openpty()
            self.process = subprocess.Popen(
                argv, stdout=slave, stderr=subprocess.STDOUT, env=env,
                stdin=subprocess.DEVNULL)
            # The parent's own copy of the slave, closed here: without this
            # the reader never sees EOF and `stop()` hangs on the join.
            os.close(slave)
            self.reader = threading.Thread(target=self._read_pty, daemon=True)
            self.reader.start()
        else:
            self.process = subprocess.Popen(
                argv, stdout=self.handle, stderr=subprocess.STDOUT, env=env,
                stdin=subprocess.DEVNULL)
        self.port = self._await_port()
        self.mcp = MCP(self.port, timeout=300)

    def _read_pty(self):
        """The live instance's stdout, line by line, in BYTES.

        It never raises. `OSError` and an empty read are both EOF (macOS
        answers `EIO` on the master once the child is gone); any other
        exception sets `reader_failed` and the thread KEEPS DRAINING and
        discarding, so the app can never block in `print` with a transcript
        half made.
        """
        tail = b""
        while True:
            try:
                block = os.read(self.master, 65536)
            except OSError:
                block = b""
            if not block:
                if tail and not self.reader_failed:
                    self._line(tail)
                return
            if self.reader_failed:
                continue
            try:
                pieces = (tail + block).split(b"\n")
                tail = pieces.pop()
                for piece in pieces:
                    self._line(piece)
            except Exception:  # noqa: BLE001 — the thread's whole failure rule
                self.reader_failed = True
                tail = b""

    def _line(self, raw):
        """One whole line: tested RAW for the key, then cleaned, then kept.

        The log handle is flushed per line because `_await_port` polls that
        file for the port.
        """
        text = raw.decode("utf-8", errors="replace").replace("\r", "")
        if live_scrubber is not None:
            for secret in live_scrubber.secrets:
                if secret in text:
                    self.leaked = True
            text = live_scrubber.clean(text)
        with self.lock:
            self.captured.append(text)
        self.handle.write((text + "\n").encode("utf-8", errors="replace"))
        self.handle.flush()

    def mark(self):
        """How many lines have been captured — the `since` a row brackets a
        call with."""
        with self.lock:
            return len(self.captured)

    def client_lines(self, since=0):
        """The `AssemblyAI: ` lines captured since a mark, with that prefix
        taken off: `POST /v2/upload → 200` and the like."""
        with self.lock:
            rows = list(self.captured[since:])
        prefix = "AssemblyAI: "
        return [line[len(prefix):] for line in rows if line.startswith(prefix)]

    def _await_port(self, seconds=60):
        deadline = time.time() + seconds
        while time.time() < deadline:
            if self.process.poll() is not None:
                raise RuntimeError(
                    f"the {self.tag} instance exited with {self.process.returncode} before it "
                    f"bound a port — {self.log}")
            found = BOUND_PORT.search(read(self.log).decode("utf-8", "replace"))
            if found:
                return int(found.group(1))
            time.sleep(0.2)
        raise RuntimeError(f"the {self.tag} instance never named a port in {self.log}")

    def parity(self):
        complaints = [line for line in read(self.log).decode("utf-8", "replace").splitlines()
                      if "Reelcut: " in line]
        check(f"{self.tag}: the startup parity check said nothing — `grep \"Reelcut: \"` on "
              f"{self.log} is empty", not complaints, "\n       ".join(complaints[:5]))

    def stop(self):
        if self.process.poll() is None:
            self.process.terminate()
            deadline = time.time() + 15
            while time.time() < deadline and self.process.poll() is None:
                time.sleep(0.2)
            if self.process.poll() is None:
                self.process.send_signal(signal.SIGKILL)
                self.process.wait(timeout=10)
        if self.live:
            # The process is dead, so the master is at EOF: the reader ends
            # of its own accord. The 10 s wall is rule H — an expiry is the
            # row's measured answer, not a hang.
            if self.reader is not None:
                self.reader.join(timeout=10)
                if self.reader.is_alive():
                    self.reader_failed = True
            if self.master is not None:
                try:
                    os.close(self.master)
                except OSError:
                    pass
        self.handle.close()

    def __enter__(self):
        return self

    def __exit__(self, *rest):
        self.parity()
        self.stop()
        return False


class Session:
    """One project in one instance — `phase4_proof.py`'s shape, minus the
    parts this feature has no use for."""

    def __init__(self, instance, name):
        self.instance = instance
        self.mcp = instance.mcp
        self.path = os.path.join(WORK, f"{name}-{os.getpid()}.reelcut")
        shutil.rmtree(self.path, ignore_errors=True)
        self.mcp.call("new_project", path=self.path)

    def op(self, tool, **arguments):
        answer = self.mcp.call_with(tool, dict(arguments, project=self.path))
        transcript_of_the_run.append(json.dumps(answer, default=str))
        return answer

    def error(self, tool, **arguments):
        """The in-band refusal text, or None when the call succeeded."""
        try:
            self.op(tool, **arguments)
            return None
        except ToolError as problem:
            transcript_of_the_run.append(str(problem))
            return str(problem)

    def project(self):
        return self.op("get_project")["project"]

    def media_of(self, path):
        return self.op("import_media", path=path)["media"]

    def add(self, media, at=0, track=None, duration=None):
        track = track if track is not None else self.project()["tracks"][0]["id"]
        clip = self.op("add_clip", track=track, media=media, at=at)["new_clips"][0]
        if duration is not None:
            self.op("trim_end", clip=clip, to=at + duration)
        return clip

    def clip(self, clip):
        return {c["id"]: c for c in self.project()["clips"]}[clip]

    def save(self):
        return self.op("save_project")


# --------------------------------------------------------------------------
# The fixtures


def fixtures():
    """`media/speech.mov`, and the probe's `say` fixture as a SECOND file —
    a different media over a different path, which is what rows 2, 6 and 11
    need to tell two uploads apart. Row 5's relink cannot use it: a relink
    keeps a media's kind (spec §11 #63), so that row copies `AV.mov`."""
    speech = os.path.join(MEDIA, "speech.mov")
    if not os.path.exists(speech):
        return None, None
    second = make_fixture()
    return speech, second


def scenario(fake, **given):
    body = dict(words=WORDS)
    body.update(given)
    fake.scenario(**body)
    return body


def routes(log):
    return [f"{row['method']} {row['path'].split('?')[0]}" for row in log["requests"]]


def uploads(log):
    return [row for row in log["requests"] if row["path"] == "/v2/upload"]


def submits(log):
    return [row for row in log["requests"]
            if row["method"] == "POST" and row["path"] == "/v2/transcript"]


def deletes(log):
    return [row for row in log["requests"] if row["method"] == "DELETE"]


# --------------------------------------------------------------------------
# Row 1 — the caller's own mistakes


def row_one_caller(instance, fake):
    print("\n1. the caller's own mistakes, refused by name and above the network")
    scenario(fake)
    speech, _ = fixtures()
    session = Session(instance, "row1")
    media = session.media_of(speech)
    session.add(media)

    text = session.error("transcribe", engine="nope")
    check("1: a misspelt engine is refused with BOTH spellings named",
          text is not None and 'engine must be "apple" or "assemblyai" (got "nope").' in text,
          f"got {text!r}")
    for name, value in (("speakers", True), ("vocabulary", ["acme"]), ("refresh", True)):
        text = session.error("transcribe", **{name: value})
        check(f"1: {name} under the default engine is refused by name, not dropped",
              text is not None
              and f'{name} only applies with engine "assemblyai". Pass engine: '
                  '"assemblyai", or leave it out.' in text,
              f"got {text!r}")
    text = session.error("transcribe", engine="apple", speakers=True, vocabulary=["a"])
    check("1: with two cloud-only arguments present the FIRST is the one named",
          text is not None and text.startswith("transcribe: speakers only applies"),
          f"got {text!r}")
    text = session.error("transcribe", clips=[99999], engine="assemblyai")
    check("1: an unknown clip is refused before the engine, the key or anything else",
          text is not None and "99999" in text, f"got {text!r}")
    check("1: and NONE of them touched the fake — its request log is empty",
          fake.log()["requests"] == [],
          f"got {routes(fake.log())!r}")


def row_one_no_key(instance, fake):
    print("\n1. the cloud engine with no key at all (a SECOND instance, the variable removed)")
    scenario(fake)
    speech, _ = fixtures()
    session = Session(instance, "row1-nokey")
    media = session.media_of(speech)
    session.add(media)
    text = session.error("transcribe", engine="assemblyai")
    check("1: with no key the run is refused with 5g's own sentence",
          text is not None
          and "No AssemblyAI API key is set. Set one in Reelcut ▸ Settings ▸ Transcription, "
              "or RC_ASSEMBLYAI_KEY for a proof." in text,
          f"got {text!r}")
    check("1: and no request was made to find that out — the credential is read ABOVE the "
          "network", fake.log()["requests"] == [], f"got {routes(fake.log())!r}")


def seed_keyless_package(instance, fake):
    """Seed with the dummy key in the owned keyed instance, then save a
    package the later keyless instance can open with no account state."""
    print("\nKL seed. keyed fake writes the package for the independent keyless app")
    speech, _ = fixtures()
    scenario(fake, fail=[{"route": "delete", "status": 500, "times": 1}])
    session = Session(instance, "keyless-package")
    media = session.media_of(speech)
    session.add(media, at=0, duration=3 * SEC)
    seeded = session.op("transcribe", engine="assemblyai", place=False)
    session.save()
    transcript = cache_path(session, media)
    marker = cache_path(session, media, marker=True)
    header = json.loads(read(transcript) or b"{}")
    check("KL seed: saved package has a readable transcript, marker and pending ID",
          bool(seeded.get("cues")) and os.path.isfile(transcript)
          and os.path.isfile(marker) and header.get("remote_deleted") is False,
          f"answer={seeded!r}, header={header!r}")
    if not os.path.isfile(transcript) or not os.path.isfile(marker):
        return None
    # Unrelated and unsafe IDs must be reported although this scope names
    # only one media. They are package files, not a second client account.
    folder = os.path.dirname(transcript)
    for extra, ident in ((90, "t_unrelated"), (91, "unsafe/id")):
        with open(os.path.join(folder, f"{extra}.json"), "w") as handle:
            handle.write(cloud_captions_probe.UNDELETED_DOCUMENT % ident)
    return {"path": session.path, "media": media, "cues": seeded["cues"],
        "bytes": {name: read(os.path.join(folder, name)) for name in os.listdir(folder)}}


def row_keyless_mcp(instance, fake, seed):
    print("\nKL MCP. saved package reopened without credential or usable endpoint")
    if seed is None:
        check("KL MCP: seeded package is available", False)
        return
    path = seed["path"]
    instance.mcp.call("open_project", path=path)
    def op(tool, **kwargs):
        return instance.mcp.call_with(tool, dict(kwargs, project=path))
    def project():
        return op("get_project")["project"]
    before = project()
    count = len(fake.log()["requests"])
    folder = os.path.join(path, "cache", "transcripts")
    package_before = {name: read(os.path.join(folder, name)) for name in os.listdir(folder)}
    try:
        preview = op("transcribe", engine="assemblyai", place=False)
    except ToolError as problem:
        check("KL MCP: place:false returns the seeded cue text/times with zero bill",
              False, str(problem))
        return
    check("KL MCP: place:false returns the seeded cue text/times with zero bill",
          preview.get("cues") == seed["cues"]
          and preview.get("cached") == [seed["media"]]
          and preview.get("uploaded") == [] and preview.get("audio_seconds") == 0,
          f"preview={preview!r}, seeded={seed['cues']!r}")
    check("KL MCP: a keyless run built no client, so its result has no `endpoint` (#94)",
          "endpoint" not in preview, f"got {preview.get('endpoint')!r}")
    check("KL MCP: place:false leaves project and package unchanged",
          project() == before and package_before == {
              name: read(os.path.join(folder, name)) for name in os.listdir(folder)},
          "project or bytes changed")
    qualified = ("cleanup was deferred because no API key is set. Its deletion ID is "
                 "retained in the project; a later run with a key for the originating "
                 "account and region will retry deletion only if that ID is safe to send.")
    note = preview.get("note", "")
    check("KL MCP: success note names all deferred IDs with the safe-ID qualification",
          all(f"media {i}; {qualified}" in note for i in (seed["media"], 90, 91)),
          f"note={note!r}")
    placed = op("transcribe", engine="assemblyai", place=True)
    after = project()
    texts = [clip for clip in after["clips"] if clip["source"]["kind"] == "text"]
    check("KL MCP: place:true lays out the cached cues into text clips",
          placed.get("cues") == seed["cues"] and len(texts) > 0,
          f"placed={placed!r}, clips={texts!r}")
    op("undo")
    check("KL MCP: one undo removes the whole caption placement", project() == before)
    op("redo")
    check("KL MCP: redo restores the exact caption placement", project() == after)
    check("KL MCP: neither operation made any HTTP request of any method",
          len(fake.log()["requests"]) == count and package_before == {
              name: read(os.path.join(folder, name)) for name in os.listdir(folder)},
          f"routes={routes(fake.log())[count:]!r}")

    # A mixed request is refused as a whole after normal target/jobs checks.
    speech, second = fixtures()
    extra = op("import_media", path=second)["media"]
    track = project()["tracks"][0]["id"]
    op("add_clip", track=track, media=extra, at=8 * SEC)
    mixed_before = project()
    try:
        op("transcribe", engine="assemblyai", place=False)
        failure = None
    except ToolError as problem:
        failure = str(problem)
    check("KL MCP: mixed cached/uncached batch refuses without partial result",
          failure is not None and "No AssemblyAI API key is set" in failure
          and project() == mixed_before and len(fake.log()["requests"]) == count,
          f"failure={failure!r}, routes={routes(fake.log())[count:]!r}")
    check("KL MCP: failure also discloses unrelated and unsafe deferred IDs",
          failure is not None and all(f"media {i}; {qualified}" in failure
                                      for i in (seed["media"], 90, 91)),
          f"failure={failure!r}")


# --------------------------------------------------------------------------
# Row 2 — ONE upload per media, and what is in it


def decode_flac(probe, path, tag):
    """The FLAC's samples through `AVAudioFile`, the decoder that is always
    on this host."""
    out = os.path.join(fresh("decode-" + tag), "raw.pcm")
    answer, error, _ = run_probe(probe, "decode-" + tag,
                                 {"mode": "extract", "op": "decode", "input": path, "out": out})
    if answer is None or not answer.get("ok"):
        return None, error or str(answer)
    return read(out), None


def decode_ffmpeg(path):
    if not shutil.which("ffmpeg"):
        return None
    run = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "s16le", "-ac", "1",
                          "-ar", "16000", "-"], capture_output=True, env=child_env(),
                         timeout=300, stdin=subprocess.DEVNULL)
    return run.stdout if run.returncode == 0 else None


def extract_wav(probe, media, tag):
    """The WAV the ON-DEVICE engine would have written for the whole file."""
    out = os.path.join(fresh("wav-" + tag), "whole.wav")
    answer, error, _ = run_probe(probe, "wav-" + tag,
                                 {"mode": "extract", "op": "whole", "media": media,
                                  "name": "speech", "out": out})
    if answer is None or "frames" not in answer:
        return None, error or str(answer)
    body, _ = wav_samples(out)
    return body, None


def row_two(instance, fake, probe):
    print("\n2. one media, one upload — a FLAC holding the audio the on-device WAV holds")
    scenario(fake, polls_before_complete=2)
    speech, _ = fixtures()
    session = Session(instance, "row2")
    media = session.media_of(speech)
    session.add(media, at=0, duration=3 * SEC)
    session.add(media, at=4 * SEC, duration=3 * SEC)

    answer = session.op("transcribe", engine="assemblyai", place=False)
    log = fake.log()
    check("2: a two-clip project over ONE media uploads exactly once",
          len(uploads(log)) == 1, f"got {routes(log)!r}")
    check("2: and reports that media under `uploaded`, with `cached` empty",
          answer.get("uploaded") == [media] and answer.get("cached") == [],
          f"got uploaded={answer.get('uploaded')!r} cached={answer.get('cached')!r}")
    check("2: the engine is named in the result",
          answer.get("engine") == "assemblyai", f"got {answer.get('engine')!r}")
    check("2: and `endpoint` is the host alone, no scheme or port (#94)",
          answer.get("endpoint") == "127.0.0.1", f"got {answer.get('endpoint')!r}")
    carried = uploads(log)[0]["headers"].get("authorization") if uploads(log) else None
    check("2: the upload carried the dummy key in its authorization header and nothing else",
          carried == DUMMY, f"got {carried!r}")
    body = submits(log)[0]["json"] if submits(log) else {}
    check("2: the submission names BOTH models in AssemblyAI's documented order",
          body.get("speech_models") == ["universal-3-5-pro", "universal-2"],
          f"got {body.get('speech_models')!r}")
    check("2: under the default language there is no `language_code` at all — that is what "
          "turns detection on", "language_code" not in body, f"got {sorted(body)!r}")
    check("2: `speaker_labels` is false and `keyterms_prompt` is absent when nothing asked "
          "for either",
          body.get("speaker_labels") is False and "keyterms_prompt" not in body,
          f"got {sorted(body)!r}")
    polls = [r for r in log["requests"]
             if r["method"] == "GET" and r["path"].startswith("/v2/transcript/")]
    check("2: the transcript was polled until it completed — 2 `processing` answers then one "
          "`completed`", len(polls) == 3, f"got {len(polls)} polls")
    served = polls[0]["path"].rsplit("/", 1)[1] if polls else "<none>"
    check("2: and exactly one DELETE, of the id the fake served",
          [r["path"].rsplit("/", 1)[1] for r in deletes(log)] == [served],
          f"got {[r['path'] for r in deletes(log)]!r}, served {served!r}")
    check("2: the language detected under `auto` comes back with its confidence",
          any(row["media"] == media and row["code"] == "en_us"
              for row in answer.get("language_detected", [])),
          f"got {answer.get('language_detected')!r}")

    named = session.op("transcribe", engine="assemblyai", language="en", refresh=True,
                       place=False)
    body = submits(fake.log())[-1]["json"]
    check("2: a named language is passed through as `language_code`",
          body.get("language_code") == "en", f"got {body.get('language_code')!r}")
    check("2: and the result reports the code that was SENT, not `auto`",
          named.get("language") == "en", f"got {named.get('language')!r}")
    check("2: a named language reports no `language_detected` — nothing was detected",
          "language_detected" not in named, f"got {named.get('language_detected')!r}")

    # --- the bodies, as a POPULATION, over the `say` fixture.
    #
    # NOT over `media/speech.mov`, and that is a MEASUREMENT rather than a
    # preference: its AAC track decodes to a different byte string on very
    # nearly every decode (the row below prints this run's numbers), where the
    # `say` AIFF is the two-string population `archive/reelcut-remaining.md`
    # §5 measured. A byte claim over the .mov would be a coin toss; over the
    # AIFF it is the claim road map 6 §5i·2 means.
    _, aiff = fixtures()
    if aiff is None:
        skip_rows(4, "`say` is not on this host, so row 2's byte population has no fixture "
                     "whose extract this host is known to repeat")
        return
    movs = []
    for index in range(3):
        body, error = extract_wav(probe, speech, f"mov{index}")
        if body is not None:
            movs.append(body)
    spread = population(movs)
    check(f"2: MEASURED, and the reason the population below uses the `say` fixture: three "
          f"extracts of media/speech.mov are {spread['distinct']} distinct byte strings of "
          f"one length {spread['lengths']}, spans {spread['spans']} — an AAC decode this "
          f"host does not repeat",
          len(spread["lengths"]) == 1, f"got {spread!r}")

    session = Session(instance, "row2-bytes")
    quiet = session.media_of(aiff)
    session.add(quiet, at=0, duration=3 * SEC)
    mark = len(uploads(fake.log()))
    for _ in range(3):
        session.op("transcribe", engine="assemblyai", refresh=True, place=False)
    bodies = [row["file"] for row in uploads(fake.log())[mark:] if row.get("file")]
    check(f"2: every upload's body is on disk at the fake ({len(bodies)} of them)",
          len(bodies) == 3, f"got {len(bodies)}")
    sent = []
    decoders = []
    for index, path in enumerate(bodies):
        check(f"2: upload {index + 1} is a FLAC stream", read(path)[:4] == b"fLaC",
              f"got {read(path)[:4]!r}")
        samples, error = decode_flac(probe, path, f"{index}")
        if samples is None:
            check(f"2: upload {index + 1} decodes through AVAudioFile", False, error)
            continue
        decoders.append("AVAudioFile")
        sent.append(samples)
        other = decode_ffmpeg(path)
        if other is not None:
            decoders.append("ffmpeg")
            sent.append(other)
    if not shutil.which("ffmpeg"):
        skip_rows(1, "ffmpeg is not on this host, so row 2's SECOND decoder did not run")

    wav = []
    for index in range(3):
        body, error = extract_wav(probe, aiff, f"{index}")
        if body is None:
            check(f"2: the on-device WAV, extract {index + 1}", False, error)
            continue
        wav.append(body)
    verdict = population(sent + wav)
    check(f"2: every decode of every upload and every on-device WAV is ONE length "
          f"({verdict['lengths']}) — decoders that answered: {sorted(set(decoders))}",
          len(verdict["lengths"]) == 1, f"got {verdict['lengths']!r}")
    check(f"2: and they are drawn from ONE population of at most two byte strings differing "
          f"in a single 16-bit sample — this host's measured flip "
          f"({verdict['distinct']} distinct, offsets {verdict['offsets']})",
          verdict["distinct"] <= 2 and all(n <= 2 for n in verdict["spans"]),
          f"{verdict['distinct']} distinct, spans {verdict['spans']!r}")
    if sent:
        broken = bytearray(sent[0])
        for at in range(0, min(len(broken), 2000), 2):
            broken[at] ^= 0x5A
        control = population(sent + wav + [bytes(broken)])
        check("2: CONTROL — one altered decode in the same population is SEEN: the row above "
              "is not true of any two byte strings",
              control["distinct"] == verdict["distinct"] + 1
              and max(control["spans"]) > 2,
              f"got {control['distinct']} distinct, spans {control['spans']!r}")


# --------------------------------------------------------------------------
# Row 3 — the oracle


TICKS_PER_MS = 600


def mapped(clip, words):
    """Road map 6 §5b's mapping, in Python, from `get_project`'s own numbers.

    A word is this clip's when `in ≤ start × 600 < in + duration × speed`,
    and it lands at `start + (m − in) / speed`, both ends clamped into the
    clip — R6-10's bound is not reachable here (every speed a proof writes is
    one the ops wrote), and `cloud_captions_probe.py`'s `jobs` section is
    where the bound itself is measured."""
    speed = float(clip.get("speed", 1) or 1)
    source_in = int(clip.get("source", {}).get("in", 0))
    length = max(1, round(clip["duration"] * speed))
    limit = clip["start"] + clip["duration"]
    out = []
    for one in words:
        m = one["start"] * TICKS_PER_MS
        if not source_in <= m < source_in + length:
            continue

        def place(ms):
            offset = (ms * TICKS_PER_MS - source_in) / speed
            return min(max(clip["start"] + int(offset + 0.5), clip["start"]), limit)

        out.append(word(one["text"], place(one["start"]),
                        place(max(one["start"], one["end"])), one.get("speaker")))
    return out


def row_log(instance, fake):
    """#116: the client's log lines reach the instance's REDIRECTED log as
    they are written — `print` was block-buffered there, so the log was a
    lower bound on the requests."""
    print("\nLOG. every request the client made is in the instance's log, in order")
    scenario(fake)
    speech, _ = fixtures()
    session = Session(instance, "log")
    media = session.media_of(speech)
    session.add(media, at=0, duration=3 * SEC)
    mark = len(read(instance.log))
    session.op("transcribe", engine="assemblyai", place=False)
    text = read(instance.log)[mark:].decode("utf-8", "replace")
    logged = [f"{found.group(1)} {found.group(2)}" for found in (
        re.match(r"^AssemblyAI: (GET|POST|DELETE) (\S+) → ", line)
        for line in text.splitlines()) if found]
    served = routes(fake.log())
    check("LOG: CONTROL — the fake saw an upload, a submit, a poll and a DELETE",
          "POST /v2/upload" in served and "POST /v2/transcript" in served
          and any(r.startswith("GET /v2/transcript/") for r in served)
          and any(r.startswith("DELETE /v2/transcript/") for r in served),
          f"got {served!r}")
    check("LOG: the instance's log names every one of those requests, in the fake's order, "
          "as soon as the call answers",
          logged == served, f"logged {logged!r}, served {served!r}")


def row_three(instance, fake, harness):
    print("\n3. the placed cues against an ORACLE computed in Python")
    if harness is None:
        skip_rows(4, "the harness would not build, so row 3 has no line-breaker to ask")
        return
    scenario(fake)
    speech, _ = fixtures()
    session = Session(instance, "row3")
    media = session.media_of(speech)
    first = session.add(media, at=0, duration=3 * SEC)
    second = session.add(media, at=4 * SEC, duration=4 * SEC)
    session.op("slip", clip=second, delta=3 * SEC)

    answer = session.op("transcribe", engine="assemblyai", place=True)
    project = session.project()
    clips = {c["id"]: c for c in project["clips"]}
    fps = tuple(project["canvas"]["fps"])

    want = []
    for clip in (first, second):
        words = mapped(clips[clip], WORDS)
        if not words:
            continue
        cues, error, _ = run_cues(harness, f"clip{clip}", words, fps=fps)
        if cues is None:
            check(f"3: the harness broke clip {clip}'s words into cues", False, error)
            return
        want += [{"start": c["start"], "end": c["end"], "text": c["text"]} for c in cues["cues"]]
    got = [{"start": c["start"], "end": c["end"], "text": c["text"]}
           for c in answer.get("cues", [])]
    check(f"3: every cue the run placed is at the tick Python computed, word for word "
          f"({len(want)} cues)", got == want,
          f"got {got!r}\n       want {want!r}")
    check("3: the run says which clips it read", answer.get("clips_read") == [first, second],
          f"got {answer.get('clips_read')!r}")

    placed = sorted((c["start"], c["duration"]) for c in project["clips"]
                    if c["source"]["kind"] == "text")
    frame = max(1, round(600_000 * fps[1] / fps[0]))
    check(f"3: and they are on the timeline as text clips, ONE PER CUE ({len(placed)})",
          len(placed) == len(want), f"got {placed!r}\n       want {len(want)} cues")
    check("3: each at its cue's own start, snapped to the frame grid (CaptionLayout.place's "
          "one adjustment)",
          all(abs(got_one[0] - want_one["start"]) < frame
              for got_one, want_one in zip(placed, sorted(want, key=lambda c: c["start"]))),
          f"got {placed!r}\n       want {[c['start'] for c in want]!r}, frame {frame}")


# --------------------------------------------------------------------------
# Row 4 — the cache file and its marker


def cache_path(session, media, marker=False):
    name = f"{media}.complete.json" if marker else f"{media}.json"
    return os.path.join(session.path, "cache", "transcripts", name)


def row_four(instance, fake):
    print("\n4. the cache file: the served words byte for byte, the marker, the delete")
    scenario(fake)
    speech, _ = fixtures()
    session = Session(instance, "row4")
    media = session.media_of(speech)
    session.add(media, at=0, duration=5 * SEC)
    session.op("transcribe", engine="assemblyai", place=False)
    session.save()

    path = cache_path(session, media)
    check("4: the transcript is in the package at cache/transcripts/<media>.json",
          os.path.exists(path), f"no file at {path}")
    if not os.path.exists(path):
        return
    raw = read(path)
    served = fake.words()
    at = raw.find(b'"words":')
    check("4: its `words` are BYTE-EQUAL to what the fake served — never re-serialised",
          at >= 0 and raw[at + len(b'"words":'):-1] == served,
          f"got {raw[at + 8:][:120]!r}\n       want {served[:120]!r}")
    header = json.loads(raw)
    check("4: `remote_deleted` is true — the transcript was deleted at the far end",
          header.get("remote_deleted") is True, f"got {header.get('remote_deleted')!r}")
    check("4: `audio_track_start_ms` is 0, q4's measured answer",
          header.get("audio_track_start_ms") == 0, f"got {header}")
    check("4: `uploaded_format` says what was actually sent",
          header.get("uploaded_format") == "flac", f"got {header.get('uploaded_format')!r}")
    check("4: `speech_model_used` is what the service reported",
          header.get("speech_model_used") == "universal-3-5-pro",
          f"got {header.get('speech_model_used')!r}")
    check("4: `requested` records the whole request, with `language_code` written as null "
          "rather than dropped",
          header.get("requested", {}).get("speech_models")
          == ["universal-3-5-pro", "universal-2"]
          and "language_code" in header.get("requested", {})
          and header["requested"]["language_code"] is None,
          f"got {header.get('requested')!r}")

    marker = json.loads(read(cache_path(session, media, marker=True)) or b"{}")
    entry = {m["id"]: m for m in session.project()["media"]}[media]
    stat = os.stat(speech)
    want = {
        "size": stat.st_size,
        "modified": round(stat.st_mtime),
        "duration": entry["duration"],
        "hasAudio": entry["has_audio"],
    }
    check("4: the whole four-field marker source equals independent os.stat and get_project facts",
          marker.get("source") == want,
          f"got {marker.get('source')!r}\n       want {want!r}")
    check("4: and the marker records the REQUEST beside it",
          marker.get("provider") == "assemblyai"
          and marker.get("speech_models") == ["universal-3-5-pro", "universal-2"]
          and marker.get("speaker_labels") is False
          and marker.get("keyterms_prompt") == []
          and "language_code" in marker,
          f"got {marker!r}")


def row_recovery(instance, fake):
    print("\nR6-14. lost submit reply recovered through the newest page, then cached")
    speech, _ = fixtures()
    for tag, lag, looks in (("immediate", 0, 1), ("delayed", 1, 2)):
        scenario(fake, drop_reply=[{"route": "submit", "times": 1}], list_lag=lag)
        session = Session(instance, "row-recovery-" + tag)
        media = session.media_of(speech)
        session.add(media, at=0, duration=5 * SEC)
        before = session.project()
        answer = session.op("transcribe", engine="assemblyai", place=True)
        session.save()
        after = session.project()
        log = fake.log()
        lists = [row for row in log["requests"]
                 if row["method"] == "GET" and row["path"] == "/v2/transcript?limit=200"]
        ids = [row["id"] for row in log.get("transcripts", [])]
        check(f"R6-14 {tag}: one upload, exactly one paid submit and {looks} list looks",
              len(uploads(log)) == len(submits(log)) == 1 and len(lists) == looks,
              f"routes {routes(log)!r}")
        check(f"R6-14 {tag}: the created ID alone was polled and DELETE confirmed",
              len(ids) == 1 and [row["path"] for row in deletes(log)]
              == ["/v2/transcript/" + ids[0]] and log.get("deleted") == ids
              and all(row["path"] == "/v2/transcript/" + ids[0]
                      for row in log["requests"] if row["method"] == "GET"
                      and row["path"].startswith("/v2/transcript/")),
              f"ids {ids!r}; routes {routes(log)!r}")
        before_text = sum(c["source"]["kind"] == "text" for c in before["clips"])
        after_text = sum(c["source"]["kind"] == "text" for c in after["clips"])
        check(f"R6-14 {tag}: MCP placed captions into the project",
              after_text > before_text and answer.get("engine") == "assemblyai",
              f"text clips {before_text} -> {after_text}; answer {answer!r}")
        header = json.loads(read(cache_path(session, media)) or b"{}")
        check(f"R6-14 {tag}: the package cache records that ID and its DELETE",
              bool(ids) and header.get("transcript_id") == ids[0]
              and header.get("remote_deleted") is True,
              f"cache {header!r}; ids {ids!r}")
        saved = session.project()
        cached = session.op("transcribe", engine="assemblyai", place=False)
        after_cache = session.project()
        after_log = fake.log()
        check(f"R6-14 {tag}: a second run serves the cache without a transcript request",
              cached.get("cached") == [media] and len(submits(after_log)) == 1
              and len(uploads(after_log)) == 1 and len(deletes(after_log)) == 1,
              f"cached {cached!r}; routes {routes(after_log)!r}")
        check(f"R6-14 {tag}: the cache-only run leaves the placed project unchanged",
              after_cache == saved, "project changed on a cache-only run")


# --------------------------------------------------------------------------
# Row 5 — the cache, refresh, a relink, a split, and the refusals


def row_five(instance, fake):
    print("\n5. the cache, `refresh`, a relink and back, a split pair, and the five refusals")
    speech, _ = fixtures()
    scenario(fake)
    session = Session(instance, "row5")
    media = session.media_of(speech)
    clip = session.add(media, at=0, duration=5 * SEC)

    session.op("transcribe", engine="assemblyai", place=False)
    before = len(fake.log()["requests"])
    again = session.op("transcribe", engine="assemblyai", place=False)
    check("5: a second run over the same file makes NO request at all",
          len(fake.log()["requests"]) == before, f"got {routes(fake.log())[before:]!r}")
    check("5: and reports the media under `cached`, not `uploaded`",
          again.get("cached") == [media] and again.get("uploaded") == [],
          f"got cached={again.get('cached')!r} uploaded={again.get('uploaded')!r}")
    check("5: a cached run bills nothing", again.get("audio_seconds") == 0,
          f"got {again.get('audio_seconds')!r}")

    forced = session.op("transcribe", engine="assemblyai", refresh=True, place=False)
    check("5: `refresh: true` uploads again",
          len(uploads(fake.log())) == 2 and forced.get("uploaded") == [media],
          f"got {len(uploads(fake.log()))} uploads, {forced.get('uploaded')!r}")

    # A relink points at a file of the media's own kind (spec §11 #63), and
    # `speech.mov` is a video, so the DIFFERENT file is a copy of `AV.mov` —
    # a video with sound — and not the `say` AIFF the other rows use.
    other = os.path.join(fresh("row5-relink"), "AV.mov")
    shutil.copy2(os.path.join(MEDIA, "AV.mov"), other)
    session.op("relink_media", media=media, path=other)
    relinked = session.op("transcribe", engine="assemblyai", place=False)
    check("5: a relink to a DIFFERENT file re-transcribes — the stamp is the source's",
          relinked.get("uploaded") == [media] and len(uploads(fake.log())) == 3,
          f"got {relinked.get('uploaded')!r}, {len(uploads(fake.log()))} uploads")
    session.op("relink_media", media=media, path=speech)
    back = session.op("transcribe", engine="assemblyai", place=False)
    check("5: and a relink BACK uploads again — one transcript per media, not a history",
          back.get("uploaded") == [media] and len(uploads(fake.log())) == 4,
          f"got {back.get('uploaded')!r}, {len(uploads(fake.log()))} uploads")

    # A split pair, a later `in`, and the refusals.
    whole = session.op("transcribe", engine="assemblyai", clips=[clip], place=False)
    # At 3.0 s, which is EXACTLY where the fake's fourth word starts — 2.5 s
    # put the split where no word was.
    #
    # It still does not catch a `<=` window test, and the reason is worth
    # knowing: `CloudTranscriber.transcribe` filters every mapped word by
    # `$0.start < job.start + job.duration` before it builds a cue, so a word
    # the window doubled at the boundary is dropped a second time, by a
    # second guard, before it can reach this row. Only the probe's section 12,
    # which calls `MediaTranscript.words` directly, sees below that filter.
    # The split is left on the boundary anyway, because a row that exercises
    # the tick is worth more than one that does not (§10.13, R7·2).
    session.op("split", clips=[clip], at=int(3.0 * SEC))
    halves = sorted(c["id"] for c in session.project()["clips"]
                    if c["source"]["kind"] == "media")
    parts = session.op("transcribe", engine="assemblyai", clips=halves, place=False)
    def spoken(answer):
        return " ".join(c["text"] for c in answer.get("cues", [])).split()

    check("5: a split clip's two halves partition the WORDS — none lost, none doubled "
          "(the cues themselves are broken differently, which is the line-breaker's job)",
          spoken(parts) == spoken(whole),
          f"got {spoken(parts)!r}\n       want {spoken(whole)!r}")
    check("5: and the second half's words are the LATER ones, at its own `in`",
          len(parts.get("clips_read", [])) == 2, f"got {parts.get('clips_read')!r}")

    session.op("add_track", index=1)
    track = session.project()["tracks"][-1]["id"]
    backwards = session.add(media, at=0, track=track, duration=2 * SEC)
    session.op("set_reversed", clip=backwards, reversed=True)
    silent = session.add(media, at=3 * SEC, track=track, duration=2 * SEC)
    session.op("set_enabled", clip=silent, audio=False)
    answer = session.op("transcribe", engine="assemblyai",
                        clips=[halves[0], backwards, silent], place=False)
    reasons = " ".join(answer.get("skipped", []))
    check("5: a REVERSED clip is skipped by name",
          f"clip {backwards}: it plays in reverse" in reasons, f"got {reasons!r}")
    check("5: an `enabled.audio`-off clip is skipped by name",
          f"clip {silent}: its audio is switched off" in reasons, f"got {reasons!r}")


# --------------------------------------------------------------------------
# Row 6 — the four ways it can fail


def row_six(instance, fake):
    print("\n6. a refused key, a transcript that errored, a 5xx once and a 5xx always")
    speech, second = fixtures()
    if second is None:
        skip_rows(9, "`say` is not on this host, so row 6 has no second media")
        return

    # --- 401 over TWO media: exactly one upload, and no cache written.
    session = Session(instance, "row6-401")
    one = session.media_of(speech)
    two = session.media_of(second)
    session.add(one, at=0, duration=3 * SEC)
    session.add(two, at=4 * SEC, duration=3 * SEC)
    scenario(fake, fail=[{"route": "upload", "status": 401, "times": -1}])
    text = session.error("transcribe", engine="assemblyai", place=False)
    check("6: a refused key fails the run with the key sentence",
          text is not None and "AssemblyAI refused the API key" in text, f"got {text!r}")
    check("6: and it ends the run AT ONCE — one upload attempted, not one per media",
          len(uploads(fake.log())) == 1, f"got {routes(fake.log())!r}")
    session.save()
    check("6: no cache file was written for either media",
          not os.path.exists(cache_path(session, one))
          and not os.path.exists(cache_path(session, two)),
          "a transcript survived a refused key")

    # --- a transcript that ends in `error`, for the FIRST media only.
    session = Session(instance, "row6-error")
    one = session.media_of(speech)
    two = session.media_of(second)
    session.add(one, at=0, duration=3 * SEC)
    session.add(two, at=4 * SEC, duration=3 * SEC)
    scenario(fake, transcript_error="The audio could not be transcribed.",
             transcript_error_first=1)
    answer = session.op("transcribe", engine="assemblyai", place=False)
    check("6: the media whose transcript errored is reported with the served sentence, "
          "VERBATIM",
          any("The audio could not be transcribed." in row
              for row in answer.get("skipped", [])),
          f"got {answer.get('skipped')!r}")
    check("6: and the OTHER media's cues still landed — one media's failure is one media's",
          answer.get("uploaded") == [two] and answer.get("cues"),
          f"got uploaded={answer.get('uploaded')!r}, {len(answer.get('cues', []))} cues")
    session.save()
    check("6: the errored media has neither a transcript nor a marker",
          not os.path.exists(cache_path(session, one))
          and not os.path.exists(cache_path(session, one, marker=True)),
          "a failed transcript was cached")

    # --- a 5xx once: retried, and it succeeds.
    session = Session(instance, "row6-500once")
    one = session.media_of(speech)
    session.add(one, at=0, duration=3 * SEC)
    scenario(fake, fail=[{"route": "upload", "status": 500, "times": 1}])
    try:
        answer = session.op("transcribe", engine="assemblyai", place=False)
    except ToolError as problem:
        # A build with no retry fails here; the row says so rather than
        # ending the run, because a mutant's SCORE is the measurement.
        transcript_of_the_run.append(str(problem))
        answer = {"failed": str(problem)}
    check("6: a 5xx on the upload is retried once — TWO uploads in the log — and succeeds",
          len(uploads(fake.log())) == 2 and answer.get("uploaded") == [one],
          f"got {len(uploads(fake.log()))} uploads, {answer!r}")

    # --- a 5xx always: the retry runs out.
    session = Session(instance, "row6-500always")
    one = session.media_of(speech)
    session.add(one, at=0, duration=3 * SEC)
    scenario(fake, fail=[{"route": "upload", "status": 500, "times": -1}])
    text = session.error("transcribe", engine="assemblyai", place=False)
    check("6: a 5xx that never clears fails the media with the server's code",
          text is not None and "AssemblyAI answered 500" in text, f"got {text!r}")
    check("6: after exactly the one retry the shipped `uploadRetries` allows",
          len(uploads(fake.log())) == 2, f"got {len(uploads(fake.log()))} uploads")


# --------------------------------------------------------------------------
# Row 7 — speakers, vocabulary, and the readers at their extremes


def row_seven(instance, fake):
    print("\n7. `speakers`, `vocabulary`, and every new reader at its extremes")
    speech, _ = fixtures()
    session = Session(instance, "row7")
    media = session.media_of(speech)
    session.add(media, at=0, duration=5 * SEC)

    spoken = [dict(one, speaker="A" if one["start"] < 1700 else "B") for one in WORDS]
    scenario(fake, words=spoken)
    answer = session.op("transcribe", engine="assemblyai", speakers=True, place=False)
    body = submits(fake.log())[-1]["json"]
    check("7: `speakers: true` sends `speaker_labels: true`",
          body.get("speaker_labels") is True, f"got {body!r}")
    texts = [c["text"] for c in answer.get("cues", [])]
    check("7: and a served speaker change BREAKS the cue where the fifth rule says",
          any(t.startswith("Hello there") for t in texts)
          and any(t.startswith("everyone") for t in texts),
          f"got {texts!r}")

    scenario(fake)
    session.op("transcribe", engine="assemblyai", refresh=True,
               vocabulary=["  Reelcut ", "acme", "Reelcut", "", "   "], place=False)
    body = submits(fake.log())[-1]["json"]
    check("7: `vocabulary` arrives trimmed, empties dropped, de-duplicated keeping the FIRST",
          body.get("keyterms_prompt") == ["Reelcut", "acme"],
          f"got {body.get('keyterms_prompt')!r}")

    session.op("transcribe", engine="assemblyai", refresh=True, vocabulary=[], place=False)
    body = submits(fake.log())[-1]["json"]
    check("7: an EMPTY vocabulary sends no `keyterms_prompt` at all",
          "keyterms_prompt" not in body, f"got {sorted(body)!r}")

    many = [f"term-{n}" for n in range(1000)] + ["term-0", "  term-1  "] + ["tail-a", "tail-b",
                                                                           "tail-c"]
    answer = session.op("transcribe", engine="assemblyai", refresh=True, vocabulary=many,
                        place=False)
    body = submits(fake.log())[-1]["json"]
    check(f"7: {len(many)} terms with duplicates and padding become exactly 1000 sent",
          len(body.get("keyterms_prompt", [])) == 1000,
          f"got {len(body.get('keyterms_prompt', []))}")
    check("7: and the cap is NAMED in the note, with how many were given",
          "vocabulary was capped at 1000 terms (AssemblyAI's limit); "
          f"{len(many)} were given." in str(answer.get("note", "")),
          f"got {answer.get('note')!r}")

    for name, value, must in (
        ("vocabulary", [1], "vocabulary must contain strings only."),
        ("vocabulary", {}, "vocabulary must be an array of strings."),
        ("engine", 7, "engine must be"),
        ("speakers", "maybe", "speakers"),
        ("refresh", [], "refresh"),
        ("language", "   ", "language cannot be empty"),
    ):
        text = session.error("transcribe", **{"engine": "assemblyai", name: value})
        check(f"7: {name}={value!r} is refused BY NAME rather than dropped",
              text is not None and must in text, f"got {text!r}")


# --------------------------------------------------------------------------
# Rows 8, 9, 10


def row_eight(instance, fake):
    print("\n8. `transcribe` with no `engine` never reaches the network")
    scenario(fake)
    speech, _ = fixtures()
    session = Session(instance, "row8")
    media = session.media_of(speech)
    session.add(media, at=0, duration=3 * SEC)
    text = session.error("transcribe", place=False)
    # Since road map 8's W2 the on-device engine asks for no grant, so it
    # RUNS here: success, or its own model or no-speech sentence.
    check("8: the default engine is the ON-DEVICE one — the call is answered by the "
          "on-device engine or its model, never by AssemblyAI",
          text is None or "not installed" in text or "ON-DEVICE" in text
          or "No speech was recognised" in text,
          f"got {text!r}")
    check("8: and the fake's log is EMPTY", fake.log()["requests"] == [],
          f"got {routes(fake.log())!r}")


def row_nine(instance, fake):
    print("\n9. `truncated` is never present for the cloud engine")
    scenario(fake)
    speech, _ = fixtures()
    session = Session(instance, "row9")
    media = session.media_of(speech)
    session.add(media, at=0, duration=5 * SEC)
    answers = [session.op("transcribe", engine="assemblyai", place=False),
               session.op("transcribe", engine="assemblyai", place=True),
               session.op("transcribe", engine="assemblyai", refresh=True, place=False)]
    check("9: no cloud result carries `truncated` — there is no ceiling to report",
          all("truncated" not in answer for answer in answers),
          f"got {[sorted(a) for a in answers]!r}")
    check("9: and every one of them names the engine that ran",
          all(answer.get("engine") == "assemblyai" for answer in answers),
          f"got {[a.get('engine') for a in answers]!r}")


def row_ten(instance):
    print("\n10. plain HTTP to loopback with no App Transport Security key anywhere")
    yaml = read(os.path.join(ROOT, "project.yml")).decode()
    check("10: `project.yml` carries no NSAppTransportSecurity key at all — C0's q3 measured "
          "that it needs none", "NSAppTransportSecurity" not in yaml,
          "project.yml names it")
    plist = os.path.join(os.path.dirname(os.path.dirname(instance_binary)), "Info.plist")
    text = subprocess.run(["plutil", "-convert", "json", "-o", "-", plist],
                          capture_output=True, text=True, env=child_env(), timeout=60).stdout
    check("10: and neither does the BUILT Info.plist",
          "NSAppTransportSecurity" not in text and "CFBundleName" in text,
          f"got {text[:200]!r}")
    check("10: and the app reached the loopback fake over plain HTTP anyway — every upload "
          "above is the evidence", instance.fake.log()["requests"] != [],
          "the fake was never reached at all")


# --------------------------------------------------------------------------
# Row 11 — the janitor, and R6-11's hold


def row_eleven(instance, fake):
    print("\n11. a failed DELETE is retried FIRST by the next run, and R6-11's HOLD")
    speech, _ = fixtures()
    session = Session(instance, "row11")
    media = session.media_of(speech)
    session.add(media, at=0, duration=3 * SEC)

    scenario(fake, fail=[{"route": "delete", "status": 500, "times": 1}])
    answer = session.op("transcribe", engine="assemblyai", place=False)
    session.save()
    header = json.loads(read(cache_path(session, media)) or b"{}")
    check("11: a DELETE that answered 500 leaves `remote_deleted` FALSE in the cache file",
          header.get("remote_deleted") is False, f"got {header.get('remote_deleted')!r}")
    check("11: and the result says so in its note",
          f"AssemblyAI has not confirmed deleting the transcript of media {media}; it will "
          "be retried at the next run with an API key." in str(answer.get("note", "")),
          f"got {answer.get('note')!r}")
    owed = header.get("transcript_id")

    mark = len(fake.log()["requests"])
    session.op("transcribe", engine="assemblyai", place=False)
    after = fake.log()["requests"][mark:]
    check("11: the next run's FIRST request is that DELETE, before anything else",
          after and after[0]["method"] == "DELETE"
          and after[0]["path"].endswith("/" + str(owed)),
          f"got {[r['method'] + ' ' + r['path'] for r in after][:4]!r}, owed {owed!r}")
    check("11: and with the delete confirmed, nothing was uploaded — the cache was current",
          not [r for r in after if r["path"] == "/v2/upload"],
          f"got {[r['path'] for r in after]!r}")
    session.save()
    header = json.loads(read(cache_path(session, media)) or b"{}")
    check("11: the janitor's success rewrote the one flag and nothing else",
          header.get("remote_deleted") is True and header.get("transcript_id") == owed,
          f"got {header.get('remote_deleted')!r} / {header.get('transcript_id')!r}")

    # --- R6-11's HOLD, on a document of its own.
    session = Session(instance, "row11-hold")
    media = session.media_of(speech)
    clip = session.add(media, at=0, duration=3 * SEC)
    # TWO delete failures and no more, set ONCE and never reset: the fake's
    # control endpoint replaces the scenario WHOLE and forgets every
    # transcript with it, so "clear the failure" has to be spelled as a
    # failure that runs out — run 1's delete, run 2's janitor, and then run
    # 3's janitor succeeds against the id the fake still remembers.
    scenario(fake, fail=[{"route": "delete", "status": 500, "times": 2}])
    session.op("transcribe", engine="assemblyai", clips=[clip], place=False)
    session.save()
    first = read(cache_path(session, media))
    header = json.loads(first or b"{}")
    check("11 (hold): run 1 uploaded and could not confirm the delete",
          header.get("remote_deleted") is False, f"got {header.get('remote_deleted')!r}")
    owed = header.get("transcript_id")
    digest = hashlib.sha256(first).hexdigest()

    mark = len(fake.log()["requests"])
    text = session.error("transcribe", engine="assemblyai", clips=[clip], refresh=True,
                         place=False)
    after = fake.log()["requests"][mark:]
    check("11 (hold): run 2 under `refresh` is REFUSED with R6-11's own sentence",
          text is not None
          and "AssemblyAI has not confirmed deleting its earlier transcript, so it was not "
              "uploaded again; the next run with an API key retries the delete" in text,
          f"got {text!r}")
    check("11 (hold): and it made EXACTLY one request — that DELETE. No upload, no submit.",
          [f"{r['method']} {r['path']}" for r in after] == [f"DELETE /v2/transcript/{owed}"],
          f"got {[r['method'] + ' ' + r['path'] for r in after]!r}")
    session.save()
    held = read(cache_path(session, media))
    check("11 (hold): the cache file is untouched — same sha256, same transcript id",
          hashlib.sha256(held).hexdigest() == digest
          and json.loads(held or b"{}").get("transcript_id") == owed,
          "the file that holds the id we still owe a DELETE was overwritten")

    mark = len(fake.log()["requests"])
    session.op("transcribe", engine="assemblyai", clips=[clip], refresh=True, place=False)
    after = fake.log()["requests"][mark:]
    check("11 (hold): with the delete failures spent, run 3's first request is the DELETE of "
          "run 1's id, and THEN an upload",
          len(after) >= 2 and after[0]["method"] == "DELETE"
          and after[0]["path"].endswith("/" + str(owed))
          and after[1]["path"] == "/v2/upload",
          f"got {[r['method'] + ' ' + r['path'] for r in after][:4]!r}")
    session.save()
    fresh_header = json.loads(read(cache_path(session, media)) or b"{}")
    check("11 (hold): and the file now holds a NEW transcript id — the hold released",
          fresh_header.get("transcript_id") not in (None, owed)
          and fresh_header.get("remote_deleted") is True,
          f"got {fresh_header.get('transcript_id')!r} / "
          f"{fresh_header.get('remote_deleted')!r}, run 1's {owed!r}")


# --------------------------------------------------------------------------
# H, T


def row_h(instance, fake):
    print("\nH. a media over AssemblyAI's ten-hour limit, refused before a byte is extracted")
    speech, _ = fixtures()
    session = Session(instance, "rowH")
    media = session.media_of(speech)
    session.add(media, at=0, duration=3 * SEC)
    session.save()
    # The duration is rewritten in the SAVED package and the package reopened,
    # because no op can make a media longer than its file.
    path = os.path.join(session.path, "project.json")
    text = read(path).decode()
    found = re.search(r'"duration"\s*:\s*(\d+)', text)
    check("H: the saved project names the media's duration once, where it can be rewritten",
          found is not None, "no duration in the saved project.json")
    if found is None:
        return
    with open(path, "w") as handle:
        handle.write(text[:found.start(1)] + str(40_000 * SEC) + text[found.end(1):])
    copy = pair_copy(session.path, "rowH-long")
    scenario(fake)
    before = temp_uploads()
    opened = instance.mcp.call("open_project", path=copy)
    check("H: the rewritten package opens", opened.get("ok") is not False, f"got {opened!r}")
    try:
        instance.mcp.call("transcribe", project=copy, engine="assemblyai", place=False)
        answer = None
    except ToolError as problem:
        answer = str(problem)
        transcript_of_the_run.append(answer)
    check("H: a media longer than ten hours is refused BY NAME, with the limit in the "
          "sentence",
          answer is not None
          and "is longer than AssemblyAI's 10-hour limit for one file." in answer,
          f"got {answer!r}")
    check("H: and nothing was sent to find that out",
          fake.log()["requests"] == [], f"got {routes(fake.log())!r}")
    check("H: and nothing was extracted either — the refusal is above the extractor",
          temp_uploads() == before, f"before {before!r}, after {temp_uploads()!r}")


def temp_folders():
    """Both spellings of a temporary directory an app of ours could use: this
    process's own, and the per-user Darwin one the launched app gets.

    De-duplicated by REAL path, because on this host they are the same folder
    under two names and a caller that globbed both counted every file twice
    (the reader review, road map 6 \u00a710.13, R7\u00b71)."""
    folders = {tempfile.gettempdir()}
    try:
        answer = subprocess.run(["getconf", "DARWIN_USER_TEMP_DIR"], capture_output=True,
                                text=True, env=child_env(), timeout=30).stdout.strip()
        if answer:
            folders.add(answer)
    except (OSError, subprocess.SubprocessError):
        pass
    return sorted({os.path.realpath(one) for one in folders})


def temp_uploads():
    """Every `reelcut-upload-*` in either temporary folder, each named ONCE.

    The set is what makes row T's CONTROL mean anything: it compares this
    answer taken during a run with the same answer taken before it, and a
    doubled `before` made the row fail whenever the folder held so much as one
    leftover from an earlier run (R7\u00b71)."""
    found = set()
    for folder in temp_folders():
        found.update(glob.glob(os.path.join(folder, "reelcut-upload-*")))
    return sorted(found)


class Watcher(threading.Thread):
    """Globs for `reelcut-upload-*` while a run is in flight. Bounded by the
    run it watches: `stop()` is called in a `finally` (rule H)."""

    def __init__(self):
        super().__init__(daemon=True)
        self.seen = set()
        self.running = True

    def run(self):
        while self.running:
            self.seen.update(temp_uploads())
            time.sleep(0.05)

    def stop(self):
        self.running = False
        self.join(timeout=5)
        return sorted(self.seen)


def row_t(instance, fake):
    print("\nT. no extract survives a cancelled, a failed or a refused run")
    speech, _ = fixtures()
    session = Session(instance, "rowT")
    media = session.media_of(speech)
    session.add(media, at=0, duration=3 * SEC)

    # The CONTROL: a slow upload, watched while the body is going out.
    scenario(fake, slow_upload={"chunk": 4096, "delay_ms": 30})
    before = temp_uploads()
    watcher = Watcher()
    watcher.start()
    try:
        session.op("transcribe", engine="assemblyai", place=False)
    except ToolError as problem:
        transcript_of_the_run.append(str(problem))
    finally:
        during = watcher.stop()
    check("T: CONTROL — an extract IS on disk while the body is going out, so the rows "
          "below are claims about a file that existed",
          set(during) - set(before), f"during {during!r}, before {before!r}")
    check("T: and it is gone once the run has ended",
          temp_uploads() == before, f"got {temp_uploads()!r}, before {before!r}")

    for tag, given, expect in (
        ("error", {"transcript_error": "AssemblyAI could not transcribe it"},
         "AssemblyAI could not transcribe it"),
        ("401", {"fail": [{"route": "upload", "status": 401, "times": -1}]},
         "AssemblyAI refused the API key"),
        ("500", {"fail": [{"route": "upload", "status": 500, "times": -1}]},
         "AssemblyAI answered 500"),
    ):
        scenario(fake, **given)
        before = temp_uploads()
        text = session.error("transcribe", engine="assemblyai", refresh=True, place=False)
        check(f"T: the {tag} run failed, as the row needs it to",
              text is not None and expect in text, f"got {text!r}")
        check(f"T: and left NO reelcut-upload-* behind — the `defer` covers it",
              temp_uploads() == before, f"got {temp_uploads()!r}, before {before!r}")


# --------------------------------------------------------------------------
# K and X — the credential, and this host's own name


def row_b(instance, fake):
    """The reader review's R5\u00b72 — a run that throws AFTER a bill says so.

    `cloudFields` is never reached on a throwing path, so `uploaded` and
    `audio_seconds` are not in the answer at all. A project whose only media
    held no speech billed AssemblyAI for the whole file and then answered a
    bare "No speech was recognised", with nothing about the money."""
    print("\nB. a failed run names what it already cost (the reader review, R5\u00b72)")
    speech, _ = fixtures()
    # `words: []` IS an array and means zero words, so the media is uploaded,
    # answered and BILLED, and the run then throws `nothingRecognized`.
    scenario(fake, words=[])
    session = Session(instance, "rowB")
    session.add(session.media_of(speech), at=0)
    session.save()
    answer = session.error("transcribe", engine="assemblyai", place=False)
    check("B: the run still ends in its own sentence about the AUDIO",
          answer is not None
          and "No speech was recognised in the audio that was transcribed." in answer,
          f"got {answer!r}")
    check("B: and the refusal names the bill it already ran up",
          answer is not None
          and "AssemblyAI had already been billed for 1 media file" in answer
          and "audio seconds) before this failed." in answer,
          f"got {answer!r}")
    check("B: CONTROL \u2014 there really was an upload behind that sentence",
          len(uploads(fake.log())) == 1, f"got {routes(fake.log())!r}")
    # And the CONTROL that says it is not printed when nothing was spent: a
    # misspelt engine is refused above the network.
    nothing = session.error("transcribe", engine="nope")
    check("B: CONTROL \u2014 a refusal that cost nothing carries no bill sentence",
          nothing is not None and "already been billed" not in nothing, f"got {nothing!r}")

    # The branch the sentence must ALSO be true on (the reader review's fix
    # pass, and issue #29): the cache write cannot land, so the media is
    # billed and in `report.uploaded` while NOTHING is cached. The write is
    # stopped exactly the way row M stops it \u2014 `UF_IMMUTABLE` on the cache
    # file, the folder left writable.
    alpha = [{"text": "alpha", "start": 600, "end": 900, "confidence": 0.9, "speaker": None}]
    scenario(fake, words=alpha)
    held = Session(instance, "rowB2")
    media = held.media_of(speech)
    held.add(media, at=0)
    held.save()
    held.op("transcribe", engine="assemblyai", place=False)
    target = os.path.join(held.path, "cache", "transcripts", f"{media}.json")
    check("B: CONTROL \u2014 run 1 cached that media, so there is a file to make unwritable",
          os.path.exists(target), f"no {target!r}")
    if not os.path.exists(target):
        return
    first = json.loads(read(target).decode())
    os.chflags(target, stat.UF_IMMUTABLE)
    try:
        # A DIFFERENT request, so run 2 re-fetches rather than serving the
        # cache, and `words: []` is what makes it throw after the bill.
        scenario(fake, words=[])
        second = held.error("transcribe", engine="assemblyai", place=False, speakers=True)
        check("B: a run whose cache write could not land still names the bill",
              second is not None
              and "AssemblyAI had already been billed for 1 media file" in second,
              f"got {second!r}")
        check("B: and promises NOTHING about a cache that was never written \u2014 the "
              "sentence is true on THIS branch too",
              second is not None
              and "cached in the project" not in second
              and "makes no request for them" not in second,
              f"got {second!r}")
        check("B: CONTROL \u2014 the immutable flag really did stop the write: the cache "
              "file still holds run 1's words",
              json.loads(read(target).decode()).get("words") == first.get("words"),
              f"got {json.loads(read(target).decode()).get('words')!r}")
    finally:
        os.chflags(target, 0)


def row_e(instance, fake):
    """The reader review's R2\u00b71 — a relayed sentence never carries the key.

    `AgentServer+CloudCaptions.swift`'s header promises "No credential is ever
    in an answer. Not in a `ToolError`, not in a `Problem`, not in the
    `note`". Three sentences ARE relayed verbatim from the server — a 402's, a
    4xx's and a transcript's `error` — and a server that echoes the
    `authorization` header it received put the key straight into an MCP
    refusal. The fake's `echo_authorization` key is what makes that branch
    reachable, with the allow-listed dummy and nothing else."""
    print("\nE. a relayed server sentence carries no credential (the reader review, R2\u00b71)")
    speech, _ = fixtures()
    session = Session(instance, "rowE")
    session.add(session.media_of(speech), at=0)
    session.save()
    for tag, given in (
            ("a 4xx at submission", {"fail": [{"route": "submit", "status": 400, "times": -1}]}),
            ("a 402 at submission", {"fail": [{"route": "submit", "status": 402, "times": -1}]}),
            ("a transcript that ended in `error`",
             {"transcript_error": f"Transcoding failed for {DUMMY}"})):
        scenario(fake, echo_authorization=True, **given)
        answer = session.error("transcribe", engine="assemblyai", place=False)
        check(f"E: {tag} is refused in band and the refusal does NOT hold the key",
              answer is not None and DUMMY not in answer, f"got {answer!r}")
        check(f"E: CONTROL \u2014 {tag} really did relay the SERVER's own sentence, with the "
              f"key replaced rather than the whole sentence dropped",
              answer is not None and "<redacted>" in answer, f"got {answer!r}")


def row_m(instance, fake):
    """The reader review's R1\u00b73 — the MARKER is written only when the cache
    file LANDED.

    `MediaTranscript.write` answers `false` for every way it can fail and
    `fetch` discarded that answer, so a run whose write failed still stamped
    the marker with the NEW request. `isCurrent` then matched the new marker
    against the OLD file and served an earlier request's words for ever.

    The write is made to fail by setting the cache file's IMMUTABLE flag: an
    `.atomic` write renames over the file, which `UF_IMMUTABLE` refuses, while
    the FOLDER stays writable so the marker's own write still succeeds — which
    is the whole point of the row."""
    print("\nM. a cache write that failed certifies nothing (the reader review, R1\u00b73)")
    speech, _ = fixtures()
    alpha = [{"text": "alpha", "start": 600, "end": 900, "confidence": 0.9, "speaker": None}]
    bravo = [{"text": "bravo", "start": 600, "end": 900, "confidence": 0.9, "speaker": None}]
    scenario(fake, words=alpha)
    session = Session(instance, "rowM")
    media = session.media_of(speech)
    session.add(media, at=0)
    session.save()
    session.op("transcribe", engine="assemblyai", place=False)
    folder = os.path.join(session.path, "cache", "transcripts")
    target = os.path.join(folder, f"{media}.json")
    marker = os.path.join(folder, f"{media}.complete.json")
    check("M: run 1 wrote the cache file and its marker",
          os.path.exists(target) and os.path.exists(marker),
          f"got {sorted(os.listdir(folder)) if os.path.isdir(folder) else folder!r}")
    if not (os.path.exists(target) and os.path.exists(marker)):
        return
    first = json.loads(read(target).decode())
    before = read(marker)
    os.chflags(target, stat.UF_IMMUTABLE)
    try:
        scenario(fake, words=bravo)
        # A DIFFERENT request, so the stamp really does change and run 2 has
        # to re-fetch rather than read the cache.
        answer = session.op("transcribe", engine="assemblyai", place=False, speakers=True)
        check("M: run 2 really did upload again — a different request is a different stamp",
              answer.get("uploaded") == [int(media)], f"got {answer!r}")
        after = json.loads(read(target).decode())
        check("M: CONTROL — the immutable flag really did stop the write: the file still "
              "holds run 1's words",
              after.get("words") == first.get("words"),
              f"got {after.get('words')!r}")
        check("M: so the MARKER was not rewritten either — a stamp over a stale file would "
              "certify an earlier request's transcript",
              read(marker) == before,
              f"marker changed: {read(marker)[:200]!r}")
        third = session.op("transcribe", engine="assemblyai", place=False, speakers=True)
        check("M: and the next run with that same request UPLOADS rather than serving the "
              "stale file from the cache",
              third.get("uploaded") == [int(media)] and third.get("cached") == [],
              f"got uploaded={third.get('uploaded')!r} cached={third.get('cached')!r}")
    finally:
        os.chflags(target, 0)


def row_o(instance, fake):
    """The reader review's R1·1 — `audio_seconds` is the SERVER's own number
    summed with `+`, which TRAPS.

    Two media, each answered `9223372036854775807`, killed the whole app after
    both had been uploaded and billed: the MCP socket closed with no answer and
    the process was gone. The row is three trials so the arithmetic is pinned
    rather than guessed — one media at the maximum and two at half of it both
    have to come back, or a build that simply refused the key would pass. A
    fourth (issue batch B34, #187 item 3): one media answered `-5` bills 0."""
    print("\nO. a hostile `audio_duration` cannot kill the app (the reader review, R1\u00b71)")
    speech, second = fixtures()
    big = 2 ** 63 - 1
    for tag, seconds, two, expected in (
            ("one media at Int.max", big, False, big),
            ("two media at half of it", big // 2, True, 2 * (big // 2)),
            ("two media at Int.max", big, True, big),
            ("one media at -5", -5, False, 0)):
        scenario(fake, audio_seconds=seconds)
        session = Session(instance, "rowO-" + tag.replace(" ", "-"))
        session.add(session.media_of(speech), at=0)
        if two:
            session.add(session.media_of(second), at=10 * SEC)
        session.save()
        answer = None
        failure = None
        try:
            answer = session.op("transcribe", engine="assemblyai", place=False)
        except ToolError as problem:
            failure = f"refused in band: {problem}"
        except Exception as problem:  # noqa: BLE001 — a dead instance is the finding
            failure = f"{type(problem).__name__}: {problem}"
        alive = instance.process.poll() is None
        check(f"O: {tag} \u2014 the instance is still alive after the call",
              alive, "the app died mid-answer: the sum trapped")
        if not alive:
            return
        check(f"O: {tag} \u2014 the call answered at all", answer is not None,
              failure or "no answer")
        if answer is None:
            continue
        check(f"O: {tag} \u2014 `audio_seconds` is {expected}",
              answer.get("audio_seconds") == expected,
              f"got {answer.get('audio_seconds')!r}")
        check(f"O: {tag} \u2014 and every media really was uploaded, so the sum has as "
              f"many terms as the tag says",
              len(answer.get("uploaded") or []) == (2 if two else 1),
              f"got {answer.get('uploaded')!r}")


def row_k(fake_folders):
    print("\nK/X. the dummy key, this host's user name, and where they are allowed to be")
    where = []
    for tag, path in logs.items():
        if DUMMY.encode() in read(path):
            where.append(path)
    check("K: the dummy key is in NO app log — the client puts it in one header and in no "
          "log line", not where, f"found in {where!r}")
    answers = [text for text in transcript_of_the_run if DUMMY in text]
    check(f"K: and in none of the {len(transcript_of_the_run)} MCP answers and refusals this "
          "run accumulated — not a result, not a `skipped` line, not a `note`",
          not answers, f"found in {answers[:2]!r}")

    # Every folder this run wrote into: the proof's own, and each fake's —
    # the upload bodies and whatever else a stand-in leaves behind. The
    # fake's request LOG is in memory and never written, which is why the
    # answer below is "nowhere at all" rather than "nowhere but the log".
    found = []
    for folder in [WORK] + list(fake_folders):
        for base, _, names in os.walk(folder):
            for name in names:
                path = os.path.join(base, name)
                if DUMMY.encode() in read(path):
                    found.append(path)
    check("K: and in no file this run wrote — not under the proof's work folder, not under "
          "any fake's (the fake keeps its request log in memory, so there is not even that)",
          not found, f"found in {found!r}")

    user = getpass.getuser()
    home = os.path.expanduser("~")
    leaks = []
    for folder in fake_folders:
        for base, _, names in os.walk(folder):
            for name in names:
                if not name.endswith(".json"):
                    continue
                body = read(os.path.join(base, name)).decode("utf-8", "replace")
                if user in body or home in body:
                    leaks.append(os.path.join(base, name))
    check("X: no header and no JSON body the fake logged holds this host's user name or "
          "home path — the person's identity is in nothing that goes out",
          not leaks, f"found in {leaks!r}")


# --------------------------------------------------------------------------
# RP — the 21 pairs of `transcribe`'s seven refusals (issue batch B24, #80;
# spec §11 R6-17)

PAIR_ORDER = [1, 2, 3, 4, 5, 7, 6]
# What a refusal's sentence is recognised by when it is NOT the winner: a
# loser's marker anywhere in the answer is a pair answering in two rules'
# words.
LOSER_MARKERS = {
    1: "No clip has id", 2: "can be transcribed", 3: 'engine must be "apple"',
    4: "only applies with engine", 5: "No AssemblyAI API key is set",
    6: "10-hour limit", 7: "its earlier transcript",
}
NO_KEY = ("No AssemblyAI API key is set. Set one in Reelcut ▸ Settings ▸ "
          "Transcription, or RC_ASSEMBLYAI_KEY for a proof.")
DEFERRED = ("AssemblyAI has not confirmed deleting the transcript of media {media}; cleanup "
            "was deferred because no API key is set. Its deletion ID is retained in the "
            "project; a later run with a key for the originating account and region will "
            "retry deletion only if that ID is safe to send.")
HELD_LINE = ("AssemblyAI has not confirmed deleting the transcript of media {media}; it will "
             "be retried at the next run with an API key. It was not uploaded again in this "
             "run.")


def rewrite_media_duration(package, seconds):
    """The one media's `duration` in a SAVED package's `project.json`, set to
    `seconds` — row H's rewrite, since no op can make a media longer than its
    file. Answers whether it was found and written."""
    path = os.path.join(package, "project.json")
    try:
        document = json.loads(read(path).decode("utf-8"))
        document["media"][0]["duration"] = int(seconds * SEC)
    except (ValueError, KeyError, IndexError, TypeError):
        return False
    with open(path, "w") as handle:
        json.dump(document, handle)
    return True


def pair_copy(source, name):
    """A copy of a package that is OPEN in an instance. Its display caches
    are still being written while it is copied, through `.sb-` temporaries
    that can vanish between the listing and the copy, so those are left out
    and a copy that raced one anyway is taken again (three tries)."""
    path = os.path.join(WORK, f"pairs-{name}-{os.getpid()}.reelcut")
    for attempt in range(3):
        shutil.rmtree(path, ignore_errors=True)
        try:
            shutil.copytree(source, path, ignore=shutil.ignore_patterns("*.sb-*"))
            return path
        except shutil.Error:
            if attempt == 2:
                raise
            time.sleep(0.5)
    return path


def build_pair_packages(rp, fake_rp):
    """Six packages over ONE media with two clips on it — A plays sound, M's
    audio is switched off — and the owed transcript id the `held` ones carry.
    None, with a scored failure, when any step of the fixture fails."""
    speech, _ = fixtures()
    session = Session(rp, "pairs-plain")
    media = session.media_of(speech)
    a = session.add(media, at=0, duration=2 * SEC)
    m = session.add(media, at=2 * SEC, duration=2 * SEC)
    session.op("set_enabled", clip=m, audio=False)
    session.save()
    plain = session.path
    long = pair_copy(plain, "long")
    plain_q = pair_copy(plain, "plain_q")
    long_q = pair_copy(plain, "long_q")
    held = pair_copy(plain, "held")
    rewritten = rewrite_media_duration(long, 40_000) and rewrite_media_duration(long_q, 40_000)
    if not rewritten:
        check("RP fixture: the copied packages' media duration can be rewritten", False,
              "no media duration in project.json")
        return None

    rp.mcp.call("open_project", path=held)
    # Never reset during RP: every DELETE the fake is sent answers 500, so
    # the one this transcribe makes leaves its id owed, and every later
    # janitor over `held` fails and HOLDS the media (R6-11).
    scenario(fake_rp, fail=[{"route": "delete", "status": 500, "times": -1}])
    answer = rp.mcp.call_with("transcribe", {"project": held, "engine": "assemblyai",
                                            "clips": [a], "place": False})
    transcript_of_the_run.append(json.dumps(answer, default=str))
    rp.mcp.call("save_project", project=held)
    header = json.loads(read(os.path.join(held, "cache", "transcripts", f"{media}.json"))
                        or b"{}")
    owed = header.get("transcript_id")
    if header.get("remote_deleted") is not False or not owed:
        check("RP fixture: the held package owes a DELETE", False,
              f"header {header!r}, answer {answer!r}")
        return None
    held_q = pair_copy(held, "held_q")
    heldlong = pair_copy(held, "heldlong")
    if not rewrite_media_duration(heldlong, 40_000):
        check("RP fixture: heldlong's media duration can be rewritten", False, "")
        return None
    for path in (long, heldlong):
        rp.mcp.call("open_project", path=path)
    return {"plain": plain, "long": long, "held": held, "heldlong": heldlong,
            "plain_q": plain_q, "long_q": long_q, "held_q": held_q,
            "a": a, "m": m, "media": media, "owed": owed}


def pair_call(instance, fake, packages, cell):
    """One cell: its package and its arguments, the answer (a refusal's
    text), and the fake's log delta across the call."""
    s = set(cell)
    if 6 in s and 7 in s:
        package = "heldlong"
    elif 6 in s:
        package = "long"
    elif 7 in s:
        package = "held"
    else:
        package = "plain"
    if 5 in s:
        package += "_q"
    arguments = {"project": packages[package], "engine": "assemblyai", "place": False}
    if 1 in s and 2 in s:
        arguments["clips"] = [packages["m"], 99999]
    elif 1 in s:
        arguments["clips"] = [packages["a"], 99999] if (6 in s or 7 in s) else [99999]
    elif 2 in s:
        arguments["clips"] = [packages["m"]]
    else:
        arguments["clips"] = [packages["a"]]
    if 3 in s:
        arguments["engine"] = "nope"
    if 4 in s:
        if 3 not in s:
            arguments["engine"] = "apple"
        arguments["speakers"] = True
    if 7 in s:
        arguments["refresh"] = True
    mark = len(fake.log()["requests"])
    try:
        answer = instance.mcp.call_with("transcribe", arguments)
        text = None
        transcript_of_the_run.append(json.dumps(answer, default=str))
    except ToolError as problem:
        text = str(problem)
        transcript_of_the_run.append(text)
    delta = [f"{r['method']} {r['path']}" for r in fake.log()["requests"][mark:]]
    return text, delta, package


def pair_expected(packages, winner, cell):
    """The winner's answer, line for line, and the log delta it may make."""
    a, m, media = packages["a"], packages["m"], packages["media"]
    first = {
        1: "No clip has id 99999. get_project lists the clips.",
        2: f"None of those clips can be transcribed — clip {m}: its audio is switched off.",
        3: 'engine must be "apple" or "assemblyai" (got "nope").',
        4: 'speakers only applies with engine "assemblyai". Pass engine: "assemblyai", or '
           'leave it out.',
        5: NO_KEY,
        6: f"The transcription failed: clip {a}: “speech.mov” is longer than "
           "AssemblyAI's 10-hour limit for one file.",
        7: f"The transcription failed: clip {a}: AssemblyAI has not confirmed deleting its "
           "earlier transcript, so it was not uploaded again; the next run with an API key "
           "retries the delete",
    }[winner]
    lines = ["transcribe: " + first]
    if winner == 5 and 7 in cell:
        lines.append(DEFERRED.format(media=media))
    if winner == 7:
        lines.append(HELD_LINE.format(media=media))
    delta = [f"DELETE /v2/transcript/{packages['owed']}"] if winner == 7 else []
    return lines, delta


def score_cell(instance, fake, packages, cell, control=False):
    winner = min(cell, key=PAIR_ORDER.index)
    text, delta, package = pair_call(instance, fake, packages, cell)
    lines, want_delta = pair_expected(packages, winner, cell)
    losers = [LOSER_MARKERS[i] for i in LOSER_MARKERS if i != winner
              and LOSER_MARKERS[i] in (text or "")]
    label = ("CONTROL R" + str(cell[0]) + " alone") if control else (
        "R" + "×R".join(str(i) for i in cell))
    print(f"  ({label} on {package}: {text!r}; log {delta!r})")
    check(f"RP {label}: answers in R{winner}'s own sentence, line for line, with no other "
          "rule's words in it, and the fake saw "
          + ("exactly the owed DELETE" if want_delta else "nothing"),
          text is not None and text.split("\n") == lines and not losers
          and delta == want_delta,
          f"got {text!r}, losers {losers!r}, log {delta!r}; want {lines!r}, "
          f"log {want_delta!r}")


PAIRS = [(i, j) for i in range(1, 8) for j in range(i + 1, 8)]


def row_pairs(rp, fake_rp, packages):
    print("\nRP. the 21 pairs of transcribe's seven refusals — the 15 without R5, "
          "and six single-ingredient CONTROLS (B24, #80)")
    if packages is None:
        check("RP: the pair packages were built", False)
        return
    # The single-ingredient CONTROLS first: a cell whose loser's ingredient
    # did not apply on its own proves nothing.
    for one in (1, 2, 3, 4, 6, 7):
        score_cell(rp, fake_rp, packages, (one,), control=True)
    for cell in PAIRS:
        if 5 not in cell:
            score_cell(rp, fake_rp, packages, cell)


def row_pairs_keyless(rq, fake_rq, packages):
    print("\nRP (keyless). the six pairs with R5, on an instance with no key, and R5's "
          "CONTROL (B24, #80)")
    if packages is None:
        check("RP keyless: the pair packages were built", False)
        return
    for path in (packages["plain_q"], packages["long_q"], packages["held_q"]):
        rq.mcp.call("open_project", path=path)
    score_cell(rq, fake_rq, packages, (5,), control=True)
    for cell in PAIRS:
        if 5 in cell:
            score_cell(rq, fake_rq, packages, cell)


# --------------------------------------------------------------------------
# The mutants


CLOUD_MUTANTS = {
    "keyless-agent-requires-key": (
        "app/Sources/AgentServer+CloudCaptions.swift",
        "        let credential = AssemblyAIConfiguration.credential(\n",
        "        guard AssemblyAIConfiguration.credential(\n"
        "            store: AssemblyAIConfiguration.store()) != nil else {\n"
        "            throw ToolError(message: CloudTranscriber.AccessError.credentialRequired"
        ".localizedDescription)\n"
        "        }\n"
        "        let credential = AssemblyAIConfiguration.credential(\n",
        "the MCP cloud arm restores unconditional credential refusal"),
    "stamp-always-stale": (
        "app/Sources/CloudTranscriber.swift",
        "            if MediaTranscript.isCurrent(stamp, for: id, in: cacheDirectory), "
        "!refresh {\n",
        "            if false {\n",
        "the stamp comparison deleted — every run uploads (row 5)"),
    "no-delete": (
        "app/Sources/CloudTranscriber+Media.swift",
        "        let deleted = client.delete(id: fetched.response.id, cancel: cancel) == .deleted\n",
        "        let deleted = false\n",
        "the remote DELETE removed (rows 2, 4)"),
    "no-janitor": (
        "app/Sources/CloudTranscriber.swift",
        "        let janitor = retryDeletes(cancel: cancel)\n",
        "        let janitor: (deleted: [UInt32], failed: [UInt32]) = ([], [])\n",
        "the janitor removed (row 11)"),
    "auth-carries-on": (
        "app/Sources/CloudTranscriber.swift",
        "                        if case .keyRefused = client { throw error }\n",
        "",
        "the 401 arm not ending the run (row 6: two uploads where one is right)"),
    "no-hold": (
        "app/Sources/CloudTranscriber.swift",
        "            } else if report.janitorFailed.contains(id) {\n"
        "                held.append(id)\n"
        "            } else {\n",
        "            } else {\n",
        "R6-11's hold removed — a media with an unconfirmed delete is fetched anyway "
        "(row 11's hold arm)"),
    "agent-reads-remembered-engine": (
        "app/Sources/AgentServer+CloudCaptions.swift",
        '        guard let name = try stringArg(a, "engine") else { return .apple }\n',
        '        guard let name = try stringArg(a, "engine")\n'
        '            ?? UserDefaults.standard.string(forKey: TranscriptionEngine.defaultsKey)\n'
        '        else { return .apple }\n',
        "R6-2 broken — the tool falling back to the SHEET's remembered engine when the "
        "call named none (row 8, because every instance is launched with that key pinned "
        "to assemblyai)"),
    # The reader review's named mutants that the MCP proof scores too
    # (road map 6 §10.13, step 8). Z6, Z7 and Z10 are `not run` here:
    # no tool reaches the resolver's argument table or the estimate.
    "z1-follows-redirect": (
        "app/Sources/AssemblyAIClient+Session.swift",
        '            completionHandler(nil)\n',
        '            completionHandler(request)\n',
        'Z1 — the redirect FOLLOWED, so the authorization header goes to whatever host the Location named'),
    "z2-throw-without-delete": (
        "app/Sources/AssemblyAIClient+Session.swift",
        '        delete(id: id, cancel: cancel)\n',
        '',
        'Z2 — `refusing` no longer DELETEs before it throws (R6-4)'),
    "z3-extract-kept": (
        "app/Sources/CloudTranscriber+Media.swift",
        '        defer { try? FileManager.default.removeItem(at: upload.url) }\n',
        '',
        'Z3 — the temporary extract is never removed'),
    "z4-words-reserialised": (
        "app/Sources/AssemblyAIClient.swift",
        'return Fetched(response: response, wordsJSON: words)',
        'return Fetched(response: response, wordsJSON: (try? JSONEncoder().encode(response.words ?? [])) ?? words)',
        'Z4 — the served `words` bytes re-serialised through Codable'),
    "z5-key-in-note": (
        "app/Sources/AssemblyAIClient.swift",
        'note("\\(request.httpMethod ?? "?") \\(request.url?.path ?? "?") → "',
        'note("\\(request.value(forHTTPHeaderField: "authorization") ?? "") \\(request.httpMethod ?? "?") \\(request.url?.path ?? "?") → "',
        'Z5 — the credential in every client log line (dummy keys only)'),
    "z9-boundary-doubled": (
        "app/Sources/MediaTranscript.swift",
        'startTicks < windowEnd else { continue }',
        'startTicks <= windowEnd else { continue }',
        "Z9 — the window's end made inclusive, so a split's halves double a word"),
    "z12-no-ceiling": (
        "app/Sources/AssemblyAIClient.swift",
        '            if Date().timeIntervalSince(started) > ceiling {\n'
        '                throw refusing(.timedOut, id: id, cancel: cancel)\n'
        '            }\n',
        '',
        'Z12 — the poll ceiling removed'),
    "silent-about-the-bill": (
        "app/Sources/AgentServer+CloudCaptions.swift",
        '        return ([error.localizedDescription + billed(report)] + warnings)',
        '        return ([error.localizedDescription] + warnings)',
        "the bill sentence dropped from a failed run \u2014 the reader review's R5\u00b72, "
        "reverted (row B)"),
    "bill-promises-cache": (
        "app/Sources/AgentServer+CloudCaptions.swift",
        '            + "before this failed."\n',
        '            + "before this failed; their transcripts are cached in the project, so "\n'
        '            + "another run makes no request for them."\n',
        "the bill sentence promising a cache again — the reader review's fix pass, "
        "reverted (row B: a run whose cache write could not land)"),
    "key-relayed-verbatim": (
        "app/Sources/AssemblyAIClient.swift",
        '        guard !credential.isEmpty, text.contains(credential) else { return text }\n'
        '        return text.replacingOccurrences(of: credential, with: "<redacted>")\n',
        '        return text\n',
        "the relayed sentence carrying the credential again \u2014 the reader review's R2\u00b71 "
        "(row E: a server that echoes the authorization header puts the key in an MCP "
        "refusal)"),
    "marker-over-stale-file": (
        "app/Sources/CloudTranscriber+Media.swift",
        '        let stampWritten = transcriptWritten\n'
        '            && MediaTranscript.writeStamp(stamp, for: media.id, in: cacheDirectory)\n',
        '        let stampWritten = MediaTranscript.writeStamp(stamp, for: media.id, in: cacheDirectory)\n'
        '            && transcriptWritten\n',
        "`write`'s answer discarded again \u2014 the reader review's R1\u00b73 (row M: a marker "
        "stamped over a cache file the write never replaced)"),
    "audio-seconds-plus": (
        "app/Sources/CloudTranscriber+Report.swift",
        '            uploaded.reduce(0) { sum, row in\n'
        '                let (total, overflowed) = sum.addingReportingOverflow(max(0, row.audioSeconds))\n'
        '                return overflowed ? Int.max : total\n'
        '            }\n',
        '            uploaded.reduce(0) { $0 + $1.audioSeconds }\n',
        "the saturating sum reverted to `+` \u2014 the reader review's R1\u00b71 (row O: the "
        "app dies on two media the server answered `9223372036854775807` for)"),
    "endpoint-whole-url": (
        "app/Sources/AgentServer+CloudCaptions.swift",
        "endpoint: client?.base.host,",
        'endpoint: client?.base.absoluteString ?? "none",',
        "#94's `endpoint` carrying the whole base URL rather than its host (row 2's "
        "endpoint check; KL MCP's absence check)"),
    "note-block-buffered": (
        "app/Sources/AssemblyAIClient+Session.swift",
        '        try? FileHandle.standardOutput.write(contentsOf: Data("AssemblyAI: \\(line)\\n".utf8))\n',
        '        print("AssemblyAI: \\(line)")\n',
        "#116 reverted — the client's log lines block-buffered again under a file "
        "redirect (row LOG's sequence check)"),
    "universal-2-only": (
        "app/Sources/AssemblyAITranscript.swift",
        '    static let shippedModels = ["universal-3-5-pro", "universal-2"]\n',
        '    static let shippedModels = ["universal-2"]\n',
        "`speech_models` pinned to Universal-2 (row 2)"),
}
# Issue batch B24 (#80): `engine` read before the scope — R1 and R2 would
# then lose to R3 (RP's R1×R3 and R2×R3 cells).
CLOUD_MUTANTS["engine-before-scope"] = (
    "app/Sources/AgentServer+Captions.swift",
    "        let document = try onMain { try self.target(a) }\n"
    "        // The scope, the jobs and the frame in ONE main-thread hop, so every\n",
    "        _ = try transcriptionEngine(a)\n"
    "        let document = try onMain { try self.target(a) }\n"
    "        // The scope, the jobs and the frame in ONE main-thread hop, so every\n",
    "`engine` read before the scope — R6-17's first two places behind the third "
    "(RP's R1×R3 and R2×R3)")
# Three come straight from the probe's own table rather than being spelled a
# second time here (road map 6 §10.9 aimed them).
for _name in ("mapping-no-in", "no-retry", "no-fifth-rule"):
    _file, _before, _after, _what = MUTANTS[_name]
    CLOUD_MUTANTS[_name] = ("app/Sources/" + _file, _before, _after, _what)


def build_mutant(name, wall=900):
    """A COPY of the tree with one text replaced and the app built inside it.

    The copy is `tree_copy.make_copy`'s: `app/` and `agent/` copied, every
    other build input `project.yml` names a SYMLINK to the tree's (`core`
    already built, so `project.yml`'s pre-build `cargo build --release` is a
    no-op and the copy links the tree's `libreelcut_core.a`). The copy is
    built by its own `make app`, whose `unexport` keeps both keys out of its
    build database. The working tree is never touched."""
    path, before, after, what = CLOUD_MUTANTS[name]
    root, reason = tree_copy.make_copy(os.path.join(WORK, "mutants", name))
    if root is None:
        return None, reason

    target = os.path.join(root, path)
    text = open(target).read()
    if text.count(before) != 1:
        return None, (f"mutant {name}: the text to replace occurs {text.count(before)} times "
                      f"in {path}, not once — the tree has moved and the mutant needs "
                      f"re-aiming")
    with open(target, "w") as handle:
        handle.write(text.replace(before, after))
    print(f"  mutant {name}: {what}")
    started = time.time()
    try:
        run = subprocess.run(["make", "app"], cwd=root, capture_output=True, text=True,
                             env=child_env(), timeout=wall, stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return None, f"the mutant's build passed its {wall:.0f} s wall"
    if run.returncode != 0:
        errors = [line for line in (run.stdout + run.stderr).splitlines() if "error:" in line]
        return None, "`make app` failed:\n      " + "\n      ".join(errors[:6] or ["(none)"])
    binary = os.path.join(root, "build", "Build", "Products", "Release", "Reelcut.app",
                          "Contents", "MacOS", "Reelcut")
    print(f"  built {binary} in {time.time() - started:.0f} s")
    return binary, None


# --------------------------------------------------------------------------

instance_binary = ""


def main():
    global instance_binary
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--binary", default=os.path.join(
        ROOT, "build", "Build", "Products", "Release", "Reelcut.app", "Contents", "MacOS",
        "Reelcut"))
    parser.add_argument("--port-base", type=int, default=None,
                        help="the first port an instance binds (default 4955, or 4960 "
                             "under --mutant so a mutant run cannot collide with a tree "
                             "run on the same host); an EXPLICIT flag is honoured under "
                             "--mutant too")
    parser.add_argument("--mutant", choices=sorted(CLOUD_MUTANTS),
                        help="build a COPY of the tree with one text replaced and run every "
                             "row against it")
    parser.add_argument("--fake-mutant",
                        choices=sorted(cloud_captions_probe.FAKE_MUTANTS),
                        help="patch a COPY of assemblyai_fake.py and run every row against "
                             "the TREE's binary \u2014 a mutant of the INSTRUMENT, which builds "
                             "nothing; refused together with --mutant")
    parser.add_argument("--wall", type=float, default=1800,
                        help="the whole run's wall-clock bound in seconds (rule H)")
    parser.add_argument("--live", action="store_true",
                        help="road map 6 §5i's rows 20 and 21 against the REAL service "
                             "INSTEAD of rows 1-11 — this SPENDS money, under "
                             "cloud_captions_live.py's ledger and its $0.25 ceiling, and "
                             "the month's $5 AssemblyAI budget in the proofs' ledger "
                             "(spec §11 P-6)")
    args = parser.parse_args()

    started = time.time()
    os.makedirs(WORK, exist_ok=True)
    print("road map 6 C1 pipeline 3 — the cloud engine, over MCP, against the stand-in\n")

    if args.mutant and args.fake_mutant:
        print("--mutant and --fake-mutant are two different mutants and are refused "
              "together: a cell measures one thing")
        return 2
    if args.fake_mutant:
        cloud_captions_probe.prepare_fake_mutant(args.fake_mutant)

    binary = args.binary
    # An explicit --port-base wins; absent, a mutant run moves off the
    # tree run's ports of its own accord.
    port_base = args.port_base if args.port_base is not None else (
        4960 if args.mutant else 4955)
    if args.mutant:
        binary, error = build_mutant(args.mutant)
        if binary is None:
            check(f"the mutant {args.mutant} builds", False, error)
            print(f"\n{passed}/{passed + failed} checks passed in {time.time() - started:.0f} s")
            # Rule R (issue batch B13): a mutant that did not build performs
            # no control, and is never read as a caught mutant.
            why = ((error or "no build").strip().splitlines() or ["no reason given"])[0]
            why = why.removeprefix(f"mutant {args.mutant}: ")
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
    if not os.path.exists(binary):
        check("the built binary is there — run `make app` first", False, binary)
        print(f"\n{passed}/{passed + failed} checks passed in {time.time() - started:.0f} s")
        return 1
    instance_binary = binary

    speech, _ = fixtures()
    if speech is None:
        check("media/speech.mov is there (tools/proof/README.md says how to make it)",
              False, "no fixture")
        return 1

    probe, error = build(TREE_SOURCES, PROBE_SOURCE, "probe", "cloudprobe")
    check("the probe binary is available for row 2's decoders — an instrument that will not "
          "compile is a FAILURE here, not an exit", probe is not None, error or "")
    harness = None
    if not args.live:
        harness, harness_error = build(TREE_SOURCES, open(HARNESS_MAIN).read(), "harness",
                                       "harness")
        check("the harness is available for row 3's line-breaking",
              harness is not None, harness_error or "")

    if args.live:
        # Rows 20 and 21, and nothing else: the live module opens its own
        # instances on `port_base + 3` and `+ 4`, against api.assemblyai.com.
        import cloud_captions_live

        run_row(cloud_captions_live.run, sys.modules[__name__], binary, port_base, probe)
        tail = ""
        if skips:
            tail = (" (" + str(skipped) + " skipped by name — "
                    + "; ".join(f"{n}: {why}" for n, why in skips) + ")")
        print(f"\n{passed}/{passed + failed} checks passed{tail} in "
              f"{time.time() - started:.0f} s")
        return 0 if failed == 0 else 1
    print("  (rows 20 and 21 are LIVE and did not run: `--live` is their flag, and it "
          "SPENDS money)")

    fake_folders = []
    keyless_seed = None
    try:
        with Fake("proof-a") as fake_a:
            fake_folders.append(fake_a.folder)
            with Instance("A", port_base, fake_a, binary) as a:
                run_row(row_one_caller, a, fake_a)
                run_row(row_two, a, fake_a, probe)
                run_row(row_log, a, fake_a)
                run_row(row_three, a, fake_a, harness)
                run_row(row_four, a, fake_a)
                run_row(row_recovery, a, fake_a)
                run_row(row_five, a, fake_a)
                run_row(row_seven, a, fake_a)
                run_row(row_eight, a, fake_a)
                run_row(row_nine, a, fake_a)
                run_row(row_ten, a)
                try:
                    keyless_seed = seed_keyless_package(a, fake_a)
                except Exception as problem:
                    check("KL seed: package fixture builds", False, str(problem))
        if time.time() - started > args.wall:
            skip_rows(1, f"the run passed its --wall bound of {args.wall:.0f} s")
        else:
            with Fake("proof-b") as fake_b:
                fake_folders.append(fake_b.folder)
                with Instance("B", port_base + 1, fake_b, binary, key=None,
                              endpoint="http://remote.invalid") as b:
                    run_row(row_one_no_key, b, fake_b)
                    run_row(row_keyless_mcp, b, fake_b, keyless_seed)
            with Fake("proof-c") as fake_c:
                fake_folders.append(fake_c.folder)
                with Instance("C", port_base + 2, fake_c, binary) as c:
                    run_row(row_six, c, fake_c)
                    run_row(row_eleven, c, fake_c)
                    run_row(row_h, c, fake_c)
                    run_row(row_t, c, fake_c)
                    run_row(row_o, c, fake_c)
                    run_row(row_m, c, fake_c)
                    run_row(row_e, c, fake_c)
                    run_row(row_b, c, fake_c)
        # RP (issue batch B24, #80): two instances of their own, so C is not
        # loaded further (an instance deadlocks past ~40 open documents).
        if time.time() - started > args.wall:
            skip_rows(1, f"the run passed its --wall bound of {args.wall:.0f} s before RP")
        else:
            packages = None
            with Fake("proof-rp") as fake_rp:
                fake_folders.append(fake_rp.folder)
                with Instance("RP", port_base + 3, fake_rp, binary) as rp:
                    try:
                        packages = build_pair_packages(rp, fake_rp)
                    except Exception as problem:  # noqa: BLE001 — the fixture's answer
                        check("RP fixture: the pair packages build", False,
                              f"{type(problem).__name__}: {problem}")
                    run_row(row_pairs, rp, fake_rp, packages)
            with Fake("proof-rq") as fake_rq:
                fake_folders.append(fake_rq.folder)
                with Instance("RQ", port_base + 4, fake_rq, binary, key=None) as rq:
                    run_row(row_pairs_keyless, rq, fake_rq, packages)
        run_row(row_k, fake_folders)
    finally:
        left = [one for one in temp_uploads()]
        if left:
            print(f"  (note: {len(left)} reelcut-upload-* left in a temporary folder)")

    tail = ""
    if skips:
        tail = (" (" + str(skipped) + " skipped by name — "
                + "; ".join(f"{n}: {why}" for n, why in skips) + ")")
    print(f"\n{passed}/{passed + failed} checks passed{tail} in {time.time() - started:.0f} s")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
