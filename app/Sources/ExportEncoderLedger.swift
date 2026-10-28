import Foundation

/// The app-wide account of the bundled-encoder exports running now (spec §11 CX-18): the
/// Export Queue's job and every Export… progress sheet's, each booked from just before its
/// exporter starts to its finish, at the resident peak `ExportEncoderCosts.memory` measured
/// for its key and size.
///
/// **Why a ledger and not a pool size.** The queue runs one job at a time (#326, road map
/// 2's 7e) and stays that way; what can run beside its job is an Export… sheet, which a
/// person started and which is never held (CX-18 (6)). So the question a queued AV1 or VP9
/// job asks is not "how many jobs" but "does the memory the others hold, with mine, fit", and
/// the answer has to see the sheets too — which is why the account is one shared object
/// both writers book into, rather than state inside `ExportQueueController`.
///
/// **The budget is a quarter of physical memory**, G-37's share for graphic rasters, so an
/// export's two large consumers stay within half the Mac together. A job is admitted when
/// nothing is booked — one export always runs, however large — or when the booked costs and
/// its own fit.
///
/// Main thread only, like the queue and the sheets that book into it, and AppKit-free so a
/// probe compiles it headless (`tools/proof/encoder_limit_probe.swift`).
final class ExportEncoderLedger {
    /// The app's one ledger. The queue observes it and the sheets book into it.
    static let shared = ExportEncoderLedger()

    /// Posted after a booking is added or removed, with the ledger as the `object`. The
    /// queue re-runs `start()` on it, so a held job launches when a booking ends.
    static let didChangeNotification = Notification.Name(
        "com.kgalligan.framejob.exportEncoderLedgerDidChange")

    /// The Mac's memory the budget is a share of — `ProcessInfo`'s, which a probe sets to
    /// ask what a Mac of another size would admit.
    var physicalMemory: UInt64

    private var entries: [(token: UInt64, cost: UInt64)] = []
    private var nextToken: UInt64 = 1

    init(physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) {
        self.physicalMemory = physicalMemory
    }

    /// What bundled-encoder exports may hold together, in bytes.
    var budget: UInt64 { Self.budget(physicalMemory: physicalMemory) }

    /// Each running booking's cost, in booking order.
    var runningCosts: [UInt64] { entries.map(\.cost) }

    // MARK: - The rule

    /// A quarter of physical memory (CX-18 (3)).
    static func budget(physicalMemory: UInt64) -> UInt64 { physicalMemory / 4 }

    /// Whether a job costing `cost` may start beside `running`: always when nothing runs,
    /// else when the sum fits `budget` (CX-18 (5)).
    static func admits(cost: UInt64, running: [UInt64], budget: UInt64) -> Bool {
        guard !running.isEmpty else { return true }
        let (inUse, over) = running.reduce((UInt64(0), false)) { sum, next in
            let added = sum.0.addingReportingOverflow(next)
            return (added.partialValue, sum.1 || added.overflow)
        }
        let total = inUse.addingReportingOverflow(cost)
        return !over && !total.overflow && total.partialValue <= budget
    }

    /// The held job's sentence: what runs, what the Mac allows, what this one needs.
    static func waitingSentence(cost: UInt64, running: [UInt64], budget: UInt64) -> String {
        let inUse = running.reduce(UInt64(0)) { $0 &+ $1 }
        return "Waiting for memory: AV1 and VP9 exports running now hold about "
            + "\(gigabytes(inUse)) of the \(gigabytes(budget)) this Mac allows them, and this "
            + "one needs about \(gigabytes(cost))."
    }

    private static func gigabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }

    // MARK: - Asking

    /// Whether `settings` may start now, leaving out the booking `token` (the queue's own
    /// running job, which a waiting job is behind anyway). True for an AVFoundation row.
    func admits(_ settings: ExportSettings, ignoring token: UInt64? = nil) -> Bool {
        guard settings.writer != nil else { return true }
        return Self.admits(
            cost: ExportEncoderCosts.memoryBytes(for: settings, budget: budget),
            running: costs(ignoring: token), budget: budget)
    }

    /// The held sentence for `settings`, or nil when it is admitted.
    func waitingSentence(for settings: ExportSettings, ignoring token: UInt64? = nil) -> String? {
        guard !admits(settings, ignoring: token) else { return nil }
        return Self.waitingSentence(
            cost: ExportEncoderCosts.memoryBytes(for: settings, budget: budget),
            running: costs(ignoring: token), budget: budget)
    }

    private func costs(ignoring token: UInt64?) -> [UInt64] {
        entries.filter { $0.token != token }.map(\.cost)
    }

    // MARK: - Booking

    /// Books an export about to start and answers its token, or nil — booking nothing —
    /// for an AVFoundation row. Called BEFORE `Exporter.export`, whose early refusals finish
    /// synchronously inside it.
    func begin(_ settings: ExportSettings) -> UInt64? {
        guard settings.writer != nil else { return nil }
        let token = nextToken
        nextToken += 1
        entries.append(
            (token, ExportEncoderCosts.memoryBytes(for: settings, budget: budget)))
        post()
        return token
    }

    /// Ends a booking. A nil or unknown token is a no-op; a removal posts, and the queue's
    /// observer may launch its next job — and book it — inside this call, which is why a
    /// caller clears its own token BEFORE calling this.
    func end(_ token: UInt64?) {
        guard let token, let index = entries.firstIndex(where: { $0.token == token }) else {
            return
        }
        entries.remove(at: index)
        post()
    }

    private func post() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
