import AVFoundation
import AppKit

/// The calls a press of Record makes about the four grants, as values a
/// probe can replace: the reads, the four system prompts, the two remembered
/// "asked" flags and the one opener of System Settings. `live` is the app's;
/// `tools/proof/recording_probe.py` puts a sealed spy in
/// `RecorderPanelController.grantDoors` before any mode runs, so no probe
/// can prompt, open Settings or touch the key. Input Monitoring's four
/// (road map creator-jobs CU6, spec §11 CU-62) come last and default INERT —
/// never granted, never asking, never remembering — so a probe that fills
/// only the first ten compiles unchanged and can never prompt.
struct RecorderGrantDoors {
    /// Whether the panel has put up the Screen Recording prompt once
    /// (spec §11 recording). Written only by a launchd-owned press.
    static let screenRecordingAskedKey = "FrameJobScreenRecordingAsked"
    /// Whether the panel has asked for Input Monitoring once (spec §11 CU-3,
    /// CU-62). Written only by a launchd-owned press.
    static let inputMonitoringAskedKey = "FrameJobInputMonitoringAsked"

    var screenGranted: () -> Bool
    var launchedByLaunchd: () -> Bool
    var requestScreen: () -> Void
    var screenAsked: () -> Bool
    var rememberScreenAsked: () -> Void
    var microphoneStatus: () -> AVAuthorizationStatus
    var requestMicrophone: (@escaping () -> Void) -> Void
    var openSettings: (URL) -> Bool
    /// The Camera grant (CR1c, spec §11 CAM-5), asked only for Source Camera.
    var cameraStatus: () -> AVAuthorizationStatus
    var requestCamera: (@escaping () -> Void) -> Void
    /// Input Monitoring (CU-62), read only with Record shortcuts on.
    var inputMonitoringGranted: () -> Bool = { false }
    var requestInputMonitoring: () -> Void = {}
    var inputMonitoringAsked: () -> Bool = { false }
    var rememberInputMonitoringAsked: () -> Void = {}

    static var live: RecorderGrantDoors {
        RecorderGrantDoors(
            screenGranted: { RecordingGrant.screenRecordingGranted },
            launchedByLaunchd: { RecordingGrant.launchedByLaunchd },
            requestScreen: { _ = CGRequestScreenCaptureAccess() },
            screenAsked: { UserDefaults.standard.bool(forKey: screenRecordingAskedKey) },
            rememberScreenAsked: { UserDefaults.standard.set(true, forKey: screenRecordingAskedKey) },
            microphoneStatus: { RecordingGrant.microphoneStatus },
            requestMicrophone: { answered in
                // The framework does not say which queue it answers on, so
                // the answer hops to main.
                AVCaptureDevice.requestAccess(for: .audio) { _ in
                    DispatchQueue.main.async { answered() }
                }
            },
            openSettings: { url in NSWorkspace.shared.open(url) },
            cameraStatus: { RecordingGrant.cameraStatus },
            requestCamera: { answered in
                // As the microphone's: the answer hops to main.
                AVCaptureDevice.requestAccess(for: .video) { _ in
                    DispatchQueue.main.async { answered() }
                }
            },
            inputMonitoringGranted: { RecordingGrant.inputMonitoringGranted },
            requestInputMonitoring: { _ = CGRequestListenEventAccess() },
            inputMonitoringAsked: { UserDefaults.standard.bool(forKey: inputMonitoringAskedKey) },
            rememberInputMonitoringAsked: {
                UserDefaults.standard.set(true, forKey: inputMonitoringAskedKey)
            })
    }
}

