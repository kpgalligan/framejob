#!/usr/bin/env python3
"""Find in the Transcript tab (#434, spec §11 TX-37…TX-39): Edit ▸ Find… ⌘F,
its bar, its marks and the dev tool `transcript_view`'s `find` / `find_step`.

    python3 tools/proof/transcript_find_proof.py [--only IDS]
    python3 tools/proof/transcript_find_proof.py --mutant NAME
    python3 tools/proof/transcript_find_proof.py --mutants

Run it under `env -u RC_ASSEMBLYAI_KEY`: no row spends anything. The package,
the fixtures (TX1's `say` phrases) and the launch are `transcript_tab_proof.py`'s.

Probe rows (`transcript_find_probe.swift`, built through `swift_build.build()`
with `-D FRAMEJOB_DEV_TOOLS`, the app's `Compositor.metal` beside it): F0
builds; F1–F13 as its header says.

App rows (the app `proof_app` chooses; `RC_PROOF_APP=release` for the record):
  Z0  no `Frame Job: ` line; `transcript_view` takes exactly its ten earlier
      arguments plus `find` and `find_step`.
  A1  on the Clip tab `perform_menu_item ["Edit","Find…"]` is refused as
      disabled; on Transcript it runs and `find` answers open, the field first
      responder, no matches for an empty field.
  A2  the commonest word, upper-cased, as the query: `matches` equal the same
      rule computed here from `tokens`; `current` is the first at or after
      `highlight`; `next` advances and wraps, `previous` returns; the range,
      the selection, the playhead and the undo list are as before;
      `current_visible`; `find_step` with the bar closed is refused;
      `find: null` answers null.
  A3  two adjacent tokens' texts as a phrase are found; the last token of one
      paragraph with the first of the next is not found there.
  A4  with the bar open, `ripple_delete_ranges` over the first matched word's
      cut: after the rebuild the matches equal this rule over the new tokens,
      one fewer.
  A5  `screens.py --only 11d-transcript-find` exits 0 with "new problems: 0".

Mutants (`--mutant NAME`, or all with `--mutants`): each anchor occurs once; a
mutant is caught when every row it names fails. All fourteen are probe mutants
(a copy of `app/Sources` with the edit); TX-39 says why there are fourteen.
  return-leaves         K-4 takes Return from the find field (F4)
  across-paragraphs     paragraphs joined by a space (F1)
  case-sensitive        the comparison options dropped (F1)
  anchor-ignored        the current match always the first (F3)
  find-selects          stepping to a match selects it (F4)
  close-keeps-keys      closing leaves the keys in the hidden field (F5)
  follow-while-finding  the follow not paused by the bar (F8)
  stale-after-rebuild   the matches not recomputed on a rebuild (F7)
  find-measures-all     every match measured at draw (F10)
  always-enabled        the validator arm removed (F2)
  hide-keeps-bar        hiding the tab leaves the bar open (F9)
  view-esc-passes       Esc in the text does not close the bar (F6)
  reveal-on-estimate    the current match scrolled to where an estimate puts
                        it, the text above not laid out (F10)
  keys-left-behind      leaving the tab does not hand the keys back (F13)

Exit: 0 iff every row passed (a mutant run: 0 when caught, 1 when it survived,
2 when the control could not be performed).
"""
import argparse
import contextlib
import json
import os
from pathlib import Path
import shutil
import sys
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import swift_build  # noqa: E402
import bounded  # noqa: E402 — on swift_build's path
import timeline_transcript_proof as ttp  # noqa: E402
import transcript_tab_proof as tab  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/transcript_find"
PROBE = ROOT / "tools/proof/transcript_find_probe.swift"
PROBE_ROWS = ["F0", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
              "F13"]
APP_ROWS = ["Z0", "A1", "A2", "A3", "A4"]
OTHER_ROWS = ["A5"]
ROWS = PROBE_ROWS + APP_ROWS + OTHER_ROWS
SEC = 600_000
TOOL = "transcript_view"
ARGUMENTS = ["click", "find", "find_step", "focus", "language", "project", "read", "select",
             "select_pause", "stop_after", "wait", "words_from"]

