// app/Sources/ProjectDocument+Alerts.swift — `present(_:)`: every error the
// document shows, one alert sheet at a time (#195).
//
// AppKit drops an error sheet asked for while another sheet is attached, and
// never attaches it after the first ends (measured in B29, and in
// `relink_sheet_probe.py` A1, A3, A4 and A5). So each error waits in
// `alertQueue`, and the next is asked for only when none of the queue's own
// alerts is up and the window has no sheet attached: a main-queue turn after
// the last alert's `didPresent`, or after the window's last sheet ends.

import AppKit

/// The document's alerts not yet shown (#195).
struct DocumentAlertQueue {
    var waiting: [any Error] = []
    var showing = false          // one of the queue's own alerts is attached
    var watchingSheets = false   // the window's didEndSheet observer is registered
}

extension ProjectDocument {
    /// Errors never crash and never go to the console alone: they land in a
    /// sheet on the document's window when it has one, in order, one at a
    /// time; with no window, app-modal at once.
    func present(_ error: any Error) {
        guard windowForSheet != nil else {
            alertQueue.waiting.removeAll()
            _ = presentError(error)
            return
        }
        alertQueue.waiting.append(error)
        drainAlerts()
    }

    /// Shows the next waiting error, unless one of the queue's alerts is up
    /// or the window has any sheet attached; then the sheet's end drains.
    private func drainAlerts() {
        guard let window = windowForSheet else {
            alertQueue.waiting.removeAll()
            return
        }
        guard !alertQueue.showing else { return }
        if window.attachedSheet != nil {
            if !alertQueue.watchingSheets {
                alertQueue.watchingSheets = true
                NotificationCenter.default.addObserver(
                    self, selector: #selector(alertWindowDidEndSheet(_:)),
                    name: NSWindow.didEndSheetNotification, object: window)
            }
            return
        }
        guard !alertQueue.waiting.isEmpty else { return }
        let next = alertQueue.waiting.removeFirst()
        alertQueue.showing = true
        presentError(next, modalFor: window, delegate: self,
                     didPresent: #selector(queuedAlertDidPresent(_:contextInfo:)),
                     contextInfo: nil)
    }

    @objc private func queuedAlertDidPresent(
        _ didRecover: Bool, contextInfo: UnsafeMutableRawPointer?
    ) {
        alertQueue.showing = false
        DispatchQueue.main.async { [weak self] in self?.drainAlerts() }
    }

    @objc private func alertWindowDidEndSheet(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.drainAlerts() }
    }
}
