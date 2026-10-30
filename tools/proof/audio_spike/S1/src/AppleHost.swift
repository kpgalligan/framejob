import AVFoundation
import AudioToolbox
import Foundation

// MARK: - Unit descriptions and parameters

enum AppleUnit {
    static func desc(_ sub: OSType) -> AudioComponentDescription {
        AudioComponentDescription(
            componentType: kAudioUnitType_Effect, componentSubType: sub,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0,
            componentFlagsMask: 0)
    }
    static let nBandEQ = desc(kAudioUnitSubType_NBandEQ)
    static let peakLimiter = desc(kAudioUnitSubType_PeakLimiter)
    static let dynamics = desc(kAudioUnitSubType_DynamicsProcessor)

    // AUNBandEQ filter types.
    static func nbType(_ k: EQKind) -> Float {
        switch k {
        case .highPass: return Float(kAUNBandEQFilterType_2ndOrderButterworthHighPass)
        case .peaking: return Float(kAUNBandEQFilterType_Parametric)
        case .lowShelf: return Float(kAUNBandEQFilterType_LowShelf)
        case .highShelf: return Float(kAUNBandEQFilterType_HighShelf)
        case .notch: return Float(kAUNBandEQFilterType_BandStop)
        }
    }

    static func stream(channels: Int, rate: Double) -> AudioStreamBasicDescription {
        AudioStreamBasicDescription(
            mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 32, mReserved: 0)
    }
}

/// What a unit is asked to do: the component, then parameters set after
/// initialisation (scope global, element 0), and for AUNBandEQ the bands.
struct UnitConfig {
    var label: String
    var desc: AudioComponentDescription
    var bands: [EQBand] = []
    var params: [(AudioUnitParameterID, Float)] = []

    static func eq(_ label: String, _ bands: [EQBand]) -> UnitConfig {
        UnitConfig(label: label, desc: AppleUnit.nBandEQ, bands: bands)
    }
}

/// Applies a config to a v2 unit (number of bands must be set before init).
func applyBands(_ unit: AudioUnit, _ bands: [EQBand], rate: Double) -> OSStatus {
    var st: OSStatus = noErr
    for (i, b) in bands.enumerated() {
        let e = AudioUnitParameterID(i)
        st |= AudioUnitSetParameter(unit, AudioUnitParameterID(kAUNBandEQParam_BypassBand) + e, kAudioUnitScope_Global, 0, 0, 0)
        st |= AudioUnitSetParameter(unit, AudioUnitParameterID(kAUNBandEQParam_FilterType) + e, kAudioUnitScope_Global, 0, AppleUnit.nbType(b.kind), 0)
        st |= AudioUnitSetParameter(unit, AudioUnitParameterID(kAUNBandEQParam_Frequency) + e, kAudioUnitScope_Global, 0, Float(b.freq), 0)
        st |= AudioUnitSetParameter(unit, AudioUnitParameterID(kAUNBandEQParam_Gain) + e, kAudioUnitScope_Global, 0, Float(b.gainDB), 0)
        st |= AudioUnitSetParameter(unit, AudioUnitParameterID(kAUNBandEQParam_Bandwidth) + e, kAudioUnitScope_Global, 0, Float(b.octaves(fs: rate)), 0)
    }
    return st
}

// MARK: - v2: AudioUnitRender with a C input callback

/// One Apple unit hosted the v2 way: created in `init` (never in the tap),
/// formats, max frames and the input callback set and the unit initialised
/// in `prepare`, then `AudioUnitRender` inside `process` with the tap's own
/// buffer list as the output. The input callback copies a snapshot of the
/// tap's input (taken just before the render) into whatever the unit asks
/// for.
final class V2Host: Stage {
    let name: String
    let config: UnitConfig
    let unit: AudioUnit
    private let ownsUnit: Bool
    private var input: PlanarBuffers?
    private var timeStamp = AudioTimeStamp()
    private var rate = 48000.0
    private(set) var maxSlice = 0
    private(set) var reportedLatency = 0.0
    private(set) var tail = 0.0
    var latency: Int { Int((reportedLatency * rate).rounded()) }
    var lastStatus: OSStatus = 0

