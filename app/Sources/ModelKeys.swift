import AppKit

/// The two keys a feature may need (spec §11 CJ-3): the person's Anthropic
/// key (AI-8, Settings ▸ Assistant) and their AssemblyAI key (R6-5,
/// Settings ▸ Transcription).
enum ModelKey: String, CaseIterable {
    case anthropic, assemblyAI

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .assemblyAI: return "AssemblyAI"
        }
    }

    /// The Settings pane that holds the key.
    var settingsSection: String {
        switch self {
        case .anthropic: return "Assistant"
        case .assemblyAI: return "Transcription"
        }
    }

    /// What a keyed menu item's title gains while it is off for this key
    /// (CJ-10, the owner's answer 4).
    var titleSuffix: String { " (needs your \(displayName) key)" }

    /// The clause every keyed tool's catalog description ends with (CJ-11),
    /// which the parity check's sixth part looks for (CJ-13).
    var catalogClause: String {
        "Keyed (spec §11 CJ-3): where it would send to \(displayName) it needs the person's "
            + "\(displayName) API key, and without one it refuses there with "
            + "\"\(ModelKeys.sentence(self))\""
    }
}

/// One row of the keyed table (CJ-12): a feature that sends to a model, its
/// key, the menu action that starts it (nil when it has none), the tools that
/// send for it, and whether it is keyed only when it would send.
struct KeyedFeature {
    let name: String
    let key: ModelKey
    let menuAction: Selector?
    let tools: [String]
    let conditional: Bool
}

/// The one test of whether a key is present, and everything a keyed surface
/// says when it is not (spec §11 CJ-10…CJ-13).
///
/// **Nothing is memoised.** A presence test is one small file read; a memo
/// would be wrong for a sheet's injected store and stale when another Frame
/// Job writes the key. The senders still read the credential to send it —
/// this answers only whether one resolves.
///
/// **`enabled` is always the caller's whole rule.** Neither `mark` overrides
/// it: `missing` says only WHY a control is off, so each caller's own key
/// term stays the gate its mutants test.
///
/// **A key saved or removed reaches every open keyed surface at once.** The
/// two keys post two different notifications, so one observer of each,
/// installed once, resets the main menu's satisfied marks and re-posts
/// `didChangeNotification`, the one a keyed surface observes. A menu item is
/// otherwise re-titled only by its validator, which does not run while a
/// sheet is up or with no editor in the responder chain.
enum ModelKeys {
    static let didChangeNotification = Notification.Name("FrameJobModelKeysDidChange")
    /// The notification's `userInfo` key; its value is the source key's
    /// `rawValue`.
    static let keyInfoKey = "key"

    /// The keyed table (CJ-12). TX6, TX7 and FC7b add rows.
    static let keyed: [KeyedFeature] = [
        KeyedFeature(
            name: "Remove Filler Words", key: .assemblyAI,
            menuAction: #selector(EditorViewController.removeFillerWords(_:)),
            tools: ["transcribe_for_fillers"], conditional: true),
        KeyedFeature(
            name: "Generate Captions with AssemblyAI", key: .assemblyAI, menuAction: nil,
            tools: ["transcribe"], conditional: true),
        KeyedFeature(
            name: "Assistant", key: .anthropic, menuAction: nil, tools: assistantTools,
            conditional: false),
    ]

    /// `assistant_send` is a dev tool, absent from Distribution builds.
    #if FRAMEJOB_DEV_TOOLS
    private static let assistantTools = ["assistant_send"]
    #else
    private static let assistantTools: [String] = []
    #endif

    // MARK: - Presence and the words

    /// Whether `key` resolves through `store` (else the key's own
    /// configuration's) and `environment`, in R6-5's order.
    static func present(
        _ key: ModelKey, store: (any SecretStore)? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        switch key {
        case .assemblyAI:
            return AssemblyAIConfiguration.credential(
                store: store ?? AssemblyAIConfiguration.store(), environment: environment) != nil
        case .anthropic:
            let resolved = store ?? AssistantConfiguration.store(environment: environment)
            return AssistantConfiguration.credential(
                store: resolved, environment: environment) != nil
        }
    }

