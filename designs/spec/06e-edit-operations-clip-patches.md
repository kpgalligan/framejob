# 6e Edit operations — the clip patch ops

Continues §6b: the patch ops (`set_video`, `set_audio`, `set_text`, `set_shape`, `set_graphic` and
`set_clip`) and `set_enabled`, moved here whole because §6b had passed the spec's ~500-line split
rule (#548, 2026-11-11). They were §6b's until then, so an older citation of §6b for one of them
means this file. The rules every op shares are §6a.

- **`set_video {clips, patch}` / `set_audio` / `set_text` / `set_shape`** — Merge the patch into the
  base props. Refuses if nothing changes. `set_audio` refuses a patch that ITSELF sets
  `duck.mode` to `speech` on a clip that is not a media clip or whose media has no `speech`
  (`audio.duck.mode speech needs the clip's media to carry speech spans (set_media_speech)`,
  format version 29, §11 AU-111); any other edit of a clip already holding such a duck applies.
  `set_audio` takes the gate and the de-esser as `gate` and `de_esser` (format version 33, §11
  AU-43, AU-45, AU-46): objects that merge per key, `{}` storing the defaults and `null` clearing,
  each field refused out of range by its dotted path (`audio.gate.hold must be between 0 and
  300000 ticks, not 400000`); both thresholds are dB relative to the clip's measured loudness.
  It takes the leveller as `leveller` the same way (format version 37, §11 AU-66:
  `audio.leveller.<field>`, its target relative to the loudness too; the first build's
  `threshold_db` is an unknown key). An unknown key, a value of the wrong JSON kind or a
  misspelt variant anywhere in the patch is an **error** that names the dotted path to it, array
  indices included, and the value sent — `unknown key "filters[1].kindd" in a video patch`, `bad
  value at "shadow" in a video patch: expected an object, not 5`, ``bad value at "filters[1].kind"
  in a video patch: unknown variant `glw`, expected one of `blur`, …`` — so a number where a shadow
  belongs is refused rather than read as a clear, and a list where an object belongs (or an object
  where a string belongs) is refused rather than read field by field; `add_text_clip`'s `text` and
  `add_shape_clip`'s `shape` answer in the same words. One value is refused by the CLIP rather than
  by the vocabulary: `video.blend` on a nest clip is an **error** naming it (format version 6),
  because a nest is flattened rather than composited offscreen and there is no group picture for a
  blend to combine with. It fires on the MERGED value only, so `{"blend": "normal"}` on a nest clip
  is the identity and refuses instead — otherwise an all-or-nothing `paste_attributes` of an
  ordinary look onto a nest clip would fail over a value that changes nothing. `set_action_end` does
  not range-check, so the same rule is enforced again in the evaluator (§5.4's `clamp_video`), which
  closes the recipe, `clip_state` and both export writers at once. A `video.filters` entry must name
  BOTH `kind` and `amount` — `missing key "filters[0].kind" in a video patch` — because a list
  replaces whole, so an entry is merged over nothing and the keys it leaves out would be completed
  from the type's defaults into a half-strength blur nobody asked for; the file reader keeps that
  completion, so an older file still opens with the defaults it always had. `video.obscure` and
  `shape.gradient.stops` entries are NOT held to it: their omitted keys leave the entry recognisably
  the thing the caller named. `video.motion` (format version 8) deep-merges like every other nested
  object — `{"motion": {"in": …}}` keeps a stored `out`, and `{"motion": {"in": null}}` clears that
  slot alone. The APP's two writers still send the WHOLE object with nil slots as `null` (the
  inspector's Motion section and Clip ▸ Motion ▸ know all three slots), which is the same rule
  spelled out rather than a second one; an AGENT's patch is the caller's own object, forwarded
  unread (§7.9). `{"motion": null}` clears the field, and a motion whose three slots are all null is
  normalised to `null` before the range checks run, so one clip has one spelling of "no motion".
  `video.cutout` (format 39, §11 CO-20) merges too and `null` removes it; a `media`, `still` or
  `image` clip takes one (a text, shape, graphic, adjustment or nest clip is an **error** naming
  what it is), and `quality: "best"` is an error until Best masks are made. `subject:
  "foreground"` (format 41, §11 CO-100) is an image clip's only: on a `media` or `still` clip it
  is an **error** (`clip 3 is a media clip and cannot take a foreground cutout: only an image clip
  can`), from `set_video`, `paste` and `paste_attributes` alike.
  `video.crop`, `video.corner_radius` and `video.chroma` on a text, shape, graphic or adjustment
  clip (§11 #524, #536) are an **error** when the patch names one with a value other than neutral (a crop other
  than all zero, a radius other than 0, a chroma key other than `null`): `clip 5 is a text clip and
  cannot take a crop off a matte track`, `… cannot take a corner radius`, `… cannot take a chroma
  key`. It is read from the patch, as AU-111's duck is, so clearing is allowed and a value the
  clip already holds (a full `paste` keeps what its payload holds) is kept by every other edit;
  a crop is taken on a matte track, where it shapes the matte (§11 K-7, MT-4), but never on an
  adjustment clip, which is inert there (§11 GR-6): `clip 5 is an adjustment clip and cannot take
  a crop`. On a nest clip a `video.corner_radius` or `video.chroma` is an **error** the same way,
  on any track — `clip 7 is a nest clip and cannot take a corner radius`, `… cannot take a chroma
  key` — and a crop is taken: it draws on a nest (§11 #536, the owner's round-3 answer). `paste`
  is unchanged, and Paste Attributes leaves such a target's own (above).
  `set_action_end` refuses the same keys at an action's end (§11 #535).
  `video.behind_subject` (format 40, §11 CO-52) is a boolean: any drawing clip takes it but an
  adjustment or a nest clip, each an **error** naming what it is (`clip 4 is an adjustment clip and
  cannot be put behind a subject`), from `set_video`, `paste` and `paste_attributes` alike.
  `video.motion_blur` (format 42, §11 CU-113) is 0–1: above 0, a nest or an adjustment clip is an
  **error** naming what it is (`clip 9 shows a nest and cannot take motion blur: set it on the
  clips inside`, `clip 4 is an adjustment clip and cannot take motion blur`), from `set_video`,
  `paste` and `paste_attributes` alike; 0 removes the key.
  `video.hide_silent` (format 43, §11 CO-90…CO-92) is `{media, pre_roll, hold, fade}`, each time
  0–3,000,000 ticks (`video.hide_silent.fade must be between 0 and 3000000 ticks, not 3000001`);
  `media` must be named (`video.hide_silent.media is required: the media whose speech the clip
  follows`), a media of the project (`video.hide_silent.media 9 is not a media of this project`)
  with sound (`video.hide_silent.media 4 has no sound to follow`), and a nest clip refuses it
  (`clip 9 shows a nest and cannot hide while silent: set it on the clips inside`) — each an
  **error**, from `set_video`, `paste` and `paste_attributes` alike; `null` removes it. Paste and
  `paste_attributes` carry the gate's media as a non-shown row (the look LUT's rule, §11 GR-8): a
  row absorbed by path or appended, a payload without it dropping the gate.
  `audio.voice` (format version 34, §11 AU-140) merges the same way, and as `video.look` does, a voice
  merged over nothing must name `kind`: `{"voice": {"amount": 0.5}}` on a clip with no voice is an
  **error**, ``bad value at "voice" in an audio patch: missing field `kind` ``.
  `set_text` can patch `case`, `words` and `word_style` like any declared key (format version 9, §11
  W-10); a `words` entry must name both `start` and `end`, and a non-empty `words` whose length is
  not the content's token count is an **error** in the rule's own words — `this text is timed word
  by word: 4 timings for 5 words` — as are a word time outside D7-1's envelope, an `end` before its
  `start`, a `start` before the previous word's, and a `word_style` value out of range
  (`active_scale` 1.0–1.5, colours 0–1, a negative pill padding or radius, `pause_dim` 0–1 — format
  version 12, §11 W-12: `text.word_style.pause_dim must be between 0 and 1, not 2`). The check runs on what
  the caller sent; the word times are then snapped to the grid, nearest, a negative one staying
  negative. A content edit that changes the count sends `words: []` in the same patch.
- **`set_graphic {clips, patch, schema?}`** — Patches each graphic clip's `name`, `width`, `height`,
  `length` (`null`: it ends with the clip, `in` + the clip's duration — G-9·c; else snapped nearest,
  at least one frame) and `props`, which merges key by key: a value is stored in the key's own slot
  or appended, a `null` removes its key and the rest keep their order — unchecked, so a key the
  schema no longer has can still be removed — each other value checked as `add_graphic_clip` checks
  them, and the merged map holds at most 64 (an **error** naming the count). `in` is an **error** —
  `trim_start`, `roll`, `split` and `add_transition` move it (road map 10's G-9 and G-18, recorded
  here by G2b) — and so is a clip that is not a graphic, an unknown key and a malformed `schema`.
  With a `schema`, a `null` for a prop an action on the clip names stores the schema's default
  instead, so the action's ramp keeps a start (§11 G-34 (d)); without one, or for a key the schema
  lacks, it removes. The identity when nothing changes, a colour re-sent in another spelling
  included.
- **`set_clip {clips, patch: {name?: string | null, label?: string | null}}`** — The fifth patch op:
  sets or clears the clip's own name and label (§5.2). Inside the patch an absent key keeps, `null`
  clears, and so does an empty string — after the trim a name gets on its way in — because an
  unnamed clip is `null`, not `""`. Any other key is an **error**, checked before the clip ids. A
  patch rather than two optional `Option<T>` envelope arguments lets "keep" and "clear" differ. A
  `split`, `duplicate`, `detach_audio` or `paste` carries both along (they clone the clip);
  `paste_attributes` never does. Refuses if nothing changes.
- **`set_enabled {clip, video?, audio?}`** — Visibility/mute per clip.
