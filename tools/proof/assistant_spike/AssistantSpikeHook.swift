// Road map 12, A0 — the spike's hook. Compiled ONLY into the spike's tree
// copy (`work/assistant_spike/tree/app/Sources/`), never into the product:
// `assistant_spike.py` copies it there and calls `startIfAsked()` from the
// copy's `AppDelegate.applicationDidFinishLaunching`.
//
// Inert unless the `UserDefaults` string `RCAssistantSpikeLog` names a file.
// Then it logs the catalog, waits (a main-run-loop Timer, never a sleep or a
// semaphore on main) for a `ProjectDocument` that has a file, launches
// `Contents/Helpers/reelcut-agent` the way Rasterize's
// `AssistantHelperSession.open` does, configures it with the dummy key
// `proof-key`, sends one message, and runs each `tool_request` through
// `AgentServer.shared.execute`. Every step is one JSON line in the log.
import AppKit

enum AssistantSpikeHook {
    private static var logURL: URL?
    private static let logQueue = DispatchQueue(label: "reelcut.a0-spike.log")
    private static let writeQueue = DispatchQueue(label: "reelcut.a0-spike.write")
    private static var process: Process?
    private static var toHelper: Pipe?
    private static var lineBuffer = Data()
    private static var finished = false

    static func startIfAsked() {
        guard let path = UserDefaults.standard.string(forKey: "RCAssistantSpikeLog"),
            !path.isEmpty
        else { return }
        logURL = URL(fileURLWithPath: path)
        FileManager.default.createFile(atPath: path, contents: nil)
        let catalog: String
        do {
            catalog = try AgentServer.shared.catalogJSON()
        } catch {
            log(["event": "catalog_failed", "error": "\(error)"])
            return
        }
        let tools = toolList(catalog)
        log(["event": "catalog", "bytes": catalog.utf8.count, "tools": tools.count])
        let started = Date()
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
            let document = NSDocumentController.shared.documents
                .compactMap { $0 as? ProjectDocument }
                .first { $0.fileURL != nil }
            if document != nil {
                timer.invalidate()
                launch(tools: tools)
            } else if Date().timeIntervalSince(started) > 60 {
                timer.invalidate()
                log(["event": "timeout", "waiting_for": "a ProjectDocument with a file"])
            }
        }
    }

    private static func toolList(_ catalog: String) -> [Any] {
        let object = try? JSONSerialization.jsonObject(with: Data(catalog.utf8))
        if let list = object as? [Any] { return list }
        if let wrapped = object as? [String: Any], let list = wrapped["tools"] as? [Any] {
            return list
        }
        return []
    }

    private static func launch(tools: [Any]) {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/reelcut-agent")
        let executable = FileManager.default.isExecutableFile(atPath: helper.path)
        log(["event": "helper", "path": helper.path, "executable": executable])
        guard executable else {
            log(["event": "launch_failed", "error": "not executable"])
            return
        }
        let process = Process()
        let toHelper = Pipe()
        let fromHelper = Pipe()
        process.executableURL = helper
        process.standardInput = toHelper
        process.standardOutput = fromHelper
        let stderrPath = (logURL?.path ?? "/dev/null") + ".stderr"
        FileManager.default.createFile(atPath: stderrPath, contents: nil)
        process.standardError = FileHandle(forWritingAtPath: stderrPath)
        process.environment = [
            "HOME": NSHomeDirectory(), "TMPDIR": NSTemporaryDirectory(), "PATH": "/usr/bin:/bin",
        ]
        _ = fcntl(toHelper.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        fromHelper.fileHandleForReading.readabilityHandler = { handle in
            consume(handle.availableData)
        }
        process.terminationHandler = { ended in
            let reason = ended.terminationReason == .exit ? "exit" : "uncaughtSignal"
            log(["event": "exited", "status": Int(ended.terminationStatus), "reason": reason])
        }
        do {
            try process.run()
        } catch {
            log(["event": "launch_failed", "error": "\(error)"])
            return
        }
        self.process = process
        self.toHelper = toHelper
        log(["event": "launched", "pid": Int(process.processIdentifier)])
        var configure: [String: Any] = [
            "type": "configure", "api_key": "proof-key", "model": "claude-opus-5-5",
            "system": "Reelcut A0 spike.", "tools": tools,
            "settings": ["auto_compact_tokens": NSNull(), "clear_tool_results": false],
        ]
        if let base = ProcessInfo.processInfo.environment["RC_ASSISTANT_BASE_URL"],
            !base.isEmpty
        {
            configure["api_base"] = base
        }
        write(configure)
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) {
            guard !finished else { return }
            finished = true
            log(["event": "timeout", "waiting_for": "turn_finished"])
            if process.isRunning { process.terminate() }
        }
    }

    /// Splits the helper's stdout into lines on the handler thread; each
    /// line is handled on main.
    private static func consume(_ data: Data) {
        if data.isEmpty { return }
        lineBuffer.append(data)
        while let newline = lineBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = Data(lineBuffer[lineBuffer.startIndex..<newline])
            lineBuffer.removeSubrange(lineBuffer.startIndex...newline)
            let object = try? JSONSerialization.jsonObject(with: line)
            let message: Any = object ?? (String(data: line, encoding: .utf8) ?? "")
            log(["event": "from_helper", "message": message])
            if let event = object as? [String: Any] {
                DispatchQueue.main.async { handle(event) }
            }
        }
    }

    private static func handle(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "ready":
            write(["type": "send", "text": "A0: add the spike marker."])
        case "tool_request":
            runTool(event)
        case "turn_finished":
            guard !finished else { return }
            finished = true
            log(["event": "done"])
            let input = toHelper?.fileHandleForWriting
            writeQueue.async { try? input?.close() }
        default:
            break
        }
    }

    /// Rasterize's `runTool`: execute, then splice the result JSON in
    /// verbatim. On main, or on a global queue for the `offMainTools`.
    private static func runTool(_ request: [String: Any]) {
        guard let callID = request["call_id"] as? String,
            let name = request["name"] as? String
        else { return }
        let arguments = request["arguments_json"] as? String ?? "{}"
        let onMain = !AgentServer.offMainTools.contains(name)
        let run = {
            let result = AgentServer.shared.execute(tool: name, argumentsJSON: arguments)
            log(["event": "ran", "tool": name, "main": onMain, "result_bytes": result.utf8.count])
            guard let idJSON = try? JSONSerialization.data(withJSONObject: [callID]),
                let idArray = String(data: idJSON, encoding: .utf8)
            else { return }
            let quotedID = idArray.dropFirst().dropLast()
            writeLine(#"{"type":"tool_result","call_id":\#(quotedID),"result":\#(result)}"#)
        }
        if onMain {
            run()
        } else {
            DispatchQueue.global(qos: .userInitiated).async(execute: run)
        }
    }

    private static func write(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
            let line = String(data: data, encoding: .utf8)
        else { return }
        writeLine(line)
    }

    private static func writeLine(_ line: String) {
        guard let handle = toHelper?.fileHandleForWriting else { return }
        let data = Data((line + "\n").utf8)
        writeQueue.async { try? handle.write(contentsOf: data) }
    }

    private static func log(_ entry: [String: Any]) {
        guard let url = logURL else { return }
        var stamped = entry
        stamped["t"] = Date().timeIntervalSince1970
        guard let data = try? JSONSerialization.data(withJSONObject: stamped) else { return }
        logQueue.async {
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data + Data("\n".utf8))
            try? handle.close()
        }
    }
}
