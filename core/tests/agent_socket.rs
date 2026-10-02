//! The agent server's Unix-socket listener (road map 14's MC2): binding,
//! the 0600 mode, the path limits, never binding over a live socket, and MC1's S7 — a listener
//! whose file was unlinked and re-bound by another must not delete the new
//! one, whether it is shut down or released. The last test drives the FFI
//! pair; it is the only test that touches the process's socket slot.
//!
//! Each test makes its own folder, `rcs-<pid>-<n>`, under the temp dir, so
//! the paths stay well inside macOS's 103-byte budget and no two tests (or
//! two runs) share one.

mod common;

use std::ffi::{c_char, c_void};
use std::io::{Read, Write};
use std::os::unix::fs::{FileTypeExt, MetadataExt, PermissionsExt};
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::ptr;
use std::sync::atomic::{AtomicUsize, Ordering};

use serde_json::{json, Value};

use common::{cstring, take_string};
use reelcut_core::agent::{self, AgentConfig, MAX_SOCKET_PATH_BYTES};
use reelcut_core::ffi_agent::{
    rc_agent_socket_release, rc_agent_socket_start, rc_agent_string_create,
};

static NEXT: AtomicUsize = AtomicUsize::new(0);

/// A fresh folder of this test's own; removed by the caller's `Folder` drop.
struct Folder(PathBuf);

