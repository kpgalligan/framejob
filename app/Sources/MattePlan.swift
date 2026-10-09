/// A frame's matte schedule (spec §11 MT-9), planned before any matte is
/// drawn: the order the recipe lists its mattes in (deepest container
/// first), the cut sets each step resolves, and the composites each step
/// gives back to `MattePool`. Pure arithmetic over group numbers, so a probe
/// reads it without a device (`tools/proof/matte_pool_probe.py`).
///
/// A cut set is resolved at the step that draws the LAST matte it names, so
/// every matte in it is drawn by then; a set naming a group no step draws is
/// never resolved, and the layer it cuts fails the frame (`unordered`), as
/// before. A group's composite is given back once every set naming it is
/// resolved — at its own step when no set reads it later — so the next step's
/// `takeComposite` draws into it.
struct MattePlan: Equatable {
    struct Step: Equatable {
        /// A `RecipeMatteGroup.group`, in `groups` order.
        let group: Int
        /// The cut sets whose last-drawn group is this one, in the order
        /// they first appear in `cuts`.
        let resolve: [[Int]]
        /// The groups whose composites no later step's `resolve` reads,
        /// given back after `resolve`, in `groups` order.
        let release: [Int]
    }

    let steps: [Step]
    /// The most composites held at once: a step's own counted before its
    /// release.
    let compositesLive: Int
    /// The distinct cut sets some step resolves: one coverage each.
    let coverages: Int

    /// `groups` is `recipe.mattes`' groups in order; `cuts` every layer's
    /// non-empty `matte.cut`, in layer order, duplicates allowed.
    init(groups: [Int], cuts: [[Int]]) {
        // The step each group is drawn at (the first, should one repeat).
        var drawnAt: [Int: Int] = [:]
        for (step, group) in groups.enumerated() where drawnAt[group] == nil {
            drawnAt[group] = step
        }
        // Each distinct set at the step that draws the last group it names.
        var resolves = [[[Int]]](repeating: [], count: groups.count)
        var seen = Set<[Int]>()
        for cut in cuts where !cut.isEmpty && seen.insert(cut).inserted {
            let at = cut.compactMap { drawnAt[$0] }
            guard at.count == cut.count, let last = at.max() else { continue }
            resolves[last].append(cut)
        }
        // The last step that reads each group's composite: its own, or the
        // latest that resolves a set naming it.
        var lastRead = drawnAt
        for (step, sets) in resolves.enumerated() {
            for cut in sets {
                for group in cut { lastRead[group] = max(lastRead[group] ?? step, step) }
            }
        }
        var releases = [[Int]](repeating: [], count: groups.count)
        for (step, group) in groups.enumerated() where drawnAt[group] == step {
            if let last = lastRead[group] { releases[last].append(group) }
        }
        steps = groups.indices.map {
            Step(group: groups[$0], resolve: resolves[$0], release: releases[$0])
        }
        var live = 0
        var most = 0
        for step in steps {
            live += 1
            most = max(most, live)
            live -= step.release.count
        }
        compositesLive = most
        coverages = resolves.reduce(0) { $0 + $1.count }
    }
}
