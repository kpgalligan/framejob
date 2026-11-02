#!/usr/bin/env python3
"""Road map "creator-jobs" CJ1 (spec §11 CJ-10…CJ-13): the key gate, `ModelKeys`.

    env -u RC_ASSEMBLYAI_KEY -u ANTHROPIC_API_KEY \\
        python3 tools/proof/keys_proof.py [--mutant NAME] [--only IDS]

No row spends anything and none reads the person's keys: the probe and every
instance get an empty `-RCSecretFolder`, both variables are unset, and the only
keys are the dummy `proof-key` against `assemblyai_fake.py` and
`anthropic_fake.py`.

Probe rows (`keys_probe.swift`, copied in as `main.swift` and built with
`swift_build.build()` and `FRAMEJOB_DEV_TOOLS` over `app/Sources`, or a probe
mutant's copy, run once as `keys-probe media/speech.mov -RCSecretFolder
<scratch>` under `tools/proof/work/keys/<tree|mutant-NAME>/`, killed at a
240 s wall; a build failure is every probe row's scored FAIL):
  K3  each `ModelKeys.keyed` row with a menu action, its item found by
      selector in `AppDelegate().buildMainMenu()` and validated through
      `EditorViewController.validateUserInterfaceItem` on a document whose
      media has no filler transcript: keyless off, the sentence its tooltip,
      its title suffixed; with a key file written into the scratch folder on,
      no tooltip, its base title.
  K3b `NSApp.mainMenu` built; keyless the filler item validates suffixed with
      the sentence; a key written and `SettingsWindowController`'s
      notification posted with NO validation: base title, no tooltip; the key
      removed and posted again: unchanged (the reset never adds a suffix).
  K4  `present` over a scratch `FileStore` follows a write and a remove with
      no notification; the variable alone is presence.
  K4b the Remove Filler Words sheet and the Generate Captions sheet (cloud
      engine) open over empty `MemoryStore`s: Transcribe and Start off with
      the sentence; a key written into each store and Settings' notification
      posted: both on with no tooltip; `ModelKeys` re-posts `assemblyAI` for
      Settings' notification and `anthropic` for the assistant's, once each.
  K5p keyless, the menu validator off; a filler transcript seeded into the
      document's cache (`MediaTranscript.write` + `writeStamp`): on, on the same
      project handle.
  K6  Generate Captions, cloud engine, empty store: the AssemblyAI engine item
      enabled; Start off with the sentence; over a reusable batch (R6-16) on
      with no tooltip; back on the on-device engine no tooltip.
  K7  (probe part) `keyedToolFailure` over `catalogJSON()` is nil, and over a
      copy with `transcribe_for_fillers`' clause removed it names that tool.

App rows (the app `proof_app` chooses — Debug by default,
`RC_PROOF_APP=release` for the record — through
`cloud_captions_proof.Instance`/`Session`, the fake serving
`cloud_captions_proof.DISFLUENT_WORDS`, with `media/speech.mov` and
`media/speech.aiff` as a second sounding media):
  K2  the dummy key in `RC_ASSEMBLYAI_KEY`, no transcript yet: Clip ▸ Remove
      Filler Words… is listed enabled under its base title and
      `perform_menu_item` opens its sheet (then `cancel_sheet`);
      `transcribe_for_fillers` reaches the stand-in (one submit) and answers
      `ready: true`; the package is saved.
  K1  a keyless instance on K2's package: `transcribe_for_fillers` refuses
      987654 for the id, the second media in exactly "transcribe_for_fillers: "
      and the AssemblyAI sentence, answers speech.mov `ready: true`,
      `uploaded: []`; `transcribe {engine: "assemblyai"}` refuses with the
      sentence; the stand-in logs no request.
  K5  the same keyless instance: K2's package lists the item enabled and
      opens its sheet; a new project with speech.mov's clip and no
      transcript lists it disabled, titled "Remove Filler Words… (needs your
      AssemblyAI key)".
  K7  (app part) neither instance's log has a "Frame Job: " line.
  K8  no Anthropic key (an empty secret folder), `anthropic_fake.py` as the
      base URL: View ▸ Assistant is listed enabled; `assistant_send` answers
      the Anthropic sentence; the stand-in logs no request.

K7 is scored by each half the run reaches: its probe half when another probe
row is wanted, its app half when another app row is, both when it is named
alone; when both run, both must pass.

Mutants (`--mutant`), each anchor asserted to occur once; a probe mutant
builds the probe over a copy of `app/Sources`, an app mutant builds the app
in a tree copy (`tree_copy.build_app`) and runs its named rows on it:
  present-ignores-environment  app: `present` reads `[:]` for AssemblyAI (K2)
  credential-before-ready      app: `transcribe_for_fillers` requires the key
                               above its ready arm (K1)
  presence-memo                probe: `present` keeps its first answer (K4)
  no-transcript-arm            app: the validator's transcript arm removed (K5)
  control-tooltip-unset        probe: `mark(control)` sets no tooltip (K6, K4b)
  item-suffix-kept             probe: `mark(item)` does not strip a suffix (K3)
  start-missing-nil            probe: Start's `missing` forced nil (K6)
  settings-unobserved          probe: the install does not observe Settings'
                               notification (K4b)
  no-clause-test               probe: `keyedToolFailure`'s clause test removed (K7)
  memo-without-folder-date     probe: the presence memo ignores the transcripts
                               folder's date (K5p)
  no-menu-reset                probe: the install does not reset the menu (K3b)

Exit: a plain run exits 0 iff every row passed, else 1. A `--mutant` run
exits 0 when every row the mutant names failed (caught), 1 when one passed
(survived), and 2 when the control could not be performed: an anchor not
found exactly once, the copy did not build, or a named row was not scored.
"""
import argparse
import contextlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import traceback

