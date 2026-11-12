#!/usr/bin/env python3
"""The proofs' one PNG reader, 8 and 16 bits a sample (#566, spec §11 PR-20).

    python3 tools/proof/png_read.py --selftest [--mutant bpp-channels]

Since PR-20 a `render_frame` or Save Frame… PNG of a frame showing a graphic is
16-bit, so a proof that reads such a frame reads it here. The decoder is pure
Python: non-interlaced PNGs of colour types 0 (grey), 2 (RGB), 4 (grey + alpha)
and 6 (RGBA), at 8 or 16 bits a sample. A 16-bit sample is big-endian on disk
and the filters work on bytes, so a pixel's filter distance (`bpp`) is
`channels × depth / 8` bytes. A whole large frame is too slow for its loops, so
`rgba8` reads one through ffmpeg instead, with the same rounding: ffmpeg's own
`rgba` conversion of a 16-bit PNG is not round-to-nearest, so a frame read that
way at each depth differs by a level where the two pictures are one.

- `header(data)` → (width, height, depth, colour) off the IHDR, or None.
- `decode(data, upto=None)` → (width, channels, depth, rows): rows 0..`upto`
  (every row when None; a pixel near the top needs only the rows above it,
  which keeps a bounded poll from spending its bound on decoding). An 8-bit
  row is `bytes`; a 16-bit row is a list of ints, one per sample.
- `rows8(data, upto=None)` → (width, channels, rows): every row as 8-bit
  levels (`bytes`), a 16-bit sample rounded to the nearest level,
  `(v + 128) // 257`.
- `pixel8(data, x, y)` → (r, g, b) in 8-bit levels from either depth;
  `pixel16(data, x, y)` → (r, g, b) as stored at 16 bits, or None for an
  8-bit PNG. Both answer None for `data` None.
- `rgba8(path, env=None, timeout=120)` → (width, height, RGBA bytes) in 8-bit
  levels through ffmpeg (`rgba64le` for a 16-bit PNG, each sample rounded as
  `rows8` does), or None.

The selftest (no app; R5 runs ffmpeg) encodes small PNGs with each of the five
filters, at both depths and in every colour type, and reads them back: R1 every
sample decoded as encoded; R2 `rows8` and `pixel8` round a 16-bit sample to the
nearest 8-bit level, and leave an 8-bit one as it is; R3 `upto` stops after its
row; R4 an interlaced PNG, a palette PNG and a 4-bit one are refused by name;
R5 `rgba8` of a 16-bit and an 8-bit RGBA PNG written to `work/png-read/` equals
`rows8` of the same bytes, the 16-bit one holding samples at 257·k + 128 and
+ 129, where truncation and rounding part. `--mutant bpp-channels` (the filter
distance left at `channels`, the 8-bit reader's) must fail exactly R1, R2 and R5.
"""

import argparse
import array
import struct
import shutil
import subprocess
import sys
import zlib
from pathlib import Path

SIGNATURE = b"\x89PNG\r\n\x1a\n"
CHANNELS = {0: 1, 2: 3, 4: 2, 6: 4}
EXPECTED = {"bpp-channels": {"R1", "R2", "R5"}}
WORK = Path(__file__).resolve().parent / "work/png-read"
# The mutants, as `mutant_anchors.py` reads them: switches on MUTANT, no tree text.
MUTANTS = tuple(sorted(EXPECTED))
MUTANT = None


def _chunks(data):
    pos, header, idat = 8, None, []
    while pos + 8 <= len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat.append(body)
        elif kind == b"IEND":
            break
    return header, b"".join(idat)


def header(data):
    """(width, height, depth, colour) off a PNG's IHDR, or None."""
    if data is None or data[:8] != SIGNATURE or len(data) < 29:
        return None
    width, height, depth, colour = struct.unpack(">IIBB", data[16:26])
    return width, height, depth, colour


def _unfilter(kind, cur, prev, bpp):
    stride = len(cur)
    if kind == 1:
        for i in range(bpp, stride):
            cur[i] = (cur[i] + cur[i - bpp]) & 255
    elif kind == 2:
        for i in range(stride):
            cur[i] = (cur[i] + prev[i]) & 255
    elif kind == 3:
        for i in range(bpp):
            cur[i] = (cur[i] + (prev[i] >> 1)) & 255
        for i in range(bpp, stride):
            cur[i] = (cur[i] + ((cur[i - bpp] + prev[i]) >> 1)) & 255
    elif kind == 4:
        for i in range(bpp):
            cur[i] = (cur[i] + prev[i]) & 255
        for i in range(bpp, stride):
            a, b, c = cur[i - bpp], prev[i], prev[i - bpp]
            p = a + b - c
            pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
            pred = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
            cur[i] = (cur[i] + pred) & 255
    elif kind != 0:
        raise RuntimeError(f"unknown PNG filter {kind}")


