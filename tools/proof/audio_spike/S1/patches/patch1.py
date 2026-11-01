import sys

d = sys.argv[1]
p = d + '/AppleHost.swift'
s = open(p).read()
old_head = """    private var renderBlock: AURenderBlock?
    private var pull: AURenderPullInputBlock?
    private var timeStamp = AudioTimeStamp()
    private var maxSlice = 4096
    let latency = 0

    init(_ config: UnitConfig) throws {
        self.config = config
        name = config.label + " (v3)"
        au = try AUAudioUnit(componentDescription: config.desc, options: [])
    }
"""
new_head = """    private var renderBlock: AURenderBlock?
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
"""
assert old_head in s
s = s.replace(old_head, new_head)
old = """        au.maximumFramesToRender = AUAudioFrameCount(maxSlice)
        do { try au.allocateRenderResources() }"""
assert old in s
s = s.replace(old, """        au.maximumFramesToRender = AUAudioFrameCount(maxSlice)
        // The v2 bridge's input bus starts DISABLED: without this the render
        // block answers kAudioUnitErr_NoConnection (-10876) and never pulls.
        au.inputBusses[0].isEnabled = true
        do { try au.allocateRenderResources() }""")
old_pull = """        renderBlock = au.renderBlock
        // Built here, once: the render thread only ever passes this block on.
        pull = { _, _, frames, _, io in"""
new_pull = """        renderBlock = au.renderBlock
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
        pull = { _, _, frames, _, io in"""
assert old_pull in s
s = s.replace(old_pull, new_pull)
old_call = """        var flags = AudioUnitRenderActionFlags()
        let st = renderBlock(&flags, &timeStamp, AUAudioFrameCount(frames), 0, abl.unsafeMutablePointer, pull)"""
new_call = """        var flags = AudioUnitRenderActionFlags()
        let st: AUAudioUnitStatus
        if blockTyped, let renderC, let pullC {
            st = renderC(&flags, &timeStamp, AUAudioFrameCount(frames), 0, abl.unsafeMutablePointer, pullC)
        } else {
            st = renderBlock(&flags, &timeStamp, AUAudioFrameCount(frames), 0, abl.unsafeMutablePointer, pull)
        }"""
assert old_call in s
s = s.replace(old_call, new_call)
open(p, 'w').write(s)

p = d + '/main.swift'
s = open(p).read()
s = s.replace('''    case ("v3", "limiter"): return try? V3Host(limiterCfg())''', '''    case ("v3b", "limiter"): return try? V3Host(limiterCfg(), blockTyped: true)
    case ("v3b", "dyn"): return try? V3Host(bothCfg, blockTyped: true)
    case ("v3b", "peak"): return try? V3Host(.eq("AUNBandEQ peak", [PEAK]), blockTyped: true)
    case ("v3", "limiter"): return try? V3Host(limiterCfg())''')
s = s.replace('''let OTHER_KEYS = ["aveq.eq6", "v3.limiter", "v3.dyn", "v3.peak", ''', '''let OTHER_KEYS = ["aveq.eq6", "v3.limiter", "v3.dyn", "v3.peak", "v3b.limiter", "v3b.dyn", "v3b.peak", ''')
s = s.replace('''let args = CommandLine.arguments''', '''/// The instrument's positive control: things that MUST be counted.
func cmdControl() {
    let b = UnsafeMutablePointer<Int>.allocate(capacity: 5), a = UnsafeMutablePointer<Int>.allocate(capacity: 5)
    func probe(_ label: String, _ body: () -> Void) {
        var c = RTCounts()
        RTCheck.read(b); RTCheck.arm(); body(); RTCheck.disarm(); RTCheck.read(a)
        c.add(before: b, after: a)
        print(String(format: "%-34@ %@", label as NSString, c.description))
    }
    let lock = NSLock()
    var unfair = os_unfair_lock()
    let sem = DispatchSemaphore(value: 1)
    let q = DispatchQueue(label: "q")
    probe("nothing") {}
    probe("[Int](repeating:count: 1000)") { let x = [Int](repeating: 1, count: 1000); _ = x.count }
    probe("NSLock lock/unlock") { lock.lock(); lock.unlock() }
    probe("os_unfair_lock") { os_unfair_lock_lock(&unfair); os_unfair_lock_unlock(&unfair) }
    probe("DispatchSemaphore wait/signal") { sem.wait(); sem.signal() }
    probe("DispatchQueue.sync") { q.sync {} }
    probe("String interpolation") { let s = "x\\(Int.random(in: 0...1000))y"; _ = s.count }
}

let args = CommandLine.arguments''')
s = s.replace('''case "params": cmdParams()''', '''case "params": cmdParams()
case "control": cmdControl()''')
open(p, 'w').write(s)
print("patched")
