```json screen
{
  "title": "Settings",
  "project": null,
  "steps": [{"call": "perform_menu_item", "args": {"path": ["Reelcut", "Settings…"]}}],
  "captures": [{"name": "window", "window": "settings"}],
  "expect": [{"capture": "window", "visible_text": "No API key is set."},
             {"capture": "window", "visible_text": "Compact when context reaches"},
             {"capture": "window",
              "visible_text": "Reelcut's own estimate at LiteLLM prices, from its spend ledger. The Anthropic Console shows what your account was billed."}]
}
```

Settings (Reelcut ▸ Settings…) has two panes, one under the other: Transcription
and Assistant. The first is where a person gives Reelcut an AssemblyAI API key, so
that the Generate Captions sheet can transcribe in the cloud instead of on this
Mac; the second is where they give it an Anthropic API key, choose the model for
the Assistant tab, and set how a long conversation is kept in bounds.

Under the "Transcription" heading: an "API key:" field, empty, whose placeholder
reads "Paste your AssemblyAI API key"; a "Region:" pop-up set to "United States";
and the status line "No API key is set." A long grey paragraph explains what
happens when AssemblyAI is chosen: the audio of the files being captioned is
uploaded, transcribed, read back and then deleted from AssemblyAI; nothing is
uploaded until Generate is pressed; captions made on this Mac never leave it; the
published price and the date it was read; and that the key is kept in a file only
the person can read and is never shown again once saved. Along its bottom: "Save"
(blue), "Remove" and "Verify" (both dimmed, since there is no key), and "Account
Page" on the right.

Under the "Assistant" heading, after a wider gap: an "API key:" field, empty,
whose placeholder reads "Paste your Anthropic API key"; a "Model:" field,
empty, whose grey placeholder reads "claude-opus-5-5" (the default when it is
left blank); then the chat settings, two rows of their own. The first is a
ticked checkbox "Compact when context reaches", a short right-aligned field
reading "300,000", and the word "tokens" in grey; the field can be typed in
only while the box is ticked. The second is an unticked checkbox "Clear old
tool results past 150,000 tokens". Neither has a Save: a change applies at
once and keeps the conversation going. Then the status line "No API key is
set." A grey paragraph says the assistant sends the messages, the project's
details and the frames it renders to Anthropic with the person's own key,
which is billed; that it asks before writing a file; that the key is kept in a
file only the person can read and never shown again; that a blank model means
claude-opus-5-5; that changing the key or the model starts a new conversation;
that at the end of a turn past the compaction threshold (20,000 to 900,000
tokens; 300,000 by default) the conversation is replaced by a summary, and
earlier renders don't survive it; that clearing lets Anthropic drop old tool
results from what the model sees, even mid-turn (never tool search results),
each clearing costing a fresh prompt-cache write; and that changing either
keeps the conversation. Along its bottom: "Save" (blue) and "Remove" (dimmed).
It has no Verify and no account link.

Under those two buttons, after a small gap, is what the assistant has cost this
month: one line in the same black as the status lines, here "Nothing recorded in
September 2026 (UTC)." (the capture's launch keeps an empty spend folder, and the
month is the UTC calendar month the capture was taken in). With responses recorded
it reads, for example, "September 2026 (UTC): $0.42 over 12 responses.", and says
how many could not be priced or could not be read rather than counting them as
nothing. Under it, in the small grey of the paragraphs: "Reelcut's own estimate at
LiteLLM prices, from its spend ledger. The Anthropic Console shows what your
account was billed."

In the light capture the ground is white and the headings, labels, status
lines and the month's line black; the paragraphs and the word "tokens" are
mid-grey, the key, model and threshold fields white boxes with grey borders,
the Region pop-up a light-grey pill, and "Account Page" a white button with a
black outline and a hard black shadow.
