# HDR and colour management

Frame Job reads each source as what it is: iPhone HDR video, HDR10 files, wide-gamut footage and camera log. It converts each one into the project's working colour before any grade, key or blend touches it. A project works in **SDR** (Rec. 709, the default) or in **HDR (HLG)** (Rec. 2100 HLG over BT.2020). An HDR project exports an HLG master, an HDR10 file or an SDR version, and you can preview that SDR version at any time. This page covers telling Frame Job how a file was shot, choosing the project's dynamic range and its blending, and the depth and colour you get in exports and saved frames.

Grading itself (Light, Color, curves, looks and the scopes) is covered in [Colour grading](color-grading.md). The export sheet as a whole is covered in [Export](export.md).

## How sources are read

You don't need to set anything for most footage. Each frame is converted once, at the very start of the picture pipeline, into the project's working colour. The chroma key and every grade then see the converted picture.

| Source | In an SDR project | In an HDR (HLG) project |
|---|---|---|
| Ordinary Rec. 709 or untagged video, stills, recordings | Drawn as is | Lifted to HDR reference white (203 cd/m², HLG 75 %), so it looks the same as it does in SDR |
| HLG video (e.g. iPhone HDR) | Converted to Rec. 709 by Frame Job, highlights rolled off smoothly | Kept as HLG, highlights above white intact |
| PQ / HDR10 video or stills | Converted to Rec. 709, highlights rolled off at the file's own peak (see [HDR10 peak](#hdr10-peak)) | Real HDR: display light up to 1,000 cd/m², brighter highlights rolled off to fit |
| Wide-gamut SDR (BT.2020 or P3 primaries with an SDR transfer, sRGB included) | Converted to Rec. 709; colours outside Rec. 709 are eased toward their brightness and rolled off instead of clipped | Converted into BT.2020 and lifted |
| Camera log (set in the Media tab) | Converted to a normal-looking Rec. 709 picture | Converted to real HDR |
| Text, captions, shapes, graphics, the background colour | Drawn as is | Lifted to HDR reference white with the SDR sources |

The conversion is Frame Job's own. It works the same way in the preview, in every export, in rendered and saved frames, and in the timeline's filmstrip and the Media tab's thumbnails. Changing a file's Camera Log redraws its thumbnails. An HLG or PQ still's thumbnail appears once its converted tile is ready, a moment after import.

**View ▸ Show Ungraded** (⌃⌘U) turns off the grades, but this source conversion stays on. The conversion is how the file is read, not part of the grade.

## Camera log

Log footage looks flat and grey until it is converted. The **Camera Log** section of the **Media** tab tells Frame Job which curve a video file was shot with. The section appears once the project has a video file.

1. Open the **Media** tab in the inspector and click the file in the list.
2. Choose a curve from the **Log** popup.

It is a setting on the *file*, so every clip of that file follows it, reversed clips included. It is one undo step, **Camera Log**. A line under the popup says what is set. It reads "Select a video in the list" when the selected row is not a video file, and the popup is disabled. The section's header shows the selected file's setting (its curve or LUT name), so you can read it with the section collapsed.

Relinking a file (**Relink…**) keeps its Camera Log setting.

### The Log popup

| Item | Curve | Camera gamut |
|---|---|---|
| None | No conversion: shows the log picture as recorded | — |
| Apple Log | Apple Log | BT.2020 |
| Apple Log 2 | Apple Log | Apple Wide Gamut |
| S-Log3 / S-Gamut3.Cine | Sony S-Log3 | S-Gamut3.Cine |
| S-Log3 / S-Gamut3 | Sony S-Log3 | S-Gamut3 |
| V-Log / V-Gamut | Panasonic V-Log | V-Gamut |
| C-Log2 / Cinema Gamut | Canon Log 2 | Cinema Gamut |
| C-Log2 / BT.2020 | Canon Log 2 | BT.2020 |
| C-Log3 / Cinema Gamut | Canon Log 3 | Cinema Gamut |
| C-Log3 / BT.2020 | Canon Log 3 | BT.2020 |
| LUT: *name* | Each `.cube` LUT already in the project | — |
| Use LUT… | Choose a `.cube` file that converts this file's log to Rec. 709 | — |

Each built-in curve follows its maker's published curve and gamut; Cinema Gamut's primaries come from the ACES project's Canon transform. Frame Job's display transform puts 18 % grey at 42 % and 90 % white at about 78 %. Highlights roll off smoothly up to about six stops over grey. In an HDR (HLG) project the same footage becomes real HDR, with 18 % grey at HLG 38 % and no roll-off.

