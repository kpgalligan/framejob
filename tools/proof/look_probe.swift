// Road map "grading", phase GR5a — looks' probe (`look_proof.py` builds it
// through `swift_build.build` and runs it).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, against `libreelcut_core.a`, so every row drives the app's own
// types: `LookTextures` (its placeholder and its bake), `LayerUniforms.apply
// (look:)`, `ReelProject.recipe(at:)` and `RecipeLook`. The shader is the
// tree's `Compositor.metal`, read from `request.json`'s `shader` and compiled
// by `makeLibrary(source:)` together with the three probe kernels below, so
// `gradeLook` and `reelcut_look_bake` are the tree's own functions. Nothing
// private is widened.
//
//   look_probe <request.json> <answer.json>
//
// GR5b adds B1–B4, over the app's chrome: `AppDelegate.lookMenu()`, the
// validator `EditorViewController.validateLookAction`, `LookGallery`'s pure
// answers and the Color tab's Look section in a headless `ClipPane`.
//
// One JSON object out: `rows`, each a name, ok and detail, the name starting
// with its L- or B-number.
import AppKit
import Metal

let request = (try? JSONSerialization.jsonObject(
    with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))) as? [String: Any]
    ?? [:]
let out = URL(fileURLWithPath: CommandLine.arguments[2])

var rows: [[String: Any]] = []
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    rows.append(["name": name, "ok": ok, "detail": String(detail.prefix(1200))])
}

func finish() -> Never {
    let answer: [String: Any] = ["rows": rows]
    if let data = try? JSONSerialization.data(withJSONObject: answer, options: [.prettyPrinted]) {
        try? data.write(to: out)
    }
    exit(0)
}

// MARK: - L3 the uniforms

do {
    var looked = LayerUniforms()
    looked.apply(look: RecipeLook(amount: 0.8, definition: .identity))
    var none = LayerUniforms()
    none.apply(look: nil)
    var zero = LayerUniforms()
    zero.apply(look: RecipeLook(amount: 0, definition: .identity))
    let stride = MemoryLayout<LayerUniforms>.stride
    let amount = MemoryLayout<LayerUniforms>.offset(of: \LayerUniforms.lookAmount) ?? -1
    let flag = MemoryLayout<LayerUniforms>.offset(of: \LayerUniforms.lookEnabled) ?? -1
    check(
        "L3 apply(look:) writes amount 0.8 and flag 1 for a look at 0.8, flag 0 for none and for "
            + "amount 0; lookAmount and lookEnabled at 456 and 460 of 512 bytes",
        looked.lookAmount == 0.8 && looked.lookEnabled == 1 && none.lookEnabled == 0
            && none.lookAmount == 0 && zero.lookEnabled == 0 && stride == 512 && amount == 456
            && flag == 460,
        "looked \(looked.lookAmount)/\(looked.lookEnabled); none \(none.lookEnabled); zero "
            + "\(zero.lookEnabled); stride \(stride), amount at \(amount), flag at \(flag)")
}

// MARK: - GR5b: the chrome (B1–B4)
//
// `request.json` names `package` (project MG, saved over MCP: MOVIE {warm,
// 0.5} at 0, IM at 2 s with no look, TX, AJ) and `cool` (the same project with
// IM at {cool, 0.5}), and `clips` (movie, image, text, adjustment → id). The
// app is bootstrapped as `tone_probe.swift` and `e2_chrome.py` do; a tile is
// driven by `sendAction(tile.action, to: tile.target)` and the inspector is
// headless (no window), so no thumbnail renders and no default is written.

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let delegate = AppDelegate()
delegate.applicationWillFinishLaunching(
    Notification(name: NSApplication.willFinishLaunchingNotification, object: app))

let bClips = (request["clips"] as? [String: NSNumber] ?? [:]).mapValues(\.uint32Value)
func bOpened(_ key: String) -> ProjectDocument? {
    guard let path = request[key] as? String else { return nil }
    let document = ProjectDocument()
    do {
        try document.read(
            from: URL(fileURLWithPath: path), ofType: "com.kgalligan.reelcut-project")
    } catch {
        return nil
    }
    return document
}
func bWalk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(bWalk) }
func bParsed(_ op: ReelOp) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(op.json.utf8))) as? [String: Any] ?? [:]
}
func bState(_ value: NSControl.StateValue) -> String {
    value == .on ? "on" : (value == .mixed ? "mixed" : "off")
}
func bIds(_ names: [String]) -> Set<UInt32> { Set(names.compactMap { bClips[$0] }) }
let bNames = LookKind.builtIns.map(\.displayName)

