import AVFoundation
import Metal

// Remove Background drawn from the cached masks (road map creator-jobs CO2a2, spec §11
// CO-24…CO-28): the layer's uniform block's cutout group and the mask bound at `texture(4)`,
// which step 7b multiplies into the layer's alpha. Never waits: a frame whose mask is not
// cached draws the layer uncut (CO-6), and CO2b's waits are elsewhere. Names no `rc_*`
// (CJ-8 (l)): the plan and the snapshot come through `ReelProject`.

extension MetalRenderer {
    /// Fills `uniforms`' cutout group for `layer` and answers the texture for `texture(4)`: the
    /// mask of the analysed frame CO-24's lookup finds, or `placeholder` with `cutoutEnabled` 0
    /// on any miss — no cutout, `background` keep, a mask kind other than a media's, a source
    /// other than a composition track, no project or plan segment under the time, a segment of
    /// another media, no cache folder or URL, a pack that does not answer (CO-25), a window that
    /// found no subject (CO-26), a frame outside the coverage, or a mask that will not upload.
    /// The caller never asks on a slate. A picture's layer draws through `imageCutoutMask`.
    func cutoutMask(
        for layer: RecipeLayer, request: AVAsynchronousVideoCompositionRequest,
        instruction: RecipeInstruction?, uniforms: inout LayerUniforms
    ) -> MTLTexture {
        if layer.cutout?.mask.kind == .image {
            return imageCutoutMask(for: layer, instruction: instruction, uniforms: &uniforms)
        }
        guard let cutout = layer.cutout, cutout.background == .remove,
            cutout.mask.kind == .media, case .track(let track) = layer.source,
            let instruction, let project = RecipeSource.shared.project(for: instruction.recipeKey)
        else { return placeholder }
        let t = CompositionBuilder.ticks(request.compositionTime)
        let plan = cutoutMasks.plan(for: instruction.recipeKey, project: project)
        guard let segment = plan.covering(track: track, at: t),
            segment.media == cutout.mask.media,
            let media = project.snapshot.media(cutout.mask.media),
            let cacheDir = ReverseSource.shared.resolution(for: instruction.recipeKey).cache
        else { return placeholder }
        let urls = RecipeSource.shared.lookURLs(for: instruction)
        guard let url = urls[media.id],
            let pack = cutoutMasks.pack(media: media, url: url, cacheDir: cacheDir, urls: urls),
            let window = plan.window(clip: segment.clip, media: media.id),
            cutoutMasks.found(pack, clip: segment.clip, window: window),
            let slot = CutoutLookup.slot(
                pack: pack.pack, ends: pack.ends, coverage: pack.coverage, grid: pack.grid,
                sourceTick: CutoutLookup.sourceTick(segment, at: t),
                pivot: plan.pivots[segment.clip]),
            let texture = cutoutMasks.texture(pack, slot: slot)
        else { return placeholder }
        uniforms.cutoutEnabled = 1
        uniforms.cutoutEdge = Float(min(max(cutout.edge, -1), 1))
        uniforms.cutoutFeather = Float(min(max(cutout.feather, 0), 1))
        return texture
    }

    /// A picture's cutout (road map creator-jobs CO10b, spec §11 CO-107): the one mask of its
    /// image, of the kind its subject asks (`masks` for a person, `foreground`), at source tick
    /// 0 with no pivot, bound as the media branch binds it; `placeholder` with `cutoutEnabled` 0
    /// on any miss — `background` keep, a source other than the mask's own picture, no project,
    /// cache folder or URL, a pack that does not answer, no subject found, or a mask that will
    /// not upload. The mask is in display orientation, as the decode `LayerRenderers.image`
    /// draws is, so the shader is the media branch's.
    private func imageCutoutMask(
        for layer: RecipeLayer, instruction: RecipeInstruction?, uniforms: inout LayerUniforms
    ) -> MTLTexture {
        guard let cutout = layer.cutout, cutout.background == .remove,
            cutout.mask.kind == .image, case .image(let id) = layer.source,
            id == cutout.mask.media, let instruction,
            let project = RecipeSource.shared.project(for: instruction.recipeKey),
            let media = project.snapshot.media(id),
            let cacheDir = ReverseSource.shared.resolution(for: instruction.recipeKey).cache
        else { return placeholder }
        let urls = RecipeSource.shared.lookURLs(for: instruction)
        let kind: AnalysisKind = cutout.mask.subject == .foreground ? .foreground : .masks
        guard let url = urls[media.id],
            let pack = cutoutMasks.pack(
                kind: kind, media: media, url: url, cacheDir: cacheDir, urls: urls),
            cutoutMasks.found(pack, clip: layer.clip, window: 0...1),
            let slot = CutoutLookup.slot(
                pack: pack.pack, ends: pack.ends, coverage: pack.coverage, grid: pack.grid,
                sourceTick: 0, pivot: nil),
            let texture = cutoutMasks.texture(pack, slot: slot)
        else { return placeholder }
        uniforms.cutoutEnabled = 1
        uniforms.cutoutEdge = Float(min(max(cutout.edge, -1), 1))
        uniforms.cutoutFeather = Float(min(max(cutout.feather, 0), 1))
        return texture
    }
}
