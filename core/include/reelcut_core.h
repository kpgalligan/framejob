/*
 * reelcut_core.h — the ONE contract between the Swift app and the Rust core.
 *
 * Hand-maintained: changing any `rc_*` signature means editing the Rust
 * `ffi_*.rs` file, this header, and `app/Sources/ReelCore.swift` in lockstep.
 *
 * Conventions, uniform across the surface:
 *
 *  - `RcProject` is an OPAQUE, IMMUTABLE handle. Every operation is pure:
 *    it returns a NEW handle and never mutates its input, so undo on the
 *    Swift side is a stack of handles.
 *  - Every export wraps its body in `catch_unwind`, tolerates NULL inputs,
 *    and never panics on any input.
 *  - Errors report through `char **err_out`: on failure the callee stores a
 *    heap C string there, which the caller frees with `rc_string_free`.
 *    A caught panic reports "internal error: <what>".
 *  - EVERY `char *` returned by this library is freed with `rc_string_free`.
 *  - Complex data crosses as UTF-8 JSON — the project, edit ops, the
 *    composition plan, the frame recipe — which keeps this header small and
 *    gives the MCP agent the same vocabulary. The schemas are the design
 *    spec's sections 5.2 (project), 6 (ops), 7.2 (plan) and 7.3 (recipe);
 *    the op table also lives in the module doc of `core/src/edit.rs`.
 *  - All times are TICKS: i64 at 600000 per second (`RC_TIMESCALE`).
 */

#ifndef REELCUT_CORE_H
#define REELCUT_CORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Ticks per second. Divides every common frame duration exactly (24, 25,
 * 30, 48, 50, 60, 120 fps and the /1001 rates), and CMTime at this
 * timescale round-trips without loss. */
#define RC_TIMESCALE 600000