// B1 the menu
do {
    let menu = delegate.lookMenu()
    let titles = menu.items.map { $0.isSeparatorItem ? "" : $0.title }
    let tags = menu.items.filter { !$0.isSeparatorItem }.map(\.tag)
    let keys = menu.items.map(\.keyEquivalent).filter { !$0.isEmpty }
    let actions = Set(menu.items.filter { !$0.isSeparatorItem }.compactMap {
        $0.action.map(NSStringFromSelector)
    })
    let clip = NSApp.mainMenu?.items.first { $0.title == "Clip" }?.submenu
    let order = clip?.items.map(\.title) ?? []
    let motion = order.firstIndex(of: "Motion")
    let look = order.firstIndex(of: "Look")
    check(
        "B1 lookMenu() is the eight names, a separator, None; tags 0…7 and −1; no key "
            + "equivalents; Clip ▸ Look follows Motion",
        titles == bNames + ["", "None"] && tags == Array(0..<8) + [-1] && keys.isEmpty
            && actions == ["setLook:"] && motion != nil && look == motion.map { $0 + 1 },
        "titles \(titles); tags \(tags); keys \(keys); actions \(actions); Clip \(order)")
}

// B2 the validation
do {
    let plain = bOpened("package")
    let cool = bOpened("cool")
    if let plain, let cool, bClips.count == 4 {
        // name, document, selection, the states wanted (kind or "None" → state), enabled
        let cases: [(String, ProjectDocument, [String], [String: String], Bool)] = [
            ("[MOVIE]", plain, ["movie"], ["Warm": "on"], true),
            ("[MOVIE, IM+cool]", cool, ["movie", "image"], ["Warm": "mixed", "Cool": "mixed"], true),
            ("[MOVIE, IM]", plain, ["movie", "image"], ["Warm": "mixed", "None": "mixed"], true),
            ("[IM]", plain, ["image"], ["None": "on"], true),
            ("[TX]", plain, ["text"], [:], false),
            ("[TX, MOVIE]", plain, ["text", "movie"], ["Warm": "on"], true),
            ("[AJ]", plain, ["adjustment"], ["None": "on"], true),
        ]
        var misses: [String] = []
        for (name, document, selection, want, enabled) in cases {
            document.selection = bIds(selection)
            let controller = EditorViewController(document: document)
            for (index, title) in (bNames + ["None"]).enumerated() {
                let item = NSMenuItem(
                    title: title, action: #selector(EditorViewController.setLook(_:)),
                    keyEquivalent: "")
                item.tag = index < 8 ? index : -1
                let on = controller.validateUserInterfaceItem(item)
                let state = bState(item.state)
                let wanted = enabled ? (want[title] ?? "off") : state
                if on != enabled || state != wanted {
                    misses.append("\(name) \(title): enabled \(on) state \(state)")
                }
            }
        }
        check(
            "B2 validation: [MOVIE] Warm on; [MOVIE, IM+cool] Warm, Cool mixed; [MOVIE, IM] Warm, "
                + "None mixed; [IM] None on; [TX] disabled; [TX, MOVIE] Warm on; [AJ] enabled",
            misses.isEmpty, misses.isEmpty ? "" : misses.joined(separator: "; "))
    } else {
        check("B2 the request names both packages and four clips", false, "\(request)")
    }
}

