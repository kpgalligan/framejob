# Podcasts and several cameras

A show filmed with more than one camera — a podcast with a camera on each
guest, an interview with a wide and a close shot — is cut in Frame Job as
ordinary clips on ordinary tracks. There is no special multicam clip: each
camera is a track, and the edit you watch is a **program track** in front of
them, made of pieces copied from whichever camera you want at each moment.

## Setting it up

1. Put each camera's recording on a track of its own, lined up in time.
   **Clip ▸ Synchronize Audio** lines the selected recordings up by their
   sound ([Audio](audio.md)). Name each track after its camera (double-click
   the track's header): the names are what Switch Angle lists.
2. Add a track in front of them for the program, and put the first shots on
   it. An agent does this with `copy_pieces` (below); by hand, ⌥-drag a
   camera's clip straight up onto the program track, which leaves a copy at
   the same time — except a clip with a detached sound, whose sound's copy
   would sit on the sound, so give it a change in time (see
   [Moving clips](editing.md#moving-clips)) — and cut it with
   **Clip ▸ Split** (⌘T).

The camera tracks stay underneath. They can stay shown — the program track is
in front and covers them — or be hidden with their track switch; a hidden
track's clips still count as an angle.

## Switch by Speaker

**Clip ▸ Switch by Speaker…** cuts a whole program track for you from a
conversation: it watches each person's microphone and shows whoever is
talking. Do it in this order:

1. **Synchronize Audio first** (Setting it up, above). Switch by Speaker trusts
   where the clips sit and does not check that they are in sync, so a camera
   moved or slipped afterwards — by dragging it, or with a ⌥⇧-drag — puts its
   shots out of step with the voices.
2. Select every camera's clips and every microphone's clips, then choose
   **Clip ▸ Switch by Speaker…**. It is offered when the selection holds
   clips with a picture on two or more tracks (each such track is a camera, up
   to nine) and at least one clip with its sound on.
3. Afterwards, fix single shots with **Switch Angle** (below) and move cuts
   with an ordinary roll.

**Which tracks are microphones.** By default, every track holding a selected
clip with sound and no picture — a separate recording from a microphone or a
recorder. When nothing like that is selected, each camera's own sound is its
microphone. A camera's sound detached with **Clip ▸ Detach Audio** is never
picked by default; you can choose it in a Microphone pop-up. A camera clip that
is still linked to its detached sound cannot be switched: the sheet says so
and names the clip, and **Clip ▸ Attach Audio** puts the two back together
first.

**The sheet.** One row per person: a Microphone pop-up and the Camera that
shows them, paired front to back to start with. Then:

- **Wide** — the camera shown until someone first talks, and while two talk
  at once (**Crosstalk shows**); when nobody talks the current shot holds. A
  camera no person uses is picked to start with when exactly one is left over,
  else None.
- **Minimum shot** (2 s) — a shorter shot is merged into its neighbour.
- **Cut** (0.2 s before speech) — how long before a new speaker's first word
  the cut comes.
- **Crosstalk shows** — the Wide, or holds the Current speaker, while two talk
  at once for a second or more.
- **Ignore bleed** (15 dB below a speaker's own level) — every microphone also
  hears the other people, quieter. A voice more than this far below that
  microphone's own speaker is bleed, and never counts as that person talking.
  Raise it if a quiet guest is never shown; lower it if someone is shown while
  only the other person talks.
- **Cut to the wide after … s on one speaker** (off) — breaks up a long
  monologue with the wide for one minimum shot.
- **Mute the cameras' own sound** — on to start with when the microphones are
  separate recordings, so the cameras' scratch sound is switched off inside the
  range.
- **Write to** — shown only when an earlier Program track can be replaced:
  choose it to write the new cut there instead of adding another track.

The summary under the controls says what Switch will do ("22 shots: 8 on Cam
A, …. Adds 23 clips."), or every reason it cannot, one per line — a
microphone still being analysed after import, a microphone with no speech, a
stretch no camera covers, or more clips than a project may hold. **Switch**
writes it as one undo step, **Switch by Speaker**:

- a new track **Program** directly in front of the front-most camera, holding
  a piece of the chosen camera for each shot, in sync, with the picture on and
  the sound off;
- the camera tracks hidden — or, when a camera track has clips outside the
  range or a clip without a picture, its clips cut at the range's ends and
  their pictures switched off inside it only;
- nothing outside the range touched, and the microphones never edited, so what
  you hear is unchanged.

The range is the In–Out range when one is set, else the selected camera clips'
whole length. The four values Minimum shot, Cut, Crosstalk shows and Ignore
bleed are remembered for the next time. Switch by Speaker works inside an open
nest and has no keyboard shortcut.

**One microphone for everyone.** When the selection holds exactly one
microphone and two or more cameras, Switch by Speaker decides who talks from
the cameras' pictures instead: while the microphone hears speech, the camera
whose person's mouth moves most is shown — the largest face in each camera,
its mouth opening and closing over half a second, at least half as much again
as the next camera's — and when two mouths move alike it is crosstalk. It
reads Frame Job's on-device face analysis of each camera; when a camera's
faces have not been found yet, an **Analyzing** sheet finds them first (Stop
leaves everything as it was, and keeps what was saved so far: the faces are
saved every 30 seconds), then the Switch by Speaker sheet opens. That sheet
has one **Microphone** pop-up and lists the
**Cameras**; there is no Ignore bleed row, and **Minimum shot** opens at 3 s
and is not remembered. Choose a **Wide** to show it during crosstalk: the wide
camera then takes no part in deciding who talks. The summary starts "Faces
guess who is talking; check the cuts." — mouths that move without speaking
(laughing, chewing) or a face it cannot find can put a cut in the wrong place,
so look through the result and fix shots with Switch Angle.

**A limit, measured.** With heavy bleed in a noisy room (another voice 24 dB
down under −45 dBFS of noise), a cut can come later than Cut before speech
asks — in the worst case measured, about 35 ms before the first word instead
of 0.2 s.

## Switch Angle

**Clip ▸ Switch Angle ▸** re-picks one shot of the program from another
camera. Select the one shot, open the submenu, and choose a camera.

- The submenu lists, front first, every other track whose video clips cover
  the shot's whole span — only clips playing a video file with a picture
  count, not a freeze frame of one, and a clip whose picture is switched off
  still counts. Up to nine tracks are listed. Two tracks with the same name are told apart by their position from
  the back, as "Camera (2)" and "Camera (3)". With no single shot selected, or
  no track covering it, the submenu holds a greyed **No Covering Angle**.
- An item is greyed when the shot's track is locked, or the shot is linked to
  a detached sound (**Clip ▸ Attach Audio** first).
- Choosing a camera replaces the shot with that camera's picture over exactly
  the same span, in sync: the new clip shows the camera's own frame at every
  moment. Where the shot crosses the end of one of the camera's clips and the
  start of the next (a camera that stopped and started again), it becomes two
  pieces, one from each file; where two of the camera's clips overlap, the
  later one takes over at its own start.
- The shot keeps its span and its video and audio switches, and the dissolves
  at both of its edges are kept with their kind, curve and audio shape. Nothing
  else carries over from the old shot: a punch-in, a grade or an action on it
  is not copied to the new camera's piece.
- The whole switch is one undo step, **Switch Angle**, and the new pieces are
  selected afterwards.
- If a dissolve can no longer fit — the camera's first or last piece is too
  short to overlap by the dissolve's length — the dissolve is dropped and the
  undo step is named **Switch Angle (transition removed)**.
- A switch that cannot be done changes nothing, beeps and says why at the foot
  of the inspector: the camera does not cover the shot (naming the first moment
  it does not), or the clip next to the shot plays a speed ramp that cannot
  give up the dissolve's frames ("clip X's edge is held at tick …").

Switch Angle works inside an open nest too, on the nest's own tracks. It has
no keyboard shortcut.

## For agents: copy_pieces, switch_angle and switch_by_speaker

Three MCP tools do the same work ([Driving Frame Job from an AI agent](mcp.md)):

- `switch_angle {clip, angle}` is **Clip ▸ Switch Angle ▸**: `clip` the shot,
  `angle` the camera's track id. It answers the step's name, the new pieces'
  ids in time order and how many dissolves were dropped.
- `copy_pieces {clip, track, ranges, video?, audio?}` is the operation Switch
  Angle is built from: it copies the parts of one clip between the given times
  onto another track at the same times. Each piece is exactly what splitting
  the clip at both ends would leave in the middle — the same frames, speed,
  speed ramp, actions and timed words — with no dissolve and no link. The
  destination track must be free over every range. An agent cuts a whole
  program from the cameras with one `copy_pieces` per camera clip.
- `switch_by_speaker` is **Clip ▸ Switch by Speaker…**: over the selected
  clips, with the same values as the sheet (`min_shot`, `lead`, `crosstalk`,
  `bleed_db`, `wide_after`, `mute_cameras`, `track` to replace, `wide`, and
  `speakers` `[{mic, angle}]` to pair people by hand), plus `min_turn` (the
  shortest turn that cuts, 1 s) and `dominance_db` (8 dB), which the sheet does
  not show. `apply: false` answers the shots without editing. Every answer says
  which `mode` ran, `microphones` or `faces` (one microphone for everyone), and
  in the faces mode a `note` that the cuts are a guess; `min_shot` is 3 s there
  unless given. Where the menu command would show the Analyzing sheet, the
  tool waits for the faces up to 60 seconds, and past that is refused with
  what it saved kept — call it again to continue.