/* Bumped by any change to the persisted project schema. The reader accepts
 * every prior version; the writer always writes this one.
 *
 * Version 2 is the M3 schema: nests, filters, reflection, spotlight,
 * reversed media, and audio pan / compressor / noise reduction. Version 3
 * is clip identity: a clip's `name` and `label`, and a track's `solo`.
 * Version 4 is `video.obscure`, the regions of a layer hidden behind a
 * blur or a pixelation. Version 5 is `text.animation`, the reveal a text
 * layer arrives and leaves with. Version 6 is looks: `video.blend`, how a
 * layer combines with the canvas under it, and `shape.gradient`, a ramp
 * that takes precedence over a shape's flat fill. Version 7 is
 * transitions, second pass: a transition's `curve`, how its progress is
 * eased, and `audio`, whether the two clips' sound crosses over at
 * constant power with the picture — plus three appended wipe directions.
 * Version 8 is motion: `video.motion`, up to three preset slots — an
 * entrance, an exit and a continuous motion — that the core turns into
 * placement at render time and never stores the result of.
 * None of the last six needed a migration step — every field they added
 * carries a serde default — but an older build must still refuse the newer
 * file rather than silently drop what it cannot read, which is what the
 * version is for. Version 7's loss would be louder than a drop: a minted
 * transition's eased, crossfading values would come back as the FILE
 * defaults, which mean a different transition rather than none. Version
 * 8's is the quietest of all: a clip whose motion was dropped is still on
 * screen, still placed where it was placed, and simply no longer moves,
 * with nothing left in the file to say it ever did.
 *
 * Version 9 is word captions: on the text group, `case` (a transform
 * applied before layout), `words` (one `{start, end}` per whitespace token
 * of `content`, in clip time) and `word_style` (how the word being said is
 * drawn), in that order, closing the object. All three default, so there
 * is again no migration step; an older build would drop a page's timings,
 * which nothing left in the file could rebuild short of transcribing the
 * audio again. The recipe's `word` and `word_pop` are computed, never
 * stored.
 *
 * Version 10 is graphics: a clip source kind `graphic` and the clip key
 * `graphic` after `shape` — `{name, width, height, in, length, props}`, the
 * module in the package's `graphics/` that draws it, its size, its own
 * timeline and its props in the caller's key order. It defaults to null,
 * so there is no migration step; an older build would drop every graphic
 * clip's description and leave a clip that draws nothing.
 *
 * Version 11 is a copy's original: the media key `original`, last —
 * `{path, bookmark}`, the WebM or Matroska file the app copied into a
 * playable .mov, which the app names, reveals and copies again when the copy
 * is gone. It defaults to null, so there is no migration step; an older
 * build would drop it and leave nothing to copy the media again from.
 *
 * Version 12 is three word-caption looks: `glide` last on
 * `word_style.active_pill` (the plate slides from word to word), and
 * `active_fill` and `pause_dim` last on `word_style`, in that order (the
 * active word fills as it is said; the page's opacity in a pause is
 * `1 - pause_dim`). All three default to off, so there is no migration step
 * and an older page draws as it did; an older build would drop them. The
 * recipe's `word_glide`, `word_fill` and `word_dim` are computed, never
 * stored.
 *
 * Version 13 is a graphic's props as action targets: an action's `end` may
 * carry `graphic: {props, kinds}`, `props` before `kinds`, `kinds` holding
 * each named prop's schema type as set_action_end wrote it. An end is
 * stored as found, so there is no migration step; a version-12 end that
 * already names `graphic` now animates, its colours switching at the end.
 * An older build would draw every animated prop held at its start.
 *
 * Version 14 is the matte track: `matte` after `solo` on a track — `none`,
 * `alpha`, `alpha_inverted`, `luma` or `luma_inverted` — written only when
 * it is not `none`, so an ordinary track writes the text it did. The
 * default is `none`, so there is no migration step; an older build would
 * drop the key and draw a matte track's clips over the picture they cut.
 *
 * Version 15 is grading (spec §11 GR-2..GR-9): tone, nine keys on
 * `video.color` after `hue`, each written only when not 0, the `adjustment`
 * source kind (GR-6), which a build that does not know it refuses as an
 * unknown variant, and `video.look` (GR-7), written only when a clip has a
 * look, and the `lut` kinds (GR-8): the media kind `lut` and the look kind
 * `lut` with its `media` key, new variants an older build refuses by name.
 * A file numbered 1015 (the grading branch's builds, GR-9) is read as 15 by
 * one migration step.
 *
 * Version 16 is the wheels (spec §11 GR-11): `video.wheels {lift, gamma,
 * gain}`, each `{x, y, master}`, every key written only when not 0 and a
 * neutral wheel not at all, so an unwheeled project writes the text it did;
 * the reader's default is 0, so there is no migration step.
 *
 * Version 17 is the curves (spec §11 GR-12): `video.curves {master, red,
 * green, blue}`, each a list of 2–16 `[x, y]` points, a channel written only
 * when not the identity and the key not at all when all four are, so an
 * uncurved project writes the text it did; the reader's default is the
 * identity, so there is no migration step.
 *
 * Version 18 is the qualifier (spec §11 GR-13): `video.qualifier {hue,
 * saturation, luma, invert}` on an adjustment clip — `hue {center, width,
 * softness}` in degrees, `saturation` and `luma {low, high, softness}` in
 * 0…1, each absent when off, `invert` written only when true — the key not
 * written at all when neutral, so an unqualified project writes the text it
 * did; the reader's default is neutral, so there is no migration step.
 *
 * Version 19 is camera log (spec §11 GR-16): `media.color {log, gamut, lut,
 * detected}`, written only when set — `log` one of `apple_log`, `slog3`,
 * `vlog`, `apple_log2`, `gamut` the camera gamut it pairs with, `lut` a
 * `lut` media converting the file instead, `detected` only when true — so a
 * project with no Camera Log writes the text it did; the reader's default is
 * none, so there is no migration step. 20 and above, 1014 included, are
 * newer. */
#define RC_FORMAT_VERSION 19

/* Reader caps enforced by the writer, so every file this build produces can
 * be read back (the `MAX_*` constants in core/src/format.rs). A nest's tracks and clips
 * count toward the same two caps as the timeline's. */
#define RC_MAX_CLIPS 4096
#define RC_MAX_TRACKS 64
#define RC_MAX_MARKERS 1024
#define RC_MAX_NEST_DEPTH 8

typedef struct RcProject RcProject;

/* ---------------------------------------------------------------- memory */

/* Frees any string this library returned (results and `err_out` messages).
 * NULL-tolerant. */
void rc_string_free(char *s);

/* --------------------------------------------------------------- project */

/* A new empty project: one track, no media, no clips. Returns NULL for a
 * zero dimension or a zero fps numerator/denominator. */
RcProject *rc_project_new(uint32_t width, uint32_t height, uint32_t fps_num, uint32_t fps_den);

/* Parses project JSON of ANY format version this build knows. NULL with a
 * message through `err_out` on malformed or out-of-cap input. */
RcProject *rc_project_from_json(const char *json, char **err_out);

/* The project as JSON at RC_FORMAT_VERSION. NULL only for a NULL project. */
char *rc_project_to_json(const RcProject *p);

/* Deep-copies the handle. NULL-tolerant. */
RcProject *rc_project_clone(const RcProject *p);

