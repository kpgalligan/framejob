//! The decoded-image cache (spec §11 G-39): a PNG or JPEG asset kept as a
//! stored, unfiltered RGBA8 PNG copy that decodes to the original's pixmap,
//! so resvg's per-frame decode of it is an inflate of stored blocks rather
//! than a real one. One process-wide map, keyed by the SHA-256 of the
//! asset's bytes, under a byte limit the app sets from G-37's budget (0, the
//! default, caches nothing) and trimmed least recently used first. A copy
//! that does not fit is remembered by its size, so it is never rebuilt per
//! frame. No lock is held across a decode, an encode or a usvg call.

use std::collections::BTreeMap;
use std::io::Cursor;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, MutexGuard};

use resvg::tiny_skia::Pixmap;
use resvg::usvg;

/// The `Refused` and `Skipped` entries together; reaching it clears them.
const MARK_CAP: usize = 1024;

/// One asset's bytes and the SHA-256 of those bytes alone (G-39 (b)).
pub(crate) struct Asset {
    pub(crate) data: Arc<Vec<u8>>,
    pub(crate) digest: [u8; 32],
}

enum Entry {
    Ready { copy: Arc<Vec<u8>>, stamp: u64 },
    Building,
    Refused,
    Skipped { len: usize },
}

impl Entry {
    fn is_mark(&self) -> bool {
        matches!(self, Entry::Refused | Entry::Skipped { .. })
    }
}

struct Cache {
    entries: BTreeMap<[u8; 32], Entry>,
    limit: usize,
    /// The sum of every `Ready` copy's length.
    bytes: usize,
    clock: u64,
}

static CACHE: Mutex<Cache> = Mutex::new(Cache {
    entries: BTreeMap::new(),
    limit: 0,
    bytes: 0,
    clock: 0,
});

static BUILDS: AtomicUsize = AtomicUsize::new(0);

fn lock() -> MutexGuard<'static, Cache> {
    CACHE
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

impl Cache {
    fn tick(&mut self) -> u64 {
        self.clock += 1;
        self.clock
    }

    /// Writes a `Refused` or `Skipped` entry; reaching `MARK_CAP` clears them.
    fn mark(&mut self, digest: [u8; 32], entry: Entry) {
        self.entries.insert(digest, entry);
        if self.entries.values().filter(|e| e.is_mark()).count() >= MARK_CAP {
            self.entries.retain(|_, e| !e.is_mark());
        }
    }

    /// Evicts `Ready` copies, least recently used first, until the total
    /// fits the limit; each becomes `Skipped` by its length.
    fn trim(&mut self) {
        while self.bytes > self.limit {
            let oldest = self
                .entries
                .iter()
                .filter_map(|(digest, entry)| match entry {
                    Entry::Ready { copy, stamp } => Some((*stamp, *digest, copy.len())),
                    _ => None,
                })
                .min();
            let Some((_, digest, len)) = oldest else {
                break;
            };
            self.bytes -= len;
            self.mark(digest, Entry::Skipped { len });
        }
    }
}

/// Sets the limit in bytes, trims to it least recently used first, and
/// answers the bytes held after; 0 clears every entry.
pub fn set_image_cache_limit(bytes: usize) -> usize {
    let mut cache = lock();
    cache.limit = bytes;
    if bytes == 0 {
        cache.entries.clear();
        cache.bytes = 0;
    } else {
        cache.trim();
    }
    cache.bytes
}

/// The bytes the cache's copies hold.
pub fn image_cache_bytes() -> usize {
    lock().bytes
}

/// How many copies were built since the process started; tests read deltas.
#[doc(hidden)]
pub fn image_cache_builds() -> usize {
    BUILDS.load(Ordering::SeqCst)
}

#[derive(Clone, Copy)]
enum Source {
    Png,
    Jpeg,
}

fn source_of(bytes: &[u8]) -> Option<Source> {
    if bytes.starts_with(&[0x89, 0x50, 0x4E, 0x47]) {
        Some(Source::Png)
    } else if bytes.starts_with(&[0xFF, 0xD8, 0xFF]) {
        Some(Source::Jpeg)
    } else {
        None
    }
}

/// Clears a `Building` mark if the build unwinds.
struct Building {
    digest: [u8; 32],
    armed: bool,
}

impl Drop for Building {
    fn drop(&mut self) {
        if self.armed {
            let mut cache = lock();
            if matches!(cache.entries.get(&self.digest), Some(Entry::Building)) {
                cache.entries.remove(&self.digest);
            }
        }
    }
}

