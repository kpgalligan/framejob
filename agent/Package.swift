// swift-tools-version: 6.0
// The assistant helper in Swift (road map "swift-helper", spec §11 SA-1): the agent loop in its
// own process, on Slaude (the Claude API in Swift). Ported once from Doctored's helper at its
// commit b524babc (the owner's answer 2 (a)); agent/CLAUDE.md has the rules. The app bundles its
// release product, built by tools/agent/build_helper.sh (spec §11 SA-8); `make agent-test` runs
// this suite.
import PackageDescription

/// The helper's own targets build warning-free in the suite (`make agent-test` sets
/// FJ_AGENT_STRICT=1, so the gate's test step holds them to it); Slaude's are never held to it,
/// and a shipping build that does not set it cannot be failed by a newer compiler's diagnostic.
let strict: [SwiftSetting] =
    Context.environment["FJ_AGENT_STRICT"] == "1" ? [.unsafeFlags(["-warnings-as-errors"])] : []

let package = Package(
    name: "FrameJobAgent",
    // The app's floor in the string form on purpose: `.v26` needs PackageDescription 6.2 and is
    // refused under 6.0 (spec §11 SA-1).
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "framejob-agent", targets: ["framejob-agent"]),
    ],
    dependencies: [
        // Pinned by exact revision; Package.resolved is committed beside this file.
        .package(
            url: "https://github.com/kpgalligan/Slaude",
            revision: "4c6c2ca435350741796c3d461720a61e7149b378"),
    ],
    targets: [
        .target(
            name: "FrameJobAgentKit",
            dependencies: [.product(name: "Anthropic", package: "Slaude")],
            // A relative symlink to agent/prices/anthropic.json, which stays where `make prices`
            // writes it; compiled in as PackageResources.anthropic_json (spec §11 SA-3).
            resources: [.embedInCode("anthropic.json")],
            swiftSettings: strict),
        .executableTarget(
            name: "framejob-agent",
            dependencies: ["FrameJobAgentKit", .product(name: "Anthropic", package: "Slaude")],
            swiftSettings: strict),
        .testTarget(
            name: "FrameJobAgentKitTests",
            dependencies: ["FrameJobAgentKit", .product(name: "Anthropic", package: "Slaude")],
            swiftSettings: strict),
    ]
)
