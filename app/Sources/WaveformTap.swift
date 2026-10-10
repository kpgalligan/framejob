import CoreVideo
import Foundation
import Metal

/// Where the waveform panel's frames come from (spec §11 GR-5): the
/// compositor offers every finished preview frame (`Compositor.serve`, one
/// line after `finish(withComposedVideoFrame:)`), and a window whose panel is
/// shown has a tap on its document's `RecipeSource` key. A key with no tap —
/// every export's, every offline frame's, and a document's with the panel
/// hidden — costs one locked dictionary read, so the pass runs only while
/// the panel is shown.
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
/// pass completes on Metal's completion thread and the trace reaches the
/// panel through one `DispatchQueue.main.async`, dropped there unless the
/// SAME tap is still attached.
final class WaveformTaps {
    static let shared = WaveformTaps(analyzer: WaveformAnalyzer.shared)

    private struct Tap {
        /// Which attach this is, so a pass begun for an earlier one is not
        /// delivered to a later one.
        let token: Int
        let onTrace: (WaveformTrace) -> Void
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

    /// Starts analysing `key`'s frames; `onTrace` runs on the main thread.
    func attach(key: Int, onTrace: @escaping (WaveformTrace) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        taps[key] = Tap(token: nextToken, onTrace: onTrace)
        nextToken += 1
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
        start(frame, key: key, token: tap.token)
    }

    private func start(_ frame: CVPixelBuffer, key: Int, token: Int) {
        let width = CVPixelBufferGetWidth(frame)
        let height = CVPixelBufferGetHeight(frame)
        guard let analyzer, let wrapper = wrap(frame),
            let texture = CVMetalTextureGetTexture(wrapper),
            let buffer = queue?.makeCommandBuffer(),
            let counts = analyzer.encode(texture, into: buffer)
        else {
            finished(key: key, token: token, trace: nil)
            return
        }
        buffer.addCompletedHandler { [weak self] done in
            // The frame and its wrapper live until the GPU is done reading them.
            withExtendedLifetime((wrapper, frame)) {}
            let trace = done.status == .completed
                ? analyzer.trace(of: counts, width: width, height: height) : nil
            self?.finished(key: key, token: token, trace: trace)
        }
        buffer.commit()
    }

    /// One pass over: the pending frame starts next, and the trace hops to
    /// main.
    private func finished(key: Int, token: Int, trace: WaveformTrace?) {
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
        if let next { start(next, key: key, token: token) }
        guard let trace else { return }
        DispatchQueue.main.async { [weak self] in self?.deliver(trace, key: key, token: token) }
    }

    private func deliver(_ trace: WaveformTrace, key: Int, token: Int) {
        lock.lock()
        let onTrace = taps[key].flatMap { $0.token == token ? $0.onTrace : nil }
        lock.unlock()
        onTrace?(trace)
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
