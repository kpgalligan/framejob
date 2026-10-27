#!/usr/bin/env python3
"""The one-item Sparkle appcast the publish workflow uploads beside `FrameJob.dmg`.

Spec §11 PUB-6..PUB-9: every published release carries `appcast.xml` on its
GitHub Release, and the feed every installed copy reads is the LATEST
release's (`releases/latest/download/appcast.xml`), so the file holds one
item, this release. The workflow's "Sign the update and write the appcast"
step runs this after `stapler staple` (PUB-8: the bytes signed are the bytes
served):

    python3 tools/proof/appcast.py write --app APP --dmg DMG \\
        --sign-update PATH --key-file PATH --url URL --notes-url URL --out PATH
    python3 tools/proof/appcast.py --selftest

`write` runs Sparkle's `sign_update --ed-key-file KEY DMG`, whose one line
is `sparkle:edSignature="…" length="N"`, refuses any other output and any N
that is not the DMG's size, reads `CFBundleShortVersionString`,
`CFBundleVersion` and `LSMinimumSystemVersion` from `APP/Contents/Info.plist`,
and writes RSS 2.0 with the `sparkle` namespace: one `<item>` with a title
"Frame Job <short>", an RFC 2822 `pubDate`, `sparkle:version`,
`sparkle:shortVersionString`, `sparkle:minimumSystemVersion`,
`sparkle:fullReleaseNotesLink` (the release page; PUB-9: no inline notes)
and the signed `<enclosure>`. The key is only ever a FILE path here: it is
never read, printed or passed in argv by this script, and `sign_update`
without `--ed-key-file` would read the Keychain, so `write` always passes it
and the selftest never runs the real tool.

`--selftest` (run by `make test`), no network and no key:

* S1 — `write` with a stand-in `sign_update` printing a canned line, a
  scratch DMG of that line's length and a scratch Info.plist: every field of
  the XML reads back through `xml.etree`;
* S2 — malformed `sign_update` output is refused (`parse_signature`);
* S3 — a length other than the DMG's size is refused, and `write` then
  exits non-zero and writes no file.

The last line is `appcast selftest: <passed>/3`; the exit is 0 only at 3/3.
"""

import argparse
import email.utils
import os
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ElementTree
from xml.sax.saxutils import escape, quoteattr

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
SIGNATURE = re.compile(r'sparkle:edSignature="([A-Za-z0-9+/=]+)"\s+length="([0-9]+)"')
SIGNATURE_LOOSE = re.compile(r"sparkle:edSignature=")
BUNDLE_KEYS = ("CFBundleShortVersionString", "CFBundleVersion", "LSMinimumSystemVersion")
TIMEOUT = 300
SELFTEST_TOTAL = 3


def parse_signature(output: str, size: int) -> tuple[str, int]:
    """The EdDSA signature and length in `sign_update`'s output; ValueError unless the
    output holds exactly one `sparkle:edSignature="…" length="N"` and N is `size`."""
    matches = SIGNATURE.findall(output)
    if len(matches) != 1 or len(SIGNATURE_LOOSE.findall(output)) != 1:
        raise ValueError(f"sign_update's output holds {len(matches)} well-formed "
                         f"`sparkle:edSignature=\"…\" length=\"N\"` pairs, not one: "
                         f"{output.strip()[:300]!r}")
    signature, length = matches[0][0], int(matches[0][1])
    if length != size:
        raise ValueError(f"sign_update's length is {length}, the DMG is {size} bytes")
    return signature, length


def appcast_xml(short: str, build: str, minimum: str, url: str, notes_url: str,
                signature: str, length: int, published: str) -> str:
    """The one-item RSS 2.0 appcast."""
    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        f'<rss version="2.0" xmlns:sparkle={quoteattr(SPARKLE_NS)}>\n'
        "  <channel>\n"
        "    <title>Frame Job</title>\n"
        "    <item>\n"
        f"      <title>{escape('Frame Job ' + short)}</title>\n"
        f"      <pubDate>{escape(published)}</pubDate>\n"
        f"      <sparkle:version>{escape(build)}</sparkle:version>\n"
        f"      <sparkle:shortVersionString>{escape(short)}</sparkle:shortVersionString>\n"
        f"      <sparkle:minimumSystemVersion>{escape(minimum)}</sparkle:minimumSystemVersion>\n"
        f"      <sparkle:fullReleaseNotesLink>{escape(notes_url)}</sparkle:fullReleaseNotesLink>\n"
        f"      <enclosure url={quoteattr(url)} length={quoteattr(str(length))} "
        f'type="application/octet-stream" sparkle:edSignature={quoteattr(signature)}/>\n'
        "    </item>\n"
        "  </channel>\n"
        "</rss>\n")


