import Accelerate
import Foundation

/// A clip's average SPEECH spectrum in third-octave bands (road map "audio"
/// AP12, spec §11 AU-124), measured on a render as `ProcessedLoudness.render`
/// reads it: the 48 kHz interleaved stereo float buffers its
/// `StepLoudnessMeter` takes are fed here too, beside it.
///
/// An STFT of `fftSize` points with a periodic Hann window, every `hop`
/// frames from the read's first frame. A frame COUNTS when the 10 ms played
/// step at its centre (frame index ⌊centre / 480⌋) is speech in the mask
/// the meter was made with; its power |X_L|² + |X_R|² is summed into each
/// band. Band n of `bandIndices` is centred at `centre(n)` = 1000·2^(n/3) Hz
/// and holds the bins in [c·2^(−1/6), c·2^(1/6)). `finish` answers each
/// band's level, 10·log10 of its mean power over the counted frames, scaled
/// so a sine of amplitude A wholly in one band of one channel reads
/// 10·log10(A²/2) (its mean square: Parseval over the one-sided spectrum,
/// divided by N·Σw²/2). Under `minimumFrames` counted frames (about 1 s of
/// speech) it answers nil.
///
/// Offline only (not a live stage, so S1's bit rule does not bind it). One
/// meter per render, on the render's own queue.
final class SpeechSpectrumMeter {
    static let fftSize = 8192
    static let hop = 4096
    static let bandIndices = -11...11
    static let minimumFrames = 12
    /// The render's rate, and its 10 ms step in frames.
    static let sampleRate = 48_000.0
    static let stepFrames = 480

    /// The centre of band `n`, Hz: 1000·2^(n/3).
    static func centre(_ n: Int) -> Double { 1000 * pow(2, Double(n) / 3) }

    /// The bins of each band, `[low, high)`, at `fftSize` and `sampleRate`.
    static let bandBins: [Range<Int>] = bandIndices.map { n in
        let c = centre(n)
        let width = sampleRate / Double(fftSize)
        let low = Int((c * pow(2, -1.0 / 6) / width).rounded(.up))
        let high = Int((c * pow(2, 1.0 / 6) / width).rounded(.up))
        return low..<max(low, high)
    }

    private let speech: [Bool]
    private let log2n = vDSP_Length(13)
    private let setup: FFTSetup?
    private var window = [Float](repeating: 0, count: SpeechSpectrumMeter.fftSize)
    /// The frames fed and not yet passed by a hop: left and right.
    private var left: [Float] = []
    private var right: [Float] = []
    /// The absolute index of `left[0]` in the read.
    private var origin = 0
    private var sums = [Double](repeating: 0, count: SpeechSpectrumMeter.bandIndices.count)
    /// Frames that counted (speech at their centre).
    private(set) var counted = 0

    /// `speech`: one flag per 10 ms played step of the read, in order; a step
    /// past its end is not speech.
    init(speech: [Bool]) {
        self.speech = speech
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        vDSP_hann_window(&window, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_DENORM))
        left.reserveCapacity(2 * Self.fftSize)
        right.reserveCapacity(2 * Self.fftSize)
    }

    deinit {
        if let setup { vDSP_destroy_fftsetup(setup) }
    }

    /// `frames` interleaved stereo frames, in read order.
    func feed(_ interleavedStereo: UnsafePointer<Float>, frames: Int) {
        guard frames > 0 else { return }
        for f in 0..<frames {
            left.append(interleavedStereo[2 * f])
            right.append(interleavedStereo[2 * f + 1])
        }
        while left.count >= Self.fftSize {
            let centre = origin + Self.fftSize / 2
            let step = centre / Self.stepFrames
            if step < speech.count, speech[step] { analyse() }
            left.removeFirst(Self.hop)
            right.removeFirst(Self.hop)
            origin += Self.hop
        }
    }

    /// Each band's level in dB, `bandIndices` order; nil under
    /// `minimumFrames` counted frames.
    func finish() -> [Double]? {
        guard counted >= Self.minimumFrames else { return nil }
        let windowPower = window.reduce(0) { $0 + Double($1) * Double($1) }
        let scale = 2 / (Double(Self.fftSize) * windowPower) / Double(counted)
        return sums.map { 10 * log10(max($0 * scale, 1e-30)) }
    }

    // MARK: - One frame

    /// The frame at `left[0..<fftSize]`: each channel windowed and
    /// transformed, its power added into each band.
    private func analyse() {
        guard let setup else { return }
        let n = Self.fftSize
        let half = n / 2
        var power = [Double](repeating: 0, count: half)
        var windowed = [Float](repeating: 0, count: n)
        var real = [Float](repeating: 0, count: half)
        var imaginary = [Float](repeating: 0, count: half)
        for channel in [left, right] {
            vDSP_vmul(channel, 1, window, 1, &windowed, 1, vDSP_Length(n))
            real.withUnsafeMutableBufferPointer { re in
                imaginary.withUnsafeMutableBufferPointer { im in
                    var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                    windowed.withUnsafeBufferPointer { source in
                        source.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                            vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                }
            }
            // `vDSP_fft_zrip` scales by 2; bin 0 packs DC and Nyquist, and no
            // band reaches either.
            for k in 1..<half {
                let re = Double(real[k]) / 2
                let im = Double(imaginary[k]) / 2
                power[k] += re * re + im * im
            }
        }
        for (b, bins) in Self.bandBins.enumerated() {
            var total = 0.0
            for k in bins where k < half { total += power[k] }
            sums[b] += total
        }
        counted += 1
    }
}
