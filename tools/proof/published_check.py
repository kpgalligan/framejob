#!/usr/bin/env python3
"""The app the publish workflow is about to pack: what notarization does not look at.

`.github/workflows/publish.yml` (spec §11 PUB-1..PUB-12) archives the
Distribution configuration with a Developer ID identity, EXPORTS the archive
— which signs the app again — and runs this over the exported `Frame Job.app`
before it builds the DMG. Apple's notary refuses a missing hardened runtime,
a missing secure timestamp, `get-task-allow` and a signature that is not
Developer ID; it says nothing about the rest, and each of these ships a
broken or wrong app in a DMG that notarizes cleanly:

* the dev tools compiled in (spec §11 V-1): the wrong configuration archived;
* the app without `com.apple.security.device.audio-input` or
  `com.apple.security.device.camera`: the microphone or camera grant is
  refused however the person answers the prompt (road map 3, R0; spec §11
  CAM-3);
* the assistant helper without `com.apple.security.cs.allow-jit`: it dies at
  launch under the hardened runtime ("Ran out of executable memory");
* `framejob-mcp` missing or holding an entitlement it has no use for;
* the catalog snapshot missing, at another version than the bundle's, or
  naming a dev tool;
* the bundle's two version numbers not the ones the workflow computed;
* the updater (spec §11 PUB-6..PUB-9) broken or unsigned: Sparkle.framework
  missing or signed by another team than the app (library validation refuses
  it), a helper inside it without the hardened runtime, the feed not the one
  `project.yml` sets for Distribution, the EdDSA public key not 32 bytes of
  base64 (empty until the owner's key lands, PUB-8), or the updater's code
  not compiled in;
* the bundled encoders (spec §11 CX-4, CX-5, PUB-11) not linked in, a
  non-system library loaded, or their licence texts missing or changed;
* the acknowledgements (spec §11 PUB-10) missing a shipped component.

`make dist` runs it too, over the Distribution build and with no `--version`
or `--build` (P15 and P16 then hold the SHAPE of the two numbers), so the
instrument is run on every local Distribution build and cannot rot between
two publishes. It reads the bundle with `dist_check.py`'s own readers — the
needle, `codesign`, the snapshot — so the two scripts cannot disagree about
what a row means. It has no positive control for the needle (P3): that is
`dist_check.py`'s D4, which needs a Release bundle the workflow never builds.

Rows, none ever skipped; the last line is `published_check: <passed>/25`
and the exit is 0 only at 25/25:

* P1  the needle reads from the seam (`dist_check.read_needle`);
* P2  the app's binary exists; P3 it does not hold the needle;
* P4  the app is signed with the hardened runtime and verifies strictly;
* P5  the app's entitlements are exactly `audio-input` and `camera`;
* P6  the helper exists; P7 hardened runtime; P8 entitlements exactly
  `allow-jit`; P9 it does not hold the needle;
* P10 the MCP proxy exists; P11 hardened runtime; P12 no entitlements;
* P13 the snapshot is `{version, tools}` at the bundle's version;
* P14 the snapshot names no dev tool;
* P15 `CFBundleShortVersionString` is `--version`, or without one is two or
  three dot-separated integers;
* P16 `CFBundleVersion` is `--build`, or without one is an integer;
* P17 Sparkle.framework is present, signed with the app binary's team
  (`dist_check.sparkle_framework`, D28's check);
* P18 every other Mach-O under it is signed with the hardened runtime and
  verifies strictly (`dist_check.sparkle_helpers`, D29's);
* P19 `SUFeedURL` is Distribution's `RC_SPARKLE_FEED_URL` in `project.yml`
  (D30's);
* P20 `SUPublicEDKey` is strict base64 of exactly 32 bytes (D31's);
* P21 the binary holds `SPUStandardUpdaterController` (D33's);
* P22 the binary's bytes hold each encoder's own string literal
  (`dist_check.codec_strings`, CODEC_STRINGS). Not D37's `nm -j`: the
  workflow's `xcodebuild archive` strips the executable's symbol table
  (`DEPLOYMENT_POSTPROCESSING`), so a symbol check would fail every publish,
  and a string literal survives the strip (spec §11 PUB-11). No row here
  reads `nm`;
* P23 every load command is a system library or Sparkle's
  (`dist_check.system_loads`, D39's);
* P24 the bundle holds every pin's licence texts, byte-identical to the
  checkout's `build/codecs/licenses/` (`dist_check.codec_licences`, D41's);
* P25 `Contents/Resources/Acknowledgements.txt` names every shipped crate, npm
  package, pin, Sparkle, Bun, the model and each font
  (`dist_check.acknowledgements`, D43's; `cargo metadata --offline` relies on
  the archive having fetched the crates).

Made to fail on purpose: `tools/proof/README.md`'s section for this script.

    python3 tools/proof/published_check.py --app APP [--version V --build N]
"""

