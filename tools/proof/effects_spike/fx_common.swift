// fx_common.swift — the shared half of the effects spike (2026-09-15).
//
// One offline renderer over AVAudioEngine's manual rendering mode, plus the
// measurements every program takes of what it renders. No async anywhere:
// renderOffline(_:to:) is a synchronous call on the calling thread, and the
// point of the spike is to show that is the whole story.
//
// Compiled beside each program: `xcrun swiftc -O -parse-as-library
// -target arm64-apple-macos26.0 fx_common.swift <program>.swift -o <program>`.

import AVFoundation
import Accelerate
import CoreAudio
import CryptoKit
import Foundation

// MARK: - Samples

/// Non-interleaved float samples, one array per channel.
struct Audio {
    var channels: [[Float]]
    var rate: Double
    var frames: Int { channels.first?.count ?? 0 }

    func slice(_ from: Int, _ count: Int) -> Audio {
        let end = min(frames, from + count)
        return Audio(channels: channels.map { Array($0[max(0, from)..<max(from, end)]) }, rate: rate)
    }

    /// SHA-256 of the raw float bytes, channel after channel.
    var digest: String {
        var h = SHA256()
        for c in channels { c.withUnsafeBufferPointer { h.update(bufferPointer: UnsafeRawBufferPointer($0)) } }
        return h.finalize().map { String(format: "%02x", $0) }.joined().prefix(16).description
    }
}

func readAudio(_ url: URL) throws -> Audio {
    let file = try AVAudioFile(forReading: url)
    let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: buf)
    let n = Int(buf.frameLength)
    let ch = Int(buf.format.channelCount)
    return Audio(channels: (0..<ch).map { Array(UnsafeBufferPointer(start: buf.floatChannelData![$0], count: n)) },
                 rate: buf.format.sampleRate)
}

func pcmBuffer(_ a: Audio) -> AVAudioPCMBuffer {
    let fmt = AVAudioFormat(standardFormatWithSampleRate: a.rate, channels: AVAudioChannelCount(a.channels.count))!
    let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(a.frames))!
    buf.frameLength = AVAudioFrameCount(a.frames)
    for (i, c) in a.channels.enumerated() { c.withUnsafeBufferPointer { buf.floatChannelData![i].update(from: $0.baseAddress!, count: a.frames) } }
    return buf
}

enum FileKind { case cafFloat, wavInt16, m4aAAC }

func writeAudio(_ a: Audio, to url: URL, kind: FileKind) throws {
    try? FileManager.default.removeItem(at: url)
    var settings: [String: Any] = [AVSampleRateKey: a.rate, AVNumberOfChannelsKey: a.channels.count]
    switch kind {
    case .cafFloat:
        settings[AVFormatIDKey] = kAudioFormatLinearPCM; settings[AVLinearPCMBitDepthKey] = 32
        settings[AVLinearPCMIsFloatKey] = true; settings[AVLinearPCMIsNonInterleaved] = false
    case .wavInt16:
        settings[AVFormatIDKey] = kAudioFormatLinearPCM; settings[AVLinearPCMBitDepthKey] = 16
        settings[AVLinearPCMIsFloatKey] = false; settings[AVLinearPCMIsNonInterleaved] = false
        settings[AVLinearPCMIsBigEndianKey] = false
    case .m4aAAC:
        settings[AVFormatIDKey] = kAudioFormatMPEG4AAC; settings[AVEncoderBitRateKey] = 192_000
    }
    let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    try file.write(from: pcmBuffer(a))
}

// MARK: - The renderer

enum Source {
    /// AVAudioPlayerNode.scheduleFile — the whole file.
    case file(URL)
    /// AVAudioPlayerNode.scheduleSegment — a window of the file.
    case segment(URL, start: AVAudioFramePosition, count: AVAudioFrameCount)
    /// AVAudioPlayerNode.scheduleBuffer — samples already in memory.
    case buffer(Audio)
    /// AVAudioSourceNode pulling from samples in memory (zeros past the end).
    case sourceNode(Audio)
}

struct RenderOptions {
    var chunk: AVAudioFrameCount = 4096
    var maxFrames: AVAudioFrameCount = 4096
    /// nil: 48 kHz stereo float.
    var outFormat: AVAudioFormat? = nil
    /// nil: the source's own format on every connection.
    var connectFormat: AVAudioFormat? = nil
    /// Enable manual mode before touching mainMixerNode (Apple's advice), or after connecting.
    var enableFirst = true
}

struct RenderResult {
    var audio: Audio
    var setupSeconds: Double
    var renderSeconds: Double
    var statuses: [String: Int]
    var units: [AVAudioNode]
}

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

