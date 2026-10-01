import AVFoundation
import AppKit
import ScreenCaptureKit

/// File ▸ New Recording… (⌥⌘N) — the recorder's panel (road map 3, R1c).
/// One instance for the life of the process, `ExportQueueWindowController`'s
/// mould (`shared`, a private init, `isExcludedFromWindowsMenu`,
/// `isReleasedWhenClosed = false`), because a recording outlives documents
/// and the panel must exist with none open. The controls become one
/// `RecordingChoice`; Record hands it to `ScreenRecorder.shared`; the result
/// goes through `RecordingLanding` into a document or opens a new one. This
/// file is the window, its rows and its phases; `+Rows.swift` is what fills
/// the popups and turns them into a `RecordingChoice` and back;
/// `+Recording.swift` is everything from Record pressed to the recording
/// running, `+Grants.swift` the two grants a press checks first and the
/// one place System Settings is opened for them, `+Landing.swift`
/// everything from the recording's end to the note that says where it
/// went, `+Picker.swift` the window picker, and `+Pause.swift` the pause
/// and the resume, the hidden recording's one door and the phases drawn
/// (R2c). Seven files at the 400-line cap, and the
/// crossing members are internal for it, the tree's rule for a class split
/// across files.
///
/// **It is an `NSPanel`, floating and NON-ACTIVATING**, and each of the four
/// window settings below is load-bearing. `.nonactivatingPanel` so Record,
/// and the countdown's Cancel, can be clicked with the application about to
/// be recorded still FRONTMOST — the panel is off screen once the recording
/// runs (below), so this is for the seconds before it, when activating
/// Reelcut would put its document windows over the target; `.floating` so
/// it stays above that thing; `hidesOnDeactivate = false`
/// because `NSPanel` defaults it TRUE (`PreviewWindowController` measured it)
/// and a recorder panel that vanished the moment the person switched to the
/// application they are about to record would be useless; and NO window
/// delegate — a delegate that answers nil for the undo manager is the trap
/// `PreviewWindowController` records, and here there is no document to
/// answer with. It persists nothing about its frame (the queue window's
/// posture: no autosave name, no defaults key for the harness to pin), and
/// centres itself once; a panel is picked up and put beside the recorded
/// window each time anyway. **Whatever it is refitted to stays on the
/// screen it is on** (`fitWindowToContent`, R1 review): the countdown
/// numeral grows the card 88 pt DOWNWARD — 130 with a note under it — from
/// a fixed top edge, and a panel parked at the bottom of a display, the
/// natural place for a recorder, used to put its Cancel button under the
/// Dock.
///
/// **Visibility during a recording** (decision 7, R2c): the panel orders
/// OUT at `recordingDidStart` for EVERY source, and the status item is the
/// recording's whole chrome — Pause, Resume and Stop are its menu; File ▸
/// Stop Recording still stops. R1 kept a DISPLAY recording's panel up, its
/// filter excluding Reelcut (R0 q3), and hid only a PICKED window's; the
/// user asked for the dialog to go away whatever is recorded, and a panel
/// whose one live control was a Stop the menu bar also has earned nothing
/// on screen. It comes back after the landing ONLY when it was on screen
/// as the recording began (`showWhenLanded`, read at `recordingDidStart`)
/// AND the landing left a note (`revealIfNoted`, `+Landing.swift`): a stop
/// from the system's own indicator, a closed target, a microphone problem,
/// a refused resume, a failure. A clean recording lands and the panel
/// stays away, and a panel closed before the recording began stays closed
/// whatever the note; ⌥⌘N shows it again. `show()` BEEPS while
/// `hiddenForRecording` (R1 review) — the welcome window's button reaches
/// it — because a panel un-hidden into the recording would be in the file;
/// the quit guard goes through `revealControls()` instead (`+Pause.swift`).
/// **It takes key only from an active Reelcut** (spec §11, #137): shown from
/// the background it is ordered front without key, so Return stays with
/// the app in front.
///
/// Two limits of that chrome, accepted (R2 review). With the panel hidden
/// the status item is the ONLY Pause and Resume, and macOS drops a status
/// item that does not fit the menu bar — behind a notch, in a crowded bar
/// — so there Stop survives in the File menu and Pause and Resume do not.
/// And "●" and "❚❚" differ in width under `variableLength`, so the items to
/// the left of it shift by a few points at each pause and resume.
///
/// **Quit while recording, and the order AppKit asks in.**
/// `AppDelegate.applicationShouldTerminate` cancels a quit while
/// `ScreenRecorder.shared.isRecording` and calls `revealControls()` — the
/// status item's menu, opened, while this panel is hidden for its
/// recording; `show()` for any other (a tool's, which File ▸ Stop Recording
/// ends) — and it is a BACKSTOP: `NSDocumentController` reviews modified
/// documents FIRST, so the save sheet comes before the guard, and a target
/// document the review CLOSED lands as `.newProject` —
/// `RecordingLanding.resolve` looks the destination up by `recipeKey`,
/// never minted twice, so the miss is exact, and the landing's note says
/// the document was closed.
///
/// **Two Record Into rules.** The popup is built from `NSMenuItem`s carrying
/// each document's `recipeKey` in `representedObject` and is read from
/// `selectedItem`, never by index: `NSPopUpButton.addItem(withTitle:)`
/// REMOVES a same-titled row (phase 4's defect), and two untitled documents
/// read alike. And it follows the FRONT document until the person chooses a
/// row themselves (`chosenDestination`), re-synced by a one-second timer
/// while the panel is visible — rows compared before any rebuild, so a menu
/// the person has open is never rebuilt under the pointer — **and only while
/// the phase is idle** (`rebuildDestinations`, R1 review): from the press
/// of Record to the landing the rows are FROZEN at what the person saw when
/// they pressed it, whichever document comes to the front meanwhile, and
/// `landed()`'s own rebuild is what moves them again. The destination the
/// recording actually lands in was captured from the controls at the
/// countdown's end and cannot move either way; what the freeze buys is that
/// the row on screen and the destination in the choice agree.
///
/// Every choice persists under a `ReelcutRecording…` key (written on change,
/// read on show); the harness pins all six on `ReelcutExportChoice`'s terms.
/// `.picked` is the one source that cannot persist — a filter is not a
/// value — so a reopened panel with a picked window keeps the row only while
/// the filter is still held.
final class RecorderPanelController: NSWindowController {
    static let shared = RecorderPanelController()

