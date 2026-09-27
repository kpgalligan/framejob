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

    /// The helper's `ChatSettings` (`agent/src/protocol.ts`): compaction at
    /// the end of a turn past 300 000 tokens (AI-9), and old tool results kept.
    static let settingsJSON: [String: Any] = [
        "auto_compact_tokens": 300_000, "clear_tool_results": false,
    ]

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
