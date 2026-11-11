import AppKit

/// What a document gives back when it closes: the body of `close()`, a pure move out of
/// `ProjectDocument.swift` (#568), which keeps the override and the once-only flag
/// `didReleaseRecipeKey`, since an extension cannot hold a stored property.
///
/// **Nothing a closed document must give back is left to a deinit** (spec §11 #568). AppKit
/// keeps a closed window for as long as it likes: in an instance driven in the background,
/// until another window opens. The editor's deinit was the only thing that dropped the
/// player's item. Since #592 the window gives its editor up when it closes
/// (`EditorWindow.close()`, after this has run), so only the bare window waits on AppKit;
/// what must go at the close still goes here.
extension ProjectDocument {
    func releaseOnClose() {
        // The compositor's only channel to this document. Dropping it here —
        // not in a deinit, which a retained window controller can delay
        // indefinitely — is what keeps a closed document's Rust project from
        // living for the life of the process.
        if !didReleaseRecipeKey {
            didReleaseRecipeKey = true
            // The players first, through `editors` and not `windowControllers`: the window's
            // close button has already removed the window controller when AppKit calls `close()`.
            for editor in editors.allObjects { editor.shutDownForClose() }
            RecipeSource.shared.unregister(recipeKey)
            ReverseSource.shared.unpublish(recipeKey)
            RampAudioRenders.shared.release(owner: recipeKey)
            stopGraphicStore()
        }
    }
}
