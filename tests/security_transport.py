#!/usr/bin/env python3
"""Optional integration tests only; Python is not an Awqat runtime dependency."""
import http.server
import os
from pathlib import Path
import ssl
import subprocess
import tempfile
import threading
import time

LIMIT = 262144
requests = []

class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *_):
        pass
    def do_GET(self):
        requests.append(self.path)
        try:
            if self.path == "/slow":
                time.sleep(2)
            if self.path == "/redirect":
                self.send_response(302)
                self.send_header("Location", "/followed")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            if self.path == "/chunked":
                self.send_response(200)
                self.send_header("Transfer-Encoding", "chunked")
                self.end_headers()
                chunk = b"A" * 8192
                for _ in range(LIMIT // len(chunk) + 1):
                    self.wfile.write(b"2000\r\n" + chunk + b"\r\n")
                self.wfile.write(b"0\r\n\r\n")
                return
            body = b"A" * (LIMIT + (self.path == "/oversized")) if self.path in ("/exact", "/oversized") else b"{}"
            self.send_response(404 if self.path == "/error" else 200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
            pass

class Server(http.server.ThreadingHTTPServer):
    def handle_error(self, *_):
        pass

with tempfile.TemporaryDirectory(prefix="awqat-tls-test-") as folder:
    cert = Path(folder) / "cert.pem"
    key = Path(folder) / "key.pem"
    subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-noenc", "-days", "1",
                    "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost",
                    "-keyout", str(key), "-out", str(cert)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(cert, key)
    server = Server(("127.0.0.1", 0), Handler)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    try:
        env = dict(os.environ, AWQAT_TLS_URL=f"https://localhost:{server.server_port}", AWQAT_TLS_CA=str(cert),
                   NO_PROXY="localhost,127.0.0.1", no_proxy="localhost,127.0.0.1")
        subprocess.run(["cargo", "test", "--locked", "--offline", "--target-dir", "/tmp/awqat-security-build",
                        "net::transport_tests::https_transport_boundaries", "--", "--ignored", "--exact"], env=env, check=True,
                       cwd=Path(__file__).resolve().parents[1], timeout=120)
        assert "/followed" not in requests, "Redirect target was contacted"
        print("TLS fixture: 9 transport assertions passed; redirect target was never contacted")
    finally:
        server.shutdown()
        server.server_close()
        worker.join()
