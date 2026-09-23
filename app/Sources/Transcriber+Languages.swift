import Foundation

// MARK: - Transcriber: languages

/// The sheet's language popup and the tool's `language` argument: the
/// `Language` row, the two cached lists (`languages()`, the locales whose
/// model is INSTALLED on this Mac; `supportedLanguages()`, every locale the
/// engine names, each marked installed or not), the display-name builder
/// behind both, and the two lookups the callers use —
/// `defaultLanguage(in:)` for the popup's first selection and
/// `language(matching:in:)` for a tag a person or an agent typed.
///
/// Since W2 (spec §11 W-8) both lists are ASKED of `SpeechEngine`
/// (`supportedLocales()`, `installedLocales()`), never written down, and
/// every identifier is BCP-47 (`en-US`) — the engine answers `en_US`, and a
/// raw compare between the two spellings never matches. No transcriber is
/// constructed per locale here: constructing one reserves its locale against
/// a cap of 5 (W0 q3), so the installed SET comes from `installedLocales()`
/// and the one model question, `SpeechEngine.isInstalled`, is asked only for
/// the locale a run chose.
extension Transcriber {

    // MARK: - Languages

    /// One row of the sheet's language popup, and the vocabulary the tool's
    /// `language` argument speaks.
    struct Language: Equatable {
        /// A BCP-47 identifier, `en-US` — never `en_US`.
        let identifier: String
        let displayName: String
        /// Whether this Mac has the model. The sheet marks a row that has not
        /// and offers its Download row; a run refuses it.
        let installed: Bool

        init(identifier: String, displayName: String, installed: Bool = true) {
            self.identifier = identifier
            self.displayName = displayName
            self.installed = installed
        }

        var locale: Locale { Locale(identifier: identifier) }
    }

    private static let languageLock = NSLock()
    private static var cachedLanguages: [Language]?
    private static var cachedSupported: [Language]?

    /// Every locale whose model is INSTALLED on this Mac, sorted by display
    /// name — the rows a run can use without a download. All `installed`.
    ///
    /// Cached only when NON-empty: an empty answer is what `askBound`
    /// expiring looks like, and remembering it would make the feature refuse
    /// for the rest of the session on a Mac where it works.
    static func languages() -> [Language] {
        languageLock.lock()
        if let cached = cachedLanguages {
            languageLock.unlock()
            return cached
        }
        languageLock.unlock()

        let found = named(SpeechEngine.installedLocales(), installed: nil)
        if !found.isEmpty {
            languageLock.lock()
            cachedLanguages = found
            languageLock.unlock()
        }
        return found
    }

    /// Every locale the ENGINE names, model installed or not — the
    /// unfiltered twin of `languages()`, each row's `installed` read off the
    /// installed SET by BCP-47 tag.
    ///
    /// There are two lists because a caller who named a language this Mac
    /// could not use has one of TWO problems with two different fixes.
    /// `en-XX` is a tag the engine has never heard of, and the fix is to
    /// spell it right; `fr-FR` is a tag it knows that this Mac has no model
    /// for, and the fix is a person pressing Download in the sheet. Told only
    /// "this Mac cannot recognise it", somebody with the second problem
    /// retypes a tag that was right all along.
    ///
    /// Cached like its twin, and an empty answer is not cached — nor is a
    /// list read against an EMPTY installed set, which is what the installed
    /// ask expiring looks like: cached, every row would read "not installed"
    /// for the rest of the session.
    static func supportedLanguages() -> [Language] {
        languageLock.lock()
        if let cached = cachedSupported {
            languageLock.unlock()
            return cached
        }
        languageLock.unlock()

        let installed = Set(SpeechEngine.installedLocales().map { $0.identifier(.bcp47) })
        let found = named(SpeechEngine.supportedLocales(), installed: installed)
        if !found.isEmpty, !installed.isEmpty {
            languageLock.lock()
            cachedSupported = found
            languageLock.unlock()
        }
        return found
    }

    /// Drops both caches, so the next ask reads the engine again — what the
    /// sheet's Download row does once a model has been installed.
    static func forgetLanguages() {
        languageLock.lock()
        cachedLanguages = nil
        cachedSupported = nil
        languageLock.unlock()
    }

    /// Locales as rows: tagged in BCP-47, named in this Mac's own language
    /// and sorted by that NAME rather than by tag, because a person reads the
    /// name — and both lists are built here so the popup and the two
    /// refusals cannot spell one locale two ways. `installed` nil means every
    /// row is installed; otherwise a row is installed when its tag is in it.
    /// A locale listed twice under one tag is one row.
    private static func named(_ locales: [Locale], installed: Set<String>?) -> [Language] {
        let names = Locale.current
        var seen = Set<String>()
        return locales.compactMap { locale -> Language? in
            let identifier = locale.identifier(.bcp47)
            guard seen.insert(identifier).inserted else { return nil }
            return Language(
                identifier: identifier,
                displayName: names.localizedString(forIdentifier: identifier) ?? identifier,
                installed: installed.map { $0.contains(identifier) } ?? true)
        }.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    /// The language a run defaults to: this Mac's own, then anything sharing
    /// its language code, then the first row — an INSTALLED row preferred at
    /// each step. Compared in BCP-47 (`Locale.current.identifier` is `en_US`
    /// and the rows are `en-US`). Over `languages()`, where every row is
    /// installed, this is exact → prefix → first.
    static func defaultLanguage(in list: [Language]) -> Language? {
        let current = Locale.current.identifier(.bcp47)
        func exact(_ row: Language) -> Bool {
            row.identifier.caseInsensitiveCompare(current) == .orderedSame
        }
        if let hit = list.first(where: { exact($0) && $0.installed }) { return hit }
        if let hit = list.first(where: exact) { return hit }
        let code = Locale.current.language.languageCode?.identifier ?? ""
        if !code.isEmpty {
            func near(_ row: Language) -> Bool { row.identifier.hasPrefix(code + "-") }
            if let hit = list.first(where: { near($0) && $0.installed }) { return hit }
            if let hit = list.first(where: near) { return hit }
        }
        return list.first(where: { $0.installed }) ?? list.first
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
