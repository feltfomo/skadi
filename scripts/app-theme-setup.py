import argparse
import configparser
import fcntl
import json
import os
from pathlib import Path
import re
import stat
import tempfile

import tomlkit


def read(path):
    if path.is_symlink():
        raise ValueError(f"Refusing to replace symlink {path}")
    return path.read_text() if path.exists() else ""


def publish(path, content):
    original = read(path)
    if original == content:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o600
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as output:
        temporary = Path(output.name)
        try:
            output.write(content)
            output.flush()
            os.fchmod(output.fileno(), mode)
            os.fsync(output.fileno())
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)


def json_preferences(path, values):
    data = json.loads(read(path) or "{}")
    if not isinstance(data, dict):
        raise ValueError(f"Expected an object in {path}")
    if all(data.get(key) == value for key, value in values.items()):
        return
    data.update(values)
    publish(path, json.dumps(data, indent=2) + "\n")


def css_import(path, source):
    content = read(path)
    line = f'@import url("{source.as_uri()}");'
    if line in content.splitlines():
        return
    charset = re.match(r'^@charset\s+"[^"]+";[^\n]*\n', content)
    offset = charset.end() if charset else 0
    publish(path, content[:offset] + line + "\n" + content[offset:])


def codex(home, config):
    if not (home / ".codex/themes/reactive.tmTheme").exists():
        return
    path = home / ".codex/config.toml"
    data = tomlkit.parse(read(path))
    if "tui" not in data:
        data["tui"] = tomlkit.table()
    data["tui"]["theme"] = "reactive"
    publish(path, tomlkit.dumps(data))


def claude_code(home, config):
    if (home / ".claude/themes/reactive.json").exists():
        json_preferences(home / ".claude/settings.json", {"theme": "custom:reactive"})


def equibop(home, config):
    theme = config / "equibop/themes/reactive.theme.css"
    if not theme.exists():
        return
    path = config / "equibop/settings/settings.json"
    data = json.loads(read(path) or "{}")
    enabled = data.get("enabledThemes", [])
    if not isinstance(enabled, list) or not all(isinstance(name, str) for name in enabled):
        raise ValueError(f"Expected enabledThemes to be a list of names in {path}")
    if theme.name not in enabled:
        json_preferences(path, {"enabledThemes": [*enabled, theme.name]})


def zen_browser(home, config):
    theme = config / "zen/theme"
    if not (theme / "userChrome.css").exists() or not (theme / "userContent.css").exists():
        return
    roots = dict.fromkeys([config / "zen", home / ".zen"])
    for root in roots:
        profiles = configparser.ConfigParser(interpolation=None)
        profiles.read(root / "profiles.ini")
        for section in profiles.sections():
            if not section.startswith("Profile"):
                continue
            entry = profiles[section]
            if entry.get("IsRelative", "1") != "1":
                raise ValueError(f"Expected a home-relative Zen profile in {root}")
            profile = (root / entry["Path"]).resolve()
            if not profile.is_relative_to(home.resolve()) or not profile.is_dir():
                raise ValueError(f"Invalid Zen profile directory {profile}")
            for name in ["userChrome.css", "userContent.css"]:
                css_import(profile / "chrome" / name, theme / name)
            path = profile / "user.js"
            content = read(path)
            key = "toolkit.legacyUserProfileCustomizations.stylesheets"
            pattern = re.compile(r'^\s*user_pref\(\s*"' + re.escape(key) + r'"\s*,[^\n]*\n?', re.M)
            content = pattern.sub("", content)
            if content and not content.endswith("\n"):
                content += "\n"
            publish(path, content + f'user_pref("{key}", true);\n')


def obs(home, config):
    if not (config / "obs-studio/themes/Reactive.ovt").exists():
        return
    path = config / "obs-studio/user.ini"
    content = read(path)
    section = re.search(r"(?m)^\[Appearance\][ \t]*\r?$", content)
    values = {"Theme": "org.skadi.Reactive", "AutoReload": "true"}
    if section:
        start = section.end()
        following = re.search(r"(?m)^\[", content[start:])
        end = start + following.start() if following else len(content)
        body = content[start:end]
        for key, value in values.items():
            pattern = re.compile(r"(?m)^" + key + r"[ \t]*=.*$")
            if pattern.search(body):
                body = pattern.sub(f"{key}={value}", body)
            else:
                body = body.rstrip("\n") + f"\n{key}={value}\n"
        content = content[:start] + body + content[end:]
    else:
        content = content.rstrip("\n") + "\n[Appearance]\n"
        content += "".join(f"{key}={value}\n" for key, value in values.items())
    publish(path, content)


APPS = {
    "claude-code": claude_code,
    "zen-browser": zen_browser,
    "equibop": equibop,
    "codex": codex,
    "obs": obs,
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("app", choices=APPS)
    args = parser.parse_args()
    home = Path.home()
    config = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config"))
    state = Path(os.environ.get("XDG_STATE_HOME", home / ".local/state"))
    directory = state / "skadi/theme-preferences"
    directory.mkdir(parents=True, exist_ok=True)
    with (directory / f"{args.app}.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        APPS[args.app](home, config)


if __name__ == "__main__":
    main()