    /// CJ-11's sentence: the tooltip, the note and the refusal alike.
    static func sentence(_ key: ModelKey) -> String {
        switch key {
        case .assemblyAI:
            return "No AssemblyAI API key is set. Set one in Frame Job ▸ Settings… ▸ Transcription."
        case .anthropic:
            return "No Anthropic API key is set. Set one in Frame Job ▸ Settings… ▸ Assistant."
        }
    }

    /// A keyed tool's refusal where it would send (CJ-12).
    static func refusal(_ key: ModelKey) -> AgentServer.ToolError {
        AgentServer.ToolError(message: sentence(key))
    }

    /// Throws `refusal(key)` unless `key` is present.
    static func require(
        _ key: ModelKey, store: (any SecretStore)? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        guard present(key, store: store, environment: environment) else { throw refusal(key) }
    }

    // MARK: - Marking a control

    /// A sheet's button: enabled by the caller's whole rule, with the missing
    /// key's sentence as its tooltip, or none.
    static func mark(_ control: NSControl?, missing: ModelKey?, enabled: Bool) {
        guard let control else { return }
        control.isEnabled = enabled
        control.toolTip = missing.map(sentence)
    }

    /// A menu item: its base title plus the missing key's suffix, and the
    /// sentence as its tooltip, each assigned only when it differs. Answers
    /// `enabled`, for a validator to return.
    @discardableResult
    static func mark(_ item: NSMenuItem?, missing: ModelKey?, enabled: Bool) -> Bool {
        _ = installed
        guard let item else { return enabled }
        let title = baseTitle(item.title) + (missing?.titleSuffix ?? "")
        if item.title != title { item.title = title }
        let tip = missing.map(sentence)
        if item.toolTip != tip { item.toolTip = tip }
        return enabled
    }

    /// `title` without either key's suffix.
    static func baseTitle(_ title: String) -> String {
        for key in ModelKey.allCases where title.hasSuffix(key.titleSuffix) {
            return String(title.dropLast(key.titleSuffix.count))
        }
        return title
    }

    /// Every item in `menu`, at any depth, whose action is a keyed row's and
    /// whose key is present now gets its base title and no tooltip. Nothing
    /// else changes, and no suffix is ever added here.
    static func clearSatisfiedMarks(in menu: NSMenu?) {
        guard let menu else { return }
        var actions: Set<Selector> = []
        for row in keyed {
            if let action = row.menuAction, present(row.key) { actions.insert(action) }
        }
        guard !actions.isEmpty else { return }
        clear(menu, actions)
    }

    private static func clear(_ menu: NSMenu, _ actions: Set<Selector>) {
        for item in menu.items {
            if let submenu = item.submenu { clear(submenu, actions) }
            guard let action = item.action, actions.contains(action) else { continue }
            let base = baseTitle(item.title)
            if item.title != base { item.title = base }
            if item.toolTip != nil { item.toolTip = nil }
        }
    }

    // MARK: - The notification

    /// Adds `observer` for `didChangeNotification`, installing the relay
    /// first.
    static func observe(_ observer: AnyObject, selector: Selector) {
        _ = installed
        NotificationCenter.default.addObserver(
            observer, selector: selector, name: didChangeNotification, object: nil)
    }

    /// The one-time install: one observer of each key's own notification.
    private static let installed: Void = {
        let center = NotificationCenter.default
        _ = center.addObserver(
            forName: SettingsWindowController.didChangeNotification, object: nil, queue: nil
        ) { _ in relay(.assemblyAI) }
        _ = center.addObserver(
            forName: AssistantConfiguration.didChangeNotification, object: nil, queue: nil
        ) { _ in relay(.anthropic) }
    }()

    /// Synchronously, in this order: the menu's satisfied marks reset, then
    /// `didChangeNotification` posted with the source key.
    private static func relay(_ key: ModelKey) {
        clearSatisfiedMarks(in: NSApp?.mainMenu)
        NotificationCenter.default.post(
            name: didChangeNotification, object: nil, userInfo: [keyInfoKey: key.rawValue])
    }
}