def bundle_values(app):
    """(short, build, minimum) from APP/Contents/Info.plist; ValueError when one is not a
    non-empty string."""
    path = os.path.join(app, "Contents", "Info.plist")
    try:
        with open(path, "rb") as handle:
            info = plistlib.load(handle)
    except Exception as error:  # OSError or a plist that does not parse
        raise ValueError(f"{path}: {type(error).__name__}: {error}")
    if not isinstance(info, dict):
        raise ValueError(f"{path} is not a dictionary")
    values = []
    for key in BUNDLE_KEYS:
        value = info.get(key)
        if not isinstance(value, str) or not value:
            raise ValueError(f"{key} in {path} is {value!r}, not a non-empty string")
        values.append(value)
    return tuple(values)


def child_env():
    """This process's environment without either product key."""
    env = dict(os.environ)
    env.pop("ANTHROPIC_API_KEY", None)
    env.pop("RC_ASSEMBLYAI_KEY", None)
    return env


def write(arguments):
    """The `write` command: 0, or 1 with the reason on stderr and no file written."""
    try:
        short, build, minimum = bundle_values(arguments.app)
        size = os.path.getsize(arguments.dmg)
        if not os.path.isfile(arguments.key_file):
            raise ValueError(f"the key file {arguments.key_file} does not exist")
        try:
            done = subprocess.run([arguments.sign_update, "--ed-key-file", arguments.key_file,
                                   arguments.dmg], capture_output=True, text=True,
                                  timeout=TIMEOUT, env=child_env())
        except (OSError, subprocess.TimeoutExpired) as error:
            raise ValueError(f"sign_update did not run: {error}")
        if done.returncode != 0:
            raise ValueError(f"sign_update exit {done.returncode}: {done.stderr.strip()[:300]}")
        signature, length = parse_signature(done.stdout, size)
        text = appcast_xml(short, build, minimum, arguments.url, arguments.notes_url,
                           signature, length, email.utils.formatdate(usegmt=True))
        ElementTree.fromstring(text.encode("utf-8"))
        partial = arguments.out + ".partial"
        with open(partial, "w", encoding="utf-8") as handle:
            handle.write(text)
        os.replace(partial, arguments.out)
    except (OSError, ValueError, ElementTree.ParseError) as error:
        print(f"appcast: {error}", file=sys.stderr)
        return 1
    print(f"appcast: {arguments.out} — Frame Job {short} ({build}), {length} bytes")
    return 0


def write_parser():
    parser = argparse.ArgumentParser(prog="appcast.py write",
                                     description="write the one-item appcast")
    parser.add_argument("--app", required=True, help="the exported Frame Job.app")
    parser.add_argument("--dmg", required=True, help="the stapled FrameJob.dmg")
    parser.add_argument("--sign-update", required=True, help="Sparkle's sign_update")
    parser.add_argument("--key-file", required=True, help="the EdDSA private key's file")
    parser.add_argument("--url", required=True, help="the DMG's download URL")
    parser.add_argument("--notes-url", required=True, help="the release page")
    parser.add_argument("--out", required=True, help="where appcast.xml goes")
    return parser


# MARK: - selftest

CANNED_SIGNATURE = "c2VsZnRlc3Qtc2lnbmF0dXJlLW5vdC1hLXJlYWwtb25lLWp1c3QtYnl0ZXMtZm9yLXM="
CANNED_LENGTH = 4096


def stand_in(folder, line):
    """A stand-in sign_update that prints `line` and nothing else."""
    path = os.path.join(folder, "sign_update")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("#!/bin/sh\nprintf '%s\\n' " + "'" + line.replace("'", "'\\''") + "'\n")
    os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)
    return path


def scratch(folder):
    """A scratch app (Info.plist only), DMG and stand-in key file."""
    app = os.path.join(folder, "Frame Job.app")
    os.makedirs(os.path.join(app, "Contents"))
    with open(os.path.join(app, "Contents", "Info.plist"), "wb") as handle:
        plistlib.dump({"CFBundleShortVersionString": "0.2.41", "CFBundleVersion": "41",
                       "LSMinimumSystemVersion": "26.0"}, handle)
    dmg = os.path.join(folder, "FrameJob.dmg")
    with open(dmg, "wb") as handle:
        handle.write(b"\0" * CANNED_LENGTH)
    key = os.path.join(folder, "key")
    with open(key, "w", encoding="utf-8") as handle:
        handle.write("not a key")
    return app, dmg, key


def run_write(folder, line):
    """Run `write` as a child with a stand-in sign_update: (exit code, out path, stderr)."""
    app, dmg, key = scratch(folder)
    out = os.path.join(folder, "appcast.xml")
    done = subprocess.run(
        [sys.executable, os.path.abspath(__file__), "write", "--app", app, "--dmg", dmg,
         "--sign-update", stand_in(folder, line), "--key-file", key,
         "--url", "https://example.invalid/v0.2.41/FrameJob.dmg",
         "--notes-url", "https://example.invalid/tag/v0.2.41", "--out", out],
        capture_output=True, text=True, timeout=60, env=child_env())
    return done.returncode, out, done.stderr.strip()


