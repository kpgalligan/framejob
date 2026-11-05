# The Transcript

The Transcript tab shows what is said in your project as text you can read
and click. It is the inspector's tab between Document and the Assistant.

## Opening it

Choose **View ▸ Transcript** (⌃⌘T). The inspector opens if it was hidden, the
Transcript tab shows, and the text takes the keyboard, so the keys below work
at once. You can also click **Transcript** in the inspector's tab strip.

## What it shows

Every word you would hear when the timeline plays, in order: clips on every
track, and clips inside nests where they play. Muted tracks, clips turned down
to silence and clips with their audio switched off are left out. When a nest
is open (⌘↓), the tab shows only what is inside it.

The words come in paragraphs, each with its timecode above it. A new paragraph
starts when:

- the words move to another track,
- the speaker changes (a transcript from AssemblyAI can name speakers),
- there are 1.5 seconds or more between two clips' words on one track, or
- the speaker pauses for 1.5 seconds or more inside a clip.

Some words are shown faint. These are the words a cut would break something
at, so they can't be deleted: words inside a nest (open the nest to work on
them), words under a transition, and words on a locked track. Hold the
pointer over a faint word to read why.

## The bar

A bar sits above the text and stays put while the text scrolls.

- **Words from** chooses whose words to show: **All tracks**, or one track by
  name. With one track chosen, the tab shows only the words on it, and reads
  only the files with a clip on it. If that track goes away, the tab goes
  back to All tracks.
- **Language** chooses the language files are read in on this Mac:
  **Automatic** (your Mac's language, shown in brackets as a code such as
  en-US) or any language your Mac has a speech model for. Choosing one reads
  the files again in that language; the earlier reading is kept too, so
  switching back is immediate. A file with an AssemblyAI transcript keeps
  showing that transcript whichever you choose.

Both choices belong to the window: they stay while it is open, whichever tab
you look at, and are not saved with the project.

Under the two popups, short notes say what the tab is doing and anything it
could not read:

- **Reading “name” on this Mac… 40 % (1 of 2)** while a file is being
  transcribed, with a **Stop** button beside it.
- **Stopped. 2 files not read on this Mac.** after you press Stop, with a
  **Read** button that carries on.
- When two tracks carry the same speech, a note names the two clips, "“Interview.mov”
  (clip 5) and “Mic.wav” (clip 6) carry the same speech.", and asks you to mute one.
- A clip with no words is listed by name with the reason, such as "“Interview.mov”
  (clip 12) — its audio is switched off" or a clip that plays in reverse. The first
  three are listed; "…and 4 more clips with no words." stands for the rest, and
  holding the pointer over it lists them.

## Where the words come from

If a file already has an AssemblyAI transcript (from **File ▸ Generate
Captions…** with AssemblyAI, or **Remove Filler Words**), the tab uses it.
Otherwise the tab transcribes the file on this Mac, in your Mac's language,
the first time you look, and keeps the result in the project, so the next
time is immediate. Transcribing on this Mac takes well under a minute for an
hour of speech, and sends nothing anywhere.

Files are read one at a time, starting with the one under the playhead, and
each file's words appear as soon as it is done. If you switch to another tab,
the reading stops; it picks up when you come back.

**Stop** stops the tab's own reading and leaves the rest of the files unread
until you press **Read** or come back to the tab; editing the timeline or
changing Words from or Language does not start it again. If an agent is
waiting for the same file's words at that moment, its reading goes on.

If your Mac has no speech model installed, the tab says so. Choose **File ▸
Generate Captions…**, pick a language and press **Download**, then come back.

## Following along and jumping

While the video plays, the word being spoken is highlighted and the text
scrolls to keep it in view. If you scroll the text yourself, it stays where
you put it for three seconds before it follows again.

- **Click a word** to move the playhead to it. If the video is playing, it
  keeps playing from there.
- **Click a timecode** to move the playhead to the start of that paragraph.
- **Click a selected clip** on the timeline or the canvas while the Transcript
  shows: the tab stays, and the clip's first word scrolls to the top. The
  playhead does not move. The click that selects a clip doesn't do this, so
  click it again; that first click scrolls to the clip selected before it, if
  there was one.

Editing the timeline updates the text right away, and the words you were
reading stay where they were.

## Cutting by deleting words

Select words, then press ⌫ (or ⌦, **Edit ▸ Delete** or **Edit ▸ Ripple
Delete**): the words and the sound under them come out of every unlocked
track and the gap closes, as one undo step, **Delete Words**. On the timeline
⌫ leaves a gap; in the transcript it closes it, the way deleting text does.