    // MARK: - Defaults keys

    static let displayKey = "ReelcutRecordingDisplay"
    static let microphoneKey = "ReelcutRecordingMicrophone"
    static let systemAudioKey = "ReelcutRecordingSystemAudio"
    static let showClicksKey = "ReelcutRecordingShowClicks"
    static let rateKey = "ReelcutRecordingRate"
    static let sizeKey = "ReelcutRecordingSize"

    // MARK: - Metrics and vocabulary

    /// Wider than `sheetWidth`: the microphone row is a popup AND a 120 pt
    /// meter beside the 106 pt label column, which 420 cannot hold.
    static let cardWidth: CGFloat = 500
    static let controlWidth: CGFloat = 200
    /// The Source popup's last row, "Window…", by tag; display rows carry
    /// their `CGDirectDisplayID` in `representedObject`.
    static let windowTag = 1
    static let countdownSeconds = 3
    static let rates = [30, 60]

    /// Where the panel is in a recording's life. `syncPhase()` draws it.
    enum Phase: Equatable {
        case idle
        case countdown(Int)
        case starting
        case recording
        case paused
        case stopping
        case landing
    }

    var phase: Phase = .idle {
        didSet { syncPhase() }
    }

    let recorder = ScreenRecorder.shared

    // The controls — internal rather than private because the recording flow
    // lives in an extension in another file, and `private` does not cross one.
    let sourcePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let microphonePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let meterView = LevelMeterView(meter: ScreenRecorder.shared.meter)
    let systemAudioSwitch = NSSwitch()
    let showClicksSwitch = NSSwitch()
    let ratePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let sizePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let sizeNote = NSTextField(labelWithString: "")
    let destinationPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let countdownLabel = NSTextField(labelWithString: "")
    let noteLabel = NSTextField(wrappingLabelWithString: "")
    let statusLabel = NSTextField(labelWithString: "")
    let recordButton = AccentButton(
        title: "Record", symbol: "record.circle", fallback: "●",
        tooltip: "Start recording after a three-second countdown",
        action: #selector(record(_:)), fill: DS.meterClip)
    let closeButton = StickerButton(
        title: "Close", style: .secondary, target: nil, action: #selector(closePanel(_:)))
    let card: NSView

    /// The picker's filter, held while the Source popup shows "Window
    /// (picked)". Cleared when a display row is chosen.
    var pickedFilter: SCContentFilter?
    var pickerObserved = false
    /// The Source row to fall back to when the picker is cancelled.
    var sourceBeforePick = 0
    /// nil follows the front document; set by the popup's own action.
    var chosenDestination: RecordingDestination?
    /// A recording is running and the panel is off screen for it (`show()`
    /// beeps). Set at EVERY `recordingDidStart`, visible panel or not;
    /// `showWhenLanded` remembers whether it WAS visible, which is what
    /// `revealIfNoted` reads after the landing.
    var hiddenForRecording = false
    var showWhenLanded = false
    /// The recorder's sentence for a resume it refused (`+Pause.swift`):
    /// REPLACED by each retry, cleared when a resume lands or the next
    /// countdown begins, one of the two parts the live note is rebuilt
    /// from, and a sentence the landing's note carries (`+Landing.swift`).
    var resumeProblem: String?
    /// Each press of Record is one attempt, numbered, and the completions
    /// the attempt hands out carry its number (`+Recording.swift`): a
    /// shareable-content answer from an attempt that was abandoned or timed
    /// out is told apart by it and ignored.
    var startGeneration = 0
    /// The current attempt has reached `ScreenRecorder.start` — from here
    /// the recorder's own arm ceiling is the bound and a Stop goes through
    /// `stop()`; before it, the lookup is the panel's to abandon.
    var launched = false
    var countdownTimer: Timer?
    var startTimer: Timer?
    var tickTimer: Timer?
    var landingTimer: Timer?
    var syncTimer: Timer?
    var landingAttempts = 0
    var statusItem: RecorderStatusItem?

    private init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.cardWidth, height: 360),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.title = "New Recording"
        panel.level = .floating
        // See the type doc: `NSPanel` defaults this to TRUE.
        panel.hidesOnDeactivate = false
        panel.isExcludedFromWindowsMenu = true
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = DS.chromeBackground

        let content = NSStackView()
        card = makeSheetView(
            hint: "The recording is saved as a movie in the Reelcut Recordings folder and "
                + "added to the project you choose at the playhead, or opened as a new "
                + "project at the rate you pick.",
            content: content,
            buttonRow: makeButtonRow(cancel: closeButton, apply: recordButton, leading: [statusLabel]),
            width: Self.cardWidth)
        super.init(window: panel)

        buildRows(into: content)
        // The card is a subview pinned at the top-left of a plain root, and
        // the window is sized to the card's fitting size by
        // `fitWindowToContent()` — never the window's content view itself,
        // whose autoresizing constraints would fight the card's own width and
        // vertical chain whenever a label appears or disappears.
        let root = NSView()
        root.wantsLayer = true
        card.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: root.topAnchor),
            card.leadingAnchor.constraint(equalTo: root.leadingAnchor),
        ])
        panel.contentView = root
        recordButton.target = self
        closeButton.target = self

        rebuildSources()
        rebuildMicrophones()
        rebuildDestinations()
        restoreChoices()
        refreshSizeNote()
        syncPhase()
        panel.center()

        NotificationCenter.default.addObserver(
            self, selector: #selector(panelWillClose(_:)),
            name: NSWindow.willCloseNotification, object: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("RecorderPanelController does not support NSCoder")
    }

    // MARK: - Actions

    @objc func controlChanged(_ sender: Any?) {
        if let sender = sender as? NSPopUpButton, sender === sourcePopup {
            if sender.selectedItem?.tag == Self.windowTag {
                presentPicker()
            } else {
                pickedFilter = nil
                sourcePopup.menu?.item(withTag: Self.windowTag)?.title = "Window…"
            }
        }
        if let sender = sender as? NSPopUpButton, sender === destinationPopup {
            chosenDestination = currentChoice().destination
        }
        persistChoices()
        refreshSizeNote()
    }

    @objc private func closePanel(_ sender: Any?) {
        window?.close()
    }

    /// A countdown must not go on in a panel nobody can see: closing cancels
    /// it, and a microphone the countdown prepared is let go with it — said
    /// again here rather than left to `cancelCountdown`, because a panel
    /// closed during the microphone PROMPT (before any countdown) may also
    /// hold one, and an input left open past the panel is the leak the
    /// discard exists to close (R1 review). A close while `.starting` is a
    /// Stop (R2 review) — the attempt abandoned before `launch`, the
    /// recording stopped after it, `stopRecording`'s own two arms — because
    /// a start that ran on behind a closed panel would read `showWhenLanded`
    /// false and land every later note where nobody sees it. A RECORDING
    /// carries on — the status item and File ▸ Stop Recording can end it —
    /// and the sync timer stops until the next `show()`.
    @objc private func panelWillClose(_ note: Notification) {
        switch phase {
        case .countdown: cancelCountdown()
        case .starting: stopRecording()
        default: break
        }
        recorder.discardPreparedMicrophone()
        syncTimer?.invalidate()
        syncTimer = nil
    }

    // MARK: - Showing

    /// Beeps and shows nothing while a recording has the panel hidden (the
    /// type doc): the welcome window's button is the caller that would
    /// otherwise un-hide it into the recording.
    func show() {
        guard !hiddenForRecording else {
            NSSound.beep()
            return
        }
        if phase == .idle {
            rebuildSources()
            rebuildMicrophones()
            restoreChoices()
        }
        rebuildDestinations()
        refreshSizeNote()
        fitWindowToContent()
        floatAgain()
        if NSApp.isActive {
            showWindow(nil)
            window?.makeKeyAndOrderFront(nil)
        } else {
            window?.orderFrontRegardless()
        }
        armSyncTimer()
    }

    /// One second, while the panel is up: the Record Into rows follow the
    /// documents that open and close and the one in front — while idle,
    /// which `rebuildDestinations` itself decides.
    private func armSyncTimer() {
        guard syncTimer == nil else { return }
        syncTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            guard self.window?.isVisible == true else { return }
            self.rebuildDestinations()
        }
    }

    // `syncPhase()` and `refreshStatusLabel()` — the phases drawn — are
    // `+Pause.swift`'s since the R2 review, the base file's toll.

    func setNote(_ text: String) {
        noteLabel.stringValue = text
        noteLabel.isHidden = text.isEmpty
        fitWindowToContent()
    }

    /// The window takes the card's fitting size, keeping its TOP-LEFT where
    /// it was — `setContentSize` would keep the bottom-left and walk the
    /// title bar up the screen every time the note appeared — and then
    /// CONSTRAINED to its screen (`window.screen`, else the main one), so a
    /// panel whose bottom edge sits near the Dock is pushed up when the
    /// countdown grows it rather than growing under the Dock (R1 review;
    /// measured, the numeral adds 88 pt below the rows and a note 42 more).
    /// `setFrame` itself constrains nothing — a window can be put anywhere
    /// programmatically, on screen or off — which is why the call is
    /// explicit.
    func fitWindowToContent() {
        guard let window else { return }
        card.layoutSubtreeIfNeeded()
        let content = NSRect(origin: .zero, size: card.fittingSize)
        var frame = window.frameRect(forContentRect: content)
        let current = window.frame
        frame.origin = NSPoint(x: current.minX, y: current.maxY - frame.height)
        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
        frame = window.constrainFrameRect(frame, to: screen)
        window.setFrame(frame, display: window.isVisible)
    }
}
