#!/usr/bin/env python3
"""Road map "codec-export" C0 — the bundled encoders are linked into the app
(spec §11 CX-4, CX-5).

    python3 tools/proof/codecs_proof.py [--app debug|release|PATH]

Runs the chosen app's executable (`proof_app.py`: `--app`, else `RC_PROOF_APP`,
else Debug; a build older than its inputs is refused) with `-RCCodecProbe 1`,
which `CodecLibraries.probeIfAsked()` answers before the app starts: it opens and
closes an SVT-AV1 encoder handle, prints `svt-av1 <version>` and
`libvpx <version> (<VP9 encoder name>)`, and exits 0. No window, no socket.

* L1 — exit 0 and exactly two stdout lines;
* L2 — the SVT line's version is `v` + `build_codecs.PINS`' SVT-AV1 version;
* L3 — the libvpx line's version is `v` + the libvpx pin's version, and the
  encoder's name contains "VP9 Encoder".

An instrument that cannot run is a FAIL, never an exit.
"""

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(ROOT / "tools/codecs"))
import build_codecs  # noqa: E402
import proof_app  # noqa: E402

PIN = {pin.name: pin for pin in build_codecs.PINS}
SECRET_KEYS = ("ANTHROPIC_API_KEY", "RC_ASSEMBLYAI_KEY")


def main(argv=None):
    parser = argparse.ArgumentParser(description="the bundled encoders' link (codec-export C0)")
    parser.add_argument("--app", help="debug, release or a .app or executable path "
                        "(default: RC_PROOF_APP, else debug)")
    args = parser.parse_args(argv)
    if args.app:
        os.environ[proof_app.ENV] = args.app
    rows = []

    def row(ident, ok, detail):
        rows.append(ok)
        print(f"{ident} {'ok' if ok else 'FAIL'} — {detail}", flush=True)

    lines, rc = [], None
    try:
        exe = proof_app.binary()
        proof_app.require_fresh(exe)
        env = {k: v for k, v in os.environ.items() if k not in SECRET_KEYS}
        done = subprocess.run([str(exe), "-RCCodecProbe", "1"], capture_output=True, text=True,
                              timeout=120, env=env, stdin=subprocess.DEVNULL)
        rc, lines = done.returncode, done.stdout.splitlines()
        print(f"app {exe}\nstdout {lines}\nstderr {done.stderr.strip()[-600:]!r}", flush=True)
    except (proof_app.StaleApp, ValueError, OSError, subprocess.TimeoutExpired) as error:
        row("L0", False, f"the probe could not run: {error}")

    row("L1", rc == 0 and len(lines) == 2, f"exit {rc}, {len(lines)} stdout lines")
    svt = re.fullmatch(r"svt-av1 (\S+)", lines[0]) if lines else None
    want = "v" + PIN["svt-av1"].version
    row("L2", bool(svt) and svt.group(1) == want,
        f"SVT-AV1 answers {svt.group(1) if svt else lines[:1]}, the pin {want}")
    vpx = re.fullmatch(r"libvpx (\S+) \((.+)\)", lines[1]) if len(lines) > 1 else None
    want = "v" + PIN["libvpx"].version
    row("L3", bool(vpx) and vpx.group(1) == want and "VP9 Encoder" in vpx.group(2),
        f"libvpx answers {vpx.groups() if vpx else lines[1:2]}, the pin {want}")
    print(f"{sum(rows)}/{len(rows)}")
    return 0 if rows and all(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