def s1(folder):
    line = f'sparkle:edSignature="{CANNED_SIGNATURE}" length="{CANNED_LENGTH}"'
    rc, out, stderr = run_write(folder, line)
    if rc != 0:
        return False, f"write exit {rc}: {stderr}"
    root = ElementTree.parse(out).getroot()
    ns = {"sparkle": SPARKLE_NS}
    items = root.findall("./channel/item")
    if root.tag != "rss" or root.get("version") != "2.0" or len(items) != 1:
        return False, f"root {root.tag} {root.get('version')}, {len(items)} items"
    item = items[0]
    enclosure = item.find("enclosure")
    published = item.findtext("pubDate") or ""
    want = {
        "title": ("Frame Job 0.2.41", item.findtext("title")),
        "sparkle:version": ("41", item.findtext("sparkle:version", namespaces=ns)),
        "sparkle:shortVersionString":
            ("0.2.41", item.findtext("sparkle:shortVersionString", namespaces=ns)),
        "sparkle:minimumSystemVersion":
            ("26.0", item.findtext("sparkle:minimumSystemVersion", namespaces=ns)),
        "sparkle:fullReleaseNotesLink": ("https://example.invalid/tag/v0.2.41",
                                         item.findtext("sparkle:fullReleaseNotesLink",
                                                       namespaces=ns)),
        "enclosure url": ("https://example.invalid/v0.2.41/FrameJob.dmg",
                          enclosure.get("url") if enclosure is not None else None),
        "enclosure length": (str(CANNED_LENGTH),
                             enclosure.get("length") if enclosure is not None else None),
        "enclosure type": ("application/octet-stream",
                           enclosure.get("type") if enclosure is not None else None),
        "enclosure sparkle:edSignature": (
            CANNED_SIGNATURE,
            enclosure.get(f"{{{SPARKLE_NS}}}edSignature") if enclosure is not None else None),
    }
    wrong = [f"{key}: {got!r}, want {expected!r}" for key, (expected, got) in want.items()
             if got != expected]
    if email.utils.parsedate_to_datetime(published) is None:
        wrong.append(f"pubDate {published!r} is not RFC 2822")
    if wrong:
        return False, "; ".join(wrong)
    return True, f"{len(want) + 1} fields read back"


def s2(_folder):
    good = f'sparkle:edSignature="{CANNED_SIGNATURE}" length="{CANNED_LENGTH}"'
    bad = [
        "",
        "error: no key",
        f'sparkle:edSignature="{CANNED_SIGNATURE}"',
        f'length="{CANNED_LENGTH}"',
        f'sparkle:edSignature="not base64!" length="{CANNED_LENGTH}"',
        f'sparkle:edSignature="{CANNED_SIGNATURE}" length="-1"',
        good + "\n" + good,
        f'sparkle:edSignature="{CANNED_SIGNATURE}" sparkle:edSignature="x" '
        f'length="{CANNED_LENGTH}"',
    ]
    accepted = []
    for output in bad:
        try:
            parse_signature(output, CANNED_LENGTH)
            accepted.append(output)
        except ValueError:
            pass
    if accepted:
        return False, f"accepted {accepted!r}"
    try:
        parse_signature(good, CANNED_LENGTH)
    except ValueError as error:
        return False, f"the well-formed line was refused: {error}"
    return True, f"{len(bad)} malformed outputs refused, the well-formed one accepted"


def s3(folder):
    try:
        parse_signature(f'sparkle:edSignature="{CANNED_SIGNATURE}" length="{CANNED_LENGTH + 1}"',
                        CANNED_LENGTH)
        return False, "parse_signature accepted a length one over the DMG's size"
    except ValueError:
        pass
    rc, out, stderr = run_write(
        folder, f'sparkle:edSignature="{CANNED_SIGNATURE}" length="{CANNED_LENGTH - 1}"')
    if rc == 0:
        return False, "write exited 0 with a length one under the DMG's size"
    if os.path.exists(out) or os.path.exists(out + ".partial"):
        return False, f"write left {out} behind"
    return True, f"refused ({stderr[:120]})"


def selftest():
    print("spec §11 PUB-6/PUB-8 — appcast.py's selftest: the one-item appcast and the "
          "refusals\n")
    passed = 0
    for name, case in (("S1 the appcast's every field reads back", s1),
                       ("S2 malformed sign_update output is refused", s2),
                       ("S3 a length other than the DMG's size is refused", s3)):
        folder = tempfile.mkdtemp(prefix="appcast-selftest-")
        try:
            ok, detail = case(folder)
        except Exception as error:  # a broken case is a scored failure, not a crash
            ok, detail = False, f"{type(error).__name__}: {error}"
        finally:
            shutil.rmtree(folder, ignore_errors=True)
        passed += ok
        print(f"  {'ok  ' if ok else 'FAIL'} {name} — {detail}")
    print(f"\nappcast selftest: {passed}/{SELFTEST_TOTAL}")
    return 0 if passed == SELFTEST_TOTAL else 1


def main(argv):
    if argv == ["--selftest"]:
        return selftest()
    if argv[:1] == ["write"]:
        return write(write_parser().parse_args(argv[1:]))
    print(__doc__.split("\n\n")[2] if "\n\n" in __doc__ else __doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
