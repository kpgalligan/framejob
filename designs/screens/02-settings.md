```json screen
{
  "title": "Settings",
  "project": null,
  "steps": [{"call": "perform_menu_item", "args": {"path": ["Reelcut", "Settings…"]}}],
  "captures": [{"name": "window", "window": "settings"}],
  "expect": [{"capture": "window", "visible_text": "No API key is set."}]
}
```

Settings (Reelcut ▸ Settings…) has one pane, Transcription. It is where a person
gives Reelcut an AssemblyAI API key, so that the Generate Captions sheet can
transcribe in the cloud instead of on this Mac.

Under the "Transcription" heading: an "API key:" field, empty, whose placeholder
reads "Paste your AssemblyAI API key"; a "Region:" pop-up set to "United States";
and the status line "No API key is set." A long grey paragraph explains what
happens when AssemblyAI is chosen: the audio of the files being captioned is
uploaded, transcribed, read back and then deleted from AssemblyAI; nothing is
uploaded until Generate is pressed; captions made on this Mac never leave it; the
published price and the date it was read; and that the key is kept in a file only
the person can read and is never shown again once saved. Along the bottom: "Save"
(blue), "Remove" and "Verify" (both dimmed, since there is no key), and "Account
Page" on the right.

In the light capture the ground is white and the heading, labels and status line
black; the paragraph is mid-grey, the key field a white box with a grey border,
the Region pop-up a light-grey pill, and "Account Page" a white button with a black
outline and a hard black shadow.