/// Renders `frames` frames of `source` through `makeUnits()`'s nodes in series.
/// A fresh AVAudioEngine each call. Throws on any error the engine reports.
func render(_ source: Source, frames: Int, options: RenderOptions = RenderOptions(),
            configure: ((AVAudioEngine) -> Void)? = nil,
            afterStart: ((AVAudioEngine) -> Void)? = nil,
            makeUnits: () -> [AVAudioNode]) throws -> RenderResult {
    let t0 = now()
    let engine = AVAudioEngine()
    let outFormat = options.outFormat ?? AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
    if options.enableFirst {
        try engine.enableManualRenderingMode(.offline, format: outFormat, maximumFrameCount: options.maxFrames)
    }
    let units = makeUnits()
    units.forEach { engine.attach($0) }

    var player: AVAudioPlayerNode?
    let head: AVAudioNode
    let srcFormat: AVAudioFormat
    var schedule: () -> Void = {}
    switch source {
    case .file(let url):
        let f = try AVAudioFile(forReading: url)
        let p = AVAudioPlayerNode(); player = p; head = p; srcFormat = f.processingFormat
        schedule = { p.scheduleFile(f, at: nil) }
    case .segment(let url, let start, let count):
        let f = try AVAudioFile(forReading: url)
        let p = AVAudioPlayerNode(); player = p; head = p; srcFormat = f.processingFormat
        schedule = { p.scheduleSegment(f, startingFrame: start, frameCount: count, at: nil) }
    case .buffer(let a):
        let b = pcmBuffer(a)
        let p = AVAudioPlayerNode(); player = p; head = p; srcFormat = b.format
        schedule = { p.scheduleBuffer(b, at: nil) }
    case .sourceNode(let a):
        let fmt = AVAudioFormat(standardFormatWithSampleRate: a.rate, channels: AVAudioChannelCount(a.channels.count))!
        srcFormat = fmt
        var cursor = 0
        let chans = a.channels
        head = AVAudioSourceNode(format: fmt) { _, _, frameCount, abl in
            let list = UnsafeMutableAudioBufferListPointer(abl)
            let n = Int(frameCount)
            for (i, b) in list.enumerated() {
                let dst = b.mData!.assumingMemoryBound(to: Float.self)
                let src = chans[min(i, chans.count - 1)]
                for k in 0..<n { dst[k] = cursor + k < src.count ? src[cursor + k] : 0 }
            }
            cursor += n
            return noErr
        }
    }
    engine.attach(head)
    let cf = options.connectFormat ?? srcFormat
    var prev = head
    for u in units { engine.connect(prev, to: u, format: cf); prev = u }
    engine.connect(prev, to: engine.mainMixerNode, format: cf)
    if !options.enableFirst {
        try engine.enableManualRenderingMode(.offline, format: outFormat, maximumFrameCount: options.maxFrames)
    }
    configure?(engine)
    schedule()
    try engine.start()
    afterStart?(engine)
    player?.play()
    let t1 = now()

    let fmt = engine.manualRenderingFormat
    let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: engine.manualRenderingMaximumFrameCount)!
    let ch = Int(fmt.channelCount)
    var out = [[Float]](repeating: [], count: ch)
    for c in 0..<ch { out[c].reserveCapacity(frames) }
    var statuses: [String: Int] = [:]
    var done = 0
    var stalls = 0
    while done < frames {
        let n = AVAudioFrameCount(min(Int(options.chunk), frames - done))
        let status = try engine.renderOffline(n, to: buf)
        let key: String
        switch status {
        case .success: key = "success"
        case .insufficientDataFromInputNode: key = "insufficientData"
        case .cannotDoInCurrentContext: key = "cannotDoInCurrentContext"
        case .error: key = "error"
        @unknown default: key = "unknown"
        }
        statuses[key, default: 0] += 1
        let got = Int(buf.frameLength)
        for c in 0..<ch { out[c].append(contentsOf: UnsafeBufferPointer(start: buf.floatChannelData![c], count: got)) }
        done += got
        if got == 0 { stalls += 1; if stalls > 1000 { throw NSError(domain: "fx", code: 1, userInfo: [NSLocalizedDescriptionKey: "render stalled: \(statuses)"]) } }
        if status == .error { throw NSError(domain: "fx", code: 2, userInfo: [NSLocalizedDescriptionKey: "render error status"]) }
    }
    let t2 = now()
    player?.stop()
    engine.stop()
    return RenderResult(audio: Audio(channels: out, rate: fmt.sampleRate), setupSeconds: t1 - t0,
                        renderSeconds: t2 - t1, statuses: statuses, units: units)
}

// MARK: - Unit factories

func timePitch(_ cents: Float, rate: Float = 1, overlap: Float? = nil) -> AVAudioUnitTimePitch {
    let u = AVAudioUnitTimePitch(); u.pitch = cents; u.rate = rate
    if let o = overlap { u.overlap = o }
    return u
}