    /// `unit` lets a caller hand over an existing instance (AVAudioUnitEQ's).
    init(_ config: UnitConfig, unit existing: AudioUnit? = nil) {
        self.config = config
        name = config.label
        if let existing {
            unit = existing
            ownsUnit = false
        } else {
            var d = config.desc
            let comp = AudioComponentFindNext(nil, &d)!
            var u: AudioUnit?
            let st = AudioComponentInstanceNew(comp, &u)
            precondition(st == noErr, "AudioComponentInstanceNew \(st)")
            unit = u!
            ownsUnit = true
        }
    }

    deinit {
        AudioUnitUninitialize(unit)
        if ownsUnit { AudioComponentInstanceDispose(unit) }
    }

    func prepare(channels: Int, sampleRate: Double, maxFrames: Int) -> String? {
        rate = sampleRate
        AudioUnitUninitialize(unit)
        var st: OSStatus
        if config.desc.componentSubType == kAudioUnitSubType_NBandEQ, !config.bands.isEmpty {
            var nb = UInt32(max(1, config.bands.count))
            st = AudioUnitSetProperty(unit, kAUNBandEQProperty_NumberOfBands, kAudioUnitScope_Global, 0, &nb, 4)
            if st != noErr { return "NumberOfBands \(st)" }
        }
        var f = AppleUnit.stream(channels: channels, rate: sampleRate)
        let sz = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        st = AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &f, sz)
        if st != noErr { return "input StreamFormat \(st)" }
        st = AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &f, sz)
        if st != noErr { return "output StreamFormat \(st)" }
        // At least what the tap promised, and never below 4096.
        var mf = UInt32(max(maxFrames, 4096))
        maxSlice = Int(mf)
        st = AudioUnitSetProperty(unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &mf, 4)
        if st != noErr { return "MaximumFramesPerSlice \(st)" }
        var cb = AURenderCallbackStruct(
            inputProc: v2InputProc, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        st = AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &cb,
                                  UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        if st != noErr { return "SetRenderCallback \(st)" }
        st = AudioUnitInitialize(unit)
        if st != noErr { return "AudioUnitInitialize \(st)" }
        if !config.bands.isEmpty {
            st = applyBands(unit, config.bands, rate: sampleRate)
            if st != noErr { return "bands \(st)" }
        }
        for (id, v) in config.params {
            st = AudioUnitSetParameter(unit, id, kAudioUnitScope_Global, 0, v, 0)
            if st != noErr { return "param \(id) \(st)" }
        }
        var lat = 0.0, t = 0.0
        var ls = UInt32(8)
        AudioUnitGetProperty(unit, kAudioUnitProperty_Latency, kAudioUnitScope_Global, 0, &lat, &ls)
        ls = 8
        AudioUnitGetProperty(unit, kAudioUnitProperty_TailTime, kAudioUnitScope_Global, 0, &t, &ls)
        reportedLatency = lat
        tail = t
        input = PlanarBuffers(channels: channels, capacity: maxSlice)
        reset()
        return nil
    }

    func reset() {
        AudioUnitReset(unit, kAudioUnitScope_Global, 0)
        timeStamp = AudioTimeStamp()
        timeStamp.mFlags = .sampleTimeValid
        timeStamp.mSampleTime = 0
    }

    func setParameter(_ id: AudioUnitParameterID, _ v: Float) {
        AudioUnitSetParameter(unit, id, kAudioUnitScope_Global, 0, v, 0)
    }

    func process(_ abl: UnsafeMutableAudioBufferListPointer, frames: Int) -> Int32 {
        guard let input else { return -1 }
        var off = 0
        while off < frames {
            let n = min(maxSlice, frames - off)
            // Snapshot this slice of the tap's buffer as the unit's input.
            input.setFrames(n)
            for c in 0..<min(abl.count, input.channels) {
                if let s = abl[c].mData { memcpy(input.data[c], s + off * 4, n * 4) }
            }
            // Render into the tap's own buffers at the slice's offset.
            var flags = AudioUnitRenderActionFlags()
            let st = withSlice(abl, offset: off, frames: n) { out in
                AudioUnitRender(unit, &flags, &timeStamp, 0, UInt32(n), out)
            }
            timeStamp.mSampleTime += Float64(n)
            if st != noErr { lastStatus = st; return st }
            off += n
        }
        return 0
    }

    /// Points the buffer list at `offset` for the duration of `body`, then
    /// restores it. No allocation: the list is rewritten in place.
    @inline(__always) private func withSlice(
        _ abl: UnsafeMutableAudioBufferListPointer, offset: Int, frames: Int,
        _ body: (UnsafeMutablePointer<AudioBufferList>) -> OSStatus
    ) -> OSStatus {
        if offset == 0 && Int(abl[0].mDataByteSize) == frames * 4 {
            return body(abl.unsafeMutablePointer)
        }
        let count = abl.count
        var saved: (UnsafeMutableRawPointer?, UInt32, UnsafeMutableRawPointer?, UInt32, UnsafeMutableRawPointer?, UInt32, UnsafeMutableRawPointer?, UInt32, UnsafeMutableRawPointer?, UInt32, UnsafeMutableRawPointer?, UInt32, UnsafeMutableRawPointer?, UInt32, UnsafeMutableRawPointer?, UInt32) =
            (nil, 0, nil, 0, nil, 0, nil, 0, nil, 0, nil, 0, nil, 0, nil, 0)
        withUnsafeMutableBytes(of: &saved) { raw in
            for c in 0..<min(count, 8) {
                raw.storeBytes(of: abl[c].mData, toByteOffset: c * 16, as: UnsafeMutableRawPointer?.self)
                raw.storeBytes(of: abl[c].mDataByteSize, toByteOffset: c * 16 + 8, as: UInt32.self)
                abl[c].mData = abl[c].mData.map { $0 + offset * 4 }
                abl[c].mDataByteSize = UInt32(frames * 4)
            }
        }
        let st = body(abl.unsafeMutablePointer)
        withUnsafeBytes(of: &saved) { raw in
            for c in 0..<min(count, 8) {
                abl[c].mData = raw.load(fromByteOffset: c * 16, as: UnsafeMutableRawPointer?.self)
                abl[c].mDataByteSize = raw.load(fromByteOffset: c * 16 + 8, as: UInt32.self)
            }
        }
        return st
    }

    /// The input callback's body: copy the snapshot into the unit's buffers,
    /// or lend it the snapshot's own when it asks for pointers.
    fileprivate func fill(_ io: UnsafeMutablePointer<AudioBufferList>, frames: Int) -> OSStatus {
        guard let input else { return -1 }
        let list = UnsafeMutableAudioBufferListPointer(io)
        for c in 0..<min(list.count, input.channels) {
            if let d = list[c].mData {
                memcpy(d, input.data[c], frames * 4)
            } else {
                list[c].mData = UnsafeMutableRawPointer(input.data[c])
            }
            list[c].mDataByteSize = UInt32(frames * 4)
        }
        return noErr
    }
}

