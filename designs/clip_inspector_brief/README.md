# Design brief: the Clip inspector

A brief for redesigning the **Clip** tab of Reelcut's inspector. Everything
below describes the app as built on 2026-09-23 (commit `7975456`). The
screenshots in `screenshots/` are real renders of that build. `tokens.css`
is the design-token file from the last shipped design pass.

---

## 1. The ask

The Clip tab works, but it is hard to use. The person who owns the product
says:

1. **It is dense.** Every property of the selected clip sits in one long
   list. A video clip with audio shows **21 collapsible sections**, 22 when it
   has a transition. A text clip shows about 17.
2. **Audio and video are not separated.** The audio sections come after all
   the picture sections, the clip-level ones (Speed, Timing, Actions,
   Transition) sit between them, and nothing marks where one group ends and
   the next begins.
3. **Actions are usable but poorly presented.** They live in the middle of the
   list, between Timing and Transition, closed by default. You should be able
   to **select an action and see it highlighted on the timeline**.
4. **Changing values need to be visible.** When the playhead is inside an
   action, the rows show the animated value at the playhead, but nothing
   marks **which sections or rows are being animated**.

What we want from Claude Design is a redesign of this panel: its
organisation, how actions are presented and selected, how animated values
are marked, and the timeline treatment that goes with selecting an action.
Section 9 lists the deliverables.

---

## 2. What Reelcut is

Reelcut is a screencast-style video editor for **macOS 26+ on Apple
Silicon**. It aims to be enough for a real cut with text, shapes,
transitions and simple animation, without Final Cut's complexity. It
records the screen itself (with pause/resume). The typical user makes
screen-recording tutorials and screencasts.

The features that define it:

- zoom-to-region on screen recordings;
- spotlight, and blur/pixelate "obscure" regions;
- automatic captions, including social-style word-by-word captions;
- Remove Silences;
- audio ducking.

Its model follows a screencast editor's ideas:

- one kind of track;
- a fixed canvas you manipulate directly;
- **actions instead of keyframes** (section 4);
- overlapping two clips *is* a transition;
- **one contextual inspector**;
- a small keyboard vocabulary.

It is a native AppKit app built in code, over a Rust core that holds the
project and every edit. An AI agent can drive every edit over MCP, so any
new control that changes the project has a matching agent tool. That
constrains engineering, not design.

**Window layout** (screenshot 01): a toolbar on top (transport, timecode,
view controls, Export); the preview canvas at left; the **inspector** at
right, 304 pt wide by default and resizable from 280 to 440; the timeline
across the bottom, with its own tool bar, a ruler and tracks. The inspector
has three tabs: **Clip · Media · Document**. This brief is about **Clip**.
Media is the imported-file list and Document holds canvas, frame rate,
appearance and markers; both stay as they are.

---

## 3. Screenshots

All are dark appearance unless noted. They are rendered at 2× (Retina), so
halve the pixels to get points.

| File | What it shows |
|---|---|
| `01-window-dark-video-clip.png` | The whole window. A video clip ("Intro demo") is selected and Transform is open. The preview is black because the renderer cannot draw offscreen; ignore it. |
| `02-window-light-inside-action.png` | The same in **light** appearance, with the playhead inside an action. |
| `03-window-tall-all-sections-collapsed.png` | A tall window: all 21 section headers of a video clip at once, which is how dense the tab is. |
| `04-inspector-playhead-inside-action.png` | **The key one.** The inspector column with the playhead inside action 2 of a clip with two actions. Transform and Color show the blue note "Editing action 2's end state"; the Actions section is open in the middle of the list. |
| `05-inspector-video-clip-every-section-open.png` | The inspector column with **every** section of a video+audio clip open. This is the full inventory in one image (very tall). |
| `06-inspector-clip-with-transition.png` | A clip that overlaps the previous one, so it gets a Transition section. Actions is open and empty. |
| `07-inspector-text-clip.png` | A text clip: Transform, the eight text sections, Shadow and the remaining effects. |
| `08-inspector-shape-clip.png` | A shape clip (arrow): Transform, the five shape sections, then the effects. |
| `09-inspector-audio-only-clip.png` | An audio-only clip. There is no Transform section, so the list starts at Speed. |
| `10-timeline-large-tracks.png` | The timeline at its largest track size, with the "Intro demo" clip selected and the playhead inside an action. |
| `11-timeline-action-bands-zoomed.png` | A close-up of the clip. The two faint dark bars under the name strip are **the only way actions are drawn on the timeline today**. |

