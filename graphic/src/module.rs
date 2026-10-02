//! A graphic's module, compiled once (road map 10 §5c): its source, its
//! revision (G-13), the `meta` and `schema` it exported, read out as
//! JSON in the module's own key order, and the warnings its top level
//! raised while compiling (G-21 (b)). A `Module` holds no QuickJS object,
//! so it is `Send + Sync`; each thread that draws it keeps its own engine.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

use sha2::{Digest, Sha256};

use crate::diagnostic::Diagnostic;
use crate::library::Library;
use crate::props::{check_schema, colour_defaults, overlay};
use crate::runtime::{adopt, Engine};

static NEXT_ID: AtomicU64 = AtomicU64::new(1);

/// A compiled graphic module. Cloning it is cheap; the engines drawing it
/// are swept once every clone has been dropped.
#[derive(Clone)]
pub struct Module {
    inner: Arc<Inner>,
}

pub(crate) struct Inner {
    pub(crate) id: u64,
    name: String,
    source: String,
    revision: String,
    meta: serde_json::Value,
    schema: serde_json::Value,
    library: Arc<Library>,
    warnings: Vec<Diagnostic>,
}

impl Module {
    /// Evaluates `source` as the ES module `name` on the calling thread,
    /// under a deadline of `budget_ms`, and checks what it exports: a
    /// `render` function, a `meta` object and a well-formed `schema`.
    pub fn compile(
        library: Arc<Library>,
        name: &str,
        source: &str,
        budget_ms: u64,
    ) -> Result<Module, Diagnostic> {
        let revision: String = Sha256::digest(source.as_bytes())
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect();
        let mut engine = Engine::new(&library)?;
        let exports = engine.load(name, source, budget_ms)?;
        let texts = colour_defaults(&exports.schema);
        let ok = engine.parse_colours(&texts, budget_ms);
        check_schema(&exports.schema, &|t| {
            texts.iter().zip(&ok).any(|(s, k)| *k && s == t)
        })?;
        if !exports.meta.is_object() {
            return Err(Diagnostic::error("meta must be an object"));
        }
        let inner = Arc::new(Inner {
            id: NEXT_ID.fetch_add(1, Ordering::Relaxed),
            name: name.to_string(),
            source: source.to_string(),
            revision,
            meta: exports.meta,
            schema: exports.schema,
            library,
            warnings: exports
                .warnings
                .into_iter()
                .map(Diagnostic::warning)
                .collect(),
        });
        adopt(&inner, engine);
        Ok(Module { inner })
    }

    pub(crate) fn inner(&self) -> &Arc<Inner> {
        &self.inner
    }

    pub fn name(&self) -> &str {
        &self.inner.name
    }

    pub fn source(&self) -> &str {
        &self.inner.source
    }

    /// SHA-256 of the source's bytes, 64 lowercase hex digits (G-13).
    pub fn revision(&self) -> &str {
        &self.inner.revision
    }

    /// The exported `meta`, `{}` when there is none.
    pub fn meta(&self) -> &serde_json::Value {
        &self.inner.meta
    }

    /// The exported `schema`, `{}` when there is none.
    pub fn schema(&self) -> &serde_json::Value {
        &self.inner.schema
    }

    /// The warnings the module's top level raised while compiling, in
    /// order. Each has `Level::Warning` and `frame`, `line` and `column`
    /// set to None (spec §11 G-21 (b)).
    pub fn warnings(&self) -> &[Diagnostic] {
        &self.inner.warnings
    }

    pub fn library(&self) -> &Arc<Library> {
        &self.inner.library
    }

    /// The schema's defaults, key by key.
    pub fn defaults(&self) -> serde_json::Value {
        overlay(&self.inner.schema, &serde_json::json!({})).0
    }
}
