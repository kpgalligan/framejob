#!/usr/bin/env python3
"""The documentation site (`docs/site/`) against the tree. No app, no build, no network, stdlib
only; `pnpm build` in `docs/site/` is what proves the site renders and its links land.

A user-visible change has to reach the site, and nothing about the site's build notices a menu
item or an agent tool it has never heard of. These rows do:

  D1  every page has a title and a description;
  D2  the sidebar and the pages are one-to-one;
  D3  every feature in `src/data/features.json` names a page, and an anchor that page has;
  D4  every product tool in `AgentCatalog*.swift` has a heading on an `mcp/` page, and no dev tool
      (`AgentServer+DevTools.swift`) is named anywhere;
  D5  every menu item in `AppDelegate+*Menu*.swift` and `EditorViewController+GraphicMenus.swift`
      is on a reference page;
  D6  no page names something internal: a decision ID, a road map, an `rc_*` export, a source
      file, a dev launch default;
  D7  no page or data file holds a local path;
  D8  every `<Shot>` names a capture that exists in both looks;
  D9  no page uses the words `docs/site/CLAUDE.md` bans;
  D10 every tool an `AtAGlance` names is a product tool, and every step of a menu path written on
      a page is a string in `app/Sources` (`MACOS_MENU` allows what macOS draws itself), so a
      renamed menu item can't stay on the site under its old name;
  D11 the site replaced the user guide, so `docs/guide/` does not exist and no file the gate
      hashes, outside `archive/` and `designs/adr/`, links into it (a relative link, or a GitHub
      URL of this repository).

    python3 tools/proof/docs_site_proof.py                       # the tree (make test)
    python3 tools/proof/docs_site_proof.py --pages a.mdx b.mdx   # those pages: D1, D6–D9
    python3 tools/proof/docs_site_proof.py --guide               # D11 alone (make gate's names)
    python3 tools/proof/docs_site_proof.py --selftest            # CONTROL + M1..M14

`--selftest` copies the site's inputs to `tools/proof/work/docs_site/` and requires the copy to
show no problem (CONTROL), then eleven mutants, each on a fresh copy, to show a problem in exactly
its row; then D11's CONTROL on a scratch root, `tools/proof/work/docs_site_guide/`, and its three
mutants, fourteen mutants in all. Exit 0 when all hold, 1 otherwise.
"""

import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SITE = os.path.join(ROOT, "docs", "site")
WORK = os.path.join(ROOT, "tools", "proof", "work", "docs_site")
SOURCES = os.path.join(ROOT, "app", "Sources")

# A menu's own title is not an item, and macOS writes these rows' text itself.
MENU_SKIP = {"MainMenu", "Services", "Open Recent"}

# The menus, and the steps of a menu path macOS draws or the app words as it runs: File's document
# items, Undo's name for the edit, and a Settings section's info button.
TOP_MENUS = {"File", "Edit", "Insert", "Clip", "Track", "Mark", "View", "Window", "Help",
             "Frame Job"}
MACOS_MENU = re.compile(r"^(?:Revert To|Move To…|Share|Close All|Undo .+|Redo .+|ⓘ|.+, for the key)$")

# Decision IDs by prefix. AC-3 is an audio format, so AC is not among them.
INTERNAL = (
    (re.compile(r"\b(?:AI|AP|AS|AU|CAM|CJ|CO|CU|CX|FC|GR|HD|MC|MT|NM|PR|PUB|REC|RMP|SH|SR|SW|SY|TL"
                r"|TR|TU|TX|VR)-\d+\b|\bG-\d{1,3}\b"), "a decision ID"),
    (re.compile(r"§\s?\d"), "a spec section"),
    (re.compile(r"\broad ?map\b", re.I), "a road map"),
    (re.compile(r"\brc_[a-z_]+"), "an rc_ export"),
    (re.compile(r"-RCDev|FRAMEJOB_DEV_TOOLS"), "a dev default"),
    (re.compile(r"app/Sources|core/src|tools/proof|\b\w+\.swift\b|\b\w+\.rs\b"), "a source file"),
    (re.compile(r"(?<![\w&/#])#\d{3}\b"), "an issue number"),
)
LOCAL_PATH = re.compile(r"/Users/[a-z]|/private/(?:tmp|var)|/var/folders/")
BANNED = re.compile(r"\b(?:seamless(?:ly)?|effortless(?:ly)?|robust|powerful|simply|supercharge"
                    r"|unleash)\b", re.I)