---

## 4. The one concept to understand first: actions

**Reelcut has no keyframes.** Its only animation mechanism is the **action**.

- **An action is a time span on one clip**, with a start (in the clip's own
  time), a duration, an easing curve, and an **end state**.
- **You edit only the values at the END of the span.** The start values are
  whatever was already in effect. Over the span, the clip moves from where
  it was to the end state, along the curve.
- **The end state holds** for the rest of the clip. Nothing springs back. To
  return, you add another action whose end state restores the values.
  ("Zoom Back" does exactly that.)
- **Curves:** Linear, Ease In, Ease Out, Ease In Out.
- **Actions on one clip may not overlap**, and may not run past the clip's
  end. A clip can have any number of them, one after another.
- **What an action can animate:**
  - **Picture:** position, scale, rotation, opacity, blend, crop, corner
    radius, colour, chroma key, shadow, filters, reflection, spotlight,
    obscure regions.
  - **Text:** everything, including colour, size, outline and backdrop.
  - **Audio:** only volume, mute and the fades are audible. Pan, compressor,
    noise reduction, ducking and mono are **not** animated by the audio
    engine (see problem P7).
  - **Not animatable:** shape properties, and the clip's Motion presets.
- **Numbers and colours glide; on/off switches, text and enums switch at the
  end** of the span.
- **A zoom is just an action** whose end state is scale + x + y. The **Zoom
  to Region** tool (key Z) lets you drag a rectangle on the canvas and adds
  that action, eased in-out.

**How the inspector uses actions today:**

- When the playhead is **inside** an action on the selected clip, every
  animatable row shows the **interpolated value at the playhead**. Any edit
  writes that action's **end** value.
- When the playhead is **outside** every action, rows show and edit the
  clip's **base** values.
- The playhead's position is therefore the only thing that decides whether
  you are editing the clip or an action. **There is no "selected action".**
  To edit an action you scrub the playhead into its span.

**Ways to create an action:** Clip ▸ Add Action (⌥⌘K) at the playhead; the
Add Action button in the Actions section; Zoom to Region (Z, drag on the
canvas; ⇧ fills instead of fits); Zoom Back.

---

## 5. Problems observed in the current design

The first four are the owner's. The rest came out of reading the code, and
a good redesign should solve them too.

- **P1. Density.**
  - There are 21–22 sections. Each has a 28 pt header, a summary, and (on
    most) a Reset button.
  - Only Transform is open by default.
  - Order: Transform → text or shape sections → Crop / Corner / Color /
    Chroma → Shadow / Filters / Reflection / Spotlight / Obscure / Motion →
    Speed → Timing → **Actions** → Transition → the six audio sections.
- **P2. No audio/video split.** Picture, clip timing and sound are one list.
  An audio-only clip gets a list that starts with Speed.
- **P3. Actions are buried.**
  - Actions is section 13 of 21, closed by default, with no Reset and no
    note.
  - Each action is two rows: "Action N" with start/duration fields and
    Remove, and "Curve" with a curve popup and a read-only list of the
    *property names* the action changes (e.g. `scale, x, y`).
  - You can't see or edit the end **values** there, you can't jump the
    playhead to an action, and you can't select one.
  - Actions are listed in creation order, not time order.
  - Start is shown in seconds of clip time, while Timing uses timecode.
- **P4. No action selection and no timeline highlight.**
  - On the timeline, each action is a 4 pt bar of 34% black under the clip's
    name strip (screenshot 11). There is no hover, selection, label or
    curve.
  - The bars can't be clicked or dragged.
  - Nothing links a bar to its row in the inspector.
