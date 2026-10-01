//! Embedded MCP server: the streamable-HTTP transport and JSON-RPC layer
//! for the app's agent integration (tools only — no resources, prompts,
//! or server-initiated streams). The protocol lives here; executing a tool
//! is delegated to the host application through the handler installed at
//! start, so this module stays generic: it knows the catalog it was given
//! and nothing about documents.
//!
//! Transport notes: two listeners speak the same HTTP through the same
//! `serve` loop. [`start`] binds TCP on 127.0.0.1 only; [`start_socket`]
//! binds a Unix socket at a path (road map 14, spec §11 MC-1), chmod 0600,
//! never unlinking a file already there. Either answers every JSON-RPC POST
//! with a single `application/json` response (the streamable-HTTP spec
//! allows this in place of an SSE stream). Stateless — no session IDs are
//! issued, and GET/DELETE report 405 as the spec directs for servers
//! without server-push or client-terminated sessions.
//!
//! **A socket listener never lets `tiny_http`'s `Drop` run against a file
//! that is no longer its own** (road map 14's MC1, S7): 0.12's `Server`
//! drop connects to its path and unlinks it unconditionally, so a listener
//! whose file was unlinked and re-bound by another instance would delete
//! that instance's socket. The listener records the file's device and inode
//! when it binds ([`SocketClaim`]); [`AgentServer::shutdown`] lets the drop
//! run only while the file is still that one, and [`AgentServer::release`]
//! unlinks it only then and abandons the listener without a join.

use std::io::Read;
use std::net::{Ipv4Addr, SocketAddrV4};
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::thread::JoinHandle;

use serde_json::{json, Value};

/// Executes one tool call: (tool name, arguments JSON) -> CallToolResult
/// JSON (`{"content": [...], "isError": bool}`). None means the handler
/// itself failed (as opposed to the tool reporting an error result).
pub type ToolHandler = Box<dyn Fn(&str, &str) -> Option<String> + Send + Sync>;

pub struct AgentConfig {
    pub name: String,
    pub version: String,
    /// The `tools/list` catalog, pre-validated to be a JSON array.
    pub tools: Value,
    pub handler: ToolHandler,
}

/// macOS's `sun_path` holds 104 bytes with the terminating NUL, so a socket
/// path may be 103 bytes long (MC1's S1: 103 binds, 104 does not).
pub const MAX_SOCKET_PATH_BYTES: usize = 103;

/// The socket file a listener bound, by the device and inode `lstat` read
/// straight after the bind: what "still this listener's file" means.
pub struct SocketClaim {
    path: PathBuf,
    dev: u64,
    ino: u64,
}

impl SocketClaim {
    /// True while `lstat(path)` answers the device and inode the bind left
    /// there. A file unlinked, or replaced by another listener's, is not.
    pub fn is_current(&self) -> bool {
        std::fs::symlink_metadata(&self.path)
            .map(|meta| meta.dev() == self.dev && meta.ino() == self.ino)
            .unwrap_or(false)
    }
}

pub struct AgentServer {
    server: Arc<tiny_http::Server>,
    thread: Option<JoinHandle<()>>,
    /// The socket file this listener bound; None for TCP.
    claim: Option<SocketClaim>,
}

impl AgentServer {
    /// Unblocks the accept loop and joins the serving thread. A socket
    /// listener whose file is no longer its own is then forgotten rather
    /// than dropped, so `tiny_http`'s `Drop` neither connects to nor unlinks
    /// another listener's socket (S7); otherwise it drops, which unlinks its
    /// own file.
    pub fn shutdown(mut self) {
        self.server.unblock();
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
        if self.claim.as_ref().is_some_and(|claim| !claim.is_current()) {
            std::mem::forget(self.server);
        }
    }

