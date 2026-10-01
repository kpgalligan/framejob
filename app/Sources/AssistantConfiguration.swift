import Foundation

/// What the assistant's session is configured with, resolved in one place:
/// the person's key (spec §11 AI-8), where the helper speaks (AI-13), the
/// model (AI-11) and the chat settings. Road map 12 A1.
///
/// **AI-13, the rule this file keeps.** A proof-launched app must never open
/// the person's stored key. `-RCSecretFolder <path>`, read from the ARGUMENT
/// domain alone (`AssemblyAIConfiguration.argument`, R6-9 (c)), names the
/// folder of `anthropic-key`; with `RC_ASSISTANT_BASE_URL` set and no
/// `-RCSecretFolder`, NO `FileStore` is built and `store()` answers an empty
/// `MemoryStore`, so an app pointed at a stand-in has the environment as its
/// only credential. The override is an environment variable, never a
/// default, because a variable cannot be persisted in the app's plist.
///
/// **`AppSupport.directory` is touched in exactly one line of this file**,
/// as in `AssemblyAIConfiguration.swift`, so "no proof reads the person's
/// folder" is checkable by reading.
///
/// **The key is never a tool argument, a launch argument or an answer**
/// (AI-8, R6-12): `credential` hands it to `AssistantSession.open`, which
/// writes it into the helper's `configure` on stdin and nowhere else. No tool
/// reads or writes the model (AI-11); it is a person's setting.
enum AssistantConfiguration {

    /// The store's file, beside AssemblyAI's `assemblyai-key`.
    static let keyFileName = "anthropic-key"

    /// The environment override, read only when the store has nothing
    /// (R6-5, R6-9 (d)).
    static let environmentKey = "ANTHROPIC_API_KEY"

    /// The helper's `api_base` (AI-13): the stand-in server's address in a
    /// proof. `protocol.ts` calls it "an environment variable of its own".
    static let baseURLVariable = "RC_ASSISTANT_BASE_URL"

    /// The persisted model, Settings' Assistant pane from A2.
    static let modelKey = "ReelcutAssistantModel"

    /// AI-11's default.
    static let defaultModel = "claude-opus-5-5"

    /// The helper's `ChatSettings` (`agent/src/protocol.ts`): the person's
    /// chat settings from Settings' Assistant pane (AI-20). A dev build's
    /// `-RCDevAssistantAutoCompact <tokens>` replaces the threshold, even
    /// with compaction off, for a proof (AI-18).
    static func settingsJSON(defaults: UserDefaults = .standard) -> [String: Any] {
        var json = AssistantChatSettings.load(from: defaults).helperJSON
        #if REELCUT_DEV_TOOLS
        if let tokens = devAutoCompactTokens(defaults: defaults) {
            json["auto_compact_tokens"] = tokens
        }
        #endif
        return json
    }

    /// Why the base-URL override cannot be used, in the sentence the session
    /// refuses with.
    enum ConfigurationError: LocalizedError, Equatable {
        case malformedBase(String)
        case insecureBase(String)

        var errorDescription: String? {
            switch self {
            case .malformedBase(let text):
                return "RC_ASSISTANT_BASE_URL “\(text)” is not a URL the assistant can reach."
            case .insecureBase(let host):
                return "A plain HTTP RC_ASSISTANT_BASE_URL is only allowed for a local server, "
                    + "and “\(host)” is not one."
            }
        }
    }

