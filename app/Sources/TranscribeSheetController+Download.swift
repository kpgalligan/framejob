import AppKit

// MARK: - Sheet: the Download row

/// The row under Language that installs an on-device model — spec §11 W-8,
/// road map 8 §5f. It shows for a supported language whose model is not on
/// this Mac, and while a download runs; a person presses Download, watches the
/// bar, and may press Cancel.
///
/// **A download is a person's act, never a tool's** (R6-12's argument read
/// across): this row is `SpeechEngine.download`'s only caller, and the
/// `transcribe` tool refuses an uninstalled locale by name instead.
///
/// **The bar is indeterminate until the download says how big it is.** W0 q3
/// read the request's `Progress` before any download: zero units, zero
/// fraction. So the row names no size and no percentage until
/// `totalUnitCount` is positive, and then shows the fraction.
///
/// **Both popups are LOCKED while a download runs.** Changing the language
/// mid-download would hide the only Cancel or show one locale's bar under
/// another's name, and changing the engine would repopulate Language under
/// it; `downloading` names the locale the running download is for and the
/// row reads that, never the popup. The lock is applied in
/// `refreshDownloadRow()`, AFTER `populateLanguages()` has set the popup's
/// own `isEnabled` — never inside it.
///
/// **Closing the sheet mid-download is a decision, not code**: the download
/// runs on in the framework, and the observation dies with this controller
/// (`[weak self]`).
extension TranscribeSheetController {

    /// Grid row 1: an empty label cell, and the button, the bar and the
    /// label in one stack.
    func makeDownloadRow() -> [NSView] {
        let button = NSButton(
            title: "Download", target: self, action: #selector(downloadClicked(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = DS.sans(12)
        let bar = NSProgressIndicator()
        bar.style = .bar
        bar.controlSize = .small
        bar.minValue = 0
        bar.maxValue = 1
        bar.isIndeterminate = true
        bar.widthAnchor.constraint(equalToConstant: 80).isActive = true
        let label = NSTextField(labelWithString: "")
        label.font = DS.sans(11)
        label.textColor = DS.textMuted
        label.lineBreakMode = .byTruncatingTail
        downloadButton = button
        downloadBar = bar
        downloadLabel = label
        let stack = NSStackView(views: [button, bar, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return [fieldLabel(""), stack]
    }

    /// The row's whole state, recomputed — `refresh()` calls it last, and
    /// every progress hop ends in it.
    func refreshDownloadRow() {
        guard let grid = grid, let button = downloadButton, let bar = downloadBar,
            let label = downloadLabel
        else { return }
        let running = downloading
        let visible = running != nil || (engine == .apple && language?.installed == false)
        if grid.numberOfRows > 1 { grid.row(at: 1).isHidden = !visible }
        guard let running else {
            button.title = "Download"
            button.isEnabled = true
            bar.isHidden = true
            bar.stopAnimation(nil)
            label.stringValue = ""
            return
        }
        languagePopup.isEnabled = false
        enginePopup.isEnabled = false
        button.title = "Cancel"
        // Nothing to cancel until the request's `Progress` has arrived: a
        // Cancel pressed before it would do nothing and the download run on.
        button.isEnabled = downloadProgress != nil
        bar.isHidden = false
        var text = "Downloading \(running.displayName)…"
        if let progress = downloadProgress, progress.totalUnitCount > 0 {
            bar.stopAnimation(nil)
            bar.isIndeterminate = false
            bar.doubleValue = min(max(progress.fractionCompleted, 0), 1)
            text += " \(Int(progress.fractionCompleted * 100))%"
        } else {
            bar.isIndeterminate = true
            bar.startAnimation(nil)
        }
        label.stringValue = text
    }

    /// Download when none runs; Cancel the running one otherwise.
    @objc func downloadClicked(_ sender: Any?) {
        guard downloading == nil else {
            downloadProgress?.cancel()
            return
        }
        guard engine == .apple, let chosen = language, !chosen.installed else {
            NSSound.beep()
            return
        }
        downloading = chosen
        refreshDownloadRow()
        SpeechEngine.download(
            chosen.locale,
            progress: { [weak self] progress in self?.observe(progress) },
            completion: { [weak self] result in self?.downloadFinished(result) })
    }

    /// Holds the request's `Progress` and watches its two numbers, each
    /// change hopped to main and ending in `refreshDownloadRow()`.
    private func observe(_ progress: Progress) {
        downloadProgress = progress
        downloadObservation = progress.observe(
            \.fractionCompleted, options: [.new]
        ) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refreshDownloadRow() }
        }
        refreshDownloadRow()
    }

    /// The completion's one-line forward. The downloaded locale is captured
    /// BEFORE `populateLanguages()` reselects the default, and selected
    /// again after it. A cancel is not reported; any other failure is one
    /// line in the note until the next refresh.
    func downloadFinished(_ result: Result<Void, any Error>) {
        let identifier = downloading?.identifier
        let cancelled = downloadProgress?.isCancelled ?? false
        downloading = nil
        downloadProgress = nil
        downloadObservation = nil
        enginePopup.isEnabled = true
        switch result {
        case .success:
            Transcriber.forgetLanguages()
            languages = Transcriber.supportedLanguages()
            populateLanguages()
            if let identifier { select(languageIdentifier: identifier) }
            refresh()
        case .failure(let error):
            populateLanguages()
            if let identifier { select(languageIdentifier: identifier) }
            refresh()
            guard !cancelled, !(error is CancellationError) else { return }
            noteLabel.stringValue = "The download did not finish: \(error.localizedDescription)"
            noteLabel.isHidden = false
        }
    }

    /// Selects the Language row whose identifier this is; a miss keeps
    /// whatever `populateLanguages()` chose.
    func select(languageIdentifier: String) {
        if let index = languagePopup.itemArray.firstIndex(where: {
            $0.representedObject as? String == languageIdentifier
        }) {
            languagePopup.selectItem(at: index)
        }
    }
}