    /// For quit: unlinks the socket file only if it is still the one this
    /// listener bound, then abandons the listener. Its thread is neither
    /// unblocked nor joined and nothing is dropped, so a call in flight
    /// cannot hold the caller; process exit ends the thread.
    pub fn release(self) {
        if let Some(claim) = &self.claim {
            if claim.is_current() {
                let _ = std::fs::remove_file(&claim.path);
            }
        }
        std::mem::forget(self);
    }
}

const MAX_BODY_BYTES: usize = 8 * 1024 * 1024;

/// Starts the server on 127.0.0.1:`port` (0 picks an ephemeral port) and
/// returns the bound port with the running server.
pub fn start(port: u16, config: AgentConfig) -> Result<(u16, AgentServer), String> {
    if !config.tools.is_array() {
        return Err("tools catalog must be a JSON array".to_string());
    }
    let addr = SocketAddrV4::new(Ipv4Addr::LOCALHOST, port);
    let server = tiny_http::Server::http(addr)
        .map_err(|e| format!("could not bind 127.0.0.1:{port}: {e}"))?;
    let server = Arc::new(server);
    let bound = server
        .server_addr()
        .to_ip()
        .map(|a| a.port())
        .ok_or_else(|| "server bound to a non-IP address".to_string())?;
    let accept = Arc::clone(&server);
    let thread = std::thread::spawn(move || serve(accept, config));
    Ok((
        bound,
        AgentServer {
            server,
            thread: Some(thread),
            claim: None,
        },
    ))
}

/// Binds the server on a Unix socket at `path`, chmod 0600, and returns the
/// running server with its claim on the file. A relative path and one over
/// [`MAX_SOCKET_PATH_BYTES`] are refused by name. An existing file is never
/// unlinked first: `tiny_http` refuses to bind over one (S4–S6), and whether
/// a file at the path is a crash's leftover is the host's to decide (MC-2).
pub fn start_socket(path: &Path, config: AgentConfig) -> Result<AgentServer, String> {
    if !config.tools.is_array() {
        return Err("tools catalog must be a JSON array".to_string());
    }
    let shown = path.display();
    if !path.is_absolute() {
        return Err(format!("socket path must be absolute: {shown}"));
    }
    let n = path.as_os_str().len();
    if n > MAX_SOCKET_PATH_BYTES {
        return Err(format!(
            "socket path is {n} bytes; macOS allows {MAX_SOCKET_PATH_BYTES}: {shown}"
        ));
    }
    let server =
        tiny_http::Server::http_unix(path).map_err(|e| format!("could not bind {shown}: {e}"))?;
    // A fresh bind's file takes the umask (0755 under 022, S3). On failure
    // the server drops here, which unlinks the file this call just made.
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))
        .map_err(|e| format!("could not make {shown} 0600: {e}"))?;
    let meta = match std::fs::symlink_metadata(path) {
        Ok(meta) => meta,
        Err(e) => {
            // Whatever is at the path now may not be this bind's file, so
            // the drop must not unlink it (S7).
            std::mem::forget(server);
            return Err(format!("could not read {shown}: {e}"));
        }
    };
    let claim = SocketClaim {
        path: path.to_path_buf(),
        dev: meta.dev(),
        ino: meta.ino(),
    };
    let server = Arc::new(server);
    let accept = Arc::clone(&server);
    let thread = std::thread::spawn(move || serve(accept, config));
    Ok(AgentServer {
        server,
        thread: Some(thread),
        claim: Some(claim),
    })
}

enum Reply {
    Json(u16, Value),
    Empty(u16),
}

fn serve(server: Arc<tiny_http::Server>, config: AgentConfig) {
    for mut request in server.incoming_requests() {
        // One request at a time: tool calls serialize through the host's
        // main thread anyway, and a panic must not take the loop down.
        let reply = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            handle_request(&mut request, &config)
        }))
        .unwrap_or_else(|_| Reply::Json(500, rpc_error(Value::Null, -32603, "internal error")));
        let _ = match reply {
            Reply::Json(status, body) => request.respond(
                tiny_http::Response::from_string(body.to_string())
                    .with_status_code(status)
                    .with_header(
                        tiny_http::Header::from_bytes(
                            &b"Content-Type"[..],
                            &b"application/json"[..],
                        )
                        .expect("static header"),
                    ),
            ),
            Reply::Empty(status) => {
                request.respond(tiny_http::Response::empty(tiny_http::StatusCode(status)))
            }
        };
    }
}

