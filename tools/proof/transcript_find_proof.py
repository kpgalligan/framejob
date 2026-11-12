#!/usr/bin/env python3
"""Find in the Transcript tab (#434, spec §11 TX-37…TX-39): Edit ▸ Find… ⌘F,
its bar, its marks and the dev tool `transcript_view`'s `find` / `find_step`;
since #559 and #560 (TX-43…TX-47) ⌘Return selecting the current match and
Edit ▸ Find… on the Media tab; since #603 (TX-48) ⌘Return taken at the
key-equivalent door only in the key window.

    python3 tools/proof/transcript_find_proof.py [--only IDS]
    python3 tools/proof/transcript_find_proof.py --mutant NAME
    python3 tools/proof/transcript_find_proof.py --mutants

Run it under `env -u RC_ASSEMBLYAI_KEY`: no row spends anything. The package,
the fixtures (TX1's `say` phrases) and the launch are `transcript_tab_proof.py`'s.

Probe rows (`transcript_find_probe.swift`, built through `swift_build.build()`
with `-D FRAMEJOB_DEV_TOOLS`, the app's `Compositor.metal` beside it): F0
builds; F1–F16 as its header says (F14 is #558's: the click-to-clip scroll and
the follow in 27,000 words; F15 is #584's: the follow at the text's ends; F16
is #583's: the whole text laid out in idle time after a rebuild, and #593's:
the top word kept across a width change, (g) and (h); F17 is #559's: ⌘Return at
both of the window's doors, and #603's: the key-equivalent door only in the key
window, (h); F18 is #560's: Edit ▸ Find… on the Media tab).

App rows (the app `proof_app` chooses; `RC_PROOF_APP=release` for the record):
  Z0  no `Frame Job: ` line; `transcript_view` takes exactly its ten earlier
      arguments plus `find` and `find_step`, whose enum is next, previous and
      select (TX-44).
  A1  on the Clip and Document tabs `perform_menu_item ["Edit","Find…"]` is
      refused as disabled; on Transcript it runs and `find` answers open, the
      field first responder, no matches for an empty field.
  A2  the commonest word, upper-cased, as the query: `matches` equal the same
      rule computed here from `tokens`; `current` is the first at or after
      `highlight`; `next` advances and wraps, `previous` returns; the
      selection, the playhead and the cut are as before, `get_project`'s
      project and unsaved_changes unchanged and its in_out_range none;
      `current_visible`; `find_step` with the bar closed is refused;
      `find: null` answers null.
  A3  two adjacent tokens' texts as a phrase are found; the last token of one
      paragraph with the first of the next is not found there.
  A4  with the bar open, `ripple_delete_ranges` over the first matched word's
      cut: after the rebuild the matches equal this rule over the new tokens,
      one fewer.
  A5  `screens.py --only 11d-transcript-find` exits 0 with "new problems: 0".
  A6  `find_step: "select"` (TX-44): the answer's selection is the current
      match, the view first responder and the field not, the current match
      unchanged, the playhead where a click on the match's first word puts it,
      the in/out range set where there was none, and `get_project`'s project
      and unsaved_changes unchanged (no edit); refused with the bar closed.
  A7  on the Media tab of an empty project `perform_menu_item
      ["Edit","Find…"]` is refused as disabled (no find band); on the Media
      tab of the project with media it runs.

Mutants (`--mutant NAME`, or all with `--mutants`): each anchor occurs once; a
mutant is caught when every row it names fails. All forty-seven are probe
mutants (a copy of `app/Sources` with the edit); TX-39, TX-47 and TX-48 say why
there are forty-seven. F15, F16 and F17 print each letter's verdict, and the letter a mutant
fails is named beside it here: the row failing is the script's verdict, and a
record reads the named letter's own verdict too.
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
  reveal-on-estimate    `layOut(through:)` lays nothing out from the top, so a
                        scroll lands where an estimate puts it (F10, F14)
  keys-left-behind      leaving the tab does not hand the keys back (F13)
  reveal-skips-layout   `revealFind` scrolls without `layOut(through:)` (F10)
  scroll-on-estimate    `scrollToToken` scrolls without `layOut(through:)`,
                        #558's old behaviour (F14)
  follow-on-estimate    the follow scrolls without `layOut(through:)` (F14)
  no-viewport-below     `layOut(through:)` stops at the target's paragraph, so
                        the view ends there (F14)
  below-keeps-estimate  the paragraphs below the target not invalidated, so
                        they keep their estimated places (F14)
  follow-steps-at-ends  the follow's skip removed, #584's old behaviour (F15 b)
  skip-at-laid-out-end  the skip at the bottom of a view not laid out whole
                        (F15 d)
  no-idle-layout        a rebuild schedules no pass, #583's old behaviour
                        (F16 a, b, c, d)
  idle-inside-rebuild   the rebuild runs the pass itself (F16 a, d, e)
  idle-survives-rebuild scheduling does not drop the pending pass (F16 d)
  idle-loses-anchor     the pass does not scroll its anchor back (F16 c, h)
  idle-stale-anchor     the waiting anchor taken whatever was scrolled since
                        (F16 f, g4)
  resize-stays-short    a width change schedules no pass (F16 e, g2, g3, g5)
  resize-drops-anchor   a width change drops a waiting rebuild's anchor before
                        it takes one (F16 e, g5)
  resize-no-anchor      a width change takes no anchor, #593's old behaviour
                        (F16 g1, g2, g3, g5)
  resize-restore-waits  the arm does not put the word back, the pass does
                        (F16 g1)
  resize-drops-offset   the arm puts the word back at the very top, not at
                        its offset; the pass corrects it (F16 g1, g3)
  resize-on-estimate    the arm restores on estimates, nothing laid out from
                        the top (F16 g3)
  resize-viewport-stays the arm lays out through the word with the viewport
                        left where it was (F16 g1–g5)
  resize-stale-stamp    the arm's anchor stamped with the clip's y from before
                        its scroll (F16 g5)
  command-return-untaken  ⌘Return is not a kept Return (F17)
  key-equivalent-door-shut  the window's `performKeyEquivalent` takes nothing
                        (F17 a)
  key-equivalent-any-window  the door takes ⌘Return in a window that is not
                        key, #603's old behaviour (F17 h)
  key-test-after-take   the door asks for the key window after `keepReturn`
                        has acted (F17 h)
  send-event-door-shut  `sendEvent` takes Return and ⇧Return only (F17 b)
  shifted-command-taken ⌘ with ⇧ also selects (F17 f)
  select-keeps-keys     ⌘Return leaves the keys in the field (F17 a)
  select-no-seek        ⌘Return does not move the playhead (F17 a)
  select-first-word-only  a phrase selects its first word only (F17 c)
  media-arm-off         the validator's Media arm answers false (F18 a)
  media-find-unshown    the Media arm offered for a field not on screen (F18 e, f)
  media-find-no-focus   the action does not give the field the keys (F18 b)
  media-find-no-scroll  the action does not scroll the field into sight (F18 g)

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
              "F13", "F14", "F15", "F16", "F17", "F18"]
APP_ROWS = ["Z0", "A1", "A2", "A3", "A4", "A6", "A7"]
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
VH = "TranscriptView+Highlight.swift"
VL = "TranscriptView+Layout.swift"
TV = "TranscriptView.swift"
VK = "TranscriptView+Keys.swift"
EV = "EditorViewController.swift"
ET = "EditorViewController+Transcript.swift"
MP = "MediaPane.swift"
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
    "reveal-on-estimate": (["F10", "F14"], [
        (VL, "        layoutManager.ensureLayout(for: all)\n", "        _ = all\n")]),
    "reveal-skips-layout": (["F10"], [
        (VF, "        layOut(through: run)\n", "")]),
    "scroll-on-estimate": (["F14"], [
        (VL, "        layOut(through: tokenRange(index))\n", "")]),
    "follow-on-estimate": (["F14"], [
        (VH, "        layOut(through: tokenRange(valid))\n", "")]),
    "no-viewport-below": (["F14"], [
        (VL, "            return below < 0\n", "            return false\n")]),
    "below-keeps-estimate": (["F14"], [
        (VL, "        if let stale = NSTextRange(location: start, end: last) {\n",
         "        if let stale = NSTextRange(location: start, end: end) {\n")]),
    "follow-steps-at-ends": (["F15"], [
        (VH, "        if followIsAtAnEnd(valid) { return }\n", "")]),
    "skip-at-laid-out-end": (["F15"], [
        (VH, "        return wanted <= target || laidOutWhole\n", "        return true\n")]),
    "no-idle-layout": (["F16"], [
        (TV, "        scheduleWholeLayout()\n        needsDisplay = true\n",
         "        needsDisplay = true\n")]),
    "idle-inside-rebuild": (["F16"], [
        (TV, "        scheduleWholeLayout()\n        needsDisplay = true\n",
         "        layOutAll()\n        needsDisplay = true\n")]),
    "idle-survives-rebuild": (["F16"], [
        (VL, "        if let pending = wholeLayoutObserver { CFRunLoopObserverInvalidate(pending) }\n",
         "")]),
    "idle-loses-anchor": (["F16"], [
        (VL, "            scroll(to: rect.minY - anchor.offset)\n", "            _ = rect\n")]),
    "idle-stale-anchor": (["F16"], [
        (VL, "        if let kept = wholeLayoutAnchor, let clipY, abs(kept.clipY - clipY) <= 0.5 {\n",
         "        if let kept = wholeLayoutAnchor, clipY != nil {\n")]),
    "resize-stays-short": (["F16"], [
        (TV, "            laidOutWhole = false\n            scheduleWholeLayout()\n",
         "            laidOutWhole = false\n")]),
    "resize-drops-anchor": (["F16"], [
        (TV, "        let anchor = widthChanged ? standingAnchor() : nil\n",
         "        if widthChanged { wholeLayoutAnchor = nil }\n"
         "        let anchor = widthChanged ? standingAnchor() : nil\n")]),
    "resize-no-anchor": (["F16"], [
        (TV, "        let anchor = widthChanged ? standingAnchor() : nil\n",
         "        let anchor: (token: Int, offset: CGFloat)? = nil\n")]),
    "resize-restore-waits": (["F16"], [
        (TV, "                scroll(to: rect.minY - anchor.offset)\n", "                _ = rect\n")]),
    "resize-drops-offset": (["F16"], [
        (TV, "                scroll(to: rect.minY - anchor.offset)\n",
         "                scroll(to: rect.minY)\n")]),
    "resize-on-estimate": (["F16"], [
        (TV, "                scroll(to: 0)\n                layOut(through: tokenRange(anchor.token))\n",
         "                layoutViewport()\n")]),
    "resize-viewport-stays": (["F16"], [
        (TV, "                scroll(to: 0)\n                layOut(through: tokenRange(anchor.token))\n",
         "                layOut(through: tokenRange(anchor.token))\n")]),
    "resize-stale-stamp": (["F16"], [
        (TV, "        let anchor = widthChanged ? standingAnchor() : nil\n",
         "        let anchor = widthChanged ? standingAnchor() : nil\n"
         "        let staleY = enclosingScrollView?.contentView.bounds.minY ?? 0\n"),
        (TV, "                    anchor.token, anchor.offset, enclosingScrollView?.contentView.bounds.minY ?? 0\n",
         "                    anchor.token, anchor.offset, staleY\n")]),
    "keys-left-behind": (["F13"], [
        (TP, "            handBackKeys()\n", "")]),
    "view-esc-passes": (["F6"], [
        (VK, "        case 27 where !extend && onEscape?() == true: break  "
             "// the find bar closed (TX-37 (e))\n", "")]),
    "command-return-untaken": (["F17"], [
        (EW, "        return flags == .command ? .select : nil\n", "        return nil\n")]),
    "key-equivalent-door-shut": (["F17"], [
        (EW, "        if keyWindowStandIn ?? isKeyWindow, keepReturn(for: event, taking: [.select]) "
             "{ return true }\n", "")]),
    "key-equivalent-any-window": (["F17"], [
        (EW, "        if keyWindowStandIn ?? isKeyWindow, keepReturn(for: event, taking: [.select]) "
             "{ return true }\n",
         "        if keepReturn(for: event, taking: [.select]) { return true }\n")]),
    "key-test-after-take": (["F17"], [
        (EW, "        if keyWindowStandIn ?? isKeyWindow, keepReturn(for: event, taking: [.select]) "
             "{ return true }\n",
         "        if keepReturn(for: event, taking: [.select]), keyWindowStandIn ?? isKeyWindow "
         "{ return true }\n")]),
    "send-event-door-shut": (["F17"], [
        (EW, "        for event: NSEvent, taking keys: Set<KeptReturn> = [.next, .previous, .select]\n",
         "        for event: NSEvent, taking keys: Set<KeptReturn> = [.next, .previous]\n")]),
    "shifted-command-taken": (["F17"], [
        (EW, "        return flags == .command ? .select : nil\n",
         "        return flags.contains(.command) ? .select : nil\n")]),
    "select-keeps-keys": (["F17"], [
        (PF, "        window.makeFirstResponder(transcriptView)\n", "        _ = window\n")]),
    "select-no-seek": (["F17"], [
        (VK, "        onActivate?(tokens.lowerBound)\n", "")]),
    "select-first-word-only": (["F17"], [
        (VK, "        select(tokens)\n", "        select(tokens.lowerBound...tokens.lowerBound)\n")]),
    "media-arm-off": (["F18"], [
        (ET, "        return shownMediaSearch != nil\n", "        return false\n")]),
    "media-find-unshown": (["F18"], [
        (MP, "        guard let field = searchField, field.window != nil, "
             "!field.isHiddenOrHasHiddenAncestor\n", "        guard let field = searchField\n")]),
    "media-find-no-focus": (["F18"], [
        (ET, "        window.makeFirstResponder(field)\n", "        _ = window\n")]),
    "media-find-no-scroll": (["F18"], [
        (ET, "        field.scrollToVisible(field.bounds)\n", "")]),
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
                steps = schema.get("properties", {}).get("find_step", {}).get("enum")
                return (not complaints and keys == ARGUMENTS
                        and steps == ["next", "previous", "select"],
                        f"parity lines {complaints[:3]}; properties {keys}; find_step {steps}")
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
                s.op("select_inspector_tab", tab="document")
                on_document = s.error("perform_menu_item", path=["Edit", "Find…"])
                s.op("select_inspector_tab", tab="transcript")
                shown = view(s, wait=60)
                s.op("perform_menu_item", path=["Edit", "Find…"])
                opened = view(s).get("find")
                closed = view(s, find=None).get("find", "absent")
                return (bool(refused) and "disabled" in refused and shown.get("find") is None
                        and bool(on_document) and "disabled" in on_document
                        and isinstance(opened, dict) and opened.get("field_first_responder") is True
                        and opened.get("count") == 0 and opened.get("current") is None
                        and closed is None,
                        f"on Clip: {refused!r}; on Document: {on_document!r}; before the item find "
                        f"{shown.get('find')!r}; after {opened!r}; find: null {closed!r}")
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
                # `get_project`'s own keys: `project` is the model (unchanged =
                # no edit) and `in_out_range` sits beside it.
                document = s.op("get_project")
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
                document_after = s.op("get_project")
                unedited = (document_after.get("project") == document.get("project")
                            and document_after.get("unsaved_changes") == document.get("unsaved_changes"))
                ranged = document_after.get("in_out_range")
                return (want is not None and count >= 2 and paragraphs >= 2
                        and pairs(found) == want and found.get("count") == count
                        and found.get("query") == query and walked == wrapped
                        and back == (first - 1) % count and all(v is True for v in visible)
                        and same and unedited and ranged is None
                        and closed.get("find", "absent") is None
                        and bool(refused) and "find_step" in refused,
                        f"query {query!r} over {len(tokens)} tokens in {paragraphs} paragraphs: "
                        f"matches {pairs(found)} (want {want}); highlight {lit}, current walked "
                        f"{walked} (want {wrapped}), previous {back}; visible {visible}; "
                        f"selection, playhead and cut unchanged {same}; project and "
                        f"unsaved_changes unchanged {unedited}; range {ranged}; "
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

            def a6():
                s = session()
                s.op("select_inspector_tab", tab="transcript")
                s.op("set_playhead", t=0)
                shown = view(s, wait=60, select=None)
                tokens = shown.get("tokens", [])
                texts = [t["text"] for t in tokens]
                query = max(sorted(set(texts)), key=lambda t: (texts.count(t), len(t)))
                # `in_out_range` and `unsaved_changes` are `get_project`'s own
                # keys, beside `project`, which is the model (unchanged = no edit).
                before = s.op("get_project")
                opened = view(s, find=query).get("find") or {}
                stepped = view(s, find_step="next").get("find") or {}
                at = stepped.get("current")
                found_pairs = pairs(stepped)
                match = found_pairs[at] if isinstance(at, int) and at < len(found_pairs) else None
                chosen = view(s, find_step="select")
                found = chosen.get("find") or {}
                after = s.op("get_project")
                unedited = (after.get("project") == before.get("project")
                            and after.get("unsaved_changes") == before.get("unsaved_changes"))
                ranged = after.get("in_out_range")
                view(s, find=None)
                closed = s.error(TOOL, find_step="select")
                clicked = view(s, select=None, click=match[0]) if match else {}
                view(s, select=None)
                return (match is not None and len(pairs(opened)) >= 2
                        and chosen.get("selection") == match
                        and chosen.get("first_responder") is True
                        and found.get("field_first_responder") is False
                        and found.get("current") == at and pairs(found) == found_pairs
                        and chosen.get("playhead") == clicked.get("playhead")
                        and chosen.get("playhead") != shown.get("playhead")
                        and before.get("in_out_range") is None and ranged is not None and unedited
                        and bool(closed) and "find_step" in closed,
                        f"{query!r}: {len(pairs(opened))} matches, current {at} {match}; select: "
                        f"selection {chosen.get('selection')}, view first responder "
                        f"{chosen.get('first_responder')}, field {found.get('field_first_responder')}, "
                        f"current {found.get('current')}, playhead {chosen.get('playhead')} (a click "
                        f"on token {match[0] if match else None}: {clicked.get('playhead')}; before "
                        f"{shown.get('playhead')}); range {before.get('in_out_range')} → {ranged}; "
                        f"project and unsaved_changes unchanged {unedited}; with the bar closed "
                        f"{closed!r}")
            run("A6", a6)

            def a7():
                s = session()
                empty = cloud.Session(app, "find-empty")
                try:
                    empty.op("select_inspector_tab", tab="media")
                    refused = empty.error("perform_menu_item", path=["Edit", "Find…"])
                finally:
                    with contextlib.suppress(Exception):
                        empty.op("close_project", discard=True)
                s.op("select_inspector_tab", tab="media")
                ran = s.error("perform_menu_item", path=["Edit", "Find…"])
                s.op("select_inspector_tab", tab="transcript")
                return (bool(refused) and "disabled" in refused and ran is None,
                        f"an empty project's Media tab: {refused!r}; with media: "
                        f"{'ran' if ran is None else repr(ran)}")
            run("A7", a7)
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
