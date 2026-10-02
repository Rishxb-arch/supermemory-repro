"""Deterministic OpenAI-compatible mock LLM for reproducing the supermemory-server v0.0.8 'stuck in indexing' bug.
Container-description calls sleep DESC_DELAY seconds (default 35, i.e. just over the 30 s step timeout);
every other call returns immediately with a plain 'nothing to store' assistant message (no tool calls)."""
import json, os, time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
DELAY = float(os.environ.get("DESC_DELAY", "35")); PORT = int(os.environ.get("MOCK_PORT", "11501"))
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _send(self, obj):
        b = json.dumps(obj).encode(); self.send_response(200); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self): self._send({"object": "list", "data": [{"id": "mock", "object": "model", "owned_by": "mock"}]})
    def do_POST(self):
        j = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"{}")
        first = str((j.get("messages") or [{}])[0].get("content"))
        is_desc = "description of a Supermemory container" in first
        print(time.strftime("%H:%M:%S"), "desc" if is_desc else "other", flush=True)
        if is_desc: time.sleep(DELAY)
        content = json.dumps({"description": "Facts about one user."}) if is_desc else "Nothing to store."
        self._send({"id": "m", "object": "chat.completion", "created": int(time.time()), "model": j.get("model"),
                    "choices": [{"index": 0, "finish_reason": "stop", "message": {"role": "assistant", "content": content}}],
                    "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2}})
ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
