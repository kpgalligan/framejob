import Foundation

/// AssemblyAI's wire vocabulary: what a transcript is ASKED for
/// (`TranscriptOptions`, `TranscriptRequest`), what comes back
/// (`TranscriptResponse`, `TranscriptWord`), what a cache file's marker
/// records about the request (`TranscriptStamp`), and `JSONValueRange`, the
/// one tool that lets a served `words` array be carried through this app byte
/// for byte.
///
/// It is beside `AssemblyAIClient.swift` and `MediaTranscript.swift` rather
/// than inside either because both are already at the 400-line cap a new file
/// has (app/CLAUDE.md, road map 6 §5h). What gathers here is the VALUES —
/// nothing here speaks HTTP and nothing here touches disk, so a probe reads
/// every one of them with no socket and no cache directory at all.
/// `TranscriptStamp` is here rather than beside the cache it marks for the
/// same reason, and because it is a record of the REQUEST above before it is
/// anything about a file.
///
/// **Snake case is spelled out, never derived.** `JSONEncoder`'s
/// `.convertToSnakeCase` would turn `audioURL` into `audio_url` and
/// `speechModelUsed` into `speech_model_used` correctly and then turn some
/// later `languageID` into `language_id` where the wire says `language_code`:
/// a `CodingKeys` block is the place a reader can check a key against
/// AssemblyAI's documentation one line at a time.
struct TranscriptOptions: Codable, Equatable {
    /// Both models, in AssemblyAI's documented priority order, so R6-8's
    /// fallback can happen and be reported.
    var speechModels: [String]
    /// nil is "detect the language", which is the wire's ABSENT
    /// `language_code` — `TranscriptRequest` is where that absence is
    /// spelled. Here nil encodes as JSON `null`, because this value is also
    /// road map 6 §5b's `requested` block in the cache file, and a cache that
    /// dropped the key could not be told from one written before the key
    /// existed.
    var languageCode: String?
    var speakerLabels: Bool
    /// Up to `AssemblyAIClient.maxKeyterms` terms; empty is the wire's
    /// ABSENT `keyterms_prompt`.
    var keytermsPrompt: [String]

    /// What this build asks for, road map 6 §2's documented default pair.
    static let shippedModels = ["universal-3-5-pro", "universal-2"]

    enum CodingKeys: String, CodingKey {
        case speechModels = "speech_models"
        case languageCode = "language_code"
        case speakerLabels = "speaker_labels"
        case keytermsPrompt = "keyterms_prompt"
    }

    /// EVERY key, always, with nil written as JSON `null`. The synthesized
    /// encoder uses `encodeIfPresent` and would DROP `language_code` when the
    /// language is auto — and this value is road map 6 §5b's `requested`
    /// block inside the cache file and the marker, where a dropped key could
    /// not be told from one written before the key existed.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(speechModels, forKey: .speechModels)
        if let code = languageCode {
            try container.encode(code, forKey: .languageCode)
        } else {
            try container.encodeNil(forKey: .languageCode)
        }
        try container.encode(speakerLabels, forKey: .speakerLabels)
        try container.encode(keytermsPrompt, forKey: .keytermsPrompt)
    }
}

/// The vocabulary's rules, beside the field they fill. A pure move out of
/// `AgentServer+CloudCaptions.swift` (c1-chrome): the tool and the sheet's
/// Vocabulary field must cap and de-duplicate a person's list the same way,
/// and two spellings of that would be two answers to one question.
extension TranscriptOptions {

    /// `keyterms_prompt`: trimmed, empties dropped, de-duplicated KEEPING
    /// THE FIRST spelling, capped at `AssemblyAIClient.maxKeyterms`.
    ///
    /// First rather than last because the order a caller wrote is the order
    /// of importance it meant, and the cap cuts from the end — a list that
    /// re-ordered itself and then cut would drop terms the caller put first.
    static func keyterms(_ given: [String]) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for term in given {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            out.append(trimmed)
            if out.count == AssemblyAIClient.maxKeyterms { break }
        }
        return out
    }
}

/// `POST /v2/transcript`'s body: the upload's URL and the options, flattened
/// into ONE object, because that is the shape AssemblyAI's endpoint takes.
///
/// `Encodable` only. Nothing decodes a request — the response is its own
/// type — and a `Decodable` conformance here would be a second, untested
/// spelling of the same keys.
struct TranscriptRequest: Encodable, Equatable {
    let audioURL: URL
    let options: TranscriptOptions

    enum CodingKeys: String, CodingKey {
        case audioURL = "audio_url"
        case speechModels = "speech_models"
        case languageCode = "language_code"
        case speakerLabels = "speaker_labels"
        case keytermsPrompt = "keyterms_prompt"
    }

