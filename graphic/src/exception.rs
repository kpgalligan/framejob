//! How a QuickJS failure becomes a Diagnostic (road map 10 §5b): the
//! exception's `{name}: {message}`, a line and column read from its `stack`
//! (rquickjs 0.14's `Exception` has no `line()`/`column()`), the budget's
//! sentence around an interrupted call, and what `render` returned.

use rquickjs::Value;

use crate::diagnostic::Diagnostic;

/// The pending exception of `e` as a Diagnostic; line and column from
/// `stack`, preferring a frame in the module `name`.
pub(crate) fn diagnose(
    ctx: &rquickjs::Ctx<'_>,
    e: rquickjs::Error,
    name: &str,
    frame: Option<i64>,
) -> Diagnostic {
    let mut d = Diagnostic::error(e.to_string());
    d.frame = frame;
    if !matches!(e, rquickjs::Error::Exception) {
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

/// The `L:C` of the first stack frame whose file ends with `name`, else of
/// the first frame (quickjs-ng writes `    at render (<name>:L:C)`; the
/// standard library and the sandbox are `eval_script`).
pub(crate) fn position(stack: &str, name: &str) -> Option<(u32, u32)> {
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

/// `d` in the budget's words when the call's deadline had passed. An
/// interrupt's position is the function's, and the sentence says so.
pub(crate) fn budgeted(mut d: Diagnostic, expired: bool, budget_ms: u64) -> Diagnostic {
    if !expired {
        return d;
    }
    d.message = match (d.frame, d.line, d.column) {
        (None, _, _) => format!("over the {budget_ms} ms budget while loading ({})", d.message),
        (Some(f), Some(l), Some(c)) => format!(
            "over the {budget_ms} ms budget at frame {f} ({}); {l}:{c} is where the function begins, not the statement that ran long",
            d.message
        ),
        (Some(f), _, _) => format!("over the {budget_ms} ms budget at frame {f} ({})", d.message),
    };
    d
}

/// The SVG text `render` returned at `frame`, or the sentence naming what
/// came back instead.
pub(crate) fn returned_svg(value: Value<'_>, frame: i64) -> Result<String, Diagnostic> {
    let message = if let Some(text) = value.as_string() {
        match text.to_string() {
            Ok(text) if text.starts_with("<svg") => return Ok(text),
            Ok(text) => {
                let head: String = text.chars().take(40).collect();
                format!(
                    "render returned a string that does not start with <svg at frame {frame}: {head:?}"
                )
            }
            Err(_) => format!(
                "render's string could not be read at frame {frame} — is it tens of megabytes?"
            ),
        }
    } else if value.is_undefined() {
        format!("render returned undefined at frame {frame} — did you forget `return`?")
    } else {
        // rquickjs names numbers `int` and `float`; an author knows `number`.
        let kind = match value.type_name() {
            "int" | "float" => "number",
            "bool" => "boolean",
            other => other,
        };
        format!("render returned {kind} at frame {frame}; it must return an SVG string")
    };
    let mut d = Diagnostic::error(message);
    d.frame = Some(frame);
    Err(d)
}
