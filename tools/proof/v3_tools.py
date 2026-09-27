#!/usr/bin/env python3
"""Road map 11's V3 — the two app additions the screen catalog needs, proved
against a Reelcut of its own: `select_inspector_tab` (a dev tool) and
`snapshot_ui`'s `recorder` window kind.

    python3 tools/proof/v3_tools.py [--port 4872] [--app APP] [--only L,T,R]

It launches the Release app exactly as `screens.py` does (`screens.launch`:
the same pins, an empty secret folder, the port from the log), builds the
`demo` fixture (`screens.build_fixture`) and writes its captures under
`tools/proof/work/v3_tools/<stamp>/`. It kills only the process it started.

Rows, in order: `L1` the launch and the catalog; `T1`–`T4` the tab tool;
`R1`–`R2` the recorder window. **R2 is the LAST row**: it puts up File ▸ New
Recording…, whose non-activating panel becomes key with Record as its default
button, captures it, reads its refusals and stops the instance at once; the
time from the perform's answer to the child's exit is printed as `recorder
panel up`. Rows print as `<ID> <pass|fail|skip> — <reason>`, then `scores:` and
`digest:`. Exit 0 iff no row failed.

Two deviations from the V3 spec's row text, both because a section's TITLE is
drawn by `InspectorSectionHeader.draw` (`InspectorSectionHeader.swift:139`) and
is no text field, so no layout dump ever holds `Frame Rate`, `Timing` or
`Transform`: T2 and T3 read ROW labels instead — Document's `Frame rate`,
Timing's `Reversed frames`, and Transform's `Position X` as the one that must
be gone. And T4 names the windowless-document refusal unreachable over MCP (no
tool makes a document without a window; V2a's C4 says the same)."""

import argparse
import datetime
import hashlib
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import screens  # noqa: E402
from dev_tools import DEV_TOOLS  # noqa: E402
from mcp import MCP, ToolError  # noqa: E402

WORK = os.path.join(HERE, "work", "v3_tools")
ROWS = ["L1", "T1", "T2", "T3", "T4", "R1", "R2"]
TABS = ["clip", "media", "document"]
SUBS = ["text", "shape", "graphic", "picture", "sound", "clip"]
states = {}


def score(rid, state, reason):
    states[rid] = state
    print(f"{rid} {state} — {reason}", flush=True)


