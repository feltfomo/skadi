"""A Matugen reload must not wait for an editor's RPC response."""

import os
from pathlib import Path
import selectors
import socket
import subprocess
import sys
import tempfile
import threading


with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    colors = root / "colors"
    colors.mkdir()
    (colors / "reactive.lua").write_text(
        'io.stdout:write("reactive loaded\\n"); io.stdout:flush()\n'
    )
    env = dict(os.environ, XDG_RUNTIME_DIR=directory)
    silent = socket.socket(socket.AF_UNIX)
    silent.bind(str(root / "nvim.silent.0"))
    silent.listen()
    received = threading.Event()

    def receive_without_reply():
        connection, _ = silent.accept()
        with connection:
            while connection.recv(65536):
                received.set()

    threading.Thread(target=receive_without_reply, daemon=True).start()
    server = subprocess.Popen(
        [
            "nvim", "--headless", "-u", "NONE", "--listen",
            str(root / "nvim.live.0"), "--cmd", f"set runtimepath^={root}",
            "--cmd", 'lua io.stdout:write("ready\\n"); io.stdout:flush()',
        ],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(server.stdout, selectors.EVENT_READ)
            assert selector.select(5), "editor did not start"
            assert server.stdout.readline() == b"ready\n"
            subprocess.run(sys.argv[1:], env=env, check=True, timeout=5)
            assert received.wait(1), "unresponsive editor received no reload"
            assert selector.select(5), "live editor did not reload"
            assert server.stdout.readline() == b"reactive loaded\n"
        print("2 checks passed: unresponsive editor does not block; live editor reloads")
    finally:
        server.terminate()
        server.wait(timeout=5)
        silent.close()