/// A reverb at a factory preset. NOT loadFactoryPreset: before engine.start()
/// that call is silently ignored on macOS 26.5.1 (fx_presets measures it), and
/// after start it lands ~43 ms into the render. auAudioUnit.currentPreset takes
/// effect from sample 0 and works before the node is even attached.
func reverb(_ preset: AVAudioUnitReverbPreset, wet: Float? = 50) -> AVAudioUnitReverb {
    let u = AVAudioUnitReverb()
    u.auAudioUnit.currentPreset = u.auAudioUnit.factoryPresets?.first { $0.number == preset.rawValue }
    if let w = wet { u.wetDryMix = w }
    return u
}

func delay(time: Double = 0.25, feedback: Float = 40, wet: Float = 35) -> AVAudioUnitDelay {
    let u = AVAudioUnitDelay(); u.delayTime = time; u.feedback = feedback; u.wetDryMix = wet
    return u
}

/// Bass +6 dB shelf at 120 Hz, treble +6 dB shelf at 6 kHz, and a 1-kHz-centred
/// band-pass two octaves wide — every band un-bypassed explicitly.
func eqThreeBand() -> AVAudioUnitEQ {
    let u = AVAudioUnitEQ(numberOfBands: 3)
    let b = u.bands
    b[0].filterType = .lowShelf; b[0].frequency = 120; b[0].gain = 6; b[0].bypass = false
    b[1].filterType = .highShelf; b[1].frequency = 6000; b[1].gain = 6; b[1].bypass = false
    b[2].filterType = .parametric; b[2].frequency = 1000; b[2].bandwidth = 2; b[2].gain = -3; b[2].bypass = false
    return u
}

/// A telephone band: high-pass 300 Hz, low-pass 3400 Hz.
func eqTelephone() -> AVAudioUnitEQ {
    let u = AVAudioUnitEQ(numberOfBands: 2)
    u.bands[0].filterType = .highPass; u.bands[0].frequency = 300; u.bands[0].bypass = false
    u.bands[1].filterType = .lowPass; u.bands[1].frequency = 3400; u.bands[1].bypass = false
    return u
}

func distortion(_ preset: AVAudioUnitDistortionPreset, wet: Float? = nil) -> AVAudioUnitDistortion {
    let u = AVAudioUnitDistortion(); u.loadFactoryPreset(preset)
    if let w = wet { u.wetDryMix = w }
    return u
}

// MARK: - Measurements

func db(_ x: Double) -> Double { x > 0 ? 20 * log10(x) : -.infinity }
func fmtDB(_ x: Double) -> String { x.isFinite ? String(format: "%.2f", x) : "-inf" }

func peak(_ a: Audio) -> Double { a.channels.map { Double(vDSP.maximumMagnitude($0)) }.max() ?? 0 }
func rms(_ a: Audio) -> Double {
    let s = a.channels.map { c -> Double in let r = Double(vDSP.rootMeanSquare(c)); return r * r }
    return sqrt(s.reduce(0, +) / Double(max(1, s.count)))
}

/// Largest absolute sample difference over the common length, and the count of
/// differing samples. Lengths differing are reported by the caller.
func compare(_ a: Audio, _ b: Audio) -> (maxAbs: Double, differing: Int, total: Int) {
    let n = min(a.frames, b.frames)
    var m: Float = 0; var d = 0
    for c in 0..<min(a.channels.count, b.channels.count) {
        let x = a.channels[c], y = b.channels[c]
        for i in 0..<n { let e = abs(x[i] - y[i]); if e > 0 { d += 1; if e > m { m = e } } }
    }
    return (Double(m), d, n * min(a.channels.count, b.channels.count))
}

/// Last frame (index) whose |sample| on any channel exceeds `threshold`.
func lastAbove(_ a: Audio, _ threshold: Float) -> Int {
    var last = -1
    for c in a.channels { if let i = c.lastIndex(where: { abs($0) > threshold }), i > last { last = i } }
    return last
}

/// Lag (frames) that maximises the correlation of y against x over ±maxLag:
/// positive means y is LATE. Uses channel 0, over x's frames [from, from+len).
func xcorrLag(_ x: [Float], _ y: [Float], from: Int, len: Int, maxLag: Int) -> (lag: Int, r: Double) {
    let xs = Array(x[from..<(from + len)])
    let ex = Double(vDSP.sumOfSquares(xs))
    var best = (0, -Double.infinity)
    for lag in -maxLag...maxLag {
        let s = from + lag
        guard s >= 0, s + len <= y.count else { continue }
        var dot: Float = 0
        y.withUnsafeBufferPointer { yp in xs.withUnsafeBufferPointer { xp in
            vDSP_dotpr(xp.baseAddress!, 1, yp.baseAddress! + s, 1, &dot, vDSP_Length(len)) } }
        let ey = Double(vDSP.sumOfSquares(y[s..<(s + len)]))
        let r = Double(dot) / max(1e-20, sqrt(ex * ey))
        if r > best.1 { best = (lag, r) }
    }
    return best
}