// B3 the pure answers
do {
    let warm8 = LookProps(kind: .warm, amount: 0.8)
    let summaries = [
        LookGallery.summary([warm8, warm8]), LookGallery.summary([nil, nil]),
        LookGallery.summary([warm8, LookProps(kind: .cool, amount: 0.8)]),
        LookGallery.summary([warm8, LookProps(kind: .warm, amount: 0.5)]),
        LookGallery.summary([warm8, nil]),
    ]
    let shared = [
        LookGallery.shared([warm8, LookProps(kind: .warm, amount: 0.5)]),
        LookGallery.shared([nil, nil]), LookGallery.shared([warm8, nil]),
        LookGallery.shared([warm8, LookProps(kind: .cool)]), LookGallery.shared([]),
    ]
    let sharedOk = shared[0] == .some(.warm) && shared[1] == .some(nil) && shared[2] == nil
        && shared[3] == nil && shared[4] == nil
    let set = bParsed(LookGallery.op(.tealOrange, clips: [3, 5]))
    let none = bParsed(LookGallery.op(nil, clips: [3]))
    let wantSet: NSDictionary = ["look": ["kind": "teal_orange"]]
    let opOk = set["op"] as? String == "set_video"
        && (set["clips"] as? [NSNumber])?.map(\.uint32Value) == [3, 5]
        && (set["patch"] as? NSDictionary) == wantSet
        && ((none["patch"] as? [String: Any])?["look"] is NSNull)
    var times: [Ticks] = []
    if let document = bOpened("package"), let movie = bClips["movie"], let image = bClips["image"],
       let m = document.project.snapshot.clips.first(where: { $0.id == movie }),
       let i = document.project.snapshot.clips.first(where: { $0.id == image })
    {
        let second: Ticks = 600_000
        times = [
            LookGallery.time(first: m, playhead: second / 2),
            LookGallery.time(first: m, playhead: m.end),
            LookGallery.time(first: i, playhead: second),
            LookGallery.time(first: i, playhead: i.start + second / 4),
            m.start, i.start,
        ]
    }
    let timeOk = times.count == 6 && times[0] == 300_000 && times[1] == times[4]
        && times[2] == times[5] && times[3] == times[5] + 150_000
    check(
        "B3 summary \"Warm 80%\", \"none\", \"mixed\" by kind, by amount and by a missing look; "
            + "shared; time (inside, at the end, before the clip); op's JSON has no amount",
        summaries == ["Warm 80%", "none", "mixed", "mixed", "mixed"] && sharedOk && opOk
            && timeOk,
        "summaries \(summaries); shared \(shared); op \(set) / \(none); times \(times)")
}

// B4 the section
do {
    if let cool = bOpened("cool"), let plain = bOpened("package"), bClips.count == 4 {
        let inspector = InspectorViewController()
        var sent: [(String, [ReelOp])] = []
        func pane(_ document: ProjectDocument, _ selection: [String]) -> ClipPane {
            inspector.document = document
            inspector.onEdit = { name, ops in
                sent.append((name, ops))
                document.applyEdit(name, ops)
            }
            document.selection = bIds(selection)
            inspector.binding.invalidate()
            let pane = ClipPane(inspector: inspector)
            pane.binding.invalidate()
            pane.choose(.color)
            pane.rebuild()
            pane.refresh()
            return pane
        }
        func gallery(_ pane: ClipPane) -> LookGalleryView? {
            pane.sections.first { $0.id == "video.look" }.flatMap { section in
                bWalk(section).lazy.compactMap { $0 as? LookGalleryView }.first
            }
        }
        func outlined(_ pane: ClipPane) -> [String] {
            gallery(pane)?.tiles.filter(\.isOutlined).map { $0.kind?.displayName ?? "None" } ?? ["?"]
        }
        func look(_ document: ProjectDocument, _ name: String) -> LookProps? {
            document.project.snapshot.clips.first { $0.id == bClips[name] }?.videoProps.look
        }
        let movieSections = pane(cool, ["movie"]).sections.map(\.id)
        let adjustmentSections = pane(cool, ["adjustment"]).sections.map(\.id)
        let movieOutline = outlined(pane(cool, ["movie"]))
        let mixedOutline = outlined(pane(cool, ["movie", "image"]))
        let image = pane(cool, ["image"])
        let tiles = gallery(image)?.tiles ?? []
        sent = []
        if let warm = tiles.first(where: { $0.kind == .warm }) {
            warm.sendAction(warm.action, to: warm.target)
        }
        let warmSent = sent
        let warmOp = warmSent.first.flatMap { $0.1.count == 1 ? bParsed($0.1[0]) : nil } ?? [:]
        let afterWarm = look(cool, "image")
        let wantWarm: NSDictionary = ["look": ["kind": "warm"]]
        let warmOk = warmSent.count == 1 && warmSent.first?.0 == "Look"
            && warmOp["op"] as? String == "set_video"
            && (warmOp["clips"] as? [NSNumber])?.map(\.uint32Value) == [bClips["image"] ?? 0]
            && (warmOp["patch"] as? NSDictionary) == wantWarm
            && afterWarm == LookProps(kind: .warm, amount: 0.5)
        let after = pane(cool, ["image"])
        sent = []
        if let noneTile = gallery(after)?.tiles.first(where: { $0.kind == nil }) {
            noneTile.sendAction(noneTile.action, to: noneTile.target)
        }
        let noneOp = sent.first.flatMap { $0.1.count == 1 ? bParsed($0.1[0]) : nil } ?? [:]
        let noneOk = sent.count == 1 && sent.first?.0 == "Look"
            && ((noneOp["patch"] as? [String: Any])?["look"] is NSNull)
            && look(cool, "image") == nil
        let imageOutline = outlined(pane(plain, ["image"]))
        check(
            "B4 Color sections [light, color, wheels, curves, look] (AJ: adjustment, then "
                + "qualifier, first); Warm on "
                + "IM+{cool, 0.5} "
                + "sends one set_video {look: {kind: warm}} named \"Look\" and IM reads {warm, "
                + "0.5}; None sends {look: null}; outlines [MOVIE] Warm, [MOVIE, IM+cool] none, "
                + "[IM] None",
            movieSections == ["video.light", "video.color", "video.wheels", "video.curves",
                              "video.look"]
                && adjustmentSections == ["video.adjustment", "video.qualifier", "video.light",
                                          "video.color", "video.wheels", "video.curves",
                                          "video.look"]
                && tiles.count == 9 && warmOk && noneOk && movieOutline == ["Warm"]
                && mixedOutline.isEmpty && imageOutline == ["None"],
            "sections \(movieSections) / \(adjustmentSections); tiles \(tiles.count); warm "
                + "\(warmSent.map { ($0.0, $0.1.map(\.json)) }) → \(String(describing: afterWarm)); "
                + "none \(noneOp); outlines \(movieOutline) \(mixedOutline) \(imageOutline)")
    } else {
        check("B4 the request names both packages and four clips", false, "\(request)")
    }
}