EW = "EditorWindow.swift"
FI = "TranscriptFind.swift"
PF = "TranscriptPane+Find.swift"
TP = "TranscriptPane.swift"
VF = "TranscriptView+Find.swift"
VK = "TranscriptView+Keys.swift"
EV = "EditorViewController.swift"
MUTANTS = {
    "return-leaves": (["F4"], [
        (EW, "        if keepReturn(for: event) { return }\n", "")]),
    "across-paragraphs": (["F1"], [
        (FI, '                if paragraph.firstToken > 0 { plain.append("\\n") }\n',
         '                if paragraph.firstToken > 0 { plain.append(" ") }\n')]),
    "case-sensitive": (["F1"], [
        (FI, "                    of: query, options: TranscriptFind.options,\n",
         "                    of: query, options: [],\n")]),
    "anchor-ignored": (["F3"], [
        (FI, "        return low < matches.count ? low : 0\n", "        return 0\n")]),
    "find-selects": (["F4"], [
        (PF, "        find.anchor = find.matches[next].tokens.lowerBound\n",
         "        find.anchor = find.matches[next].tokens.lowerBound\n"
         "        transcriptView.select(find.matches[next].tokens)\n")]),
    "close-keeps-keys": (["F5"], [
        (PF, "            window.makeFirstResponder(find.openedFromText ? transcriptView : "
             "window.contentView)\n", "            _ = window\n")]),
    "follow-while-finding": (["F8"], [
        (TP, "            follow: (host?.transcriptIsPlaying ?? false) && !find.isOpen)\n",
         "            follow: host?.transcriptIsPlaying ?? false)\n")]),
    "stale-after-rebuild": (["F7"], [
        (TP, "        refreshFind(keeping: found)  // the matches over the new words (TX-37 (g))\n",
         "        _ = found\n")]),
    "find-measures-all": (["F10"], [
        (VF, "        guard !findMatches.isEmpty, let shown = tokens(in: dirtyRect) else { return }\n",
         "        guard !findMatches.isEmpty, !tokenStarts.isEmpty else { return }\n"
         "        let shown = 0...(tokenStarts.count - 1)\n")]),
    "always-enabled": (["F2"], [
        (EV, "            if let answer = validateTranscriptAction(action) { return answer }\n", "")]),
    "hide-keeps-bar": (["F9"], [
        (PF, "        guard find.isOpen else { return }  // nothing to close\n",
         "        guard find.isOpen, window == nil, find.window == nil else { return }\n")]),
    "reveal-on-estimate": (["F10"], [
        (VF, "            layoutManager.ensureLayout(for: above)\n", "            _ = above\n")]),
    "keys-left-behind": (["F13"], [
        (TP, "            handBackKeys()\n", "")]),
    "view-esc-passes": (["F6"], [
        (VK, "        case 27 where !extend && onEscape?() == true: break  "
             "// the find bar closed (TX-37 (e))\n", "")]),
}


# --------------------------------------------------------------------------
# The probe


def probe_rows(results, wanted, mutant=None):
    import space_key_proof
    here = WORK / (f"mutant-{mutant}" if mutant else "tree")
    if here.exists():
        shutil.rmtree(here)
    here.mkdir(parents=True)
    sources = ROOT / "app/Sources"
    if mutant:
        shutil.copytree(ROOT / "app/Sources", here / "Sources")
        why = tab.apply_edits(MUTANTS[mutant][1], here / "Sources")
        if why:
            return why
        sources = here / "Sources"
    shader, why = space_key_proof.build_shader(str(here))
    if shader is None:
        results.score("F0", False, f"the shader: {why}")
        return None
    entry = here / "main.swift"
    shutil.copyfile(PROBE, entry)
    binary = here / "transcript-find-probe"
    try:
        swift_build.build(sources=swift_build.app_sources(sources) + [entry], output=binary,
                          defines=["FRAMEJOB_DEV_TOOLS"])
    except swift_build.SwiftBuildFailed as error:
        results.score("F0", False, "swiftc: " + "; ".join([str(error)] + list(error.diagnostics[:8])))
        return None
    results.score("F0", True, f"built from {sources}")
    ran = bounded.run([str(binary), str(tab.probe_package()), "--fonts", str(tab.FONTS)], 300,
                      cwd=str(here))
    (here / "stderr.txt").write_text(ran["stderr"])
    try:
        answers = json.loads(ran["stdout"].strip().splitlines()[-1])["rows"]
    except (ValueError, KeyError, IndexError):
        answers = []
    for row in wanted:
        if row == "F0":
            continue
        answer = next((a for a in answers if a.get("id") == row), None)
        if answer is None:
            results.score(row, False, f"no row (exit {ran['rc']}): {ran['stderr'][-300:]}")
        else:
            results.score(row, answer.get("pass") is True, answer.get("detail", ""))
    return None


