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
 * layer arrives and leaves with. None of the last three needed a migration
 * step — every field they added carries a serde default — but an older
 * build must still refuse the newer file rather than silently drop what it
 * cannot read, which is what the version is for. */
#define RC_FORMAT_VERSION 5

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

void rc_project_free(RcProject *p);

/* ----------------------------------------------------------------- edits */

/* THE one edit entry point. `op` is `{"op": "<name>", ...args}` — the table
 * in the module doc of core/src/edit.rs and spec section 6.
 *
 * Returns a NEW project on success. Returns NULL in two distinguishable
 * cases:
 *   - `*err_out` UNTOUCHED (still NULL): the op is valid but would change
 *     nothing. The caller registers NO undo step (an identity edit is a
 *     phantom undo step) — the UI beeps or animates the gesture back.
 *   - `*err_out` SET: the op or its arguments are invalid.
 * The caller must therefore initialise its `char *err = NULL;` before the
 * call and test it after a NULL return. */
RcProject *rc_project_apply(const RcProject *p, const char *op, char **err_out);

/* Every op name `rc_project_apply` accepts, as a JSON array of strings in
 * the order of that table. The host reads it to check its MCP tool catalog
 * covers the whole table; the core owns the list so no copy can drift from
 * it. Never NULL. */
char *rc_op_names(void);

/* --------------------------------------------------------------- queries */

/* End of the last clip, in ticks. 0 for an empty project or NULL. */
int64_t rc_project_duration(const RcProject *p);

/* The composition plan (spec 7.2): what Swift builds an AVMutableComposition,
 * AVMutableAudioMix and AVMutableVideoComposition from. Swift asks for this
 * after every edit and rebuilds ONLY when the JSON differs from the current
 * plan — the plan holds exactly the structural facts. */
char *rc_project_composition_plan(const RcProject *p);

/* The frame recipe at time `t` (spec 7.3): the back-to-front layer list with
 * every property already evaluated through actions. Asked once per composed
 * frame, and by the canvas overlay for hit-testing and handles. */
char *rc_project_frame_recipe(const RcProject *p, int64_t t);

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

/* ---------------------------------------------------------------- export */

/* The export presets as a JSON array (spec 7.8), in menu order: one row per
   ENCODING — a container and a codec — with no size of its own, so that an
   export is at the document's size unless a size is asked for. The two
   image formats are the exception and carry the cap 7.8 argues. The FIRST
   row is the default the export sheet opens on. */
char *rc_export_presets(void);

/* The output sizes the export sheet offers for `preset_id` against this
   project, as a JSON array of {id, name, width, height} in menu order. The
   FIRST row is the default: the document's own size ("document"), or for an
   image format its cap ("preset"). After it come the standard sizes fitted to
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
 * preset or bad overrides. */
char *rc_export_settings(const RcProject *p, const char *preset_id, const char *overrides_json,
                         char **err_out);

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

/* Starts the embedded MCP server on 127.0.0.1:`port` (0 picks an ephemeral
 * port) and returns the bound port, or 0 with a message through `err_out`.
 * `tools_json` is the `tools/list` catalog as a JSON array. One server per
 * process: a second start is an error. `handler` and `context` must stay
 * valid and callable from any thread until `rc_agent_server_stop` returns. */
uint16_t rc_agent_server_start(uint16_t port, const char *server_name,
                               const char *server_version, const char *tools_json,
                               RcAgentToolHandler handler, void *context, char **err_out);

/* Stops the server and joins its thread. Safe when none is running. */
void rc_agent_server_stop(void);

#ifdef __cplusplus
}
#endif

#endif /* REELCUT_CORE_H */