import swift_build

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/keys"
PROBE = ROOT / "tools/proof/keys_probe.swift"
SPEECH = ROOT / "tools/proof/media/speech.mov"
SECOND = ROOT / "tools/proof/media/speech.aiff"
PROBE_ROWS = ["K3", "K3b", "K4", "K4b", "K5p", "K6", "K7"]
APP_ROWS = ["K2", "K1", "K5", "K7", "K8"]
ROWS = ["K1", "K2", "K3", "K3b", "K4", "K4b", "K5", "K5p", "K6", "K7", "K8"]
WALL = 240
BUILD_BOUND = 1500
SEC = 600_000

AAI = "No AssemblyAI API key is set. Set one in Frame Job ▸ Settings… ▸ Transcription."
ANTHROPIC = "No Anthropic API key is set. Set one in Frame Job ▸ Settings… ▸ Assistant."
BASE = "Remove Filler Words…"
SUFFIXED = BASE + " (needs your AssemblyAI key)"

MK = "app/Sources/ModelKeys.swift"
FS = "app/Sources/FillerSheetController.swift"
TC = "app/Sources/TranscribeSheetController+Cloud.swift"
AF = "app/Sources/AgentServer+Fillers.swift"
PA = "app/Sources/AgentServer+Parity.swift"
MEMO = """    static var presenceMemo: [ModelKey: Bool] = [:]
    static func present(
        _ key: ModelKey, store: (any SecretStore)? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        if let kept = presenceMemo[key] { return kept }
        let answer = presentFresh(key, store: store, environment: environment)
        presenceMemo[key] = answer
        return answer
    }
    static func presentFresh(
"""
# name: (kind, the rows it must fail, [(file, before, after), ...])
MUTANTS = {
    "present-ignores-environment": ("app", ["K2"], [(
        MK, "store: store ?? AssemblyAIConfiguration.store(), environment: environment)",
        "store: store ?? AssemblyAIConfiguration.store(), environment: [:])")]),
    "credential-before-ready": ("app", ["K1"], [(
        AF, "        var result: [String: Any]\n        if context.ready {",
        "        var result: [String: Any]\n        try ModelKeys.require(.assemblyAI)\n"
        "        if context.ready {")]),
    "presence-memo": ("probe", ["K4"], [(MK, "    static func present(\n", MEMO)]),
    "no-transcript-arm": ("app", ["K5"], [(
        FS, "                && !FillerTranscriptPresence.any(in: document) ? .assemblyAI : nil",
        "                ? .assemblyAI : nil")]),
    "control-tooltip-unset": ("probe", ["K6", "K4b"], [(
        MK, "        control.toolTip = missing.map(sentence)\n", "")]),
    "item-suffix-kept": ("probe", ["K3"], [(
        MK, 'let title = baseTitle(item.title) + (missing?.titleSuffix ?? "")',
        'let title = item.title + (missing?.titleSuffix ?? "")')]),
    "start-missing-nil": ("probe", ["K6"], [(
        TC, "missing: !hasCredential && !reusable ? .assemblyAI : nil", "missing: nil")]),
    "settings-unobserved": ("probe", ["K4b"], [(
        MK, "forName: SettingsWindowController.didChangeNotification, object: nil, queue: nil",
        'forName: Notification.Name("FrameJobKeysProofUnobserved"), object: nil, queue: nil')]),
    "no-clause-test": ("probe", ["K7"], [(
        PA, "                if !description.contains(row.key.catalogClause) "
            "{ unclaused.append(name) }\n", "")]),
    "memo-without-folder-date": ("probe", ["K5p"], [(
        FS, "memo.key.stamp == key.stamp", "true")]),
    "no-menu-reset": ("probe", ["K3b"], [(
        MK, "        clearSatisfiedMarks(in: NSApp?.mainMenu)\n", "")]),
}


