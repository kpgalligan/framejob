//! The Library: the font set and the asset map a graphic draws with, built
//! from bytes the caller read (G-2, G-6 — never `load_system_fonts`), its
//! content version, the `measure_text` memo, and the usvg options every
//! parse shares, whose resolvers record what resvg itself never reports.

use std::collections::{BTreeMap, HashMap};
use std::sync::{Arc, Mutex, MutexGuard};

use resvg::usvg;
use resvg::usvg::fontdb;
use sha2::{Digest, Sha256};

use crate::diagnostic::Diagnostic;
use crate::measure::{FontStyle, TextMetrics};

/// `(family, size bits, weight, style, letter-spacing bits, text)`.
pub(crate) type MemoKey = (String, u64, u16, FontStyle, u64, String);

/// The memo is cleared when it reaches this many entries.
const MEMO_CAP: usize = 4096;

/// The engine's fonts and assets. Immutable once built; `Send + Sync`.
pub struct Library {
    db: Arc<fontdb::Database>,
    assets: BTreeMap<String, Arc<Vec<u8>>>,
    families: Vec<String>,
    version: String,
    warnings: Vec<Diagnostic>,
    memo: Mutex<HashMap<MemoKey, TextMetrics>>,
}

/// One loaded face.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Face {
    pub family: String,
    pub post_script_name: String,
    pub weight: u16,
    pub italic: bool,
}

/// What one parse's resolvers saw: the family lists no face answered, the
/// hrefs that name no asset, whether a data: URL was met, and the assets
/// that are not images.
#[derive(Default)]
pub(crate) struct Probe {
    pub(crate) families: Vec<Vec<usvg::FontFamily>>,
    pub(crate) hrefs: Vec<String>,
    pub(crate) data_url: bool,
    pub(crate) bad_assets: Vec<String>,
}

/// Every closure takes the lock only for its own push: a nested SVG asset
/// re-enters `select_font` on the same thread, and the lock is not
/// re-entrant.
pub(crate) fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

impl Library {
    pub fn new(fonts: Vec<Vec<u8>>, assets: BTreeMap<String, Vec<u8>>) -> Library {
        let version = version_of(&fonts, &assets);
        let mut db = fontdb::Database::new();
        let mut warnings = Vec::new();
        for (index, bytes) in fonts.into_iter().enumerate() {
            let before = db.len();
            db.load_font_data(bytes);
            if db.len() == before {
                warnings.push(Diagnostic::warning(format!("font {index} loaded no face")));
            }
        }
        let mut families: Vec<String> = db
            .faces()
            .filter_map(|face| face.families.first().map(|(name, _)| name.clone()))
            .collect();
        families.sort();
        families.dedup();
        Library {
            db: Arc::new(db),
            assets: assets
                .into_iter()
                .map(|(name, data)| (name, Arc::new(data)))
                .collect(),
            families,
            version,
            warnings,
            memo: Mutex::new(HashMap::new()),
        }
    }

    /// Primary family names, sorted and deduplicated.
    pub fn families(&self) -> &[String] {
        &self.families
    }

    pub fn faces(&self) -> Vec<Face> {
        self.db
            .faces()
            .map(|face| Face {
                family: face
                    .families
                    .first()
                    .map(|(name, _)| name.clone())
                    .unwrap_or_default(),
                post_script_name: face.post_script_name.clone(),
                weight: face.weight.0,
                italic: face.style != fontdb::Style::Normal,
            })
            .collect()
    }

    pub fn asset_names(&self) -> Vec<&str> {
        self.assets.keys().map(String::as_str).collect()
    }

    pub fn asset(&self, name: &str) -> Option<&[u8]> {
        self.assets.get(name).map(|data| data.as_slice())
    }

    /// SHA-256 of the font and asset bytes, 64 lowercase hex characters.
    pub fn version(&self) -> &str {
        &self.version
    }

