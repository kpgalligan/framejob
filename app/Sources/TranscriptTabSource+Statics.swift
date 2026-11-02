import Foundation

/// `TranscriptTabSource`'s two statics that hold no instance state, moved out
/// whole (a pure move, road map "creator-jobs" TX1b) so the source has room
/// under the ~600-line cap: the chosen language and a media's pause set.
extension TranscriptTabSource {

    /// One media's read: its words, and its pause set with the voice cache
    /// it was read from.
    typealias Read = (TimelineTranscript.MediaWords, (Set<Ticks>, [Float]?))

    /// The chosen language among `list`, else the Mac's default. Any thread.
    static func resolve(
        _ wanted: String?, in list: [Transcriber.Language]
    ) -> Transcriber.Language? {
        wanted.flatMap { Transcriber.language(matching: $0, in: list) }
            ?? Transcriber.defaultLanguage(in: list)
    }

    /// A media's pause set, and the voice cache it was read from (TX-30).
    static func pauses(
        _ words: TimelineTranscript.MediaWords, cacheDir: URL
    ) -> (Set<Ticks>, [Float]?) {
        let speech = MediaImporter.loadSpeech(for: words.media, in: cacheDir)
        return (
            TranscriptTokens.pauses(
                words.words, speech: speech,
                confidence: Float(SilenceDetector.Settings.defaultVoiceConfidence)), speech)
    }

    #if FRAMEJOB_DEV_TOOLS
    /// Probes only (TX1b's U10): each load block waits on it after its read,
    /// before its main hop.
    static var loadHold: DispatchSemaphore?
    #endif

    /// The probes' hold between a load's read and its main hop; nothing
    /// without `FRAMEJOB_DEV_TOOLS` or a hold set.
    static func holdLoad() {
        #if FRAMEJOB_DEV_TOOLS
        loadHold?.wait()
        #endif
    }
}
