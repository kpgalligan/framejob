// Copyright 2006 The Android Open Source Project
// Copyright 2020 Yevhenii Reizner
//
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

use alloc::vec;
use alloc::vec::Vec;

use core::convert::TryFrom;
use core::num::NonZeroUsize;

use tiny_skia_path::IntSize;

use crate::{Color, IntRect};

use crate::color::PremultipliedColorU8;
use crate::geom::{IntSizeExt, ScreenIntRect};

#[cfg(feature = "png-format")]
use crate::color::{premultiply_u8, ALPHA_U8_OPAQUE};

/// Number of bytes per pixel.
pub const BYTES_PER_PIXEL: usize = 4;

// Frame Job (spec §11 PR-15): the door to a deep pixmap. Inside `with_deep_pixmaps`, on the calling
// thread only, `Pixmap::new` makes the residual plane; everywhere else it makes today's 8-bit
// pixmap. The flag is restored on the way out, on a panic too.
#[cfg(feature = "std")]
std::thread_local! {
    static DEEP: core::cell::Cell<bool> = const { core::cell::Cell::new(false) };
}

/// Frame Job (spec §11 PR-15): runs `f` with every `Pixmap::new` on this thread deep.
#[cfg(feature = "std")]
pub fn with_deep_pixmaps<R>(f: impl FnOnce() -> R) -> R {
    struct Restore(bool);
    impl Drop for Restore {
        fn drop(&mut self) {
            DEEP.with(|deep| deep.set(self.0));
        }
    }
    let _restore = Restore(DEEP.with(|deep| deep.replace(true)));
    f()
}

fn deep_pixmaps() -> bool {
    #[cfg(feature = "std")]
    {
        DEEP.with(|deep| deep.get())
    }
    #[cfg(not(feature = "std"))]
    {
        false
    }
}

// Frame Job (spec §11 PR-15): a deep pixmap read at 8 bits. Each pixel holding a residual has R, G and B
// rounded with PR-13's offset for its position (`origin` is the first pixel's), clamped to
// [0, alpha]; alpha is already rounded. A value on a level never moves: the offset is under
// half a level. The residual is zeroed.
pub(crate) fn collapse(data: &mut [u8], lo: &mut [u8], width: usize, origin: (u32, u32)) {
    for (i, (px, l)) in data.chunks_exact_mut(4).zip(lo.chunks_exact_mut(4)).enumerate() {
        if l[0] | l[1] | l[2] | l[3] == 0 {
            continue;
        }
        let (x, y) = ((i % width) as u32 + origin.0, (i / width) as u32 + origin.1);
        let offset = crate::pipeline::dither_offset_256(x, y);
        let alpha = px[3] as i32;
        for c in 0..3 {
            let v = ((px[c] as i32) << 8) + (l[c] as i8 as i32);
            px[c] = ((v + offset + 128) >> 8).clamp(0, alpha) as u8;
        }
        l.fill(0);
    }
}

// Frame Job (spec §11 PR-15): whether every byte is 0, without a branch a byte.
fn is_zero(bytes: &[u8]) -> bool {
    bytes.iter().fold(0u8, |all, byte| all | *byte) == 0
}

// Frame Job (spec §11 PR-15): `collapse` of a borrowed deep pixmap, as new 8-bit bytes.
pub(crate) fn collapsed(data: &[u8], lo: &[u8], width: usize) -> Vec<u8> {
    let (mut data, mut lo) = (data.to_vec(), lo.to_vec());
    collapse(&mut data, &mut lo, width, (0, 0));
    data
}

/// A container that owns premultiplied RGBA pixels.
///
/// The data is not aligned, therefore width == stride.
#[derive(PartialEq)]
pub struct Pixmap {
    data: Vec<u8>,
    // Frame Job (spec §11 PR-15): the residual plane, empty when the pixmap is 8-bit. A channel's
    // value in 1/256 levels is `data × 256 + (lo as i8)`, 65280 being 1; `data` alone is the
    // value rounded to 8 bits.
    lo: Vec<u8>,
    size: IntSize,
}

