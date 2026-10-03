#!/usr/bin/env python3
"""Road map 6, spike C0 — the three rows that cost nothing: q3, q4, q7.

Everything here runs local processes, and every one of them goes through
`run_bounded`: a fixed timeout, `stdin` closed, the key REMOVED from the
child's environment, and a kill of that child's own `Popen` and nothing else.
Nobody is at this machine, so a modal (q7's whole question) has to come back
as `blocked: true` with whether `SecurityAgent` was seen — never as a hang and
never as a `pkill`.
"""

import json
import os
import plistlib
import shutil
import subprocess
import sys
import threading
import time
import http.server

import aai

PROOF = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if PROOF not in sys.path:
    sys.path.insert(1, PROOF)
import tree_copy  # noqa: E402

TARGET = ["-O", "-target", "arm64-apple-macos26.0"]
Q7_SERVICE = "com.reelcut.spike.q7"
Q7_ACCOUNT = "spike"


def child_env():
    env = dict(os.environ)
    env.pop(aai.KEY_ENV, None)
    return env


def security_agent_running():
    try:
        return subprocess.run(["pgrep", "-x", "SecurityAgent"],
                              capture_output=True, env=child_env()).returncode == 0
    except OSError:
        return False


def run_bounded(argv, timeout=20.0):
    """A child, bounded; never kills anything but its own `Popen`."""
    started = time.monotonic()
    try:
        child = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, env=child_env(), text=True)
    except OSError as error:
        return {"rc": None, "stdout": "", "stderr": f"{type(error).__name__}: {error}",
                "blocked": False, "security_agent_seen": False, "ms": 0.0}
    seen = False
    looked = 0.0
    deadline = started + timeout
    while child.poll() is None and time.monotonic() < deadline:
        time.sleep(0.05)
        if time.monotonic() - looked > 1.0:
            looked = time.monotonic()
            seen = seen or security_agent_running()
    blocked = child.poll() is None
    if blocked:
        seen = seen or security_agent_running()
        child.kill()
    try:
        out, err = child.communicate(timeout=5)
    except subprocess.TimeoutExpired:
        out, err = "", ""
    return {"rc": None if blocked else child.returncode, "stdout": out or "", "stderr": err or "",
            "blocked": blocked, "security_agent_seen": seen,
            "ms": (time.monotonic() - started) * 1000.0}


def spoken(result):
    """The one JSON object a probe prints, or what went wrong instead."""
    for line in reversed((result["stdout"] or "").strip().splitlines()):
        try:
            return json.loads(line)
        except ValueError:
            continue
    return {"ok": False, "blocked": result["blocked"],
            "error": (result["stderr"] or "no output")[-400:]}


def build(sources, out):
    """`xcrun swiftc` over the spike's own files. A refusal is the row's."""
    os.makedirs(os.path.dirname(out), exist_ok=True)
    command = ["xcrun", "swiftc"] + TARGET + list(sources) + ["-o", out]
    result = subprocess.run(command, capture_output=True, text=True, env=child_env())
    if result.returncode != 0 or not os.path.exists(out):
        return None, (result.stderr or result.stdout)[-600:]
    return out, None


def bundle(work, name, bundle_id, binary, ats):
    """An ad-hoc-signed `.app` around a probe, with or without an ATS key."""
    root = os.path.join(work, "bundles", f"{name}.app")
    tree_copy.remove_tree(root)
    os.makedirs(os.path.join(root, "Contents", "MacOS"))
    info = {"CFBundleExecutable": name, "CFBundleIdentifier": bundle_id, "CFBundleName": name,
            "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1", "LSMinimumSystemVersion": "15.0"}
    if ats:
        info["NSAppTransportSecurity"] = {"NSAllowsLocalNetworking": True}
    with open(os.path.join(root, "Contents", "Info.plist"), "wb") as handle:
        plistlib.dump(info, handle)
    executable = os.path.join(root, "Contents", "MacOS", name)
    shutil.copy2(binary, executable)
    signed = subprocess.run(["codesign", "--force", "--sign", "-", "--options", "runtime", root],
                            capture_output=True, text=True, env=child_env())
    shown = subprocess.run(["codesign", "-dvvv", root],
                           capture_output=True, text=True, env=child_env())
    text = shown.stdout + shown.stderr
    flags = cdhash = ""
    for line in text.splitlines():
        for part in line.split():
            if line.startswith("CodeDirectory") and part.startswith("flags="):
                flags = part
        if line.startswith("CDHash="):
            cdhash = line.split("=", 1)[1].strip()
    return {"app": root, "executable": executable, "flags": flags, "cdhash": cdhash,
            "sign_error": (signed.stderr or "").strip() if signed.returncode != 0 else None}