/* The project INSIDE nest `nest_id`, as a new handle: its tracks and clips at
 * the top level, its frozen size as the canvas, the parent's rate, media,
 * nests and next id, and no markers. The SAME view an op carrying
 * `"scope": nest_id` is applied to (core/src/scope.rs), so what the host
 * draws from this handle and what its edits land in cannot disagree.
 *
 * The READ half of a scope: the host plays, plans, renders and snapshots a
 * nest through this handle while every edit still goes to the PARENT handle
 * with `scope` set. Applying an op to this handle edits the view rather than
 * the document, which is not what any caller wants; nothing enforces it.
 *
 * NULL with a message through `err_out` for a NULL project or a nest id this
 * project has not got ("no nest with id N"). There is no "valid but changes
 * nothing" case here, so a NULL return ALWAYS carries a message. The handle
 * is freed with rc_project_free. */
RcProject *rc_project_scoped(const RcProject *p, uint32_t nest_id, char **err_out);

void rc_project_free(RcProject *p);

/* ----------------------------------------------------------------- edits */

/* THE one edit entry point. `op` is `{"op": "<name>", ...args}` — the table
 * in the module doc of core/src/edit.rs and spec section 6.
 *
 * One key of that object is NOT an argument: `"scope"`, an optional nest id
 * (core/src/scope.rs, spec section 6). With it the op is applied INSIDE that
 * nest — its tracks and clips at the top level, its own zero as time zero —
 * and the result is still a whole project, so undo stays a stack of these
 * handles. Absent and null both mean the timeline. Eight ops have no meaning
 * in a nest and are an error naming themselves and it (the three marker ops,
 * set_canvas, the three media ops, and add_adjustment_clip), and a scoped op has a WIDER error
 * arm than an unscoped one: the clip and track caps and the nesting depth are
 * document-wide and invisible from inside a nest, so an op can be valid
 * against the nest and still come back "too many clips", "too many tracks" or
 * "nests are more than 8 deep at nest N". A caller must not assume a valid
 * scoped edit landed.
 *
 * Returns a NEW project on success. Returns NULL in three distinguishable
 * cases, which is why there are two message channels and not one:
 *   - NEITHER written (both still NULL): the op is valid and nothing needed
 *     to change — an identity edit. The caller registers NO undo step (an
 *     identity edit that registered one is a phantom undo step), and tells
 *     its own caller only that: a rule named here would be a rule the caller
 *     did not break.
 *   - `*reason_out` SET: a rule refused the op, and this is that rule's own
 *     sentence, naming what the caller could act on ("clips 3 and 4 would
 *     overlap by 8000 ticks, more than half of the shorter clip (6000
 *     ticks)"). Still NO undo step, and NOT an error: the project is exactly
 *     as it was, and the UI beeps or animates the gesture back.
 *   - `*err_out` SET: the op or its arguments are invalid.
 * The two channels are never both written, and `reason_out` may be NULL for
 * a caller that does not want the sentence. The caller must therefore
 * initialise its `char *err = NULL; char *reason = NULL;` before the call
 * and test both after a NULL return. Either message is freed with
 * rc_string_free. */
RcProject *rc_project_apply(const RcProject *p, const char *op, char **err_out,
                            char **reason_out);

/* Every op name `rc_project_apply` accepts, as a JSON array of strings in
 * the order of that table. The host reads it to check its MCP tool catalog
 * covers the whole table; the core owns the list so no copy can drift from
 * it. Never NULL. */
char *rc_op_names(void);

/* Every op's ARGUMENTS as JSON Schema: a JSON object mapping each name
 * rc_op_names reports to
 *   {"type": "object", "properties": {...}, "required": [...]}
 * for that op, with one property per argument — an id is an integer with a
 * minimum of 0, ticks an integer (a delta is negative), a closed vocabulary
 * a string with its members enumerated, and a caller-authored patch an
 * object with NO declared properties, because the core is the one validator
 * of what a patch may carry and this says only that an object belongs there.
 *
 * The host merges its own PROSE over this to build its MCP tool schemas: the
 * core says what an argument is, the host says what it is for. The envelope's
 * "scope" is not an argument of any op and is in no schema here; the host
 * injects it, as it does "project".
 *
 * A query — no handle, nothing persisted changes, and never NULL. */
char *rc_op_schemas(void);

/* Every number about a clip's speed, as a JSON object:
 *   {"min":0.1,"max":1000.0,"audio_max":12.0}
 * "min"/"max" are the range set_speed clamps to and the reader refuses
 * outside; "audio_max" is the speed above which the composition plan leaves
 * a clip's audio out, in both pitch modes (spec §11 #190). The core
 * is the one home of these numbers; the host reads them here.
 *
 * A query — no handle, nothing persisted changes, and never NULL. Freed with
 * rc_string_free. */
