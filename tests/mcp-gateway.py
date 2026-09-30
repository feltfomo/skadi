"""Check the gateway's HTTP boundary with local upstreams and dummy credentials."""

import http.server
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request

TOKEN = "gateway-test-credential"


class Upstream(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        body = json.dumps({"path": self.path, "headers": dict(self.headers)}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        pass


def redirect_upstreams(value, port):
    if isinstance(value, dict):
        if value.get("handler") == "reverse_proxy":
            value["upstreams"] = [{"dial": f"127.0.0.1:{port}"}]
            value.setdefault("transport", {"protocol": "http"}).pop("tls", None)
        for child in value.values():
            redirect_upstreams(child, port)
    elif isinstance(value, list):
        for child in value:
            redirect_upstreams(child, port)


def request(base, path, headers=None, method="POST"):
    req = urllib.request.Request(base + path, data=b"{}" if method == "POST" else None,
                                 headers=headers or {}, method=method)
    try:
        with urllib.request.urlopen(req, timeout=2) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


def main(config_path, header_helper, client_path):
    client = json.loads(Path(client_path).read_text())
    servers = client["mcpServers"]
    assert set(servers) == {"desktop-commander", "context7", "github"}
    assert servers["context7"]["url"] == "https://mcp.context7.com/mcp"
    assert servers["github"]["url"] == "https://api.githubcopilot.com/mcp/"
    assert all("requestHeadersCommand" not in servers[name] for name in ("context7", "github"))
    assert servers["github"]["bearerTokenStore"] is True
    assert not client["imports"]
    environment = {**os.environ, "DESKTOP_COMMANDER_MCP_TOKEN": TOKEN}
    adapted = subprocess.run(["caddy", "adapt", "--config", config_path, "--adapter", "caddyfile"],
                             env=environment, check=True, capture_output=True, text=True)
    config = json.loads(adapted.stdout)
    with tempfile.TemporaryDirectory() as temporary:
        directory = Path(temporary)
        upstream = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Upstream)
        thread = threading.Thread(target=upstream.serve_forever, daemon=True)
        thread.start()
        redirect_upstreams(config, upstream.server_port)
        with socket.socket() as reservation:
            reservation.bind(("127.0.0.1", 0))
            port = reservation.getsockname()[1]
        for server in config["apps"]["http"]["servers"].values():
            server["listen"] = [f"127.0.0.1:{port}"]
        config_file = directory / "caddy.json"
        config_file.write_text(json.dumps(config))
        log_file = directory / "caddy.log"
        with log_file.open("wb") as log:
            process = subprocess.Popen(["caddy", "run", "--config", str(config_file)],
                                       env=environment, stdout=log, stderr=log)
            base = f"http://127.0.0.1:{port}"
            try:
                deadline = time.monotonic() + 10
                while True:
                    assert process.poll() is None, log_file.read_text()
                    try:
                        status, _ = request(base, "/health", method="GET")
                        if status == 200:
                            break
                    except (urllib.error.URLError, TimeoutError):
                        pass
                    assert time.monotonic() < deadline, "Gateway startup deadline exceeded"

                assert request(base, "/mcp")[0] == 401
                assert request(base, "/mcp", {"Authorization": "Bearer invalid"})[0] == 401
                auth = {"Authorization": "Bearer " + TOKEN}
                status, body = request(base, "/mcp", auth)
                assert status == 200
                result = json.loads(body)
                assert result["path"] == "/mcp"
                assert "Authorization" not in result["headers"]
                assert TOKEN not in body.decode()
                for name in ("minecraft", "codebase-memory", "serena", "gradle", "lldb", "nixos", "kleisli", "context7", "github"):
                    assert request(base, f"/{name}/mcp", auth)[0] == 404, name
            finally:
                process.terminate()
                process.wait(timeout=5)
                upstream.shutdown()
                upstream.server_close()
                thread.join(timeout=5)
        logs = log_file.read_text()
        assert TOKEN not in logs, "Gateway credential leaked into logs"

        secret = directory / "token.env"
        secret.write_text(f'DESKTOP_COMMANDER_MCP_TOKEN="{TOKEN}"\n')
        helper_env = {**os.environ, "MCP_GATEWAY_TOKEN_FILE": str(secret)}
        helper_env.pop("DESKTOP_COMMANDER_MCP_TOKEN", None)
        result = subprocess.run([header_helper], env=helper_env, check=True,
                                capture_output=True, text=True)
        assert json.loads(result.stdout) == {"Authorization": "Bearer " + TOKEN}
        result = subprocess.run([header_helper, "Invalid"], env=helper_env,
                                capture_output=True, text=True)
        assert result.returncode != 0 and TOKEN not in result.stderr and not result.stdout
    print("1 self-hosted route, 9 retired routes, credential isolation/redaction, 3 Pi servers passed")


if __name__ == "__main__":
    main(*sys.argv[1:])