# ---- q3 — App Transport Security ------------------------------------------

class _Quiet(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *arguments):
        pass

    def do_GET(self):
        self.send_response(200)
        self.send_header("content-type", "text/plain")
        self.send_header("content-length", "2")
        self.end_headers()
        self.wfile.write(b"ok")


def q3(work, here):
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), _Quiet)
    port = server.server_address[1]
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        binary, error = build([os.path.join(here, "ats_probe.swift")],
                              os.path.join(work, "bin", "ats_probe"))
        if binary is None:
            return {"state": "failed", "reason": "ats_probe did not build",
                    "measured": {"build_error": error}}
        plain = bundle(work, "RCSpikeQ3", "com.reelcut.spike.q3", binary, ats=False)
        keyed = bundle(work, "RCSpikeQ3Keyed", "com.reelcut.spike.q3keyed", binary, ats=True)
        rows = {}
        for label, runner in (("bare", binary), ("bundle_no_key", plain["executable"]),
                              ("bundle_local_networking", keyed["executable"])):
            for host in ("127.0.0.1", "localhost"):
                answer = spoken(run_bounded([runner, f"http://{host}:{port}/"], timeout=20.0))
                rows[f"{label}/{host}"] = answer
        return {"state": "run", "reason": None, "measured": {
            "port_kind": "ephemeral loopback",
            "answers": rows,
            "signing": {"bundle_no_key": {k: plain[k] for k in ("flags", "cdhash", "sign_error")},
                        "bundle_local_networking": {k: keyed[k] for k in
                                                    ("flags", "cdhash", "sign_error")}},
            "reached": {name: ("status" in row and row.get("status") == 200)
                        for name, row in rows.items()},
        }}
    finally:
        server.shutdown()
        server.server_close()


# ---- q4 — a late audio track ----------------------------------------------

def q4(work, extract):
    if extract is None:
        return {"state": "failed", "reason": "extract did not build", "measured": {}}
    fixtures = os.path.join(work, "fixtures")
    reference = os.path.join(fixtures, "speech.wav")
    rows = {}
    for name in ("late.mov", "late.mp4"):
        path = os.path.join(fixtures, name)
        if not os.path.exists(path):
            rows[name] = {"error": "fixture missing"}
            continue
        out = os.path.join(fixtures, f"{name}.extract.wav")
        tracks = spoken(run_bounded([extract, "tracks", path], timeout=60))
        written = spoken(run_bounded([extract, "wav", path, out], timeout=120))
        lag = spoken(run_bounded([extract, "lag", reference, out, "40000"], timeout=180))
        samples = lag.get("lag_samples")
        if samples is None:
            verdict = "not measured"
        elif abs(samples - 24000) <= 534:
            verdict = "KEPT — the 1.5 s stays at the head of the extract"
        elif abs(samples) <= 534:
            verdict = "DROPPED — the extract starts at the first sample of the track"
        else:
            verdict = f"neither: the extract sits {samples} samples from the reference"
        rows[name] = {"tracks": tracks, "extract": written, "lag": lag, "verdict": verdict}
    return {"state": "run", "reason": None, "measured": rows}


# ---- q7 — the Keychain from an ad-hoc-signed bundle ------------------------

def _q7_build(work, here, label):
    folder = os.path.join(work, "bin", f"q7{label}")
    os.makedirs(folder, exist_ok=True)
    main = os.path.join(folder, "main.swift")
    # The tracked probe is compiled under the name `main.swift` because top
    # level code is only allowed there once a second file joins it, and the
    # second file is the per-build nonce that makes two cdhashes.
    shutil.copy2(os.path.join(here, "keychain_probe.swift"), main)
    nonce = f"{label}-{int(time.time() * 1000)}"
    with open(os.path.join(folder, "nonce.swift"), "w") as handle:
        handle.write(f'let buildNonce = "{nonce}"\n')
    binary, error = build([main, os.path.join(folder, "nonce.swift")],
                          os.path.join(folder, "keychain_probe"))
    return binary, error, nonce


