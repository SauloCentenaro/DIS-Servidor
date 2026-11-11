import json
import os
import random
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.getenv("PORT", "8080"))
DELAY = float(os.getenv("ARTIFICIAL_DELAY_MS", "0")) / 1000
ERROR_RATE = float(os.getenv("ERROR_RATE", "0"))

class Handler(BaseHTTPRequestHandler):
    server_version = "BenchmarkMock/1.0"

    def reply(self, status, value):
        body = json.dumps(value, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self.reply(200, {"status": "ok"})
        else:
            self.reply(404, {"error": "not_found"})

    def do_POST(self):
        if self.path != "/reconstruct":
            return self.reply(404, {"error": "not_found"})
        size = int(self.headers.get("Content-Length", "0"))
        try:
            value = json.loads(self.rfile.read(size) or b"{}")
        except json.JSONDecodeError:
            return self.reply(400, {"error": "invalid_json"})
        if DELAY:
            time.sleep(DELAY)
        if random.random() < ERROR_RATE:
            return self.reply(503, {"error": "simulated"})
        items = value.get("values", [1, 2, 3])
        self.reply(200, {"result": items, "count": len(items)})

    def log_message(self, fmt, *args):
        print(json.dumps({"client": self.client_address[0], "message": fmt % args}), flush=True)

ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
