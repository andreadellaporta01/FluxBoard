#!/usr/bin/env python3
"""Serve build/web locally WITH cross-origin isolation headers, so
multithreaded Skwasm actually kicks in for the recording.

Usage (from the project root, after `flutter build web --wasm`):
    python3 serve.py           # http://localhost:8000
    python3 serve.py 9000      # custom port
"""
import http.server
import os
import socketserver
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build", "web")
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8000


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def end_headers(self):
        # The two headers that unlock SharedArrayBuffer -> multithreaded Skwasm.
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def guess_type(self, path):
        if path.endswith(".wasm"):
            return "application/wasm"
        return super().guess_type(path)


if not os.path.isdir(ROOT):
    sys.exit("build/web not found — run `flutter build web --wasm` first.")

with socketserver.TCPServer(("", PORT), Handler) as httpd:
    print(f"FluxBoard (cross-origin isolated) → http://localhost:{PORT}")
    print("Open in Chrome, then check `self.crossOriginIsolated === true` in the console.")
    httpd.serve_forever()
