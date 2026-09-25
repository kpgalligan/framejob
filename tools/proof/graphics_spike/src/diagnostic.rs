//! §5b's Diagnostic, and how a QuickJS exception becomes one: the message,
//! and a line and column read from `stack` (rquickjs 0.14's `Exception` has
//! no `line()`/`column()`).

use std::time::Duration;

use rquickjs::Value;

/// §5b's `{level, message, line, column, frame}`.
#[derive(Debug, Clone)]
pub struct Diagnostic {
    pub level: String,
    pub message: String,
    pub line: Option<u32>,
    pub column: Option<u32>,
    pub frame: Option<i64>,
}

impl Diagnostic {
    pub fn error(message: impl Into<String>) -> Diagnostic {
        Diagnostic {
            level: "error".into(),
            message: message.into(),
            line: None,
            column: None,
            frame: None,
        }
    }

    pub fn to_json(&self) -> serde_json::Value {
        serde_json::json!({
            "level": self.level, "message": self.message,
            "line": self.line, "column": self.column, "frame": self.frame,
        })
    }
}

pub(crate) fn returned_svg(value: Value, frame: i64) -> Result<String, Diagnostic> {
    let mut d = if let Some(text) = value.as_string() {
        let text = match text.to_string() {
            Ok(text) => text,
            Err(e) => {
                let mut d = Diagnostic::error(format!(
                    "render's string could not be read at frame {frame}: {e}"
                ));
                d.frame = Some(frame);
                return Err(d);
            }
        };
        if text.starts_with("<svg") {
            return Ok(text);
        }
        let head: String = text.chars().take(40).collect();
        Diagnostic::error(format!(
            "render returned a string that does not start with <svg at frame {frame}: {head:?}"
        ))
    } else if value.is_undefined() {
        Diagnostic::error(format!(
            "render returned undefined at frame {frame} — did you forget `return`?"
        ))
    } else {
        Diagnostic::error(format!(
            "render returned {} at frame {frame}; it must return an SVG string",
            value.type_name()
        ))
    };
    d.frame = Some(frame);
    Err(d)
}

pub(crate) fn budgeted(mut d: Diagnostic, expired: bool, budget: Duration) -> Diagnostic {
    if expired {
        let at = d
            .frame
            .map(|f| format!(" at frame {f}"))
            .unwrap_or_default();
        d.message = format!(
            "over the {} ms budget{at} ({})",
            budget.as_millis(),
            d.message
        );
    }
    d
}

/// The pending exception as a Diagnostic; line and column from `stack`,
/// preferring a frame in `name` (quickjs-ng: "    at render (name:L:C)").
pub(crate) fn diagnose(
    ctx: &rquickjs::Ctx<'_>,
    error: rquickjs::Error,
    name: &str,
    frame: Option<i64>,
) -> Diagnostic {
    let mut d = Diagnostic::error(error.to_string());
    d.frame = frame;
    if !matches!(error, rquickjs::Error::Exception) {
        return d;
    }
    let caught = ctx.catch();
    let mut stack = None;
    if let Some(exception) = caught.as_exception() {
        let kind: Option<String> = exception.get("name").ok();
        let message = exception.message().unwrap_or_default();
        d.message = match kind {
            Some(kind) if !kind.is_empty() => format!("{kind}: {message}"),
            _ => message,
        };
        stack = exception.stack();
    } else if let Some(text) = caught.as_string().and_then(|s| s.to_string().ok()) {
        d.message = text;
    } else {
        d.message = format!("threw {}", caught.type_name());
    }
    if let Some((line, column)) = stack.as_deref().and_then(|s| position(s, name)) {
        d.line = Some(line);
        d.column = Some(column);
    }
    d
}

fn position(stack: &str, name: &str) -> Option<(u32, u32)> {
    let mut first = None;
    for line in stack.lines() {
        let trimmed = line.trim().trim_end_matches(')');
        let mut parts = trimmed.rsplitn(3, ':');
        let (Some(col), Some(row), Some(rest)) = (parts.next(), parts.next(), parts.next()) else {
            continue;
        };
        let (Ok(col), Ok(row)) = (col.parse::<u32>(), row.parse::<u32>()) else {
            continue;
        };
        if rest.ends_with(name) {
            return Some((row, col));
        }
        first.get_or_insert((row, col));
    }
    first
}