    /// The wire body, and the whole of it: `audio_url`, `speech_models` and
    /// `speaker_labels` always; `language_code` ABSENT when nil, which is
    /// what turns detection on; `keyterms_prompt` ABSENT when empty, because
    /// an empty array is a request for a vocabulary of nothing and the
    /// service need not be asked to consider one. No other key — every option
    /// this app does not set is AssemblyAI's own default (road map 6 §2's
    /// "options refused here" row), and sending it explicitly would pin a
    /// default that is not ours to pin.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(audioURL, forKey: .audioURL)
        try container.encode(options.speechModels, forKey: .speechModels)
        try container.encode(options.speakerLabels, forKey: .speakerLabels)
        if let code = options.languageCode {
            try container.encode(code, forKey: .languageCode)
        }
        if !options.keytermsPrompt.isEmpty {
            try container.encode(options.keytermsPrompt, forKey: .keytermsPrompt)
        }
    }
}

/// One word as AssemblyAI spells it: `start` and `end` in MILLISECONDS, not
/// ticks, because road map 6 §5b stores the provider's answer unchanged and
/// `MediaTranscript.words` is the one place it is converted.
struct TranscriptWord: Codable, Equatable {
    let text: String
    let start: Int
    let end: Int
    let confidence: Double
    /// `"A"`, `"B"`… and nil unless `speaker_labels` was asked for. The cue
    /// builder's fifth rule is what reads it (road map 6 §5f).
    let speaker: String?
}

/// `GET /v2/transcript/{id}`'s body, in the fields this app reads. Every one
/// past `id` and `status` is optional because a `queued` transcript carries
/// almost none of them and a decoder that demanded them would fail the first
/// poll.
struct TranscriptResponse: Codable, Equatable {
    let id: String
    /// `queued`, `processing`, `completed` or `error` (road map 6 §2).
    let status: String
    /// Set only with `status == "error"`; the service's own sentence, which
    /// 5c relays verbatim.
    let error: String?
    let audioURL: String?
    /// R6-8: which model actually ran.
    let speechModelUsed: String?
    let languageCode: String?
    /// Present when the language was DETECTED and absent when it was named —
    /// measured, road map 6 §3 q1.
    let languageConfidence: Double?
    /// Seconds, integer, rounded UP — measured, §3 q1. What was billed.
    let audioDuration: Int?
    /// Decoded for a count and for the probe's convenience; the bytes that
    /// are STORED come out of `JSONValueRange`, never out of this array.
    let words: [TranscriptWord]?

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case error
        case audioURL = "audio_url"
        case speechModelUsed = "speech_model_used"
        case languageCode = "language_code"
        case languageConfidence = "language_confidence"
        case audioDuration = "audio_duration"
        case words
    }

    /// `words` is read through a `try?` and EVERYTHING ELSE strictly.
    ///
    /// A body whose `words` is an object rather than an array must still
    /// decode, because `AssemblyAIClient.poll` has a rule of its own about
    /// what a `completed` body with no words ARRAY answers, and that rule's
    /// sentence is the one a person can act on. The synthesized decoder would
    /// throw first and the refusal would read "the transcript did not decode"
    /// — true, and about the wrong thing. This is not the lenient decoding
    /// app/CLAUDE.md forbids: what is read leniently is discarded, and the
    /// bytes that are STORED come out of `JSONValueRange` either way.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        status = try container.decode(String.self, forKey: .status)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        audioURL = try container.decodeIfPresent(String.self, forKey: .audioURL)
        speechModelUsed = try container.decodeIfPresent(String.self, forKey: .speechModelUsed)
        languageCode = try container.decodeIfPresent(String.self, forKey: .languageCode)
        languageConfidence = try container.decodeIfPresent(
            Double.self, forKey: .languageConfidence)
        audioDuration = try container.decodeIfPresent(Int.self, forKey: .audioDuration)
        words = try? container.decodeIfPresent([TranscriptWord].self, forKey: .words)
    }
}

/// Where a top-level key's VALUE sits inside a JSON document, in bytes.
///
/// **Why this exists at all.** Road map 6 §5b says the words are stored
/// VERBATIM, and 5i·4 claims the cache file's `words` are byte-equal to what
/// the stand-in served. A `Codable` round trip cannot make that claim true: a
/// served `0.98` decodes to a `Double` and re-encodes as `0.9800000000000001`
/// on some values and `0.98` on others, `1e-3` comes back `0.001`, and a
/// non-ASCII character may come back escaped or not depending on the encoder.
/// So the array is never re-serialised. The client cuts the served bytes of
/// `words` out of the response body with this, and `MediaTranscript.File`
/// splices those same bytes back into the document it writes.
///
/// **It is a scanner, not a parser.** It walks the top level of one object
/// counting braces and brackets, skipping over strings and their escapes, and
/// answers the byte range of the value that follows the named key's colon. It
/// does not validate the document, and it is only ever asked about a body a
/// `JSONDecoder` has already accepted.
enum JSONValueRange {

