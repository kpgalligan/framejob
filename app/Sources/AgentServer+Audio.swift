import AppKit

/// The agent's sound tools. One so far: `normalize_clip`, the mirror of
/// Normalize Clip (road map 2 phase 5c).
///
/// It is an APP-STATE composite rather than an op, for `detect_silence`'s
/// reason exactly: the level it measures comes from `cache/peaks/<media
/// id>.bin`, which is not in the model, and the core does no sample work at
/// all (spec §7). So `OP_NAMES` is untouched, nothing goes in
/// `opsWithoutTools`, and what actually reaches the document is the ordinary
/// `set_audio` the op table already carries — one per clip, since each clip
/// gets its own measured gain.
///
/// **Not a line of the arithmetic is here.** `AudioNormalize` is a value type
/// — peaks in, ops out — and this handler calls the same `read` + `plan` pair
/// the Audio pane's button calls. That is what makes "the button and the tool
/// do the same thing" a fact about the code rather than a claim in a comment;
/// re-deriving the gain here would be the drift that "one implementation per
/// algorithm" exists to prevent, and a proof that measured the tool would then
/// be saying nothing about the button.
///
/// It stays on the MAIN thread, and so out of `AgentServer.offMainTools`, on
/// that set's stated criterion — "waits for something the main thread has to
/// deliver or must not be doing", not "touches the disk". Reading a few
/// hundred KB of peaks and making one arithmetic pass over it waits on
/// nothing, which is the case `detect_silence` argues at length beside it.
extension AgentServer {

    /// `normalize_clip` — the Audio section's Normalize button
    /// (`AudioPane.normalize`) and the Clip menu's Normalize item.
    ///
    /// Three properties of the command are worth stating wherever it is
    /// described, because each is a decision rather than an accident, and the
    /// button's tooltip, the catalog's description and this comment all say
    /// the same three (contract D-C3):
    ///
    /// 1. it REPLACES `audio.volume` rather than multiplying it, so pressing
    ///    it twice changes nothing — the peaks cache is pre-fader and knows
    ///    nothing about the volume the clip already carries;
    /// 2. it writes the clip's BASE props even while the playhead sits inside
    ///    an action, because it is a statement about the whole clip;
    /// 3. it leaves `muted` alone — a mute is a switch, not a level.
    ///
    /// The result reports what actually ran, `detect_silence`'s posture: every
    /// clip's measured peak and the volume written, every clip that could not
    /// be measured with the reason it could not, and a note when the model's
    /// 4× ceiling stopped a clip short of the level asked for.
    ///
    /// **A second identical call is an identity edit** and comes back as the
    /// shared "Normalize made no change: the project is already in that
    /// state", exactly as a second `set_audio` with the same volume would.
    /// That is the idempotence working, not a failure.
    ///
    /// **The all-measured-nothing case is answered HERE, and deepening D2·4
    /// left it standing on purpose.** "No clip could be measured" and "every
    /// clip is already at that level" are different answers, and the core
    /// can only give the second: the level comes from
    /// `cache/peaks/<media id>.bin`, which is not in the model and which the
    /// core has never seen (spec §7). With no reading there is no op to
    /// send, so the shared reply would be the identity's — and that sentence
    /// would be FALSE here, since the project is not at that level at all
    /// and nothing was measured against it. What this reports is a fact only
    /// the app holds, per clip, and it is not a rule's refusal restated.
    func normalizeClip(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clips = try clipsArg(a, "clips", document)
        let peakDB = try normalizePeakDB(a)
        guard let input = AudioNormalize.read(from: document, clips: clips) else {
            throw ToolError(
                message: "The project's audio plan could not be read, so there is no level to "
                    + "measure.")
        }
        // Nothing was MEASURED — a question about the read, not a guess at
        // what the core would answer, which is why it is asked of `input`
        // and before there is a plan at all. Each reason is already a
        // sentence naming its clip, so the whole answer is those sentences:
        // a caller that asked about five clips needs to know which of the
        // five reasons it hit, and there is no partial success to report
        // beside them.
        guard !input.isEmpty else {
            let reasons = input.problems.map { $0.description }.joined(separator: " ")
            throw ToolError(
                message: "Nothing could be normalised. \(reasons)")
        }
        let plan = AudioNormalize.plan(input, peakDB: peakDB)

        var fields: [String: Any] = [
            // The level that RAN, off the plan rather than off the argument:
            // `AudioNormalize.plan` substitutes the default for a non-finite
            // one, and a caller reading this back sees what was used.
            "peak_db": plan.peakDB,
            "normalized": plan.normalized.map { result in
                [
                    "clip": Int(result.clip),
                    "media": Int(result.media),
                    "measured_db": Self.jsonLevel(result.measuredDB),
                    "volume": result.volume,
                    "result_db": Self.jsonLevel(result.resultDB),
                    "clamped": result.clamped,
                ] as [String: Any]
            },
        ]
        // The same flat array of "clip N: …" sentences `transcribe` and
        // `import_captions` report, so an agent can hand any of the three back
        // to a person unchanged.
        if !plan.skipped.isEmpty {
            fields["skipped"] = plan.skipped.map { $0.description }
        }
        let clamped = plan.normalized.filter { $0.clamped }
        if !clamped.isEmpty {
            // The clamp is reported rather than refused (contract D-C7): a
            // clip quieter than about −13 dBFS cannot reach −1 with a volume
            // the model allows, so it is normalised to the loudest it can be
            // and told so. `result_db` on each row is where it actually
            // landed.
            let ids = clamped.map { String($0.clip) }.joined(separator: ", ")
            fields["note"] =
                "Clip(s) \(ids) wanted more gain than the model's 4× ceiling on volume, so each "
                + "was raised as far as it goes and lands below \(plan.peakDB) dBFS — result_db "
                + "says where."
        }
        return try editResult(document, "Normalize", plan.ops, fields)
    }