import argparse
import os
import plistlib
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dist_check  # noqa: E402  (its readers; its rows are not run)

TOTAL = 25
SHORT_VERSION = re.compile(r"^[0-9]+\.[0-9]+(\.[0-9]+)?$")
BUILD = re.compile(r"^[0-9]+$")

passed = 0
failed = 0


def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print(f"  ok   {name}")
    else:
        failed += 1
        print(f"  FAIL {name}" + (f"\n       {detail}" if detail else ""))


def info_strings(app):
    """(CFBundleShortVersionString, CFBundleVersion, ""), or (None, None, the reason)."""
    path = os.path.join(app, dist_check.INFO_PLIST)
    try:
        with open(path, "rb") as handle:
            info = plistlib.load(handle)
    except Exception as error:  # OSError or a plist that does not parse
        return None, None, f"{path}: {type(error).__name__}: {error}"
    if not isinstance(info, dict):
        return None, None, f"{path} is not a dictionary"
    return info.get("CFBundleShortVersionString"), info.get("CFBundleVersion"), ""


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--app", required=True, help="the Frame Job.app about to be packed")
    parser.add_argument("--version", help="the CFBundleShortVersionString it must carry")
    parser.add_argument("--build", help="the CFBundleVersion it must carry")
    arguments = parser.parse_args()
    app = arguments.app

    needle, needle_reason = dist_check.read_needle()
    print("spec §11 PUB-4, PUB-6..PUB-11 — the app about to be packed: no dev tools, each "
          "binary's entitlements, the MCP proxy and its snapshot, the version numbers, the "
          "updater, the encoders and the acknowledgements\n")
    print(f"  needle: {needle.decode('ascii') if needle else '(none)'}")
    print(f"  app:    {os.path.abspath(app)}\n")

    check("P1 the needle is one bare devToolsMarker line, ASCII, at least "
          f"{dist_check.MIN_BYTES} bytes", needle is not None, needle_reason)
    binary, where = dist_check.read_binary(app)
    check("P2 the app's binary exists", binary is not None, where)
    name = "P3 the app's binary does not hold the needle"
    if needle is None:
        check(name, False, "no needle (P1)")
    elif binary is None:
        check(name, False, "no binary (P2)")
    else:
        count = binary.count(needle)
        check(name, count == 0, f"{count} occurrences in {where}")
    name = "P4 the app is signed with the hardened runtime and verifies strictly"
    if binary is None:
        check(name, False, "no binary (P2)")
    else:
        ok, detail = dist_check.helper_runtime(os.path.realpath(where))
        check(name, ok, "" if ok else detail)
    name = ("P5 the app's entitlements are exactly com.apple.security.device.audio-input and "
            "com.apple.security.device.camera")
    if binary is None:
        check(name, False, "no binary (P2)")
    else:
        ok, detail = dist_check.entitlements(os.path.realpath(where),
                                             dist_check.APP_ENTITLEMENTS)
        check(name, ok, detail)

    helper, helper_where = dist_check.read_helper(app)
    check("P6 the helper exists", helper is not None, helper_where)
    name = "P7 the helper is signed with the hardened runtime"
    if helper is None:
        check(name, False, "no helper (P6)")
    else:
        ok, detail = dist_check.helper_runtime(helper_where)
        check(name, ok, "" if ok else detail)
    name = "P8 the helper's entitlements are exactly com.apple.security.cs.allow-jit"
    if helper is None:
        check(name, False, "no helper (P6)")
    else:
        ok, detail = dist_check.helper_entitlements(helper_where)
        check(name, ok, detail)
    name = "P9 the helper does not hold the needle"
    if needle is None:
        check(name, False, "no needle (P1)")
    elif helper is None:
        check(name, False, "no helper (P6)")
    else:
        count = helper.count(needle)
        check(name, count == 0, f"{count} occurrences in {helper_where}")

    proxy = os.path.join(app, dist_check.PROXY)
    held = os.path.isfile(proxy)
    check("P10 the MCP proxy exists", held, f"{proxy}: no such file")
    name = "P11 the MCP proxy is signed with the hardened runtime"
    if not held:
        check(name, False, "no MCP proxy (P10)")
    else:
        ok, detail = dist_check.helper_runtime(proxy)
        check(name, ok, "" if ok else detail)
    name = "P12 the MCP proxy holds no entitlements"
    if not held:
        check(name, False, "no MCP proxy (P10)")
    else:
        ok, detail = dist_check.proxy_entitlements(proxy)
        check(name, ok, detail)

    short, build, why = info_strings(app)
    names, version, snapshot_where = dist_check.read_snapshot(app)
    name = "P13 the snapshot is {version, tools} at the bundle's version, every tool named"
    if names is None:
        check(name, False, snapshot_where)
    elif not isinstance(short, str):
        check(name, False, why or "no string CFBundleShortVersionString")
    else:
        check(f"{name} ({len(names)} tools, {version})", version == short,
              f"version {version!r} in {snapshot_where}; the bundle's is {short!r}")
    dev, dev_reason = dist_check.dev_names()
    name = "P14 the snapshot names no dev tool"
    if dev is None:
        check(name, False, dev_reason)
    elif names is None:
        check(name, False, f"no readable snapshot (P13): {snapshot_where}")
    else:
        found = [tool for tool in dev if tool in names]
        check(name, not found, f"holds {found} in {snapshot_where}")

    if arguments.version is not None:
        check(f"P15 CFBundleShortVersionString is {arguments.version}",
              short == arguments.version, why or f"it is {short!r}")
    else:
        check(f"P15 CFBundleShortVersionString is two or three integers ({short})",
              isinstance(short, str) and SHORT_VERSION.match(short) is not None,
              why or f"it is {short!r}")
    if arguments.build is not None:
        check(f"P16 CFBundleVersion is {arguments.build}", build == arguments.build,
              why or f"it is {build!r}")
    else:
        check(f"P16 CFBundleVersion is an integer ({build})",
              isinstance(build, str) and BUILD.match(build) is not None,
              why or f"it is {build!r}")

    ok, detail = dist_check.sparkle_framework(app)
    check("P17 the app holds Sparkle.framework, signed with the app's team",
          ok, "" if ok else detail)
    ok, detail = dist_check.sparkle_helpers(app)
    check("P18 every helper in Sparkle.framework is signed with the hardened runtime"
          + (f" ({detail})" if ok else ""), ok, "" if ok else detail)
    want, want_reason = dist_check.feed_url()
    keys, keys_where = dist_check.updater_keys(app)
    name = "P19 SUFeedURL is Distribution's RC_SPARKLE_FEED_URL"
    if want is None:
        check(name, False, want_reason)
    elif keys is None:
        check(name, False, keys_where)
    else:
        check(name, keys["SUFeedURL"] == want,
              f"SUFeedURL {keys['SUFeedURL']!r} in {keys_where}; project.yml's is {want!r}")
    name = "P20 SUPublicEDKey is base64 of exactly 32 bytes"
    if keys is None:
        check(name, False, keys_where)
    else:
        ok, detail = dist_check.public_key_ok(keys["SUPublicEDKey"])
        check(name, ok, detail)
    name = "P21 the app's binary holds SPUStandardUpdaterController"
    if binary is None:
        check(name, False, "no binary (P2)")
    else:
        count = binary.count(dist_check.UPDATER_NEEDLE)
        check(name, count > 0, f"0 occurrences in {where}")

    name = ("P22 the app's binary holds each encoder's own string ("
            + " and ".join(needle.decode("ascii") for needle in dist_check.CODEC_STRINGS) + ")")
    if binary is None:
        check(name, False, "no binary (P2)")
    else:
        ok, detail = dist_check.codec_strings(where)
        check(name, ok, detail)
    name = "P23 every load command is a system library or Sparkle's"
    if binary is None:
        check(name, False, "no binary (P2)")
    else:
        ok, detail = dist_check.system_loads(where)
        check(f"{name} ({detail})" if ok else name, ok, "" if ok else detail)
    ok, detail = dist_check.codec_licences(app)
    check("P24 the bundle holds the encoders' licence texts" + (f" ({detail})" if ok else ""),
          ok, "" if ok else detail)
    ok, detail = dist_check.acknowledgements(app)
    check("P25 Acknowledgements.txt names every shipped crate, npm package, pin, Sparkle, Bun, "
          "the model and each font" + (f" ({detail})" if ok else ""), ok, "" if ok else detail)

    print(f"\npublished_check: {passed}/{TOTAL}")
    return 0 if passed == TOTAL else 1


if __name__ == "__main__":
    sys.exit(main())
