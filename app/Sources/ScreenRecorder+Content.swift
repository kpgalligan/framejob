import AVFoundation
import AppKit
import ScreenCaptureKit

/// `ScreenRecorder`'s static helpers — the shareable-content call, the
/// programmatic filter, the microphone lookup, and the two readings of an
/// `SCStreamError` — in a file of their own because none of them touches a
/// session and `ScreenRecorder.swift` is at the 400-line cap with the
/// machine alone. The spellings are the SDK scout's, compiled:
/// `getExcludingDesktopWindows(_:onScreenWindowsOnly:completionHandler:)`
/// (there is no `getShareableContent` in Swift and `current` is
/// `async`-only), `SCStreamError.Code` (there is no `SCError`),
/// `SCContentFilter(display:excludingApplications:exceptingWindows:)`,
/// `(display:excludingWindows:)` and `(desktopIndependentWindow:)`, `AVCaptureDevice.DeviceType.microphone`
/// and `.external` (`.builtInMicrophone` is a deprecation warning at 15.0).
/// There is no geometry helper here: the FILTER's `contentRect` and
/// `pointPixelScale` are the one geometry source (`ScreenRecorder.start`),
/// and the two that read an `SCDisplay` and an `NSScreen` had no caller.
extension ScreenRecorder {
    /// `SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly:
    /// true, …)`, ISSUED from a global queue and hopped to MAIN — one spelling
    /// for both doors (R1 review). The framework can hold the CALLING thread
    /// for tens of seconds before answering (measured ~37 s on a locked
    /// console), and the panel calls this from a button on main, so the
    /// call itself goes off main and only the answer comes back to it;
    /// `record_screen` asks from the server thread and waits on a semaphore
    /// the hop signals. Needs the Screen Recording grant; without it the
    /// framework answers an error, which is passed on unchanged.
    static func shareableContent(
        completion: @escaping (Result<SCShareableContent, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) {
                content, error in
                let outcome: Result<SCShareableContent, Error>
                if let content {
                    outcome = .success(content)
                } else {
                    outcome = .failure(
                        error
                            ?? RecorderError.startFailed(
                                "The shareable content could not be listed."))
                }
                DispatchQueue.main.async { completion(outcome) }
            }
        }
    }

    /// The programmatic filter. A display source leaves out what the
    /// `RecordingExclusion` names: by default Reelcut's own application (R0
    /// q3: that removes 99.19 % of the excluded application's window pixels
    /// against a 0 % noise floor), so the panel can stay on screen; with
    /// Include Reelcut windows on, no application and only the windows it
    /// lists (the panel's own). A bare probe has no bundle identifier and
    /// then excludes nothing rather than crashing. A window source is the
    /// window alone. A `.picked` source carries the picker's filter and has
    /// none to build, and a `.voiceOver` source has no picture at all.
    static func filter(
        for source: RecordingSource, in content: SCShareableContent,
        excluding exclusion: RecordingExclusion
    ) throws -> SCContentFilter {
        switch source {
        case .display(let id):
            guard let display = content.displays.first(where: { $0.displayID == id }) else {
                throw RecorderError.startFailed(
                    "No display with id \(id) is shareable; the displays are "
                        + content.displays.map { "\($0.displayID)" }.joined(separator: ", ") + ".")
            }
            if !exclusion.bundleIDs.isEmpty {
                let apps = content.applications.filter {
                    exclusion.bundleIDs.contains($0.bundleIdentifier)
                }
                return SCContentFilter(
                    display: display, excludingApplications: apps, exceptingWindows: [])
            }
            let windows = content.windows.filter { exclusion.windowIDs.contains($0.windowID) }
            return SCContentFilter(display: display, excludingWindows: windows)
        case .window(let id):
            guard let window = content.windows.first(where: { $0.windowID == id }) else {
                throw RecorderError.startFailed("No window with id \(id) is shareable.")
            }
            return SCContentFilter(desktopIndependentWindow: window)
        case .picked:
            throw RecorderError.startFailed(
                "A picked source carries the picker's own filter; none can be built here.")
        case .voiceOver:
            throw RecorderError.startFailed(
                "A voice-over records the microphone alone; it has no filter to build.")
        }
    }

    /// The device a choice names, or nil for an id no connected microphone
    /// carries.
    static func microphone(withID id: String) -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified
        ).devices.first { $0.uniqueID == id }
    }

    /// A stream error as a sentence. `.failedToStartAudioCapture` (−3818)
    /// names system audio, the one capture the stream carries;
    /// `.failedToStartMicrophoneCapture` (−3820) cannot occur — no microphone
    /// is on the stream — and is still named rather than left to the
    /// default. Anything else is the framework's own description.
    static func sentence(for error: any Error) -> String {
        if let streamError = error as? SCStreamError {
            switch streamError.code {
            case .userDeclined:
                return RecordingGrant.screenRecordingRefusal
            case .failedToStartAudioCapture:
                return "System audio could not be captured (\(error.localizedDescription)). "
                    + "Turn System Audio off, or check System Settings ▸ Privacy & Security ▸ "
                    + "Screen & System Audio Recording."
            case .failedToStartMicrophoneCapture:
                return "The microphone could not be captured (\(error.localizedDescription))."
            default:
                break
            }
        }
        return error.localizedDescription
    }

    /// The two external stops that are not failures: −3817 and −3821.
    static func externalStop(_ error: any Error) -> StopReason? {
        guard let streamError = error as? SCStreamError else { return nil }
        switch streamError.code {
        case .userStopped: return .userStopped
        case .systemStoppedStream: return .systemStopped
        default: return nil
        }
    }
}

// MARK: - The meter's arithmetic

/// dB → linear magnitude for `AVCaptureAudioChannel`'s two readings, which
/// are decibels relative to full scale (0 dB = 1.0). Clamped to [0, 1] and
/// a non-finite reading answered as silence, `LevelMeterReading`'s posture.
/// Pure, so the probe pins it at −20 dB → 0.1, 0 dB → 1, +6 dB → 1.
enum RecordingMeter {
    static func linear(fromDecibels dB: Float) -> Float {
        guard dB.isFinite else { return 0 }
        return min(1, max(0, powf(10, dB / 20)))
    }
}

// MARK: - What a display recording leaves out

/// The one decision both doors and the picker read (spec §11 recording.md,
/// Include Reelcut windows). Off: Reelcut's application, whole (no bundle
/// identifier → nothing). On: no application, and the panel's own window
/// when the panel started the recording (none → nothing). Pure, so the
/// probe pins it.
struct RecordingExclusion: Equatable {
    /// Applications left out whole.
    let bundleIDs: [String]
    /// Single windows left out.
    let windowIDs: [CGWindowID]

    static func make(
        includeReelcutWindows: Bool, ownBundleID: String?, panelWindowID: CGWindowID?
    ) -> RecordingExclusion {
        if includeReelcutWindows {
            return RecordingExclusion(bundleIDs: [], windowIDs: panelWindowID.map { [$0] } ?? [])
        }
        return RecordingExclusion(bundleIDs: ownBundleID.map { [$0] } ?? [], windowIDs: [])
    }
}
