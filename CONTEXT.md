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

**Op table**:
The one list of the ops and their arguments, kept by the core and published by it. A row is an op's name and, per **Argument**, its name, its kind and whether it is required — the STRUCTURE of a call and nothing about its meaning, which stays in the prose beside the ops themselves. Everything downstream — the tool catalog an agent reads, the check that compares the two at startup — reads the table rather than restating it, so an argument is written down once and a row that lies is a failing test rather than a call that goes wrong.
_Avoid_: schema, op list, the op enum (the enum is one implementation of the table)

**Argument**:
One named value an **Op** takes, checked against the op table. An argument is part of the CALL: the core knows what it is — ticks, an id, a boolean, a closed vocabulary — and the app says what it is FOR. Distinct from a **Patch**'s keys, which are part of a VALUE and are checked against the property vocabulary instead: `set_video` takes the two arguments `clips` and `patch`, and everything inside that patch is not an argument at all. A name no tool published is not an argument either: it is refused at the door, naming the tool and what it does take, and never dropped.
_Avoid_: parameter, field, key, option

**Patch**:
A partial object a caller writes to say what to change — a clip's property group, a clip's own name and label, or an action's end state. It merges key by key at every depth; a key set to null clears that key, or removes it from an end state; an array replaces the whole list. A key or value the vocabulary does not have is refused by its dotted path, and never dropped, corrected or clamped. The core is the one that reads it, wherever it came from.
_Avoid_: update, delta, diff, replacement
