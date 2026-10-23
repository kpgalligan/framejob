import Foundation

/// The one filler vocabulary (spec §11 TR-8) and the rule that matches a word
/// against it. Every caption producer's input passes through
/// `MediaTranscript.captionWords`, so a caption made from a transcript that
/// asked for fillers (TR-1) is the caption the same words make without them.
///
/// The cache keeps every served word verbatim (R6-3): this filters decoded
/// words only, and `wordsJSON` and `File.encoded()` never see it.
enum FillerWords {

    /// TR-8's list: the tokens AssemblyAI itself names as fillers for the
    /// models the app requests. "uh huh" is matched by its two halves, and
    /// `uh-huh` as one token. Another source's fillers (TR-7) are added by
    /// that source's own entry.
    static let assemblyAI: Set<String> = [
        "um", "uh", "hmm", "mhm", "uh-huh", "ah", "huh", "hm", "m", "er", "erm",
    ]

    /// Lowercased, then leading and trailing punctuation and whitespace
    /// trimmed: `"Um,"` is `"um"`, and an inner hyphen stays.
    static func normalized(_ text: String) -> String {
        text.lowercased().trimmingCharacters(
            in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
    }

    /// Whether a word is a filler: its normalised text is in the list.
    static func isFiller(_ text: String) -> Bool {
        assemblyAI.contains(normalized(text))
    }
}

extension MediaTranscript {

    /// `words(for:in:)` with every `FillerWords.isFiller` word removed; the
    /// order and every other word untouched. What a caption is made from.
    static func captionWords(for job: Transcriber.Job, in file: File) -> [CaptionCues.Word] {
        words(for: job, in: file).filter { !FillerWords.isFiller($0.text) }
    }
}
