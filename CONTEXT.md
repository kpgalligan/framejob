# Reelcut

A screencast video editor. A project is a document of tracks and clips that the core edits through ops; the app and the agent both speak in those ops. This glossary holds the terms the spec and the op table use, sharpened as decisions settle them.

## Language

**Op**:
One edit to a project, named by a row of the op table and applied whole. An op the core understood answers one of exactly three ways: it applies and yields a new project, it is an identity, or it is refused. A request the core could not read at all is none of the three — that is a mistake in the asking rather than an answer about the project.
_Avoid_: command, mutation, action (an action is an animation on a clip)

**Identity**:
An op that was understood and had nothing to change: the project already says what was asked, or the op was handed an empty selection. It leaves the project exactly as it was, makes no undo step, and has nothing to explain — a caller told about a rule here would go looking for one it did not break.
_Avoid_: no-op, failure, "nothing happened" (all three hide the difference from a refusal)

**Refusal**:
A rule declining an op, in that rule's own sentence: which track is locked, which clips still show the media, by how many ticks two clips would overlap and how long the shorter one is. Like an identity it leaves the project exactly as it was and makes no undo step; unlike an identity it says why, and it names what a caller could send instead rather than restating the rule. A refusal is not an error — an error is a request that could not be read.
_Avoid_: error, rejection, failure, "invalid"

**Patch**:
A partial object a caller writes to say what to change — a clip's property group, a clip's own name and label, or an action's end state. It merges key by key at every depth; a key set to null clears that key, or removes it from an end state; an array replaces the whole list. A key or value the vocabulary does not have is refused by its dotted path, and never dropped, corrected or clamped. The core is the one that reads it, wherever it came from.
_Avoid_: update, delta, diff, replacement
