import Foundation

// MARK: - export_status and cancel_export

/// The agent's half of the Export Queue (spec §11 #326): `export` enqueues a
/// job in `ExportQueueController.shared` and answers its id at once, and the
/// two tools here follow it. `export_status` mirrors Window ▸ Export Queue's
/// row for that job (`ExportQueueWindowController`) — its state, its progress
/// bar, its phase and its closing sentence — and `cancel_export` mirrors the
/// row's Cancel button, which calls the same `ExportQueueController.cancel`.
///
/// **Only ids `export` returned are reachable.** A person's own queued job has
/// no record here and is answered as unknown: the mirror follows what the
/// agent started, not the queue as a whole.
///
/// **A record outlives its row.** The queue drops a finished job on Remove or
/// Clear Finished, and an agent that asks after that must still hear how it
/// ended, so `AgentExports` copies each tracked job's state on every queue
/// change — synchronously, on main, inside the queue's own post — and stamps
/// the finish (its time and the file's size) on its first terminal sight.
/// Records last for the launch and hold no project handle or graphic set.
extension AgentServer {

    /// `export_status {export_id}` — the row of Window ▸ Export Queue for a job
    /// `export` started, read now; it never waits.
    func exportStatus(_ a: [String: Any]) throws -> String {
        let id = try exportIDArg(a)
        guard let status = AgentExports.shared.status(id) else {
            throw Self.unknownExport(id)
        }
        return try jsonResult(status)
    }

    /// `cancel_export {export_id}` — the Export Queue row's Cancel. A queued
    /// or running job is cancelled through the queue (a running one answers
    /// through the writer, so it may still read `running` here); a finished
    /// one is left alone and answered as it is.
    func cancelExport(_ a: [String: Any]) throws -> String {
        let id = try exportIDArg(a)
        guard AgentExports.shared.status(id) != nil else {
            throw Self.unknownExport(id)
        }
        if let job = ExportQueueController.shared.job(id), !job.state.isFinished {
            ExportQueueController.shared.cancel(id)
        }
        guard let status = AgentExports.shared.status(id) else {
            throw Self.unknownExport(id)
        }
        return try jsonResult(status)
    }

    /// The word a status answer spells a queue state with.
    static func exportStatusWord(_ state: ExportQueueController.State) -> String {
        switch state {
        case .waiting: return "queued"
        case .running: return "running"
        case .completed: return "done"
        case .failed: return "failed"
        case .cancelled: return "cancelled"
        }
    }

    /// `export_id`, required and whole. An id below 1 is no id `export`
    /// returned, so it is refused as an unknown one rather than converted.
    private func exportIDArg(_ a: [String: Any]) throws -> UInt64 {
        guard let raw = try intArg(a, "export_id") else {
            throw ToolError(message: "Missing required argument: export_id")
        }
        guard raw >= 1 else {
            throw ToolError(
                message: "No export this launch has export_id \(raw) — ids come from export "
                    + "and last until Frame Job quits.")
        }
        return UInt64(raw)
    }

    private static func unknownExport(_ id: UInt64) -> ToolError {
        ToolError(
            message: "No export this launch has export_id \(id) — ids come from export and "
                + "last until Frame Job quits.")
    }
}

/// What `AgentExports` keeps of one tracked job: the queue row's fields as
/// last seen, plus what the `done` answer needs that the job does not carry.
private struct AgentExportRecord {
    let settings: ExportSettings
    let burnInTimecode: Bool
    /// `systemUptime` at the `export` handler's first line.
    let started: TimeInterval
    var state: ExportQueueController.State
    var progress: Double
    var phase: String?
    var message: String?
    var destination: URL
    var loudness: ExportLoudness?
    var graphicWarnings: [ExportGraphicWarning]
    /// `systemUptime` at the first terminal sight, nil until then.
    var finished: TimeInterval?
    /// The file's size as read at that finish.
    var bytes: Int = 0

    mutating func copy(_ job: ExportQueueController.Job) {
        state = job.state
        progress = job.progress
        phase = job.phase
        message = job.message
        destination = job.destination
        loudness = job.loudness
        graphicWarnings = job.graphicWarnings
        guard job.state.isFinished, finished == nil else { return }
        finished = ProcessInfo.processInfo.systemUptime
        bytes =
            (try? FileManager.default.attributesOfItem(atPath: job.destination.path)[.size])
            .flatMap { ($0 as? NSNumber)?.intValue } ?? 0
    }
}

/// The records of every export the agent started this launch, by the queue's
/// job id. Main thread only, like the queue it reads.
final class AgentExports {
    static let shared = AgentExports()

    private var records: [UInt64: AgentExportRecord] = [:]
    private var observer: NSObjectProtocol?

    private init() {
        // `queue: nil` runs the block synchronously inside the queue's own
        // post, so a terminal state is copied before any Remove can drop it.
        observer = NotificationCenter.default.addObserver(
            forName: ExportQueueController.didChangeNotification,
            object: ExportQueueController.shared, queue: nil
        ) { [weak self] _ in self?.refresh() }
    }

    /// Starts following a job `export` just enqueued. Reads it AT ONCE: an
    /// early refusal finishes inside `enqueue`, before this is called, so its
    /// terminal post has already gone by.
    func track(
        _ id: UInt64, settings: ExportSettings, burnInTimecode: Bool, started: TimeInterval
    ) {
        // Never nil: `enqueue` appends the job before it returns, an early
        // refusal only finishes it in place, and the only removals (`remove`,
        // `clearFinished`) are the queue window's button actions, which cannot
        // run inside the one main-thread block that enqueues and calls this.
        guard let job = ExportQueueController.shared.job(id) else { return }
        var record = AgentExportRecord(
            settings: settings, burnInTimecode: burnInTimecode, started: started,
            state: job.state, progress: job.progress, phase: job.phase, message: job.message,
            destination: job.destination, loudness: job.loudness,
            graphicWarnings: job.graphicWarnings)
        record.copy(job)
        records[id] = record
    }

    /// The `export_status` answer for `id`, or nil for an id `export` never
    /// returned this launch.
    func status(_ id: UInt64) -> [String: Any]? {
        guard let record = records[id] else { return nil }
        let end = record.finished ?? ProcessInfo.processInfo.systemUptime
        var answer: [String: Any] = [:]
        switch record.state {
        case .running:
            answer["progress"] = record.progress
            if let phase = record.phase { answer["phase"] = phase }
        case .completed:
            answer = AgentServer.exportResult(
                settings: record.settings, burnInTimecode: record.burnInTimecode,
                path: record.destination.path, bytes: record.bytes, loudness: record.loudness,
                graphicWarnings: record.graphicWarnings)
        case .failed, .cancelled:
            answer["reason"] = record.message ?? ""
        case .waiting:
            break
        }
        answer["export_id"] = id
        answer["status"] = AgentServer.exportStatusWord(record.state)
        answer["path"] = record.destination.path
        answer["elapsed"] = ((end - record.started) * 1000).rounded() / 1000
        return answer
    }

    /// Copies every unfinished tracked job from the queue.
    private func refresh() {
        let queue = ExportQueueController.shared
        for (id, record) in records where record.finished == nil {
            guard let job = queue.job(id) else { continue }
            var updated = record
            updated.copy(job)
            records[id] = updated
        }
    }
}