/// The asset's stored copy as a PNG kind, or None for the original route:
/// not a PNG or JPEG, a limit of 0, a copy being built or refused, or one
/// remembered as not fitting while it still would not.
pub(crate) fn cached_kind(asset: &Asset) -> Option<usvg::ImageKind> {
    let source = source_of(&asset.data)?;
    {
        let mut cache = lock();
        if cache.limit == 0 {
            return None;
        }
        let room = cache.limit.saturating_sub(cache.bytes);
        let stamp = cache.tick();
        match cache.entries.get_mut(&asset.digest) {
            Some(Entry::Ready { copy, stamp: used }) => {
                *used = stamp;
                return Some(usvg::ImageKind::PNG(copy.clone()));
            }
            Some(Entry::Building | Entry::Refused) => return None,
            Some(Entry::Skipped { len }) if *len > room => return None,
            _ => {}
        }
        cache.entries.insert(asset.digest, Entry::Building);
    }
    let mut guard = Building {
        digest: asset.digest,
        armed: true,
    };
    BUILDS.fetch_add(1, Ordering::SeqCst);
    let built = stored_copy(&asset.data, source).map(Arc::new);
    guard.armed = false;
    let mut cache = lock();
    // A limit of 0 since the build began cleared its mark, and another
    // build may have marked the digest since: a build writes only while the
    // digest is still marked `Building`, so one copy is counted once.
    if !matches!(cache.entries.get(&asset.digest), Some(Entry::Building)) {
        return built.map(usvg::ImageKind::PNG);
    }
    if cache.limit == 0 {
        cache.entries.remove(&asset.digest);
        return built.map(usvg::ImageKind::PNG);
    }
    match &built {
        None => cache.mark(asset.digest, Entry::Refused),
        Some(copy) if copy.len() > cache.limit => {
            cache.mark(asset.digest, Entry::Skipped { len: copy.len() })
        }
        Some(copy) => {
            let stamp = cache.tick();
            let copy = copy.clone();
            cache.bytes += copy.len();
            cache
                .entries
                .insert(asset.digest, Entry::Ready { copy, stamp });
            cache.trim();
        }
    }
    built.map(usvg::ImageKind::PNG)
}

/// The original's straight RGBA8 written as a stored, unfiltered RGBA PNG,
/// used only when it decodes to the original's pixmap at the original's
/// size (G-39 (a)); None refuses it.
fn stored_copy(original: &[u8], source: Source) -> Option<Vec<u8>> {
    let (width, height, rgba) = match source {
        Source::Png => decode_png(original)?,
        Source::Jpeg => decode_jpeg(original)?,
    };
    let copy = encode(width, height, &rgba)?;
    let size = imagesize::blob_size(original).ok()?;
    if size != imagesize::blob_size(&copy).ok()? {
        return None;
    }
    let drawn = Pixmap::decode_png(&copy).ok()?;
    let same = match source {
        Source::Png => {
            let reference = Pixmap::decode_png(original).ok()?;
            drawn.width() == reference.width()
                && drawn.height() == reference.height()
                && drawn.data() == reference.data()
        }
        Source::Jpeg => {
            drawn.width() == width && drawn.height() == height && drawn.data() == rgba.as_slice()
        }
    };
    same.then_some(copy)
}

/// png 0.18 with `normalize_to_color8`, Rgb, Grayscale and GrayscaleAlpha
/// expanded to RGBA exactly as tiny-skia 0.12's `Pixmap::decode_png` does;
/// any other colour type is refused.
fn decode_png(data: &[u8]) -> Option<(u32, u32, Vec<u8>)> {
    let mut decoder = png::Decoder::new(Cursor::new(data));
    decoder.set_transformations(png::Transformations::normalize_to_color8());
    let mut reader = decoder.read_info().ok()?;
    let mut buffer = vec![0; reader.output_buffer_size()?];
    let info = reader.next_frame(&mut buffer).ok()?;
    if info.bit_depth != png::BitDepth::Eight {
        return None;
    }
    buffer.truncate(info.buffer_size());
    let rgba: Vec<u8> = match info.color_type {
        png::ColorType::Rgba => buffer,
        png::ColorType::Rgb => buffer
            .chunks(3)
            .flat_map(|p| [p[0], p[1], p[2], 255])
            .collect(),
        png::ColorType::Grayscale => buffer.iter().flat_map(|&g| [g, g, g, 255]).collect(),
        png::ColorType::GrayscaleAlpha => buffer
            .chunks(2)
            .flat_map(|p| [p[0], p[0], p[0], p[1]])
            .collect(),
        png::ColorType::Indexed => return None,
    };
    Some((info.width, info.height, rgba))
}

/// resvg 0.48.1's `decode_jpeg`, reproduced: zune-jpeg asked for RGBA, and
/// anything else it answers refused.
fn decode_jpeg(data: &[u8]) -> Option<(u32, u32, Vec<u8>)> {
    use zune_jpeg::zune_core::colorspace::ColorSpace;
    use zune_jpeg::zune_core::options::DecoderOptions;

    let options = DecoderOptions::default().jpeg_set_out_colorspace(ColorSpace::RGBA);
    let mut decoder = zune_jpeg::JpegDecoder::new_with_options(Cursor::new(data), options);
    decoder.decode_headers().ok()?;
    let output = decoder.output_colorspace()?;
    let rgba = decoder.decode().ok()?;
    if output != ColorSpace::RGBA {
        return None;
    }
    let info = decoder.info()?;
    Some((u32::from(info.width), u32::from(info.height), rgba))
}

/// An RGBA PNG at 8 bits, stored and unfiltered.
fn encode(width: u32, height: u32, rgba: &[u8]) -> Option<Vec<u8>> {
    let mut out = Vec::with_capacity(rgba.len() + rgba.len() / 1024 + 1024);
    let mut encoder = png::Encoder::new(&mut out, width, height);
    encoder.set_color(png::ColorType::Rgba);
    encoder.set_depth(png::BitDepth::Eight);
    encoder.set_deflate_compression(png::DeflateCompression::NoCompression);
    encoder.set_filter(png::Filter::NoFilter);
    let mut writer = encoder.write_header().ok()?;
    writer.write_image_data(rgba).ok()?;
    writer.finish().ok()?;
    Some(out)
}
