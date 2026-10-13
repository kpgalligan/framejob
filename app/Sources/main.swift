import AppKit

// The supplemental VP9 and AV1 decoders, before anything decodes (spec §11 #216).
DecoderSupport.enable()
// The document controller that knows which paths AppKit's own open is
// reading, before anything else can make one (spec §11 #234).
ProjectDocumentController.install()

// No storyboard and no @NSApplicationMain: the delegate is created and set
// before NSApplicationMain so applicationWillFinishLaunching can build the
// menu bar (AppDelegate.swift) before the first event is delivered.
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
#if FRAMEJOB_DEV_TOOLS
DevAppearance.apply()
DevAssistantLaunch.installIfAsked()
#endif
// The catalog, the gate and the parity check, once, before any other thread
// exists (spec §11 AI-3): the assistant needs the gate whether or not the MCP
// server is ever started.
AgentLane.prepareAtLaunch()
AgentCatalogSnapshot.writeIfAsked()
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
