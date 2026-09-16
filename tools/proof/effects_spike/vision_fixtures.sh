#!/bin/sh
# The Vision spike's fixtures (2026-09-15). Writes into
# tools/proof/work/effects_spike/vision/ (untracked scratch) and reads only
# images shipped with the system or installed apps (Photos' FlexAudio covers,
# Adobe CEP's MUSE hero, iA Presenter's theme photos), tools/proof/media,
# harness chrome renders under tools/proof/work/chrome{3,4}/, and the
# recorder spike's own screen recordings under tools/proof/work/spike/
# (road map 3, R0). No personal folder.
#
#   sh tools/proof/effects_spike/vision_fixtures.sh
set -eu
FF=${FFMPEG:-/opt/homebrew/bin/ffmpeg}
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
OUT="$ROOT/tools/proof/work/effects_spike/vision"
mkdir -p "$OUT/frames" "$OUT/video"
cd "$OUT"
F=/System/Library/Fonts/Helvetica.ttc

# --- non-person stills, 1920x1080 --------------------------------------------
$FF -y -v error -f lavfi -i "color=c=0x3a6ea5:s=1920x1080" -frames:v 1 frames/card_blue.png
$FF -y -v error -f lavfi -i "color=c=black:s=1920x1080" -frames:v 1 frames/card_black.png
$FF -y -v error -f lavfi -i "color=c=white:s=1920x1080" -frames:v 1 frames/card_white.png
$FF -y -v error -f lavfi -i "color=c=0x202020:s=1920x1080" \
  -vf "drawtext=fontfile=$F:text='Remove Background':fontsize=160:fontcolor=white:x=(w-tw)/2:y=(h-th)/2" \
  -frames:v 1 frames/text_title.png
$FF -y -v error -f lavfi -i "color=c=0xf4f1ea:s=1920x1080" \
  -vf "drawtext=fontfile=$F:text='func render(frame\: Frame) -> Image {':fontsize=48:fontcolor=0x222222:x=120:y=200,drawtext=fontfile=$F:text='    let mask = cache.nearest(frame.time)':fontsize=48:fontcolor=0x222222:x=120:y=280,drawtext=fontfile=$F:text='    return frame.image.multiplyingAlpha(mask)':fontsize=48:fontcolor=0x222222:x=120:y=360,drawtext=fontfile=$F:text='}':fontsize=48:fontcolor=0x222222:x=120:y=440" \
  -frames:v 1 frames/text_code.png
$FF -y -v error -f lavfi -i "testsrc2=s=1920x1080" -frames:v 1 frames/testsrc2.png
# tools/proof/media's test clip, upscaled
$FF -y -v error -ss 1 -i "$ROOT/tools/proof/media/A.mov" -vf "scale=1920:1080:flags=bicubic" -frames:v 1 frames/media_A.png
# Reelcut's own chrome, an offscreen harness render (road map 2, phase 4): app UI, no person
W="$ROOT/tools/proof/work"
$FF -y -v error -i "$W/chrome4/shape-open.png" \
  -vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=0x9a9a9a" -frames:v 1 frames/screen_app_ui.png
# real screen recordings (the recorder spike's): a desktop PLAYING A FILM, so
# these three frames contain people inside a screencast; letterboxed to 16:9
REC="$ROOT/tools/proof/work/spike"
$FF -y -v error -ss 1 -i "$REC/q7-immediate-1.mov" \
  -vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2" -frames:v 1 frames/screen_1.png
$FF -y -v error -ss 1 -i "$REC/q4-rate-60.mov" \
  -vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2" -frames:v 1 frames/screen_2.png
$FF -y -v error -ss 1 -i "$REC/q7-mic-builtin-1.mov" \
  -vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2" -frames:v 1 frames/screen_3.png
# a salient non-person object (iA Presenter's bundled theme photo: pencils)
$FF -y -v error -i "/Applications/iA Presenter.app/Contents/Resources/NewTheme/image4.jpg" \
  -vf "scale=1920:-2,crop=1920:1080" -frames:v 1 frames/object_pencils.png
$FF -y -v error -i "/Applications/iA Presenter.app/Contents/Resources/NewTheme/image2.jpg" \
  -vf "scale=1920:-2,crop=1920:1080" -frames:v 1 frames/object_notebook.png

