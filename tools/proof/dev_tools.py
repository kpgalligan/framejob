"""The dev tools (road map 11, spec §11 V-1..V-3), named once for every proof.

A dev tool is compiled only under `REELCUT_DEV_TOOLS` (Debug and Release, never
Distribution), so a Release catalog holds the PRODUCT tools plus these and a
Distribution one holds the product tools alone. A script that asserts an exact
set of tools subtracts `DEV_TOOLS` first; `op_argument_proof.py` counts them
apart.

`DEV_TOOLS` is in catalog order: `devTools()` in `AgentServer+DevTools.swift`
splices its rows in immediately before `import_media`, the first file tool."""

import re

DEV_TOOLS = ["snapshot_ui"]

MARKER = re.compile(r"Reelcut agent server: reelcut-dev-tools-compiled-in, (\d+) dev tools")


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