// Frame Job (spec §11 PR-15): a copy is 8-bit. Only resvg's filters clone a pixmap, and they read the
// copy's bytes, so a deep source is rounded with PR-13's offset here.
impl Clone for Pixmap {
    fn clone(&self) -> Self {
        let data = if self.lo.is_empty() {
            self.data.clone()
        } else {
            collapsed(&self.data, &self.lo, self.size.width() as usize)
        };
        Pixmap { data, lo: Vec::new(), size: self.size }
    }
}

impl Pixmap {
    /// Allocates a new pixmap.
    ///
    /// A pixmap is filled with transparent black by default, aka (0, 0, 0, 0).
    ///
    /// Zero size in an error.
    ///
    /// Pixmap's width is limited by i32::MAX/4.
    pub fn new(width: u32, height: u32) -> Option<Self> {
        let size = IntSize::from_wh(width, height)?;
        let data_len = data_len_for_size(size)?;

        // We cannot check that allocation was successful yet.
        // We have to wait for https://github.com/rust-lang/rust/issues/48043

        Some(Pixmap {
            data: vec![0; data_len],
            lo: if deep_pixmaps() { vec![0; data_len] } else { Vec::new() },
            size,
        })
    }

    /// Creates a new pixmap by taking ownership over an image buffer
    /// (premultiplied RGBA pixels).
    ///
    /// The size needs to match the data provided.
    ///
    /// Pixmap's width is limited by i32::MAX/4.
    pub fn from_vec(data: Vec<u8>, size: IntSize) -> Option<Self> {
        let data_len = data_len_for_size(size)?;
        if data.len() != data_len {
            return None;
        }

        Some(Pixmap { data, lo: Vec::new(), size })
    }

    /// Decodes a PNG data into a `Pixmap`.
    ///
    /// Only 8-bit images are supported.
    /// Index PNGs are not supported.
    #[cfg(feature = "png-format")]
    pub fn decode_png(data: &[u8]) -> Result<Self, png::DecodingError> {
        fn make_custom_png_error(msg: &str) -> png::DecodingError {
            std::io::Error::new(std::io::ErrorKind::Other, msg).into()
        }

        let mut decoder = png::Decoder::new(std::io::BufReader::new(std::io::Cursor::new(data)));
        decoder.set_transformations(png::Transformations::normalize_to_color8());
        let mut reader = decoder.read_info()?;
        let output_buffer_size = reader
            .output_buffer_size()
            .ok_or(png::DecodingError::LimitsExceeded)?;
        let mut img_data = vec![0; output_buffer_size];
        let info = reader.next_frame(&mut img_data)?;

        if info.bit_depth != png::BitDepth::Eight {
            return Err(make_custom_png_error("unsupported bit depth"));
        }

        let size = IntSize::from_wh(info.width, info.height)
            .ok_or_else(|| make_custom_png_error("invalid image size"))?;
        let data_len =
            data_len_for_size(size).ok_or_else(|| make_custom_png_error("image is too big"))?;

        img_data = match info.color_type {
            png::ColorType::Rgb => {
                let mut rgba_data = Vec::with_capacity(data_len);
                for rgb in img_data.chunks(3) {
                    rgba_data.push(rgb[0]);
                    rgba_data.push(rgb[1]);
                    rgba_data.push(rgb[2]);
                    rgba_data.push(ALPHA_U8_OPAQUE);
                }

                rgba_data
            }
            png::ColorType::Rgba => img_data,
            png::ColorType::Grayscale => {
                let mut rgba_data = Vec::with_capacity(data_len);
                for gray in img_data {
                    rgba_data.push(gray);
                    rgba_data.push(gray);
                    rgba_data.push(gray);
                    rgba_data.push(ALPHA_U8_OPAQUE);
                }

                rgba_data
            }
            png::ColorType::GrayscaleAlpha => {
                let mut rgba_data = Vec::with_capacity(data_len);
                for slice in img_data.chunks(2) {
                    let gray = slice[0];
                    let alpha = slice[1];
                    rgba_data.push(gray);
                    rgba_data.push(gray);
                    rgba_data.push(gray);
                    rgba_data.push(alpha);
                }

                rgba_data
            }
            png::ColorType::Indexed => {
                return Err(make_custom_png_error("indexed PNG is not supported"));
            }
        };

        // Premultiply alpha.
        //
        // We cannon use RasterPipeline here, which is faster,
        // because it produces slightly different results.
        // Seems like Skia does the same.
        //
        // Also, in our tests unsafe version (no bound checking)
        // had roughly the same performance. So we keep the safe one.
        for pixel in img_data.as_mut_slice().chunks_mut(BYTES_PER_PIXEL) {
            let a = pixel[3];
            pixel[0] = premultiply_u8(pixel[0], a);
            pixel[1] = premultiply_u8(pixel[1], a);
            pixel[2] = premultiply_u8(pixel[2], a);
        }

        Pixmap::from_vec(img_data, size)
            .ok_or_else(|| make_custom_png_error("failed to create a pixmap"))
    }

