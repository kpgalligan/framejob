import AppKit

/// The colours a clip can be labelled with — and the ONE home of the
/// marker-colour vocabulary, which spec §5.2 stores as a NAME (`red`,
/// `orange`, …) on a marker's `color` and, since format version 3, on a
/// clip's `label`.
///
/// **The core stores the name unvalidated.** That is the `Marker.color`
/// policy, kept on purpose: a build that policed the list would refuse a
/// project written by a newer one. So the six names, their order, their
/// display names and their inks are decided here and nowhere else — the
/// timeline's label dot, the ruler's marker flags
/// (`TimelineRulerView.markerColor` routes through `color(named:)`), the
/// Clip ▸ Label submenu and the Clip tab all read this enum, and an unknown
/// name is an error nowhere: it draws in `DS.textStrong`, the neutral ink,
/// so a project from a newer build still opens and still shows SOMETHING
/// where its label is.
///
/// The inks are the ruler's marker palette, verbatim — two system colours
/// at either end and the three brand inks between — so a label reads the
/// same in both appearances as the marker it matches.
enum ClipLabel: String, CaseIterable {
    case red
    case orange
    case yellow
    case green
    case blue
    case purple

    /// The menu title: the name, capitalised.
    var displayName: String { rawValue.capitalized }

    var color: NSColor {
        switch self {
        case .red: return .systemRed
        case .orange: return DS.coral
        case .yellow: return DS.butter
        case .green: return DS.forest
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        }
    }

    /// The ink for a stored name, case-insensitively; `DS.textStrong` for a
    /// name this build does not know.
    static func color(named name: String) -> NSColor {
        ClipLabel(rawValue: name.lowercased())?.color ?? DS.textStrong
    }
}