FENCE = re.compile(r"^```.*?^```", re.M | re.S)

# D11. The history keeps its links to the retired guide; the guide itself existing is its own row.
GUIDE_EXEMPT = ("archive/", "designs/adr/", "docs/guide/")
GUIDE_SUFFIXES = (".md", ".mdx", ".astro", ".mjs", ".json", ".swift", ".yml", ".yaml", ".html",
                  ".plist")
GUIDE_WORK = os.path.join(ROOT, "tools", "proof", "work", "docs_site_guide")
GUIDE_LINKS = (
    re.compile(r"\]\(\s*<?([^)\s>]+)"),                              # [text](target)
    re.compile(r"^\s{0,3}\[[^\]\n]+\]:\s*<?([^\s>]+)", re.M),          # [ref]: target
    re.compile(r"\b(?:href|src)\s*=\s*[\"']([^\"']+)[\"']"),          # href="target"
    re.compile(r"(https?://[^\s)\]>\"'`]+)"),                         # a bare URL
)


def content_dir(site):
    return os.path.join(site, "src", "content", "docs")


def pages(site):
    """{slug: path} for every page, the home page's slug being ''."""
    found = {}
    base = content_dir(site)
    for path in glob.glob(os.path.join(base, "**", "*.md*"), recursive=True):
        slug = os.path.relpath(path, base).rsplit(".", 1)[0]
        found["" if slug == "index" else slug] = path
    return found


def split_page(text):
    match = re.match(r"---\n(.*?)\n---\n(.*)", text, re.S)
    return (match.group(1), match.group(2)) if match else ("", text)


def slugify(text):
    """A heading's anchor, as Starlight makes it (github-slugger)."""
    text = re.sub(r"<[^>]+>", "", text)
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = text.replace("`", "").replace("*", "").strip().lower()
    text = re.sub(r"[^\w\- ]", "", text)
    return text.replace(" ", "-")


def anchors(text):
    """Every anchor a page has: its headings, numbered as repeats are, and any explicit id."""
    body = FENCE.sub("", split_page(text)[1])
    seen, found = {}, set()
    for heading in re.findall(r"^#{2,6}\s+(.+?)\s*$", body, re.M):
        slug = slugify(heading)
        count = seen.get(slug, 0)
        seen[slug] = count + 1
        found.add(slug if count == 0 else f"{slug}-{count}")
    found.update(re.findall(r"""\bid=["']([^"']+)["']""", body))
    return found


def headings(text):
    return {slugify(heading) for heading in
            re.findall(r"^#{2,6}\s+(.+?)\s*$", FENCE.sub("", split_page(text)[1]), re.M)}


def product_tools():
    names = set()
    for path in glob.glob(os.path.join(SOURCES, "AgentCatalog*.swift")):
        names |= set(re.findall(r'\b[A-Za-z]*[Tt]ool\(\s*(?:name:\s*)?"([a-z][a-z0-9_]+)"',
                                open(path, encoding="utf-8").read()))
    return names


def dev_tools():
    text = open(os.path.join(SOURCES, "AgentServer+DevTools.swift"), encoding="utf-8").read()
    return set(re.findall(r'^\s+"([a-z][a-z0-9_]+)": \{ \$0\.', text, re.M))


def menu_items():
    titles = set()
    files = glob.glob(os.path.join(SOURCES, "AppDelegate+*Menu*.swift"))
    for path in files + [os.path.join(SOURCES, "EditorViewController+GraphicMenus.swift")]:
        text = open(path, encoding="utf-8").read()
        titles |= set(re.findall(r'\b(?:item|tagged)\(\s*"((?:[^"\\]|\\.)+)"', text))
        titles |= set(re.findall(r'NSMenu(?:Item)?\(\s*title:\s*"((?:[^"\\]|\\.)+)"', text))
    return {title for title in titles if "\\" not in title and title not in MENU_SKIP}


def app_strings():
    found = set()
    for path in glob.glob(os.path.join(SOURCES, "*.swift")):
        found |= set(re.findall(r'"((?:[^"\\\n]|\\.)+)"', open(path, encoding="utf-8").read()))
    return found


