import Foundation

/// `TranscriptTabSource`'s status line, moved out whole (a pure move, fixes
/// batch c2) so the source has room under the ~600-line cap: `Status`,
/// `canStop`, and the status refresh the poll and every load call.
extension TranscriptTabSource {
    enum Status: Equatable {
        case idle, loading, reading(name: String, fraction: Double, index: Int, of: Int), noModel
        case failed([String])
        case stopped(remaining: Int)
    }

    /// Whether Stop applies: the tab's waiter reads on this Mac.
    var canStop: Bool {
        if case .reading = status { return true }
        return false
    }

    // MARK: - Status

    func polled() {
        let before = status
        refreshStatus()
        if status != before { onChange() }
    }

    func refreshStatus() {
        lock.lock()
        let running = waiting.first
        let remaining = pending.count
        let total = pendingTotal
        lock.unlock()
        let unread = stopped ? needed.filter { words[$0] == nil && missItems[$0] != nil }.count : 0
        if let running {
            let progress = fill.progress()
            let fraction = progress?.media == running.media ? progress?.fraction ?? 0 : 0
            let of = max(total, 1)
            status = .reading(
                name: running.name, fraction: fraction, index: min(max(total - remaining, 1), of), of: of)
        } else if unread > 0 {
            status = .stopped(remaining: unread)
        } else if !failures.isEmpty {
            status = .failed(failures.keys.sorted().compactMap { failures[$0] })
        } else if noModel {
            status = .noModel
        } else if !loading.isEmpty {
            status = .loading
        } else {
            status = .idle
        }
    }

    /// The fill's running media and its fraction, for `transcript_view`.
    var fillProgress: (media: UInt32, fraction: Double)? { fill.progress() }
}
