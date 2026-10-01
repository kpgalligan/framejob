//! The bundle this proxy lives in, and the catalog snapshot the build wrote
//! into it (road map 14's MC1 q1: `-RCWriteCatalog` in the "Write Agent
//! Catalog" build phase). A proxy launches only its OWN bundle (MC-4), so a
//! copy of Reelcut launches itself and never another copy.

use std::path::{Path, PathBuf};

use serde_json::Value;

/// Where the build puts the snapshot, relative to the bundle.
pub const SNAPSHOT_RELATIVE: &str = "Contents/Resources/agent-catalog.json";

/// `{version, tools}`: the bundle's short version and its `tools/list`
/// catalog as the app would answer it.
#[derive(Debug, Clone, PartialEq)]
pub struct Snapshot {
    pub version: String,
    pub tools: Value,
}

/// The `.app` that holds this executable as `Contents/Helpers/<name>`,
/// symlinks resolved; anything else is an error naming the executable.
pub fn own_bundle() -> Result<PathBuf, String> {
    let exe = std::env::current_exe()
        .map_err(|e| format!("reelcut-mcp cannot find its own executable: {e}"))?;
    let exe = exe
        .canonicalize()
        .map_err(|e| format!("reelcut-mcp cannot resolve {}: {e}", exe.display()))?;
    let outside = || {
        format!(
            "reelcut-mcp is not inside a Reelcut bundle: {} is not <X>.app/Contents/Helpers/<name>, \
             so there is no Reelcut to launch",
            exe.display()
        )
    };
    let helpers = exe.parent().ok_or_else(outside)?;
    let contents = helpers.parent().ok_or_else(outside)?;
    let app = contents.parent().ok_or_else(outside)?;
    let named = |path: &Path, name: &str| path.file_name().is_some_and(|n| n == name);
    if !named(helpers, "Helpers")
        || !named(contents, "Contents")
        || app.extension().is_none_or(|ext| ext != "app")
    {
        return Err(outside());
    }
    Ok(app.to_path_buf())
}

/// Reads and checks `<bundle>/Contents/Resources/agent-catalog.json`.
pub fn read_snapshot(bundle: &Path) -> Result<Snapshot, String> {
    let path = bundle.join(SNAPSHOT_RELATIVE);
    let shown = path.display();
    let bytes = std::fs::read(&path).map_err(|e| format!("could not read {shown}: {e}"))?;
    let mut value: Value =
        serde_json::from_slice(&bytes).map_err(|e| format!("{shown} is not JSON: {e}"))?;
    let version = value
        .get("version")
        .and_then(Value::as_str)
        .ok_or_else(|| format!("{shown} has no string `version`"))?
        .to_string();
    let tools = value
        .get_mut("tools")
        .filter(|tools| tools.is_array())
        .map(Value::take)
        .ok_or_else(|| format!("{shown} has no array `tools`"))?;
    Ok(Snapshot { version, tools })
}
