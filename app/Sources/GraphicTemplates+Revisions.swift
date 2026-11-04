import Foundation

/// Every text of road map 10's six templates the app has bundled (spec §11 VR-44 (a); road map
/// "creator-jobs" VR4b), so Make Vertical knows a project's own copy of an old one by its
/// revision, never by its name. `graphic/tests/vertical_templates.rs`'s trap reads the rows
/// below and fails `make test` until the current text of each of the six is one of them, and
/// `tools/proof/vr4b_proof.py`'s G6 holds them to the history of the files. Pure; names no
/// `rc_*`.
extension GraphicTemplates {
    /// The six that measured by `ctx.height / 1080` before VR-43.
    static let revisedStems = [
        "bar-chart", "callout", "counter", "kinetic-type", "lower-third", "title-card",
    ]

    /// SHA-256 (lowercase hex, `GraphicStore.hex`) of every text of the six the app has
    /// bundled → its stem: each file at 601f4ee3 (unchanged through b0091535, the first
    /// bundling), at b71e20b5 (spec §11 G-45's `meta`) and VR-43's text.
    static let shippedRevisions: [String: String] = [
        // 601f4ee3 … b0091535
        "ce72c9a4795ac2b3a068bf4cc5b3a4c89c76f76c4eb3ed24974450fb3d6242bd": "bar-chart",
        "2fd921fe0352696f157312ddfd532e0d957a9f647f3cc672b51278e1d9ff8c29": "callout",
        "eb7daaa45ab8727188a69b5870af68fdbb736d258d291e5ff709aa014803cf67": "counter",
        "38846b98eeeef0df3d24002834ad4caf9eb8fe67c6a2b9f4eadcf43480125859": "kinetic-type",
        "38b382b65fc518286375923f81b5908f2ea3795f57c2ae8153073a320b9a48db": "lower-third",
        "7efb6b5f520b006c80688fcfdcb9e070bd803a2c8a05db126f94cfb71c3f9677": "title-card",
        // b71e20b5
        "269524824fbd6b89890c0be746bbff45bb02edf1da394aa43b6fab7eda597b82": "bar-chart",
        "60efb8170a425cd78f805d23e048d9c1de6f45412a2b05e8c2a6be2b8e02b822": "callout",
        "eb9320e2ec26d421cd3f3cb92d399128f5f2e38833f7e55fb00dc56fdf1e2233": "counter",
        "23b83131b69d090f47d4f446e3fa31ffa858e10e26907f8b31790defec717b7e": "kinetic-type",
        "9676a844a90c3765c061c146dcf8ea6b4687430da3c7f20c300c0a03899032e3": "lower-third",
        "632be051990c326b7b489b0455abceeb27fdd0c3d4f3e8b7634fd28a36d4b0af": "title-card",
        // VR-43
        "647e0c94c731ddddfdd14d75556559df6558db6bf90e92ccb5fd782d9bfaae9b": "bar-chart",
        "dc74ad1c5f5336013bd7fc87b209c56d6547d4c2530f168602a60fcc32981ebc": "callout",
        "8c389fb86b06fb41d399f2238dc5878285c381654c7d3c78554efca89559e60b": "counter",
        "a98b1733ed222200d3bc66df5bc417ac2ea2fcbaafbd41929906985329d16105": "kinetic-type",
        "4655013213f000518e9cb5357936823d709b96f04a14e22e2c48e1289bef6226": "lower-third",
        "51e35eccbd36fb6200d240480f04ba0d3390c9edc63b31e5fef09c41392a2503": "title-card",
    ]

    private static let byHeight = try? NSRegularExpression(pattern: #"ctx\.height\s*/\s*1080\b"#)

    /// True when `source` measures by the canvas's height: the regex
    /// `ctx\.height\s*/\s*1080\b`.
    static func measuresByHeight(_ source: String) -> Bool {
        guard let byHeight else { return false }
        return byHeight.firstMatch(
            in: source, range: NSRange(source.startIndex..., in: source)) != nil
    }
}
