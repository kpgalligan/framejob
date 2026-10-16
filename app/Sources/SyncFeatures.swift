import Accelerate
import Foundation

/// Synchronize Audio's features (road map "audio-sync-2", AS-3; spec §11
/// SY-11): MFCC frames of a file's sound, what `cache/sync/<id>.bin` holds and
/// what the coarse match correlates (SY-12).
///
/// Pure — samples in, frames out, no AVFoundation and no disk; the reader is
/// `MediaImporter+SyncFeatures.swift`'s. The recipe is BBC R&D's
/// `audio-offset-finder` as the round's `mfccsync.py` wrote it, exactly, so
/// the numbers it measured carry over: mono at `sampleRate`, one frame every
/// `hop` samples, each `fftSize` samples holding a symmetric Hann window of
/// `windowLength` centred in it, the power spectrum through `melBands`
/// triangular HTK-mel bands from 0 to the Nyquist, `log(P·FB + 1e-10)`, and
/// an unnormalised DCT-II to c0…c(`coefficients` − 1). Frame f starts at
/// sample `hop·f`, so it is `frameTicks` of source time from frame f − 1.
///
/// A change to ANY constant here is a new cache format: bump
/// `MediaImporter.syncFeaturesVersion` with it.
enum SyncFeatures {

    // MARK: - The recipe (SY-11)

    static let sampleRate = 8000
    static let fftSize = 512
    static let windowLength = 256
    static let hop = 128
    static let melBands = 40
    static let coefficients = 26

    /// One frame's step in source ticks — exactly 9,600, written as the
    /// division for `MediaSpeech.chunkTicks`' reason.
    static var frameTicks: Ticks {
        ReelTime.perSecond * Ticks(hop) / Ticks(sampleRate)
    }

    /// How many whole frames `samples` hold: `(samples − fftSize)/hop + 1`, 0
    /// when there is not one.
    static func frameCount(samples: Int) -> Int {
        samples >= fftSize ? (samples - fftSize) / hop + 1 : 0
    }

    /// The frames of `samples` at `sampleRate`, frame-major,
    /// `coefficients` floats a frame.
    static func frames(_ samples: [Float]) -> [Float] {
        let extractor = Extractor()
        samples.withUnsafeBufferPointer { extractor.feed($0) }
        return extractor.finish()
    }

    // MARK: - The tables

    /// The Hann(`windowLength`) window centred in `fftSize` zeros: numpy's
    /// `hanning`, `0.5 − 0.5·cos(2πn/(M − 1))`.
    private static let window: [Float] = {
        var values = [Float](repeating: 0, count: fftSize)
        let offset = (fftSize - windowLength) / 2
        for n in 0..<windowLength {
            values[offset + n] = Float(
                0.5 - 0.5 * cos(2 * Double.pi * Double(n) / Double(windowLength - 1)))
        }
        return values
    }()

    /// One mel band: its first power bin and its weights from there.
    private struct Band {
        let first: Int
        let weights: [Float]
    }

    /// The HTK-mel filterbank, `mfccsync.py`'s `filterbank()`: `melBands + 2`
    /// points evenly spaced in mel from 0 to the Nyquist, each at bin
    /// `⌊(fftSize + 1)·f/sampleRate⌋`; band i rises from point i to i + 1 and
    /// falls to i + 2.
    private static let bands: [Band] = {
        func mel(_ f: Double) -> Double { 2595 * log10(1 + f / 700) }
        func hertz(_ m: Double) -> Double { 700 * (pow(10, m / 2595) - 1) }
        let top = mel(Double(sampleRate) / 2)
        let bins = (0..<(melBands + 2)).map { index -> Int in
            let f = hertz(top * Double(index) / Double(melBands + 1))
            return Int((Double(fftSize + 1) * f / Double(sampleRate)).rounded(.down))
        }
        return (0..<melBands).map { i in
            let (l, c, r) = (bins[i], bins[i + 1], bins[i + 2])
            var weights: [Float] = []
            for k in l..<max(l, c) { weights.append(Float(Double(k - l) / Double(max(c - l, 1)))) }
            for k in c..<max(c, r) { weights.append(Float(Double(r - k) / Double(max(r - c, 1)))) }
            return Band(first: l, weights: weights)
        }
    }()

    /// `cos(π/melBands · (k + 0.5) · n)`, row n, column k.
    private static let dct: [Double] = {
        var values = [Double](repeating: 0, count: coefficients * melBands)
        for n in 0..<coefficients {
            for k in 0..<melBands {
                values[n * melBands + k] = cos(
                    Double.pi / Double(melBands) * (Double(k) + 0.5) * Double(n))
            }
        }
        return values
    }()

    // MARK: - Streaming

    /// Takes a file's samples in whatever pieces the reader hands over and
    /// keeps every whole frame; `finish` answers them.
    final class Extractor {
        private var pending: [Float] = []
        private var output: [Float] = []
        private let log2n = vDSP_Length(9)  // fftSize = 512
        private let setup: FFTSetup?
        private var framed = [Float](repeating: 0, count: SyncFeatures.fftSize)
        private var real = [Float](repeating: 0, count: SyncFeatures.fftSize / 2)
        private var imaginary = [Float](repeating: 0, count: SyncFeatures.fftSize / 2)
        private var power = [Float](repeating: 0, count: SyncFeatures.fftSize / 2 + 1)
        private var logMel = [Double](repeating: 0, count: SyncFeatures.melBands)

        init() {
            setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        }

        deinit {
            if let setup { vDSP_destroy_fftsetup(setup) }
        }

        func feed(_ samples: UnsafeBufferPointer<Float>) {
            pending.append(contentsOf: samples)
            var start = 0
            while pending.count - start >= SyncFeatures.fftSize {
                frame(at: start)
                start += SyncFeatures.hop
            }
            if start > 0 { pending.removeFirst(start) }
        }

        /// Every frame fed so far, frame-major.
        func finish() -> [Float] { output }

        private func frame(at start: Int) {
            guard let setup else { return }
            let size = SyncFeatures.fftSize
            let half = size / 2
            let window = SyncFeatures.window
            for n in 0..<size { framed[n] = pending[start + n] * window[n] }
            real.withUnsafeMutableBufferPointer { re in
                imaginary.withUnsafeMutableBufferPointer { im in
                    var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                    framed.withUnsafeBufferPointer { source in
                        source.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                            vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                }
            }
            // `vDSP_fft_zrip` answers twice the DFT, DC packed in real[0] and
            // the Nyquist in imaginary[0]: |X|² is a quarter of what it gives.
            power[0] = real[0] * real[0] / 4
            power[half] = imaginary[0] * imaginary[0] / 4
            for k in 1..<half {
                power[k] = (real[k] * real[k] + imaginary[k] * imaginary[k]) / 4
            }
            for (index, band) in SyncFeatures.bands.enumerated() {
                var energy = 0.0
                for (offset, weight) in band.weights.enumerated() {
                    energy += Double(weight) * Double(power[band.first + offset])
                }
                logMel[index] = log(energy + 1e-10)
            }
            let bandsCount = SyncFeatures.melBands
            let dct = SyncFeatures.dct
            for n in 0..<SyncFeatures.coefficients {
                var sum = 0.0
                for k in 0..<bandsCount { sum += dct[n * bandsCount + k] * logMel[k] }
                output.append(Float(sum))
            }
        }
    }
}
