import AppKit

// No storyboard and no @NSApplicationMain: the delegate is created and set
// before NSApplicationMain so applicationWillFinishLaunching can build the
// menu bar (AppDelegate.swift) before the first event is delivered.
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
#if REELCUT_DEV_TOOLS
DevAppearance.apply()
#endif
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