/// The grants, for the recorder panel (road map 3, R1c; spec §11
/// recording) — `RecorderPanelController.swift`'s seventh file, cut out of
/// `+Recording.swift` when the press learned to open System Settings.
///
/// **The grants are asked for HERE and nowhere else, and UNCONDITIONALLY**
/// (decision 4: the TOOL never asks — it reads the status and refuses by
/// name — because a system prompt needs a person in front of it; the panel
/// asks, because a press of Record IS that person, exactly as the transcribe
/// sheet's Start is). **This is also the only place System Settings is
/// opened for them**, and the tool never opens it. Screen Recording is
/// asked with `CGRequestScreenCaptureAccess()` on the FIRST press that finds
/// it absent — the system prompt appears once per app, not per launch — and
/// the ask is remembered in `FrameJobScreenRecordingAsked`; every later press
/// opens the Screen & System Audio Recording pane and the note says so.
/// `CGRequestScreenCaptureAccess()` returns false at once on a first ask, so
/// the refusal sentence is shown either way and the person presses Record
/// again once the grant is on. The flag is read and written only in a
/// launchd-owned launch: a shell-launched press always asks and never
/// remembers, because TCC attributes that prompt to the terminal (R0 q1).
/// The microphone is asked only when one is chosen, from `.notDetermined`,
/// and the countdown starts from the answer; `.denied` and `.restricted`
/// open the Microphone pane and stop there, and a prompt's answer never
/// opens it. Both readings happen BEFORE the countdown, so a countdown never
/// ends in a prompt. An earlier draft gated both asks on a `canAsk` (since
/// deleted with the speech grant) — false for a scripted agent launch —
/// and the R1 review measured what that cost: under that flag the refusal
/// note told the person to press the button they had just pressed, and a
/// `notDetermined` microphone could never be granted from anywhere.
/// `canAsk` is the tool's rule about a prompt nobody would see; it does not
/// apply to a button somebody clicked. **The Camera grant** (CR1c, spec §11
/// CAM-5) is the third, read only for Source Camera, whose press never reads
/// Screen Recording: the microphone's steps, through its own pane
/// (`Privacy_Camera`), and its prompt's answer RE-READS the grant before the
/// microphone and the countdown, so a refused prompt stops there. **Input
/// Monitoring** (road map creator-jobs CU6, spec §11 CU-3, CU-62) is the
/// fourth, read only when Record shortcuts is on with a screen source, after
/// Screen Recording and before the Camera and the Microphone. Its step is
/// Screen Recording's table, remembered in `FrameJobInputMonitoringAsked`;
/// because no prompt shows and Frame Job is not listed until a person adds
/// it (CU0b), an ask ALSO opens the Input Monitoring pane, and the note says
/// to add Frame Job with + (`inputMonitoringNote(opened:)`).
extension RecorderPanelController {
    /// The doors every grant call goes through; a probe replaces it.
    static var grantDoors = RecorderGrantDoors.live

    /// A system prompt, or System Settings, is about to come up in ANOTHER
    /// process at normal window level, and a `.floating` panel sits over
    /// every normal window on the screen: the person found the Screen
    /// Recording prompt hidden behind the panel until they dragged it away
    /// (2026-09-28). So the panel steps down to `.normal` first, and
    /// `floatAgain` puts it back on the next press that goes on, or on
    /// `show()`.
    func stepAsideForSystemUI() { window?.level = .normal }
    func floatAgain() { window?.level = .floating }

    /// Screen Recording, for a press: true to go on; false with the note
    /// set, and the press ends. `screenStep` is the one decision point.
    func checkScreenRecordingGrant() -> Bool {
        floatAgain()
        let doors = Self.grantDoors
        let owned = doors.launchedByLaunchd()
        let step = RecordingGrant.screenStep(
            granted: doors.screenGranted(), asked: doors.screenAsked(), launchedByLaunchd: owned)
        switch step {
        case .proceed:
            return true
        case .ask:
            if owned { doors.rememberScreenAsked() }
            stepAsideForSystemUI()
            doors.requestScreen()
            setNote(RecordingGrant.screenRecordingRefusal)
            return false
        case .openPane:
            stepAsideForSystemUI()
            let opened = RecordingGrant.screenRecordingPaneURL.map(doors.openSettings) ?? false
            setNote(
                opened ? RecordingGrant.screenRecordingOpenedNote : RecordingGrant.screenRecordingRefusal)
            return false
        }
    }