    /// Loads a PNG file into a `Pixmap`.
    ///
    /// Only 8-bit images are supported.
    /// Index PNGs are not supported.
    #[cfg(feature = "png-format")]
    pub fn load_png<P: AsRef<std::path::Path>>(path: P) -> Result<Self, png::DecodingError> {
        // `png::Decoder` is generic over input, which means that it will instance
        // two copies: one for `&[]` and one for `File`. Which will simply bloat the code.
        // Therefore we're using only one type for input.
        let data = std::fs::read(path)?;
        Self::decode_png(&data)
    }

    /// Encodes pixmap into a PNG data.
    #[cfg(feature = "png-format")]
    pub fn encode_png(&self) -> Result<Vec<u8>, png::EncodingError> {
        self.as_ref().encode_png()
    }

    /// Saves pixmap as a PNG file.
    #[cfg(feature = "png-format")]
    pub fn save_png<P: AsRef<std::path::Path>>(&self, path: P) -> Result<(), png::EncodingError> {
        self.as_ref().save_png(path)
    }

    /// Returns a container that references Pixmap's data.
    pub fn as_ref(&self) -> PixmapRef<'_> {
        PixmapRef {
            data: &self.data,
            lo: if self.lo.is_empty() { None } else { Some(&self.lo) },
            size: self.size,
        }
    }

    /// Returns a container that references Pixmap's data.
    pub fn as_mut(&mut self) -> PixmapMut<'_> {
        PixmapMut {
            data: &mut self.data,
            lo: if self.lo.is_empty() { None } else { Some(&mut self.lo) },
            size: self.size,
        }
    }

    /// Frame Job (spec §11 PR-15): copies the pixmap into `out` as premultiplied RGBA, 16 bits
    /// a channel with 65535 as 1, rows `stride` values apart. A row's values past `width × 4`
    /// are untouched. An 8-bit pixmap copies as `× 257`. Panics if `out` is too short.
    pub fn copy_rgba16(&self, out: &mut [u16], stride: usize) {
        let row = self.size.width() as usize * BYTES_PER_PIXEL;
        for (y, hi) in self.data.chunks_exact(row).enumerate() {
            let to = &mut out[y * stride..y * stride + row];
            let lo = if self.lo.is_empty() { &[][..] } else { &self.lo[y * row..(y + 1) * row] };
            // A row with no residual (an 8-bit pixmap's, an untouched or solid one) widens
            // `data` alone; both loops are branch-free.
            let flat = lo.is_empty() || is_zero(lo);
            if flat {
                for (t, h) in to.iter_mut().zip(hi) {
                    *t = *h as u16 * 257;
                }
            } else {
                for ((t, h), l) in to.iter_mut().zip(hi).zip(lo) {
                    let v = ((*h as i32) << 8) + (*l as i8 as i32);
                    *t = ((v * 257 + 128) >> 8) as u16;
                }
            }
        }
    }

    /// Returns pixmap's width.
    #[inline]
    pub fn width(&self) -> u32 {
        self.size.width()
    }

    /// Returns pixmap's height.
    #[inline]
    pub fn height(&self) -> u32 {
        self.size.height()
    }

    /// Returns pixmap's size.
    #[allow(dead_code)]
    pub(crate) fn size(&self) -> IntSize {
        self.size
    }

    /// Fills the entire pixmap with a specified color.
    pub fn fill(&mut self, color: Color) {
        let c = color.premultiply().to_color_u8();
        // Frame Job (spec §11 PR-15): a colour is on a level; the pixmap stays deep.
        self.lo.fill(0);
        for p in bytemuck::cast_slice_mut::<u8, PremultipliedColorU8>(&mut self.data) {
            *p = c;
        }
    }

    /// Returns the internal data.
    ///
    /// Byteorder: RGBA
    pub fn data(&self) -> &[u8] {
        self.data.as_slice()
    }

    /// Returns the mutable internal data.
    ///
    /// Byteorder: RGBA
    pub fn data_mut(&mut self) -> &mut [u8] {
        // Frame Job (spec §11 PR-15): an 8-bit reader or writer outside the pipeline (resvg's filters and
        // image decoders) gets the pixmap rounded with PR-13's offset, 8-bit from here on.
        if !self.lo.is_empty() {
            collapse(&mut self.data, &mut self.lo, self.size.width() as usize, (0, 0));
            self.lo = Vec::new();
        }
        self.data.as_mut_slice()
    }

    /// Returns a pixel color.
    ///
    /// Returns `None` when position is out of bounds.
    pub fn pixel(&self, x: u32, y: u32) -> Option<PremultipliedColorU8> {
        let idx = self.width().checked_mul(y)?.checked_add(x)?;
        self.pixels().get(idx as usize).cloned()
    }

    /// Returns a mutable slice of pixels.
    pub fn pixels_mut(&mut self) -> &mut [PremultipliedColorU8] {
        bytemuck::cast_slice_mut(self.data_mut())
    }

    /// Returns a slice of pixels.
    pub fn pixels(&self) -> &[PremultipliedColorU8] {
        bytemuck::cast_slice(self.data())
    }

    /// Consumes the internal data.
    ///
    /// Byteorder: RGBA
    pub fn take(mut self) -> Vec<u8> {
        // Frame Job (spec §11 PR-15): as `data_mut`.
        self.data_mut();
        self.data
    }

    /// Consumes the pixmap and returns the internal data as demultiplied RGBA bytes.
    ///
    /// Byteorder: RGBA
    pub fn take_demultiplied(mut self) -> Vec<u8> {
        // Demultiply alpha.
        //
        // RasterPipeline is 15% faster here, but produces slightly different results
        // due to rounding. So we stick with this method for now.
        for pixel in self.pixels_mut() {
            let c = pixel.demultiply();
            *pixel =
                PremultipliedColorU8::from_rgba_unchecked(c.red(), c.green(), c.blue(), c.alpha());
        }
        self.data
    }

    /// Returns a copy of the pixmap that intersects the `rect`.
    ///
    /// Returns `None` when `Pixmap`'s rect doesn't contain `rect`.
    pub fn clone_rect(&self, rect: IntRect) -> Option<Pixmap> {
        self.as_ref().clone_rect(rect)
    }
}

