import AppKit

/// What a document gives back when it closes: the body of `close()`, a pure move out of
/// `ProjectDocument.swift` (#568), which keeps the override and the once-only flag
/// `didReleaseRecipeKey`, since an extension cannot hold a stored property.
extension ProjectDocument {
    func releaseOnClose() {
        // The compositor's only channel to this document. Dropping it here —
        // not in a deinit, which a retained window controller can delay
        // indefinitely — is what keeps a closed document's Rust project from
        // living for the life of the process.
        if !didReleaseRecipeKey {
            didReleaseRecipeKey = true
            RecipeSource.shared.unregister(recipeKey)
            ReverseSource.shared.unpublish(recipeKey)
            RampAudioRenders.shared.release(owner: recipeKey)
            stopGraphicStore()
        }
    }
}
