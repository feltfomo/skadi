import pathlib
import subprocess
import sys
import tempfile


script = pathlib.Path(sys.argv[1]).resolve()


def git(*args):
    return subprocess.run(["git", *map(str, args)], check=True, capture_output=True)


def bootstrap(checkout, remote, success=True):
    result = subprocess.run(
        ["bash", str(script), str(checkout), str(remote)], capture_output=True
    )
    assert (result.returncode == 0) == success, result.stderr.decode()


with tempfile.TemporaryDirectory() as directory:
    root = pathlib.Path(directory)
    remote = root / "remote.git"
    git("init", "--bare", remote)
    checkout = root / "Projects" / "skills"
    bootstrap(checkout, remote)
    assert (checkout / ".git").is_dir()
    skill = checkout / "SKILL.md"
    skill.write_text("local edit\n")
    before = git("-C", checkout, "status", "--porcelain").stdout
    bootstrap(checkout, root / "unreachable.git")
    assert git("-C", checkout, "status", "--porcelain").stdout == before
    assert skill.read_text() == "local edit\n"
    occupied = root / "occupied"
    occupied.mkdir()
    (occupied / "keep").write_text("keep")
    bootstrap(occupied, remote, success=False)
    assert (occupied / "keep").read_text() == "keep"
    linked = root / "linked"
    linked.symlink_to(checkout)
    bootstrap(linked, remote, success=False)
    assert linked.is_symlink()
    bootstrap(root / "missing", root / "unreachable.git", success=False)
