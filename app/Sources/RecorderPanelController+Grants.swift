import AVFoundation
import AppKit

/// The seven calls a press of Record makes about the two grants, as values
/// a probe can replace: the reads, the two system prompts, the remembered
/// "asked" flag and the one opener of System Settings. `live` is the app's;
/// `tools/proof/recording_probe.py` puts a sealed spy in
/// `RecorderPanelController.grantDoors` before any mode runs, so no probe
/// can prompt, open Settings or touch the key.
struct RecorderGrantDoors {
    /// Whether the panel has put up the Screen Recording prompt once
    /// (spec §11 recording). Written only by a launchd-owned press.
    static let screenRecordingAskedKey = "ReelcutScreenRecordingAsked"

    var screenGranted: () -> Bool
    var launchedByLaunchd: () -> Bool
    var requestScreen: () -> Void
    var screenAsked: () -> Bool
    var rememberScreenAsked: () -> Void
    var microphoneStatus: () -> AVAuthorizationStatus
    var requestMicrophone: (@escaping () -> Void) -> Void
    var openSettings: (URL) -> Bool

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
            openSettings: { url in NSWorkspace.shared.open(url) })
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
/// the ask is remembered in `ReelcutScreenRecordingAsked`; every later press
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
/// apply to a button somebody clicked.
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
}
