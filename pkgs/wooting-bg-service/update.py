import base64
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from urllib.request import Request, urlopen


DOWNLOAD_URL = "https://api.wooting.io/public/bg-service/download-installer?target=linux"


def update(release_file):
    current = json.loads(release_file.read_text())
    with urlopen(Request(DOWNLOAD_URL, method="HEAD"), timeout=30) as response:
        filename = response.headers.get_filename()
    match = re.fullmatch(
        r"Wooting\.Background\.Service_(\d+\.\d+\.\d+)_amd64\.AppImage", filename or ""
    )
    if match is None:
        raise ValueError(f"unexpected Wooting download filename: {filename!r}")
    version = match[1]
    if current["version"] == version:
        print(f"Wooting Background Service {version} is up to date")
        return

    result = subprocess.run(
        [
            "nix", "store", "prefetch-file", "--json", "--hash-type", "sha256",
            "--name", f"wooting-bg-service-{version}.AppImage",
            f"{DOWNLOAD_URL}&version={version}",
        ],
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    )
    digest = json.loads(result.stdout).get("hash")
    if (
        not isinstance(digest, str)
        or not digest.startswith("sha256-")
        or len(base64.b64decode(digest.removeprefix("sha256-"), validate=True)) != 32
    ):
        raise ValueError("nix returned an invalid SHA-256 hash")

    # Keep the old pin intact until the versioned download and hash both succeed.
    with tempfile.NamedTemporaryFile(mode="w", dir=release_file.parent, delete=False) as output:
        json.dump({"version": version, "hash": digest}, output, indent=2)
        output.write("\n")
    os.replace(output.name, release_file)
    print(f"Updated Wooting Background Service from {current['version']} to {version}")


if __name__ == "__main__":
    try:
        update(Path(sys.argv[1]))
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(f"Wooting update failed: {error}")