// MARK: - The library: the tree's shader and the probe's kernels

let kernels = """

    // ---- look_probe.swift's kernels ----
    kernel void probe_look_identity(texture3d<float> look [[texture(0)]],
                                    sampler samp [[sampler(0)]],
                                    constant LayerUniforms &u [[buffer(0)]],
                                    device atomic_uint *misses [[buffer(1)]],
                                    uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= 4096 || gid.y >= 4096) {
            return;
        }
        uint index = gid.y * 4096 + gid.x;
        uint3 want = uint3(index >> 16, (index >> 8) & 255u, index & 255u);
        float3 got = gradeLook(float3(want) / 255.0, look, samp, u);
        uint3 back = uint3(round(saturate(got) * 255.0));
        if (any(back != want)) {
            atomic_fetch_add_explicit(misses, 1u, memory_order_relaxed);
        }
    }

    kernel void probe_look_samples(texture3d<float> look [[texture(0)]],
                                   sampler samp [[sampler(0)]],
                                   constant LayerUniforms &u [[buffer(0)]],
                                   device const float4 *inputs [[buffer(1)]],
                                   device float4 *outputs [[buffer(2)]],
                                   uint gid [[thread_position_in_grid]]) {
        outputs[gid] = float4(gradeLook(inputs[gid].rgb, look, samp, u), 1.0);
    }

    kernel void probe_look_read(texture3d<float> look [[texture(0)]],
                                device float4 *texels [[buffer(0)]],
                                uint3 gid [[thread_position_in_grid]]) {
        uint n = look.get_width();
        if (gid.x >= n || gid.y >= n || gid.z >= n) {
            return;
        }
        texels[(gid.z * n + gid.y) * n + gid.x] = look.read(gid);
    }
    """

let lRows = ["L1", "L2", "L4", "L5"]
func failAll(_ why: String) -> Never {
    for name in lRows { check("\(name) the Metal setup", false, why) }
    finish()
}

guard let shaderPath = request["shader"] as? String,
    let shader = try? String(contentsOfFile: shaderPath, encoding: .utf8)