    /// One per font blob that loaded no face.
    pub fn warnings(&self) -> &[Diagnostic] {
        &self.warnings
    }

    pub(crate) fn memo_get(&self, key: &MemoKey) -> Option<TextMetrics> {
        lock(&self.memo).get(key).copied()
    }

    pub(crate) fn memo_put(&self, key: MemoKey, metrics: TextMetrics) {
        let mut memo = lock(&self.memo);
        if memo.len() >= MEMO_CAP {
            memo.clear();
        }
        memo.insert(key, metrics);
    }

    /// The options every parse uses: this font set only, `<image>` hrefs
    /// answered from the asset map only, and every miss recorded in
    /// `probe`. `Options` is not `Clone`, so each call builds its own.
    pub(crate) fn options<'a>(&'a self, probe: &'a Mutex<Probe>) -> usvg::Options<'a> {
        let inner = usvg::FontResolver::default_font_selector();
        let select_font: usvg::FontSelectionFn<'a> = Box::new(move |font, db| {
            let id = inner(font, db);
            if id.is_none() {
                lock(probe).families.push(font.families().to_vec());
            }
            id
        });
        let resolve_data: usvg::ImageHrefDataResolverFn<'a> = Box::new(move |_, _, _| {
            lock(probe).data_url = true;
            None
        });
        let resolve_string: usvg::ImageHrefStringResolverFn<'a> =
            Box::new(move |href, opts| match self.assets.get(href) {
                Some(data) => {
                    let kind = image_kind(data, opts);
                    if kind.is_none() {
                        lock(probe).bad_assets.push(href.to_string());
                    }
                    kind
                }
                None => {
                    lock(probe).hrefs.push(href.to_string());
                    None
                }
            });
        usvg::Options {
            fontdb: self.db.clone(),
            font_resolver: usvg::FontResolver {
                select_font,
                select_fallback: usvg::FontResolver::default_fallback_selector(),
            },
            image_href_resolver: usvg::ImageHrefResolver {
                resolve_data,
                resolve_string,
            },
            ..usvg::Options::default()
        }
    }
}

/// An asset's kind by its magic; anything that is not PNG, JPEG, GIF or
/// WebP is tried as an SVG (gzipped or not), with no lock held.
fn image_kind(data: &Arc<Vec<u8>>, opts: &usvg::Options) -> Option<usvg::ImageKind> {
    let bytes = data.as_slice();
    if bytes.starts_with(&[0x89, 0x50, 0x4E, 0x47]) {
        Some(usvg::ImageKind::PNG(data.clone()))
    } else if bytes.starts_with(&[0xFF, 0xD8, 0xFF]) {
        Some(usvg::ImageKind::JPEG(data.clone()))
    } else if bytes.starts_with(&[0x47, 0x49, 0x46, 0x38]) {
        Some(usvg::ImageKind::GIF(data.clone()))
    } else if bytes.len() >= 12 && &bytes[0..4] == b"RIFF" && &bytes[8..12] == b"WEBP" {
        Some(usvg::ImageKind::WEBP(data.clone()))
    } else {
        usvg::Tree::from_data_nested(bytes, opts)
            .ok()
            .map(usvg::ImageKind::SVG)
    }
}

/// Each font's length (u64 LE) then bytes; then each asset in name order:
/// name length, name, data length, data. The length prefixes keep
/// `{"ab": "c"}` and `{"a": "bc"}` apart.
fn version_of(fonts: &[Vec<u8>], assets: &BTreeMap<String, Vec<u8>>) -> String {
    let mut hash = Sha256::new();
    for font in fonts {
        hash.update((font.len() as u64).to_le_bytes());
        hash.update(font);
    }
    for (name, data) in assets {
        hash.update((name.len() as u64).to_le_bytes());
        hash.update(name.as_bytes());
        hash.update((data.len() as u64).to_le_bytes());
        hash.update(data);
    }
    hash.finalize()
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}
