# Spec §11 — decisions: HDR, the clean-up batches onward

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the HD- series of [`hdr.md`](hdr.md), so a citation never has to say which file.
This file holds HD-18…HD-22 and #487, and a new HD- decision is appended here. It is new because
`hdr.md` had passed the spec's ~500-line split rule (#548, 2026-11-11); the entries moved here
unchanged, and an "above" or "below" in one may now point into a sibling file.

- **HD-18 — Clean-up batch 2's settlements: the PQ peak read from a WebM/Matroska Colour
  element and from an AV1 stream's metadata OBUs, the scopes with both switches on, and ProRes
  4444 with alpha from an HLG project measured.** Recorded before the batch's code (#316, #315,
  #317); it settles what HD-12 left to other containers. No op, tool, argument, recipe, catalog
  or format change (format stays 25).
  - **(a) Matroska's HDR10 fields** (RFC 9559's Colour element): MaxCLL 0x55BC and MaxFALL
    0x55BD (unsigned integers, cd/m²) and MasteringMetadata 0x55D0, whose children are floats —
    PrimaryRChromaticityX/Y 0x55D1/0x55D2, G 0x55D3/0x55D4, B 0x55D5/0x55D6, the white point
    0x55D7/0x55D8, LuminanceMax 0x55D9 and LuminanceMin 0x55DA (cd/m²). The core reads them with
    the Colour element and `rc_container_describe` reports them (the video's `mdcv_hex`,
    `clli_hex`, and the Colour's `transfer`, `primaries` and `matrix` codes, each null when
    absent). The copy's format description carries them as HD-12's two blobs **only when the
    Colour's transfer is 16** (PQ), so an SDR or untagged copy gains nothing, and HD-12's route 1
    reads them unchanged:
    - `MasteringDisplayColorVolume`, 24 bytes, written when 0x55D0 is present: the primaries in
      ST 2086's and SEI 137's order G, B, R, then the white point, each x and y a big-endian u16
      of round(c·50000) clamped to 0…50000; then the maximum and minimum luminance, each a
      big-endian u32 of round(L·10000) clamped to the u32's range (NaN or negative → 0). An
      absent child is 0.
    - `ContentLightLevelInfo`, 4 bytes, written when MaxCLL or MaxFALL is present: MaxCLL then
      MaxFALL, each a big-endian u16 clamped to 65535, an absent one 0.
  - **(b) The PQ label.** A copy whose Colour's transfer is 16 is labelled PQ in its format
    description: `TransferFunction` SMPTE ST 2084, and `ColorPrimaries` and `YCbCrMatrix` from
    `CVColorPrimariesGetStringForIntegerCodePoint` and `CVYCbCrMatrixGetStringForIntegerCodePoint`
    when the Colour names them and Core Video maps the code. No other copy's description changes.
    **Amended by CX-16** (codec-export C4, (10)): an SDR copy (its Colour's transfer neither 16
    nor 18) is labelled too, from its Colour's BT.709, BT.601 or BT.2020 matrix and primaries
    and BT.709-class or sRGB transfer, else a VP9 track's keyframe `color_space` for the
    matrix; with neither its description is unchanged.
  - **(c) AV1.** The description's two extensions first (HD-12's route 1); else the stream (AV1
    §5.3, §5.8; AV1-ISOBMFF §2.3): the `av1C`'s configOBUs (bytes 4 on, when byte 0 is 0x81, the
    marker and version 1; else none), then the first sample with data. Every OBU is walked: the
    type is the header's bits 6–3, an extension byte is skipped, `obu_size` is a leb128 of at
    most 8 bytes when `obu_has_size_field` is set, else the OBU is the rest of the bytes. An
    OBU_METADATA (type 5) is read by its leb128 `metadata_type`: 1 HDR_CLL (`max_cll` a
    big-endian u16, 4 bytes or more) and 2 HDR_MDCV (`luminance_max` a big-endian u32 at payload
    bytes 16–19 in 24.8 fixed point, 24 bytes or more), the first of each kept, the config's
    before the sample's. The maximum is whole cd/m² as (v + 128) / 256 in 64 bits, clamped to
    10,000, 0 no reading; MaxCLL as it stands, 0 absent, clamped to 10,000. MaxCLL first, else
    the mastering maximum, as HD-12. The core's pure `hdr10.rs` reads it through one export,
    `rc_hdr10_av1_peak`; the import probe calls it for an `av01` track.
  - **(d) The scopes, #315.** With Show Ungraded and Show SDR Version both on, the scopes read
    the ungraded SDR version (HD-15 (c)): no new branch, since the recipe's `ungraded` and
    `dynamic_range` are independent and `ScopeSignal` reads the second. A scope slot takes its
    caption and signal only from a trace of its own kind; another kind's trace is "no frame
    yet".
  - **(e) ProRes 4444 with alpha, #317,** is measured by a row before any fix (`hdr_proof.py`
    DA): an HLG project with a transparent background, a translucent shape and its opaque twin,
    exported `prores_4444` at its default, `hlg`, `sdr` and `pq`. Rules, fixed before the row
    runs: at the shape's centre, alpha within ±1/255 and the straight colour within ±2/1023;
    `hlg` and the default against `render_frame`, `sdr` against `render_frame {sdr_version:
    true}`, `pq`'s alpha against `render_frame`'s and its colour against the opaque twin's `pq`
    export. A failure is filed with its figures and fixed in a later phase.
  - **(f) Amends** HD-12 (its routes: a Matroska Colour's fields carried into the copy's
    description, and AV1's metadata OBUs as the stream route for an `av01` track).
  **Amended by HD-19** (clean-up batch 2, phase 2): (b) a copy whose Colour's transfer is 18
  is labelled HLG as a transfer-16 copy is labelled PQ, when H7h finds it misread without.
- **HD-19 — Clean-up batch 2, phase 2's settlements: an HLG or PQ still by its own label, an
  HLG WebM/Matroska copy labelled HLG, and the chroma key on an HDR source read as the SDR colour
  an SDR project shows.** Recorded before the phase's code (#311, #321, #312). No op, tool,
  argument, recipe, catalog or format change (format stays 25).
  - **(a) An HDR still, #311.** A still whose decoded image's colour space is HLG-based
    (`CGColorSpaceIsHLGBased`) takes step 0's `.hlg(p)` arm, and one that is PQ-based
    (`CGColorSpaceIsPQBased`) `.pq(p)`: p is `.p3D65` for `displayP3_HLG` and `displayP3_PQ`,
    `.bt709` for `itur_709_HLG` and `itur_709_PQ`, and `.bt2020` for every other such space.
    - It is decoded with its longest side bounded by `maxPixelSize` and its EXIF orientation
      applied, as `MediaCacheFiles.decodeImage` decodes every still today, on whichever ImageIO
      route keeps its space, its depth and its codes (measured first, M1 below).
    - **M1, measured 2026-10-21** (`tools/proof/work/cleanup2/m1/`, scratch, gitignored:
      `m1.swift` built over `app/Sources` by `swift_build.py`, run by `python3 -I m1.py` over
      `hdr_proof.py`'s stills). Four routes: `decodeImage` (ImageIO's thumbnail with the
      transform, bounded at 8192), the same with `kCGImageSourceDecodeRequest:
      kCGImageSourceDecodeToHDR`, and `CGImageSourceCreateImageAtIndex` with and without it.
      Every route answered the same space and depth for every file: the 16-bit HLG PNG
      (`render_frame` of an HLG project, cICP 9/18/0/1) `kCGColorSpaceITUR_2100_HLG` at 16 bits;
      the 16-bit PQ PNG (ffmpeg, cICP 9/16/0/1) `kCGColorSpaceITUR_2100_PQ`, 16; the 16-bit
      BT.709 HLG PNG (cICP 1/18/0/1) `kCGColorSpaceITUR_709_HLG`, 16; the 10-bit HLG HEIC
      (`render_frame {format: heic}`) and a 10-bit HLG AVIF (ffmpeg's libsvtav1)
      `kCGColorSpaceITUR_2100_HLG` at 10 bits; the 16-bit sRGB PNG and `still8.png`
      `kCGColorSpaceSRGB` at 16 and 8 bits. Each image drawn into a 16-bit-float bitmap of its
      own space kept the file's codes (ffmpeg `rgb48le`) within 0.01 of a 10-bit level (HLG
      PNG), 0.17 (PQ and BT.709 HLG PNGs) and 0.06 (sRGB), and the HEIC and AVIF, against the
      HLG PNG they were encoded from, within 1.01 and 5.99 (their encodes' own loss, the same
      on every route). Only the thumbnail routes bound and orient: a 9000×600 HLG PNG came back
      8192×546 from both and 9000×600 from `CreateImageAtIndex`, and the HLG HEIC rewritten
      with `kCGImagePropertyOrientation` 6 came back 128×1024 from both against 1024×128. So
      the route is today's `decodeImage`, unchanged, and nothing in it is redone by hand. A
      lossless JPEG XL of the HLG PNG (`cjxl -d 0`) read the same on every route:
      `kCGColorSpaceITUR_2100_HLG` at 16 bits, its codes within 0.008 of a level.
    - It is drawn in its own space, its codes unconverted, into a 16-bit-float premultiplied
      RGBA bitmap and uploaded `rgba16Float`.
    - `LayerLift` runs that arm on it, the peak unknown (1,000 cd/m², HD-6): in an HLG project
      the HLG arms of HD-13 (c), (d) — an `.hlg(.bt2020)` still is sampled as drawn, as
      `choose(input:buffer:output:)` answers nil for its video twin — and in an SDR project
      GR-15's arm, so an HDR still is no longer drawn as SDR there either.
    - The image cache's key is unchanged: the texture holds the file's codes in both outputs.
    - Every other still takes today's path byte for byte, and so does an HDR still that this
      route cannot read or draw.
    - Amends HD-13 (f) (a still is lifted by its own arm, not the SDR one) and closes (l)'s first
      limit.
  - **(b) An HLG WebM/Matroska copy, #321.** A copy whose Colour element's transfer is 18
    (ARIB STD-B67) is labelled HLG in its format description: `TransferFunction` ITU-R 2100
    HLG, with `ColorPrimaries` and `YCbCrMatrix` exactly as HD-18 (b)'s PQ label takes them. No
    HDR10 blobs. No other copy's description changes. Taken only if `hdr_proof.py` H7h finds an
    unlabelled HLG copy misread on the control; otherwise this records that AVFoundation reads
    the copy as HLG without the label and no writer changes. **H7h on the control** (the
    phase's untouched Release build, 2026-10-21): the copy was misread, its grey row as far
    as 158.27 10-bit levels from GR-15's HLG arm in an SDR project and 213.67 from the
    identity in an HLG project, so the label is written. Amends HD-18 (b).
    **Amended by CX-16** (codec-export C4, (10)): "no other copy's description changes" no
    longer holds for an SDR copy, which carries the labels its source states.
  - **(c) The chroma key on an HDR source, #312**, the owner's choice of 2026-10-20 ("Key means
    SDR colour (Recommended)", the designer's option (b)). In an HLG project, the key's distance
    reads the working colour, saturated, against the stored key, through:
    - for a layer whose source's SDR-project step-0 choice (`choose(input:buffer:output: .sdr)`;
      a still's by (a)) is `.hlg`: GR-15's HLG arm over BT.2020, applied to the working colour;
    - for one whose choice is `.pq`: the working colour back to display light (the inverse
      OETF, BT.2100's OOTF γ 1.2, × 1000/203), then GR-15's PQ arm (BT.2020 → BT.709, the gamut
      lift, the shoulder from 0.39 to max(peak, 203)/203);
    - for every other layer — Camera Log and LUT media, SDR sources, drawn layers — HD-13 (h)'s
      un-lift, unchanged.
    - So a key picked in an SDR project keys the same colour after a switch to HLG. The reading
      is exact for an HLG BT.2020 source and for a PQ source up to 1,000 cd/m². It is close for
      HLG over P3 or BT.709 (their working colour was matrixed in scene light) and for PQ above
      1,000 cd/m² (BT.2390's EETF is not undone).
    - The eyedropper in an HLG project stores the picked HLG colour through the keyed clips'
      reading: their common one when they all agree, else the un-lift.
    - The spill, a luma matte and the qualifier are unchanged.
    - Amends HD-13 (h) and closes (l)'s second limit.
  - **(d) Amends** HD-13 ((f), (h), (l)) and HD-18 (b).
  **Amended by HD-20** (clean-up 3 batch B): (a) a PQ still's peak is read at import and drawn;
  (c) the key on a built-in Camera Log reads through GR-16's SDR arm, not the un-lift.
  **Amended by HD-21** (clean-up 3 batch B, phase 2): (a) an HLG or PQ still's thumbnail is drawn
  through step 0.
  **Amended by HD-22** (clean-up 3 batch B, phase 3): (a) in an HLG project a gain-map still is
  decoded to HDR (`kCGImageSourceDecodeToHDR` on today's route) under an image-cache key of its
  own.
- **HD-20 — Clean-up 3 batch B, phase 1's settlements: the key on Camera Log media read as its
  SDR colour across HLG, and a PQ still's HDR10 peak read at import.** Recorded before the
  phase's code (#324, #325). Format 26.
  - **(a) The key on a built-in Camera Log, #324.** In an HLG project, the chroma key on a layer
    whose media's `choose(input:)` is `.log` reads the working colour back through the HLG
    inverse OETF to scene light (BT.2020 reflection × `logHLGExposure`, HD-13 (e)), then
    multiplies it by `logExposure / logHLGExposure` (0.42^2.4·3/0.38² ≈ 2.5903) and applies
    BT.2020 → BT.709, GR-15's gamut lift, the shoulder (knee 0.39, white `logWhite` =
    64·0.42^2.4 ≈ 7.98) and the encode L^(1/2.4): GR-16's SDR arm, with M(p→709) =
    M(2020→709)·M(p→2020).
    - The reading is exact where the HLG arm floored no channel and did not clip (reflection ≤
      3.74).
    - A LUT media keeps HD-13 (h)'s un-lift, which is already exact because its output is
      lifted by HD-3.
    - The eyedropper stores the pick through the same reading (`KeyReading.of(media:url:)`).
    - Amends HD-19 (c)'s "every other layer".
  - **(b) A PQ still's peak, #325.** A still whose decoded space is PQ-based (HD-19 (a)) is a PQ
    file. Import writes `media.color.pq` from `rc_hdr10_still_peak` over the file's bytes;
    ImageIO's properties are not read.
    - **PNG:** the first `cLLI` (8 bytes or more; MaxCLL a big-endian u32 in 0.0001 cd/m², read
      through `ten_thousandths`) and the first `mDCV` (24 bytes or more; its maximum at bytes
      16–19 in 0.0001 cd/m², through `mastering_max`), each counted only before the first
      `IDAT`. CRCs are not checked.
    - **ISOBMFF** (`ftyp` at bytes 4–8): the first top-level `meta` (a FullBox) gives `pitm` (the
      item id a u16 when its version is 0, else a u32) and `iprp`. Inside `iprp`, `ipco` holds
      the properties (1-based) and `ipma` (a FullBox) the associations: an entry's item id is a
      u16 when the version is 0, else a u32; `association_count` is a u8; each association is a
      u16 when flags & 1, else a u8, its index the low 15 or low 7 bits. Among the primary
      item's associated properties, the first `clli` (4 bytes or more, `max_cll`) and the first
      `mdcv` (24 bytes or more, `mastering_max`) are read. A box size of 1 means a 64-bit size,
      0 that the box runs to its parent's end, and an overrun ends the walk. The `av1C` OBUs are
      not read.
    - **The choice:** MaxCLL when present and non-zero, else the mastering maximum
      (`hdr10::choose`), else `{}`. Any other file reads `{}`. No input panics.
    - **The op:** `set_media_color {peak}` takes a PQ still. Camera Log stays on video only, its
      sentence unchanged. A stored colour of `pq` alone is valid on an image media.
    - **What draws:** the still's recipe layer publishes `input.peak`. `LayerLift` runs the
      `.pq` arm at that peak — BT.2390's EETF above 1,000 in HLG, the shoulder at
      max(peak, 203)/203 in SDR — and its pool hits only on the same peak. The key reads
      `.pq(peak)`. The Media tab's HDR10 section acts on the still.
    - **Persistence:** format 26. An older file is not re-read (HD-12's rule).
    - Amends HD-12 (where import writes `pq`) and HD-19 (a) (a still's peak).
- **HD-21 — Clean-up 3 batch B, phase 2's settlement: an HLG or PQ still's thumbnail drawn
  through step 0 (#323).** Recorded before the phase's code. No op, tool, argument, recipe,
  catalog or format change (format stays 26).
  - **Which stills:** a still whose first image's space is HLG- or PQ-based
    (`StillColor.conversion(at:)`, HD-19 (a)), or an image media whose `color.pq` has an
    effective peak (HD-20 (b)). Every other still keeps today's tile (ImageIO's decode, longest
    side 640, JPEG 0.7) and its flat marker, byte for byte.
  - **How it is drawn:** GR-21's one-clip project around the media — its pixel size, its rate,
    the still at 0, and its `pq` only when it has a peak — built as `render_frame` builds a
    frame and read by the generator at 0 with zero tolerance, its longest side at most 640
    (`thumbnailHeight` × 4, today's still bound).
  - **Which picture:** the SDR project's picture (GR-15's arm at the still's peak), in an HLG
    project too, as a video's converted strip is.
  - **The marker:** GR-21's converted stamp. A labelled still with no peak writes `transfer`
    "hlg" or "pq"; a PQ still with a peak writes `peak` (HD-12's shape).
  - **The head check:** a still's label is resolved first (a header read, no decode), so a flat
    marker from a build before HD-21 is drawn again. This differs from GR-21's accepted limit
    for video.
  - **Peak changes:** a set, clear, undo or redo of a PQ still's peak starts a pass (GR-21's
    ledger rule, through `convertingColor`).
  - **Failure:** a failed build or read writes today's tile and no marker, so the next open
    retries.
  - **The Media-tab row:** an HLG or PQ still shows no picture until its tile lands. It never
    shows ImageIO's own tone map.
  - **Measured by** `log_thumbs_proof.py` TS0, TS and TU.
  - **Amends** GR-21 and HD-19 (a).
- **HD-22 — Clean-up 3 batch B, phase 3's settlement: a gain-map still drawn as HDR in an HLG
  project (#322).** Recorded before the phase's code. No op, tool, argument, recipe, catalog,
  schema, `media.color` or format change (format stays 26).
  - **(a) Which stills.** A still whose base `StillColor` does not claim (its first image's space
    is neither HLG- nor PQ-based, HD-19 (a)) and whose first image carries an ISO 21496-1 or
    Apple HDR gain map: `CGImageSourceCopyAuxiliaryDataInfoAtIndex` answers for
    `kCGImageAuxiliaryDataTypeISOGainMap` or `kCGImageAuxiliaryDataTypeHDRGainMap`
    (`StillGainMap.hasGainMap`).
    - **M2, measured 2026-10-22** (`tools/proof/work/cleanup3/m2/`, scratch, gitignored:
      `m2.swift` built by `swift_build.py`, run by `python3 -I m2.py`). The fixture is eight
      equal vertical bands of extended-linear grey, L = 0.05, 0.18, 0.5, 1, 2, 4, 6, 8, drawn
      into a 16-bit-float `extendedLinearSRGB` image.
    - **The writer.** W1, `CGImageDestinationAddImage` with `kCGImageDestinationEncodeRequest:
      kCGImageDestinationEncodeToISOGainmap` (quality 0.99), needs the source image's content
      headroom set (`CGImageCreateCopyWithContentHeadroom`, 8). At the default headroom (0)
      the file carried an ISO gain map but every band from L = 1 up read back 1.0. At 8 it
      answered the ISO lookup and not Apple's. Its base is `kCGColorSpaceDisplayP3` at 8 bits
      (headroom 1.0, the sRGB transfer), ImageIO's own tone map of the bands: codes 43, 84,
      130, 166, 202, 237, 255, 255 (linear 0.024, 0.089, 0.223, 0.381, 0.591, 0.847, 1, 1).
      W2 (Core Image's HEIF writer with `.hdrImage`) also wrote an ISO gain map, over a base
      clipped at L = 1 (codes 63, 118, 188, then 255). W1 is the fixture's writer.
    - **The routes.** R1, `decodeImage`'s thumbnail options plus `kCGImageSourceDecodeRequest:
      kCGImageSourceDecodeToHDR`, answered a PQ-based 10-bit image (content headroom 8.0).
      Drawn into 16-bit-float extended-linear BT.2020 with `setEDRTargetHeadroom(0)`, the
      bands read 0.049, 0.181, 0.499, 1.000, 1.996, 4.004, 5.992, 7.984. A fresh context's
      headroom is already 0, and both read the same. The 1024×128 file decoded in 18–27 ms,
      the 9000×600 one came back 8192×546 in 251 ms, and an Orientation-6 copy
      (`CGImageDestinationAddImageFromSource`, `kCGImageDestinationPreserveGainMap`) came back
      128×1024 with the same bands. R2, `CGImageSourceCreateImageAtIndex` with DecodeToHDR,
      read the same bands but neither bounded (9000×600) nor oriented (1024×128). R3, Core
      Image's `.expandToHDR`, read 0.049 … 8.000, oriented but not bounded. R1 over
      `still8.png`, `still16_srgb.png`, `still_hlg.heic` and `still_pq.png` answered today's
      space, depth and bytes, and none has a gain map. So **R1 is the route**: today's
      `decodeImage` with one more option, nothing bounded or oriented by hand (HD-19 (a)). No
      owner photo was in `tools/proof/media/`.
  - **(b) In an HLG project.** R1's decode (`StillGainMap.decodeHDR`) is drawn into 16-bit-float
    premultiplied `extendedLinearITUR_2020`, where 1.0 is the base's white at 203 cd/m² (BT.2408,
    HD-3's SDR white), with `setEDRTargetHeadroom(0)`, so the full gain is applied and nothing is
    tone-mapped. It is encoded on the CPU to SMPTE ST 2084 PQ (each channel floored at 0, ×203,
    at most 10,000 cd/m²; `StillGainMap.encodePQ`) and uploaded `rgba16Float`. Then step 0's
    `.pq(.bt2020)` arm runs at the rendition's peak: its brightest decoded channel × 203,
    rounded up, clamped to 1…10,000 (`Rendered.peak`; a stored `input.peak` would win, and none
    is written, (e)). BT.2390's EETF applies above 1,000 (HD-13 (c)). No highlight the file holds
    is clipped before the EETF.
  - **(c) Parts with no gain** are the base's own linear light (its own EOTF), not HD-3's lift of
    its codes, so un-gained mids may sit darker than the same still's lift. The owner chose this
    on 2026-10-22 ("draw as the gain map defines it, measure and record the difference").
    `hdr_proof.py` HG measures how this differs from the lifted base and prints the figure.
    **Measured** (HG, Release, 2026-10-22, the synthetic fixture): the rendition sits above the
    lifted base at every band, by 48.3 10-bit levels at L = 0.05, 122.0 at L = 0.5, 148.7 at
    L = 1 and 256.6 at L = 8, because this fixture's base is ImageIO's own tone map of the
    bands, darker than their light. A real photo's base and gain differ; HDR-7 looks at one.
  - **(d) In an SDR project, and in every thumbnail and Media-tab row:** the base, as today, byte
    for byte. HD-21 does not apply, because `StillColor` does not claim the still.
  - **(e) Not stored.** No `media.color` is written and there is no Media-tab HDR10 section.
    `set_media_color {peak}` still refuses a gain-map still ("…is not a PQ file; only a PQ file
    takes a peak").
  - **(f) The image cache.** An HLG project's still textures sit under their own key
    (`image:hlg:<media>:<path>`), and that texture is unchanged for every other still. The SDR key
    is unchanged.
  - **(g) The chroma key** in an HLG project reads HD-13 (h)'s un-lift on a gain-map still. The
    eyedropper's `KeyReading.of(media:url:)` reads the same, by the SDR label, so a pick in HLG
    keys. A key picked in an SDR project on the base is close, not exact.
  - **(h) Show SDR Version and the SDR deliverables** of an HLG project show the rendition through
    HD-14's output pass (the project's own HDR→SDR conversion), not the photo's SDR base. The
    owner chose this on 2026-10-22 ("HDR toned down").
  - **(i) What the proof does not cover:** Apple's pre-ISO gain map, a real photo's headroom and
    look, and JPEG or AVIF gain maps. These are `docs/manual-checks.md` HDR-7's.
  - **(j) Amends** HD-13 (f) and HD-19 (a).
  - **(k) The proof's record** (2026-10-22). HG0's control decodes the base with HD-3's lift
    (Core Media 709's γ and toe, HD-13 (f)), not by the base's own transfer: on the untouched
    tree every unclaimed still is drawn through the `.sdr` arm, so the control held to 1.30/1023
    with that decode and would have been 38.57/1023 off with sRGB. The rule changed before the
    control ran, and the row prints both figures. The `gainmap-peak-dropped` mutant is caught
    only by HG's bands-increasing test (L = 6 and L = 8 both render 0.99951); the L = 6 band
    sat 1.85/1023 from its oracle, inside ±2/1023, so the per-band check alone would miss it
    (#330).
  - **(l) The band moved to L = 5** (#330, 2026-10-25). The fixture's bands are L = 0.05, 0.18,
    0.5, 1, 2, 4, 5, 8 (`gainmap_writer.swift`, `GAINMAP_L`): the L = 5 band, 1,015 cd/m², sits
    just above the 1,000 cd/m² a dropped peak clips at, where the EETF still moves it. The
    oracle (computed, peak 1621): with the EETF the L = 5 band sits 10.19/1023 below the same
    band's no-peak clip, against 2.32/1023 at L = 6; a half-float ULP of its PQ signal moves it
    0.29/1023. So `gainmap-peak-dropped` fails the per-band check (±2/1023) by about 10/1023.
    HG also gains a check aimed at the peak, its rule set before the run: the L = 5 band's mean
    is at least 5/1023 below the mean of pq_hlg(pq_signal(203·rgb)) with no EETF, the gap
    printed in levels. HG's ≥ 40/1023 rows are L = 2, 4, 5 and 8. A fixture under
    `work/hdr/media/` older than the writer is remade. (a) and (c) stay as measured on the
    L = 6 fixture. **Measured** (Release, 2026-10-25): the L = 5 band (linear 5.0078) 0.40/1023
    from its oracle and 10.49/1023 below its no-peak clip; under `gainmap-peak-dropped` 9.59/1023
    from its oracle and 0.50/1023 below the clip, so the per-band check, the bands' order and the
    peak check all fail.
- **#487 — AVIF is the ninth still type.** `MediaImporter.imageTypes` gains
  `public.avif`, so `isImage` routes it to `probeImage` and it comes in as
  `kind: image` on every door that reaches `probe`, with no ffmpeg question. It
  joins TIFF, GIF, BMP, HEIF and WebP: a Media tab drop, `import_media` or Add
  Background. `ProjectDocument.mediaTypeIdentifiers` and `project.yml` are
  unchanged, so File ▸ Add Media…, File ▸ Open and `open_project` keep refusing it
  as they refuse a TIFF. HD-12 and HD-19 already write of an AVIF as a still.
  Bytes ImageIO cannot parse answer `Could not read x.avif.`. **Accepted:**
  `probeImage` reads only the header, so an AVIF cut short whose header survives
  imports as a still, and draws black or wrong.
