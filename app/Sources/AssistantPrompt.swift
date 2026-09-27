import Foundation

/// The texts the assistant's session hands the helper in `configure`
/// (`agent/src/protocol.ts`), and the tools it loads up front. Road map 12
/// A1: working placeholders; A3 writes the final texts.
enum AssistantPrompt {

    /// The tools the model sees up front (A0 C3); every other catalog entry
    /// is deferred and found through tool search.
    static let coreTools = ["get_project", "render_frame", "undo", "redo"]

    /// The system prompt. A3 replaces it.
    static let system =
        "You are the assistant in Reelcut, a video editor for macOS. You edit the project open "
        + "in this window through its tools; each tool call is one step the person can undo. "
        + "Times are in ticks, 600000 per second. Read the project with get_project before you "
        + "edit, and look with render_frame after."

    /// What tool search can find, appended to the system prompt after a
    /// blank line by the helper. A3 replaces it.
    static let searchGuide =
        "Only a few tools are loaded up front. Every other tool (clips, tracks, text, captions, "
        + "audio, transitions, actions, graphics, media, export) is found with tool search: "
        + "search for what you want to do, in a few words, before deciding a tool does not "
        + "exist."

    /// What the end-of-turn compaction summary must carry (AI-9). A3
    /// replaces it.
    static let compactionInstructions =
        "Summarise this video-editing conversation so the work can continue. Keep what the "
        + "person asked for and any preference they stated; every clip, track, marker and media "
        + "id used and what each is; every edit made, in order, and whether it was undone; what "
        + "is left to do. Renders do not survive: describe in words what each frame you looked "
        + "at showed."
}
