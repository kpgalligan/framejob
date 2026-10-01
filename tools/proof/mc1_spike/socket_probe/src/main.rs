//! Road map 14 MC1, q4: what tiny_http 0.12's `Server::http_unix` does on
//! this host. Every row is a measurement; `mc1_spike.py` scores them.
//!
//!     socket_probe <scratch-dir>   one JSON object of rows S2..S10 on stdout
//!     socket_probe --hold <path>   bind at <path> and block (S5's fixture)
//!
//! Every path it binds is under <scratch-dir>, which the runner makes and
//! removes; nothing here touches the person's support folder.

use std::io::{ErrorKind, Read, Write};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::sync::Arc;
use std::time::{Duration, Instant};

use serde_json::{json, Value};

fn bind(path: &Path) -> Result<tiny_http::Server, String> {
    tiny_http::Server::http_unix(path).map_err(|e| e.to_string())
}

fn exists(path: &Path) -> bool {
    std::fs::symlink_metadata(path).is_ok()
}

fn connect(path: &Path) -> Value {
    match UnixStream::connect(path) {
        Ok(_) => json!({"ok": true}),
        Err(e) => json!({"ok": false, "kind": format!("{:?}", e.kind()), "error": e.to_string()}),
    }
}

/// A path of exactly `len` bytes under `dir`, or None when `dir` is too long.
fn path_of_len(dir: &Path, len: usize) -> Option<PathBuf> {
    let base = dir.as_os_str().len() + 1;
    if len <= base + 1 {
        return None;
    }
    let path = dir.join("s".repeat(len - base));
    (path.as_os_str().len() == len).then_some(path)
}

fn s2(dir: &Path) -> Value {
    let mut out = serde_json::Map::new();
    for len in [103usize, 104, 105] {
        let row = match path_of_len(dir, len) {
            None => json!({"len": len, "ok": false, "error": "scratch dir too long to build the path"}),
            Some(path) => match bind(&path) {
                Ok(server) => {
                    let file = exists(&path);
                    drop(server);
                    json!({"len": len, "ok": true, "error": null, "file": file})
                }
                Err(e) => json!({"len": len, "ok": false, "error": e, "file": exists(&path)}),
            },
        };
        out.insert(len.to_string(), row);
    }
    Value::Object(out)
}

fn s3(dir: &Path) -> Value {
    let path = dir.join("s3.sock");
    match bind(&path) {
        Ok(server) => {
            let mode = std::fs::symlink_metadata(&path)
                .map(|m| format!("{:o}", m.permissions().mode() & 0o7777))
                .unwrap_or_else(|e| format!("stat failed: {e}"));
            let reach = connect(&path);
            drop(server);
            json!({"ok": true, "mode": mode, "connect": reach, "file_after_drop": exists(&path)})
        }
        Err(e) => json!({"ok": false, "error": e}),
    }
}

fn s4(dir: &Path) -> Value {
    let path = dir.join("s4.sock");
    let first = match bind(&path) {
        Ok(server) => server,
        Err(e) => return json!({"first_ok": false, "error": e}),
    };
    let second = bind(&path);
    let row = match &second {
        Ok(_) => json!({"first_ok": true, "second_ok": true, "error": null}),
        Err(e) => json!({"first_ok": true, "second_ok": false, "error": e}),
    };
    let first_reachable = connect(&path);
    drop(second);
    drop(first);
    let mut row = row;
    row["first_reachable_after"] = first_reachable;
    row
}

fn s5(dir: &Path) -> Value {
    let path = dir.join("s5.sock");
    let exe = match std::env::current_exe() {
        Ok(exe) => exe,
        Err(e) => return json!({"hold_bound": false, "error": format!("current_exe: {e}")}),
    };
    let mut child = match Command::new(exe)
        .arg("--hold")
        .arg(&path)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
    {
        Ok(child) => child,
        Err(e) => return json!({"hold_bound": false, "error": format!("spawn: {e}")}),
    };
    let started = Instant::now();
    let mut bound = false;
    while started.elapsed() < Duration::from_secs(5) {
        if exists(&path) && UnixStream::connect(&path).is_ok() {
            bound = true;
            break;
        }
        std::thread::sleep(Duration::from_millis(20));
    }
    let killed = child.kill().is_ok(); // SIGKILL
    let _ = child.wait();
    if !bound {
        return json!({"hold_bound": false, "killed": killed, "error": "the --hold child never answered"});
    }
    let file_left = exists(&path);
    let reach = connect(&path);
    let row = match bind(&path) {
        Ok(server) => {
            let after = connect(&path);
            drop(server);
            json!({"bind_ok": true, "bind_error": null, "connect_after_bind": after})
        }
        Err(e) => json!({"bind_ok": false, "bind_error": e}),
    };
    let _ = std::fs::remove_file(&path);
    let mut row = row;
    row["hold_bound"] = json!(true);
    row["killed"] = json!(killed);
    row["file_left"] = json!(file_left);
    row["connect"] = reach;
    row
}

