//! Road map 10 §5b's Diagnostic: `{level, message, line, column, frame}`.

/// How bad a diagnostic is: a warning draws anyway, an error draws nothing.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Level {
    Warning,
    Error,
}

impl Level {
    pub fn as_str(self) -> &'static str {
        match self {
            Level::Warning => "warning",
            Level::Error => "error",
        }
    }
}

/// One message about a graphic, with where it happened when that is known.
#[derive(Debug, Clone, PartialEq)]
pub struct Diagnostic {
    pub level: Level,
    pub message: String,
    pub line: Option<u32>,
    pub column: Option<u32>,
    pub frame: Option<i64>,
}

impl Diagnostic {
    pub fn error(message: impl Into<String>) -> Diagnostic {
        Diagnostic::at(Level::Error, message.into())
    }

    pub fn warning(message: impl Into<String>) -> Diagnostic {
        Diagnostic::at(Level::Warning, message.into())
    }

    fn at(level: Level, message: String) -> Diagnostic {
        Diagnostic {
            level,
            message,
            line: None,
            column: None,
            frame: None,
        }
    }

    /// `{"level","message","line","column","frame"}` in that order; an
    /// absent position is `null`.
    pub fn to_json(&self) -> serde_json::Value {
        serde_json::json!({
            "level": self.level.as_str(),
            "message": self.message,
            "line": self.line,
            "column": self.column,
            "frame": self.frame,
        })
    }
}
