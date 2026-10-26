import Foundation

extension MediaImporter {
    /// The lane a media cache pass's three synchronous audio decodes run on —
    /// `writePeaks`, `writeSyncFeatures` and `writeSpeech`, each reached
    /// through `MediaImporter.onCacheLane` (spec §11 #367). At most `width`
    /// bodies run at once, in the order they were submitted, on the lane's
    /// own concurrent `.utility` queue and never on the Swift cooperative
    /// pool.
    ///
    /// Why it exists: twenty imports of long files that nobody waited for put
    /// every cache pass's `AVAssetReader` to work at once, each on a
    /// cooperative-pool thread blocked in `copyNextSampleBuffer`; with the
    /// pool full, every reader in the process — the ramp-audio render's on
    /// its own queue included — stopped reading at 0 % CPU (#367). The lane
    /// has two guards, each enough alone and kept together: its decodes run
    /// off the pool (no synchronous `AVAssetReader` read runs on it), and
    /// only two run at once, which also bounds what cache passes take from
    /// playback, export and the ramp renderer. A queued body waits in
    /// `pending` and holds no thread.
    ///
    /// `submit` never blocks its caller. A body must not wait on the lane
    /// itself (a body that submitted and waited would hold a slot while it
    /// waited); the writers end in `CacheLedger.publish`, which does not.
    /// Thumbnails are not on the lane (spec §11 #367).
    final class CacheLane: @unchecked Sendable {
        /// Two at a time: a concurrency bound on audio decodes, not a memory
        /// limit (spec §11 #367).
        static let width = 2
        static let label = "com.kgalligan.framejob.cache-lane"
        static let shared = CacheLane(width: width)

        private let width: Int
        private let queue: DispatchQueue
        private let lock = NSLock()
        /// Bodies submitted and not yet started, oldest first.
        private var pending: [() -> Void] = []
        /// Bodies started and not yet finished; never above `width`.
        private var running = 0

        init(width: Int) {
            self.width = width
            queue = DispatchQueue(label: Self.label, qos: .utility, attributes: .concurrent)
        }

        /// FIFO; never blocks the caller; runs `body` on the lane's own
        /// concurrent `.utility` DispatchQueue (labelled `label`) once fewer
        /// than `width` bodies run.
        func submit(_ body: @escaping () -> Void) {
            lock.lock()
            pending.append(body)
            let next = takeLocked()
            lock.unlock()
            if let next { start(next) }
        }

        /// The oldest pending body, with its slot taken, when a slot is free.
        private func takeLocked() -> (() -> Void)? {
            guard running < width, !pending.isEmpty else { return nil }
            running += 1
            return pending.removeFirst()
        }

        /// Runs `body` on the queue; when it returns, its slot goes to the
        /// oldest pending body.
        private func start(_ body: @escaping () -> Void) {
            let run = { [self] in
                body()
                lock.lock()
                running -= 1
                let next = takeLocked()
                lock.unlock()
                if let next { start(next) }
            }
            queue.async(execute: run)
        }
    }
}
