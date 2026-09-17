# Reelcut

A screencast video editor. A project is a document of tracks and clips that the core edits through ops; the app and the agent both speak in those ops. This glossary holds the terms the spec and the op table use, sharpened as decisions settle them.

## Language

**Op**:
One edit to a project, named by a row of the op table and applied whole: it either yields a new project or changes nothing.
_Avoid_: command, mutation, action (an action is an animation on a clip)

**Patch**:
A partial property object an op merges into a clip's properties. It merges key by key at every depth; a key set to null clears that key; an array replaces the whole list. A key or value the vocabulary does not have is refused by its path and never dropped or corrected.
_Avoid_: update, delta, diff, replacement
