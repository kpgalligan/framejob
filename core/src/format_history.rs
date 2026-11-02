//! What each [`crate::format::RC_FORMAT_VERSION`] added, version by
//! version: the per-version paragraphs of its doc, moved here verbatim (a
//! pure move) so `format.rs` stays clear of the cap. No items.
//!
//! Version 2 is the M3 schema: nests (`project.nests`, and a nest CLIP
//! naming one by id instead of by path), filters, reflection, spotlight,
//! reversed media, and audio pan / compressor / noise reduction. Every one
//! of those fields carries a serde default, so a version-1 file reads
//! unchanged — with the single exception the nest payload's type change
//! forces, which [`migrate_1_to_2`](crate::format::migrate_1_to_2) handles.
//!
//! Version 3 is clip identity (road map 2, phase 2): `Clip.name`,
//! `Clip.label` and `Track.solo`. All three carry a serde default — `None`,
//! `None`, `false` — so a version-2 file reads unchanged and no migration
//! step exists for it; the bump is there so a version-2 build refuses a
//! file whose names and labels it would otherwise silently drop.
//!
//! Version 4 is hidden regions (road map 2, phase 3c):
//! [`crate::model::VideoProps::obscure`], a list of at most
//! [`crate::model::MAX_OBSCURE`] rectangles or ellipses each hiding what is
//! under it behind a blur or a pixelation. The list carries a serde default
//! — the empty one — so a version-3 file reads unchanged and there is again
//! no migration step; the bump is there for version 3's reason exactly,
//! that unknown keys are ignored at every level by design (`model.rs`'s
//! module doc), so without the version gate a version-3 build would open a
//! version-4 file, drop every region on read, and write the loss back over
//! the original on the next save. Nothing else phase 3 added persists a new
//! key: `ripple_delete_ranges` only removes time, and `add_zoom_action`
//! writes an ordinary [`crate::model::Action`] whose `end` patch is schema
//! that already existed.
//!
//! Version 5 is text animations (road map 2, phase 4c):
//! [`crate::model::TextProps::animation`], the kind of reveal a text layer
//! arrives and leaves with and how long each half takes. The field is an
//! `Option` and defaults to `None`, so a version-4 file reads unchanged and
//! there is no migration step for it either. The bump is there for
//! versions 3 and 4's reason exactly, and it is worth restating rather than
//! pointing at, because a defaulted field is precisely the case where the
//! bump looks like paperwork: unknown keys are ignored at every level by
//! design (`model.rs`'s module doc), so without the version gate a
//! version-4 build would open a version-5 file, drop every animation on
//! read, and write the loss back over the original on the next save —
//! silently, since the project still opens and the text is still there. It
//! is the fields that need NO migration whose loss is quietest. Nothing
//! else phase 4 added persists a new key: auto captions and caption export
//! both work in ordinary text clips through the ops that already existed,
//! and the per-frame reveal the animation produces is computed by
//! [`crate::recipe`] and never stored.
//!
//! Version 6 is looks (road map 2, phase 6): two keys, and this time on two
//! different groups. [`crate::model::VideoProps::blend`] is how a layer
//! combines with the canvas under it — a [`crate::model::BlendMode`], eight
//! of them, `Normal` being the source-over every project drew before the
//! key existed — and [`crate::model::ShapeProps::gradient`] is an optional
//! [`crate::model::Gradient`] that takes precedence over a shape's flat
//! `fill`. Both default (`Normal` and `None`), so a version-5 file reads
//! unchanged and there is no migration step.
//!
//! The bump is the point all the same, and the argument is written out here
//! rather than pointed at because a defaulted field is exactly the case
//! where it looks like paperwork. Unknown keys are ignored at every level by
//! design (`model.rs`'s module doc). So a version-5 build handed a version-6
//! file with no gate would OPEN it, drop every blend mode and every gradient
//! silently on read — the project still opens, the clips are all there, the
//! shapes are still shapes — and then write that loss back over the original
//! on the next save. What makes this version's loss quieter still than
//! version 5's is that a dropped blend does not remove anything from the
//! picture: the layer is still drawn, just source-over, so there is nothing
//! missing to notice. Nothing else phase 6 added persists a new key:
//! `add_background` and `add_blurred_background` build ordinary clips out of
//! schema that already existed.
//!
//! Version 7 is transitions, second pass (road map 5, E1): two keys on ONE
//! object. [`crate::model::Transition`] gains `curve`, how the progress the
//! compositor is handed is eased, and `audio`, whether the two clips'
//! SOUND crosses over with the picture at constant power. Both derive
//! their defaults — `Linear` and `false` — so a version-6 file reads
//! unchanged, renders the linear progress it always did, and is silent
//! about sound; there is no migration step. Three transition KINDS are
//! appended in the same version (`wipe_left`, `wipe_up`, `wipe_down`),
//! which need no gate of their own: an unknown kind was never readable by
//! an older build in the first place.
//!
//! The argument for bumping is version 5's and version 6's, and it is
//! written out again rather than pointed at, because the shape of the loss
//! here is different from both. The two new fields do not merely go
//! missing in a version-6 build — they are replaced by values that MEAN
//! something else. A transition the core minted says `ease_in_out` and
//! `audio: true`; drop those two keys and the same overlap reads as the
//! FILE default, linear and silent, which is a different transition drawn
//! with different sound and not an absence anybody would notice. That
//! divergence is deliberate and is spec §11's R5-2: what a NEW transition
//! is (`Transition::minted`) is not what an OLD file's transition is
//! (`Transition::default`), so an ungated round trip through a version-6
//! build would quietly rewrite every eased, crossfading transition in a
//! project as a linear, silent one. Nothing else E1 added persists a new
//! key: `add_transition` moves clips and writes a `transition_in` that
//! already had a home.
//!
//! Version 8 is motion (road map 5, E2): ONE key,
//! [`crate::model::VideoProps::motion`], an optional
//! [`crate::model::Motion`] holding up to three preset slots — an
//! entrance, an exit and a continuous motion. It defaults to `None`, so a
//! version-7 file reads unchanged and there is no migration step, and it
//! is the only key the version adds: `motion.rs` computes placement out of
//! it at render time and stores nothing, so the recipe publishes no
//! `motion` key and no layer key moved.
//!
//! The argument for bumping is versions 5, 6 and 7's, written out again
//! rather than pointed at because the shape of THIS loss is different
//! again. A version-7 build handed a version-8 file would open it, drop
//! every entrance, every exit and every continuous motion on read, and
//! write the loss back on the next save. What is lost is not a value that
//! comes back meaning something else, as version 7's two did, and not a
//! per-pixel property — the clip is still there, still on screen, still
//! placed exactly where it was placed. It simply no longer MOVES, and
//! there is nothing left in the file to say it ever did, which makes this
//! the quietest loss of the four: version 6's dropped blend at least left
//! a picture a careful reader could compare, where a preset that is gone
//! looks in every still frame exactly like a preset that was never
//! chosen.
//!
//! Version 9 is word captions (road map 8, W1b): THREE keys on the text
//! group, closing it in this order. [`crate::model::TextProps::case`] is a
//! transform applied before layout, `as_written` or `upper`;
//! [`crate::model::TextProps::words`] is one `{start, end}` per whitespace
//! token of `content`, in clip time, or empty for an untimed text; and
//! [`crate::model::TextProps::word_style`] is an optional
//! [`crate::model::WordStyle`] saying how the word being said is drawn. All
//! three default (`as_written`, `[]`, `None`), so a version-8 file reads
//! unchanged and there is no migration step. The per-frame `word` and
//! `word_pop` the recipe carries are computed by `recipe_words.rs` and
//! never stored.
//!
//! The argument for bumping is versions 5 through 8's, written out again
//! because the shape of THIS loss is different again: it is not one key but
//! the relation between two. A version-8 build handed a version-9 file
//! would open it, drop every page's timings and style on read and write
//! the loss back — and what is left is a page of text that is still on
//! screen for exactly as long as it was, still says every word it said,
//! and simply no longer knows WHEN any of them was spoken. The timings came
//! from a recogniser run over the audio; nothing in the file that survives
//! could rebuild them, so the loss is the one version whose repair is not a
//! click in the inspector but a second transcription.
//!
//! Version 10 is graphics (road map 10, G2a): a clip source kind,
//! `graphic`, and the clip key [`crate::model::Clip::graphic`], placed
//! after `shape` — a [`crate::model::GraphicProps`] naming the module in
//! the package's `graphics/` folder that draws it, the size it draws at,
//! its own `in` and `length`, and its `props` in the caller's key order.
//! The key defaults to `None` and a version-9 file has no graphic clips,
//! so there is again no migration step.
//!
//! The argument for bumping is the same as ever, and this loss is the
//! widest yet: a version-9 build cannot read a `graphic` source kind at
//! all, and one that could would drop every graphic clip's description —
//! which module, at what size, over which stretch of its timeline, with
//! which props — leaving a clip that draws nothing and a file with nothing
//! left in it to say what it drew.
//!
//! Version 11 is a copy's original (spec §11 #228-O): the media key
//! [`crate::model::Media::original`], placed last — the `{path, bookmark}`
//! of the WebM or Matroska file the app copied into a playable `.mov`, which
//! the app names, reveals and copies again when the copy is gone. It
//! defaults to `None`, so there is no migration step; an older build would
//! drop it and leave a media named after its copy, with nothing left to
//! copy it again from.
//!
//! Version 12 is three word-caption looks (spec §11, W-12): on
//! [`crate::model::ActivePill`], `glide`, placed last — the plate slides
//! from word to word — and on [`crate::model::WordStyle`], `active_fill`
//! and `pause_dim`, placed last in that order — the active word fills as it
//! is said, and the page dims in a pause. All three default to off, so
//! there is no migration step and a version-11 page draws as it did; an
//! older build would drop them and write back a page that no longer slides,
//! fills or dims, with nothing left in the file to say it ever did. The
//! recipe's `word_glide`, `word_fill` and `word_dim` are computed, never
//! stored.
//!
//! Version 13 is a graphic's props as action targets (spec §11 G-34): an
//! action's `end` may carry `graphic: {props, kinds}`, `props` before
//! `kinds`, `kinds` holding each named prop's schema type as
//! `set_action_end` wrote it. Nothing new is a typed field — an `end` is
//! stored as found — so there is no migration step, and a version-12 file
//! whose end already names `graphic` (G-10 kept it inert) now animates, its
//! colours switching at the end for want of `kinds`. The bump is so an older
//! build refuses the file instead of drawing every animated prop held at
//! its start.
//!
//! Version 14 is the matte track (spec §11 MT-1): the track key
//! [`crate::model::Track::matte`], placed after `solo` — `none`, `alpha`,
//! `alpha_inverted`, `luma` or `luma_inverted` — and written only when it is
//! not `none`, so an ordinary track, and every older file, writes exactly
//! the text it did. The reader's default is `none`, so there is no
//! migration step; an older build would drop the key and write back a
//! matte track as an ordinary one, its clips suddenly drawn over the
//! picture they were cutting.
//!
//! Version 15 is grading (spec §11 GR-2..GR-9). It is tone (GR-2): nine
//! keys on [`crate::model::ColorAdjust`] after `hue` — `exposure`,
//! `temperature`, `tint`, `highlights`, `shadows`, `whites`, `blacks`,
//! `vibrance`, `fade` — each written only when not 0, so an untoned project
//! writes exactly the text it did, and the reader's default is 0, so there
//! is no migration step for them. It is also the `adjustment` source kind
//! (GR-6), a new variant rather than an optional key: a build that does not
//! know it refuses the file with serde's "unknown variant `adjustment`", so
//! nothing is dropped silently. It is also `video.look` (GR-7), an optional
//! key written only when a clip has a look, so a look-less project writes
//! the text it did. It is also the `lut` kinds (GR-8): the media kind `lut`
//! and the look kind `lut` with its `media` key, written only on a LUT's
//! row and a LUT look — new variants, refused by name by a build that does
//! not know them, as `adjustment` is. The experiment's builds wrote the same
//! schema as 1015 ([`GRADING_BRANCH_VERSION`](crate::format::GRADING_BRANCH_VERSION));
//! [`read`](crate::format::read) reads that number as 15 in one step,
//! [`migrate_1015_to_15`](crate::format::migrate_1015_to_15).
//!
//! Version 16 is the wheels (spec §11 GR-11): [`crate::model::Wheels`] on
//! `video.wheels` — `lift`, `gamma` and `gain`, each `{x, y, master}` —
//! every key written only when not 0 and a neutral wheel not at all, so an
//! unwheeled project writes exactly the text it did, and the reader's
//! default is 0, so there is no migration step. The bump is so an older
//! build refuses the file instead of dropping the wheels on save.
//!
//! Version 17 is the curves (spec §11 GR-12): [`crate::model::Curves`] on
//! `video.curves` — `master`, `red`, `green` and `blue`, each a list of 2–16
//! `[x, y]` points — a channel written only when not the identity and
//! `curves` not at all when all four are, so an uncurved project writes
//! exactly the text it did, and the reader's default is the identity, so
//! there is no migration step. The bump is so an older build refuses the
//! file instead of dropping the curves on save.
//!
//! Version 18 is the qualifier (spec §11 GR-13): [`crate::model::Qualifier`]
//! on `video.qualifier` — `hue {center, width, softness}`, `saturation` and
//! `luma {low, high, softness}`, each absent when off, and `invert` written
//! only when true — the key written only when not neutral, so an
//! unqualified project writes exactly the text it did, and the reader's
//! default is neutral, so there is no migration step. The bump is so an
//! older build refuses the file instead of dropping the qualifier on save.
//!
//! Version 19 is camera log (spec §11 GR-16): [`crate::model::MediaColor`]
//! on `media.color` — `log`, `gamut`, `lut` and `detected`, each written
//! only when set (`detected` only when true) — the key written only when the
//! media has a setting, so a project with no Camera Log writes exactly the
//! text it did, and the reader's default is none, so there is no migration
//! step. The bump is so an older build refuses the file instead of dropping
//! the setting on save.
//!
//! Version 20 is the hue curves (spec §11 GR-32): `video.curves` gains
//! `hue_hue` and `hue_sat`, each a list of 2–16 `[hue, value]` points, a
//! channel written only when not the identity, so a project with no hue
//! curve writes exactly the text it did, and the reader's default is the
//! identity, so there is no migration step. The bump is so an older build
//! refuses the file instead of dropping the hue curves on save.
//!
//! Version 21 is the qualifier's cleanup blur (spec §11 GR-35):
//! `video.qualifier` gains `blur`, 0…1, written only when above 0, so a
//! project with no blurred qualifier writes exactly the text it did, and the
//! reader's default is 0, so there is no migration step. The bump is so an
//! older build refuses the file instead of dropping the blur on save.
//!
//! Version 22 is a PQ file's HDR10 peak (spec §11 HD-12):
//! [`crate::model_media_color::PqColor`] on `media.color.pq`, after
//! `detected` — `file` (the peak import read, whole cd/m²), `from`
//! (`max_cll` or `mastering_display`, exactly when `file` is) and `peak` (the
//! person's override), each written only when set, `{}` for a PQ file whose
//! import read nothing — written only on a PQ file's media, so a project with
//! none writes exactly the text it did, and the reader's default is none, so
//! there is no migration step: a PQ media from an older file has no `pq` and
//! renders at 1,000 cd/m² until imported again. The bump is so an older build
//! refuses the file instead of dropping the peak on save.
//!
//! Version 23 is the project's dynamic range (spec §11 HD-2, HD-13):
//! [`crate::model::CanvasOutput`] on `canvas.output`, `sdr` or `hlg`, after
//! `timecode_frames`, written only when `hlg`, so an SDR project writes
//! exactly the text it did, and the reader's default is `sdr`, so there is
//! no migration step. The bump is so an older build refuses an HLG file
//! instead of opening it as SDR and dropping its output on save.
//!
//! Version 24 is the canvas's blending (spec §11 GR-18, HD-9, HD-16):
//! [`crate::model::CanvasBlending`] on `canvas.blending`, `encoded` or
//! `linear`, after `output`, written only when `linear`, so every other
//! project writes exactly the text it did, and the reader's default is
//! `encoded`, so there is no migration step. The bump is so an older build
//! refuses a linear file instead of opening it encoded and dropping its
//! blending on save.
//!
//! Version 25 is Canon Log 2 and Canon Log 3 (spec §11 HD-17):
//! [`crate::model_media_color::LogCurve`] gains `canon_log2` and
//! `canon_log3`, and [`crate::model_media_color::CameraGamut`] gains
//! `cinema_gamut`, each Canon curve pairing with `cinema_gamut` (the default)
//! or `bt2020` on `media.color`. No key moves, so every other project writes
//! exactly the text it did, and there is no migration step. The bump is so an
//! older build refuses a Canon file instead of failing on its unknown
//! `log` value.
//!
//! Version 26 is a PQ still's HDR10 peak (spec §11 HD-20 (b)): an image
//! media whose decoded space is PQ-based carries `media.color.pq` as a PQ
//! video's media does (version 22), read from its PNG `cLLI`/`mDCV` or its
//! HEIF/AVIF `clli`/`mdcv`, and takes `peak`; a colour of `pq` alone is valid
//! on an image. No key moves, so every other project writes exactly the text
//! it did, and the reader's default is none, so there is no migration step: a
//! PQ still from an older file has no `pq` and renders at 1,000 cd/m² until
//! imported again. The bump is so an older build refuses the file instead of
//! refusing an image's `pq`.
//!
//! Version 27 is a clip's rate as an action target (spec §11 SR-10):
//! `actions[].end.speed`, a number beside the end's groups, which a media
//! clip ramps to along the action's curve and holds after. No key moves, so
//! every project without one writes exactly the text it did, and the reader's
//! default is none, so there is no migration step. The bump is so an older
//! build refuses the file: it would play a ramp at the clip's base rate,
//! losing nothing visible on save, and the ramp would be wrong with no sign.
//!
//! Version 28 is a linked pair (spec §11 AU-90): `clips[].linked`, the id
//! of the clip a clip is linked to, after `label`, written only when set —
//! Detach Audio's picture and sound name each other. A link is mutual and
//! inside one container, and a one-sided one is refused on open. No key
//! moves, so every project without one writes exactly the text it did, and
//! the reader's default is none, so there is no migration step. The bump is
//! so an older build refuses the file: it would open the pair as two
//! unrelated clips and drop the link on save.
//!
//! Version 29 is ducking by speech and fade shapes (spec §11 AU-110..AU-116):
//! `media.speech` (speech spans), `audio.duck`'s `mode`, `pre_roll` and
//! `hold`, `audio.fade_in_shape` and `fade_out_shape`, and
//! `transition_in.audio_shape`, each written only when not its default, so
//! every other project writes exactly the text it did and there is no
//! migration step. The bump is so an older build refuses the file rather than
//! ducking a speech duck over its whole clip and dropping the keys on save.
//!
//! Version 30 is the clip limiter (spec §11 AU-21): `audio.limiter`,
//! `{ceiling_db, release}` after `fade_out_shape`, written only when set,
//! so every project without one writes exactly the text it did, and the
//! reader's default is none, so there is no migration step. The bump is so
//! an older build refuses a limited file instead of opening it unlimited and
//! dropping the limiter on save.
//!
//! Version 31 is voice isolation (spec §11 AU-50): `audio.isolation`, after
//! `limiter`, written only when not 0, so every other project writes
//! exactly the text it did and there is no migration step. The bump is so an
//! older build refuses the file rather than playing the clip unisolated and
//! dropping the key on save.
//!
//! Version 32 is EQ, hum and channels (spec §11 AU-37): `audio.eq`,
//! `audio.hum` (each written only when set) and `audio.channels` (only when
//! not `both`); no migration. An older build would drop them on save.
//! Version 33 is the gate and de-esser (spec §11 AU-46): `audio.gate` and
//! `audio.de_esser`, each written only when set, after `channels`; no
//! migration.
//!
//! Version 34 is voice effects (spec §11 AU-140): `audio.voice`, after
//! `de_esser`, written only when set; no migration.
//!
//! Version 35 is a track's volume and pan (spec §11 AU-102):
//! `tracks[].volume` (linear, 0…4, default 1) and `tracks[].pan` (−1…1,
//! default 0), after `matte`, on the timeline's tracks and a nest's, each
//! written only when not its default; no migration. The bump is so an older
//! build refuses the file instead of playing every track at unity and centre
//! and dropping the keys on save.
//!
//! Version 36 is a track's compressor and limiter (spec §11 AU-150):
//! `tracks[].compressor` and `tracks[].limiter`, the clip's own two types,
//! after `pan`, each written only when set; no migration. The bump is so an
//! older build refuses the file instead of playing every track undynamic and
//! dropping the keys on save.
//!
//! Version 37 is the leveller (spec §11 AU-66): `audio.leveller`,
//! `{target_db, max_up_db, max_down_db, response}` after `voice`, written
//! only when set; no migration. The bump is so an older build refuses a
//! levelled file instead of playing it unlevelled and dropping the key on
//! save.
//!
//! Version 38 is the cursor (spec §11 CU-30, CU-39): `media[].cursor`,
//! `{path, bookmark?, in_picture}` after `speech`, and `video.cursor`, the
//! eight `CursorProps` keys after `look`, each written only when set; no
//! migration (CU-35). The bump is so an older build refuses a file with a
//! cursor instead of opening it and dropping the keys on save.
//!
//! Version 39 is the cutout (spec §11 CO-20, CO-23): `video.cutout`,
//! `{subject, quality, background, edge, feather}` after `cursor`, written
//! only when set; no migration. The bump is so an older build refuses a
//! file with a cutout instead of opening it and dropping the key on save.
//!
//! Version 40 is Behind Subject (spec §11 CO-52): `video.behind_subject`, a
//! boolean after `cutout`, written only when true; no migration. The bump
//! is so an older build refuses a file with the flag instead of drawing the
//! title uncut and dropping the key on save.
//!
//! Version 41 is a picture's cutout (spec §11 CO-100): `video.cutout.subject`
//! may be `foreground`, an image clip's only; no new key, no migration. The
//! bump is so an older build refuses the file instead of failing to read
//! the subject.
//! Every number from 42 up, 1014 included, is newer than this build.
