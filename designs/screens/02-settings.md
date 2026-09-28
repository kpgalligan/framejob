```json screen
{
  "title": "Settings",
  "project": null,
  "steps": [{"call": "perform_menu_item", "args": {"path": ["Reelcut", "Settings…"]}}],
  "captures": [{"name": "window", "window": "settings"}],
  "expect": [{"capture": "window", "visible_text": "No API key is set."}]
}
```

Settings (Reelcut ▸ Settings…) has two panes, one under the other: Transcription
and Assistant. The first is where a person gives Reelcut an AssemblyAI API key, so
that the Generate Captions sheet can transcribe in the cloud instead of on this
Mac; the second is where they give it an Anthropic API key and choose the model
for the Assistant tab.

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

Under the "Assistant" heading, after a wider gap: an "API key:" field, empty, whose
placeholder reads "Paste your Anthropic API key"; a "Model:" field, empty, whose
grey placeholder reads "claude-opus-5-5" (the default when it is left blank); and
the status line "No API key is set." A shorter grey paragraph says the assistant
sends the messages, the project's details and the frames it renders to Anthropic
with the person's own key, which is billed; that it asks before writing a file;
that the key is kept in a file only the person can read and never shown again;
that a blank model means claude-opus-5-5; and that changing the key or the model
starts a new conversation. Along its bottom: "Save" (blue) and "Remove" (dimmed).
It has no Verify and no account link.

In the light capture the ground is white and the headings, labels and status lines
black; the paragraphs are mid-grey, the key and model fields white boxes with grey
borders, the Region pop-up a light-grey pill, and "Account Page" a white button
with a black outline and a hard black shadow.