char *rc_speed_limits(void);

/* --------------------------------------------------------------- queries */

/* End of the last clip, in ticks. 0 for an empty project or NULL. */
int64_t rc_project_duration(const RcProject *p);

/* The composition plan (spec 7.2): what Swift builds an AVMutableComposition,
 * AVMutableAudioMix and AVVideoComposition.Configuration from. Swift asks for this
 * after every edit and rebuilds ONLY when the JSON differs from the current
 * plan — the plan holds exactly the structural facts. */
char *rc_project_composition_plan(const RcProject *p);

/* The frame recipe at time `t` (spec 7.3): the back-to-front layer list with
 * every property already evaluated through actions. Asked once per composed
 * frame, and by the canvas overlay for hit-testing and handles. */
char *rc_project_frame_recipe(const RcProject *p, int64_t t);

/* The same recipe, with the caller's OPTIONS. `opts_json` is
 * {"burn_in_timecode": bool, "ungraded": bool, "selection": clip id,
 * "behind": clip id} (any key may be absent) —
 * or NULL, which is the defaults and is exactly what rc_project_frame_recipe
 * asks for, the two being one implementation.
 *
 * `ungraded` (spec 11 GR-4) writes every layer's `color` neutral — all
 * thirteen keys — and its `wheels` neutral — all nine (spec 11 GR-11) —
 * nested and matte layers included, and adds no layer. It keeps a qualifier
 * (spec 11 GR-13).
 *
 * `selection` (spec 11 GR-13) marks that top-level adjustment clip's layer
 * (`"selection": true` in its source: the compositor writes its qualifier's
 * selection as grey) and leaves out every layer in front of it that is not
 * drawn into a matte; when no such layer is on the frame there are no layers
 * and the background is black. `behind` leaves out that layer and the same
 * layers in front of it (none found: the recipe unchanged) — the picture the
 * clip reads. A clip id is a whole number; anything else is OFF.
 *
 * `burn_in_timecode` APPENDS a text layer (so, last: topmost) showing the
 * project timecode at `t`, spelled by the document's own timecode_frames, in
 * a monospaced face on a backdrop, placed at a fraction of the canvas height
 * below its centre — the core stores no measured text size (spec 5.3, 11), so
 * a burn-in cannot be anchored to the bottom EDGE of the frame. It is
 * non-drop, like every timecode this library formats, and on an in/out range
 * export it reads PROJECT time rather than the time in the file.
 *
 * The option lives here rather than in rc_export_settings' overrides because
 * an unknown override key is IGNORED, so an option posted that way would
 * vanish and an export would report success on an un-burnt file. It changes
 * the picture, so it travels with the description of the picture.
 *
 * An `opts_json` that is not JSON answers NULL — a query has no err_out. A
 * key that is absent, of the wrong type, or in a document that is not an
 * object simply means OFF, so a caller that spells one wrong gets the frame
 * it would have got before the option existed rather than a black one. */
char *rc_project_frame_recipe_opts(const RcProject *p, int64_t t, const char *opts_json);

/* One clip's evaluated properties at time `t` (project time), for the
 * inspector. NULL if the clip id is unknown. */
char *rc_project_clip_state(const RcProject *p, uint32_t clip, int64_t t);

/* Snap candidates for a timeline drag: a JSON object with sorted tick
 * arrays. `exclude_clips_json` is a JSON array of clip ids to omit (the
 * clips being dragged), or NULL for none. */
char *rc_project_snap_candidates(const RcProject *p, const char *exclude_clips_json);

/* Nearest candidate to `t` within `threshold` ticks, else `t`. `candidates_json`
 * is a JSON array of ticks. `snapped_out` (optional) reports whether a
 * candidate was taken. */
int64_t rc_snap_resolve(const char *candidates_json, int64_t t, int64_t threshold,
                        bool *snapped_out);

/* ------------------------------------------------------------------ time */

/* Rounds `t` to the nearest frame boundary of `fps_num`/`fps_den`. Returns
 * `t` unchanged for a degenerate rate. */
int64_t rc_time_snap_to_frame(int64_t t, uint32_t fps_num, uint32_t fps_den);

/* Non-drop timecode: "HH:MM:SS:FF" when `frames`, else "HH:MM:SS.mmm".
 * Negative times get a leading '-'. */
char *rc_timecode_format(int64_t t, uint32_t fps_num, uint32_t fps_den, bool frames);

/* Parses "HH:MM:SS:FF", "MM:SS", "SS.sss" and "HH:MM:SS.mmm" into ticks.
 * false (and `*out` untouched) when the text is not a time. */
