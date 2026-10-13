"""The dev tools (road map 11, spec §11 V-1..V-3; road map 12 A1), named once
for every proof.

A dev tool is compiled only under `FRAMEJOB_DEV_TOOLS` (Debug and Release, never
Distribution), so a Release catalog holds the PRODUCT tools plus these and a
Distribution one holds the product tools alone. A script that asserts an exact
set of tools subtracts `DEV_TOOLS` first; `op_argument_proof.py` counts them
apart.

`DEV_TOOLS` is in catalog order: `devTools()` in `AgentServer+DevTools.swift`
splices its rows in immediately before `import_media`, the first file tool:
`snapshot_ui` (road map 11's V2a), then `perform_menu_item` and `cancel_sheet`
(V2b), then `select_inspector_tab` (V3), then `assistant_send` and
`assistant_answer` (road map 12 A1)."""

import re

DEV_TOOLS = ["snapshot_ui", "perform_menu_item", "cancel_sheet", "select_inspector_tab",
             "assistant_send", "assistant_answer"]

MARKER = re.compile(r"Frame Job agent server: framejob-dev-tools-compiled-in, (\d+) dev tools")


def dev_marker_count(log_path):
    """The dev-tool count the flag-on `devTools()` logged at startup, or None
    when the log holds no marker line (a Distribution build, or no log)."""
    try:
        with open(log_path, errors="replace") as handle:
            text = handle.read()
    except OSError:
        return None
    found = MARKER.findall(text)
    return int(found[-1]) if found else None