def decode(data, upto=None):
    """(width, channels, depth, rows) of a non-interlaced 8- or 16-bit PNG of
    colour type 0, 2, 4 or 6, rows 0..`upto` (all when None)."""
    found, raw = _chunks(data)
    if found is None:
        raise RuntimeError("no IHDR: not a PNG")
    width, height, depth, colour, _, _, interlace = found
    if interlace != 0 or depth not in (8, 16) or colour not in CHANNELS:
        raise RuntimeError(f"an 8- or 16-bit non-interlaced grey, RGB or RGBA PNG is the only "
                           f"kind read here (depth {depth}, colour type {colour}, interlace "
                           f"{interlace})")
    channels = CHANNELS[colour]
    raw = zlib.decompress(raw)
    stride = width * channels * depth // 8
    bpp = channels if MUTANT == "bpp-channels" else channels * depth // 8
    rows, prev, pos = [], bytearray(stride), 0
    for _ in range(height if upto is None else min(height, upto + 1)):
        kind = raw[pos]
        cur = bytearray(raw[pos + 1:pos + 1 + stride])
        pos += 1 + stride
        _unfilter(kind, cur, prev, bpp)
        if depth == 8:
            rows.append(bytes(cur))
        else:
            rows.append(list(struct.unpack(f">{width * channels}H", bytes(cur))))
        prev = cur
    return width, channels, depth, rows


def level(value):
    """A 16-bit sample as the nearest 8-bit level."""
    return (value + 128) // 257


def rows8(data, upto=None):
    """(width, channels, rows) with every row as 8-bit levels (`bytes`)."""
    width, channels, depth, rows = decode(data, upto)
    if depth == 8:
        return width, channels, rows
    return width, channels, [bytes(level(v) for v in row) for row in rows]


def pixel8(data, x, y):
    """(r, g, b) at (x, y) in 8-bit levels, from either depth; None for no data."""
    if data is None:
        return None
    _, channels, depth, rows = decode(data, upto=y)
    row = rows[y]
    found = row[x * channels:x * channels + 3]
    return tuple(found) if depth == 8 else tuple(level(v) for v in found)


def pixel16(data, x, y):
    """(r, g, b) at (x, y) as stored at 16 bits; None for an 8-bit PNG or no data."""
    if data is None:
        return None
    _, channels, depth, rows = decode(data, upto=y)
    if depth != 16:
        return None
    return tuple(rows[y][x * channels:x * channels + 3])


def rgba8(path, env=None, timeout=120):
    """(width, height, RGBA bytes) of the PNG at `path` in 8-bit levels through ffmpeg, a
    16-bit one decoded to `rgba64le` and each sample rounded by `level`; None when it cannot be
    read. Binary output, bounded by `timeout`."""
    try:
        with open(path, "rb") as handle:
            found = header(handle.read(64))
        if found is None:
            return None
        width, height, depth, _ = found
        deep = depth == 16
        raw = subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-i", str(path), "-frames:v",
                              "1", "-f", "rawvideo", "-pix_fmt", "rgba64le" if deep else "rgba",
                              "-"], capture_output=True, timeout=timeout, env=env).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
    if len(raw) != width * height * (8 if deep else 4):
        return None
    if deep:
        words = array.array("H")
        words.frombytes(raw)
        if sys.byteorder != "little":
            words.byteswap()
        raw = bytes(level(v) for v in words)
    return width, height, raw


# ---- the selftest ----------------------------------------------------------------------

def _filter(kind, cur, prev, bpp):
    """`cur` (raw bytes) filtered by `kind` against `prev`: the encoder's side."""
    out = bytearray(len(cur))
    for i, value in enumerate(cur):
        a = cur[i - bpp] if i >= bpp else 0
        b = prev[i]
        c = prev[i - bpp] if i >= bpp else 0
        if kind == 0:
            pred = 0
        elif kind == 1:
            pred = a
        elif kind == 2:
            pred = b
        elif kind == 3:
            pred = (a + b) >> 1
        else:
            p = a + b - c
            pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
            pred = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
        out[i] = (value - pred) & 255
    return out