else { failAll("no shader at \(request["shader"] ?? "nil")") }
guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue()
else { failAll("no Metal device") }
let library: MTLLibrary
do {
    library = try device.makeLibrary(source: shader + kernels, options: nil)
} catch {
    failAll("the tree's shader with the probe kernels did not compile: \(error)")
}
guard let looks = LookTextures(device: device, library: library) else {
    failAll("LookTextures(device:library:) answered nil")
}
func pipeline(_ name: String) -> MTLComputePipelineState? {
    library.makeFunction(name: name).flatMap { try? device.makeComputePipelineState(function: $0) }
}
let samplerDescriptor = MTLSamplerDescriptor()
samplerDescriptor.minFilter = .linear
samplerDescriptor.magFilter = .linear
samplerDescriptor.sAddressMode = .clampToEdge
samplerDescriptor.tAddressMode = .clampToEdge
guard let identityKernel = pipeline("probe_look_identity"),
    let samplesKernel = pipeline("probe_look_samples"),
    let readKernel = pipeline("probe_look_read"),
    let sampler = device.makeSamplerState(descriptor: samplerDescriptor)
else { failAll("a probe kernel or the sampler could not be made") }

/// The uniforms a full look reads at step 4d.
var full = LayerUniforms()
full.apply(look: RecipeLook(amount: 1, definition: .identity))

func run(_ encode: (MTLComputeCommandEncoder) -> Void) -> Bool {
    guard let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeComputeCommandEncoder()
    else { return false }
    encode(encoder)
    encoder.endEncoding()
    buffer.commit()
    buffer.waitUntilCompleted()
    return buffer.status == .completed
}