# --------------------------------------------------------------------------
# TX-37 (a), (b) computed here


def expected(tokens, query):
    """The matches of `query` over `tokens` by TX-37's rule, as [first, last]
    pairs; None when the words are not plain ASCII (this twin lowercases only)."""
    text, spans, paragraph = "", [], None
    for token in tokens:
        if not token["text"].isascii():
            return None
        if spans:
            text += "\n" if token["paragraph"] != paragraph else " "
        paragraph = token["paragraph"]
        spans.append((len(text), len(text) + len(token["text"])))
        text += token["text"]
    if not query or "\n" in query or not query.isascii():
        return [] if query.isascii() else None
    low, needle, out, at = text.lower(), query.lower(), [], 0
    while True:
        found = low.find(needle, at)
        if found < 0:
            return out
        end = found + len(needle)
        at = max(end, found + 1)
        covered = [i for i, (a, b) in enumerate(spans) if a < end and b > found]
        if covered:
            out.append([covered[0], covered[-1]])


def pairs(find):
    return [[m["first"], m["last"]] for m in (find or {}).get("matches", [])]


# --------------------------------------------------------------------------
# The app rows


def app_rows(results, wanted, app_path, files):
    import assistant_session_proof as sp
    import cloud_captions_probe
    import cloud_captions_proof as cloud

    os.makedirs(cloud.WORK, exist_ok=True)
    os.makedirs(sp.WORK, exist_ok=True)
    lock, _, holder = cloud_captions_probe.hold_cloud_lock(1800)
    if lock is None:
        for row in wanted:
            results.score(row, False, f"not run: the cloud instruments' lock is held by {holder}")
        return
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

    stand_in = app = None
    with contextlib.closing(lock), cloud_captions_probe.Fake("transcript-find") as aai:
        try:
            stand_in = sp.Fake(str(WORK / "anthropic-fake"))
            app = sp.App("transcript-find", app_path,
                         ["-RCSecretFolder", tab.secret_folder(), "-RCAssemblyAIEndpoint", aai.base],
                         stand_in.base)
            app.connect()

            def view(session, **arguments):
                return session.op(TOOL, **arguments)

            def z0():
                complaints = [line for line in app.log().splitlines() if "Frame Job: " in line]
                schema = app.mcp.schemas().get(TOOL, {}).get("inputSchema", {})
                keys = sorted(schema.get("properties", {}))
                return (not complaints and keys == ARGUMENTS,
                        f"parity lines {complaints[:3]}; properties {keys}")
            run("Z0", z0)

            def session():
                """A and B on one track, 1.5 s apart: two paragraphs or more."""
                if "s" not in state:
                    s = cloud.Session(app, "find")
                    a, b = (s.media_of(str(files[n])) for n in ("A", "B"))
                    first = s.add(a, at=0)
                    s.add(b, at=s.clip(first)["duration"] + 2 * SEC)
                    state["s"] = s
                return state["s"]

            def a1():
                s = session()
                s.op("select_inspector_tab", tab="clip")
                refused = s.error("perform_menu_item", path=["Edit", "Find…"])
                s.op("select_inspector_tab", tab="transcript")
                shown = view(s, wait=60)
                s.op("perform_menu_item", path=["Edit", "Find…"])
                opened = view(s).get("find")
                closed = view(s, find=None).get("find", "absent")
                return (bool(refused) and "disabled" in refused and shown.get("find") is None
                        and isinstance(opened, dict) and opened.get("field_first_responder") is True
                        and opened.get("count") == 0 and opened.get("current") is None
                        and closed is None,
                        f"on Clip: {refused!r}; before the item find {shown.get('find')!r}; after "
                        f"{opened!r}; find: null {closed!r}")
            run("A1", a1)

            def a2():
                s = session()
                s.op("set_playhead", t=0)
                shown = view(s, wait=60, select=None)
                tokens = shown.get("tokens", [])
                texts = [t["text"] for t in tokens]
                common = max(sorted(set(texts)), key=lambda t: (sum(x.lower() == t.lower()
                                                                    for x in texts), len(t)))
                query = common.upper()
                want = expected(tokens, query)
                paragraphs = len(shown.get("paragraphs", []))
                mid = tokens[len(tokens) // 2]
                s.op("set_playhead", t=mid["start"])
                before = view(s)
                undo = s.project().get("undo")
                found = view(s, find=query).get("find") or {}
                lit = before.get("highlight") or 0
                first = next((i for i, m in enumerate(want or []) if m[0] >= lit), 0)
                count = len(want or [])
                walked = [found.get("current")]
                visible = [found.get("current_visible")]
                for _ in range(count):
                    step = view(s, find_step="next").get("find") or {}
                    walked.append(step.get("current"))
                    visible.append(step.get("current_visible"))
                back = (view(s, find_step="previous").get("find") or {}).get("current")
                after = view(s)
                closed = view(s, find=None)
                refused = s.error(TOOL, find_step="next")
                wrapped = [(first + k) % count for k in range(count + 1)] if count else []
                same = all(after.get(k) == before.get(k) for k in ("selection", "playhead", "cut"))
                project = s.project()
                return (want is not None and count >= 2 and paragraphs >= 2
                        and pairs(found) == want and found.get("count") == count
                        and found.get("query") == query and walked == wrapped
                        and back == (first - 1) % count and all(v is True for v in visible)
                        and same and project.get("undo") == undo
                        and project.get("in_out_range") is None
                        and closed.get("find", "absent") is None
                        and bool(refused) and "find_step" in refused,
                        f"query {query!r} over {len(tokens)} tokens in {paragraphs} paragraphs: "
                        f"matches {pairs(found)} (want {want}); highlight {lit}, current walked "
                        f"{walked} (want {wrapped}), previous {back}; visible {visible}; "
                        f"selection, playhead and cut unchanged {same}; undo unchanged "
                        f"{project.get('undo') == undo}; range {project.get('in_out_range')}; "
                        f"closed {closed.get('find', 'absent')!r}; step while closed {refused!r}")
            run("A2", a2)

            def a3():
                s = session()
                shown = view(s, wait=60)
                tokens = shown.get("tokens", [])
                starts = [p["first_token"] for p in shown.get("paragraphs", [])]
                if len(starts) < 2 or starts[1] < 2:
                    return False, f"paragraph starts {starts}: two paragraphs of two words needed"
                inside = f"{tokens[0]['text']} {tokens[1]['text']}"
                edge = starts[1]
                across = f"{tokens[edge - 1]['text']} {tokens[edge]['text']}"
                got_inside = pairs(view(s, find=inside).get("find"))
                got_across = pairs(view(s, find=across).get("find"))
                view(s, find=None)
                want_inside, want_across = expected(tokens, inside), expected(tokens, across)
                return (want_inside is not None and got_inside == want_inside
                        and [0, 1] in got_inside and got_across == want_across
                        and [edge - 1, edge] not in got_across,
                        f"{inside!r}: {got_inside} (want {want_inside}, with [0, 1]); across the "
                        f"break at token {edge}, {across!r}: {got_across} (want {want_across})")
            run("A3", a3)

            def a4():
                s = session()
                shown = view(s, wait=60)
                tokens = shown.get("tokens", [])
                texts = [t["text"] for t in tokens]
                query = max(sorted(set(texts)), key=lambda t: (texts.count(t), len(t)))
                opened = view(s, find=query).get("find") or {}
                before = pairs(opened)
                if not before:
                    return False, f"no match of {query!r}"
                victim = tokens[before[0][0]]
                s.op("ripple_delete_ranges", ranges=[[victim["cut_start"], victim["cut_end"]]])
                after = view(s, wait=60)
                want = expected(after.get("tokens", []), query)
                got = pairs(after.get("find"))
                view(s, find=None)
                return (want is not None and got == want and len(got) == len(before) - 1
                        and len(after.get("tokens", [])) < len(tokens)
                        and (after.get("find") or {}).get("count") == len(want),
                        f"{query!r}: {len(before)} matches; token {before[0][0]} "
                        f"({victim['text']!r}) cut: {len(tokens)} → {len(after.get('tokens', []))} "
                        f"tokens, matches {got} (want {want})")
            run("A4", a4)
        finally:
            if state.get("s") is not None:
                with contextlib.suppress(Exception):
                    state["s"].op("close_project", discard=True)
            if app is not None:
                app.stop()
            if stand_in is not None:
                stand_in.stop()


def screen_row(results):
    """A5: the screen `11d-transcript-find` captured light and dark with no
    new layout problem, on the app `proof_app` chooses."""
    import proof_app
    ran = bounded.run([sys.executable, str(ROOT / "tools/proof/screens.py"), "--only",
                       "11d-transcript-find", "--app", str(proof_app.bundle())], 900, cwd=str(ROOT))
    lines = [l for l in ran["stdout"].splitlines() if l.strip()]
    news = [l for l in lines if l.startswith("new problems:")]
    results.score("A5", ran["rc"] == 0 and news == ["new problems: 0"],
                  f"screens.py --only 11d-transcript-find rc {ran['rc']}: {lines[-4:]}")


def run_rows(wanted, mutant=None):
    results = tab.Rows()
    probe_wanted = [r for r in wanted if r in PROBE_ROWS]
    app_wanted = [r for r in wanted if r in APP_ROWS]
    if probe_wanted:
        if "F0" not in probe_wanted:
            probe_wanted = ["F0"] + probe_wanted
        why = probe_rows(results, probe_wanted, mutant)
        if why:
            return None, why
    if "A5" in wanted:
        screen_row(results)
    if app_wanted:
        import proof_app
        try:
            proof_app.require_fresh(proof_app.binary())
        except proof_app.StaleApp as stale:
            for row in app_wanted:
                results.score(row, False, f"not run: {stale}")
            return results, None
        app_rows(results, app_wanted, str(proof_app.bundle()), ttp.fixtures())
        for row in app_wanted:
            if row not in results.results and row not in results.skipped:
                results.score(row, False, "not scored")
    return results, None


def mutant_run(name):
    named, _ = MUTANTS[name]
    results, why = run_rows(list(named), mutant=name)
    if results is None:
        print(f"mutant {name}: the control could not be performed — {why}")
        return 2
    ttp.report(results, list(named))
    lost = [r for r in named if r not in results.results]
    if lost or not results.results.get("F0", (False,))[0]:
        print(f"mutant {name}: the control could not be performed — "
              f"{'not scored: ' + ', '.join(lost) if lost else 'the mutated probe did not build'}")
        return 2
    survived = [r for r in named if results.results[r][0]]
    if survived:
        print(f"mutant {name}: SURVIVED — {', '.join(survived)} passed")
        return 1
    print(f"mutant {name}: caught — {', '.join(named)} failed")
    return 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--mutants", action="store_true")
    parser.add_argument("--only", help="comma-separated row ids")
    args = parser.parse_args()
    if args.mutants:
        codes = {name: mutant_run(name) for name in MUTANTS}
        print("mutants: " + ", ".join(
            f"{n} {'caught' if c == 0 else 'SURVIVED' if c == 1 else 'NOT PERFORMED'}"
            for n, c in codes.items()))
        return 0 if all(c == 0 for c in codes.values()) else 1
    if args.mutant:
        return mutant_run(args.mutant)
    wanted = args.only.split(",") if args.only else ROWS
    unknown = [r for r in wanted if r not in ROWS]
    if unknown:
        print("unknown row " + ", ".join(unknown))
        return 2
    results, why = run_rows(wanted)
    if results is None:
        print(f"not run: {why}")
        return 1
    return 0 if ttp.report(results, [r for r in ROWS if r in wanted or r == "F0"]) else 1


if __name__ == "__main__":
    code = 2
    try:
        code = main()
    finally:
        cloud = sys.modules.get("cloud_captions_proof")
        if cloud is not None:
            from mcp import remove_scratch
            for scratch in cloud.SCRATCH:
                remove_scratch(scratch)
    sys.exit(code)
