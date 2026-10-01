//! C FFI for the embedded MCP agent server (`rc_agent_*` in the header).
//!
//! Two listeners, each one per process in its own slot: the TCP server
//! (`rc_agent_server_start` / `_stop`, `SERVER`) and the Unix socket
//! (`rc_agent_socket_start` / `_release`, `SOCKET`, road map 14). A second
//! start of either is refused. Both are built from the same
//! [`AgentConfig`] (`host_config`), so they serve one catalog through one
//! handler. The host's tool handler is a C function pointer invoked from
//! either server thread; its return value must come from
//! [`rc_agent_string_create`] so this side can reclaim the allocation.

use std::ffi::{c_char, c_void, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::Path;
use std::ptr;
use std::sync::Mutex;

use crate::agent::{self, AgentConfig, AgentServer};
use crate::ffi_util::{fallible_op, read_cstr};

/// C signature of the host tool handler. See the header for the contract.
pub type RcAgentToolHandler = unsafe extern "C" fn(
    context: *mut c_void,
    tool_name: *const c_char,
    arguments_json: *const c_char,
) -> *mut c_char;

/// The handler pointer and its context, made Send+Sync so a worker
/// thread may call them. The host guarantees the pair stays valid and
/// callable from any thread for the life of the server it was
/// registered with.
pub(crate) struct HostHandler {
    pub(crate) handler: RcAgentToolHandler,
    pub(crate) context: *mut c_void,
}
unsafe impl Send for HostHandler {}
unsafe impl Sync for HostHandler {}

impl HostHandler {
    pub(crate) fn call(&self, name: &str, arguments: &str) -> Option<String> {
        let name = CString::new(name.replace('\0', " ")).ok()?;
        let arguments = CString::new(arguments.replace('\0', " ")).ok()?;
        let raw = unsafe { (self.handler)(self.context, name.as_ptr(), arguments.as_ptr()) };
        if raw.is_null() {
            return None;
        }
        // Reclaims the rc_agent_string_create allocation.
        let owned = unsafe { CString::from_raw(raw) };
        owned.into_string().ok()
    }
}

static SERVER: Mutex<Option<AgentServer>> = Mutex::new(None);
static SOCKET: Mutex<Option<AgentServer>> = Mutex::new(None);

/// Reads the three strings both starts take and builds the
/// [`AgentConfig`] around the host's handler: the one place the catalog is
/// parsed and the handler wrapped, so the two listeners cannot differ.
///
/// # Safety
/// String arguments must be NULL or valid NUL-terminated C strings.
unsafe fn host_config(
    server_name: *const c_char,
    server_version: *const c_char,
    tools_json: *const c_char,
    handler: RcAgentToolHandler,
    context: *mut c_void,
) -> Result<AgentConfig, String> {
    let name = unsafe { read_cstr(server_name, "server_name") }?;
    let version = unsafe { read_cstr(server_version, "server_version") }?;
    let tools_text = unsafe { read_cstr(tools_json, "tools_json") }?;
    let tools: serde_json::Value = serde_json::from_str(&tools_text)
        .map_err(|e| format!("tools_json is not valid JSON: {e}"))?;
    let host = HostHandler { handler, context };
    Ok(AgentConfig {
        name,
        version,
        tools,
        handler: Box::new(move |tool, arguments| host.call(tool, arguments)),
    })
}

/// Allocates a NUL-terminated copy of `s` owned by this library, for tool
/// handlers to return. Never freed by the caller: ownership passes back
/// across the handler return.
///
/// # Safety
/// `s` must be NULL or a valid NUL-terminated C string.
#[no_mangle]
pub unsafe extern "C" fn rc_agent_string_create(s: *const c_char) -> *mut c_char {
    if s.is_null() {
        return ptr::null_mut();
    }
    let bytes = unsafe { CStr::from_ptr(s) }.to_bytes().to_vec();
    match CString::new(bytes) {
        Ok(owned) => owned.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Starts the embedded MCP server on 127.0.0.1 (`port` 0 picks an
/// ephemeral port) and returns the bound port, or 0 on failure with a
/// message through `err_out`. `tools_json` must be the `tools/list`
/// catalog as a JSON array. `handler` is called from the server thread
/// for every `tools/call`; it must return a CallToolResult JSON object
/// allocated with [`rc_agent_string_create`], or NULL for handler failure.
///
/// # Safety
/// String arguments must be valid NUL-terminated C strings; `err_out`
/// must be NULL or a valid pointer to writable `*mut c_char`; `handler`
/// and `context` must remain valid and callable from any thread until
/// `rc_agent_server_stop` returns.
#[no_mangle]
pub unsafe extern "C" fn rc_agent_server_start(
    port: u16,
    server_name: *const c_char,
    server_version: *const c_char,
    tools_json: *const c_char,
    handler: RcAgentToolHandler,
    context: *mut c_void,
    err_out: *mut *mut c_char,
) -> u16 {
    let body = || {
        let config =
            unsafe { host_config(server_name, server_version, tools_json, handler, context) }?;

        let mut slot = SERVER
            .lock()
            .map_err(|_| "server lock poisoned".to_string())?;
        if slot.is_some() {
            return Err("agent server already running".to_string());
        }
        let (bound, server) = agent::start(port, config)?;
        *slot = Some(server);
        Ok(bound)
    };
    unsafe {
        fallible_op(
            err_out,
            "panic while starting agent server",
            0,
            body,
            |bound| bound,
        )
    }
}

/// Stops the embedded MCP server and waits for its thread to exit. Safe
/// to call when no server is running. After this returns, the handler
/// and context passed to start are no longer used.
#[no_mangle]
pub extern "C" fn rc_agent_server_stop() {
    let server = catch_unwind(|| SERVER.lock().ok().and_then(|mut slot| slot.take()));
    if let Ok(Some(server)) = server {
        let _ = catch_unwind(AssertUnwindSafe(|| server.shutdown()));
    }
}

/// Binds the embedded MCP server's Unix-socket listener at `socket_path` —
/// a second server object beside the TCP one, with the same catalog and
/// handler contract — chmod 0600. True, or false with a message through
/// `err_out`. One per process: a second start is an error ("agent socket
/// already bound"). Never unlinks an existing file.
///
/// # Safety
/// String arguments must be valid NUL-terminated C strings; `err_out`
/// must be NULL or a valid pointer to writable `*mut c_char`; `handler`
/// and `context` must remain valid and callable from any thread for the
/// life of the process, because [`rc_agent_socket_release`] never joins.
#[no_mangle]
pub unsafe extern "C" fn rc_agent_socket_start(
    socket_path: *const c_char,
    server_name: *const c_char,
    server_version: *const c_char,
    tools_json: *const c_char,
    handler: RcAgentToolHandler,
    context: *mut c_void,
    err_out: *mut *mut c_char,
) -> bool {
    let body = || {
        let path = unsafe { read_cstr(socket_path, "socket_path") }?;
        let config =
            unsafe { host_config(server_name, server_version, tools_json, handler, context) }?;

        let mut slot = SOCKET
            .lock()
            .map_err(|_| "socket lock poisoned".to_string())?;
        if slot.is_some() {
            return Err("agent socket already bound".to_string());
        }
        let server = agent::start_socket(Path::new(&path), config)?;
        *slot = Some(server);
        Ok(())
    };
    unsafe {
        fallible_op(
            err_out,
            "panic while binding agent socket",
            false,
            body,
            |()| true,
        )
    }
}

/// For quit. Takes the listener out of its slot and unlinks the socket
/// file only if it is still the one this listener bound (same device and
/// inode), then abandons the listener: its thread is neither unblocked nor
/// joined, so a call in flight cannot hold the quit, and process exit ends
/// it. `handler` and `context` must stay valid for the life of the process.
/// Safe when none is bound.
#[no_mangle]
pub extern "C" fn rc_agent_socket_release() {
    let server = catch_unwind(|| SOCKET.lock().ok().and_then(|mut slot| slot.take()));
    if let Ok(Some(server)) = server {
        let _ = catch_unwind(AssertUnwindSafe(|| server.release()));
    }
}
