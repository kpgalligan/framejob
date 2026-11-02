"""Road map "creator-jobs": a spike's rule hash and its results file (spec §11
CJ-7).

`rule_sha256(spike)` is the SHA-256 of the spike's entry in the road map's
"Every spike, with its rule": its first line, `- **<ID> —`, and every
following line that begins with two spaces, each with its newline.
`recorded(spike)` is the value CJ0a's table holds for it. `write_results`
puts `tools/proof/work/creator_spike/<ID>/results.json` down with both, the
OS build and the device.
"""

import hashlib
import json
import platform
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
ROADMAP = ROOT / "designs/creator-jobs.md"
WORK = ROOT / "tools/proof/work/creator_spike"


def rule_sha256(spike):
    lines = ROADMAP.read_text().splitlines(keepends=True)
    head = f"- **{spike} —"
    for index, line in enumerate(lines):
        if line.startswith(head):
            entry = [line]
            for following in lines[index + 1:]:
                if not following.startswith("  "):
                    break
                entry.append(following)
            return hashlib.sha256("".join(entry).encode()).hexdigest()
    raise SystemExit(f"no entry for {spike} in {ROADMAP}")


def recorded(spike):
    match = re.search(rf"^\| {re.escape(spike)} \| `([0-9a-f]{{64}})` \|$", ROADMAP.read_text(),
                      re.M)
    return match.group(1) if match else None


def sysctl(name):
    run = subprocess.run(["sysctl", "-n", name], capture_output=True, text=True)
    return run.stdout.strip()


def host():
    battery = subprocess.run(["pmset", "-g", "batt"], capture_output=True, text=True).stdout
    load = subprocess.run(["uptime"], capture_output=True, text=True).stdout.strip()
    return {"os_build": sysctl("kern.osversion"), "os": platform.mac_ver()[0],
            "device": sysctl("machdep.cpu.brand_string"), "cores": int(sysctl("hw.ncpu") or 0),
            "memory": int(sysctl("hw.memsize") or 0),
            "ac_power": "AC Power" in battery, "uptime": load}


def check_rule(spike):
    """(computed, recorded, match); a mismatch is printed first, to be recorded."""
    computed, table = rule_sha256(spike), recorded(spike)
    if computed != table:
        print(f"RULE MISMATCH {spike}: computed {computed}, the table holds {table}")
    else:
        print(f"{spike} rule_sha256 {computed} matches the table")
    return computed, table, computed == table


def write_results(spike, results, folder=None):
    """`folder` (a name under `WORK`) when a spike's rule is re-run for
    another kind (road map CO1's `CJ-S2-masks`, `CJ-S3-masks`); the rule hash
    is still `spike`'s."""
    folder = WORK / (folder or spike)
    folder.mkdir(parents=True, exist_ok=True)
    computed, table, match = check_rule(spike)
    document = {"spike": spike, "rule_sha256": computed, "rule_sha256_recorded": table,
                "rule_matches": match, **host(), **results}
    path = folder / "results.json"
    path.write_text(json.dumps(document, indent=1, sort_keys=True))
    return path
