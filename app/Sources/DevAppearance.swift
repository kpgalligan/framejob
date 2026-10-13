import AppKit

#if FRAMEJOB_DEV_TOOLS
/// `-RCDevAppearance light|dark` — a dev-only LAUNCH default (road map 11's
/// V3): the whole app's appearance, set on `NSApp` in `main.swift` before
/// `NSApplicationMain`, so before the first window is built.
///
/// **Why at launch and not per capture.** `snapshot_ui` used to set an
/// appearance on the live window for one capture (V2a). Measured in V3, that
/// repaints only the views that resolve their colours when they draw; a colour
/// taken once when a view was built keeps the launch appearance, so the
/// capture was a mix no person ever sees. Set here, every view is built in the
/// asked appearance, whatever the host runs — the offscreen harness's own rule
/// (`tools/proof/harness/main.swift` sets `NSApp.appearance` before it builds).
///
/// Absent, the app follows the system as it always does. Any other value is
/// named on stderr and ignored.
enum DevAppearance {
    static let defaultsKey = "RCDevAppearance"

    static func apply() {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey) else { return }
        switch raw {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            let line = "\(defaultsKey) must be light or dark (got \"\(raw)\"); the "
                + "system's appearance is kept.\n"
            FileHandle.standardError.write(Data(line.utf8))
        }
    }
}
#endif
