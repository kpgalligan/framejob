import Foundation

// MARK: - The marker

/// The four source facts that identify audio for transcription (R6-15).
/// `CacheStamp` also contains display and generator fields, which remain
/// relevant to their own caches but cannot invalidate a transcript.
struct TranscriptSourceStamp: Codable, Equatable {
    let size: Int64
    let modified: Int64
    let duration: Ticks
    let hasAudio: Bool

    init(_ source: MediaImporter.CacheStamp) {
        size = source.size
        modified = source.modified
        duration = source.duration
        hasAudio = source.hasAudio
    }
}

/// What `cache/transcripts/<id>.complete.json` holds: the four-field source
/// identity plus the REQUEST. Keyed decoding projects old wide markers onto
/// this value, so their display-cache fields cannot cause a new upload.
///
/// The region is deliberately NOT in it. A transcript of a file is the same
/// whichever of AssemblyAI's two regions made it, and putting the region here
/// would re-upload every media of every project the first time somebody
/// looked at the popup.
struct TranscriptStamp: Codable, Equatable {
    let source: TranscriptSourceStamp
    let provider: String
    let speechModels: [String]
    let languageCode: String?
    let speakerLabels: Bool
    let keytermsPrompt: [String]

    init(source: MediaImporter.CacheStamp, options: TranscriptOptions) {
        self.source = TranscriptSourceStamp(source)
        self.provider = MediaTranscript.provider
        self.speechModels = options.speechModels
        self.languageCode = options.languageCode
        self.speakerLabels = options.speakerLabels
        self.keytermsPrompt = options.keytermsPrompt
    }

    enum CodingKeys: String, CodingKey {
        case source
        case provider
        case speechModels = "speech_models"
        case languageCode = "language_code"
        case speakerLabels = "speaker_labels"
        case keytermsPrompt = "keyterms_prompt"
    }

    /// Every key, always, nil as `null` — `TranscriptOptions.encode`'s
    /// reason. A marker that dropped `language_code` when the language was
    /// auto would compare unequal to one written by a build that kept it.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encode(provider, forKey: .provider)
        try container.encode(speechModels, forKey: .speechModels)
        try encodeOrNull(languageCode, into: &container, forKey: .languageCode)
        try container.encode(speakerLabels, forKey: .speakerLabels)
        try container.encode(keytermsPrompt, forKey: .keytermsPrompt)
    }
}
