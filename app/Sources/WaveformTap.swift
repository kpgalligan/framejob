import CoreVideo
import Foundation
import Metal

/// Where the scopes panel's frames come from (spec §11 GR-5, GR-10): the
/// compositor offers every finished preview frame (`Compositor.serve`, one
/// line after `finish(withComposedVideoFrame:)`), and a window whose panel is
/// shown has a tap on its document's `RecipeSource` key, attached with the
/// set of scopes its slots show. A key with no tap — every export's, every
/// offline frame's, and a document's with the panel hidden — costs one locked
/// dictionary read, so the passes run only while the panel is shown.
///
/// **One command buffer per offered frame** holds every shown kind's pass
/// (`WaveformAnalyzer.encode(_:frame:into:)`), and one delivery hands the
/// panel every kind's trace from that one frame.
///
/// **Latest wins.** At most one pass is in flight per key, and ONE pending
/// frame waits beside it: a frame offered while a pass is in flight replaces
/// whatever was pending, and a pass that completes with the slot full starts
/// that frame's pass. So the last frame composed after an edit is always the
/// one the panel ends on — which matters when the player is parked at the end
/// and `Playback.refreshPausedFrame` composes a single frame per edit.
///
/// **Its own command queue and texture cache**, so the pass never joins the
/// compositor's serial render queue and the frame is handed to AVFoundation
/// without waiting for it. The destination is read-only here; holding it
/// keeps its pool from recycling it until the pass is done.
///
/// **The main hop is a documented seam** (app/CLAUDE.md's hygiene list): the
/// passes complete on Metal's completion thread and the traces reach the
/// panel through one `DispatchQueue.main.async`, dropped there unless the
/// SAME tap is still attached.
final class WaveformTaps {
    static let shared = WaveformTaps(analyzer: WaveformAnalyzer.shared)

    private struct Tap {
        /// Which attach this is, so a pass begun for an earlier one is not
        /// delivered to a later one.
        let token: Int
        /// The scopes to measure, never empty.
        let kinds: Set<ScopeKind>
        let onTraces: ([ScopeKind: ScopeTrace]) -> Void
        var inFlight = false
        var pending: CVPixelBuffer?
    }

    private let analyzer: WaveformAnalyzer?
    private let queue: MTLCommandQueue?
    private let textureCache: CVMetalTextureCache?
    private let lock = NSLock()
    /// The texture cache's own lock: two windows' passes may wrap at once.
    private let cacheLock = NSLock()
    private var taps: [Int: Tap] = [:]
    private var nextToken = 1

    init(analyzer: WaveformAnalyzer?) {
        self.analyzer = analyzer
        queue = analyzer?.device.makeCommandQueue()
        var cache: CVMetalTextureCache?
        if let device = analyzer?.device {
            CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        }
        textureCache = cache
    }

    /// Starts measuring `kinds` of `key`'s frames; `onTraces` runs on the
    /// main thread with every kind's trace of one frame. Attaching an attached
    /// key replaces its kinds and its callback (a pass begun for the old
    /// attach is dropped when it completes); an empty set detaches it.
    func attach(
        key: Int, kinds: Set<ScopeKind>,
        onTraces: @escaping ([ScopeKind: ScopeTrace]) -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard !kinds.isEmpty else {
            taps.removeValue(forKey: key)
            return
        }
        taps[key] = Tap(token: nextToken, kinds: kinds, onTraces: onTraces)
        nextToken += 1
    }

    /// The kinds `key` is attached with, or nil when it has no tap.
    func attachedKinds(key: Int) -> Set<ScopeKind>? {
        lock.lock()
        defer { lock.unlock() }
        return taps[key]?.kinds
    }

    /// Stops it, emptying the pending slot; a pass in flight is dropped when
    /// it completes.
    func detach(key: Int) {
        lock.lock()
        defer { lock.unlock() }
        taps.removeValue(forKey: key)
    }

    /// A finished frame for `key`, from the compositor's render queue.
    func offer(_ frame: CVPixelBuffer, key: Int) {
        lock.lock()
        guard analyzer != nil, var tap = taps[key] else {
            lock.unlock()
            return
        }
        if tap.inFlight {
            tap.pending = frame
            taps[key] = tap
            lock.unlock()
            return
        }
        tap.inFlight = true
        taps[key] = tap
        lock.unlock()
        start(frame, key: key, token: tap.token, kinds: tap.kinds)
    }

    private func start(_ frame: CVPixelBuffer, key: Int, token: Int, kinds: Set<ScopeKind>) {
        let width = CVPixelBufferGetWidth(frame)
        let height = CVPixelBufferGetHeight(frame)
        guard let analyzer, let wrapper = wrap(frame),
            let texture = CVMetalTextureGetTexture(wrapper),
            let buffer = queue?.makeCommandBuffer(),
            let counts = analyzer.encode(kinds, frame: texture, into: buffer)
        else {
            finished(key: key, token: token, traces: nil)
            return
        }
        buffer.addCompletedHandler { [weak self] done in
            // The frame and its wrapper live until the GPU is done reading them.
            withExtendedLifetime((wrapper, frame)) {}
            var traces: [ScopeKind: ScopeTrace]?
            if done.status == .completed {
                var read: [ScopeKind: ScopeTrace] = [:]
                for kind in ScopeKind.allCases {
                    guard let buffer = counts[kind] else { continue }
                    read[kind] = analyzer.trace(kind, of: buffer, width: width, height: height)
                }
                traces = read
            }
            self?.finished(key: key, token: token, traces: traces)
        }
        buffer.commit()
    }

    /// One pass over: the pending frame starts next, and the traces hop to
    /// main.
    private func finished(key: Int, token: Int, traces: [ScopeKind: ScopeTrace]?) {
        lock.lock()
        guard var tap = taps[key], tap.token == token else {
            lock.unlock()
            return
        }
        let next = tap.pending
        tap.pending = nil
        tap.inFlight = next != nil
        taps[key] = tap
        lock.unlock()
        if let next { start(next, key: key, token: token, kinds: tap.kinds) }
        guard let traces else { return }
        DispatchQueue.main.async { [weak self] in self?.deliver(traces, key: key, token: token) }
    }

    private func deliver(_ traces: [ScopeKind: ScopeTrace], key: Int, token: Int) {
        lock.lock()
        let onTraces = taps[key].flatMap { $0.token == token ? $0.onTraces : nil }
        lock.unlock()
        onTraces?(traces)
    }

    /// The frame as a Metal texture over the same IOSurface.
    private func wrap(_ frame: CVPixelBuffer) -> CVMetalTexture? {
        let format: MTLPixelFormat
        switch CVPixelBufferGetPixelFormatType(frame) {
        case kCVPixelFormatType_64RGBAHalf: format = .rgba16Float
        case kCVPixelFormatType_32BGRA: format = .bgra8Unorm
        default: return nil
        }
        guard let textureCache else { return nil }
        cacheLock.lock()
        defer { cacheLock.unlock() }
        CVMetalTextureCacheFlush(textureCache, 0)
        var wrapper: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, frame, nil, format,
            CVPixelBufferGetWidth(frame), CVPixelBufferGetHeight(frame), 0, &wrapper)
        return status == kCVReturnSuccess ? wrapper : nil
    }
}