    /// The `SecretStore` the assistant may use, and AI-13's whole decision in
    /// one function: `-RCSecretFolder`'s folder; else, with the base-URL
    /// override set, an EMPTY `MemoryStore`; else the person's own file under
    /// `AppSupport.directory`; else (no such folder) an empty `MemoryStore`.
    static func store(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> any SecretStore {
        let folderKey = AssemblyAIConfiguration.secretFolderArgument
        if let folder = AssemblyAIConfiguration.argument(folderKey, defaults: defaults) {
            return FileStore(
                directory: URL(
                    fileURLWithPath: (folder as NSString).expandingTildeInPath,
                    isDirectory: true),
                name: keyFileName)
        }
        if let base = environment[baseURLVariable], !base.isEmpty { return MemoryStore() }
        guard let directory = AppSupport.directory else { return MemoryStore() }
        return FileStore(directory: directory, name: keyFileName)
    }

    /// The credential: the store first, the environment second (R6-9 (d)).
    /// An empty environment variable is no credential.
    static func credential(
        store: any SecretStore,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        if let stored = store.read() { return stored }
        guard let value = environment[environmentKey] else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The helper's `api_base`, or nil (the SDK's own host) when the override
    /// is unset or empty. Plain HTTP for a loopback host only (AI-13, R6-9).
    static func baseURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL? {
        guard let text = environment[baseURLVariable], !text.isEmpty else { return nil }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
            let host = url.host, !host.isEmpty,
            scheme == "http" || scheme == "https"
        else { throw ConfigurationError.malformedBase(text) }
        guard scheme == "https" || AssemblyAIConfiguration.isLoopback(host) else {
            throw ConfigurationError.insecureBase(host)
        }
        return url
    }

    /// The model the person chose, else AI-11's default. Blank is unset.
    static func model(defaults: UserDefaults = .standard) -> String {
        let chosen = defaults.string(forKey: modelKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let chosen, !chosen.isEmpty else { return defaultModel }
        return chosen
    }
}

extension AssistantConfiguration {
    /// Posted by Settings' Assistant pane, and only by it, when the key is
    /// saved or removed, the model changes or the chat settings change. A key
    /// or model change ends each window's conversation, since a session keeps
    /// what it was opened with (road map 12 A2); a chat-settings change is
    /// written to each open session and ends nothing (AI-20).
    static let didChangeNotification = Notification.Name("ReelcutAssistantConfigurationDidChange")

    /// The notification's `userInfo` key; its value is "key", "model" or
    /// "settings".
    static let changeKey = "change"
}

/// The person's chat settings (spec §11 AI-20), Rasterize's two under
/// Reelcut's keys: end-of-turn compaction past a threshold (AI-9), and the
/// API's clearing of old tool results past the helper's fixed trigger. Kept
/// in `UserDefaults`; no tool reads or writes them (AI-11's reason).
struct AssistantChatSettings: Equatable {
    /// AI-9's threshold, and the one 300 000 in the app.
    static let defaultCompactTokens = 300_000
    static let compactTokensRange = 20_000...900_000
    /// `agent/src/main.ts`'s `CLEAR_TRIGGER_TOKENS` (the settings proof's CS1).
    static let clearTriggerTokens = 150_000
    /// Bool; absent = true.
    static let autoCompactKey = "ReelcutAssistantAutoCompact"
    /// Int; absent or outside the range = the default.
    static let autoCompactTokensKey = "ReelcutAssistantAutoCompactTokens"
    /// Bool; absent = false.
    static let clearToolResultsKey = "ReelcutAssistantClearToolResults"

    var autoCompact = true
    var autoCompactTokens = defaultCompactTokens
    var clearToolResults = false

    static func load(from defaults: UserDefaults = .standard) -> AssistantChatSettings {
        var settings = AssistantChatSettings()
        if defaults.object(forKey: autoCompactKey) != nil {
            settings.autoCompact = defaults.bool(forKey: autoCompactKey)
        }
        if defaults.object(forKey: autoCompactTokensKey) != nil {
            let tokens = defaults.integer(forKey: autoCompactTokensKey)
            if compactTokensRange.contains(tokens) { settings.autoCompactTokens = tokens }
        }
        settings.clearToolResults = defaults.bool(forKey: clearToolResultsKey)
        return settings
    }

    /// Writes all three keys.
    func save(to defaults: UserDefaults = .standard) {
        defaults.set(autoCompact, forKey: Self.autoCompactKey)
        defaults.set(autoCompactTokens, forKey: Self.autoCompactTokensKey)
        defaults.set(clearToolResults, forKey: Self.clearToolResultsKey)
    }

    /// `protocol.ts`'s `ChatSettings`: the threshold, or null when compaction
    /// is off, and whether old tool results are cleared.
    var helperJSON: [String: Any] {
        [
            "auto_compact_tokens": autoCompact ? autoCompactTokens as Any : NSNull(),
            "clear_tool_results": clearToolResults,
        ]
    }
}

#if REELCUT_DEV_TOOLS
extension AssistantConfiguration {
    /// `-RCDevAssistantAutoCompact <tokens>` — a dev-only LAUNCH default
    /// (spec §11 AI-18): the end-of-turn compaction threshold a proof lowers,
    /// read from the argument domain alone. It replaces the person's
    /// threshold (`AssistantChatSettings`, AI-20).
    static let devAutoCompactArgument = "RCDevAssistantAutoCompact"

    /// The knob's tokens, or nil when it is absent. A value that is not a
    /// whole number of 1 or more is named on stderr and ignored.
    static func devAutoCompactTokens(defaults: UserDefaults) -> Int? {
        guard let raw = AssemblyAIConfiguration.argument(devAutoCompactArgument, defaults: defaults)
        else { return nil }
        if let tokens = Int(raw), tokens >= 1 { return tokens }
        let line = "\(devAutoCompactArgument) must be a whole number of tokens, 1 or more "
            + "(got \"\(raw)\"); it is ignored.\n"
        FileHandle.standardError.write(Data(line.utf8))
        return nil
    }
}
#endif