def _q7_step(runner, mode, dp, steps, name):
    argv = [runner, mode] + (["--dp"] if dp else [])
    result = run_bounded(argv, timeout=20.0)
    answer = spoken(result)
    answer["blocked"] = result["blocked"]
    answer["security_agent_seen"] = result["security_agent_seen"]
    answer["wall_ms"] = round(result["ms"], 1)
    steps[name] = answer
    return answer


# Pre-clean, A writes, A reads twice, the REBUILT B reads twice, B deletes,
# and the item is gone: the whole of q7's question in eight subprocesses.
Q7_STEPS = [("A", "delete", "pre-clean A"), ("A", "add", "A add"),
            ("A", "read-noui", "A read-noui"), ("A", "read", "A read"),
            ("B", "read-noui", "B read-noui"), ("B", "read", "B read"),
            ("B", "delete", "B delete"), ("A", "attrs", "attrs after delete")]


def _q7_sequence(runners, dp, label, steps):
    for build_label, mode, name in Q7_STEPS:
        _q7_step(runners[build_label], mode, dp, steps, f"{label}/{name}")


def q7(work, here, save):
    """Every subprocess bounded; `measured` saved BEFORE cleanup starts."""
    builds = {}
    for label in ("A", "B"):
        binary, error, nonce = _q7_build(work, here, label)
        if binary is None:
            return {"state": "failed", "reason": f"keychain_probe {label} did not build",
                    "measured": {"build_error": error}}
        builds[label] = {"binary": binary, "nonce": nonce}
    signed = {label: bundle(work, f"RCSpikeQ7{label}", Q7_SERVICE,
                            builds[label]["binary"], ats=False) for label in ("A", "B")}
    steps = {}
    measured = {
        "cdhashes": {label: signed[label]["cdhash"] for label in ("A", "B")},
        "cdhashes_differ": bool(signed["A"]["cdhash"]) and
                           signed["A"]["cdhash"] != signed["B"]["cdhash"],
        "flags": {label: signed[label]["flags"] for label in ("A", "B")},
        "nonces": {label: builds[label]["nonce"] for label in ("A", "B")},
        "steps": steps,
        "cleanup_blocked": False,
    }
    bundled = {label: signed[label]["executable"] for label in ("A", "B")}
    bare = {label: builds[label]["binary"] for label in ("A", "B")}
    _q7_sequence(bundled, False, "signed bundle, file keychain", steps)
    _q7_sequence(bundled, True, "signed bundle, data-protection keychain", steps)
    _q7_sequence(bare, False, "bare Mach-O, file keychain", steps)
    save(measured)
    # Cleanup, bounded like everything else, and its failure is a MEASURED
    # answer that owes a person-check issue (#53) a line.
    blocked = False
    for dp in (False, True):
        step = _q7_step(bundled["A"], "delete", dp, steps, f"cleanup delete dp={dp}")
        blocked = blocked or step.get("blocked", False)
        found = _q7_step(bundled["A"], "attrs", dp, steps, f"cleanup attrs dp={dp}")
        blocked = blocked or found.get("blocked", False) or found.get("matched") is True
    if blocked:
        fallback = run_bounded(["security", "delete-generic-password",
                                "-s", Q7_SERVICE, "-a", Q7_ACCOUNT], timeout=20.0)
        steps["cleanup security fallback"] = {
            "rc": fallback["rc"], "blocked": fallback["blocked"],
            "stderr": fallback["stderr"][-200:]}
        found = _q7_step(bundled["A"], "attrs", False, steps, "cleanup attrs after fallback")
        blocked = fallback["blocked"] or found.get("blocked", False) or found.get("matched") is True
    measured["cleanup_blocked"] = bool(blocked)
    return {"state": "run", "reason": None, "measured": measured}
