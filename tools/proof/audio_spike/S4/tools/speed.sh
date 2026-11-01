#!/bin/bash
# The source window's loudness against the window played at a speed, by ffmpeg:
# varispeed (asetrate then back to 48 kHz) and pitch kept (atempo).
set -e
cd "$(dirname "$0")/.."
head -6 out/windows48.txt > out/w6.txt
echo "== x1 (reference)"
python3 -I tools/ffref.py media/rode.f32 48000 1 out/w6.txt
for s in 0.5 0.8 1.25 2.0; do
  r=$(python3 -I -c "print(int(48000*${s}))")
  echo "== varispeed x${s}"
  python3 -I tools/ffref.py media/rode.f32 48000 1 out/w6.txt --filter "asetrate=${r},aresample=48000:filter_size=64"
  echo "== pitch kept (atempo) x${s}"
  python3 -I tools/ffref.py media/rode.f32 48000 1 out/w6.txt --filter "atempo=${s}"
done
