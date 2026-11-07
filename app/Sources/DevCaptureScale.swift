import AppKit

#if FRAMEJOB_DEV_TOOLS
/// `-RCDevCaptureScale 1|2|3` — a dev-only LAUNCH default (spec §11 #539):
/// every `snapshot_ui` capture is drawn at that many pixels per point,
/// whatever screen its window is on.
///
/// **Why.** `cacheDisplay` draws at the window's `backingScaleFactor`, so a
/// window that opened on a 1× display captured at 1× and the catalog's
/// pictures came out half the size of their siblings. An agent may not move
/// a person's windows, so the scale is chosen at launch instead, and
/// `screens.py` pins it to 2.
///
/// Read once. Absent, a capture keeps its window's scale. Any other value is
/// named on stderr and ignored. The answer's and the dump's `scale` are the
/// capture's; `window_facts.scale` and the listing's stay the window's.
enum DevCaptureScale {
    static let defaultsKey = "RCDevCaptureScale"

    static let forced: CGFloat? = {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey) else { return nil }
        switch raw {
        case "1": return 1
        case "2": return 2
        case "3": return 3
        default:
            let line = "\(defaultsKey) must be 1, 2 or 3 (got \"\(raw)\"); captures keep the "
                + "window's scale.\n"
            FileHandle.standardError.write(Data(line.utf8))
            return nil
        }
    }()

    /// The scale a capture of `window` is drawn at.
    static func scale(for window: NSWindow) -> CGFloat {
        forced ?? window.backingScaleFactor
    }
}
#endif
