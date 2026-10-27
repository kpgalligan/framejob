#if FRAMEJOB_UPDATER
import AppKit
import Sparkle

/// Frame Job ▸ Check for Updates… and Sparkle's scheduled check — the
/// published build's updater (spec §11 PUB-6..PUB-9).
///
/// **Distribution's alone (PUB-7).** The whole file compiles only under
/// `FRAMEJOB_UPDATER`, which `project.yml` sets in the Distribution
/// configuration and nowhere else; the feed (`SUFeedURL`) and the EdDSA public
/// key (`SUPublicEDKey`) are set there too. `make typecheck`, the offscreen
/// harness and every probe compile `app/Sources` without Sparkle, so no
/// Sparkle name may appear outside this condition. Sparkle.framework is
/// embedded in every configuration (xcodegen links a package per target) but
/// loaded only in Distribution: Debug and Release link with
/// `-dead_strip_dylibs`, because an ad-hoc hardened build refuses to load it
/// (dist_check D35).
///
/// **Sparkle's own defaults (PUB-9).** The standard controller and user driver:
/// Sparkle asks on the second launch whether to check automatically, checks
/// once a day when allowed, and never installs without asking.
///
/// The controller is a static, because `AppDelegate` holds no stored
/// properties (`AppDelegate+Recording.swift` says why); `startUpdater()` is
/// what first touches it, at launch. The menu item is a nil-target selector
/// validated in `AppDelegate.validateMenuItem` against the updater's
/// `canCheckForUpdates`. It has no MCP mirror: it edits no project, and it
/// exists only in the build that has no dev tools (PUB-7).
extension AppDelegate {
    static let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    /// Called from `applicationDidFinishLaunching`: creating the controller
    /// starts the updater and its scheduled check.
    func startUpdater() {
        _ = Self.updaterController
    }

    /// Frame Job ▸ Check for Updates… (Distribution only, spec §11 PUB-7).
    @objc func checkForUpdates(_ sender: Any?) {
        Self.updaterController.checkForUpdates(sender)
    }
}
#endif