impl core::fmt::Debug for Pixmap {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.debug_struct("Pixmap")
            .field("data", &"...")
            .field("width", &self.size.width())
            .field("height", &self.size.height())
            .finish()
    }
}

/// A container that references premultiplied RGBA pixels.
///
/// Can be created from `Pixmap` or from a user provided data.
///
/// The data is not aligned, therefore width == stride.
#[derive(Clone, Copy, PartialEq)]
pub struct PixmapRef<'a> {
    data: &'a [u8],
    pub(crate) lo: Option<&'a [u8]>,
    size: IntSize,
}

impl<'a> PixmapRef<'a> {
    /// Creates a new `PixmapRef` from bytes.
    ///
    /// The size must be at least `size.width() * size.height() * BYTES_PER_PIXEL`.
    /// Zero size in an error. Width is limited by i32::MAX/4.
    ///
    /// The `data` is assumed to have premultiplied RGBA pixels (byteorder: RGBA).
    pub fn from_bytes(data: &'a [u8], width: u32, height: u32) -> Option<Self> {
        let size = IntSize::from_wh(width, height)?;
        let data_len = data_len_for_size(size)?;
        if data.len() < data_len {
            return None;
        }

        Some(PixmapRef { data, lo: None, size })
    }

    /// Creates a new `Pixmap` from the current data.
    ///
    /// Clones the underlying data.
    pub fn to_owned(&self) -> Pixmap {
        Pixmap {
            data: self.data.to_vec(),
            // Frame Job (spec §11 PR-15): the residual plane follows.
            lo: self.lo.as_ref().map(|lo| lo.to_vec()).unwrap_or_default(),
            size: self.size,
        }
    }