fn s6(dir: &Path) -> Value {
    let path = dir.join("s6.sock");
    let content = b"a regular file, not a socket\n";
    if let Err(e) = std::fs::write(&path, content) {
        return json!({"bind_ok": false, "error": format!("fixture: {e}")});
    }
    let result = bind(&path);
    let intact = std::fs::read(&path).map(|b| b == content).unwrap_or(false);
    let row = match &result {
        Ok(_) => json!({"bind_ok": true, "error": null}),
        Err(e) => json!({"bind_ok": false, "error": e}),
    };
    drop(result);
    let mut row = row;
    row["file_intact"] = json!(intact);
    row
}

fn s7(dir: &Path) -> Value {
    let path = dir.join("s7.sock");
    let a = match bind(&path) {
        Ok(a) => a,
        Err(e) => return json!({"a_ok": false, "error": e}),
    };
    if let Err(e) = std::fs::remove_file(&path) {
        return json!({"a_ok": true, "error": format!("unlink: {e}")});
    }
    let b = match bind(&path) {
        Ok(b) => b,
        Err(e) => return json!({"a_ok": true, "b_ok": false, "error": e}),
    };
    let before = connect(&path);
    drop(a);
    let file_after = exists(&path);
    let after = connect(&path);
    drop(b);
    json!({
        "a_ok": true,
        "b_ok": true,
        "b_reachable_before_drop": before,
        "b_file_exists_after_a_drop": file_after,
        "b_reachable_after_a_drop": after,
    })
}

fn s8(dir: &Path) -> Value {
    let path = dir.join("s8.sock");
    let server = match bind(&path) {
        Ok(s) => Arc::new(s),
        Err(e) => return json!({"ok": false, "error": e}),
    };
    let serving = Arc::clone(&server);
    let thread = std::thread::spawn(move || {
        for mut request in serving.incoming_requests() {
            let mut body = String::new();
            let _ = request.as_reader().read_to_string(&mut body);
            let answer = json!({"method": request.method().to_string(), "url": request.url(), "body": body});
            let _ = request.respond(tiny_http::Response::from_string(answer.to_string()));
        }
    });
    let body = r#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#;
    let request = format!(
        "POST /mcp HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        body.len(),
        body
    );
    let outcome = (|| -> Result<String, String> {
        let mut stream = UnixStream::connect(&path).map_err(|e| format!("connect: {e}"))?;
        stream
            .set_read_timeout(Some(Duration::from_secs(5)))
            .map_err(|e| e.to_string())?;
        stream.write_all(request.as_bytes()).map_err(|e| format!("write: {e}"))?;
        let mut reply = Vec::new();
        match stream.read_to_end(&mut reply) {
            Ok(_) => {}
            Err(e) if e.kind() == ErrorKind::WouldBlock && !reply.is_empty() => {}
            Err(e) => return Err(format!("read: {e}")),
        }
        Ok(String::from_utf8_lossy(&reply).into_owned())
    })();
    server.unblock();
    let _ = thread.join();
    match outcome {
        Ok(reply) => {
            let status = reply.lines().next().unwrap_or("").to_string();
            let body = reply.split("\r\n\r\n").nth(1).unwrap_or("").to_string();
            json!({"ok": status.starts_with("HTTP/1.1 200"), "status_line": status, "body": body})
        }
        Err(e) => json!({"ok": false, "error": e}),
    }
}

fn s9(dir: &Path) -> Value {
    let path = dir.join("s9.sock");
    match bind(&path) {
        Ok(server) => {
            let addr = server.server_addr();
            let none = addr.clone().to_ip().is_none();
            json!({"ok": true, "to_ip_is_none": none, "addr": format!("{addr:?}")})
        }
        Err(e) => json!({"ok": false, "error": e}),
    }
}

fn s10(dir: &Path) -> Value {
    let path = dir.join("s10.sock");
    let server = match bind(&path) {
        Ok(s) => Arc::new(s),
        Err(e) => return json!({"ok": false, "error": e}),
    };
    let serving = Arc::clone(&server);
    let (done_tx, done_rx) = mpsc::channel();
    let thread = std::thread::spawn(move || {
        for _ in serving.incoming_requests() {}
        let _ = done_tx.send(());
    });
    std::thread::sleep(Duration::from_millis(100));
    let started = Instant::now();
    server.unblock();
    let returned = done_rx.recv_timeout(Duration::from_secs(5)).is_ok();
    let ms = started.elapsed().as_secs_f64() * 1000.0;
    if returned {
        let _ = thread.join();
    }
    json!({"ok": true, "returned": returned, "ms": (ms * 1000.0).round() / 1000.0})
}

fn hold(path: &Path) -> i32 {
    match bind(path) {
        Ok(server) => {
            for _ in server.incoming_requests() {}
            0
        }
        Err(e) => {
            eprintln!("socket_probe --hold: {e}");
            1
        }
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() == 3 && args[1] == "--hold" {
        std::process::exit(hold(Path::new(&args[2])));
    }
    if args.len() != 2 {
        eprintln!("usage: socket_probe <scratch-dir> | socket_probe --hold <path>");
        std::process::exit(2);
    }
    let dir = PathBuf::from(&args[1]);
    let rows = json!({
        "scratch": dir.to_string_lossy(),
        "S2": s2(&dir),
        "S3": s3(&dir),
        "S4": s4(&dir),
        "S5": s5(&dir),
        "S6": s6(&dir),
        "S7": s7(&dir),
        "S8": s8(&dir),
        "S9": s9(&dir),
        "S10": s10(&dir),
    });
    println!("{rows}");
}