/// A smoothed amplitude envelope: |x| through a `width`-sample box filter.
func envelope(_ x: [Float], width: Int = 48) -> [Float] {
    var absx = vDSP.absolute(x)
    let kernel = [Float](repeating: 1 / Float(width), count: width)
    absx.append(contentsOf: [Float](repeating: 0, count: width))
    return vDSP.convolve(absx, withKernel: kernel)
}

/// Dominant frequency (Hz) of `x[from..<from+4096*16]` by a Hann-windowed FFT
/// with parabolic interpolation.
func dominantHz(_ x: [Float], rate: Double, from: Int) -> Double {
    let log2n = 16, n = 1 << log2n
    guard from + n <= x.count else { return .nan }
    let mags = magnitudes(Array(x[from..<(from + n)]), log2n: log2n)
    var k = 1; for i in 1..<(n / 2 - 1) where mags[i] > mags[k] { k = i }
    let a = Double(mags[k - 1]), b = Double(mags[k]), c = Double(mags[k + 1])
    let p = 0.5 * (a - c) / (a - 2 * b + c)
    return (Double(k) + p) * rate / Double(n)
}

func magnitudes(_ frame: [Float], log2n: Int) -> [Float] {
    let n = 1 << log2n
    let win = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: n, isHalfWindow: false)
    var re = vDSP.multiply(frame, win)
    var im = [Float](repeating: 0, count: n)
    let setup = vDSP_create_fftsetup(vDSP_Length(log2n), FFTRadix(kFFTRadix2))!
    defer { vDSP_destroy_fftsetup(setup) }
    var mags = [Float](repeating: 0, count: n / 2)
    re.withUnsafeMutableBufferPointer { rp in im.withUnsafeMutableBufferPointer { ip in
        var z = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
        vDSP_fft_zip(setup, &z, 1, vDSP_Length(log2n), FFTDirection(FFT_FORWARD))
        vDSP_zvabs(&z, 1, &mags, 1, vDSP_Length(n / 2))
    } }
    return mags
}

struct Spectrum { var centroidHz: Double; var below300: Double; var band: Double; var above3400: Double }

/// Energy-weighted mean spectral centroid over 2048-sample frames above −50 dBFS,
/// and the fraction of energy below 300 Hz, in 300–3400 Hz, and above 3400 Hz.
func spectrum(_ x: [Float], rate: Double) -> Spectrum {
    let log2n = 11, n = 1 << log2n
    var cw = 0.0, w = 0.0, lo = 0.0, mid = 0.0, hi = 0.0
    var i = 0
    while i + n <= x.count {
        let frame = Array(x[i..<(i + n)])
        let r = Double(vDSP.rootMeanSquare(frame))
        if db(r) > -50 {
            let m = magnitudes(frame, log2n: log2n)
            var e = 0.0, fe = 0.0
            for k in 1..<(n / 2) {
                let p = Double(m[k]) * Double(m[k]); let f = Double(k) * rate / Double(n)
                e += p; fe += f * p
                if f < 300 { lo += p } else if f <= 3400 { mid += p } else { hi += p }
            }
            if e > 0 { cw += (fe / e) * e; w += e }
        }
        i += n
    }
    let tot = max(1e-30, lo + mid + hi)
    return Spectrum(centroidHz: w > 0 ? cw / w : .nan, below300: lo / tot, band: mid / tot, above3400: hi / tot)
}

// MARK: - Host facts

func hostLine() -> String {
    let v = ProcessInfo.processInfo.operatingSystemVersionString
    var id = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                          mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
    var name: Unmanaged<CFString>?
    size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    addr.mSelector = kAudioObjectPropertyName
    AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name)
    var rate: Float64 = 0
    size = UInt32(MemoryLayout<Float64>.size)
    addr.mSelector = kAudioDevicePropertyNominalSampleRate
    AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &rate)
    let devName = name?.takeRetainedValue() as String? ?? "?"
    return "host: macOS \(v); default output device \"\(devName)\" at \(rate) Hz"
}

func fixture(_ name: String) -> URL {
    let dir = ProcessInfo.processInfo.environment["FX_FIXTURES"] ?? "../work/effects_spike/fx"
    return URL(fileURLWithPath: dir).appendingPathComponent(name)
}

func workDir() -> URL {
    let dir = ProcessInfo.processInfo.environment["FX_WORK"] ?? "../work/effects_spike/out"
    let url = URL(fileURLWithPath: dir)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func pad(_ s: String, _ n: Int) -> String { s.count >= n ? s : s + String(repeating: " ", count: n - s.count) }