    /// Returns pixmap's width.
    #[inline]
    pub fn width(&self) -> u32 {
        self.size.width()
    }

    /// Returns pixmap's height.
    #[inline]
    pub fn height(&self) -> u32 {
        self.size.height()
    }

    /// Returns pixmap's size.
    pub(crate) fn size(&self) -> IntSize {
        self.size
    }

    /// Returns pixmap's rect.
    pub(crate) fn rect(&self) -> ScreenIntRect {
        self.size.to_screen_int_rect(0, 0)
    }

    /// Returns the internal data.
    ///
    /// Byteorder: RGBA
    pub fn data(&self) -> &'a [u8] {
        self.data
    }

    /// Returns a pixel color.
    ///
    /// Returns `None` when position is out of bounds.
    pub fn pixel(&self, x: u32, y: u32) -> Option<PremultipliedColorU8> {
        let idx = self.width().checked_mul(y)?.checked_add(x)?;
        self.pixels().get(idx as usize).cloned()
    }

    /// Returns a slice of pixels.
    pub fn pixels(&self) -> &'a [PremultipliedColorU8] {
        bytemuck::cast_slice(self.data())
    }

    // TODO: add rows() iterator

    /// Returns a copy of the pixmap that intersects the `rect`.
    ///
    /// Returns `None` when `Pixmap`'s rect doesn't contain `rect`.
    pub fn clone_rect(&self, rect: IntRect) -> Option<Pixmap> {
        // TODO: to ScreenIntRect?

        let rect = self.rect().to_int_rect().intersect(&rect)?;
        // Frame Job (spec §11 PR-15): a copy of a deep pixmap is 8-bit, as `Pixmap::clone`, with the
        // offset of each pixel's place in this pixmap.
        if let Some(lo) = self.lo {
            let (w, rw) = (self.width() as usize * 4, rect.width() as usize * 4);
            let (mut data, mut part) = (Vec::new(), Vec::new());
            for y in 0..rect.height() as usize {
                let from = (y + rect.y() as usize) * w + rect.x() as usize * 4;
                data.extend_from_slice(&self.data[from..from + rw]);
                part.extend_from_slice(&lo[from..from + rw]);
            }
            let origin = (rect.x() as u32, rect.y() as u32);
            collapse(&mut data, &mut part, rect.width() as usize, origin);
            return Some(Pixmap { data, lo: Vec::new(), size: rect.size() });
        }
        let mut new = Pixmap::new(rect.width(), rect.height())?;
        {
            let old_pixels = self.pixels();
            let mut new_mut = new.as_mut();
            let new_pixels = new_mut.pixels_mut();

            // TODO: optimize
            for y in 0..rect.height() {
                for x in 0..rect.width() {
                    let old_idx = (y + rect.y() as u32) * self.width() + (x + rect.x() as u32);
                    let new_idx = y * rect.width() + x;
                    new_pixels[new_idx as usize] = old_pixels[old_idx as usize];
                }
            }
        }

        Some(new)
    }

    /// Encodes pixmap into a PNG data.
    #[cfg(feature = "png-format")]
    pub fn encode_png(&self) -> Result<Vec<u8>, png::EncodingError> {
        // Skia uses skcms here, which is somewhat similar to RasterPipeline.

        // Sadly, we have to copy the pixmap here, because of demultiplication.
        // Not sure how to avoid this.
        // TODO: remove allocation
        let demultiplied_data = self.to_owned().take_demultiplied();

        let mut data = Vec::new();
        {
            let mut encoder = png::Encoder::new(&mut data, self.width(), self.height());
            encoder.set_color(png::ColorType::Rgba);
            encoder.set_depth(png::BitDepth::Eight);
            let mut writer = encoder.write_header()?;
            writer.write_image_data(&demultiplied_data)?;
        }

        Ok(data)
    }

    /// Saves pixmap as a PNG file.
    #[cfg(feature = "png-format")]
    pub fn save_png<P: AsRef<std::path::Path>>(&self, path: P) -> Result<(), png::EncodingError> {
        let data = self.encode_png()?;
        std::fs::write(path, data)?;
        Ok(())
    }
}