impl Folder {
    fn new() -> Folder {
        let n = NEXT.fetch_add(1, Ordering::SeqCst);
        let dir = std::env::temp_dir().join(format!("rcs-{}-{n}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("the test folder is made");
        Folder(dir)
    }

    fn sock(&self) -> PathBuf {
        self.0.join("agent.sock")
    }
}

impl Drop for Folder {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn tools() -> Value {
    json!([
        {"name": "zeta", "description": "last", "inputSchema": {"type": "object",
            "properties": {"z": {"type": "string"}, "a": {"type": "integer"}}}},
        {"name": "alpha", "description": "first", "inputSchema": {"type": "object"}}
    ])
}

fn config() -> AgentConfig {
    AgentConfig {
        name: "reelcut-test".to_string(),
        version: "9.9.9".to_string(),
        tools: tools(),
        handler: Box::new(|_, _| Some(r#"{"content":[],"isError":false}"#.to_string())),
    }
}

/// One HTTP POST of `body` over `stream`, answered as (status line, body).
fn post_over(mut stream: impl Read + Write, body: &str) -> (String, String) {
    let request = format!(
        "POST /mcp HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\n\
         Accept: application/json, text/event-stream\r\nContent-Length: {}\r\n\
         Connection: close\r\n\r\n{body}",
        body.len()
    );
    stream
        .write_all(request.as_bytes())
        .expect("the request is written");
    let mut raw = Vec::new();
    stream.read_to_end(&mut raw).expect("the response is read");
    let text = String::from_utf8(raw).expect("the response is UTF-8");
    let (head, rest) = text
        .split_once("\r\n\r\n")
        .expect("the response has a head");
    let status = head.lines().next().unwrap_or("").to_string();
    (status, rest.to_string())
}

fn post_unix(path: &Path, body: &str) -> (String, String) {
    post_over(UnixStream::connect(path).expect("the socket accepts"), body)
}

const INITIALIZE: &str =
    r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#;

fn answers(path: &Path) -> bool {
    let (status, body) = post_unix(path, INITIALIZE);
    let value: Value = serde_json::from_str(&body).expect("initialize answers JSON");
    status.contains(" 200 ") && value["result"]["serverInfo"]["name"] == "reelcut-test"
}

fn ino(path: &Path) -> u64 {
    std::fs::symlink_metadata(path)
        .expect("the file is there")
        .ino()
}

#[test]
fn binds_at_0600_and_answers_initialize_over_the_socket() {
    let folder = Folder::new();
    let path = folder.sock();
    let server = agent::start_socket(&path, config()).expect("the socket binds");
    let meta = std::fs::symlink_metadata(&path).expect("the socket file exists");
    assert!(meta.file_type().is_socket(), "the file is a socket");
    assert_eq!(meta.permissions().mode() & 0o777, 0o600);
    let (status, body) = post_unix(&path, INITIALIZE);
    assert!(status.contains(" 200 "), "{status}");
    let value: Value = serde_json::from_str(&body).expect("JSON");
    assert_eq!(value["result"]["serverInfo"]["name"], "reelcut-test");
    assert_eq!(value["result"]["serverInfo"]["version"], "9.9.9");
    server.shutdown();
    assert!(!path.exists(), "its own file is unlinked at shutdown");
}

#[test]
fn a_103_byte_path_binds_and_104_or_relative_is_refused() {
    let folder = Folder::new();
    let base = folder.0.to_str().expect("UTF-8 temp dir").len() + 1;
    assert!(base + 2 < MAX_SOCKET_PATH_BYTES, "the temp dir leaves room");
    let name = |len: usize| folder.0.join("s".repeat(len - base));

    let fits = name(103);
    assert_eq!(fits.as_os_str().len(), 103);
    let server = agent::start_socket(&fits, config()).expect("103 bytes binds");
    assert!(answers(&fits));
    server.shutdown();

    let long = name(104);
    assert_eq!(long.as_os_str().len(), 104);
    let refused = agent::start_socket(&long, config())
        .err()
        .expect("104 bytes is refused");
    assert_eq!(
        refused,
        format!(
            "socket path is 104 bytes; macOS allows 103: {}",
            long.display()
        )
    );
    assert!(!long.exists(), "nothing is made");

    let relative = agent::start_socket(Path::new("agent.sock"), config())
        .err()
        .expect("a relative path is refused");
    assert_eq!(relative, "socket path must be absolute: agent.sock");
}

#[test]
fn a_live_socket_at_the_path_is_refused_and_keeps_answering() {
    let folder = Folder::new();
    let path = folder.sock();
    let first = agent::start_socket(&path, config()).expect("the first binds");
    let before = ino(&path);
    let refused = agent::start_socket(&path, config())
        .err()
        .expect("the second is refused");
    assert!(
        refused.starts_with(&format!("could not bind {}: ", path.display())),
        "{refused}"
    );
    assert_eq!(ino(&path), before, "the file is untouched");
    assert!(answers(&path), "the first still answers");
    first.shutdown();
}

/// A bound, its file unlinked, B bound at the same path: the S7 setup.
fn a_then_b(path: &Path) -> (agent::AgentServer, agent::AgentServer, u64) {
    let a = agent::start_socket(path, config()).expect("A binds");
    std::fs::remove_file(path).expect("A's file is unlinked");
    let b = agent::start_socket(path, config()).expect("B binds over the gap");
    let b_ino = ino(path);
    (a, b, b_ino)
}

#[test]
fn shutting_down_a_listener_whose_file_was_replaced_leaves_the_new_one() {
    let folder = Folder::new();
    let path = folder.sock();
    let (a, b, b_ino) = a_then_b(&path);
    a.shutdown();
    assert_eq!(ino(&path), b_ino, "B's file keeps its inode");
    assert!(answers(&path), "B still answers");
    b.shutdown();
    assert!(!path.exists(), "B's shutdown unlinks its own file");
}

#[test]
fn releasing_a_listener_whose_file_was_replaced_leaves_the_new_one() {
    let folder = Folder::new();
    let path = folder.sock();
    let (a, b, b_ino) = a_then_b(&path);
    a.release();
    assert_eq!(ino(&path), b_ino, "B's file keeps its inode");
    assert!(answers(&path), "B still answers");
    b.release();
    assert!(!path.exists(), "B's release unlinks its own file");
}

unsafe extern "C" fn echo_handler(
    _context: *mut c_void,
    _tool_name: *const c_char,
    _arguments_json: *const c_char,
) -> *mut c_char {
    let result = cstring(r#"{"content":[],"isError":false}"#);
    unsafe { rc_agent_string_create(result.as_ptr()) }
}

/// The only test that touches the FFI's socket slot.
#[test]
fn the_ffi_pair_binds_once_and_releases_its_file() {
    let folder = Folder::new();
    let path = folder.sock();
    let path_c = cstring(path.to_str().expect("UTF-8 path"));
    let name = cstring("reelcut-test");
    let version = cstring("9.9.9");
    let catalog = cstring(&tools().to_string());
    let start = || {
        let mut err: *mut c_char = ptr::null_mut();
        let ok = unsafe {
            rc_agent_socket_start(
                path_c.as_ptr(),
                name.as_ptr(),
                version.as_ptr(),
                catalog.as_ptr(),
                echo_handler,
                ptr::null_mut(),
                &mut err,
            )
        };
        (ok, take_string(err))
    };

    assert_eq!(start(), (true, None));
    assert!(answers(&path));
    assert_eq!(
        start(),
        (false, Some("agent socket already bound".to_string()))
    );
    assert!(answers(&path), "the refused second start left the first");

    rc_agent_socket_release();
    assert!(!path.exists(), "release unlinks the file it bound");
    rc_agent_socket_release();

    assert_eq!(start(), (true, None), "the slot is free again");
    assert!(answers(&path));
    rc_agent_socket_release();
    assert!(!path.exists());
}