- **P5. Animated values aren't marked.**
  - The only signal is a blue one-line note, **"Editing action N's end
    state"**, at the top of some sections.
  - It is per *section*, not per *row*, and it is hidden when the section is
    collapsed.
  - The summaries in the section headers do update as the playhead moves,
    but nothing says *which* values have keys in the action's end state and
    which are just held.
- **P6. The note is inconsistent.**
  - It appears on Transform, Crop, Corner Radius, Color, Chroma Key,
    Filters, Reflection, Spotlight, Obscure, and the text Content, Font,
    Style and Animation sections, and on audio Volume.
  - It does **not** appear on Shadow, text Outline / Backdrop / Box, or audio
    Fades / Ducking / Noise / Compressor / Mix, even though edits there also
    go into the action.
  - Motion shows the opposite note ("Motion belongs to the clip; the action
    under the playhead does not animate it").
- **P7. Silent no-op edits.** Inside an action, editing Pan, Compressor,
  Noise Reduction, Ducking or Mono writes into the action's end state, which
  the audio engine ignores. The user gets no warning.
- **P8. Shows one value, writes another.**
  - Inside an action, a field shows the value **at the playhead** but a
    write sets the **end** value.
  - Type 200% at an action's midpoint and the field then reads something
    like 150%.
  - The same happens when dragging a slider: the knob follows the evaluated
    value, not the pointer.
  - This is the single most confusing behaviour in the panel.
- **P9. Some edits ignore the action.**
  - Canvas handle drags (move, scale, rotate, crop) always edit the clip's
    **base** values, even while the inspector says it is editing an action.
  - Adding or removing a filter or an obscure region, and every Motion edit,
    also always go to the base values.
- **P10. Unchecking inside an action doesn't turn the effect off.**
  Unchecking Drop shadow, Chroma, Reflection or Spotlight inside an action
  removes that key from the action's end state rather than turning the
  effect off.
- **P11. Reset is inconsistent.**
  - Most Resets turn a feature off.
  - Stroke's Reset turns it **on** (6 px white).
  - Shape's Reset only zeroes the corner radius.
  - Style's Reset leaves the font alone.
  - Content, Font, Presets, Arrowheads, Actions, Timing and Transition have
    none.
  - Inside an action, Reset writes into the action's end state.
- **P12. "Mixed" only on primary rows.** In a multi-selection, a small
  "mixed" badge marks rows where the clips disagree. Sub-rows under a toggle
  (shadow, outline, compressor, etc.) never show it.

---

## 6. The panel today: anatomy and metrics

**Inspector panel:**
- 304 pt wide by default (280–440).
- A 32 pt tab strip; the active tab has a 2 pt accent underline.
- Below it, a vertical scroll view.

**Selection header** (44 pt):
- an 8×26 pt chip in the clip kind's tint;
- the clip name, which is editable for a single clip, sans 12 semibold;
- a mono 10 meta line: `video · 00:00:05:00 · 640×360 · 30 fps`;
- a 6 pt dot for the clip's colour label.
- A multi-selection reads "N clips selected" and shows the total duration.

**Section:**
- **Header** (28 pt): a filled band with a chevron; the TITLE in mono 10,
  uppercase and tracked; a right-aligned **summary** in mono 10 faint (e.g.
  `300%`, `vignette`, `off`, `-3.3 dB`); an optional **Reset** button.
- **Open/closed state** is remembered per section across launches.
- **Note line** (optional): the first row of the body, sans 11 in the accent
  colour.
- **Body:** 10 pt side insets, 7 pt between rows.

**Row:**
- a 76 pt label column (sans 11, muted), then the controls, then an
  optional `mixed` badge;
- every control is 22 pt tall.

**Controls:**
- **Slider + value field:** a 3 pt rail with an accent fill and an 11 pt round
  knob, plus a 58 pt mono field.
  - Dragging is live, and one drag is one undo step.
  - The field shows its unit at rest and commits on Return or on leaving.
  - Many fields have a ▾ zone that opens a menu of **quick values**.
- **Field only:** the same field without a slider.
- **Popup** (116 pt); **checkbox**, which carries its own label; **colour
  well** (22×22, opens the system colour panel); **segmented** (icon cells);
  **button**; **read-only readout** (mono); **timecode field** (104 pt);
  **multi-line text area** (72 pt).
- Disabled controls draw at 42% opacity; they are greyed, not hidden.

**Behaviour:**
- The panel rebuilds when the selection changes, and also when the playhead
  crosses into or out of an action.
- While the selected clip has actions, the panel refreshes on every playhead
  tick, about 30 Hz during playback.
- Clicking a clip always switches to the Clip tab.

---

## 7. Every section, every control

**Key:**
- **Anim:** ✓ means the row is animatable, so inside an action it edits the
  action's end state. ✗ means it always edits the clip itself. ✓\* means an
  action will store it but it has no audible effect (P7).
- **Summary:** the text shown in the collapsed header.
- **When shown:** "pixels" means any clip that draws (video, image, still,
  text, shape, compound). "media" means a clip from an imported file.

### 7.0 Clip-level (not picture or sound)

**Selection header:** see section 6. The name is editable here, and an
emptied name falls back to the file name.

**Timing** (`clip.timing`; summary: duration, e.g. `00:00:05:00`; no Reset):

| Row | Control | Notes | Anim |
|---|---|---|---|
| In | timecode field | where the clip starts on the timeline; trims the front edge (clamped, never refused) | ✗ |
| Out | timecode field | where it ends; trims the back edge | ✗ |
| Duration | readout | Out − In | — |
| Reverse | checkbox | plays the clip backwards (media only; frames are pre-rendered) | ✗ |
| Reversed frames | readout | — / Rendering… / Rendered / Not rendered / Media missing | — |
| Render Reverse | button | restarts a stopped reverse render | — |

For several selected clips, only the Reverse rows appear.

**Speed** (`video.speed`; media clips, audio-only included; summary `1.00×`;
Reset to 1×):

| Row | Control | Range / quick | Anim |
|---|---|---|---|
| Rate | field | ×, 0.1–10; quick 0.5 / 1 / 2 / 4. Changes the clip's length; its actions keep their fraction of the clip. | ✗ |
| Keep pitch | checkbox | on by default | ✗ |

**Transition** (`video.transition`; only when one clip is selected **and** it
overlaps the previous clip on its track; the overlap *is* the duration;
summary e.g. `cross dissolve · linear · 0.50 s`; no Reset):

| Row | Control | Values | Anim |
|---|---|---|---|
| Kind | popup | None, Cross Dissolve, Fade Through Black, Fade Through White, Push Left/Right/Up/Down, Wipe, Slide, Zoom, Wipe Left/Up/Down | ✗ |
| Curve | popup | Linear, Ease In, Ease Out, Ease In Out | ✗ |
| Crossfade Audio | checkbox | | ✗ |
| Duration | field | s, 0.02–10; quick 0.25 / 0.5 / 1 / 2. Moves the clip so the overlap matches. | ✗ |

**Actions** (`video.actions`; always shown; summary: the count or `none`; no
Reset). For several selected clips it shows only "Select one clip to edit
its actions." For one clip, each action, in creation order, is:

| Row | Controls |
|---|---|
| Action N | Start field (s, clip time, frame-snapped) · Duration field (s; quick 0.25 / 0.5 / 1 / 2) · **Remove** |
| Curve | curve popup (Linear / Ease In / Ease Out / Ease In Out) · readout of the property **names** in the end state, e.g. `scale, x, y`, `color, opacity, rotation, volume`, or `no change` |

Then: "No actions on this clip." when empty; **Add Action** with its `⌥⌘K`
hint (adds a 1 s linear action with an empty end state at the playhead);
**Zoom to Region…** (arms the canvas tool, Z); **Zoom Back** (adds an action
returning to the clip's own scale and position).

**Motion** (`video.motion`; pixels; summary e.g. `in fade · out slide left ·
pulse`; Reset clears). These are preset entrance, exit and continuous
animations, **not** actions, and they are never animatable:

| Row | Control | Values |
|---|---|---|
| In | popup | None, Fade, Zoom In, Zoom Out, Slide Left/Right/Up/Down, Spin, Pop |
| In Duration | field | s, 0.1–10; quick 0.25 / 0.5 / 1 |
| Out | popup | same nine kinds as In |
| Out Duration | field | same as In Duration |
| During | popup | None, Pulse, Shake, Spin, Bounce, Drift |
| Amount | field | %, 0–100 |
| Period | field | s, 0.1–10 (not for Drift) |
| Preview | button | loops the clip in the preview |

A wrapping note appears when an edge is set to zero duration. The timeline
draws in/out wedges and a During glyph for Motion.

### 7.1 Picture (video)

**Transform** (`video.transform`; pixels; open by default; summary `300%` or
`150% · 45°`; Reset):

| Row | Control | Range / quick | Anim |
|---|---|---|---|
| Scale | slider + field | %, 1–1000; quick 25 / 50 / 75 / 100 / 150 / 200 / 400 | ✓ |
| Position X | field | px from the canvas centre | ✓ |
| Position Y | field | px, measured downward | ✓ |
| Rotation | slider + field | °, −180–180; quick ±90, ±45, 0, 180 | ✓ |
| Opacity | slider + field | %, 0–100 | ✓ |
| Blend | popup | Normal, Multiply, Screen, Add, Overlay, Darken, Lighten, Difference | ✓ (switches at the end) |
| Fit to Canvas · Fill Canvas | buttons | | ✓ |

Its note line can instead warn about blend modes: "Nothing behind this clip
— multiply reads black here." The canvas also has direct handles for move,
scale and rotate.

**Crop** (`video.crop`; media, images and stills; summary `none` or
`10·0·10·0`; Reset): Left, Top, Right, Bottom fields (source px). **Crop on
Canvas** button (C). All ✓.

**Corner Radius** (`video.corner`; summary `0 px`; Reset): Radius slider,
0–500 px. ✓

**Color** (`video.color`; summary `neutral` / `adjusted`; Reset):
Brightness, Contrast, Saturation (each −1…1) and Hue (−180…180°), all
sliders. ✓

**Chroma Key** (`video.chroma`; summary `off` or tolerance; Reset): "Key out
a color" checkbox · Key Color well · **Pick from Canvas** (eyedropper) ·
Tolerance, Softness, Spill sliders (%). ✓

**Shadow** (`video.shadow`; every pixel kind, text and shapes too; summary
`off` or blur; Reset): "Drop shadow" checkbox · Color · Opacity % · Blur
0–200 px · Angle 0–360° · Distance 0–200 px. ✓ (but no note, P6).

**Filters** (`video.filters`; summary `none` / kind / `3 filters`; Reset). An
ordered stack of at most 4, applied top to bottom. Each filter is:

- an **order popup** (1…n), a **Kind** popup (Blur, Sharpen, Pixelate, Sepia,
  Noir, Vignette, Invert) and **Remove**;
- an **Amount** slider (%).

Below the stack: **Add Filter** (appends a 50% blur) and "4 at most". Amount
and kind are ✓. Adding, removing and reordering are ✗ (always the clip).

**Reflection** (`video.reflection`; summary `off` / opacity; Reset): "Mirror
the layer below itself" checkbox · Opacity · Height (% of the layer) · Gap
(px) · Falloff (%). ✓

**Spotlight** (`video.spotlight`; summary `off` / `rectangle` / `ellipse`;
Reset). It dims everything outside a region and can magnify inside it.
Rows: "Spotlight a region" checkbox · Shape (Rectangle / Ellipse) · Center
X / Y fields · Width / Height fields · Feather (px) · Dim (%) · Zoom (1–2×).
✓. It has no canvas handle; you place it by numbers only.

**Obscure** (`video.obscure`; summary `none` / kind / `2 regions`; Reset).
Up to 4 regions that blur or pixelate what is under them (for passwords and
emails in screen recordings). Each region is six rows:

- **Region N**: a Kind popup (Blur / Pixelate) and **Remove**;
- Shape;
- Amount;
- Feather;
- Center (x, y);
- Size (w, h).

Below the regions: **Add Region**, **Place on Canvas** (drag a rectangle)
and "4 at most". Values are ✓; adding and removing are ✗.

**Motion:** see 7.0.

### 7.2 Text (all selected clips are text)

| Section | Summary | Rows | Anim |
|---|---|---|---|
| **Content** (open by default, no Reset) | first line | multi-line text area; commits on leaving or ⌘Return | ✓ |
| **Font** (no Reset) | `72 px` | Family popup · Style popup · Size field (6–800 px; quick 24 / 36 / 48 / 72 / 96 / 144) | ✓ |
| **Style** | `center` | Color · Align (3-cell segmented) · Vertical (3-cell segmented) · UPPERCASE checkbox · Line spacing (0.5–4×) · Tracking (−20–100 px) | ✓ |
| **Outline** | `off` / `2.0 px` | Outline checkbox · Width · Color | ✓ (no note) |
| **Backdrop** | `off` / `12 px` | Backdrop checkbox · Fill colour · Padding · Radius | ✓ (no note) |
| **Box** | `auto` / `1152 px` | Mode popup (Auto-size / Fixed width) · Width field | ✓ (no note) |
| **Animation** | `typewriter · 1.00 s` | Reveal popup (None, Typewriter, Word Fade, Line Rise) · In (s) · Out (s). Greyed on word-caption pages ("the word style wins"). | ✓ |
| **Presets** (no Reset) | — | buttons: Title · Subtitle · Lower Third · Caption. Each sets font, size, alignment, backdrop and position in one step. | ✓ |

The Picture sections a text clip also gets: Transform, Shadow, Filters,
Reflection, Spotlight, Obscure, Motion.

### 7.3 Shape (all selected clips are shapes; **never animatable**)

| Section | Summary | Rows |
|---|---|---|
| **Shape** (open by default; its Reset only zeroes the radius) | `arrow` | Kind popup (Rectangle, Ellipse, Line, Arrow) · Width · Height · Corner radius (rectangles only) |
| **Stroke** (its Reset turns the stroke **on**) | `6.0 px` | Stroke checkbox · Width · Color |
| **Fill** | `off` / `100%` | Fill checkbox · Color · Opacity |
| **Gradient** | `linear, 2 stops` | Gradient checkbox · Kind (Linear / Radial) · Angle · one row per stop (colour, position %, Remove; 2–8 stops) · **Add Stop**. Rectangles and ellipses only. |
| **Arrowheads** (no Reset) | `end` | "Arrowhead at start" and "Arrowhead at end" checkboxes (lines and arrows only) |

A line's or arrow's endpoints are set by dragging on the canvas only.

### 7.4 Sound (any selected clip with live audio)

| Section | Summary | Rows | Anim |
|---|---|---|---|
| **Volume** | `-3.3 dB`, `muted` | Volume slider (0–400%) · Gain readout (dB) · Mute checkbox · **Normalize** (sets peak to −1 dBFS; always the clip's base level) | ✓ |
| **Fades** | `0.50 · 1.00 s` | Fade in · Fade out (0–10 s). These are the same values as the fade handles on the timeline clip. | ✓ (no note) |
| **Ducking** | `off` / `20%` | "Duck other audio" checkbox · Level % · Attack s · Release s. Lowers *other* clips' audio while this one plays. | ✓\* |
| **Noise Reduction** | `off` / `50%` | Remove noise slider (%) · Depth readout ("6 dB at most") | ✓\* |
| **Compressor** | `off` / `3.0:1` | "Smooth volume levels" checkbox · Threshold dB · Ratio · Attack ms · Release ms · Makeup dB | ✓\* |
| **Mix** | `centre` / `left 50` | Pan slider (−100…100) · Position readout · "Mix to mono" checkbox · **Detach Audio** (moves the audio to its own clip, ⌥⌘D) | ✓\* |

There is no per-clip level meter or waveform in the inspector; waveforms
live on the timeline clips.

### 7.5 Multi-selection

Sections appear when they apply:

- **text and shape groups** need *every* selected clip to be that kind;
- **audio** appears if *any* selected clip has sound;
- **Actions** reads "Select one clip…";
- **Timing** keeps only Reverse.

Rows show the first clip's value, with a `mixed` badge where the clips
differ, and an edit writes to all of them.

---

## 8. Constraints on the design

**Visual language** (the "sharp" pass, 2026-09-23; `tokens.css` holds the
tokens):
- **Square chrome.** Every chrome radius is 0: fields, buttons, rows, chips,
  segmented cells. Only timeline clip bodies keep 2 pt. The one leftover
  round element is the inspector slider's knob (the timeline zoom slider
  already uses a 7×11 block knob).
- **Type:**
  - Source Sans 3 (Regular / Semibold, 10–13 pt) for UI text.
  - IBM Plex Mono (9–12 pt) for every machine-produced number and for the
    uppercase micro-labels such as section titles.
- **Colour:**
  - Chrome uses system semantic colours so light and dark both work: accent
    blue for selection and focus; separator greys for borders.
  - Fixed inks:
    - **coral `#F4653F`** is the playhead, the selection ring and the marquee,
      and is reserved for those;
    - **butter `#F2C14E`** is the snap guide;
    - clip-kind tints: video `#3E5063`, audio `#2C7A58`, still `#6A4B93`,
      text `#B17C1E`, shape `#247686`, compound `#55595F`.
  - Any new "animated" or "action" colour must work in **both appearances**
    and must not collide with coral, butter or the accent.
- **Metrics:** control height 22; tabs 32; section header 28; label column
  76; spacing scale 2 / 3 / 6 / 7 / 8 / 9 / 10 / 12.
- **Motion:** 0.14 s hover, 0.22 s state changes, easing (0.2, 0.7, 0.3, 1);
  respect Reduce Motion.
- It is a **native Mac app**, not a web app. Standard AppKit behaviours
  (popups, colour panel, contextual menus, keyboard focus) are expected.

**Product rules that are not open for redesign:**
- **Actions stay "end state only".** No keyframe graph and no start-value
  editing.
- Actions on one clip do not overlap.
- Everything the panel does must stay possible from the keyboard and menus
  where it is today (⌥⌘K Add Action, Z Zoom to Region, C crop, ⌥⌘D Detach
  Audio).
- The Media and Document tabs are out of scope. The inspector keeps a single
  column of about 304 pt (it can be widened to 440).
- Adding more tabs, or tabs *inside* Clip, **is allowed**. The earlier design
  had separate Video / Audio / Text / Shape tabs, which were folded into
  Clip. Splitting Clip again (for example Video · Audio · Animation) is a
  legitimate answer.

**Engineering notes** (so the design lands cheaply, not as rules):
- A new "selected action" is view state, like the playhead or clip
  selection.
- Dragging an action on the timeline maps onto an existing edit
  (`set_action`).
- **Clearing one property from an action** (so it stops being animated) is
  already supported by the core, but has no UI. A design that offers
  "remove this property from the action" costs little.

---

## 9. What we'd like back

1. **A reorganised Clip inspector.** Show how picture, text/shape, sound,
   clip timing and animation are grouped, and how a person moves between
   the groups. Cover it for a video+audio clip, a text clip, a shape clip,
   an audio-only clip, and a multi-selection.
2. **An Actions experience**:
   - where actions live;
   - how the list reads (in time order, with start/duration/curve and what
     each action changes, ideally with its end **values**);
   - how you **select** an action;
   - what selecting does: it highlights the action on the timeline, and
     probably moves the playhead into it and puts the panel into "editing
     this action" mode;
   - how you leave that mode to edit the clip's base values;
   - how you add, retime, re-curve and remove actions;
   - how a zoom action is shown.
3. **The timeline treatment**: an action's band in normal, hover and
   **selected** states (and, optionally, dragging or resizing it), at the
   three track sizes, in both appearances.
4. **"This is animated" marking**, at row level:
   - a value that has a key in the current action's end state;
   - a value that is changing across the span but is not keyed;
   - a value the current action can't animate (Motion, shape properties,
     pan / compressor / noise / ducking);
   - how a collapsed section's header signals that something inside it is
     animated.
5. **Solve P8 (shows one value, writes another).** For example, show the
   end value as the editable value with the value at the playhead as a
   secondary readout, or anything better.
6. **A consistent Reset and note model** across sections (P6, P11).
7. Mockups in **dark and light**, at 304 pt width, using the tokens in
   `tokens.css`. An interactive HTML prototype of the panel is welcome.