Whether a log file is stored in video range or full range is read from the file itself.

### Detection on import

An iPhone **Apple Log** or **Apple Log 2** file is recognised by its label when you import it, so it looks like normal video straight away. The line under the popup then adds "— from the file", for example "Apple Log — from the file". Sony, Panasonic and Canon files carry no label Frame Job can read, so choose their curve by hand. To see an Apple Log file's raw log picture, choose **None**.

### Using your own LUT

**Use LUT…** opens a file panel asking you to "Choose a .cube LUT that converts this file's log footage to Rec. 709." The LUT is added to the project's media list and becomes this file's conversion, all in one **Camera Log** step. Its output is taken as Rec. 709. Other files can then pick it from the popup as **LUT: *name***. If that LUT is already in the Media list, its entry is reused instead of a second one being added. A file that can't be read as a LUT shows an error.

A LUT that is some file's Camera Log counts as used: **Unused only** hides it, and Remove asks first.

If you remove that LUT from the Media list, the alert says how many files use it as their Camera Log, for example "the Camera Log of 2 files, which lose it". **Remove and Clear Looks** removes it, and those files go back to no conversion.

### Camera Log and looks

Camera Log is applied before any look. If a clip's file is converted by Camera Log and you also give the clip a camera LUT as a look, the Look section warns: "This clip's file is converted by Camera Log; a camera LUT here converts it twice." It is only a warning, because a creative LUT on top is legitimate. See [Colour grading](color-grading.md).

*Agents:* `set_media_color` (`color` is `{log, gamut?}`, `{lut}` or `null`); `get_project`'s `media[].color` shows `detected: true` for a file set at import.

## HDR10 peak

A PQ (HDR10) file has its highlights roll off to white at the brightness its own metadata names. Import reads the peak from the file: MaxCLL first, then the mastering display's maximum. It looks in the file's sample description and, when that names none, in the video stream's own HDR10 metadata (HEVC SEI, or AV1 metadata), so files from ffmpeg, HandBrake or x265 are read too. A file that names no peak is treated as 1,000 cd/m².

The **HDR10** section of the **Media** tab appears once the project has a PQ file. That can be a video, or a PQ still image (PNG, HEIF or AVIF). Click the file in the list to see and change its peak. The section's header shows the selected file's peak in cd/m² (for example "4,000 cd/m²"), so you can read it with the section collapsed.

| Control | What it does |
|---|---|
| **Peak** | The peak in cd/m², 1 to 10,000, with quick values 1,000, 2,000, 4,000 and 10,000. Typing a value overrides the file's. |
| **Use File's** | Goes back to the peak the file's metadata names. It is available only while an override is set. |

The line under the controls says where the peak came from:

- "Mastered at 4,000 cd/m² (MaxCLL, from the file)": the file's own value.
- "No HDR10 metadata — 1,000 cd/m² assumed": the file names no peak.
- "Set by hand; the file says 1,000 cd/m² (mastering display)": an override.
- "Set by hand; the file has no HDR10 metadata": an override on a file with no metadata.

Each change is one undo step, **PQ Peak**. Changing the peak keeps the file's Camera Log setting, and changing the Camera Log keeps the peak. When the selected row is not a PQ file, the section reads "Select a PQ file in the list" and its controls are disabled.

*Agents:* `set_media_color` with `peak` (a whole number of cd/m², 1–10000; a PQ still takes `{peak}` alone). `color` replaces the Camera Log and the peak together, so send both to keep both; `color: null` clears both the Camera Log and a peak override, and the peak goes back to the file's own reading. `media[].color.pq` shows the file's own reading.

## The project's dynamic range

The **Document** tab's **Canvas** section has a **Dynamic Range** popup:

| Item | What the project works in | Default |
|---|---|---|
| SDR | Rec. 709 | Yes |
| HDR (HLG) | Rec. 2100 HLG over BT.2020 | |

The Document tab's summary shows the choice in its **Colour** row: "SDR — Rec. 709" or "HDR — Rec. 2100 HLG". Switching is one undo step, **Dynamic Range**.

In an HDR (HLG) project:

- **HDR sources keep their range.** An iPhone HDR clip keeps its highlights above white, and PQ and camera-log footage become real HDR.
- **SDR material is lifted to HDR reference white.** That covers SDR video, stills, screen recordings, titles, captions, shapes, graphics, the background and shadow colours. White is fixed at 203 cd/m² (HLG 75 %), so SDR material looks as it did and HDR highlights rise above it. There is no setting for the reference white.
- **HDR stills.** A still labelled HLG or PQ is drawn in its own colour, as HDR. An iPhone HDR photo with a gain map (HEIC) shows its HDR highlights in an HLG project. An SDR project draws its ordinary picture. In the SDR version (Show SDR Version, JPEG frames, SDR-version exports) a gain-map photo is its HDR rendition toned down, not the photo's own SDR image.
- **Grades keep their settings.** Switching changes no clip and no grade value. The grade's maths uses BT.2020's weights in an HLG project.
- **The chroma key keeps keying the colour it was picked on.** A key on an HLG, PQ or camera-log source compares the colour an SDR project would show, so it cuts the same pixels after the switch, or very nearly: HLG footage over P3 or BT.709 primaries, PQ highlights above 1,000 cd/m² and a key picked on a gain-map photo key close to, but not exactly, what they keyed before.
- **Qualifiers read the HLG signal.** An adjustment clip's qualifier ranges are measured on the HLG values, so re-pick them after switching.
- **A `.cube` look reads its values as Rec. 709.** The Look section warns: "This project is HDR (HLG): a .cube LUT reads its values as Rec. 709."
- **Frames are saved as HDR.** **File ▸ Save Frame…** (⌥⌘E) as PNG or HEIC writes a 16-bit PNG or a 10-bit HEIC labelled BT.2100 HLG. A JPEG writes the SDR version.

*Agents:* `set_canvas` with `output` set to `"sdr"` or `"hlg"`.

### Show SDR Version

