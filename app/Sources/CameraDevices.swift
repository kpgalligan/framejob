import AVFoundation
import AppKit

/// The cameras (camera-recording CR1a, spec §11 CAM-3): which are connected,
/// what each offers, which one a name or id means, which is the default, and
/// the format a recording is made at. Only `connected()`, `facts(of:)` and
/// `device(withID:)` touch the framework; the rule, the spelling, the rate,
/// the lookup and the default are PURE functions over `CameraDeviceFacts`,
/// so `tools/proof/camera_recording_probe.py` pins them on CR0's own format
/// lists without a camera.
///
/// **No Continuity key** (CR0's D2): the discovery asks for
/// `.builtInWideAngleCamera` and `.external` only — never `.continuityCamera`,
/// and the Info.plist has no `NSCameraUseContinuityCameraDeviceType` — and an
/// iPhone's Continuity Camera is listed all the same. Listing a device opens
/// nothing and needs no grant.

/// One format as the recorder reads it: its size and its highest frame rate.
struct CameraFormatFacts: Equatable {
    let width: Int
    let height: Int
    let maxRate: Double
}

/// One connected camera as the recorder reads it. `formats` is the device's
/// own list, in its own order; `activeFormat` an index into it.
struct CameraDeviceFacts: Equatable {
    let uniqueID: String
    let name: String
    let isBuiltIn: Bool
    let formats: [CameraFormatFacts]
    let activeFormat: Int?
}

enum CameraDevices {
    /// The cameras connected now, the discovery session's own order.
    static func connected() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external], mediaType: .video,
            position: .unspecified
        ).devices
    }

    /// `device`'s facts: each format's dimensions and the highest maximum of
    /// its frame-rate ranges, and the index of the active one.
    static func facts(of device: AVCaptureDevice) -> CameraDeviceFacts {
        let formats = device.formats.map { format -> CameraFormatFacts in
            let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let rate = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
            return CameraFormatFacts(width: Int(size.width), height: Int(size.height), maxRate: rate)
        }
        return CameraDeviceFacts(
            uniqueID: device.uniqueID, name: device.localizedName,
            isBuiltIn: device.deviceType == .builtInWideAngleCamera, formats: formats,
            activeFormat: device.formats.firstIndex { $0 == device.activeFormat })
    }

    /// The connected camera whose `uniqueID` is `id`, or nil.
    static func device(withID id: String) -> AVCaptureDevice? {
        connected().first { $0.uniqueID == id }
    }

    // MARK: - The format (CAM-3)

    /// CAM-3's best format: CAM-2's rule over the formats WIDER THAN TALL;
    /// if none qualifies, CAM-2's rule over every format; if that finds none
    /// either, `active`. An index into `formats`, or nil.
    static func bestFormat(_ formats: [CameraFormatFacts], active: Int?) -> Int? {
        let landscape = formats.indices.filter { formats[$0].width > formats[$0].height }
        return largest(formats, among: landscape)
            ?? largest(formats, among: Array(formats.indices)) ?? active
    }

    /// CAM-2's rule over `indices`: the largest width × height whose maximum
    /// rate is ≥ 30, ties to the higher maximum rate, then to the format
    /// listed first.
    private static func largest(_ formats: [CameraFormatFacts], among indices: [Int]) -> Int? {
        var best: Int?
        for index in indices where formats[index].maxRate >= 30 {
            guard let current = best else {
                best = index
                continue
            }
            let area = formats[index].width * formats[index].height
            let bestArea = formats[current].width * formats[current].height
            if area > bestArea
                || (area == bestArea && formats[index].maxRate > formats[current].maxRate)
            {
                best = index
            }
        }
        return best
    }

    /// The canvas rate of a new project made around a recording at `format`:
    /// its maximum rate, rounded, at least 1 (CAM-3's Canvas).
    static func canvasRate(_ format: CameraFormatFacts) -> Int {
        max(1, Int(format.maxRate.rounded()))
    }

    /// `1920x1080@30` — the format as the result and the tool spell it, the
    /// rate written `%g`.
    static func spelled(_ format: CameraFormatFacts) -> String {
        "\(format.width)x\(format.height)@" + String(format: "%g", format.maxRate)
    }

    // MARK: - Which camera

    /// The camera `wanted` names: a `uniqueID` matched exactly, else a name
    /// matched case-insensitively and exactly. An index into `cameras`, or nil.
    static func match(_ wanted: String, in cameras: [CameraDeviceFacts]) -> Int? {
        cameras.firstIndex { $0.uniqueID == wanted }
            ?? cameras.firstIndex { $0.name.caseInsensitiveCompare(wanted) == .orderedSame }
    }

    /// The camera a recording takes when none is named: the system's
    /// preferred camera (`preferredID`) when it is listed, else the first
    /// built-in, else the first; nil when none is connected.
    static func defaultIndex(in cameras: [CameraDeviceFacts], preferredID: String?) -> Int? {
        if let preferredID, let index = cameras.firstIndex(where: { $0.uniqueID == preferredID }) {
            return index
        }
        return cameras.firstIndex { $0.isBuiltIn } ?? (cameras.isEmpty ? nil : 0)
    }

    static let noCameraSentence = "No camera is connected."

    /// The refusal for a name or id no connected camera carries, naming every
    /// camera present (each by name and id); `noCameraSentence` when none is.
    static func noSuchCameraSentence(_ wanted: String, cameras: [CameraDeviceFacts]) -> String {
        guard !cameras.isEmpty else { return noCameraSentence }
        let present = cameras.map { "\($0.name) (\($0.uniqueID))" }.joined(separator: ", ")
        return "No connected camera is named or has the id \(wanted). The cameras connected are "
            + present + "."
    }
}
