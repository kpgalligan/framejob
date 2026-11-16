#if FRAMEJOB_DEV_TOOLS
import AppKit

/// What `open_link` remembers: each link it handed over and how it ended.
/// Every call carries its own reader into `GraphicLinkController.receive`,
/// so an outcome can only land on its own entry.
final class GraphicLinkDevLog: @unchecked Sendable {
    static let shared = GraphicLinkDevLog()

    private let condition = NSCondition()
    private var entries: [(url: String, outcome: [String: Any]?)] = []

    func begin(_ url: String) -> Int {
        condition.lock()
        defer { condition.unlock() }
        entries.append((url, nil))
        return entries.count - 1
    }

    func end(_ index: Int, _ outcome: [String: Any]) {
        condition.lock()
        entries[index].outcome = outcome
        condition.broadcast()
        condition.unlock()
    }

    /// Entry `index`'s row once it has ended, or pending at the bound; nil `index` waits
    /// for every entry and answers them all.
    func wait(_ index: Int?, seconds: Double) -> [[String: Any]] {
        let deadline = Date().addingTimeInterval(seconds)
        condition.lock()
        defer { condition.unlock() }
        let waiting = { () -> Bool in
            index.map { self.entries[$0].outcome == nil }
                ?? self.entries.contains { $0.outcome == nil }
        }
        while waiting(), condition.wait(until: deadline) {}
        let rows = entries.map { entry -> [String: Any] in
            var row = entry.outcome ?? ["outcome": "pending"]
            row["url"] = entry.url
            return row
        }
        return index.map { [rows[$0]] } ?? rows
    }
}

/// `open_link`, a DEV TOOL (spec §11 G-49 (l)): a proof's stand-in for a
/// browser's click. It builds the `kAEGetURL` event a link arrives as, reads
/// it with the product's reader and hands it to the product's
/// `GraphicLinkController.shared.receive`, with a reader of its own in place
/// of the alert: an application-modal alert would hold the instance. It
/// mirrors no edit; the import it can lead to is the sheet's own.
extension AgentServer {

    static let openLinkWaitLimit: Double = 300

    func openLink(_ a: [String: Any]) throws -> String {
        guard !Thread.isMainThread else {
            throw ToolError(
                message: "open_link must run on the server thread — its name is missing from "
                    + "AgentServer.devOffMainTools.")
        }
        let url = try stringArg(a, "url")
        let wait = try doubleArg(a, "wait") ?? 150
        guard (0...Self.openLinkWaitLimit).contains(wait) else {
            throw ToolError(message: "wait must be 0…\(Int(Self.openLinkWaitLimit)) seconds.")
        }
        let log = GraphicLinkDevLog.shared
        var index: Int?
        if let url {
            let entry = log.begin(url)
            index = entry
            onMain {
                let event = NSAppleEventDescriptor(
                    eventClass: AEEventClass(kInternetEventClass), eventID: AEEventID(kAEGetURL),
                    targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
                    transactionID: AETransactionID(kAnyTransactionID))
                event.setParam(NSAppleEventDescriptor(string: url), forKeyword: keyDirectObject)
                GraphicLinkController.shared.receive(
                    GraphicLinkController.text(of: event) ?? ""
                ) { outcome in
                    log.end(entry, Self.linkRow(outcome))
                }
            }
        }
        let rows = log.wait(index, seconds: wait)
        let answer: [String: Any] = index == nil ? ["links": rows] : rows[0]
        let data = try JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys])
        return try callResult(
            content: [["type": "text", "text": String(decoding: data, as: UTF8.self)]],
            isError: false)
    }

    private static func linkRow(_ outcome: GraphicLinkController.Outcome) -> [String: Any] {
        switch outcome {
        case .sheet(let first, let final, let bytes, let gone):
            return [
                "outcome": "sheet", "host": first, "final_host": final, "bytes": bytes,
                "temp_removed": gone,
            ]
        case .refused(let host, let sentence, let gone):
            var row: [String: Any] = [
                "outcome": "refused", "message": sentence, "temp_removed": gone,
            ]
            if let host { row["host"] = host }
            return row
        case .unreadable(let host, let message, let gone):
            return [
                "outcome": "refused", "message": message, "host": host, "temp_removed": gone,
            ]
        }
    }

    // MARK: - Catalog

    func openLinkTool() -> [String: Any] {
        tool(
            "open_link",
            "DEV TOOL (absent from Distribution builds). Hand Frame Job a link as a browser's "
                + "click does (spec G-49): a framejob://graphic?src=<https URL> link (a Debug "
                + "build claims framejob-debug://) makes Frame Job fetch a .fjgraphic itself "
                + "and ask about it in the Import Graphic sheet. url: the link; the call "
                + "waits up to wait seconds (default 150, 0 answers at once) for it to end "
                + "and answers {url, outcome: sheet | refused | pending, message (a refusal's "
                + "sentence, shown here in place of the alert), host, final_host and bytes (a "
                + "sheet), temp_removed}. With no url: waits for every earlier link and "
                + "answers {links: [...]}, oldest first. Nothing is imported until the "
                + "sheet's Import. The dev-only launch argument "
                + "-RCDevGraphicLinkLoopbackHTTP YES lets src and a redirect be "
                + "http://127.0.0.1 (that host only), for a local stand-in server.",
            [
                "url": [
                    "type": "string",
                    "description": "The link to open. Absent: answer every earlier link.",
                ],
                "wait": [
                    "type": "number",
                    "description": "Seconds to wait for the outcome, 0…300. Default 150.",
                ],
            ])
    }
}
#endif
