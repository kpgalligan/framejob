"""The local stand-in server for a `framejob://` link's fetch (spec §11 G-49),
shared by `graphic_link_probe.py` and `graphic_link_proof.py`. Stdlib only,
bound to `127.0.0.1` on a port the system picks, plain HTTP: the app and the
probe reach it only with the dev-only loopback switch.

    server = graphic_link_server.Listener({"late.fjgraphic": data})
    server.url("/pkg/late.fjgraphic")   # http://127.0.0.1:<port>/pkg/late.fjgraphic
    server.requests()                   # every path asked for, in order
    server.stop()

Paths:
  /pkg/<name>        200, the bytes registered under <name>, with their length
  /status/<code>     that status, a short body
  /redirect?to=<u>   302 to <u> (percent-decoded), whatever it is
  /chain/<n>         302 to /chain/<n-1>; /chain/0 answers the first package
  /declared/<n>      200, Content-Length <n>, then <n> zero bytes
  /endless           200, no length, zero bytes until the client closes (12 s at most);
                     `closed("/endless")` is then the bytes it had sent
  /stall             200, Content-Length 100, then nothing for 10 s
  /drip              200, Content-Length 1000, one byte every 0.3 s, 20 of them
  /slow/<ms>/<name>  the package, its second half <ms> milliseconds after its first
  /hold/<key>/<name> the package's headers, then its body once `release(key)` is called
                     (30 s at most); `holding(key)` says the request has arrived
  /multipart/<n>     200, `multipart/x-mixed-replace`, <n> parts `part0`… each with its own
                     headers, 20 ms apart, until the client closes
  /never/<x>         404; a row asserts it was never asked for
"""

import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Listener:
    def __init__(self, packages):
        self.packages = dict(packages)
        self._lock = threading.Lock()
        self._requests = []
        self._closed = {}
        self._holds = {}
        self._arrived = set()
        owner = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.0"

            def log_message(self, *_):
                pass

            def do_GET(self):
                try:
                    owner._serve(self)
                except (BrokenPipeError, ConnectionResetError, OSError):
                    pass

        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.httpd.daemon_threads = True
        self.port = self.httpd.server_address[1]
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()

    # ---- what a script asks -----------------------------------------------------------------

    def url(self, path):
        return f"http://127.0.0.1:{self.port}{path}"

    def requests(self):
        with self._lock:
            return list(self._requests)

    def closed(self, path):
        with self._lock:
            return self._closed.get(path)

    def holding(self, key):
        with self._lock:
            return key in self._arrived

    def release(self, key):
        self._hold(key).set()

    def stop(self):
        with self._lock:
            holds = list(self._holds.values())
        for event in holds:
            event.set()
        self.httpd.shutdown()
        self.httpd.server_close()

    def _hold(self, key):
        with self._lock:
            return self._holds.setdefault(key, threading.Event())

    # ---- the routes -------------------------------------------------------------------------

    def _head(self, handler, status, length=None, extra=()):
        handler.send_response(status)
        handler.send_header("Content-Type", "application/octet-stream")
        if length is not None:
            handler.send_header("Content-Length", str(length))
        for name, value in extra:
            handler.send_header(name, value)
        handler.end_headers()

    def _package(self, name):
        return self.packages.get(name, next(iter(self.packages.values()), b""))

    def _serve(self, handler):
        parsed = urllib.parse.urlsplit(handler.path)
        path = parsed.path
        with self._lock:
            self._requests.append(handler.path)
        parts = path.strip("/").split("/")
        route = parts[0]
        out = handler.wfile
        if route == "pkg" and len(parts) == 2 and parts[1] in self.packages:
            data = self.packages[parts[1]]
            self._head(handler, 200, len(data))
            out.write(data)
        elif route == "status" and len(parts) == 2:
            body = b"no\n"
            self._head(handler, int(parts[1]), len(body))
            out.write(body)
        elif route == "redirect":
            target = urllib.parse.parse_qs(parsed.query).get("to", [""])[0]
            self._head(handler, 302, 0, [("Location", target)])
        elif route == "chain" and len(parts) == 2:
            left = int(parts[1])
            if left > 0:
                self._head(handler, 302, 0, [("Location", self.url(f"/chain/{left - 1}"))])
            else:
                data = self._package("")
                self._head(handler, 200, len(data))
                out.write(data)
        elif route == "declared" and len(parts) == 2:
            size = int(parts[1])
            self._head(handler, 200, size)
            block = bytes(65536)
            while size > 0:
                out.write(block[:min(size, len(block))])
                size -= len(block)
        elif route == "endless":
            self._head(handler, 200)
            sent, block, deadline = 0, bytes(65536), time.monotonic() + 12
            try:
                while time.monotonic() < deadline:
                    out.write(block)
                    out.flush()
                    sent += len(block)
            except OSError:
                with self._lock:
                    self._closed[path] = sent
        elif route == "stall":
            self._head(handler, 200, 100)
            out.flush()
            time.sleep(10)
        elif route == "drip":
            self._head(handler, 200, 1000)
            for _ in range(20):
                out.write(b"x")
                out.flush()
                time.sleep(0.3)
        elif route == "slow" and len(parts) == 3:
            data = self._package(parts[2])
            self._head(handler, 200, len(data))
            out.write(data[:len(data) // 2])
            out.flush()
            time.sleep(int(parts[1]) / 1000)
            out.write(data[len(data) // 2:])
        elif route == "hold" and len(parts) == 3:
            data = self._package(parts[2])
            self._head(handler, 200, len(data))
            out.flush()
            with self._lock:
                self._arrived.add(parts[1])
            self._hold(parts[1]).wait(30)
            out.write(data)
        elif route == "multipart" and len(parts) == 2:
            handler.send_response(200)
            handler.send_header("Content-Type", "multipart/x-mixed-replace; boundary=B")
            handler.end_headers()
            for index in range(int(parts[1])):
                body = b"part%d" % index
                out.write(b"--B\r\nContent-Type: application/octet-stream\r\n"
                          b"Content-Length: %d\r\n\r\n%s\r\n" % (len(body), body))
                out.flush()
                time.sleep(0.02)
            out.write(b"--B--\r\n")
        else:
            body = b"not found\n"
            self._head(handler, 404, len(body))
            out.write(body)
