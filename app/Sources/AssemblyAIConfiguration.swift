import Foundation

/// The two things that make an AssemblyAI client, resolved in one place: WHERE
/// it speaks (the base URL) and WHAT it says it is (the credential). R6-6 —
/// the protocol boundary is exactly this pair, so the stand-in server of road
/// map 6 §5i, the EU endpoint and a same-protocol relay are configurations
/// and not code.
///
/// **R6-9, the rule this file is the whole of.** A proof-launched app must
/// never open the person's stored key. `-RCSecretFolder <path>` overrides the
/// store's folder; with `-RCAssemblyAIEndpoint` set and no `-RCSecretFolder`,
/// NO `FileStore` is built at all and `store()` answers an empty
/// `MemoryStore`, so an app pointed at a stand-in has the environment as its
/// only credential. Both arguments are read ONLY out of the ARGUMENT domain,
/// so a persisted default — `UserDefaults`, a plist somebody wrote, a
/// leftover from another session — can redirect neither. Without that rule a
/// machine where the person had saved a real key would send it to a server
/// that writes every header to disk.
///
/// **`AppSupport.directory` is touched in exactly one line of this file** and
/// nowhere else in the feature, which is what makes "no proof reads the real
/// folder" checkable by reading rather than by hoping.
enum AssemblyAIConfiguration {

    /// The endpoint override, the `-RCRecordingFolder` idiom
    /// (`RecordingSetup.swift`). A whole base URL rather than a host, because
    /// the scheme is part of what is being overridden: the stand-in speaks
    /// plain HTTP.
    static let endpointArgument = "RCAssemblyAIEndpoint"

    /// The store-folder override (R6-9). A PATH, never a key — `ps` shows
    /// every launch argument to every user on the machine, which is the same
    /// reason R6-5 keeps the credential out of `transcribe`'s arguments.
    static let secretFolderArgument = "RCSecretFolder"

    /// The persisted region, the Settings window's popup.
    static let regionKey = "ReelcutAssemblyAIRegion"

    /// The environment override, read only when the store has nothing
    /// (R6-5, R6-9 (d)).
    static let environmentKey = "RC_ASSEMBLYAI_KEY"

    /// AssemblyAI's two data regions (road map 6 §2). A transcript made in
    /// one is not visible in the other, which is why this is a setting and
    /// not a fallback.
    enum Region: String, CaseIterable {
        case us
        case eu

        var base: URL {
            switch self {
            case .us: return Region.url("https://api.assemblyai.com")
            case .eu: return Region.url("https://api.eu.assemblyai.com")
            }
        }

        /// `URL(string:)` is optional because its input is usually somebody
        /// else's; these two are literals on the lines above. A parse that
        /// failed would be a typo there, and the fallback reaches no host at
        /// all — every request against it refuses, which is the safe
        /// direction: never a DIFFERENT server.
        private static func url(_ text: String) -> URL {
            URL(string: text) ?? URL(fileURLWithPath: "/dev/null")
        }

        var displayName: String {
            switch self {
            case .us: return "United States"
            case .eu: return "European Union"
            }
        }
    }

    /// Why a configured endpoint cannot be used, in a sentence the Settings
    /// window and a tool can both print.
    enum ConfigurationError: LocalizedError, Equatable {
        case malformedEndpoint(String)
        case insecureEndpoint(String)

        var errorDescription: String? {
            switch self {
            case .malformedEndpoint(let text):
                return "“\(text)” is not a URL the transcription service can be reached at."
            case .insecureEndpoint(let host):
                return "A plain HTTP endpoint is only allowed for a local server, and "
                    + "“\(host)” is not one."
            }
        }
    }

    /// The region the person chose. An unknown or absent value is `.us`, not
    /// an error: a defaults file written by a later build, or by hand, must
    /// not stop the app from transcribing.
    static func region(defaults: UserDefaults = .standard) -> Region {
        guard let raw = defaults.string(forKey: regionKey), let region = Region(rawValue: raw)
        else { return .us }
        return region
    }

    /// Where the client speaks: the argument-domain endpoint when one is set,
    /// the region's own host otherwise.
    static func baseURL(defaults: UserDefaults = .standard) throws -> URL {
        guard let override = argument(endpointArgument, defaults: defaults) else {
            return region(defaults: defaults).base
        }
        guard let url = URL(string: override), let scheme = url.scheme?.lowercased(),
            let host = url.host, !host.isEmpty
        else { throw ConfigurationError.malformedEndpoint(override) }
        guard scheme == "http" || scheme == "https" else {
            throw ConfigurationError.malformedEndpoint(override)
        }
        // Plain HTTP for a loopback host only. C0's q3 measured that macOS
        // 26.5.1 does not block it from an ad-hoc-signed hardened-runtime
        // bundle with no ATS key at all, which is why `project.yml` carries
        // none — and this guard is what keeps that measurement from becoming
        // a licence to send a key over the open network in clear.
        guard scheme == "https" || isLoopback(host) else {
            throw ConfigurationError.insecureEndpoint(host)
        }
        return url
    }

    /// The `SecretStore` this process may use, and R6-9's whole decision in
    /// one function.
    ///
    /// With `-RCSecretFolder` set, a `FileStore` on that folder: a proof's
    /// own disposable directory. With no `-RCSecretFolder` but
    /// `-RCAssemblyAIEndpoint` set, an EMPTY `MemoryStore`: the app has been
    /// pointed at something that is not AssemblyAI, so the person's stored
    /// key is not opened at all and `RC_ASSEMBLYAI_KEY` is the only
    /// credential such a run can have. With neither, the person's own file
    /// under `AppSupport.directory` — the ONE line in this feature that names
    /// it. A machine with no Application Support folder answers an empty
    /// `MemoryStore` too, which reads as "no key is set".
    static func store(defaults: UserDefaults = .standard) -> any SecretStore {
        if let folder = argument(secretFolderArgument, defaults: defaults) {
            return FileStore(
                directory: URL(
                    fileURLWithPath: (folder as NSString).expandingTildeInPath,
                    isDirectory: true))
        }
        if argument(endpointArgument, defaults: defaults) != nil { return MemoryStore() }
        guard let directory = AppSupport.directory else { return MemoryStore() }
        return FileStore(directory: directory)
    }

    /// The credential: the store first, the environment second (R6-5, and
    /// R6-9 (d) amends the wording of that order and not the order). An empty
    /// environment variable is no credential, for `FileStore.read`'s reason.
    static func credential(
        store: any SecretStore,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        if let stored = store.read() { return stored }
        guard let value = environment[environmentKey] else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The three spellings of this machine, and only those three.
    /// `localhost.evil.com` resolves wherever its owner says and is not one
    /// of them; a bracketed IPv6 literal arrives from `URL.host` without its
    /// brackets, which is why `::1` is compared bare.
    static func isLoopback(_ host: String) -> Bool {
        let name = host.lowercased()
        return name == "127.0.0.1" || name == "localhost" || name == "::1"
    }

    /// A launch argument, from the ARGUMENT domain alone (R6-9 (c)). Reading
    /// it off `UserDefaults.standard.string(forKey:)` would let a value
    /// persisted in the app's own plist — by a previous session, by an
    /// installer, by anything running as the person — move where the key is
    /// read from, which is exactly what this rule forbids. Empty is absent.
    static func argument(_ key: String, defaults: UserDefaults) -> String? {
        let domain = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        guard let value = domain[key] as? String, !value.isEmpty else { return nil }
        return value
    }
}
