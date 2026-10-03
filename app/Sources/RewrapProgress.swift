import Foundation

/// One WebM or Matroska copy's progress and its Cancel (spec §11 #228-P):
/// the copying thread reports bytes, the window polls them on main, and a
/// Cancel from main is read by the copy between samples. All state is
/// behind one lock, so any thread may call any member (hence the
/// unchecked `Sendable`). Await-free, no AppKit.
final class RewrapProgress: @unchecked Sendable {
    let source: URL

    private let lock = NSLock()
    private var cancelled = false
    private var finished = false
    private var total: UInt64 = 0
    private var copied: UInt64 = 0
    private var begun = false
    private var lateAdds = 0
    private var cancelFraction: Double?

    init(source: URL) {
        self.source = source
    }

    var isCancelled: Bool { locked { cancelled } }
    var isFinished: Bool { locked { finished } }
    /// 0 until `begin`.
    var totalBytes: UInt64 { locked { total } }
    var copiedBytes: UInt64 { locked { copied } }

    /// nil until `begin`; then copied over total, clamped to 0…1 (1 for an
    /// empty total).
    var fraction: Double? {
        locked {
            guard begun else { return nil }
            guard total > 0 else { return 1 }
            return min(max(Double(copied) / Double(total), 0), 1)
        }
    }

    /// The probe's seam: `add(bytes:)` cancels once the fraction reaches
    /// it. The app sets none.
    var cancelAt: Double? {
        get { locked { cancelFraction } }
        set { locked { cancelFraction = newValue } }
    }

    /// `add(bytes:)` calls made while already cancelled; the call that trips
    /// `cancelAt` is not one of them.
    var addsAfterCancel: Int { locked { lateAdds } }

    func cancel() { locked { cancelled = true } }

    /// The copy's size: the described video and audio bytes, just before
    /// the write begins.
    func begin(totalBytes: UInt64) {
        locked {
            total = totalBytes
            copied = 0
            begun = true
        }
    }

    /// One appended sample's bytes.
    func add(bytes: UInt64) {
        locked {
            if cancelled { lateAdds += 1 }
            copied &+= bytes
            if let at = cancelFraction, begun, !cancelled {
                let reached = total == 0 ? 1 : Double(copied) / Double(total)
                if reached >= at { cancelled = true }
            }
        }
    }

    /// The copy has ended, however it ended; the window closes on it.
    func finish() { locked { finished = true } }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

/// Called once, on the copying thread, when a copy really starts — never
/// for a copy already on disk. The click doors pass
/// `RewrapProgressWindowController.watch`; a tool call passes none.
typealias RewrapWatch = (RewrapProgress) -> Void