bool rc_timecode_parse(const char *s, uint32_t fps_num, uint32_t fps_den, int64_t *out);

/* ---------------------------------------------------------------- colour */

/* A CSS colour (spec §11 G-12) as lowercase "#rrggbb", or "#rrggbbaa" when not opaque — what a
   stored `color` prop holds. NULL when `text` is NULL or G-12 refuses it. Freed with rc_string_free. */
char *rc_normalise_color(const char *text);

/* ---------------------------------------------------------------- export */

/* The export presets as a JSON array (spec 7.8), in menu order: one row per
   ENCODING — a container and a codec — with no size of its own, so that an
   export is at the document's size unless a size is asked for. The two
   image formats are the exception and carry the cap 7.8 argues. The FIRST
   row is the default the export sheet opens on.

   Three of the rows are audio only: `audio_m4a` (AAC) is what you send,
   and `audio_wav` / `audio_aiff` are 16-bit LPCM at 48 kHz — what you hand
   to somebody else's tool, where a second lossy generation is the one
   thing you cannot take back. A row's `avf_preset` means only
   "AVFoundation can write this row": `null` is what routes an export to
   the frame-by-frame ImageIO writer (the two image formats), and since
   AVFoundation publishes no LPCM export preset the two new rows repeat the
   M4A row's name rather than carrying a null that would hand a WAV to the
   image writer. Read it as a record, never as an instruction. */
char *rc_export_presets(void);

/* The output sizes the export sheet offers for `preset_id` against this
   project, as a JSON array of {id, name, width, height} in menu order. The
   FIRST row is the default: the document's own size ("document"), or for an
   image format its cap ("preset"). On a row that needs even pixel dimensions
   — every row AVFoundation writes but `prores_4444` — the "document" row
   holds the canvas with an odd edge made one pixel smaller, the size the
   file will have, and is named "Document (even)" when that is not the
   canvas's own size; everywhere else it is named "Document size" and is the
   canvas as it is (spec §11 G-33). After it come the standard sizes fitted to
   the document's aspect — "2160p" (named 4K), "1440p", "1080p", "720p": the
   number is the SHORT edge, the long edge follows the document, rounded to
   even. On an image format every row's numbers are the canvas fitted inside
   that box, never upscaled — the size the file will have. A row may repeat an
   earlier row's numbers (a 1920 × 1080 document's "1080p" is its own size)
   and is listed anyway, since an id must mean the same thing on every
   document; the sheet hides repeats. NULL with a message through `err_out`
   for a NULL project, a NULL `preset_id`, or an unknown preset. */
char *rc_export_sizes(const RcProject *p, const char *preset_id, char **err_out);

/* A preset plus optional `overrides_json` resolved against the project into
 * concrete settings. NULL with a message through `err_out` for an unknown
 * preset or bad overrides.
 *
 * The overrides are `width` and `height` in pixels (each strictly
 * positive, and each alone leaves the other the document's), `fps`,
 * `range`, `optimize_for_network`, the two bitrates in bits per second
 * (`video_bitrate`, `audio_bitrate`) and the two loudness figures
 * (`loudness_lufs`, the integrated target an export is normalised to,
 * -70..0; `peak_dbtp`, the true-peak ceiling the gain is capped against,
 * -20..0). Absent and explicit null both mean "use the preset", an
 * unknown key is ignored so a newer UI still gets an export, and a value
 * out of range or of the wrong type is an error naming the key and the
 * value. One pairing rule, and it is the table's only one: a `peak_dbtp`
 * with no `loudness_lufs` is an error, because normalisation is gain-only
 * and a ceiling with nothing to cap would be accepted, echoed and
 * silently inert. Neither loudness key appears in the resolved settings
 * unless it was asked for.
 *
 * Note what is NOT in that list: there is no `size` key. A size is two
 * numbers here. `rc_export_sizes`' row ids ("1080p", "document") are the
 * SHEET's vocabulary and a caller resolves one into `width` and `height`
 * before calling this.
 *
 * The paragraph above is checked rather than trusted: `core/tests/export.rs`
 * reads its backticked keys back out of THIS file and sends each one a
 * value no reader accepts, so a key named there that nothing reads fails
 * the suite. It has to be checked, because the ignore-unknown rule is
 * exactly what makes a wrong name silent — settings that resolve, at the
 * document's size, reported ok.
 *
 * The resolved `width` and `height` are the size the FILE will have, which
 * is not always the pair that was asked for. On a row that needs even pixel
 * dimensions (every row AVFoundation writes but `prores_4444`) an odd edge
 * comes back one pixel smaller and an edge below 2 comes back 2, whether it
 * was the canvas's or an override's; on the two image formats the pair is
 * the canvas fitted inside the size, never upscaled; `prores_4444` answers
 * the pair as it stands, odd or not (spec §11 G-33). So a caller prints
 * these two numbers and never the ones it sent.
 *
 * One key of the RESOLVED settings needs its meaning stated, because the
 * obvious reading of the name is the wrong one: `alpha` is a capability of
 * the ENCODING — "this row carries an alpha channel" — and is true for
 * `prores_4444`, `hevc_alpha` and `apng`, and for nothing else. It is not
 * "this project's canvas is translucent". `gif` is false and `apng` is true
 * although both can show a transparent pixel: APNG has a real fourth
 * channel and a pixel may be any fraction of opaque, while a GIF
 * nominates ONE palette index as transparent and has no partial value to
 * store, so a soft edge against nothing comes out hard.
 * The settings are one flat object with the same shape for every row, so a
 * project-derived flag would report it true on an H.264, a GIF and a WAV,
 * none of which has anywhere to put a fourth channel; it is the same kind
 * of fact as `audio`, which says what the CONTAINER can hold and not
 * whether this timeline has any sound in it. A transparent canvas exported
 * through any other row is composited onto black. */