private let v2InputProc: AURenderCallback = { refCon, _, _, _, frames, io in
    guard let io else { return -1 }
    return Unmanaged<V2Host>.fromOpaque(refCon).takeUnretainedValue().fill(io, frames: Int(frames))
}

// MARK: - v3: AUAudioUnit.renderBlock with a pull block built once

final class V3Host: Stage {
    let name: String
    let config: UnitConfig
    let au: AUAudioUnit
    private var input: PlanarBuffers?
    private var renderBlock: AURenderBlock?
    private var pull: AURenderPullInputBlock?
    /// The block-typed pair: the render block taken as the Objective-C
    /// object it is, and a pull block made once as a block. Calling one with
    /// the other passes two pointers; nothing is bridged per call.
    typealias PullC = @convention(block) (UnsafeMutablePointer<AudioUnitRenderActionFlags>, UnsafePointer<AudioTimeStamp>, AUAudioFrameCount, Int, UnsafeMutablePointer<AudioBufferList>) -> AUAudioUnitStatus
    typealias RenderC = @convention(block) (UnsafeMutablePointer<AudioUnitRenderActionFlags>, UnsafePointer<AudioTimeStamp>, AUAudioFrameCount, Int, UnsafeMutablePointer<AudioBufferList>, PullC?) -> AUAudioUnitStatus
    private var renderObject: AnyObject?
    private var renderC: RenderC?
    private var pullC: PullC?
    let blockTyped: Bool
    private var timeStamp = AudioTimeStamp()
    private var maxSlice = 4096
    let latency = 0

    init(_ config: UnitConfig, blockTyped: Bool = false) throws {
        self.config = config
        self.blockTyped = blockTyped
        name = config.label + (blockTyped ? " (v3, block-typed)" : " (v3)")
        au = try AUAudioUnit(componentDescription: config.desc, options: [])
    }

