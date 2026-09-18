# Reelcut

A screencast video editor. A project is a document of tracks and clips that the core edits through ops; the app and the agent both speak in those ops. This glossary holds the terms the spec and the op table use, sharpened as decisions settle them.

## Language

**Op**:
One edit to a project, named by a row of the op table and applied whole. It yields a new project, changes nothing, or is refused with a sentence saying what was wrong; a refusal leaves the project exactly as it was and makes no undo step.
_Avoid_: command, mutation, action (an action is an animation on a clip)

**Patch**:
A partial object a caller writes to say what to change — a clip's property group, a clip's own name and label, or an action's end state. It merges key by key at every depth; a key set to null clears that key, or removes it from an end state; an array replaces the whole list. A key or value the vocabulary does not have is refused by its dotted path, and never dropped, corrected or clamped. The core is the one that reads it, wherever it came from.
_Avoid_: update, delta, diff, replacement