char *rc_export_settings(const RcProject *p, const char *preset_id, const char *overrides_json,
                         char **err_out);

/* -------------------------------------------------------------- graphics */

/* The motion-graphics engine (road map 10 §5e), linked from the `graphic`
 * crate through `core/src/ffi_graphic.rs`, the one module that names it.
 *
 * `RcGraphicLibrary` is a font and asset set being BUILT: `add_font` and
 * `add_asset` fill it until the first `rc_graphic_compile` or
 * `rc_graphic_rasterize` against it FREEZES it, after which an add answers
 * false with `err_out` = "the library is frozen: a graphic was compiled or
 * a frame drawn against it; build a new one". So a library never changes
 * under a compiled graphic. `RcGraphic` is one compiled module; it keeps the
 * library's fonts alive, so the two may be freed in either order.
 *
 * `diag_out` is NULL or a JSON ARRAY of Diagnostics, each
 * {"level","message","line","column","frame"} in that order (an absent
 * position is null). On failure it always holds exactly ONE error: the
 * engine's own, or the FFI's for an argument it could not read ("library
 * is NULL", "name is NULL", "source is NULL", "graphic is NULL", "svg is
 * NULL", "out_bgra is NULL", "ctx_json is NULL", "props_json is not JSON:
 * …", "ctx_json is not JSON: …", "height × stride overflows"), or
 * "internal error: <what>" for a caught panic. On success it is written only
 * when there are warnings. NULL `diag_out` and `err_out` are tolerated; every
 * `char *` here is freed with `rc_string_free`. */
typedef struct RcGraphicLibrary RcGraphicLibrary;
typedef struct RcGraphic RcGraphic;

/* The largest width or height a graphic draws at, in pixels (G-7): the
 * engine's `MAX_SIDE` and the core's `GRAPHIC_MAX_SIDE`, which
 * core/tests/graphic_ffi.rs pins equal to this. The app reads it as
 * `GraphicLibrary.maxSide`. */
#define RC_GRAPHIC_MAX_SIDE 8192

/* A new, empty library. Never NULL. */
RcGraphicLibrary *rc_graphic_library_new(void);

/* Adds one font file's bytes. False with `err_out` for a NULL argument
 * ("bytes is NULL"), bytes that load no face ("font bytes loaded no face"),
 * or a frozen library. */
bool rc_graphic_library_add_font(RcGraphicLibrary *lib, const uint8_t *bytes, size_t len,
                                 char **err_out);

/* Adds one asset under `name`, the string an `<image href>` names. False with
 * `err_out` for a NULL argument, an empty name ("name is empty"), a name
 * already added ("asset \"<name>\" is already in the library"), or a frozen
 * library. */
bool rc_graphic_library_add_asset(RcGraphicLibrary *lib, const char *name, const uint8_t *bytes,
                                  size_t len, char **err_out);

/* The frozen library's families as a JSON array of strings, sorted and
 * deduplicated — the exact names a `font-family` must match (freezes the
 * library as a compile would). NULL only for NULL. */
char *rc_graphic_library_families(const RcGraphicLibrary *lib);

/* Releases a library. NULL-tolerant. */
void rc_graphic_library_free(RcGraphicLibrary *lib);

/* Compiles `source` as the ES module `name` against `lib` (freezing it); its
 * top level runs under a deadline of `budget_ms`. NULL with one error through
 * `diag_out` on failure. Freed with `rc_graphic_free`. */
RcGraphic *rc_graphic_compile(const RcGraphicLibrary *lib, const char *name, const char *source,
                              uint32_t budget_ms, char **diag_out);

