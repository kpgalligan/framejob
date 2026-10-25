import AppKit

/// The WebM or Matroska copy's progress window (spec §11 #228-P): a small
/// titled panel, the same for every click door, with the bar, the file's
/// name, how much is copied and one Cancel. It is non-modal and never takes
/// the keyboard from a Frame Job window: it shows only when the copy is still
/// running `showDelay` after it started, ordered front without becoming key
/// while any window is key (made key only when none is — File ▸ Open, a
/// Finder double-click), so typing and Escape keep reaching the editor
/// until the person clicks into it.
///
/// `watch` is the `RewrapWatch` the click doors pass: called on the copying
/// thread, it hops to main, keeps a controller in `live` and polls the
/// progress on a run-loop timer, as `Exporter.startProgressTimer` does,
/// until the copy finishes; then the window closes and the controller goes.
/// It raises no modal, no sheet and no alert. Copies are serial
/// (`ContainerRewrap.assist`'s lock), so at most one is live.
final class RewrapProgressWindowController: NSWindowController {
    static let showDelay: TimeInterval = 1.0
    static let pollInterval: TimeInterval = 0.1

    /// Main-only: one controller per copy not yet finished.
    static private(set) var live: [RewrapProgressWindowController] = []

    let progress: RewrapProgress
    /// Built in `loadView`; the button's action and its Escape key
    /// equivalent are `cancelCopy(_:)`.
    private(set) var cancelButton: StickerButton!

    private let bar = NSProgressIndicator()
    private let detailLabel = NSTextField(labelWithString: "")
    private var timer: Timer?
    private let started = Date()

    init(progress: RewrapProgress) {
        self.progress = progress
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: sheetWidth, height: 160),
            styleMask: [.titled], backing: .buffered, defer: true)
        panel.title = "Copying Movie"
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        super.init(window: panel)
        loadView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("RewrapProgressWindowController does not support NSCoder")
    }

    private func loadView() {
        styleSheetProgressBar(bar, indeterminate: true)

        styleSheetDetailLabel(detailLabel)
        detailLabel.stringValue = Self.detail(for: progress)

        let content = makeProgressStack([bar, detailLabel])

        cancelButton = StickerButton(
            title: "Cancel", style: .secondary, target: self, action: #selector(cancelCopy(_:)))
        let apply = StickerButton(title: "Close", style: .primary, target: nil, action: nil)
        hideReturnTarget(apply)

        let view = makeSheetView(
            title: "Copying “\(progress.source.lastPathComponent)”",
            hint: "Frame Job copies the video and sound of a WebM or MKV file into a movie once, "
                + "without re-encoding. Importing the same file again uses the copy.",
            content: content, buttonRow: makeButtonRow(cancel: cancelButton, apply: apply))
        window?.contentView = view
        view.layoutSubtreeIfNeeded()
        window?.setContentSize(view.fittingSize)
    }

    /// Cancel, and Escape once the panel is key: the copy stops before its
    /// next sample and its partial file is deleted (`ContainerRewrap`).
    @objc func cancelCopy(_ sender: Any?) {
        progress.cancel()
        cancelButton.title = "Cancelling…"
        cancelButton.isEnabled = false
    }

    /// A `RewrapWatch`: any thread; hops to main for the window.
    nonisolated static func watch(_ progress: RewrapProgress) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { start(progress) }
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated { start(progress) } }
        }
    }

    private static func start(_ progress: RewrapProgress) {
        let controller = RewrapProgressWindowController(progress: progress)
        live.append(controller)
        // `.common` modes: the panel keeps polling during menu tracking and
        // behind a modal alert.
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak controller] _ in
            MainActor.assumeIsolated { controller?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        controller.timer = timer
    }

    /// "Reading the file…" until the copy has begun, then "412 MB of 1.2 GB".
    nonisolated static func detail(for progress: RewrapProgress) -> String {
        guard progress.fraction != nil else { return "Reading the file…" }
        let copied = ByteCountFormatter.string(
            fromByteCount: Int64(clamping: progress.copiedBytes), countStyle: .file)
        let total = ByteCountFormatter.string(
            fromByteCount: Int64(clamping: progress.totalBytes), countStyle: .file)
        return "\(copied) of \(total)"
    }

    private func poll() {
        guard !progress.isFinished else {
            timer?.invalidate()
            timer = nil
            close()
            Self.live.removeAll { $0 === self }
            return
        }
        if let window, !window.isVisible, Date().timeIntervalSince(started) >= Self.showDelay {
            window.center()
            // Never take the keyboard from a Frame Job window (spec §11
            // #228-P): a click into the panel makes it key. An inactive app
            // has no key window, so it gets the panel ordered front, not key.
            if NSApp.isActive && NSApp.keyWindow == nil {
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderFront(nil)
            }
        }
        if let fraction = progress.fraction {
            if bar.isIndeterminate {
                bar.stopAnimation(nil)
                bar.isIndeterminate = false
            }
            bar.doubleValue = fraction
        } else {
            bar.startAnimation(nil)
        }
        detailLabel.stringValue = Self.detail(for: progress)
    }
}