def named_things(slug, text, tools, strings):
    """D10 for one page."""
    problems = []
    for block in re.findall(r"""tools=(\{\[[^\]]*\]\}|"[^"]*")""", text):
        for name in re.findall(r"[a-z][a-z0-9_]+", block):
            if name not in tools:
                problems.append(("D10", f"{slug}: no tool {name}"))
    paths = re.findall(r"\*\*([^*\n]+?▸[^*\n]*?)\*\*", text)
    paths += re.findall(r"""['"]((?:%s) ▸ [^'"\n]+)['"]""" % "|".join(TOP_MENUS), text)
    for path in paths:
        steps = [step.strip() for step in path.split("▸") if step.strip()]
        if not steps or steps[0] not in TOP_MENUS:
            continue
        for step in steps[1:]:
            step = re.sub(r"\s*\(.*$", "", step)
            known = {step, step + "…", step.rstrip("…")} & strings
            if not known and not MACOS_MENU.match(step):
                problems.append(("D10", f"{slug}: no menu step \"{step}\" in {path}"))
    return problems


def page_rows(slug, path):
    """D1, D6, D7, D8 and D9 for one page."""
    text = open(path, encoding="utf-8").read()
    head, body = split_page(text)
    problems = []
    for key in ("title", "description"):
        if not re.search(rf"^{key}:\s*\S", head, re.M):
            problems.append(("D1", f"{slug}: no {key}"))
    for number, line in enumerate(text.split("\n"), 1):
        if line.startswith(("import ", "export ")):
            continue
        for pattern, what in INTERNAL:
            found = pattern.search(line)
            if found:
                problems.append(("D6", f"{slug}:{number}: {what}: {found.group(0)}"))
        if LOCAL_PATH.search(line):
            problems.append(("D7", f"{slug}:{number}: a local path"))
        found = BANNED.search(line)
        if found:
            problems.append(("D9", f"{slug}:{number}: {found.group(0)}"))
    site = path.split(os.sep + os.path.join("src", "content", "docs"))[0]
    for name in re.findall(r'<Shot[^>]*\bname="([^"]+)"', body):
        for look in ("light", "dark"):
            if not os.path.exists(os.path.join(site, "src", "assets", "screens",
                                               f"{name}.{look}.webp")):
                problems.append(("D8", f"{slug}: no capture {name}.{look}"))
    return problems


def check(site, tools, devs, menus, strings):
    problems = []
    found = pages(site)
    texts = {slug: open(path, encoding="utf-8").read() for slug, path in found.items()}

    for slug, path in found.items():
        problems += page_rows(slug, path)
        problems += named_things(slug, texts[slug], tools, strings)

    sidebar = open(os.path.join(site, "sidebar.mjs"), encoding="utf-8").read()
    listed = set(re.findall(r"'([a-z0-9-]+/[a-z0-9-]+)'", sidebar))
    listed |= set(re.findall(r"slug: '([a-z0-9-]+)'", sidebar))
    for slug in sorted(set(found) - listed - {""}):
        problems.append(("D2", f"{slug}: not in the sidebar"))
    for slug in sorted(listed - set(found)):
        problems.append(("D2", f"{slug}: in the sidebar, with no page"))

    data = json.load(open(os.path.join(site, "src", "data", "features.json"), encoding="utf-8"))
    known = {slug: anchors(text) for slug, text in texts.items()}
    for section in data["sections"]:
        for feature in section["features"]:
            page, anchor = feature["page"], feature.get("anchor")
            if page not in known:
                problems.append(("D3", f"{feature['name']}: no page {page}"))
            elif anchor and anchor not in known[page]:
                problems.append(("D3", f"{feature['name']}: {page} has no #{anchor}"))

    documented = set()
    for slug, text in texts.items():
        if slug.startswith("mcp/"):
            documented |= {heading.replace("-", "_") for heading in headings(text)}
    for tool in sorted(tools - documented):
        problems.append(("D4", f"{tool}: no heading on an mcp/ page"))
    for slug, text in texts.items():
        for tool in devs:
            if re.search(rf"\b{tool}\b", text):
                problems.append(("D4", f"{slug}: names the dev tool {tool}"))

    reference = "\n".join(text for slug, text in texts.items() if slug.startswith("reference/"))
    for title in sorted(menus):
        if title not in reference:
            problems.append(("D5", f"{title}: on no reference page"))

    for name in glob.glob(os.path.join(site, "src", "data", "*")):
        if LOCAL_PATH.search(open(name, encoding="utf-8").read()):
            problems.append(("D7", f"{os.path.basename(name)}: a local path"))
    return problems