fn handle_request(request: &mut tiny_http::Request, config: &AgentConfig) -> Reply {
    match request.method() {
        tiny_http::Method::Post => {}
        // No server-initiated SSE stream (GET) and no sessions to delete.
        _ => return Reply::Empty(405),
    }
    if request
        .body_length()
        .is_some_and(|len| len > MAX_BODY_BYTES)
    {
        return Reply::Empty(413);
    }
    let mut body = Vec::new();
    let mut reader = request.as_reader().take(MAX_BODY_BYTES as u64 + 1);
    if reader.read_to_end(&mut body).is_err() || body.len() > MAX_BODY_BYTES {
        return Reply::Empty(413);
    }
    let parsed: Value = match serde_json::from_slice(&body) {
        Ok(v) => v,
        Err(_) => return Reply::Json(400, rpc_error(Value::Null, -32700, "parse error")),
    };
    // A batch (2025-03-26 revision) is answered element-wise; notifications
    // produce no entry. All-notification input gets the bodiless 202.
    let replies: Vec<Value> = match parsed {
        Value::Array(items) => items
            .into_iter()
            .filter_map(|m| handle_message(m, config))
            .collect(),
        single => match handle_message(single, config) {
            Some(reply) => return Reply::Json(200, reply),
            None => return Reply::Empty(202),
        },
    };
    if replies.is_empty() {
        Reply::Empty(202)
    } else {
        Reply::Json(200, Value::Array(replies))
    }
}

/// Answers one JSON-RPC message; None for notifications (nothing to say).
fn handle_message(message: Value, config: &AgentConfig) -> Option<Value> {
    let Some(method) = message.get("method").and_then(Value::as_str) else {
        // A response to a server request — we never send any, so ignore.
        return None;
    };
    let id = message.get("id").cloned();
    let params = message.get("params").cloned().unwrap_or(json!({}));
    let Some(id) = id else {
        return None; // notification: nothing is ever returned
    };

    let reply = match method {
        "initialize" => {
            let requested = params
                .get("protocolVersion")
                .and_then(Value::as_str)
                .unwrap_or("");
            let version = crate::mcp_versions::negotiate(requested);
            rpc_result(
                id,
                json!({
                    "protocolVersion": version,
                    "capabilities": {"tools": {}},
                    "serverInfo": {"name": config.name, "version": config.version},
                }),
            )
        }
        "ping" => rpc_result(id, json!({})),
        "tools/list" => rpc_result(id, json!({"tools": config.tools})),
        "tools/call" => {
            let Some(name) = params.get("name").and_then(Value::as_str) else {
                return Some(rpc_error(id, -32602, "tools/call requires a tool name"));
            };
            let arguments = params.get("arguments").cloned().unwrap_or(json!({}));
            let arguments = arguments.to_string();
            match (config.handler)(name, &arguments) {
                None => rpc_error(id, -32603, "tool handler failed"),
                Some(result) => match serde_json::from_str::<Value>(&result) {
                    Ok(value) if value.is_object() => rpc_result(id, value),
                    _ => rpc_error(id, -32603, "tool returned invalid JSON"),
                },
            }
        }
        _ => rpc_error(id, -32601, &format!("method not found: {method}")),
    };
    Some(reply)
}

fn rpc_result(id: Value, result: Value) -> Value {
    json!({"jsonrpc": "2.0", "id": id, "result": result})
}

fn rpc_error(id: Value, code: i64, message: &str) -> Value {
    json!({"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}})
}
