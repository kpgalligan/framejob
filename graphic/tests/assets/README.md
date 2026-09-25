# Test assets

Four 8×8 solid images, one per raster format resvg decodes, made in this
directory with ImageMagick 7.1.2 (`/opt/homebrew/bin/magick`). The colour
each was made with is the oracle `tests/images.rs` reads the centre pixel
against.

| File | Command | Colour |
|---|---|---|
| `red.png` | `magick -size 8x8 xc:'#ff0000' red.png` | `#ff0000` |
| `steel.jpg` | `magick -size 8x8 xc:'#4080c0' -quality 95 steel.jpg` | `#4080c0` (JPEG: within ±4 per channel) |
| `blue-then-yellow.gif` | `magick -size 8x8 xc:'#0000ff' -size 8x8 xc:'#ffff00' -delay 10 blue-then-yellow.gif` | two frames; the FIRST, `#0000ff`, is the one drawn |
| `magenta.webp` | `magick -size 8x8 xc:'#ff00ff' -define webp:lossless=true magenta.webp` | `#ff00ff` (lossless) |
