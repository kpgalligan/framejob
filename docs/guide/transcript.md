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

Some words are shown faint. You will be able to cut words by deleting them in
a later version, and these are the words where a cut would break something:
words inside a nest (open the nest to work on them), words under a transition,
and words on a locked track. Hold the pointer over a faint word to read why.

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
- When two tracks carry the same speech, a note names the two clips, so you
  can mute one.
- A clip with no words is listed with the reason, such as "clip 12 — its audio
  is switched off" or a clip that plays in reverse. The first three are
  listed; "…and 4 more clips with no words." stands for the rest, and holding
  the pointer over it lists them.

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
- **Click a clip** on the timeline or the canvas while the Transcript shows:
  the tab stays, and the clip's first word scrolls to the top. The playhead
  does not move.

Editing the timeline updates the text right away, and the words you were
reading stay where they were.

## Keys

With the transcript text active:

| Key | What it does |
|---|---|
| ← → | Select the previous or next word and move the playhead to it |
| ↑ ↓ | Select the word on the line above or below and move the playhead to it |
| ⇧ with an arrow | Extend the selection without moving the playhead |
| ⌘A | Select every word |
| ⎋ | Clear the selection |

Every other key works as it does on the timeline: Space plays and pauses, J,
K and L shuttle, I and O set the range, and M adds a marker.

## Not yet

Find (⌘F) does not search the transcript yet. Cutting by deleting words comes
in a later version.