    /// `peak_db`, in the button's own unit, refused by name.
    ///
    /// The pane has no control for it at all — it presses the constant — so
    /// this is the tool's own knob and the tool is the only place it can be
    /// wrong. It is REFUSED rather than clamped, the rule every argument in
    /// this server follows (`silenceSettings` argues it for `threshold_db`):
    /// clamping silently would normalise to a level the caller did not ask
    /// for and report success. `AudioNormalize.plan` carries its own
    /// finiteness fallback for the pane's sake; a NaN that arrived here is a
    /// caller's mistake and is named.
    private func normalizePeakDB(_ a: [String: Any]) throws -> Double {
        guard let peakDB = try doubleArg(a, "peak_db") else {
            return AudioNormalize.defaultPeakDB
        }
        let range = AudioNormalize.peakDBRange
        guard peakDB.isFinite, range.contains(peakDB) else {
            throw ToolError(
                message: "peak_db must be a level from \(range.lowerBound) to "
                    + "\(range.upperBound) dBFS — above 0 is a request to clip — and the "
                    + "default is \(AudioNormalize.defaultPeakDB).")
        }
        return peakDB
    }

    /// A decibel figure as something `JSONSerialization` will write: the number
    /// itself, or null where it is not finite.
    ///
    /// Not defensive decoration. `JSONSerialization.data` THROWS on an
    /// infinity, so an un-guarded −∞ would turn a completed export or a
    /// committed normalise into a tool error reported after the work was
    /// done — the worst of both answers. And −∞ is a real value on both sides
    /// of this file: `LoudnessReport.silence` measures digital silence that
    /// way, and a peak read out of a corrupt cache could be anything at all.
    ///
    /// Shared by `normalize_clip`'s per-clip levels and `export`'s loudness
    /// echo (`AgentServer+Render.swift`), which are the two places this server
    /// reports a level; it lives here because this is the file whose subject
    /// is sound.
    static func jsonLevel(_ value: Double) -> Any {
        value.isFinite ? value : NSNull()
    }
}
