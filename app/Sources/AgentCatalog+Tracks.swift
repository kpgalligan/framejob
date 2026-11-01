import AppKit

// The agent's five TRACK rows: `add_track`, `remove_track`, `move_track`, `set_track` and
// `remove_empty_tracks`. A pure move out of `AgentCatalog.swift` at its size cap (road map
// audio AP10c), spliced back into `catalogJSON()` at the place they stood, so the
// catalog's order is unchanged; nothing else changed.
extension AgentServer {
    /// The track rows, given the track-id sentence the catalog already hoisted.
    func trackTools(trackDescription: String) -> [[String: Any]] {
        return [
            opTool(
                "add_track",
                "Adds an empty track. INDEX 0 IS THE BACK of the layer stack — the bottom lane "
                    + "of the timeline, drawn first — and tracks.count is the front, which is "
                    + "what ⇧⌘N adds and where an overlay belongs.",
                [
                    "index": "Where in the stack (0 = back). Default: the front.",
                    "name": "Track name, e.g. \"Titles\".",
                ]),
            opTool(
                "remove_track",
                "Removes a track. A track that still holds clips is refused unless with_clips "
                    + "is true, which removes them with it.",
                [
                    "track": trackDescription,
                    "with_clips": "Remove the track's clips too (default false).",
                ]),
            opTool(
                "move_track",
                "Reorders the layer stack: the track moves to `index`, 0 being the back. A "
                    + "higher index draws in FRONT of the tracks below it.",
                ["track": trackDescription, "index": "New position."]),
            opTool(
                "set_track",
                "Renames a track, flips its four switches — the track header's toggles, "
                    + "Track ▸ Hide Video / Mute Audio / Lock Track / Solo — or sets its matte, "
                    + "Track ▸ Matte. hidden drops its "
                    + "picture from the composition, muted its sound; locked keeps every ripple, "
                    + "insert and range edit off it; solo silences every OTHER track in its "
                    + "container (the timeline, or a nest's own tracks) that is not also soloed "
                    + "— mute wins on a track that is both, and pictures are untouched. matte "
                    + "makes the track a matte for the track directly behind it in its "
                    + "container: its clips are not drawn, and what they show cuts that track "
                    + "by alpha, inverted alpha, luma or inverted luma — where the matte track "
                    + "shows nothing, the track behind shows uncut; a back-most matte track, or "
                    + "one in front of another matte track, cuts nothing. Its clips still "
                    + "sound. \"none\" makes it an ordinary track again. volume is the track's "
                    + "fader, linear 0–4 (1 is unity, 4 is +12.04 dB, 0 silent), multiplying every "
                    + "clip's own volume on it; pan is −1 (left) … 1 (right), a constant-power "
                    + "balance after each clip's own pan, and a mono source is not panned. Both "
                    + "are refused outside their ranges and play through nests: a nested clip "
                    + "hears its own track's and every enclosing nest clip's track's. compressor "
                    + "and limiter are the track's dynamics, run post-fader on its sub-mix — "
                    + "after every clip, its volume and its pan, compressor then limiter, the "
                    + "ceiling in dBTP on what the track hands the mix — so the track holding a "
                    + "nest clip is that nest's bus. Each takes the clip's own object "
                    + "(get_project's audio.compressor and audio.limiter keys) and REPLACES the "
                    + "whole value, the keys left out taking their defaults; null clears it. "
                    + "Exact in every export; the preview runs them per composition track, "
                    + "approximately. Timeline tracks only: refused inside a scope. Normalize, "
                    + "Loudness, Enhance Voice and Match Audio do not hear them.",
                [
                    // The four switches name the MENU ITEM each one mirrors
                    // and nothing else: what each DOES is the sentence above,
                    // and a sentence written twice is what this candidate
                    // exists to delete. The description an agent reads comes
                    // with these in one tool object, so nothing is lost.
                    "track": trackDescription,
                    "name": "New track name.",
                    "hidden": "Track ▸ Hide Video.",
                    "muted": "Track ▸ Mute Audio.",
                    "locked": "Track ▸ Lock Track.",
                    "solo": "Track ▸ Solo.",
                    "matte": "Track ▸ Matte; \"none\" is its Off.",
                    "volume": "Track ▸ Mix…'s Volume, as a linear gain 0–4.",
                    "pan": "Track ▸ Mix…'s Pan, −1–1.",
                    "compressor": "Track ▸ Mix…'s Compressor: {threshold_db −60–0, ratio 1–20, "
                        + "attack and release in ticks, makeup_db 0–24}, or null for off.",
                    "limiter": "Track ▸ Mix…'s Limit peaks: {ceiling_db −24–0 dBTP, release "
                        + "600–600000 ticks}, or null for off.",
                ]),
            opTool(
                "remove_empty_tracks",
                "Removes every track that holds no clips — Track ▸ Remove Empty Tracks.",
                [:]),
        ]
    }
}