**View ▸ Show SDR Version** shows the preview as the project's SDR version: the picture that 8-bit formats, JPEG frames and the SDR-version export get. A tag reading "SDR Version" sits in the preview's top-left corner while it is on, after the Ungraded and Selection tags when those are on. The scopes read the SDR version while it is on (see [Scopes in an HDR project](#scopes-in-an-hdr-project)).

- It is a checkmark toggle with no shortcut. It is always enabled.
- It belongs to the window. It reaches the preview and the Preview Window (**View ▸ Preview Window**, ⇧⌘P), never an export or a saved frame, and it is not remembered: a new window starts with it off.
- In an SDR project, the picture already is the SDR version, so no pixel changes, but the tag still shows.

The SDR version brings the HLG master back to Rec. 709. Everything up to reference white comes back as it was, so a white title stays white (about 248 of 255). Only the highlights above reference white are rolled off.

*Agents:* `render_frame` with `sdr_version: true` draws the same picture. The menu toggle itself never reaches the tool.

### Scopes in an HDR project

In an HLG project, **View ▸ Scopes** (⌃⌘W) reads the HLG signal:

- The waveform and parade label their lines in cd/m²: 0, 10, 51, 203 and 1000 at 0, 25, 50, 75 and 100 %.
- The 75 % line, HDR reference white, is dashed. Titles and SDR material sit on it, and HDR highlights rise above it.
- Luma and the vectorscope use BT.2020's weights. The vectorscope's colour-bar targets and skin line are BT.2020's too.
- Each slot's caption reads "HLG · cd/m²" (waveform, parade) or "Rec. 2100 HLG" (vectorscope, histogram), where an SDR project's reads "Rec. 709 · encoded".

The scopes measure the picture on screen. With **Show SDR Version** on, they read the SDR version exactly as they would in an SDR project. **Show Ungraded** keeps the HLG reading. For everything else about the scopes, see [Colour grading](color-grading.md).

*Agents:* `render_frame`'s scope options. In an HLG project each scope's JSON adds `signal: "hlg"`, and the waveform, parade and histogram add a `scale` (ticks in cd/m², reference white at 75 %).

## Blending: encoded or linear light

The **Document** tab's **Canvas** section also has a **Blending** popup. It sets how layers mix where they overlap: in opacity, dissolves, soft edges, blend modes and glows.

| Item | What it does | Default |
|---|---|---|
| Encoded | Layers blend on their encoded values, as most editors do | Yes |
| Linear light | Layers blend as light. A dissolve between two saturated clips keeps its brightness instead of dipping dark at the midpoint. A title fading over video and a blurred or feathered edge come out brighter, and a glow adds light the way light does. | |

The change is one undo step, **Blending**. It changes no clip and no grade. Grades, the chroma key, qualifiers, Show Selection, luma mattes and the scopes still read the same values they did, so a grade looks the same either way. In an HDR (HLG) project, "linear" means HLG's scene light.

*Agents:* `set_canvas` with `blending` set to `"encoded"` or `"linear"`.

## Exporting HDR

In an HDR (HLG) project, the export sheet gets a **Dynamic Range:** row under **Format**. It decides what the 10-bit formats write:

| Item | What the file holds | Default |
|---|---|---|
| HDR (HLG) | The BT.2100 HLG master, Dolby Vision off | Yes |
| HDR10 (PQ) | BT.2100 PQ, mastered at 1,000 cd/m² | |
| SDR version | The SDR version, Rec. 709 | |

- The row is live only on **HEVC 10-bit (MP4)**, **AV1 (MP4)**, **AV1 (WebM)**, **VP9 (WebM)**, **ProRes 422 (MOV)** and **ProRes 4444 (MOV)**. On every other video format it is disabled and shows **SDR version**, because those formats always write the SDR version: H.264, HEVC, HEVC with Alpha, Animated GIF and Animated PNG.
- **VP9 (WebM)** writes HLG and HDR10 as 10-bit VP9 Profile 2, and the SDR version as 8-bit Profile 0. VP9 itself cannot say which transfer it uses, so the WebM file's colour information is what tells a player it is HLG or PQ.
- An HDR10 file carries fixed HDR10 metadata: a P3 D65 mastering display of 0.005–1,000 cd/m², MaxCLL 1,000 and MaxFALL 0. Its picture never goes above 1,000 cd/m², so the metadata is always accurate. The Media tab's HDR10 Peak describes a *source* file and does not change this.
- The choice applies to that one sheet only. It is not remembered for the next export or saved in an export preset.
- An SDR project's export sheet has no Dynamic Range row.

For formats, sizes and the export queue, see [Export](export.md).

*Agents:* `export` with `dynamic_range` set to `"hlg"`, `"pq"` or `"sdr"`. `hlg` and `pq` are refused on an 8-bit preset ("… is 8-bit and writes the SDR version …") and in an SDR project ("… needs an HLG project; set_canvas output \"hlg\" first"). `export` answers an `export_id` at once; once `export_status` reports the job `done`, its `dynamic_range` names the picture that was written (`hlg`, `pq` or `sdr`).

## Precision and bit depth

- **16-bit float compositing.** Every frame is composited at 16-bit float, and every video source is decoded at full depth. Gradients from a 10-bit camera file survive grading.
- **10-bit exports.** HEVC 10-bit (Main 10), both AV1 formats, ProRes 422 and ProRes 4444 keep that depth. H.264, HEVC and HEVC with Alpha are 8-bit.
- **Deep stills.** A still deeper than 8 bits per channel, such as a 16-bit PNG or TIFF or a 10-bit HEIC, is drawn at 16-bit float. An 8-bit still is drawn as before.
- **Saved and rendered frames.** **File ▸ Save Frame…** writes a 16-bit PNG or a 10-bit HEIC when the frame shows a deep still or deep video, and in every HDR (HLG) project. JPEG, Animated GIF and Animated PNG are always 8-bit.
- **Reversed clips.** A reversed clip's backwards copy is rendered at 10 bits, at the source's exact size, with the source's own colour labels. That means an HDR or log clip still reads correctly when reversed. See [Speed](speed.md).
- **What stays 8-bit.** Text, shapes, captions, graphics, thumbnails and screen recordings are 8-bit. In an HDR (HLG) project they are still lifted to HDR reference white.

## Limits

- **Log detection is Apple-only.** Only Apple Log and Apple Log 2 are recognised on import. S-Log3, V-Log and Canon Log must be chosen by hand.
- **One setting per file.** Camera Log and the HDR10 peak belong to the media file, not to a clip. Two clips of one file can't be read differently.
- **The HDR10 peak is read once, at import.** Relinking a PQ file does not read its peak again; set it by hand if the new file differs. Relinking keeps the file's Camera Log.
- **Camera Log needs a video file.** It is refused on an audio file, an image or a LUT. A PQ still takes only a peak.
- **A peak only on a PQ file.** Setting a peak on a file that isn't PQ is refused.
- **A camera LUT as a look over Camera Log converts twice.** The Look section only warns.
- **The chroma key after switching to HDR (HLG) is close, not exact,** on HLG footage with P3 or BT.709 primaries, on PQ highlights above 1,000 cd/m² and on an HDR gain-map photo. Re-pick the key if an edge changes.
- **Some Canon files look too contrasty.** A non-ProRes Canon file flagged as video range that actually stores full-range codes looks too contrasty after C-Log2 or C-Log3 conversion.
- **Two settings are fixed.** There is no Dolby Vision output, and SDR reference white in an HDR project is fixed at 203 cd/m².
- **Wide-gamut SDR projects aren't offered.** An SDR project always works in Rec. 709.