impl core::fmt::Debug for PixmapRef<'_> {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.debug_struct("PixmapRef")
            .field("data", &"...")
            .field("width", &self.size.width())
            .field("height", &self.size.height())
            .finish()
    }
}

/// A container that references mutable premultiplied RGBA pixels.
///
/// Can be created from `Pixmap` or from a user provided data.
///
/// The data is not aligned, therefore width == stride.
#[derive(PartialEq)]
pub struct PixmapMut<'a> {
    data: &'a mut [u8],
    pub(crate) lo: Option<&'a mut [u8]>,
    size: IntSize,
}

impl<'a> PixmapMut<'a> {
    /// Creates a new `PixmapMut` from bytes.
    ///
    /// The size must be at least `size.width() * size.height() * BYTES_PER_PIXEL`.
    /// Zero size in an error. Width is limited by i32::MAX/4.
    ///
    /// The `data` is assumed to have premultiplied RGBA pixels (byteorder: RGBA).
    pub fn from_bytes(data: &'a mut [u8], width: u32, height: u32) -> Option<Self> {
        let size = IntSize::from_wh(width, height)?;
        let data_len = data_len_for_size(size)?;
        if data.len() < data_len {
            return None;
        }

        Some(PixmapMut { data, lo: None, size })
    }

    /// Creates a new `Pixmap` from the current data.
    ///
    /// Clones the underlying data.
    pub fn to_owned(&self) -> Pixmap {
        Pixmap {
            data: self.data.to_vec(),
            // Frame Job (spec §11 PR-15): the residual plane follows.
            lo: self.lo.as_ref().map(|lo| lo.to_vec()).unwrap_or_default(),
            size: self.size,
        }
    }

