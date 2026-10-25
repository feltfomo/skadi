import importlib.util
import json
from pathlib import Path
import tempfile
import sys
import tomllib


spec = importlib.util.spec_from_file_location("setup", sys.argv[1])
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


def put(path, content=""):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


with tempfile.TemporaryDirectory() as directory:
    home = Path(directory)
    config = home / ".config"
    for app in setup.APPS.values():
        app(home, config)
    assert not any(home.iterdir())

    put(home / ".codex/themes/reactive.tmTheme")
    codex = home / ".codex/config.toml"
    put(codex, '# retain this comment\nmodel = "existing"\n[tui]\nnotifications = false\n')
    setup.codex(home, config)
    data = tomllib.loads(codex.read_text())
    assert data["model"] == "existing" and data["tui"]["notifications"] is False
    assert data["tui"]["theme"] == "reactive"
    assert "# retain this comment" in codex.read_text()

    put(home / ".claude/themes/reactive.json")
    claude = home / ".claude/settings.json"
    put(claude, '{"permissions":{"allow":["Read"]},"theme":"dark"}')
    setup.claude_code(home, config)
    data = json.loads(claude.read_text())
    assert data["permissions"] == {"allow": ["Read"]}
    assert data["theme"] == "custom:reactive"

    theme = config / "equibop/themes/reactive.theme.css"
    put(theme)
    quick_css = config / "equibop/settings/quickCss.css"
    put(quick_css, '@charset "UTF-8";\n.custom { color: red; }\n')
    settings = config / "equibop/settings/settings.json"
    put(settings, '{"plugins":{"existing":{"enabled":true}},"useQuickCss":false,"enabledThemes":["existing.css"]}')
    setup.equibop(home, config)
    assert quick_css.read_text() == '@charset "UTF-8";\n.custom { color: red; }\n'
    assert json.loads(settings.read_text())["plugins"]["existing"]["enabled"]
    assert json.loads(settings.read_text())["useQuickCss"] is False
    assert json.loads(settings.read_text())["enabledThemes"] == ["existing.css", "reactive.theme.css"]

    for name in ["userChrome.css", "userContent.css"]:
        put(config / "zen/theme" / name)
    profile = config / "zen/profile with spaces"
    profile.mkdir()
    put(config / "zen/profiles.ini", '[Profile0]\nIsRelative=1\nPath=profile with spaces\n')
    put(profile / "user.js", 'user_pref("keep.me", 42);\nuser_pref("zen.widget.linux.transparency", false);\nuser_pref("toolkit.legacyUserProfileCustomizations.stylesheets", false);\n')
    put(profile / "chrome/userChrome.css", ".existing { color: blue; }\n")
    before_palette = (profile / "user.js").read_bytes()
    setup.zen_browser(home, config)
    assert (profile / "user.js").read_bytes() == before_palette
    assert (profile / "chrome/userChrome.css").read_text() == ".existing { color: blue; }\n"
    put(config / "zen/theme/palette.css")
    setup.zen_browser(home, config)
    assert 'user_pref("keep.me", 42);' in (profile / "user.js").read_text()
    assert 'stylesheets", true)' in (profile / "user.js").read_text()
    assert (profile / "user.js").read_text().count('user_pref("zen.widget.linux.transparency", true);') == 1
    assert 'transparency", false)' not in (profile / "user.js").read_text()
    assert ".existing { color: blue; }" in (profile / "chrome/userChrome.css").read_text()
    for name in ["userChrome.css", "userContent.css"]:
        imported = (config / "zen/theme" / name).as_uri()
        assert (profile / "chrome" / name).read_text().count(f'@import url("{imported}");') == 1

    put(config / "obs-studio/themes/Reactive.ovt")
    obs = config / "obs-studio/user.ini"
    put(obs, '[General]\nKeep=1\n\n[Appearance]\nTheme=old\n[Other]\nKeep=2\n')
    setup.obs(home, config)
    assert "Theme=org.skadi.Reactive\nAutoReload=true\n[Other]" in obs.read_text()
    assert "Keep=1" in obs.read_text() and "Keep=2" in obs.read_text()

    watched = [codex, claude, quick_css, settings, profile / "user.js", obs]
    before = {path: (path.read_bytes(), path.stat().st_mtime_ns) for path in watched}
    for app in setup.APPS.values():
        app(home, config)
    assert before == {path: (path.read_bytes(), path.stat().st_mtime_ns) for path in watched}

    put(claude, "invalid json")
    try:
        setup.claude_code(home, config)
    except json.JSONDecodeError:
        pass
    else:
        raise AssertionError("invalid settings were accepted")
    assert claude.read_text() == "invalid json"

    linked = config / "linked.css"
    linked.symlink_to(quick_css)
    try:
        setup.css_import(linked, theme)
    except ValueError:
        pass
    else:
        raise AssertionError("symlink settings were accepted")

    put(config / "zen/profiles.ini", '[Profile0]\nIsRelative=1\nPath=../../../outside\n')
    try:
        setup.zen_browser(home, config)
    except ValueError:
        pass
    else:
        raise AssertionError("a profile outside the home was accepted")

print("Theme selection preserves app settings, rejects unsafe inputs, and is idempotent")