    /// The byte range of `key`'s value in `json`, or nil when `json` is not a
    /// top-level object, when the key is not at its top level, or when the
    /// document ends mid-value. Whitespace before the value is skipped;
    /// whitespace after it is not included.
    static func topLevel(key: String, in json: Data) -> Range<Data.Index>? {
        let bytes = [UInt8](json)
        var index = skipSpace(bytes, from: 0)
        guard index < bytes.count, bytes[index] == UInt8(ascii: "{") else { return nil }
        index += 1
        let wanted = Array(key.utf8)
        while true {
            index = skipSpace(bytes, from: index)
            guard index < bytes.count else { return nil }
            if bytes[index] == UInt8(ascii: "}") { return nil }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
                continue
            }
            guard bytes[index] == UInt8(ascii: "\""), let name = stringEnd(bytes, from: index)
            else { return nil }
            // The key is compared as RAW bytes between the quotes, so a key
            // spelled with an escape (`"words"`, legal JSON) does not
            // match `words` — it would be a different key to this scanner and
            // a caller must never be told it found one it did not.
            let matched = Array(bytes[(index + 1)..<(name - 1)]) == wanted
            index = skipSpace(bytes, from: name)
            guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { return nil }
            index = skipSpace(bytes, from: index + 1)
            guard let end = valueEnd(bytes, from: index) else { return nil }
            if matched {
                let base = json.startIndex
                return json.index(base, offsetBy: index)..<json.index(base, offsetBy: end)
            }
            index = end
        }
    }

    private static func skipSpace(_ bytes: [UInt8], from start: Int) -> Int {
        var index = start
        while index < bytes.count {
            let byte = bytes[index]
            guard byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D else { break }
            index += 1
        }
        return index
    }

    /// One past the closing quote of the string that starts at `start`, or
    /// nil when it never closes. `\\` is honoured, so `"a\\"` ends at its
    /// third quote and `"a\""` does not end at its second.
    private static func stringEnd(_ bytes: [UInt8], from start: Int) -> Int? {
        var index = start + 1
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "\\") {
                index += 2
                continue
            }
            if byte == UInt8(ascii: "\"") { return index + 1 }
            index += 1
        }
        return nil
    }

    /// One past the last byte of the value that starts at `start`. Objects
    /// and arrays are matched by depth with strings skipped whole, so a `}`
    /// inside a word's text cannot close the document; a scalar runs to the
    /// first `,`, `}`, `]` or space that is not inside a string.
    private static func valueEnd(_ bytes: [UInt8], from start: Int) -> Int? {
        guard start < bytes.count else { return nil }
        switch bytes[start] {
        case UInt8(ascii: "\""):
            return stringEnd(bytes, from: start)
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            var depth = 0
            var index = start
            while index < bytes.count {
                let byte = bytes[index]
                if byte == UInt8(ascii: "\"") {
                    guard let after = stringEnd(bytes, from: index) else { return nil }
                    index = after
                    continue
                }
                if byte == UInt8(ascii: "{") || byte == UInt8(ascii: "[") { depth += 1 }
                if byte == UInt8(ascii: "}") || byte == UInt8(ascii: "]") {
                    depth -= 1
                    if depth == 0 { return index + 1 }
                }
                index += 1
            }
            return nil
        default:
            var index = start
            while index < bytes.count {
                let byte = bytes[index]
                if byte == UInt8(ascii: ",") || byte == UInt8(ascii: "}")
                    || byte == UInt8(ascii: "]") || byte == 0x20 || byte == 0x09 || byte == 0x0A
                    || byte == 0x0D
                {
                    return index > start ? index : nil
                }
                index += 1
            }
            return index > start ? index : nil
        }
    }
}

// MARK: - The marker

/// What `cache/transcripts/<id>.complete.json` holds: the source file's own
/// stamp — so a relink, an edited file or a changed duration invalidates a
/// transcript exactly as it invalidates the peaks — plus the REQUEST, so a
/// run with a different language, with speakers on or with a new vocabulary
/// is a new transcript. `MediaImporter.SpeechStamp`'s shape, and for its
/// reason: `CacheStamp` is UNCHANGED, so thumbs and peaks stay valid.
///
/// The region is deliberately NOT in it. A transcript of a file is the same
/// whichever of AssemblyAI's two regions made it, and putting the region here
/// would re-upload every media of every project the first time somebody
/// looked at the popup.
struct TranscriptStamp: Codable, Equatable {
    let source: MediaImporter.CacheStamp
    let provider: String
    let speechModels: [String]
    let languageCode: String?
    let speakerLabels: Bool
    let keytermsPrompt: [String]

    init(source: MediaImporter.CacheStamp, options: TranscriptOptions) {
        self.source = source
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

/// One optional written as its value or as JSON `null`, never dropped —
/// `TranscriptOptions`, `TranscriptStamp` and `MediaTranscript.Header` all
/// need it and `encodeIfPresent` is the thing all three must not do.
func encodeOrNull<Key: CodingKey, Value: Encodable>(
    _ value: Value?, into container: inout KeyedEncodingContainer<Key>, forKey key: Key
) throws {
    if let value = value {
        try container.encode(value, forKey: key)
    } else {
        try container.encodeNil(forKey: key)
    }
}
