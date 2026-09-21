import Foundation
import Speech

// MARK: - Transcriber: languages

/// The sheet's language popup and the tool's `language` argument: the
/// `Language` row, the two cached lists (`languages()`, the locales this Mac
/// has an on-device model for; `supportedLanguages()`, every locale the
/// framework names), the display-name builder behind both, and the two lookups
/// the callers use — `defaultLanguage(in:)` for the popup's first selection
/// and `language(matching:in:)` for a tag a person or an agent typed.
///
/// A pure move out of `Transcriber.swift`, road map 6's C1 toll 1. The block
/// came here whole and in its own order, with every line byte-identical, and
/// nothing arrived widened: the lock and the two caches stay `private`
/// because every reader of them moved with them.
extension Transcriber {

    // MARK: - Languages

    /// One row of the sheet's language popup, and the vocabulary the tool's
    /// `language` argument speaks.
    struct Language: Equatable {
        /// A BCP-47 identifier, `en-US`.
        let identifier: String
        let displayName: String

        var locale: Locale { Locale(identifier: identifier) }
    }

    private static let languageLock = NSLock()
    private static var cachedLanguages: [Language]?
    private static var cachedSupported: [Language]?

    /// Every dictation locale this Mac can recognise WITHOUT a network,
    /// sorted by display name.
    ///
    /// The filter is not cosmetic: an `SFSpeechRecognitionRequest` can only
    /// honour `requiresOnDeviceRecognition` where the recogniser answers
    /// `supportsOnDeviceRecognition`, so an unfiltered popup would offer rows
    /// whose every run fails. Measured on this machine: **4 of 63** supported
    /// locales have on-device assets, and the whole pass — one recogniser per
    /// locale — takes **0.33 s**, which is why it is cached and why it is not
    /// asked for again on every control change.
    ///
    /// The result is cached only when it is NON-empty, because the property
    /// is known to answer false on the first read after a recogniser is
    /// constructed and true a moment later — caching an empty first answer
    /// would make the feature refuse for the rest of the session on a machine
    /// where it works.
    static func languages() -> [Language] {
        languageLock.lock()
        if let cached = cachedLanguages {
            languageLock.unlock()
            return cached
        }
        languageLock.unlock()

        let found = named(
            SFSpeechRecognizer.supportedLocales().filter { locale in
                SFSpeechRecognizer(locale: locale)?.supportsOnDeviceRecognition ?? false
            })

        if !found.isEmpty {
            languageLock.lock()
            cachedLanguages = found
            languageLock.unlock()
        }
        return found
    }

    /// Every locale the FRAMEWORK names, model downloaded or not — the
    /// unfiltered twin of `languages()`.
    ///
    /// There are two lists because a caller who named a language this Mac
    /// could not use has one of TWO problems and they have two different
    /// fixes. `en-XX` is a tag speech recognition has never heard of, and the
    /// fix is to spell it right; `fr-FR` is a tag it knows perfectly well
    /// that this Mac has no model for, and the fix is a download in System
    /// Settings. Told only "this Mac cannot recognise it", somebody with the
    /// second problem retypes a tag that was right all along, which is what
    /// `transcribe`'s catalog entry promises does not happen.
    ///
    /// It costs no recogniser — `supportedLocales()` is a list the framework
    /// answers out of its own bundle — so this is sixty-odd display-name
    /// lookups where `languages()` is sixty-odd recogniser constructions.
    /// And it is INDEPENDENT OF THE GRANT, which is the property the tool
    /// leans on: measured at status `notDetermined`, 63 locales here, the
    /// same 4 of them on device. That is why a misspelled tag can be refused
    /// ABOVE the authorization check, among the caller's other mistakes,
    /// while the download question stays BELOW it, where a machine nobody has
    /// granted yet cannot be mistaken for one with no models installed.
    ///
    /// Cached like its twin, and an empty answer is not cached, for its
    /// twin's reason turned around: the list is static, so the cache is only
    /// about not rebuilding the display names, and an empty framework list is
    /// not an answer this file is willing to remember.
    static func supportedLanguages() -> [Language] {
        languageLock.lock()
        if let cached = cachedSupported {
            languageLock.unlock()
            return cached
        }
        languageLock.unlock()

        let found = named(SFSpeechRecognizer.supportedLocales())
        if !found.isEmpty {
            languageLock.lock()
            cachedSupported = found
            languageLock.unlock()
        }
        return found
    }

    /// Locales as rows: named in this Mac's own language and sorted by that
    /// NAME rather than by tag, because a person reads the name — and both
    /// lists are built here so the popup and the two refusals cannot spell
    /// one locale two ways.
    private static func named(_ locales: Set<Locale>) -> [Language] {
        let names = Locale.current
        return locales.map { locale -> Language in
            let identifier = locale.identifier
            return Language(
                identifier: identifier,
                displayName: names.localizedString(forIdentifier: identifier) ?? identifier)
        }.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    /// The language a run defaults to: this Mac's own, when it survives the
    /// on-device filter, then anything sharing its language code, then the
    /// first row there is.
    static func defaultLanguage(in list: [Language]) -> Language? {
        let current = Locale.current.identifier
        if let exact = list.first(where: {
            $0.identifier.caseInsensitiveCompare(current) == .orderedSame
        }) {
            return exact
        }
        let code = Locale.current.language.languageCode?.identifier ?? ""
        if !code.isEmpty,
           let near = list.first(where: { $0.identifier.hasPrefix(code) }) {
            return near
        }
        return list.first
    }

    /// The language a caller named — `en-US`, `en`, or a display name — or nil
    /// when nothing in `list` matches it.
    ///
    /// It is asked of BOTH lists, and that is the point: of
    /// `supportedLanguages()` to tell a misspelling from a real tag, and then
    /// of `languages()` to tell a real tag this Mac has a model for from one
    /// it has not. Those are the tool's two language refusals, and one
    /// matcher answers both so they cannot come to disagree about what
    /// counts as a match.
    static func language(matching name: String, in list: [Language]) -> Language? {
        let wanted = name.trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty else { return nil }
        if let exact = list.first(where: {
            $0.identifier.caseInsensitiveCompare(wanted) == .orderedSame
        }) { return exact }
        if let named = list.first(where: {
            $0.displayName.caseInsensitiveCompare(wanted) == .orderedSame
        }) { return named }
        // `en` should find `en-US` — a caller who names a language rather
        // than a region means the one this Mac has.
        let prefix = wanted.replacingOccurrences(of: "_", with: "-").lowercased()
        return list.first { $0.identifier.lowercased().hasPrefix(prefix + "-") }
    }
}
