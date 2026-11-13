"""Serve the mock interviewer and proxy its AI requests to local Ollama."""

import json
import os
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parent
OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://127.0.0.1:11434")
OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "llama3.1:8b")
HOST = os.environ.get("MOCK_INTERVIEWER_HOST", "127.0.0.1")
PORT = int(os.environ.get("MOCK_INTERVIEWER_PORT", "8000"))
active_model = OLLAMA_MODEL


def resolve_model(installed_models, requested_model=OLLAMA_MODEL):
    """Use the requested tag, or an installed variant carrying that tag prefix."""
    if requested_model in installed_models:
        return requested_model
    variants = sorted(name for name in installed_models if name.startswith(requested_model + "-"))
    return variants[0] if variants else None


class InterviewerHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def send_json(self, status, body):
        encoded = json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def ollama_request(self, path, payload=None):
        data = None
        headers = {}
        if payload is not None:
            data = json.dumps(payload).encode("utf-8")
            headers["Content-Type"] = "application/json"
        request = Request(OLLAMA_URL + path, data=data, headers=headers)
        with urlopen(request, timeout=300) as response:
            return json.loads(response.read().decode("utf-8"))

    def do_GET(self):
        global active_model
        if self.path != "/api/status":
            return super().do_GET()
        try:
            tags = self.ollama_request("/api/tags")
            installed = {item["name"] for item in tags.get("models", [])}
            resolved = resolve_model(installed)
            if resolved is None:
                self.send_json(
                    503,
                    {"error": f"Model {OLLAMA_MODEL} is not installed. Run: ollama pull {OLLAMA_MODEL}"},
                )
                return
            active_model = resolved
            self.send_json(200, {"ok": True, "model": active_model})
        except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as error:
            self.send_json(503, {"error": f"Could not reach Ollama: {error}"})

    def do_POST(self):
        if self.path != "/api/chat":
            self.send_json(404, {"error": "Not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            incoming = json.loads(self.rfile.read(length).decode("utf-8"))
            messages = incoming.get("messages")
            if not isinstance(messages, list) or not messages:
                self.send_json(400, {"error": "messages must be a non-empty list"})
                return
            payload = {
                "model": active_model,
                "messages": messages,
                "stream": False,
                "options": {"temperature": 0},
            }
            if incoming.get("format") == "json":
                payload["format"] = "json"
            result = self.ollama_request("/api/chat", payload)
            self.send_json(200, result)
        except json.JSONDecodeError:
            self.send_json(400, {"error": "Request body must be valid JSON"})
        except HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")
            self.send_json(502, {"error": f"Ollama returned {error.code}: {detail}"})
        except (URLError, TimeoutError) as error:
            self.send_json(503, {"error": f"Could not reach Ollama: {error}"})


if __name__ == "__main__":
    print(f"Mock Interviewer: http://{HOST}:{PORT}")
    print(f"Requested Ollama model: {OLLAMA_MODEL}")
    ThreadingHTTPServer((HOST, PORT), InterviewerHandler).serve_forever()