/* {"meta":…,"schema":…,"revision":…,"warnings":[…]}: the module's exported
 * meta and schema in its own key order, the SHA-256 of its source as 64 hex
 * digits, and what its top level warned as it loaded, shaped as `diag_out`'s
 * entries ([] when none). NULL only for a NULL graphic. */
char *rc_graphic_describe(const RcGraphic *g);

/* The SVG of `frame`: `props_json` overlaid on the schema's defaults (NULL is
 * `{}`; a value the schema does not take is a warning, and the default is
 * used), `ctx_json` the context object, run under `budget_ms`. NULL with one
 * error through `diag_out` on failure. */
char *rc_graphic_svg(const RcGraphic *g, int64_t frame, const char *props_json,
                     const char *ctx_json, uint32_t budget_ms, char **diag_out);

/* Draws `svg` with `lib`'s fonts and assets (freezing it) into `out_bgra`:
 * `w`×`h` premultiplied BGRA rows `stride` bytes apart; the buffer holds
 * `h × stride` writable bytes, and the bytes past `w × 4` in a row are left
 * untouched. False with one error through `diag_out`, and nothing written,
 * on failure. */
bool rc_graphic_rasterize(const RcGraphicLibrary *lib, const char *svg, uint32_t w, uint32_t h,
                          uint8_t *out_bgra, size_t stride, char **diag_out);

/* Releases a graphic. NULL-tolerant. */
void rc_graphic_free(RcGraphic *g);

/* ------------------------------------------------------------- container */

/* A WebM or Matroska file being imported, read as an INDEX (spec §11
 * #216-R) through `core/src/ffi_container.rs`: its first video and first
 * audio track and where each frame's bytes lie, which the app copies
 * unchanged into a QuickTime movie. The file is opened read-only; nothing
 * is decoded. A truncated or damaged Cluster tail ends the index, so a cut
 * file opens shorter.
 *
 * `rc_container_describe` answers, with exactly these keys:
 *   {"doc_type":"webm"|"matroska", "required_bytes":N,
 *    "video":null|{"codec_id","fourcc":"vp09"|"av01"|"avc1"|"hvc1"|"vp08"|null,
 *      "encoded":bool,"width","height","atom":"vpcC"|"av1C"|"avcC"|"hvcC"|null,
 *      "atom_hex","vp9_profile":int|null,"nominal_fps":f64|null,"timescale",
 *      "grid":bool,"samples","bytes"},
 *    "audio":null|{"codec_id","fourcc":"opus"|"vorb"|"aac "|null,"encoded":bool,
 *      "sample_rate","channels","cookie_hex","frames_per_packet":0|1024,
 *      "timescale","samples","bytes"}}
 * A track is null when the file has none or none of its frames. `fourcc`
 * null, or `encoded` (a ContentEncodings element), means the track is not
 * copied: its `samples` and `bytes` are then 0. `required_bytes` is the
 * copied payload + 64 × the copied samples + 16 MiB. `video.timescale` is
 * the one the samples are in NOW: fps num after a `rc_container_retime`
 * that answered true, else the raw timescale (1e9 / TimestampScale when
 * exact, else 1000000). For Vorbis (`"vorb"`, spec §11 #228-V),
 * `sample_rate` and `channels` are the identification header's, and its
 * `fourcc` is null when the headers cannot be read. A sample's times are in
 * its track's `timescale`; samples come in decode order. */
#define RC_CONTAINER_VIDEO 0
#define RC_CONTAINER_AUDIO 1

typedef struct RcContainer RcContainer;

typedef struct RcContainerSample {
    uint64_t offset;
    uint32_t size;
    uint32_t frames; /* audio: samples in this packet (0 = describe's frames_per_packet); video: 0 */
    int64_t pts;
    int64_t dts;
    int64_t duration; /* in the track's describe `timescale` */
    bool sync;
} RcContainerSample;

/* Opens and indexes the whole file at `path`. NULL with a lowercase reason
 * through `err_out` ("path is NULL", "it does not begin with an EBML
 * header", "its DocType is “x”, not webm or matroska", "track N's
 * CodecPrivate is B bytes, over the 1 MiB limit", "track N has laced video
 * Blocks and no DefaultDuration, so its frames have no times", …). Freed
 * with `rc_container_free`. */
RcContainer *rc_container_open(const char *path, char **err_out);

/* The JSON above. NULL only for NULL. */
char *rc_container_describe(const RcContainer *container);