class Proof:
    def __init__(self, args, out):
        self.args = args
        self.out = out
        self.child = None
        self.mcp = None
        self.demo = None
        self.ids = {}
        self.recorder_ms = None

    def tab(self, **arguments):
        return self.mcp.call_with("select_inspector_tab", dict(arguments, project=self.demo))

    def refused(self, tool, arguments):
        try:
            self.mcp.call_with(tool, arguments)
        except ToolError as error:
            return str(error)
        return None

    def select(self, *names):
        self.mcp.call("set_selection", project=self.demo, clips=[self.ids[n] for n in names])

    def snap(self, name, **arguments):
        path = os.path.join(self.out, name + ".png")
        answer = screens.v2_snapshot.snap(self.mcp, path=path, **arguments)
        screens.v2_snapshot.captures.clear()
        answer.pop("_image", None)
        data = answer.pop("_bytes", None)
        return answer, data

    def inspector(self, name):
        return self.snap(name, window="editor", view="inspector", project=self.demo)

    @staticmethod
    def visible(answer):
        views = screens.load_layout(answer)["views"]
        return {v.get("text") for v in views if not v.get("hidden")}

    # -- L1 -----------------------------------------------------------------

    def row_l1(self):
        try:
            self.child, bound = screens.launch(self.args.app, self.args.port, self.out)
        except screens.LaunchError as error:
            score("L1", "fail", f"launch: {error}")
            return False
        print(f"app: pid {self.child.pid} port {bound}", flush=True)
        notes, ok = [], True
        try:
            self.mcp = MCP(bound, timeout=180)
            deadline = time.monotonic() + 15
            welcome = False
            while time.monotonic() < deadline and not welcome:
                listing, _ = self.snap_listing()
                welcome = any(w.get("kind") == "welcome" for w in listing.get("windows", []))
                if not welcome:
                    time.sleep(0.25)
            tools = self.mcp.schemas()
            self.demo, self.ids = screens.build_fixture(self.mcp, "demo")
        except (ToolError, OSError, RuntimeError) as error:
            score("L1", "fail", f"MCP or fixture: {error}")
            return False
        alive = self.child.poll() is None
        parity = screens.parity_lines(self.out)
        marker = screens.dev_marker_count(os.path.join(self.out, "app.log"))
        names = list(tools)
        at = names.index(DEV_TOOLS[0]) if DEV_TOOLS[0] in names else len(names)
        block = names[at:at + len(DEV_TOOLS) + 1]
        schema = tools.get("select_inspector_tab", {}).get("inputSchema", {})
        props = set(schema.get("properties", {}))
        shaped = (props == {"tab", "sub_tab", "project"} and schema.get("required", []) == []
                  and "scope" not in props)
        ok = (alive and welcome and not parity and marker == len(DEV_TOOLS)
              and block == DEV_TOOLS + ["import_media"] and shaped)
        notes = [f"alive {alive}", f"welcome {welcome}", f"`Reelcut: ` lines {len(parity)}",
                 f"marker count {marker} (want {len(DEV_TOOLS)})", f"block {block}",
                 f"select_inspector_tab properties {sorted(props)} required "
                 f"{schema.get('required')}", f"fixture {sorted(self.ids)}"]
        score("L1", "pass" if ok else "fail", "; ".join(notes))
        return ok

    def snap_listing(self):
        answer = screens.v2_snapshot.snap(self.mcp)
        return answer, None

    # -- T ------------------------------------------------------------------

    def row_t1(self):
        self.select("video")
        before, a = self.inspector("t1_before")
        got = self.tab()
        after, b = self.inspector("t1_after")
        ok = (got.get("tab") == "clip" and got.get("sub_tab") == "picture"
              and got.get("sub_tabs") == ["picture", "sound", "clip"] and a == b
              and got.get("project") == self.demo)
        score("T1", "pass" if ok else "fail",
              f"{{}} answered tab {got.get('tab')!r} sub_tab {got.get('sub_tab')!r} sub_tabs "
              f"{got.get('sub_tabs')}; inspector before/after byte-identical {a == b}")

    def row_t2(self):
        got = self.tab(tab="document")
        shot, _ = self.inspector("t2_document")
        seen = self.visible(shot)
        ok = (got.get("tab") == "document" and got.get("sub_tab") is None
              and got.get("sub_tabs") == [] and "Frame rate" in seen
              and "Position X" not in seen)
        score("T2", "pass" if ok else "fail",
              f"{{tab: document}} answered {got.get('tab')!r} / {got.get('sub_tab')!r}; "
              f"dump: visible `Frame rate` {'Frame rate' in seen}, visible `Position X` "
              f"{'Position X' in seen}")

    def row_t3(self):
        first = self.tab(tab="clip")
        picked = self.tab(tab="clip", sub_tab="clip")
        shot, _ = self.inspector("t3_clip")
        seen = self.visible(shot)
        self.select("text")
        after = self.tab()
        ok = (first.get("sub_tab") == "picture" and picked.get("sub_tab") == "clip"
              and "Reversed frames" in seen and "Position X" not in seen
              and after.get("sub_tab") == "text")
        score("T3", "pass" if ok else "fail",
              f"{{tab: clip}} → {first.get('sub_tab')!r}; {{tab: clip, sub_tab: clip}} → "
              f"{picked.get('sub_tab')!r}, dump: visible `Reversed frames` "
              f"{'Reversed frames' in seen}, visible `Position X` {'Position X' in seen}; "
              f"set_selection [text] then {{}} → {after.get('sub_tab')!r}")

    def row_t4(self):
        notes, ok = [], True

        def case(label, arguments, needle, before=None):
            nonlocal ok
            state = before or self.state()
            text = self.refused("select_inspector_tab", dict(arguments, project=self.demo))
            now = self.state()
            good = text is not None and needle in text and now == state
            ok = ok and good
            notes.append(f"{label}: {'refused' if text else 'ACCEPTED'}"
                         f"{' naming it' if text and needle in text else ''}, state kept "
                         f"{now == state}")

        tabs = ", ".join(TABS)
        subs = ", ".join(SUBS)
        case("tab nope", {"tab": "nope"}, f'tab must be one of {tabs} (got "nope")')
        case("sub_tab nope", {"tab": "clip", "sub_tab": "nope"},
             f'sub_tab must be one of {subs} (got "nope")')
        case("sub_tab alone", {"sub_tab": "text"}, "sub_tab needs tab clip")
        case("sub_tab with tab document", {"tab": "document", "sub_tab": "text"},
             "sub_tab needs tab clip")
        self.select()
        case("no selection", {"tab": "clip", "sub_tab": "clip"}, "sub_tab needs a selected clip")
        self.select("text")
        self.tab(tab="document")
        case("absent sub-tab", {"tab": "clip", "sub_tab": "sound"},
             "The selection has no sound sub-tab; its sub-tabs are text, picture, clip.")
        final = self.state()
        ok = ok and final[0] == "document"
        notes.append(f"{{}} after it answers tab {final[0]!r}")
        notes.append("the windowless-document refusal (`has no window: select_inspector_tab "
                     "reaches the inspector only through its editor window`) is not reachable "
                     "over MCP")
        score("T4", "pass" if ok else "fail", "; ".join(notes))

    def state(self):
        got = self.tab()
        return (got.get("tab"), got.get("sub_tab"), tuple(got.get("sub_tabs") or []))

    # -- R ------------------------------------------------------------------

    def row_r1(self):
        text = self.refused("snapshot_ui", {"window": "recorder"})
        listing, _ = self.snap_listing()
        kinds = [w.get("kind") for w in listing.get("windows", [])]
        items = self.mcp.call("perform_menu_item", project=self.demo)["items"]
        item = next((i for i in items if i["path"] == screens.NEW_RECORDING), None)
        ok = (text is not None and "not open" in text and "recorder" not in kinds
              and item is not None and item.get("verdict") == "window")
        score("R1", "pass" if ok else "fail",
              f"snapshot_ui {{window: recorder}}: {(text or 'ACCEPTED')[:90]!r}; listing kinds "
              f"{kinds}; New Recording… verdict {item and item.get('verdict')!r}")

    def row_r2(self):
        answer = self.mcp.call("perform_menu_item", project=self.demo, path=screens.NEW_RECORDING)
        up = time.monotonic()
        notes, ok = [], True
        try:
            shot, _ = self.snap("r2_recorder", window="recorder")
            opened = [w for w in answer.get("windows_opened", []) if w.get("kind") == "recorder"]
            scale = shot.get("scale") or 0
            points = shot.get("points") or [0, 0]
            sized = (shot.get("width_px") == round(points[0] * scale)
                     and shot.get("height_px") == round(points[1] * scale))
            with_project = self.refused("snapshot_ui", {"window": "recorder",
                                                        "project": self.demo})
            with_view = self.refused("snapshot_ui", {"window": "recorder", "view": "toolbar"})
            items = self.mcp.call("perform_menu_item", project=self.demo)["items"]
            titled = any(i["path"] == screens.NEW_RECORDING for i in items)
            facts = shot.get("window_facts") or {}
            ok = (len(opened) == 1 and sized and with_project is not None
                  and "project" in with_project and with_view is not None
                  and "view" in with_view and titled)
            notes = [f"windows_opened recorder rows {len(opened)}",
                     f"{shot.get('width_px')}×{shot.get('height_px')} px = {points} pt × "
                     f"{scale}: {sized}",
                     f"with project: {(with_project or 'ACCEPTED')[:70]!r}",
                     f"with view: {(with_view or 'ACCEPTED')[:70]!r}",
                     f"listing still titles New Recording… {titled}",
                     f"panel key {facts.get('key')} active {facts.get('active')} (not scored)"]
        except (ToolError, OSError, RuntimeError, KeyError) as error:
            ok = False
            notes.append(f"threw: {error}")
        screens.stop(self.child)
        self.recorder_ms = int(round((time.monotonic() - up) * 1000))
        score("R2", "pass" if ok else "fail", "; ".join(notes))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=4872)
    parser.add_argument("--app", default=screens.DEFAULT_APP)
    parser.add_argument("--only")
    args = parser.parse_args()
    args.app = os.path.abspath(args.app)
    only = set(args.only.replace(" ", "").split(",")) if args.only else set("LTR")
    only.add("L")
    selected = [rid for rid in ROWS if rid[0] in only]
    out = os.path.join(WORK, datetime.datetime.now().strftime("%Y-%m-%d-%H%M%S"))
    os.makedirs(out, exist_ok=True)

    proof = Proof(args, out)
    try:
        if proof.row_l1():
            for rid in selected[1:]:
                try:
                    getattr(proof, "row_" + rid.lower())()
                except (ToolError, OSError, RuntimeError, KeyError) as error:
                    score(rid, "fail", f"threw: {error}")
    finally:
        if proof.child is not None:
            screens.stop(proof.child)

    for rid in selected:
        if rid not in states:
            score(rid, "fail", "the row was never scored")
    if proof.recorder_ms is not None:
        print(f"recorder panel up: {proof.recorder_ms} ms")
    counts = {s: sum(1 for rid in selected if states[rid] == s) for s in ("pass", "fail", "skip")}
    print(f"scores: {counts['pass']} pass, {counts['fail']} fail, {counts['skip']} skip of "
          f"{len(selected)}")
    digest = hashlib.sha256("\n".join(sorted(f"{rid}={states[rid]}" for rid in selected))
                            .encode()).hexdigest()
    print(f"digest: {digest}")
    print(f"out: {out}")
    return 1 if counts["fail"] else 0


if __name__ == "__main__":
    sys.exit(main())