    func prepare(channels: Int, sampleRate: Double, maxFrames: Int) -> String? {
        au.deallocateRenderResources()
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channels))
        else { return "format" }
        do {
            try au.inputBusses[0].setFormat(fmt)
            try au.outputBusses[0].setFormat(fmt)
        } catch { return "setFormat \(error)" }
        maxSlice = max(maxFrames, 4096)
        au.maximumFramesToRender = AUAudioFrameCount(maxSlice)
        // The v2 bridge's input bus starts DISABLED: without this the render
        // block answers kAudioUnitErr_NoConnection (-10876) and never pulls.
        au.inputBusses[0].isEnabled = true
        do { try au.allocateRenderResources() } catch { return "allocateRenderResources \(error)" }
        if let tree = au.parameterTree {
            for (i, b) in config.bands.enumerated() {
                let e = AUParameterAddress(i)
                tree.parameter(withAddress: AUParameterAddress(kAUNBandEQParam_BypassBand) + e)?.value = 0
                tree.parameter(withAddress: AUParameterAddress(kAUNBandEQParam_FilterType) + e)?.value = AppleUnit.nbType(b.kind)
                tree.parameter(withAddress: AUParameterAddress(kAUNBandEQParam_Frequency) + e)?.value = Float(b.freq)
                tree.parameter(withAddress: AUParameterAddress(kAUNBandEQParam_Gain) + e)?.value = Float(b.gainDB)
                tree.parameter(withAddress: AUParameterAddress(kAUNBandEQParam_Bandwidth) + e)?.value = Float(b.octaves(fs: sampleRate))
            }
            for (id, v) in config.params { tree.parameter(withAddress: AUParameterAddress(id))?.value = v }
        }
        let buffers = PlanarBuffers(channels: channels, capacity: maxSlice)
        input = buffers
        renderBlock = au.renderBlock
        renderObject = au.value(forKey: "renderBlock") as AnyObject
        renderC = unsafeBitCast(renderObject!, to: RenderC.self)
        pullC = { _, _, frames, _, io in
            let list = UnsafeMutableAudioBufferListPointer(io)
            for c in 0..<min(list.count, buffers.channels) {
                if let d = list[c].mData {
                    memcpy(d, buffers.data[c], Int(frames) * 4)
                } else {
                    list[c].mData = UnsafeMutableRawPointer(buffers.data[c])
                }
                list[c].mDataByteSize = frames * 4
            }
            return noErr
        }
        // Built here, once: the render thread only ever passes this block on.
        pull = { _, _, frames, _, io in
            let list = UnsafeMutableAudioBufferListPointer(io)
            for c in 0..<min(list.count, buffers.channels) {
                if let d = list[c].mData {
                    memcpy(d, buffers.data[c], Int(frames) * 4)
                } else {
                    list[c].mData = UnsafeMutableRawPointer(buffers.data[c])
                }
                list[c].mDataByteSize = frames * 4
            }
            return noErr
        }
        reset()
        return nil
    }

    func reset() {
        au.reset()
        timeStamp = AudioTimeStamp()
        timeStamp.mFlags = .sampleTimeValid
    }

    func process(_ abl: UnsafeMutableAudioBufferListPointer, frames: Int) -> Int32 {
        guard let input, let renderBlock, let pull, frames <= maxSlice else { return -1 }
        for c in 0..<min(abl.count, input.channels) {
            if let s = abl[c].mData { memcpy(input.data[c], s, frames * 4) }
        }
        var flags = AudioUnitRenderActionFlags()
        let st: AUAudioUnitStatus
        if blockTyped, let renderC, let pullC {
            st = renderC(&flags, &timeStamp, AUAudioFrameCount(frames), 0, abl.unsafeMutablePointer, pullC)
        } else {
            st = renderBlock(&flags, &timeStamp, AUAudioFrameCount(frames), 0, abl.unsafeMutablePointer, pull)
        }
        timeStamp.mSampleTime += Float64(frames)
        return st
    }
}

// MARK: - AVAudioEngine, real-time manual rendering

final class EngineHost: Stage {
    let name: String
    let configs: [UnitConfig]
    private var engine: AVAudioEngine?
    private var units: [AVAudioUnit] = []
    private var input: PlanarBuffers?
    private var block: AVAudioEngineManualRenderingBlock?
    private var maxSlice = 4096
    let latency = 0