def encode(width, height, depth, colour, samples, filters, interlace=0):
    """A PNG of `samples` (one int per sample, row-major), row r filtered by
    `filters[r % len(filters)]`, with a true filter distance."""
    channels = CHANNELS.get(colour, 1)
    bpp = max(1, channels * depth // 8)
    per_row = width * channels
    body, prev = bytearray(), bytearray(per_row * depth // 8)
    for r in range(height):
        values = samples[r * per_row:(r + 1) * per_row]
        cur = (bytearray(values) if depth == 8
               else bytearray(struct.pack(f">{per_row}H", *values)))
        kind = filters[r % len(filters)]
        body.append(kind)
        body += _filter(kind, cur, prev, bpp)
        prev = cur

    def chunk(kind, payload):
        return (struct.pack(">I", len(payload)) + kind + payload
                + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", width, height, depth, colour, 0, 0, interlace)
    return (SIGNATURE + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(body)))
            + chunk(b"IEND", b""))


def _samples(width, height, channels, depth, seed):
    top = 255 if depth == 8 else 65535
    state, out = seed, []
    for _ in range(width * height * channels):
        state = (state * 1103515245 + 12345) & 0x7FFFFFFF
        out.append(state % (top + 1))
    return out


def selftest():
    rows = {}

    def row(name, good, detail):
        rows[name] = bool(good) and rows.get(name, True)
        print(("  ok   " if good else "  FAIL ") + f"{name} {detail}", flush=True)

    width, height = 7, 6
    misses = []
    for depth in (8, 16):
        for colour, channels in sorted(CHANNELS.items()):
            for kind in range(5):
                samples = _samples(width, height, channels, depth, 17 * depth + 5 * colour + kind)
                data = encode(width, height, depth, colour, samples, [kind])
                got_width, got_channels, got_depth, got = decode(data)
                flat = [v for r in got for v in r]
                if (got_width, got_channels, got_depth) != (width, channels, depth) \
                        or flat != samples:
                    misses.append((depth, colour, kind))
            mixed = _samples(width, height, channels, depth, 99 + depth + colour)
            if [v for r in decode(encode(width, height, depth, colour, mixed,
                                          [0, 1, 2, 3, 4, 4]))[3] for v in r] != mixed:
                misses.append((depth, colour, "mixed"))
    row("R1", not misses, f"every sample decoded as encoded, 8 and 16 bits, colour types 0, 2, "
        f"4, 6, filters 0–4 and mixed; misses {misses}")

    deep = [0, 128, 129, 257 * 90, 257 * 90 + 128, 257 * 90 + 129, 65535, 65406, 65407]
    width16 = len(deep) // 3
    data16 = encode(width16, 2, 16, 2, deep + deep, [1, 4])
    want = [level(v) for v in deep]
    _, _, got = rows8(data16)
    shallow = list(range(0, 255, 28))[:9]
    data8 = encode(3, 1, 8, 2, shallow, [3])
    good = (list(got[0]) == want == [0, 0, 1, 90, 90, 91, 255, 254, 255]
            and list(got[1]) == want
            and pixel8(data16, 1, 1) == tuple(want[3:6])
            and pixel16(data16, 2, 0) == tuple(deep[6:9])
            and pixel16(data8, 0, 0) is None
            and pixel8(data8, 2, 0) == tuple(shallow[6:9])
            and rows8(data8)[2][0] == bytes(shallow))
    row("R2", good, f"16-bit {deep} → 8-bit {list(got[0])} (want {want}); pixel8 and pixel16 "
        f"from either depth")

    tall = encode(4, 50, 16, 6, _samples(4, 50, 4, 16, 3), [2])
    row("R3", len(decode(tall, upto=9)[3]) == 10 and len(decode(tall)[3]) == 50,
        "upto 9 decodes 10 rows of 50")

    refused = []
    for label, data in [("interlaced", encode(2, 2, 8, 2, [1] * 12, [0], interlace=1)),
                        ("palette", encode(2, 2, 8, 3, [1] * 4, [0])),
                        # IHDR's depth byte (offset 24) set to 4 over an 8-bit grey PNG.
                        ("4-bit", (lambda d: d[:24] + b"\x04" + d[25:])(
                            encode(2, 2, 8, 0, [1] * 4, [0])))]:
        try:
            decode(data)
        except RuntimeError as error:
            refused.append((label, "is the only kind read here" in str(error)))
    row("R4", len(refused) == 3 and all(ok for _, ok in refused),
        f"refused by name: {refused}")

    shutil.rmtree(WORK, ignore_errors=True)
    WORK.mkdir(parents=True)
    edges = [257 * k + d for k in (0, 40, 90, 200, 254) for d in (0, 127, 128, 129)]
    deep_samples = (edges * 6)[:9 * 3 * 4]
    compared = []
    for name, data in [("deep.png", encode(9, 3, 16, 6, deep_samples, [1, 3, 4])),
                       ("shallow.png", encode(9, 3, 8, 6, _samples(9, 3, 4, 8, 11), [4, 1, 3]))]:
        path = WORK / name
        path.write_bytes(data)
        got = rgba8(path)
        want = b"".join(rows8(data)[2])
        compared.append((name, got is not None and got[:2] == (9, 3) and got[2] == want))
    shutil.rmtree(WORK, ignore_errors=True)
    row("R5", all(ok for _, ok in compared),
        f"rgba8 through ffmpeg equal to rows8: {compared}")
    failed = {name for name, ok in rows.items() if not ok}
    print(f"{len(rows) - len(failed)}/{len(rows)}")
    return failed


def main():
    global MUTANT
    parser = argparse.ArgumentParser()
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--mutant", choices=list(MUTANTS))
    args = parser.parse_args()
    if not args.selftest:
        parser.print_help()
        return 2
    MUTANT = args.mutant
    failed = selftest()
    if MUTANT is None:
        return 0 if not failed else 1
    caught = failed == EXPECTED[MUTANT]
    print(f"{'MUTANT PASS' if caught else 'MUTANT FAILURE'}: {MUTANT} — failed {sorted(failed)}, "
          f"expected exactly {sorted(EXPECTED[MUTANT])}")
    return 0 if caught else 1


if __name__ == "__main__":
    sys.exit(main())