/* Snaps the video to the fps_num/fps_den grid when every frame lies within
 * a quarter frame of a grid point and no two share one: true, `grid` true,
 * frame k at k × fps_den in a timescale of fps_num. Otherwise false and the
 * raw times stay. False for NULL or a term outside 1…UINT32_MAX. Not to be
 * called while another thread reads the container. */
bool rc_container_retime(RcContainer *container, int64_t fps_num, int64_t fps_den);

/* The copied samples of `track` (RC_CONTAINER_VIDEO or RC_CONTAINER_AUDIO);
 * 0 for NULL, another track, or a track not copied. */
uint64_t rc_container_sample_count(const RcContainer *container, uint32_t track);

/* Writes sample `index` of `track` through `out`; false, `out` untouched,
 * for NULL or an index past the count. */
bool rc_container_sample(const RcContainer *container, uint32_t track, uint64_t index,
                         RcContainerSample *out);

/* Releases a container. NULL-tolerant. */
void rc_container_free(RcContainer *container);

/* ------------------------------------------------------------------ cube */

/* A `.cube` 3D LUT (spec §11 GR-8), parsed by the core so the import probe
 * and the compositor read one file the same way. Read: 3D only,
 * LUT_3D_SIZE 2–65, TITLE, `#` comment lines, blank lines, CRLF, a UTF-8
 * BOM, and DOMAIN_MIN 0 0 0 / DOMAIN_MAX 1 1 1 / LUT_3D_INPUT_RANGE 0 1 (the
 * defaults); table values any finite number. Everything else is refused by
 * a lowercase sentence naming the 1-based line ("line 2: LUT_3D_SIZE 200 is
 * outside 2–65", "line 4: LUT_1D_SIZE is a 1D LUT; only 3D LUTs are read",
 * "line 3: DOMAIN_MIN must be 0 0 0, not 0 0 -0.1", "line 5: unknown
 * keyword FOO", "line 9: FOO comes after the table", "line 3: a second
 * LUT_3D_SIZE", "line 3: DOMAIN_MAX needs 3 numbers", "line 7: \"0.5x\" is
 * not a number", "line 7: nan is not a finite number", "line 7: a table row
 * has 3 numbers, not 2", "no LUT_3D_SIZE line", "LUT_3D_SIZE 33 needs 35937
 * table rows, not 35936", "the file is larger than 32 MB", "the file is not
 * text"). An RcCube is immutable and may be read from any thread. */
#define RC_CUBE_MAX_BYTES 33554432

typedef struct RcCube RcCube;

/* Parses `len` bytes at `bytes`. NULL with the sentence above through
 * `err_out` (or "bytes is NULL"). Freed with `rc_cube_free`. */
RcCube *rc_cube_parse(const uint8_t *bytes, size_t len, char **err_out);

/* Points an axis, 2–65; 0 for NULL. */
uint32_t rc_cube_size(const RcCube *cube);

/* Copies the table into the `count` floats at `out`: size³ rows of red,
 * green, blue, red changing fastest, then green, then blue (a 3D texture's
 * texel order). False, `out` untouched, for NULL or unless count is
 * size³ × 3. */
bool rc_cube_copy_rgb(const RcCube *cube, float *out, size_t count);

/* Releases a LUT. NULL-tolerant. */
void rc_cube_free(RcCube *cube);

/* ----------------------------------------------------------------- agent */

/* C signature of the host tool handler. Called from the server thread for
 * every `tools/call`. Must return a CallToolResult JSON object allocated
 * with `rc_agent_string_create` (ownership passes back across the return),
 * or NULL for handler failure. */
typedef char *(*RcAgentToolHandler)(void *context, const char *tool_name,
                                    const char *arguments_json);

/* Allocates a NUL-terminated copy of `s` owned by this library, for tool
 * handlers to return. Never freed by the caller. */
char *rc_agent_string_create(const char *s);

/* Binds the embedded MCP server's Unix-socket listener at `socket_path`,
 * chmod 0600. `tools_json` is the `tools/list` catalog as a JSON array.
 * True, or false with a message through `err_out`.
 * One per process: a second start is an error ("agent socket already
 * bound"). Never unlinks an existing file. */
bool rc_agent_socket_start(const char *socket_path, const char *server_name,
                           const char *server_version, const char *tools_json,
                           RcAgentToolHandler handler, void *context, char **err_out);

/* For quit. Takes the listener out of its slot and unlinks the socket file
 * only if it is still the one this listener bound (same device and inode),
 * then abandons the listener: its thread is neither unblocked nor joined, so
 * a call in flight cannot hold the quit, and process exit ends it. `handler`
 * and `context` must stay valid for the life of the process. Safe when none
 * is bound. */
void rc_agent_socket_release(void);

#ifdef __cplusplus
}
#endif

#endif /* REELCUT_CORE_H */
