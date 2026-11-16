#!/usr/bin/env python3
"""Spec §11 G-49 (#385) — a `framejob://graphic?src=…` link's rules and its
fetch, through the app's own `GraphicLink.swift`, `GraphicLinkDownload.swift`
and `GraphicLinkController.swift`. No app, no browser and no network beyond
`127.0.0.1`: the fetch rows go to `graphic_link_server.py`'s listener.

    python3 tools/proof/graphic_link_probe.py [--sources DIR] [--only IDS]
    python3 tools/proof/graphic_link_probe.py --mutant NAME | --mutants

`graphic_link_probe.swift` is built by `swift_build.build` as `main.swift`
with those three files alone and `FRAMEJOB_DEV_TOOLS` defined (the loopback
switch exists only under it), and run once, killed at 180 s.

Rows (U: no request; F: one fetch each, with small injected limits — 1 MiB,
5 s idle, 10 s in all unless said; K: the controller with a stand-in hand-off):
  B0   the probe builds.
  U1   a well-formed link parses to its source, host and file name; the
       scheme and the action match in any case.
  U2   another scheme, an https URL, a non-URL string and "" are refused.
  U2b  a link of more than 2,048 bytes is refused; one under it passes.
  U3   action `project`, an empty action and `framejob:graphic` are refused.
  U3b  a port, a user, a user and password, a fragment and a path are each
       refused in their own sentence.
  U3c  the path `/` passes.
  U4   no `src`, an empty `src`, two `src` and another key (before or after
       `src`) are each refused.
  U5   `src` of http, file, ftp, framejob, data and no scheme is refused, and
       so is one that is not plain ASCII (a non-ASCII host, a space, a
       backslash).
  U6   `src` with a user, and with a user and password, is refused.
  U7   hosts refused in `src`: IPv4 and IPv6 literals, the integer and hex
       forms, one-word names, the private suffixes, the same with a
       trailing dot or a percent escape, and a name with an empty label.
  U7b  the same hosts are refused as a redirect's address.
  U7c  `example.com`, an `xn--` name and a deep name pass; the host is shown
       lowercased.
  U8   the file's name: a plain `.fjgraphic` name kept; a traversal, a
       102-character name, a `:`, a leading dot, no extension and no name each
       give a plain name that joins no path.
  U9   `http://127.0.0.1` is refused without the switch and passes with it;
       `http://localhost`, `http://127.0.0.2`, `http://example.com` and
       `https://127.0.0.1` are refused with it.
  F1   a 200: the file's bytes equal the served bytes, in
       `<temporary directory>/FrameJobLink-<UUID>/late.fjgraphic`.
  F2   404 and 500 are refused naming the status.
  F3   a redirect to http, to an address, to credentials and to
       `http://localhost` is refused in the redirect's sentence.
  F3f  a redirect to `file:` fetches nothing: the system refuses it before
       the delegate is asked ("the connection failed: …"), else the rule does.
  F3n  (driver) the listener never saw `/never/f3`.
  F4   six redirects are refused; five then a 200 succeed.
  F5   a declared length of the cap + 1 is refused naming both sizes before a
       folder is made; exactly the cap succeeds.
  F6   an endless body with no length is cut off past the cap.
  F6c  (driver) the listener saw that connection close before its own 12 s
       end: the cut-off stops the transfer, it does not drain it. (How much
       the listener had written by then depends on the socket's buffers, so
       no size is asserted and no mutant names this row.)
  F7   headers and then nothing: refused at the idle timeout (1 s; total 6 s).
  F8   a byte every 0.3 s: refused at the total timeout (2 s; idle 1 s).
  F9   a `multipart/x-mixed-replace` answer of 40 parts is refused at its second
       part ("the server answered more than once"), and the fetch leaves no
       `FrameJobLink-*` folder in the temporary directory.
  K1   a second link during a fetch is refused at once naming the first's
       host; the first lands, and a third after it is taken.
  K2   the hand-off holds the served bytes and the host line; the folder is
       gone after its read, whether the read was taken or refused.
  K3   no refused fetch of F2–F8 left its folder behind.
  K4   the host line when a redirect changed the host.

Mutants (`--mutant`, each on a copy of `--sources`; `--mutants` runs all):
the row(s) each must fail are in `MUTANTS`. Exit (rule R): a plain run exits
0 iff every row passed; a `--mutant` run exits 1 when every named row failed
(caught), 0 when one passed (survived), 2 when the control could not be
performed. `--mutants` exits 0 iff every mutant was caught.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import graphic_link_server  # noqa: E402
import swift_build  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/graphic-link-probe"
FILES = ("GraphicLink.swift", "GraphicLinkDownload.swift", "GraphicLinkController.swift")
PROBE_ROWS = ["U1", "U2", "U2b", "U3", "U3b", "U3c", "U4", "U5", "U6", "U7", "U7b", "U7c", "U8",
              "U9", "F1", "F2", "F3", "F3f", "F4", "F5", "F6", "F7", "F8", "F9", "K1", "K2", "K3", "K4"]
ROWS = ["B0"] + PROBE_ROWS + ["F3n", "F6c"]
WALL = 180
LINK, LOAD, CONTROL = FILES

# name: (the rows it must fail, [(file, before, after), ...])
MUTANTS = {
    "any-scheme": (["U2"], [
        (LINK, "            link.scheme?.lowercased() == scheme.lowercased()\n",
         "            link.scheme != nil\n")]),
    "no-length": (["U2b"], [
        (LINK, "        guard text.utf8.count <= maxBytes else {\n"
         "            return refused(",
         "        guard text.utf8.count <= maxBytes || true else {\n"
         "            return refused(")]),
    "any-action": (["U3"], [
        (LINK, "        guard named.lowercased() == action else {",
         "        guard named.lowercased() == action || true else {")]),
    "link-extras": (["U3b"], [
        (LINK, "        guard link.user == nil, link.password == nil else {",
         "        guard link.user == nil || true else {"),
        (LINK, "        guard link.port == nil else {", "        guard link.port == nil || true else {"),
        (LINK, "        guard link.path.isEmpty || link.path == \"/\" else {",
         "        guard link.path.isEmpty || true else {"),
        (LINK, "        guard link.fragment == nil else {",
         "        guard link.fragment == nil || true else {")]),
    "any-keys": (["U4"], [
        (LINK, "        if let other = items.first(where: { $0.name != \"src\" }) {",
         "        if let other = items.first(where: { $0.name != \"src\" }), false {"),
        (LINK, "        guard items.count == 1 else {", "        guard items.count >= 1 else {")]),
    "http-src": (["U5"], [
        (LINK, "        guard scheme == \"https\" else {",
         "        guard scheme == \"https\" || scheme == \"http\" else {")]),
    "credentials": (["U6"], [
        (LINK, "        guard url.user == nil, url.password == nil else {",
         "        guard url.user == nil || true else {")]),
    "any-host": (["U7", "U7b"], [
        (LINK, "        guard isPublicName(host) else {", "        guard isPublicName(host) || true else {")]),
    "empty-label": (["U7"], [
        (LINK, "labels.allSatisfy({ !$0.isEmpty && $0.count <= 63 })",
         "labels.allSatisfy({ $0.count <= 63 })")]),
    "any-file-name": (["U8"], [
        (LINK, "        else { return fallbackFileName }", "        else { return name }")]),
    "switch-any-host": (["U9"], [
        (LINK, "if policy.loopbackHTTP, scheme == \"http\", host == \"127.0.0.1\" { return nil }",
         "if policy.loopbackHTTP, scheme == \"http\" { return nil }")]),
    "any-status": (["F2"], [
        (LOAD, "        guard status == 200 else {", "        guard status == 200 || true else {")]),
    "redirect-any": (["F3", "F3n"], [
        (LOAD, "what: \"the redirect\", policy: policy) {", "what: \"the redirect\", policy: policy), false {")]),
    "redirect-count": (["F4"], [
        (LOAD, "        if redirects > limits.maxRedirects {",
         "        if redirects > limits.maxRedirects, false {")]),
    "no-declared-cap": (["F5"], [
        (LOAD, "        if response.expectedContentLength > limits.maxBytes {",
         "        if response.expectedContentLength > limits.maxBytes, false {")]),
    "no-running-cap": (["F6"], [
        (LOAD, "        if bytes > limits.maxBytes {", "        if bytes > limits.maxBytes, false {")]),
    "no-idle": (["F7"], [
        (LOAD, "        configuration.timeoutIntervalForRequest = limits.idleTimeout\n", "")]),
    "no-total": (["F8"], [
        (LOAD, "        DispatchQueue.global().asyncAfter(deadline: .now() + limits.totalTimeout, "
         "execute: timer)\n", "")]),
    "many-answers": (["F9"], [
        (LOAD, "        guard !answered else {", "        guard !answered || true else {")]),
    "no-single": (["K1"], [
        (CONTROL, "        if let fetching {", "        if let fetching, false {")]),
    "keep-temp-read": (["K2"], [
        (CONTROL, "                    try? FileManager.default.removeItem(at: fetched.folder)\n",
         "")]),
    "keep-temp-refusal": (["K3"], [
        (LOAD, "            if let folder { try? FileManager.default.removeItem(at: folder) }\n",
         "")]),
}


def build(sources, here):
    """(binary, None) or (None, why)."""
    entry = here / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/graphic_link_probe.swift", entry)
    binary = here / "graphic_link_probe"
    try:
        swift_build.build(sources=[str(sources / name) for name in FILES] + [str(entry)],
                          output=binary, defines=["FRAMEJOB_DEV_TOOLS"])
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + "; ".join(error.diagnostics[:8])
    return binary, None


def mutate(sources, name, dest):
    dest.mkdir(parents=True)
    for file in FILES:
        shutil.copyfile(sources / file, dest / file)
    for file, before, after in MUTANTS[name][1]:
        text = (dest / file).read_text()
        if text.count(before) != 1:
            return f"{file}: `{before.strip()}` found {text.count(before)} times"
        (dest / file).write_text(text.replace(before, after))
    return None


def package():
    """Bytes to serve: any bytes do, no reader runs here."""
    return b"PK\x03\x04 a stand-in package for graphic_link_probe\n" + bytes(range(256)) * 64


def probe(binary, here):
    """({row: (pass, detail)}, None) or (None, why)."""
    served = here / "served.fjgraphic"
    served.write_bytes(package())
    server = graphic_link_server.Listener({"late.fjgraphic": served.read_bytes()})
    try:
        try:
            result = subprocess.run([str(binary), str(server.port), str(served)],
                                    capture_output=True, text=True, timeout=WALL, cwd=here)
        except subprocess.TimeoutExpired:
            return None, f"no answer within {WALL} s"
        (here / "stderr.txt").write_text(result.stderr)
        try:
            rows = json.loads(result.stdout)["rows"]
        except (ValueError, KeyError, TypeError):
            return None, f"no answer (exit {result.returncode}): {result.stderr[-400:]}"
        answers = {row["id"]: (bool(row["pass"]), row["detail"]) for row in rows}
        asked = server.requests()
        never = [path for path in asked if path.startswith("/never/")]
        answers["F3n"] = (not never and any(p.startswith("/redirect") for p in asked),
                          f"{len(asked)} requests; /never asked: {never or 'no'}")
        sent = server.closed("/endless")
        answers["F6c"] = (sent is not None,
                          f"the endless body's connection closed after {sent} bytes sent")
        return answers, None
    finally:
        server.stop()


def run(sources, mutant, only):
    named = MUTANTS[mutant][0] if mutant else []
    wanted = only or (["B0"] + named if mutant else ROWS)
    here = WORK / (f"mutant-{mutant}" if mutant else "tree")
    if here.exists():
        shutil.rmtree(here)
    here.mkdir(parents=True)
    if mutant:
        why = mutate(sources, mutant, here / "Sources")
        if why:
            print(f"mutant {mutant}: the control could not be performed — {why}")
            return 2
        sources = here / "Sources"
    results = {}
    binary, why = build(sources, here)
    results["B0"] = (binary is not None, why or f"built from {sources}")
    if binary is None and mutant:
        print(f"B0 fail — {why}")
        print(f"mutant {mutant}: the control could not be performed — the copy did not build")
        return 2
    answers, why = probe(binary, here) if binary else (None, "the probe did not build")
    not_scored = []
    for row in wanted:
        if row == "B0":
            continue
        if answers is None or row not in answers:
            not_scored.append(row)
            results[row] = (False, f"no row: {why or 'the probe did not answer it'}")
        else:
            results[row] = answers[row]
    for row in wanted:
        good, detail = results[row]
        print(f"{row} {'pass' if good else 'fail'} — {detail}", flush=True)
    passed = sum(1 for row in wanted if results[row][0])
    print(f"scores: {passed}/{len(wanted)}")
    if not mutant:
        return 0 if passed == len(wanted) else 1
    lost = [row for row in named if row in not_scored]
    if lost:
        print(f"mutant {mutant}: the control could not be performed — row(s) not scored: "
              f"{', '.join(lost)}")
        return 2
    survived = [row for row in named if results[row][0]]
    if survived:
        print(f"mutant {mutant}: SURVIVED — {', '.join(survived)} passed")
        return 0
    print(f"mutant {mutant}: caught — {', '.join(named)} failed")
    return 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", type=Path, default=ROOT / "app/Sources")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--mutants", action="store_true")
    parser.add_argument("--only", help="comma-separated row ids")
    args = parser.parse_args()
    only = args.only.split(",") if args.only else None
    unknown = [row for row in only or [] if row not in ROWS]
    if unknown:
        print("unknown row " + ", ".join(unknown))
        return 2
    sources = args.sources.resolve()
    if args.mutants:
        codes = {name: run(sources, name, None) for name in MUTANTS}
        caught = [name for name, code in codes.items() if code == 1]
        print(f"mutants: {len(caught)}/{len(codes)} caught; not caught: "
              f"{ {n: c for n, c in codes.items() if c != 1} or 'none'}")
        return 0 if len(caught) == len(codes) else 1
    return run(sources, args.mutant, only)


if __name__ == "__main__":
    sys.exit(main())