    init(_ name: String, _ configs: [UnitConfig]) {
        self.name = name
        self.configs = configs
    }

    func prepare(channels: Int, sampleRate: Double, maxFrames: Int) -> String? {
        engine?.stop()
        let engine = AVAudioEngine()
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channels))
        else { return "format" }
        maxSlice = max(maxFrames, 4096)
        do {
            try engine.enableManualRenderingMode(.realtime, format: fmt, maximumFrameCount: AVAudioFrameCount(maxSlice))
        } catch { return "enableManualRenderingMode \(error)" }
        units = configs.map { c -> AVAudioUnit in
            if c.desc.componentSubType == kAudioUnitSubType_NBandEQ {
                let eq = AVAudioUnitEQ(numberOfBands: max(1, c.bands.count))
                for (i, b) in c.bands.enumerated() {
                    let p = eq.bands[i]
                    p.bypass = false
                    p.filterType = AVAudioUnitEQFilterType(rawValue: Int(AppleUnit.nbType(b.kind)))!
                    p.frequency = Float(b.freq)
                    p.gain = Float(b.gainDB)
                    p.bandwidth = Float(b.octaves(fs: sampleRate))
                }
                return eq
            }
            let u = AVAudioUnitEffect(audioComponentDescription: c.desc)
            for (id, v) in c.params {
                AudioUnitSetParameter(u.audioUnit, id, kAudioUnitScope_Global, 0, v, 0)
            }
            return u
        }
        var previous: AVAudioNode = engine.inputNode
        for u in units {
            engine.attach(u)
            engine.connect(previous, to: u, format: fmt)
            previous = u
        }
        engine.connect(previous, to: engine.mainMixerNode, format: fmt)
        let buffers = PlanarBuffers(channels: channels, capacity: maxSlice)
        input = buffers
        let ok = engine.inputNode.setManualRenderingInputPCMFormat(fmt) { frames in
            buffers.setFrames(Int(frames))
            return UnsafePointer(buffers.abl.unsafeMutablePointer)
        }
        if !ok { return "setManualRenderingInputPCMFormat refused" }
        do { try engine.start() } catch { return "engine.start \(error)" }
        block = engine.manualRenderingBlock
        self.engine = engine
        return nil
    }

    func reset() { engine?.reset() }

    func process(_ abl: UnsafeMutableAudioBufferListPointer, frames: Int) -> Int32 {
        guard let input, let block, frames <= maxSlice else { return -1 }
        for c in 0..<min(abl.count, input.channels) {
            if let s = abl[c].mData { memcpy(input.data[c], s, frames * 4) }
        }
        var err: OSStatus = 0
        let status = block(AVAudioFrameCount(frames), abl.unsafeMutablePointer, &err)
        if status != .success { return err != 0 ? err : Int32(status.rawValue) + 1000 }
        return 0
    }
}

// MARK: - The AVAudioUnitEQ's own instance through v2

/// `AVAudioUnitEQ` outside any engine: its bands set through AVFoundation's
/// API, its `audioUnit` then hosted exactly as `V2Host` hosts a raw one.
final class AVEQv2Host: Stage {
    let name: String
    let eq: AVAudioUnitEQ
    let inner: V2Host
    var latency: Int { inner.latency }
    init(_ label: String, bands: [EQBand]) {
        name = label
        eq = AVAudioUnitEQ(numberOfBands: bands.count)
        inner = V2Host(UnitConfig(label: label, desc: AppleUnit.nBandEQ), unit: eq.audioUnit)
        self.bands = bands
    }
    let bands: [EQBand]
    func prepare(channels: Int, sampleRate: Double, maxFrames: Int) -> String? {
        if let e = inner.prepare(channels: channels, sampleRate: sampleRate, maxFrames: maxFrames) { return e }
        for (i, b) in bands.enumerated() {
            let p = eq.bands[i]
            p.bypass = false
            p.filterType = AVAudioUnitEQFilterType(rawValue: Int(AppleUnit.nbType(b.kind)))!
            p.frequency = Float(b.freq)
            p.gain = Float(b.gainDB)
            p.bandwidth = Float(b.octaves(fs: sampleRate))
        }
        return nil
    }
    func reset() { inner.reset() }
    func process(_ abl: UnsafeMutableAudioBufferListPointer, frames: Int) -> Int32 {
        inner.process(abl, frames: frames)
    }
}
