import Foundation

/// The languages Universal-3.5 Pro speaks, as AssemblyAI listed them on the
/// day they were read — 18 languages in 21 codes (road map 6 §2).
///
/// **It is dated because it will go stale.** A model gains languages; this
/// table cannot. So the sheet's popup offers these and "Detect
/// automatically", the tool passes whatever code it was given straight
/// through, and a code AssemblyAI refuses comes back as AssemblyAI's own
/// sentence — measured at a 400 in 0.24 s (road map 6 §3 q5), so a wrong code
/// costs one upload and a quarter of a second rather than a wrong transcript.
/// The table's job is to stop the common mistake before the upload, not to be
/// the authority on what the service accepts.
enum AssemblyAILanguages {

    struct Entry: Equatable {
        /// What goes in `language_code`.
        let code: String
        /// What the popup shows.
        let displayName: String
    }

    /// The day the list was read off AssemblyAI's supported-languages page.
    static let readOn = "2026-09-17"

    /// §2's order, which is the documentation's: the English codes first,
    /// then the rest as the page lists them. The order is the popup's, so it
    /// is the one a reader can check against the page line for line.
    static let all: [Entry] = [
        Entry(code: "en", displayName: "English"),
        Entry(code: "en_au", displayName: "English (Australia)"),
        Entry(code: "en_uk", displayName: "English (United Kingdom)"),
        Entry(code: "en_us", displayName: "English (United States)"),
        Entry(code: "es", displayName: "Spanish"),
        Entry(code: "fr", displayName: "French"),
        Entry(code: "de", displayName: "German"),
        Entry(code: "it", displayName: "Italian"),
        Entry(code: "pt", displayName: "Portuguese"),
        Entry(code: "ar", displayName: "Arabic"),
        Entry(code: "da", displayName: "Danish"),
        Entry(code: "nl", displayName: "Dutch"),
        Entry(code: "fi", displayName: "Finnish"),
        Entry(code: "he", displayName: "Hebrew"),
        Entry(code: "hi", displayName: "Hindi"),
        Entry(code: "ja", displayName: "Japanese"),
        Entry(code: "zh", displayName: "Chinese"),
        Entry(code: "no", displayName: "Norwegian"),
        Entry(code: "sv", displayName: "Swedish"),
        Entry(code: "tr", displayName: "Turkish"),
        Entry(code: "vi", displayName: "Vietnamese"),
    ]

    /// The row for a code, or nil. Case-insensitive, because a person typing
    /// `EN_US` into a tool argument means the same thing.
    static func entry(code: String) -> Entry? {
        let wanted = code.lowercased()
        return all.first { $0.code == wanted }
    }
}