    /// Input Monitoring, for a press (CU-62): true to go on — Record shortcuts
    /// off (it is `.off` for a voice-over and a camera) or granted; false with
    /// the note set, and the press ends. `inputMonitoringStep` decides.
    func checkInputMonitoringGrant() -> Bool {
        guard currentChoice().keys == .shortcuts else { return true }
        floatAgain()
        let doors = Self.grantDoors
        let owned = doors.launchedByLaunchd()
        let step = RecordingGrant.inputMonitoringStep(
            granted: doors.inputMonitoringGranted(), asked: doors.inputMonitoringAsked(),
            launchedByLaunchd: owned)
        switch step {
        case .proceed:
            return true
        case .ask:
            if owned { doors.rememberInputMonitoringAsked() }
            stepAsideForSystemUI()
            doors.requestInputMonitoring()
            let opened = RecordingGrant.inputMonitoringPaneURL.map(doors.openSettings) ?? false
            setNote(RecordingGrant.inputMonitoringNote(opened: opened))
            return false
        case .openPane:
            stepAsideForSystemUI()
            let opened = RecordingGrant.inputMonitoringPaneURL.map(doors.openSettings) ?? false
            setNote(RecordingGrant.inputMonitoringNote(opened: opened))
            return false
        }
    }

    /// The microphone, for a press: true to go on (none chosen, or
    /// authorized); false when it asked (the answer continues the press) or
    /// opened its pane.
    func checkMicrophoneGrant() -> Bool {
        guard currentChoice().microphone != nil else { return true }
        let doors = Self.grantDoors
        let status = doors.microphoneStatus()
        switch RecordingGrant.microphoneStep(status) {
        case .proceed:
            return true
        case .ask:
            recordButton.isEnabled = false
            stepAsideForSystemUI()
            doors.requestMicrophone { [weak self] in self?.microphoneAnswered() }
            return false
        case .openPane:
            stepAsideForSystemUI()
            let opened = RecordingGrant.microphonePaneURL.map(doors.openSettings) ?? false
            setNote(
                opened
                    ? RecordingGrant.microphoneOpenedNote(status)
                    : RecordingGrant.microphoneRefusal(status))
            return false
        }
    }

    /// The prompt's answer. The button comes back either way; the countdown
    /// begins only in an idle panel that is still ON SCREEN (R1 review) — a
    /// panel closed during the prompt must not count down where nobody can
    /// cancel it, and `panelWillClose` cannot cancel a countdown that has not
    /// begun. It never opens System Settings.
    private func microphoneAnswered() {
        recordButton.isEnabled = true
        guard phase == .idle, window?.isVisible == true else { return }
        let status = Self.grantDoors.microphoneStatus()
        guard status == .authorized else {
            setNote(RecordingGrant.microphoneRefusal(status))
            return
        }
        setNote("")
        floatAgain()
        beginCountdown()
    }

    /// The camera, for a press with Source Camera: true to go on
    /// (authorized); false when it asked (the answer continues the press) or
    /// opened its pane — `checkMicrophoneGrant`'s three arms.
    func checkCameraGrant() -> Bool {
        let doors = Self.grantDoors
        let status = doors.cameraStatus()
        switch RecordingGrant.cameraStep(status) {
        case .proceed:
            return true
        case .ask:
            recordButton.isEnabled = false
            stepAsideForSystemUI()
            doors.requestCamera { [weak self] in self?.cameraAnswered() }
            return false
        case .openPane:
            stepAsideForSystemUI()
            let opened = RecordingGrant.cameraPaneURL.map(doors.openSettings) ?? false
            setNote(
                opened
                    ? RecordingGrant.cameraOpenedNote(status)
                    : RecordingGrant.cameraRefusal(status))
            return false
        }
    }

    /// The camera prompt's answer, `microphoneAnswered`'s rule: the button
    /// comes back either way, and the press goes on only in an idle panel
    /// still on screen. The grant is READ AGAIN first — anything but
    /// authorized stops with the refusal, no microphone prompt and no
    /// countdown — then the microphone's grant, then the countdown.
    private func cameraAnswered() {
        recordButton.isEnabled = true
        guard phase == .idle, window?.isVisible == true else { return }
        let status = Self.grantDoors.cameraStatus()
        guard status == .authorized else {
            setNote(RecordingGrant.cameraRefusal(status))
            return
        }
        setNote("")
        floatAgain()
        guard checkMicrophoneGrant() else { return }
        beginCountdown()
    }
}