# --- person stills (system/app-shipped art; no personal data) ----------------
FLEX=/System/Library/Photos/Resources/FlexAudio
MUSE="/Library/Application Support/Adobe/CEP/extensions/com.adobe.ccx.fnft-3.5.0/images/empty-state/video-hero-MUSE.jpg"
$FF -y -v error -i "$MUSE" -vf "scale=1920:1080:flags=bicubic" -frames:v 1 frames/person_desk.png
$FF -y -v error -i "$FLEX/e5fc4933-8a24-410e-9e4a-ec155980a389.jpg" \
  -vf "scale=1080:1080:flags=bicubic,pad=1920:1080:420:0:color=0x303030" -frames:v 1 frames/person_duo.png
$FF -y -v error -i "$FLEX/AAE4E824-DD67-4DB0-933F-AD2D619E4EF6.jpg" \
  -vf "scale=1080:1080:flags=bicubic,pad=1920:1080:420:0:color=0x303030" -frames:v 1 frames/person_hero.png
$FF -y -v error -i "$FLEX/9048dcfa-a2b8-4cfb-a5d6-7bc70c3722c2.jpg" \
  -vf "scale=1080:1080:flags=bicubic,pad=1920:1080:420:0:color=0x303030" -frames:v 1 frames/person_fall.png

# --- 4K variants ---------------------------------------------------------------
$FF -y -v error -i frames/person_desk.png -vf "scale=3840:2160:flags=bicubic" -frames:v 1 frames/person_desk_4k.png
$FF -y -v error -ss 1 -i "$REC/q4-size-best_pixels.mov" \
  -vf "scale=3840:2160:force_original_aspect_ratio=decrease,pad=3840:2160:(ow-iw)/2:(oh-ih)/2" -frames:v 1 frames/screen_4k.png

# --- videos --------------------------------------------------------------------
# q2's job, person-ish: 60 s 1080p30, a slow push-in on the desk shot plus sensor noise
$FF -y -v error -loop 1 -framerate 30 -i "$MUSE" -t 60 \
  -vf "scale=3840:2160,zoompan=z='1+0.25*on/1800':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:s=1920x1080:fps=30,noise=alls=6:allf=t,format=yuv420p" \
  -c:v libx264 -preset veryfast -crf 20 -g 60 video/job_person_60s.mov
# q2's job, screencast of a playing film (people in it): the 2.1 s recording looped to 60 s at 1080p30
$FF -y -v error -stream_loop 40 -i "$REC/q7-immediate-1.mov" -t 60 -an \
  -vf "fps=30,scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,format=yuv420p" \
  -c:v libx264 -preset veryfast -crf 20 -g 60 video/job_screen_60s.mov
# q2's job, screencast with no person: Reelcut's chrome (a 2880x3000 harness
# render) scrolled top to bottom over 60 s, 1080p30
$FF -y -v error -loop 1 -framerate 30 -i "$W/chrome3/open-two.png" -t 60 \
  -vf "scale=1920:-2,crop=1920:1080:0:'(ih-1080)*t/60',format=yuv420p" \
  -c:v libx264 -preset veryfast -crf 20 -g 60 video/job_ui_60s.mov
# q7: static shots, 10 s 1080p30 — a still with per-frame sensor noise, through H.264
$FF -y -v error -loop 1 -framerate 30 -i frames/person_desk.png -t 10 \
  -vf "noise=alls=6:allf=t,format=yuv420p" -c:v libx264 -preset veryfast -crf 20 -g 60 video/static_desk.mov
$FF -y -v error -loop 1 -framerate 30 -i frames/person_duo.png -t 10 \
  -vf "noise=alls=6:allf=t,format=yuv420p" -c:v libx264 -preset veryfast -crf 20 -g 60 video/static_duo.mov
$FF -y -v error -loop 1 -framerate 30 -i frames/object_pencils.png -t 10 \
  -vf "noise=alls=6:allf=t,format=yuv420p" -c:v libx264 -preset veryfast -crf 20 -g 60 video/static_pencils.mov
echo "fixtures in $OUT"
