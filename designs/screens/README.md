# The screen catalog

One Markdown file per Reelcut screen: how to reach it, what to capture, and a
description of it for someone who has never seen the app — the text a design
request carries beside the pictures. `tools/proof/screens.py` reads every file
here, drives its own Reelcut into each screen over MCP and the dev tools, and
writes the PNGs (light and dark) and one `screens.md` pairing each picture with
its prose into `tools/proof/work/screens/<date>/`. The prose lives here so it
changes with the screens; the pictures are made fresh each run and are not kept
in the repository.

```sh
python3 tools/proof/screens.py            # the whole catalog; tools/proof/README.md has the rest
```

## A screen file

The file's first non-blank line is ```` ```json screen ````; the block ends at
the next line that is exactly ```` ``` ````. What is between is one JSON object,
the front block. Everything after the closing fence is the prose, copied into
`screens.md` verbatim. The file's name without `.md` is the screen's id, and the
screens run in name order.

```json
{
  "title": "Clip inspector — Sound",
  "project": "demo",
  "steps": [
    {"call": "set_selection", "args": {"clips": ["$clip:tone"]}},
    {"call": "set_playhead", "args": {"t": 1500000}}
  ],
  "captures": [
    {"name": "window", "window": "editor"},
    {"name": "inspector", "window": "editor", "view": "inspector"}
  ],
  "after": [],
  "expect": [{"capture": "inspector", "visible_text": "Gain"}]
}
```

- `title` (required): the heading in `screens.md`.
- `project` (required): `null` (no project open — Welcome, Settings), `"empty"`
  or `"demo"`, a fixture `screens.py` builds (below). It is opened before the
  steps run.
- `steps`: calls, in order, `{"call": TOOL, "args": {…}}`. `TOOL` is one of
  `STEP_TOOLS`: `set_selection`, `set_playhead`, `detect_silence`,
  `perform_menu_item`, `cancel_sheet`, `select_inspector_tab`. Never give
  `args` a `project`: `screens.py` adds the fixture's path to every call. A
  string `"$clip:<name>"` anywhere in `args` becomes that fixture clip's id.
  `"until_absent": KEY, "within": SECONDS` repeats the call every 0.5 s until its
  answer has no `KEY` (for example `detect_silence` until `pending_peaks` is
  gone), and fails the screen after `within`.
- `captures` (at least one): `{"name", "window", "view"?}`. `window` is
  `welcome`, `settings`, `editor`, `sheet` (the sheet attached to the editor) or
  `recorder` (the New Recording panel); `view` — `toolbar`, `preview`,
  `inspector` or `timeline` — captures one region of the editor. Each capture is
  taken light and dark: `<id>.<name>.light.png` and `.dark.png`, each with its
  layout dump beside it. The two looks come from two instances, one launched
  with `-RCDevAppearance light` and one with `-RCDevAppearance dark`, so every
  step runs once per look; a capture that answers any other appearance fails the
  screen.
- `after`: steps run after the captures, to put the app back — `cancel_sheet`
  for a screen that opened a sheet. A screen that leaves a sheet attached fails.
- `expect`: `{"capture", "visible_text" | "no_visible_text"}`, checked on every
  look's layout dump: some view that is not hidden must read exactly that text,
  or none may. A failed expect fails the screen and deletes its pictures. Use it
  where a screen depends on something the pins or the fixture decide (the
  Settings window must say `No API key is set.`; the Sound sub-tab's Volume
  section must be open).
- `skip`: a reason. A screen with a non-empty `skip` runs nothing and is scored
  a skip with that reason; it needs only `title`.

Anything else — an unknown key, a missing required one, a step with its own
`project`, a `$clip:` name the fixture lacks, a menu path that is not a leaf of
the menu or not a `sheet`/`window` item or a view toggle — fails the screen as `front block: …`
before any of its steps runs.

**Menu items.** `perform_menu_item` takes a path of titles as the menu shows
them (`["File", "Export…"]`). Only items the dev tool classifies `sheet` or
`window` are allowed, and the two view toggles of grading GR3 (View ▸ Show
Ungraded and View ▸ Waveform, `VIEW_SELECTORS` in `screens.py`), which persist
nothing — a screen that turns one on turns it off in `after`. File ▸ New
Recording… runs only in the LAST screen run:
shown from the background its panel no longer takes key (spec §11, #137), but
an instance that is active when it runs still gets a key panel whose default
button is Record, and the script cannot hold its child inactive, so
`screens.py` stops the instance straight after that screen's captures.

## The fixtures

Built by `screens.py` on the first screen that names one, into
`tools/proof/work/screens/fixtures/`, from `tools/proof/media/` (made by
`tools/proof/README.md`'s recipe). All are 960 × 540 at 30 fps on black.

- `empty` — `Empty.reelcut`: one track, "Track 1", no clips.
- `demo` — `Demo.reelcut`: five tracks, back to front Video, Titles, Graphics,
  Shapes and Music, one clip each, all starting at 0:
  - `video` — `media/speech.mov` (5.2 s, a navy card with speech);
  - `text` — a text clip reading "Reelcut", 5 s;
  - `graphic` — `graphic/tests/graphics/lower-third.js` as the module
    `lower-third`, 5 s. The module is written twice, an earlier text first
    (the file plus one trailing comment line), so `demo` holds one kept
    version of it — the "1 version kept" the Restore Graphic Version sheet
    shows;
  - `shape` — an ellipse, 5 s;
  - `tone` — `media/toneA.m4a` (a 440 Hz tone, about 5 s).

  `demo` also imports `media/toneB.m4a` (an 880 Hz tone, about 5 s) with no
  clip, so the Media tab has an unused row.

  `demo` is ready once both sound clips' (`video`'s and `tone`'s) peaks are
  cached: `screens.py` polls `detect_silence` in level mode until it answers
  no `pending_peaks`, so every capture draws the Music clip's waveform band.
- `animated` — `Animated.reelcut` (issue batch B87 phase 3): one track,
  "Graphics", holding one clip, `graphic` — `lower-third` at 0, 5 s — with one
  action at clip 1–3 s whose end keys `size` 96, `accent` "#2d7ff9" and
  `boxed` false (`set_action_end`'s graphic group, spec §11 G-34). A playhead
  inside the span selects the action (CI-1), so the Graphic tab shows the
  action's end.
- `matte` — `Matte.reelcut` (mattes MT4, spec §11 MT-7): three tracks, back to
  front Video, Window and Stray, one clip each, all starting at 0: `video` —
  `media/speech.mov`; `window` — a white-filled rectangle, 5 s, on an `alpha`
  matte track (it cuts Video); `stray` — a text clip reading "Reelcut", 5 s, on
  a `luma_inverted` matte track with a matte behind it (it cuts nothing). Ready
  once `video`'s peaks are cached.
- `adjust` — `Adjust.reelcut` (grading GR4b, spec §11 GR-6): two tracks, back
  to front Video and Adjustment, one clip each, both starting at 0: `video` —
  `media/speech.mov`; `adjustment` — an adjustment clip, 5 s, at saturation −1
  and opacity 0.75 (Strength 75%), so it greys three quarters of the video
  behind it. Ready once `video`'s peaks are cached.

## Adding a screen

1. Write `NN-name.md` with its front block and a placeholder for the prose.
2. Run `python3 tools/proof/screens.py --only NN-name` and look at every
   picture it wrote.
3. Write the prose from the pictures and the code: what the screen is for, what
   the person there is doing, and what each visible part is. Say only what the
   light or dark capture shows.
4. A screen that needs something new — a fixture clip, a step tool, a window —
   needs a change to `screens.py` first; its README section says how the run is
   proved.
