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
// One JSON object out: `rows`, each a name, ok and detail, the name starting
// with its L-number.
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
            + "amount 0; lookAmount and lookEnabled at 456 and 460 of 464 bytes",
        looked.lookAmount == 0.8 && looked.lookEnabled == 1 && none.lookEnabled == 0
            && none.lookAmount == 0 && zero.lookEnabled == 0 && stride == 464 && amount == 456
            && flag == 460,
        "looked \(looked.lookAmount)/\(looked.lookEnabled); none \(none.lookEnabled); zero "
            + "\(zero.lookEnabled); stride \(stride), amount at \(amount), flag at \(flag)")
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
        {"version": 1015, "canvas": {"width": 640, "height": 360, "fps": [30, 1]},
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
for kind in LookKind.allCases {
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
