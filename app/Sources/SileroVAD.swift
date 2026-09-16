import CoreML
import Foundation

/// Silero VAD v6.2.1 through Core ML: the streaming 32 ms wrapper road map
/// 4's S0 spike proved and S1 ships. No AppKit, no `async` — the model
/// predicts synchronously, which is what lets `SilenceDetector.detect`
/// (never off main) and `MediaImporter+Speech.writeSpeech` (which never
/// `await`s) share one class.
///
/// `tools/proof/silence_spike/silero_coreml.swift`'s `Silero` made streaming:
/// the spike's `run` fed a whole signal and returned; `feed` holds the
/// remainder across calls, so a reader handing it one `CMSampleBuffer` at a
/// time never loses the tail of a chunk that straddled two buffers.
///
/// One instance holds one utterance's state — `h`, `c`, the 64-sample
/// context and the held remainder — so two media analysed concurrently
/// (`generateCaches`'s per-media passes run in call order, but two DIFFERENT
/// media can overlap) each need their own `bundled()`.
final class SileroVAD {
    static let modelName = "silero-vad-6.2.1-coreml-fp16-32ms"

    static let sampleRate = 16_000
    static let chunkSamples = 512
    static let contextSamples = 64
    static let stateSize = 128

    static let audioInput = "audio"
    static let stateH = "h"
    static let stateC = "c"
    static let probabilityOutput = "probability"
    static let stateHOut = "h_out"
    static let stateCOut = "c_out"

    // MARK: - Availability

    /// The bundled model's compiled location, or nil when this build carries
    /// none: `Bundle.main`'s own `Models` subdirectory first (the shipped
    /// app), then `bundleURL/Models/silero_vad.mlmodelc` for a binary that is
    /// not a proper bundle (the offscreen harness, which copies `Models`
    /// beside itself rather than building a bundle).
    static var bundledURL: URL? {
        if let url = Bundle.main.url(
            forResource: "silero_vad", withExtension: "mlmodelc", subdirectory: "Models") {
            return url
        }
        let sibling = Bundle.main.bundleURL
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("silero_vad.mlmodelc", isDirectory: true)
        return FileManager.default.fileExists(atPath: sibling.path) ? sibling : nil
    }

    private static let availabilityLock = NSLock()
    private static var unavailableReason: String?

    /// Whether the voice model can be asked for this process. `NSLock`-guarded
    /// because it is written from a cache pass off main (`writeSpeech`) and
    /// read on main (`Input.read`) — the same shape road map 3's recorder
    /// gives its availability flag, and `app/CLAUDE.md`'s one sanctioned
    /// cross-thread lock.
    static var isAvailable: Bool {
        availabilityLock.lock()
        defer { availabilityLock.unlock() }
        return bundledURL != nil && unavailableReason == nil
    }

    /// Marks the model unavailable for the rest of the process. Idempotent —
    /// only the FIRST reason is kept and logged, because a second failure
    /// after the first has nothing new to say and a log line per media would
    /// drown the one that mattered.
    static func markUnavailable(_ reason: String) {
        availabilityLock.lock()
        let first = unavailableReason == nil
        if first { unavailableReason = reason }
        availabilityLock.unlock()
        if first { print("Reelcut: voice model unavailable — \(reason)") }
    }

    /// A fresh instance, or nil (and `markUnavailable`d) for a nil URL or a
    /// throwing init. FRESH per call, never shared: state is per instance,
    /// and passes for different media run concurrently.
    static func bundled() -> SileroVAD? {
        guard let url = bundledURL else {
            markUnavailable("no model in the bundle")
            return nil
        }
        do {
            return try SileroVAD(modelURL: url)
        } catch {
            markUnavailable("\(error)")
            return nil
        }
    }

    // MARK: - Instance

    private let model: MLModel
    private var h: MLMultiArray
    private var c: MLMultiArray
    private var context: [Float]
    private var remainder: [Float] = []

    init(modelURL: URL) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        model = try MLModel(contentsOf: modelURL, configuration: configuration)
        h = try MLMultiArray(shape: [1, 1, NSNumber(value: Self.stateSize)], dataType: .float16)
        c = try MLMultiArray(shape: [1, 1, NSNumber(value: Self.stateSize)], dataType: .float16)
        for i in 0..<Self.stateSize {
            h[i] = 0
            c[i] = 0
        }
        context = [Float](repeating: 0, count: Self.contextSamples)
    }

    /// Zeroes the state and drops the held context and remainder — the start
    /// of a fresh utterance.
    func reset() {
        for i in 0..<Self.stateSize {
            h[i] = 0
            c[i] = 0
        }
        context = [Float](repeating: 0, count: Self.contextSamples)
        remainder = []
    }

    /// One probability per COMPLETE 512-sample chunk `samples` completes,
    /// counting whatever `feed` and `flush` held from earlier calls. Any
    /// samples left over after the last full chunk are held for next time
    /// (or for `flush`).
    func feed(_ samples: [Float]) throws -> [Float] {
        var pending = remainder + samples
        remainder = []
        var probabilities: [Float] = []
        var offset = 0
        while offset + Self.chunkSamples <= pending.count {
            let chunk = Array(pending[offset..<(offset + Self.chunkSamples)])
            probabilities.append(try step(chunk))
            offset += Self.chunkSamples
        }
        remainder = Array(pending[offset...])
        pending = []
        return probabilities
    }

    /// The held remainder, zero-padded to a full chunk and run once — or nil
    /// when nothing was held.
    func flush() throws -> Float? {
        guard !remainder.isEmpty else { return nil }
        var chunk = remainder
        chunk.append(contentsOf: [Float](repeating: 0, count: Self.chunkSamples - chunk.count))
        remainder = []
        return try step(chunk)
    }

    /// `reset` + `feed` + `flush`: the whole signal, one call, the spike's
    /// `run` with the tail folded in.
    func probabilities(of samples: [Float]) throws -> [Float] {
        reset()
        var result = try feed(samples)
        if let tail = try flush() { result.append(tail) }
        return result
    }

    /// One 512-sample chunk through the model: 64 samples of context + the
    /// new 512 as `[1,1,576]`, `h`/`c` fed back, the context updated to the
    /// chunk's last 64 samples.
    private func step(_ chunk: [Float]) throws -> Float {
        let width = Self.contextSamples + Self.chunkSamples
        let audio = try MLMultiArray(shape: [1, 1, NSNumber(value: width)], dataType: .float16)
        audio.withUnsafeMutableBytes { raw, _ in
            let pointer = raw.bindMemory(to: Float16.self)
            for i in 0..<Self.contextSamples { pointer[i] = Float16(context[i]) }
            for i in 0..<Self.chunkSamples { pointer[Self.contextSamples + i] = Float16(chunk[i]) }
        }
        let input = try MLDictionaryFeatureProvider(dictionary: [
            Self.audioInput: audio, Self.stateH: h, Self.stateC: c,
        ])
        let output = try model.prediction(from: input)
        guard
            let probabilityValue = output.featureValue(for: Self.probabilityOutput)?
                .multiArrayValue,
            let hOut = output.featureValue(for: Self.stateHOut)?.multiArrayValue,
            let cOut = output.featureValue(for: Self.stateCOut)?.multiArrayValue
        else {
            throw SileroError.badOutput
        }
        h = hOut
        c = cOut
        context = Array(chunk[(Self.chunkSamples - Self.contextSamples)...])
        return Float(truncating: probabilityValue[0])
    }

    private enum SileroError: Error, CustomStringConvertible {
        case badOutput
        var description: String { "the model's output did not carry the expected features" }
    }
}
