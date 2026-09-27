import AppKit

// No storyboard and no @NSApplicationMain: the delegate is created and set
// before NSApplicationMain so applicationWillFinishLaunching can build the
// menu bar (AppDelegate.swift) before the first event is delivered.
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
#if REELCUT_DEV_TOOLS
DevAppearance.apply()
DevAssistantLaunch.installIfAsked()
#endif
// The catalog, the gate and the parity check, once, before any other thread
// exists (spec §11 AI-3): the assistant needs the gate whether or not the MCP
// server is ever started.
AgentLane.prepareAtLaunch()
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
