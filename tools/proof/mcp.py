"""A minimal MCP streamable-HTTP client, enough to drive Reelcut's agent."""

import json
import urllib.request


class MCP:
    def __init__(self, port, path="/mcp", timeout=600):
        """`timeout` is the per-request ceiling in seconds. 600 is what every
        script before road map 3 waited (and still waits: the default is
        unchanged); `recording_proof.py` passes its own, because a
        `record_screen` blocks for the whole recording plus its finish and a
        hang has to be told apart from a long take."""
        self.url = f"http://127.0.0.1:{port}{path}"
        self.session = None
        self.next_id = 0
        self.timeout = timeout
        self._request(
            "initialize",
            {
                "protocolVersion": "2025-06-18",
                "capabilities": {},
                "clientInfo": {"name": "reelcut-proof", "version": "1"},
            },
        )
        self._notify("notifications/initialized")

    def _post(self, body, notify=False):
        data = json.dumps(body).encode()
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
        }
        if self.session:
            headers["Mcp-Session-Id"] = self.session
        req = urllib.request.Request(self.url, data=data, headers=headers, method="POST")
        with urllib.request.urlopen(req, timeout=self.timeout) as response:
            sid = response.headers.get("Mcp-Session-Id")
            if sid:
                self.session = sid
            raw = response.read().decode()
        if notify or not raw.strip():
            return None
        # SSE frames or a bare JSON body.
        for line in raw.splitlines():
            if line.startswith("data:"):
                return json.loads(line[5:].strip())
        return json.loads(raw)

    def _request(self, method, params):
        self.next_id += 1
        answer = self._post(
            {"jsonrpc": "2.0", "id": self.next_id, "method": method, "params": params}
        )
        if answer is None:
            raise RuntimeError(f"{method}: no answer")
        if "error" in answer:
            raise RuntimeError(f"{method}: {answer['error']}")
        return answer["result"]

    def _notify(self, method, params=None):
        self._post({"jsonrpc": "2.0", "method": method, "params": params or {}}, notify=True)

    def tools(self):
        return [t["name"] for t in self._request("tools/list", {})["tools"]]

    def call(self, name, **arguments):
        """Call a tool with keyword arguments. A tool ARGUMENT spelled `name`
        (`add_track`, `set_track`, `add_marker`, `set_marker`, `nest`)
        collides with this parameter — send those through `call_with`."""
        return self.call_with(name, arguments)

    def call_with(self, tool, arguments):
        """Call `tool` with `arguments` as a dict, whatever its keys are."""
        result = self._request("tools/call", {"name": tool, "arguments": arguments})
        text = "".join(
            part.get("text", "") for part in result.get("content", []) if part.get("type") == "text"
        )
        if result.get("isError"):
            raise ToolError(f"{tool}: {text}")
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            return text


class ToolError(RuntimeError):
    pass
