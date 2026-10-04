import AppKit

/// The app's document controller: it knows which paths AppKit's own open is
/// reading (spec §11 #234).
///
/// **Why it exists.** A document added for a URL while AppKit is still
/// reading that URL is not seen when the read ends, and AppKit adds a second
/// document at the path. An agent's `open_project` reads on the lane's
/// thread and adds its document itself (spec §11 #231), so without this it
/// could add one while a person's File ▸ Open, Finder double-click, Recent
/// row or drop of the same file was still reading, or a person's open could
/// begin and end inside the agent's own read. `AgentServer.openProject` asks
/// `isOpening` in each of its two main-thread steps and waits for the
/// person's open; `refuseHeldPath` refuses a write to a path being opened.
///
/// **What is counted.** The two public asynchronous opens, which every door
/// AppKit has reaches (spec §11 #234 lists them): one is added to the
/// path's count on the main thread before `super`, and taken off in the
/// completion handler, which AppKit calls on main after it has added the
/// document, before the caller's handler runs. A reopen with no URL (an
/// untitled document restored) holds no path and is not counted.
///
/// `main.swift` makes the one instance before anything else can make an
/// `NSDocumentController`: the first one instantiated is `.shared`. No other
/// product file instantiates it. A proof probe compiles every source but
/// `main.swift` and installs a controller of its own first, and there
/// `isOpening` answers false.
class ProjectDocumentController: NSDocumentController {

    /// Opens in flight, by `AgentServer.canonical` path. Main only.
    private var opening: [String: Int] = [:]

    override init() {
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ProjectDocumentController does not support NSCoder")
    }

    // MARK: - Launch

    /// Makes the app's controller. Called once, from `main.swift`, before
    /// `NSApplicationMain`.
    static func install() {
        let controller = ProjectDocumentController()
        if NSDocumentController.shared !== controller {
            NSLog("Reelcut: %@", "a document controller existed before ProjectDocumentController "
                + "was installed, so an open in flight is not counted (spec §11 #234)")
        }
    }

    /// The startup complaint when the shared controller is not this class
    /// (the `Reelcut: ` prefix every MCP proof requires absent).
    static func complainUnlessShared() {
        guard !(NSDocumentController.shared is ProjectDocumentController) else { return }
        NSLog("Reelcut: %@", "the shared document controller is not ProjectDocumentController, "
            + "so open_project cannot see a window's open in flight (spec §11 #234)")
    }

    // MARK: - What is being opened

    /// Whether AppKit's own open of `url` is in flight. Main only. False
    /// when the shared controller is not this class.
    static func isOpening(_ url: URL) -> Bool {
        guard let controller = NSDocumentController.shared as? ProjectDocumentController
        else { return false }
        return controller.opens(of: url) > 0
    }

    /// How many of AppKit's opens of `url` are in flight. Main only.
    func opens(of url: URL) -> Int {
        opening[AgentServer.canonical(url.path)] ?? 0
    }

    private func began(_ url: URL) -> String {
        let key = AgentServer.canonical(url.path)
        opening[key, default: 0] += 1
        return key
    }

    private func ended(_ key: String) {
        let left = (opening[key] ?? 1) - 1
        opening[key] = left > 0 ? left : nil
    }

    // MARK: - The two public opens

    override func openDocument(
        withContentsOf url: URL, display displayDocument: Bool,
        completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void
    ) {
        let key = began(url)
        super.openDocument(withContentsOf: url, display: displayDocument) {
            [weak self] document, wasOpen, error in
            self?.ended(key)
            completionHandler(document, wasOpen, error)
        }
    }

    override func reopenDocument(
        for urlOrNil: URL?, withContentsOf contentsURL: URL, display displayDocument: Bool,
        completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void
    ) {
        guard let url = urlOrNil else {
            super.reopenDocument(
                for: urlOrNil, withContentsOf: contentsURL, display: displayDocument,
                completionHandler: completionHandler)
            return
        }
        let key = began(url)
        super.reopenDocument(for: url, withContentsOf: contentsURL, display: displayDocument) {
            [weak self] document, wasOpen, error in
            self?.ended(key)
            completionHandler(document, wasOpen, error)
        }
    }
}
