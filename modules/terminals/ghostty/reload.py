import ast
import os
import re
import signal
import subprocess
import sys


def bus_call(destination, path, method, *arguments):
    return subprocess.run(
        ["gdbus", "call", "--session", "--dest", destination,
         "--object-path", path, "--method", method, *arguments],
        capture_output=True, text=True, timeout=10,
    )


def ghostty_owner():
    result = bus_call("org.freedesktop.DBus", "/org/freedesktop/DBus",
                      "org.freedesktop.DBus.GetNameOwner", "com.mitchellh.ghostty")
    if result.returncode:
        if "org.freedesktop.DBus.Error.NameHasNoOwner" in result.stderr:
            return None
        result.check_returncode()
    owner, = ast.literal_eval(result.stdout)
    if not isinstance(owner, str) or not re.fullmatch(r":[0-9]+\.[0-9]+", owner):
        raise ValueError("Unexpected Ghostty D-Bus owner")
    return owner


def herdr_clients(ghostty_pid):
    result = subprocess.run(
        ["ps", "-u", str(os.getuid()), "-o", "pid=,ppid=,comm="],
        capture_output=True, text=True, check=True,
    )
    processes = {}
    for line in result.stdout.splitlines():
        pid, parent, name = line.split(None, 2)
        processes[int(pid)] = (int(parent), name)
    for pid, (_, name) in processes.items():
        if name != "herdr":
            continue
        current = pid
        visited = set()
        while current in processes and current not in visited:
            visited.add(current)
            parent = processes[current][0]
            if parent == ghostty_pid:
                yield pid
                break
            current = parent


def reload_theme():
    owner = ghostty_owner()
    if owner is None:
        return None
    result = bus_call("org.freedesktop.DBus", "/org/freedesktop/DBus",
                      "org.freedesktop.DBus.GetConnectionUnixProcessID", owner)
    result.check_returncode()
    match = re.fullmatch(r"\(uint32 ([0-9]+),\)\s*", result.stdout)
    if match is None:
        raise ValueError("Unexpected Ghostty process ID response")
    pid = int(match[1])

    # A unique bus name prevents activation from starting Ghostty after it exits.
    result = bus_call(owner, "/com/mitchellh/ghostty", "org.gtk.Actions.Activate",
                      "reload-config", "[]", "{}")
    result.check_returncode()
    count = 0
    for client in herdr_clients(pid):
        try:
            # Herdr 0.9.5 re-queries host colors on SIGWINCH, even without a resize.
            os.kill(client, signal.SIGWINCH)
            count += 1
        except ProcessLookupError:
            continue
    return count


if __name__ == "__main__":
    try:
        count = reload_theme()
    except subprocess.CalledProcessError as error:
        print(error.stderr or str(error), file=sys.stderr)
        sys.exit(1)
    if count is not None:
        print(f"Refreshed Ghostty and {count} Herdr clients")
