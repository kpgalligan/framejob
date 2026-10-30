#!/bin/bash
# K-weighting coefficients derived at low rates vs the reader's resample to 48 kHz.
set -e
cd "$(dirname "$0")/.."
head -1 out/windows48.txt > out/whole.txt
for r in 16000 22050; do
  ffmpeg -hide_banner -v error -y -f f32le -ar 48000 -ac 1 -i media/rode.f32 \
    -af "aresample=${r}:filter_size=64:cutoff=0.97" -c:a pcm_f32le "media/rode${r}.wav"
  ./tools/lcache decode "media/rode${r}.wav" "media/rode${r}.f32" > /dev/null
  ./tools/lcache decode "media/rode${r}.wav" "media/rode${r}to48.f32" 48000 > /dev/null
  echo "== ${r} native-rate derived coefficients:"
  ./tools/lcache windows "media/rode${r}.f32" "${r}" 1 10 out/whole.txt | sed -n 3p | cut -d'|' -f2-4
  echo "   resampled to 48 kHz by the reader, table coefficients:"
  ./tools/lcache windows "media/rode${r}to48.f32" 48000 1 10 out/whole.txt | sed -n 3p | cut -d'|' -f2-4
  echo "   ffmpeg at the native rate:"
  python3 -I tools/ffref.py "media/rode${r}.f32" "${r}" 1 out/whole.txt
done