/// How many of the 16,777,216 8-bit colours `lattice` does not return as
/// themselves through `gradeLook`; nil when the GPU did not answer.
func misses(_ lattice: MTLTexture) -> UInt32? {
    guard let counter = device.makeBuffer(length: 4, options: .storageModeShared) else { return nil }
    counter.contents().storeBytes(of: UInt32(0), as: UInt32.self)
    var u = full
    let ran = run { encoder in
        encoder.setComputePipelineState(identityKernel)
        encoder.setTexture(lattice, index: 0)
        encoder.setSamplerState(sampler, index: 0)
        encoder.setBytes(&u, length: MemoryLayout<LayerUniforms>.stride, index: 0)
        encoder.setBuffer(counter, offset: 0, index: 1)
        encoder.dispatchThreads(
            MTLSize(width: 4096, height: 4096, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
    }
    return ran ? counter.contents().load(as: UInt32.self) : nil
}

/// `gradeLook` through `lattice` at each of `inputs`.
func samples(_ lattice: MTLTexture, _ inputs: [SIMD4<Float>]) -> [SIMD4<Float>]? {
    let size = MemoryLayout<SIMD4<Float>>.stride * inputs.count
    guard let input = device.makeBuffer(bytes: inputs, length: size, options: .storageModeShared),
        let output = device.makeBuffer(length: size, options: .storageModeShared)
    else { return nil }
    var u = full
    let ran = run { encoder in
        encoder.setComputePipelineState(samplesKernel)
        encoder.setTexture(lattice, index: 0)
        encoder.setSamplerState(sampler, index: 0)
        encoder.setBytes(&u, length: MemoryLayout<LayerUniforms>.stride, index: 0)
        encoder.setBuffer(input, offset: 0, index: 1)
        encoder.setBuffer(output, offset: 0, index: 2)
        encoder.dispatchThreads(
            MTLSize(width: inputs.count, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
    }
    guard ran else { return nil }
    let pointer = output.contents().bindMemory(to: SIMD4<Float>.self, capacity: inputs.count)
    return Array(UnsafeBufferPointer(start: pointer, count: inputs.count))
}

/// Every texel of `lattice`, x fastest.
func texels(_ lattice: MTLTexture) -> [SIMD4<Float>]? {
    let n = lattice.width
    let size = MemoryLayout<SIMD4<Float>>.stride * n * n * n
    guard let output = device.makeBuffer(length: size, options: .storageModeShared) else { return nil }
    let ran = run { encoder in
        encoder.setComputePipelineState(readKernel)
        encoder.setTexture(lattice, index: 0)
        encoder.setBuffer(output, offset: 0, index: 0)
        encoder.dispatchThreads(
            MTLSize(width: n, height: n, depth: n),
            threadsPerThreadgroup: MTLSize(width: 4, height: 4, depth: 4))
    }
    guard ran else { return nil }
    let pointer = output.contents().bindMemory(to: SIMD4<Float>.self, capacity: n * n * n)
    return Array(UnsafeBufferPointer(start: pointer, count: n * n * n))
}

// MARK: - L1, L2 the identity

let placeholder = looks.texture(for: nil)
let neutral = looks.bake(.identity)
let placeholderMisses = misses(placeholder)
let neutralMisses = neutral.flatMap { misses($0) }
check(
    "L1 the 2³ placeholder and a neutral 33³ bake through gradeLook return all 16,777,216 "
        + "8-bit colours as themselves",
    placeholder.width == 2 && placeholder.depth == 2 && neutral?.width == 33
        && neutral?.depth == 33 && placeholderMisses == 0 && neutralMisses == 0,
    "placeholder \(placeholder.width)³ misses \(placeholderMisses.map(String.init) ?? "nil"); "
        + "bake \(neutral.map { "\($0.width)³" } ?? "nil") misses "
        + "\(neutralMisses.map(String.init) ?? "nil")")

if let neutral, let read = texels(neutral) {
    let n = neutral.width
    var worst: Float = 0
    var at = (0, 0, 0)
    for z in 0..<n {
        for y in 0..<n {
            for x in 0..<n {
                let texel = read[(z * n + y) * n + x]
                let want = SIMD4<Float>(Float(x), Float(y), Float(z), Float(n - 1)) / Float(n - 1)
                let d = texel - want
                let error = max(abs(d.x), abs(d.y), abs(d.z), abs(d.w))
                if error > worst {
                    worst = error
                    at = (x, y, z)
                }
            }
        }
    }
    check(
        "L2 the neutral bake's \(n * n * n) texels equal their coordinates (and alpha 1) within "
            + "1e-4", read.count == n * n * n && worst <= 1e-4,
        "worst \(worst) at \(at)")
} else {
    check("L2 the neutral bake reads back", false)
}

// MARK: - L4, L5 the eight, as the core defines them

/// `kind`'s definition, read off the core's recipe for a one-clip project.
func definition(_ kind: LookKind) -> LookDefinition? {
    let json = """
        {"version": 15, "canvas": {"width": 640, "height": 360, "fps": [30, 1]},
         "media": [{"id": 1, "path": "/m/probe.mov", "kind": "video", "duration": 6000000,
                    "width": 640, "height": 360, "fps": [30, 1], "has_video": true,
                    "has_audio": false}],
         "tracks": [{"id": 4, "name": "Track 1"}],
         "clips": [{"id": 10, "track": 4, "start": 0, "duration": 600000, "speed": 1.0,
                    "source": {"kind": "media", "media": 1, "in": 0},
                    "enabled": {"video": true, "audio": false},
                    "video": {"look": {"kind": "\(kind.rawValue)"}}}],
         "next_id": 20}
        """
    guard let project = try? ReelProject.from(json: json), let recipe = project.recipe(at: 0)
    else { return nil }
    return recipe.layers.first { $0.clip == 10 }?.look?.definition
}

var timings: [String] = []
var definitions: [LookKind: LookDefinition] = [:]
for kind in LookKind.builtIns {
    guard let found = definition(kind) else {
        timings.append("\(kind.rawValue) no definition")
        continue
    }
    definitions[kind] = found
    let started = CFAbsoluteTimeGetCurrent()
    let baked = looks.bake(found)
    let ms = (CFAbsoluteTimeGetCurrent() - started) * 1000
    timings.append("\(kind.rawValue) \(baked == nil ? "FAILED" : String(format: "%.2f ms", ms))")
}
check(
    "L4 RECORD the eight 33³ bakes, each waited for: " + timings.joined(separator: ", "),
    definitions.count == 8, timings.joined(separator: ", "))

if let teal = definitions[.tealOrange], let lattice = looks.bake(teal),
    let answered = samples(lattice, [SIMD4<Float>(0.2, 0.2, 0.2, 1), SIMD4<Float>(0.8, 0.8, 0.8, 1)])
{
    let dark = answered[0], light = answered[1]
    check(
        "L5 teal_orange's lattice (split \(teal.split.shadowHue)° / \(teal.split.highlightHue)°): "
            + "B > R at grey 0.2 and R > B at grey 0.8",
        dark.z > dark.x && light.x > light.z,
        "grey 0.2 → \(dark); grey 0.8 → \(light)")
} else {
    check("L5 teal_orange's definition was read and baked", false, "\(definitions.keys)")
}

finish()
