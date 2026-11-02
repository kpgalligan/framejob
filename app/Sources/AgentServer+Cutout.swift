import Foundation

/// `analyze_cutout` (road map creator-jobs CO3, spec §11 CO-31): the mirror of the Background
/// section's Status and Analyze Now. Off the main thread: one main hop names the clips, refuses
/// in CO-31 (b)'s order and runs `analyzeMasksNow()`; `CutoutWants.queue.sync {}` lets that
/// want and its retry run before the first read; then the statuses are read every 0.25 s on
/// main until every clip settles, `wait` passes or the assistant's Stop — never a timeout
/// refusal. The centroid is read here, off main, from the values captured on it.
extension AgentServer {

    static let cutoutPollInterval: TimeInterval = 0.25
    static let cutoutWaitLimit: Double = 60

    func analyzeCutout(_ a: [String: Any]) throws -> String {
        let stop = AgentLane.shared.callCancel  // the assistant's Stop (spec §11 AI-16)
        guard !Thread.isMainThread else {
            throw ToolError(
                message: "analyze_cutout must run on the server thread — its name is missing "
                    + "from AgentServer.creatorOffMainTools.")
        }
        var wait = 0.0
        if let raw = a["wait"], !(raw is NSNull) {
            guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                number.doubleValue.isFinite, number.doubleValue >= 0,
                number.doubleValue <= Self.cutoutWaitLimit
            else { throw ToolError(message: "wait must be from 0 to 60 seconds.") }
            wait = number.doubleValue
        }
        let (document, clips) = try onMain { () throws -> (ProjectDocument, [UInt32]) in
            let document = try target(a)
            let snapshot = document.editedProject.snapshot
            let cutOut = { (id: UInt32) in snapshot.clip(id)?.video?.cutout != nil }
            let clips: [UInt32]
            if let named = try optionalClipsArg(a, "clips", document) {
                if let bare = named.first(where: { !cutOut($0) }) {
                    throw ToolError(
                        message: "Clip \(bare) has no Remove Background; set_video "
                            + "{cutout: {}} turns it on.")
                }
                clips = named
            } else {
                clips = snapshot.clips.filter { $0.video?.cutout != nil }
                    .sorted { ($0.start, $0.id) < ($1.start, $1.id) }.map(\.id)
                guard !clips.isEmpty else {
                    throw ToolError(
                        message: "No clip in the open scope has Remove Background on; "
                            + "set_video {cutout: {}} turns it on.")
                }
            }
            document.analyzeMasksNow()
            return (document, clips)
        }
        CutoutWants.queue.sync {}
        let deadline = Date().addingTimeInterval(wait)
        var read: (details: [CutoutStatus.Detail], qualities: [String], project: [String: Any])
        while true {
            read = onMain {
                let snapshot = document.editedProject.snapshot
                let details = clips.map { CutoutStatus.detail(of: $0, in: document) }
                let qualities = clips.map {
                    snapshot.clip($0)?.video?.cutout?.quality.rawValue
                        ?? CutoutQuality.standard.rawValue
                }
                return (details, qualities, summary(document))
            }
            if read.details.allSatisfy({ $0.status.state.isSettled }) || Date() >= deadline
                || stop?.isCancelled == true
            {
                break
            }
            Thread.sleep(forTimeInterval: Self.cutoutPollInterval)
        }
        let rows = zip(read.details, read.qualities).map { Self.cutoutRow($0, quality: $1) }
        return try jsonResult(["ok": true, "clips": rows, "project": read.project])
    }

    /// One clip's answer (CO-31 (c)), its centroid read from the pack here.
    private static func cutoutRow(_ detail: CutoutStatus.Detail, quality: String) -> [String: Any] {
        let status = detail.status
        let state: String
        var progress = status.frames > 0 ? Double(status.covered) / Double(status.frames) : 0
        switch status.state {
        case .off: state = "off"
        case .noPicture: state = "no_picture"
        case .analyzing(let value):
            state = "analyzing"
            progress = value
        case .ready: state = "ready"
        case .noPerson: state = "no_person"
        case .failed: state = "failed"
        }
        var centroid: Any = NSNull()
        if status.state == .ready, status.subjectFound, let url = detail.pack,
            let media = detail.media, let pack = try? MaskPack(contentsOf: url),
            let point = try? CutoutStatus.centroid(
                pack: pack, need: detail.need, coverage: detail.coverage,
                mediaWidth: media.width, mediaHeight: media.height)
        {
            centroid = ["x": Double(point.x), "y": Double(point.y)]
        }
        var row: [String: Any] = [
            "clip": Int(status.clip), "media": status.media.map { Int($0) } ?? NSNull(),
            "state": state, "progress": (progress * 1000).rounded() / 1000, "quality": quality,
            "frames": status.frames, "covered": status.covered,
            "ready": status.frames > 0 && status.covered == status.frames,
            "subject_found": status.subjectFound, "centroid": centroid,
        ]
        if let error = status.error { row["error"] = error }
        return row
    }
}
