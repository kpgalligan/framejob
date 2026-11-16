// app/Sources/GraphicLinkController+App.swift — the app's side of a
// `framejob://` link (spec §11 G-49): the one controller, the Apple Event
// handler, the scheme the bundle claims, the dev switch, the hand-off to
// G-47's import and the alert.
//
// **An Apple Event handler, never `application(_:open:)`** (G-49 (j)): a
// delegate that implements that method takes every Finder open away from
// `NSDocumentController`, which is every `.framejob` and `.fjgraphic` door.
// `install()` runs from `applicationWillFinishLaunching`, because a link
// that launches Frame Job is delivered inside `finishLaunching`.
//
// **No second import.** A fetched file goes to
// `GraphicImportSheetController.open(packageAt:origin:onRead:)`, the Finder
// door, which reads it once launch has settled and puts the sheet up.
//
// **A refusal is one alert** (G-49 (h)), then the Welcome window when Frame
// Job has no project and no window, as after a link that launched it.

import AppKit

extension GraphicLinkController {
    static let shared = GraphicLinkController(
        scheme: claimedScheme(), policy: launchPolicy(), limits: .shipped, handOff: importSheet)

    // MARK: - The event

    func install() {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc func handleGetURL(
        _ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor
    ) {
        receive(Self.text(of: event) ?? "", report: Self.showAlert)
    }

    /// The URL a `kAEGetURL` event carries.
    static func text(of event: NSAppleEventDescriptor) -> String? {
        event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue
    }

    // MARK: - The product's values

    /// The scheme this bundle claims: `framejob`, or a Debug build's `framejob-debug`.
    static func claimedScheme() -> String {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        return (types?.first?["CFBundleURLSchemes"] as? [String])?.first ?? "framejob"
    }

    static func launchPolicy() -> GraphicLink.Policy {
        #if FRAMEJOB_DEV_TOOLS
        var policy = GraphicLink.Policy()
        // The ARGUMENT domain only: a persisted default must never open the switch.
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        let value = arguments["RCDevGraphicLinkLoopbackHTTP"]
        policy.loopbackHTTP =
            (value as? String).map { ["yes", "true", "1"].contains($0.lowercased()) }
            ?? (value as? NSNumber)?.boolValue ?? false
        return policy
        #else
        return GraphicLink.Policy()
        #endif
    }

    static let importSheet: HandOff = { fetched, origin, afterRead in
        GraphicImportSheetController.open(packageAt: fetched.file, origin: origin) { error in
            afterRead(error.map { ($0 as? ReelCoreError)?.message ?? $0.localizedDescription })
        }
    }

    /// The product's `report`: nothing for a sheet, G-49 (h)'s alert otherwise.
    static func showAlert(_ outcome: Outcome) {
        let heading: String
        let body: String
        switch outcome {
        case .sheet:
            return
        case .refused(let host, let sentence, _):
            heading =
                host.map { "The graphic from \($0) could not be opened." }
                ?? "This link cannot be opened."
            // The system's own words (a failed connection's) may already end a sentence.
            let ended = sentence.hasSuffix(".") ? "" : "."
            body = sentence.prefix(1).uppercased() + sentence.dropFirst() + ended
        case .unreadable(let host, let message, _):
            heading = "The graphic from \(host) could not be opened."
            body = message
        }
        ProjectDocumentController.whenSettled {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = heading
            alert.informativeText = body
            if let window = GraphicImportSheetController.frontEditor()?.view.window {
                alert.beginSheetModal(for: window, completionHandler: nil)
                return
            }
            alert.runModal()
            // A link that launched Frame Job and was refused: never an app with no window.
            if NSDocumentController.shared.documents.isEmpty,
                !NSApp.windows.contains(where: { $0.isVisible })
            {
                WelcomeWindowController.shared.show()
            }
        }
    }
}
