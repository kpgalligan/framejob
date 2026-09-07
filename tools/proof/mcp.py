"""A minimal MCP streamable-HTTP client, enough to drive Reelcut's agent."""

import json
import urllib.request


class MCP:
    def __init__(self, port, path="/mcp"):
        self.url = f"http://127.0.0.1:{port}{path}"
        self.session = None
        self.next_id = 0
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
        with urllib.request.urlopen(req, timeout=600) as response:
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
        result = self._request("tools/call", {"name": name, "arguments": arguments})
        text = "".join(
            part.get("text", "") for part in result.get("content", []) if part.get("type") == "text"
        )
        if result.get("isError"):
            raise ToolError(f"{name}: {text}")
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            return text


class ToolError(RuntimeError):
    pass