class Rows:
    def __init__(self):
        self.results = {}

    def score(self, row, ok, detail):
        if row in self.results:
            was_ok, was = self.results[row]
            self.results[row] = (was_ok and bool(ok), f"{was} | {detail}")
        else:
            self.results[row] = (bool(ok), detail)


# --------------------------------------------------------------------------
# The probe


def mutate(name, dest):
    """`dest` is a copy root holding `app/Sources` (a probe mutant) or a tree
    copy (an app mutant); the mutant's edits applied, or why not."""
    for file, before, after in MUTANTS[name][2]:
        path = dest / file
        text = path.read_text() if path.exists() else ""
        if text.count(before) != 1:
            return f"{file}: `{before}` found {text.count(before)} times"
        path.write_text(text.replace(before, after))
    return None


def build_probe(sources, here):
    """(binary, None) or (None, why)."""
    entry = here / "main.swift"
    shutil.copyfile(PROBE, entry)
    binary = here / "keys-probe"
    try:
        swift_build.build(sources=swift_build.app_sources(sources) + [entry], output=binary,
                          defines=["FRAMEJOB_DEV_TOOLS"])
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + "; ".join([str(error)] + list(error.diagnostics[:8]))
    return binary, None


def probe(binary, here):
    """The rows the probe answered, or None and why."""
    secrets = here / "secrets"
    shutil.rmtree(secrets, ignore_errors=True)
    secrets.mkdir()
    os.chmod(secrets, 0o700)
    env = dict(os.environ)
    env.pop("RC_ASSEMBLYAI_KEY", None)
    env.pop("ANTHROPIC_API_KEY", None)
    try:
        result = subprocess.run([str(binary), str(SPEECH), "-RCSecretFolder", str(secrets)],
                                capture_output=True, text=True, timeout=WALL, cwd=here, env=env,
                                stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return None, f"no answer within {WALL} s"
    (here / "stderr.txt").write_text(result.stderr)
    try:
        return json.loads(result.stdout.strip().splitlines()[-1])["rows"], None
    except (ValueError, KeyError, IndexError):
        return None, f"no answer (exit {result.returncode}): {result.stderr[-300:]}"


def probe_rows(results, wanted, mutant):
    here = WORK / (f"mutant-{mutant}" if mutant else "tree")
    if here.exists():
        shutil.rmtree(here)
    here.mkdir(parents=True)
    sources = ROOT / "app/Sources"
    if mutant:
        shutil.copytree(ROOT / "app/Sources", here / "app/Sources")
        why = mutate(mutant, here)
        if why:
            return f"the control could not be performed — {why}"
        sources = here / "app/Sources"
    binary, why = build_probe(sources, here)
    if binary is None:
        if mutant:
            return f"the control could not be performed — the copy did not build: {why}"
        for row in wanted:
            results.score(row, False, f"the probe did not build: {why}")
        return None
    if not SPEECH.exists():
        answers, why = None, "media/speech.mov is missing"
    else:
        answers, why = probe(binary, here)
    for row in wanted:
        answer = next((a for a in answers or [] if a.get("id") == row), None)
        if answer is None:
            results.score(row, False, f"no row: {why or 'the probe did not answer it'}")
        else:
            results.score(row, answer.get("pass") is True, answer.get("detail", ""))
    return None


# --------------------------------------------------------------------------
# The app rows


def listed(session, path):
    """The perform_menu_item listing's entry for `path`, or None."""
    items = session.op("perform_menu_item").get("items") or []
    return next((i for i in items if i.get("path") == path), None)


def open_sheet(session, path):
    """Runs the item and polls (≤ 10 s) for a sheet; whether one came, then
    cancels it."""
    session.op("perform_menu_item", path=path)
    began = time.monotonic()
    up = False
    while time.monotonic() - began < 10:
        listing = session.op("perform_menu_item")
        if (listing.get("window") or {}).get("sheet") is not None:
            up = True
            break
        time.sleep(0.1)
    if up:
        session.op("cancel_sheet")
        time.sleep(0.3)
    return up


def complaints(cloud, instance):
    log = cloud.read(instance.log).decode("utf-8", "replace")
    return [line for line in log.splitlines() if "Frame Job: " in line]


def app_rows(results, wanted, binary, bundle):
    import cloud_captions_proof as cloud
    import cloud_captions_probe

    os.makedirs(cloud.WORK, exist_ok=True)
    WORK.mkdir(parents=True, exist_ok=True)
    state = {}

    def run(row, body):
        if row not in wanted:
            return
        try:
            ok, detail = body()
        except Exception as problem:  # noqa: BLE001 — a row's throw is its answer
            ok, detail = False, f"{type(problem).__name__}: {problem}; " + \
                traceback.format_exc(limit=2).splitlines()[-1]
        results.score(row, ok, detail)

    class Opened(cloud.Session):
        """A Session on a package that exists, opened rather than made."""

        def __init__(self, instance, path):  # noqa: super is deliberately not called
            self.instance = instance
            self.mcp = instance.mcp
            self.path = path
            self.mcp.call("open_project", path=path)

    cloud_rows = [r for r in ("K2", "K1", "K5", "K7") if r in wanted]
    if cloud_rows:
        lock, _, holder = cloud_captions_probe.hold_cloud_lock(1800)
        if lock is None:
            for row in cloud_rows:
                results.score(row, False, f"not run: the cloud instruments' lock is held by "
                              f"{holder}")
        else:
            with contextlib.closing(lock), cloud_captions_probe.Fake("keys") as fake:
                keyed = cloud.Instance("keys", fake, str(binary))
                try:
                    def k2():
                        cloud.scenario(fake, disfluent_words=cloud.DISFLUENT_WORDS)
                        session = cloud.Session(keyed, "keys-K2")
                        media = session.media_of(str(SPEECH))
                        session.add(media, at=0, duration=5 * SEC)
                        second = session.media_of(str(SECOND))
                        session.add(second, at=6 * SEC)
                        session.save()
                        session.op("set_selection", clips=[])
                        state.update(path=session.path, media=media, second=second)
                        entry = listed(session, ["Clip", BASE])
                        sheet = open_sheet(session, ["Clip", BASE])
                        mark = len(fake.log()["requests"])
                        answer = session.op("transcribe_for_fillers", media=media)
                        sent = cloud.submits({"requests": fake.log()["requests"][mark:]})
                        session.save()
                        session.op("close_project")
                        return (entry is not None and entry.get("enabled") is True and sheet
                                and len(sent) == 1 and answer.get("ready") is True,
                                f"listed {entry}; sheet opened {sheet}; submits {len(sent)}; "
                                f"ready {answer.get('ready')}, uploaded {answer.get('uploaded')}")
                    run("K2", k2)
                finally:
                    keyed.stop()
                if "K7" in wanted:
                    found = complaints(cloud, keyed)
                    results.score("K7", not found, f"keyed instance's parity lines {found[:3]}")

                if {"K1", "K5", "K7"} & set(wanted):
                    keyless = cloud.Instance("keys-keyless", fake, str(binary), key=None)
                    try:
                        def k1():
                            if "path" not in state:
                                return False, "K2's package is not available"
                            mark = len(fake.log()["requests"])
                            session = Opened(keyless, state["path"])
                            unknown = session.error("transcribe_for_fillers", media=987654)
                            second = session.error("transcribe_for_fillers",
                                                   media=state["second"])
                            ready = session.op("transcribe_for_fillers", media=state["media"])
                            captions = session.error("transcribe", engine="assemblyai")
                            heard = fake.log()["requests"][mark:]
                            want_unknown = ("transcribe_for_fillers: No media has id 987654. "
                                            "get_project lists the media; import_media adds "
                                            "a file.")
                            return (unknown == want_unknown
                                    and second == "transcribe_for_fillers: " + AAI
                                    and ready.get("ready") is True
                                    and ready.get("uploaded") == []
                                    and captions in (AAI, "transcribe: " + AAI)
                                    and not heard,
                                    f"987654 → {unknown!r}; the second media → {second!r}; "
                                    f"speech.mov ready {ready.get('ready')}, uploaded "
                                    f"{ready.get('uploaded')}; transcribe → {captions!r}; "
                                    f"stand-in requests {len(heard)}")
                        run("K1", k1)
                        with contextlib.suppress(Exception):
                            keyless.mcp.call("close_project", project=state.get("path", ""),
                                             discard=True)

                        def k5():
                            if "path" not in state:
                                return False, "K2's package is not available"
                            session = Opened(keyless, state["path"])
                            session.op("set_selection", clips=[])
                            entry = listed(session, ["Clip", BASE])
                            sheet = open_sheet(session, ["Clip", BASE])
                            session.op("close_project", discard=True)
                            fresh = cloud.Session(keyless, "keys-K5-new")
                            media = fresh.media_of(str(SPEECH))
                            fresh.add(media, at=0, duration=5 * SEC)
                            off = listed(fresh, ["Clip", SUFFIXED])
                            fresh.op("close_project", discard=True)
                            return (entry is not None and entry.get("enabled") is True and sheet
                                    and off is not None and off.get("enabled") is False,
                                    f"with a filler transcript: listed {entry}, sheet opened "
                                    f"{sheet}; with none: listed {off}")
                        run("K5", k5)
                    finally:
                        keyless.stop()
                    if "K7" in wanted:
                        found = complaints(cloud, keyless)
                        results.score("K7", not found,
                                      f"keyless instance's parity lines {found[:3]}")

    if "K8" in wanted:
        run("K8", lambda: k8(bundle))


def k8(bundle):
    import assistant_session_proof as assistant

    os.makedirs(assistant.WORK, exist_ok=True)
    folder = WORK / "secrets-k8"
    shutil.rmtree(folder, ignore_errors=True)
    folder.mkdir(parents=True)
    os.chmod(folder, 0o700)
    fake = assistant.Fake(str(WORK / "anthropic-fake"))
    app = None
    try:
        app = assistant.App("keys-K8", str(bundle), ["-RCSecretFolder", str(folder)], fake.base)
        app.connect()
        fake.scenario([])
        app.must("new_project")
        listing = app.must("perform_menu_item")
        entry = next((i for i in listing.get("items") or []
                      if i.get("path") == ["View", "Assistant"]), None)
        ok, answer = app.call("assistant_send", text="Anything.", timeout=30)
        time.sleep(0.5)
        heard = fake.log().get("requests", [])
        parity = [line for line in app.log().splitlines() if "Frame Job: " in line]
    finally:
        if app is not None:
            app.stop()
        fake.stop()
    return (entry is not None and entry.get("enabled") is True and not ok
            and answer in (ANTHROPIC, "assistant_send: " + ANTHROPIC) and not heard
            and not parity,
            f"View ▸ Assistant listed {entry}; assistant_send "
            f"{'refused' if not ok else 'TAKEN'}: {str(answer)[:120]!r}; stand-in requests "
            f"{len(heard)}; parity lines {parity[:2]}")


# --------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--only", help="comma-separated row ids")
    args = parser.parse_args()
    if os.environ.get("RC_ASSEMBLYAI_KEY") or os.environ.get("ANTHROPIC_API_KEY"):
        print("run under `env -u RC_ASSEMBLYAI_KEY -u ANTHROPIC_API_KEY`")
        return 2
    if args.mutant:
        kind, named, _ = MUTANTS[args.mutant]
        wanted = list(named)
        if kind == "app":
            wanted = sorted(set(wanted) | {"K2"}, key=ROWS.index)
    else:
        kind, named = None, []
        wanted = args.only.split(",") if args.only else list(ROWS)
    unknown = [row for row in wanted if row not in ROWS]
    if unknown:
        print("unknown row " + ", ".join(unknown))
        return 2
    others_probe = [r for r in wanted if r in PROBE_ROWS and r != "K7"]
    others_app = [r for r in wanted if r in APP_ROWS and r != "K7"]
    alone = wanted == ["K7"]
    probe_wanted = others_probe + (["K7"] if "K7" in wanted and (others_probe or alone)
                                   else [])
    app_wanted = others_app + (["K7"] if "K7" in wanted and (others_app or alone) else [])
    if kind == "probe":
        app_wanted = []
    if kind == "app":
        probe_wanted = []
    if ("K1" in app_wanted or "K5" in app_wanted) and "K2" not in app_wanted:
        app_wanted.append("K2")
    wanted = [row for row in ROWS if row in probe_wanted + app_wanted]
    results = Rows()

    if probe_wanted:
        why = probe_rows(results, probe_wanted, args.mutant if kind == "probe" else None)
        if why:
            print(f"mutant {args.mutant}: {why}")
            return 2

    if app_wanted:
        import proof_app
        binary, bundle = None, None
        if kind == "app":
            import tree_copy
            made, why = tree_copy.make_copy(str(WORK / "mutant-app"))
            if made is None:
                print(f"mutant {args.mutant}: the control could not be performed — {why}")
                return 2
            why = mutate(args.mutant, Path(made))
            if why:
                print(f"mutant {args.mutant}: the control could not be performed — {why}")
                return 2
            bundle, why = tree_copy.build_app(Path(made), BUILD_BOUND)
            if bundle is None:
                print(f"mutant {args.mutant}: the control could not be performed — the copy "
                      f"did not build: {why}")
                return 2
            binary = proof_app.executable(bundle)
        else:
            binary, bundle = proof_app.binary(), proof_app.bundle()
            try:
                proof_app.require_fresh(binary)
            except proof_app.StaleApp as stale:
                for row in app_wanted:
                    results.score(row, False, f"not run: {stale}")
                binary = None
        if binary is not None:
            if not SPEECH.exists() or not SECOND.exists():
                for row in app_wanted:
                    results.score(row, False, "media/speech.mov or media/speech.aiff is "
                                  "missing: tools/proof/README.md says how to make them")
            else:
                app_rows(results, app_wanted, binary, bundle)
        for row in app_wanted:
            if row not in results.results:
                results.score(row, False, "not scored")

    for row in wanted:
        good, detail = results.results.get(row, (False, "not scored"))
        print(f"{row} {'pass' if good else 'fail'} — {detail}")
    passed = sum(1 for row in wanted if results.results.get(row, (False,))[0])
    print(f"scores: {passed}/{len(wanted)}")
    if not args.mutant:
        return 0 if passed == len(wanted) else 1
    lost = [row for row in named if row not in results.results
            or results.results[row][1].startswith(("no row", "not run", "not scored"))]
    if lost:
        print(f"mutant {args.mutant}: the control could not be performed — "
              f"row(s) not scored: {', '.join(lost)}")
        return 2
    survived = [row for row in named if results.results[row][0]]
    if survived:
        print(f"mutant {args.mutant}: SURVIVED — {', '.join(survived)} passed")
        return 1
    print(f"mutant {args.mutant}: caught — {', '.join(named)} failed")
    return 0


if __name__ == "__main__":
    try:
        code = main()
    finally:
        cloud = sys.modules.get("cloud_captions_proof")
        if cloud is not None:
            from mcp import remove_scratch
            for scratch in cloud.SCRATCH:
                remove_scratch(scratch)
    sys.exit(code)