- **Selecting.** Click a word to select it, drag across words to select a
  run, or ⇧-click and ⇧ with the arrows to extend. ⌘A selects every word.
- **The range.** Whatever you select becomes the timeline's in/out range, so
  the timeline shades exactly what will go, and Loop plays it. ⎋ clears the
  selection and the range with it. If you set the range another way (I, O, or
  an agent), the transcript leaves it alone.
- **Where the cut falls.** From where the first word starts to where the next
  word you keep starts, so the pause before the cut stays and the pause after
  it goes, but never more than one second past the last deleted word: a long
  pause after it keeps the rest. Both ends land on whole frames, never past
  the start of a word that stays.
- **Where a word starts.** This Mac's recogniser puts a word's start early,
  often well inside the pause before it. So the tab moves each start to where
  its sound begins: where the voice model (the one Remove Silences uses) first
  hears speech after it, then to the first hundredth of a second loud enough
  to be the word (at least −40 dBFS, and at least 12 dB above the pause's own
  background noise). A word after a pause therefore starts on its sound, and
  deleting the word before it ends there, if that is within the one second
  above, instead of keeping a slice of the pause or taking the start of the
  word you keep. Both steps read what the project measures when it opens a
  file; until the voice model has heard it, the starts are the recogniser's
  own, and the tab moves them as soon as it has, keeping your selection. Words
  from an AssemblyAI transcript, and where any word ends, are left as
  transcribed.
- **Other tracks.** If a word on another track starts before your selection
  and runs into it (two people talking at once), the tab adds it to the
  selection first, so you see everything the cut takes before you press ⌫. A
  word on another track that starts inside your last selected word is not
  added: it is the next word you keep, so the cut ends at its start, and the
  rest of the deleted word after that point can stay in.
- **After the cut** the range clears and the playhead lands where the cut
  was. Deleting words one at a time gives the same result as deleting them
  together, unless a pause of more than a second lies between them.

The tab will not cut, and says why at the foot of the inspector, when:

- a selected word can't be cut (a faint word, as above);
- a locked track has words inside the cut: "Track Music is locked and has
  words in this cut: unlock it to cut here." (a locked track never moves, so
  its words would fall out of step);
- the cut would pass the project's limit of 4096 clips while it is being made:
  "This cut would make 4097 clips; a project holds at most 4096. Lock a track
  that needs no cut, such as a music bed, or cut less."

The word edges come from the transcript itself, so in fast speech a cut can
take the very end of the word before it, or leave a sliver of the word you
deleted. Play the cut back (Loop plays the shaded range before you delete) and
undo if it sounds wrong.

### Shortening a pause

Where the speech stops for more than a second between two words of one clip,
the transcript shows the pause's length after the word before it, in grey:
"[2.4 s]". The pause is what the voice model hears as silence between the end
of that word and the next one. Click it: it is selected on its own, the part
that would go becomes the timeline's in/out range, and the playhead moves to
it. Press ⌫ (or ⌦, **Edit ▸ Delete** or **Edit ▸ Ripple Delete**) and the
pause is shortened to 0.2 s at each end, the gap closed on every unlocked
track, as one undo step, **Delete Pause**. The cut lands on whole frames and
never takes the start of a word. The tab refuses it for the same reasons as
words (a locked track's words in the cut, the 4096-clip limit). A pause
appears once the file's voice model has run (it runs when the project opens
the file); a pause across two clips, inside a nest or under a transition is
not shown. ⎋ clears it; dragging, ⇧ and ⌘A select words only.

An agent cuts words the same way: each word it reads carries the range the
tab would cut it by, and it deletes a run of words with one ripple delete;
it reads the same pauses, each with the range the tab would cut it by.
See [Driving Frame Job from an AI agent](mcp.md).

## Keys

With the transcript text active:

| Key | What it does |
|---|---|
| ← → | Select the previous or next word and move the playhead to it |
| ↑ ↓ | Select the word on the line above or below and move the playhead to it |
| ⇧ with an arrow | Extend the selection without moving the playhead |
| ⌘A | Select every word |
| ⎋ | Clear the selection |
| ⌫ or ⌦ | Delete the selected words and close the gap, or shorten the selected pause |

Every other key works as it does on the timeline: Space plays and pauses, J,
K and L shuttle, I and O set the range, and M adds a marker.

## Not yet

Find (⌘F) does not search the transcript yet.