    /// Returns a container that references Pixmap's data.
    pub fn as_ref(&self) -> PixmapRef<'_> {
        PixmapRef {
            data: self.data,
            lo: self.lo.as_deref(),
            size: self.size,
        }
    }

    /// Returns pixmap's width.
    #[inline]
    pub fn width(&self) -> u32 {
        self.size.width()
    }

    /// Returns pixmap's height.
    #[inline]
    pub fn height(&self) -> u32 {
        self.size.height()
    }

    /// Returns pixmap's size.
    pub(crate) fn size(&self) -> IntSize {
        self.size
    }

    /// Fills the entire pixmap with a specified color.
    pub fn fill(&mut self, color: Color) {
        let c = color.premultiply().to_color_u8();
        // Frame Job (spec §11 PR-15): a colour is on a level; the pixmap stays deep.
        if let Some(lo) = self.lo.as_deref_mut() {
            lo.fill(0);
        }
        for p in bytemuck::cast_slice_mut::<u8, PremultipliedColorU8>(self.data) {
            *p = c;
        }
    }

    /// Returns the mutable internal data.
    ///
    /// Byteorder: RGBA
    pub fn data_mut(&mut self) -> &mut [u8] {
        // Frame Job (spec §11 PR-15): as `Pixmap::data_mut`; a borrowed plane is zeroed, not dropped.
        if let Some(lo) = self.lo.as_deref_mut() {
            collapse(self.data, lo, self.size.width() as usize, (0, 0));
        }
        self.data
    }

    /// Returns a mutable slice of pixels.
    pub fn pixels_mut(&mut self) -> &mut [PremultipliedColorU8] {
        bytemuck::cast_slice_mut(self.data_mut())
    }

    /// Creates `SubPixmapMut` that contains the whole `PixmapMut`.
    pub(crate) fn as_subpixmap(&mut self) -> SubPixmapMut<'_> {
        SubPixmapMut {
            size: self.size(),
            real_width: self.width() as usize,
            data: self.data,
            lo: self.lo.as_deref_mut(),
        }
    }

    /// Returns a mutable reference to the pixmap region that intersects the `rect`.
    ///
    /// Returns `None` when `Pixmap`'s rect doesn't contain `rect`.
    pub(crate) fn subpixmap(&mut self, rect: IntRect) -> Option<SubPixmapMut<'_>> {
        let rect = self.size.to_int_rect(0, 0).intersect(&rect)?;
        let row_bytes = self.width() as usize * BYTES_PER_PIXEL;
        let offset = rect.top() as usize * row_bytes + rect.left() as usize * BYTES_PER_PIXEL;

        Some(SubPixmapMut {
            size: rect.size(),
            real_width: self.width() as usize,
            data: &mut self.data[offset..],
            lo: self.lo.as_deref_mut().map(|lo| &mut lo[offset..]),
        })
    }
}

impl core::fmt::Debug for PixmapMut<'_> {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.debug_struct("PixmapMut")
            .field("data", &"...")
            .field("width", &self.size.width())
            .field("height", &self.size.height())
            .finish()
    }
}

/// A `PixmapMut` subregion.
///
/// Unlike `PixmapMut`, contains `real_width` which references the parent `PixmapMut` width.
/// This way we can operate on a `PixmapMut` subregion without reallocations.
/// Primarily required because of `DrawTiler`.
///
/// We cannot implement it in `PixmapMut` directly, because it will brake `fill`, `data_mut`
/// `pixels_mut` and other similar methods.
/// This is because `SubPixmapMut.data` references more "data" than it actually allowed to access.
/// On the other hand, `PixmapMut.data` can access all it's data and it's stored linearly.
pub struct SubPixmapMut<'a> {
    pub data: &'a mut [u8],
    // Frame Job (spec §11 PR-15): the residual plane at the same offset; None for a mask or an 8-bit
    // pixmap.
    pub lo: Option<&'a mut [u8]>,
    pub size: IntSize,
    pub real_width: usize,
}

impl SubPixmapMut<'_> {
    /// Returns a mutable slice of pixels.
    pub fn pixels_mut(&mut self) -> &mut [PremultipliedColorU8] {
        bytemuck::cast_slice_mut(self.data)
    }
}

/// Returns minimum bytes per row as usize.
///
/// Pixmap's maximum value for row bytes must fit in 31 bits.
fn min_row_bytes(size: IntSize) -> Option<NonZeroUsize> {
    let w = i32::try_from(size.width()).ok()?;
    let w = w.checked_mul(BYTES_PER_PIXEL as i32)?;
    NonZeroUsize::new(w as usize)
}

/// Returns storage size required by pixel array.
fn compute_data_len(size: IntSize, row_bytes: usize) -> Option<usize> {
    let h = size.height().checked_sub(1)?;
    let h = (h as usize).checked_mul(row_bytes)?;

    let w = (size.width() as usize).checked_mul(BYTES_PER_PIXEL)?;

    h.checked_add(w)
}

fn data_len_for_size(size: IntSize) -> Option<usize> {
    let row_bytes = min_row_bytes(size)?;
    compute_data_len(size, row_bytes.get())
}
