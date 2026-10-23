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
    /// Whether the request asked for fillers (TR-1). A marker written
    /// before CT-1 has no key and reads as false (TR-2).
    let disfluencies: Bool

    init(source: MediaImporter.CacheStamp, options: TranscriptOptions) {
        self.source = TranscriptSourceStamp(source)
        self.provider = MediaTranscript.provider
        self.speechModels = options.speechModels
        self.languageCode = options.languageCode
        self.speakerLabels = options.speakerLabels
        self.keytermsPrompt = options.keytermsPrompt
        self.disfluencies = options.disfluencies
    }

    enum CodingKeys: String, CodingKey {
        case source
        case provider
        case speechModels = "speech_models"
        case languageCode = "language_code"
        case speakerLabels = "speaker_labels"
        case keytermsPrompt = "keyterms_prompt"
        case disfluencies
    }

    /// The synthesized reading for every key a marker had before CT-1, and
    /// `disfluencies` absent as false, so an old marker still decodes (TR-2).
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decode(TranscriptSourceStamp.self, forKey: .source)
        provider = try container.decode(String.self, forKey: .provider)
        speechModels = try container.decode([String].self, forKey: .speechModels)
        languageCode = try container.decodeIfPresent(String.self, forKey: .languageCode)
        speakerLabels = try container.decode(Bool.self, forKey: .speakerLabels)
        keytermsPrompt = try container.decode([String].self, forKey: .keytermsPrompt)
        disfluencies = try container.decodeIfPresent(Bool.self, forKey: .disfluencies) ?? false
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
        try container.encode(disfluencies, forKey: .disfluencies)
    }
}

// MARK: - What a marker serves (TR-2)

/// What a transcript is wanted for. A caption run takes a marker whatever its
/// `disfluencies`; a filler run (CT-2 on) needs one that asked for fillers.
enum TranscriptUse: Equatable { case captions, fillers }

extension TranscriptStamp {

    /// `self` is the marker on disk. True when every field but `disfluencies`
    /// equals `wanted`'s, and the use is captions or this marker asked for
    /// fillers — TR-2's rule, so a transcript cached before CT-1 stays
    /// current for captions and nothing re-transcribes on its own.
    func serves(_ wanted: TranscriptStamp, for use: TranscriptUse) -> Bool {
        guard source == wanted.source, provider == wanted.provider,
            speechModels == wanted.speechModels, languageCode == wanted.languageCode,
            speakerLabels == wanted.speakerLabels, keytermsPrompt == wanted.keytermsPrompt
        else { return false }
        return use == .captions || disfluencies
    }
}

/// `requested`'s reading: the synthesized behaviour for the four keys a
/// cache file had before CT-1, and `disfluencies` absent as false (TR-2).
/// Here, in an extension, so `TranscriptOptions` keeps its memberwise init.
extension TranscriptOptions {
    init(from decoder: any Decoder) throws {
        let keys = try decoder.container(keyedBy: CodingKeys.self)
        let speechModels = try keys.decode([String].self, forKey: .speechModels)
        let languageCode = try keys.decodeIfPresent(String.self, forKey: .languageCode)
        let speakerLabels = try keys.decode(Bool.self, forKey: .speakerLabels)
        let keytermsPrompt = try keys.decode([String].self, forKey: .keytermsPrompt)
        let disfluencies = try keys.decodeIfPresent(Bool.self, forKey: .disfluencies) ?? false
        self.init(
            speechModels: speechModels, languageCode: languageCode,
            speakerLabels: speakerLabels, keytermsPrompt: keytermsPrompt,
            disfluencies: disfluencies)
    }
}