def listed(root):
    """The tracked and untracked, not ignored, files under `root`, repo-relative: the list
    `gate.py` hashes. A failed git call raises."""
    out = subprocess.run(["git", "ls-files", "-z", "-co", "--exclude-standard"], cwd=root,
                         capture_output=True, check=True).stdout
    return [path for path in out.decode("utf-8", "replace").split("\0") if path]


def guide_rows(root, paths):
    """D11: the user guide was retired for the site, so `docs/guide/` must not exist and no file
    outside the history (`GUIDE_EXEMPT`) may link into it."""
    problems = []
    if os.path.exists(os.path.join(root, "docs", "guide")):
        problems.append(("D11", "docs/guide exists"))
    seen = set()
    for path in paths:
        if not path.endswith(GUIDE_SUFFIXES) or path.startswith(GUIDE_EXEMPT):
            continue
        full = os.path.join(root, path)
        if not os.path.isfile(full):
            continue
        with open(full, encoding="utf-8", errors="replace") as source:
            text = source.read()
        for pattern in GUIDE_LINKS:
            for match in pattern.finditer(text):
                target = re.split(r"[#?]", match.group(1), maxsplit=1)[0]
                if not target:
                    continue
                if "://" in target:
                    flagged = ("github.com/kpgalligan/framejob/" in target
                               and re.search(r"/docs/guide(?:/|$)", target) is not None)
                elif re.match(r"^[A-Za-z][A-Za-z0-9+.-]*:", target) or target.startswith("/"):
                    flagged = False
                else:
                    resolved = os.path.normpath(os.path.join(os.path.dirname(path), target))
                    flagged = resolved == os.path.join("docs", "guide") or resolved.startswith(
                        os.path.join("docs", "guide") + os.sep)
                line = text.count("\n", 0, match.start()) + 1
                if flagged and (path, line, target) not in seen:
                    seen.add((path, line, target))
                    problems.append(("D11", f"{path}:{line}: links into docs/guide: {target}"))
    return problems


def report(problems):
    for row, message in sorted(problems):
        print(f"{row} {message}")
    print(f"docs site: {len(problems)} problems")
    return 1 if problems else 0


def fresh_copy():
    shutil.rmtree(WORK, ignore_errors=True)
    os.makedirs(WORK)
    for part in ("src/content/docs", "src/data", "src/assets/screens"):
        shutil.copytree(os.path.join(SITE, part), os.path.join(WORK, part))
    shutil.copy(os.path.join(SITE, "sidebar.mjs"), WORK)
    return WORK


def edit(path, change):
    with open(path, encoding="utf-8") as source:
        text = source.read()
    with open(path, "w", encoding="utf-8") as target:
        target.write(change(text))


