import CoreML
import Vision

/// A Vision analysis kind's compute device (spec §11 CO-11, CJ-32; road map
/// "creator-jobs" CJ3's toll, a pure move out of `AnalysisMasks.swift`): the
/// three devices every supported Mac has, a request pinned to one on every
/// stage it supports, and the devices it reads back — the stamp's `device`,
/// which a job compares before each request it runs.
enum AnalysisVision {

    enum Device: String { case cpu, gpu, neuralEngine = "neural_engine" }

    /// Sets `device` on every stage the request supports and answers the
    /// devices it reads back (sorted, `+`-joined; `auto` for a stage left
    /// unset).
    static func pin(_ request: VNRequest, to device: Device) -> String {
        guard let stages = try? request.supportedComputeStageDevices else { return "unavailable" }
        var names = Set<String>()
        for (stage, devices) in stages {
            if let pick = devices.first(where: { name(of: $0) == device.rawValue }) {
                request.setComputeDevice(pick, for: stage)
            }
            names.insert(request.computeDevice(for: stage).map(name(of:)) ?? "auto")
        }
        return names.isEmpty ? "auto" : names.sorted().joined(separator: "+")
    }

    static func name(of device: MLComputeDevice) -> String {
        switch device {
        case .cpu: return Device.cpu.rawValue
        case .gpu: return Device.gpu.rawValue
        case .neuralEngine: return Device.neuralEngine.rawValue
        @unknown default: return "unknown"
        }
    }
}
