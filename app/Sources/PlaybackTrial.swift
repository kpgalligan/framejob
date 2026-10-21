#if FRAMEJOB_DEV_TOOLS
import CoreVideo
import CryptoKit
import Foundation

/// `play_preview`'s record of what the compositor served on one document key
/// while a trial ran (issue #127, spec §11 G-36): each finished frame's
/// composition time and its compose time, and — only while the trial asked —
/// the SHA-256 of the destination buffer's pixels. A dev tool's instrument,
/// absent from Distribution builds.
///
/// `Compositor.serve` calls `served` after a successful finish, on its render
/// queue; with no trial for the key that is one lock and one lookup. A digest
/// is taken outside the lock, over each row's first `width × 8` bytes
/// (`Compositor.outputPixelFormat`, 64RGBAHalf) with the buffer locked
/// read-only, so a row's padding never enters it.
final class PlaybackTrials: @unchecked Sendable {
    static let shared = PlaybackTrials()

    struct Served: Equatable {
        let ticks: Ticks
        let seconds: Double
        let digest: String?
    }

    /// One trial's record. Guarded by `lock`.
    private final class Trial {
        let digests: Bool
        var served: [Served] = []

        init(digests: Bool) {
            self.digests = digests
        }
    }

    private let lock = NSLock()
    private var trials: [Int: Trial] = [:]

    private init() {}

    /// Starts recording `key`, replacing any trial already running there.
    func begin(_ key: Int, digests: Bool) {
        lock.lock()
        trials[key] = Trial(digests: digests)
        lock.unlock()
    }

    /// One frame the compositor finished on `key`. Any thread.
    func served(_ key: Int, ticks: Ticks, seconds: Double, buffer: CVPixelBuffer) {
        lock.lock()
        let trial = trials[key]
        lock.unlock()
        guard let trial else { return }
        let digest = trial.digests ? Self.digest(buffer) : nil
        lock.lock()
        trial.served.append(Served(ticks: ticks, seconds: seconds, digest: digest))
        lock.unlock()
    }

    /// Ends `key`'s trial and answers what it recorded, in serving order.
    func end(_ key: Int) -> [Served] {
        lock.lock()
        defer { lock.unlock() }
        return trials.removeValue(forKey: key)?.served ?? []
    }

    /// The SHA-256 of `buffer`'s rows, each row's first `width × 8` bytes.
    private static func digest(_ buffer: CVPixelBuffer) -> String? {
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else {
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let rowBytes = width * 8
        guard rowBytes <= stride else { return nil }
        var hasher = SHA256()
        for row in 0..<height {
            hasher.update(bufferPointer: UnsafeRawBufferPointer(
                start: base.advanced(by: row * stride), count: rowBytes))
        }
        return GraphicStore.hex(hasher.finalize())
    }
}
#endif