def selftest():
    tools, devs, menus, strings = product_tools(), dev_tools(), menu_items(), app_strings()
    page = "src/content/docs/timeline/markers.mdx"

    def in_page(site, line):
        edit(os.path.join(site, page), lambda text: text + f"\n{line}\n")

    def bad_anchor(site):
        path = os.path.join(site, "src/data/features.json")
        data = json.load(open(path, encoding="utf-8"))
        data["sections"][0]["features"][0]["anchor"] = "no-such-heading"
        json.dump(data, open(path, "w", encoding="utf-8"))

    def drop_description(site):
        edit(os.path.join(site, page), lambda text: re.sub(r"^description:.*\n", "", text, count=1, flags=re.M))

    def off_sidebar(site):
        edit(os.path.join(site, "sidebar.mjs"), lambda text: text.replace("'timeline/markers',", ""))

    mutants = [
        ("M1", "D1", drop_description, set()),
        ("M2", "D2", off_sidebar, set()),
        ("M3", "D3", bad_anchor, set()),
        ("M4", "D4", lambda site: None, {"tool": "a_tool_nobody_wrote_up"}),
        ("M5", "D5", lambda site: None, {"menu": "A Menu Item Nobody Wrote Up"}),
        ("M6", "D6", lambda site: in_page(site, "Decided in AU-12."), set()),
        ("M7", "D7", lambda site: in_page(site, "See /Users/someone/project."), set()),
        ("M8", "D8", lambda site: in_page(site, '<Shot name="no-such-capture" alt="x" />'), set()),
        ("M9", "D9", lambda site: in_page(site, "A seamless experience."), set()),
        ("M10", "D10", lambda site: in_page(site, '<AtAGlance tools="a_tool_nobody_built" />'), set()),
        ("M11", "D10", lambda site: in_page(site, "Choose **Clip ▸ Fold Space**."), set()),
    ]

    failed = 0
    control = check(fresh_copy(), tools, devs, menus, strings)
    print(f"CONTROL {'pass' if not control else 'fail'}: {len(control)} problems")
    failed += bool(control)
    for name, row, mutate, extra in mutants:
        site = fresh_copy()
        mutate(site)
        found = check(site, tools | ({extra["tool"]} if "tool" in extra else set()), devs,
                      menus | ({extra["menu"]} if "menu" in extra else set()), strings)
        rows = {problem[0] for problem in found}
        held = rows == {row}
        print(f"{name} {'pass' if held else 'fail'}: wanted {row}, got {sorted(rows)}")
        failed += not held
    shutil.rmtree(WORK, ignore_errors=True)

    # D11 on a root of its own: a link into the guide from the README or the app is caught, the
    # history's links and the site's root-absolute links are not, and a listed file that is gone
    # from disk is skipped.
    guide_files = {
        "README.md": "[Audio](docs/site/src/content/docs/audio/how-audio-works.mdx)\n",
        "archive/old.md": "[Old](../docs/guide/audio.md)\n",
        "designs/adr/old.md": "[Old](../../docs/guide/audio.md)\n",
        "docs/site/x.mdx": "[Markers](/timeline/markers/)\n",
    }

    def guide_root():
        shutil.rmtree(GUIDE_WORK, ignore_errors=True)
        for path, text in guide_files.items():
            os.makedirs(os.path.dirname(os.path.join(GUIDE_WORK, path)), exist_ok=True)
            with open(os.path.join(GUIDE_WORK, path), "w", encoding="utf-8") as target:
                target.write(text)
        return GUIDE_WORK, sorted(guide_files) + ["gone.md"]

    def make_guide(root, paths):
        os.makedirs(os.path.join(root, "docs", "guide"))
        return paths

    def readme_link(root, paths):
        edit(os.path.join(root, "README.md"), lambda text: text + "[Audio](docs/guide/audio.md#fades)\n")
        return paths

    def app_link(root, paths):
        os.makedirs(os.path.join(root, "app", "Sources"))
        with open(os.path.join(root, "app", "Sources", "Help.swift"), "w", encoding="utf-8") as target:
            target.write('let help = "https://github.com/kpgalligan/framejob/blob/main/docs/guide/README.md"\n')
        return paths + ["app/Sources/Help.swift"]

    try:
        control = guide_rows(*guide_root())
    except Exception as error:  # a raise is a failed CONTROL, never a crash
        control = [("D11", f"raised {error!r}")]
    print(f"CONTROL (D11) {'pass' if not control else 'fail'}: {len(control)} problems")
    failed += bool(control)
    for name, mutate in (("M12", make_guide), ("M13", readme_link), ("M14", app_link)):
        root, paths = guide_root()
        rows = {problem[0] for problem in guide_rows(root, mutate(root, paths))}
        held = rows == {"D11"}
        print(f"{name} {'pass' if held else 'fail'}: wanted D11, got {sorted(rows)}")
        failed += not held
    shutil.rmtree(GUIDE_WORK, ignore_errors=True)
    return 1 if failed else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--pages", nargs="+")
    parser.add_argument("--guide", action="store_true")
    arguments = parser.parse_args()
    if arguments.selftest:
        return selftest()
    if arguments.pages:
        problems = []
        for path in arguments.pages:
            path = os.path.abspath(path)
            problems += page_rows(os.path.relpath(path, content_dir(SITE)), path)
        return report(problems)
    if arguments.guide:
        return report(guide_rows(ROOT, listed(ROOT)))
    return report(check(SITE, product_tools(), dev_tools(), menu_items(), app_strings())
                  + guide_rows(ROOT, listed(ROOT)))


if __name__ == "__main__":
    sys.exit(main())
