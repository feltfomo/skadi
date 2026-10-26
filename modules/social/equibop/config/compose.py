import argparse
import base64
from pathlib import Path
import re


def data_uri(path, mime):
    return f"data:{mime};base64," + base64.b64encode(path.read_bytes()).decode()


def without_imports(content, expected):
    pattern = r"(?m)^@import url\([^\n]+\);\n"
    content, count = re.subn(pattern, "", content)
    if count != expected:
        raise ValueError(f"Expected {expected} upstream imports, found {count}")
    return content


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--system24", type=Path, required=True)
    parser.add_argument("--midnight", type=Path, required=True)
    parser.add_argument("--font-license", type=Path, required=True)
    parser.add_argument("--font", nargs=3, action="append", required=True)
    parser.add_argument("--palette", type=Path, required=True)
    parser.add_argument("--overrides", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    midnight = without_imports((args.midnight / "build/midnight.css").read_text(), 1)
    system24 = without_imports((args.system24 / "build/system24.css").read_text(), 2)
    for url, path, mime in [
        ("https://refact0r.github.io/midnight-discord/assets/Font_Awesome_5_solid_moon.svg",
         args.midnight / "assets/Font_Awesome_5_solid_moon.svg", "image/svg+xml"),
        ("https://refact0r.github.io/system24/assets/asciid.woff",
         args.system24 / "assets/asciid.woff", "font/woff"),
        ("https://raw.githubusercontent.com/refact0r/system24/refs/heads/main/assets/cats.gif",
         args.system24 / "assets/cats.gif", "image/gif"),
    ]:
        if midnight.count(url) + system24.count(url) != 1:
            raise ValueError(f"Expected one upstream asset reference for {url}")
        encoded = data_uri(path, mime)
        midnight = midnight.replace(url, encoded)
        system24 = system24.replace(url, encoded)
    fonts = []
    for weight, style, path in args.font:
        fonts.append(
            '@font-face { font-family: "DM Mono"; '
            f'font-weight: {weight}; font-style: {style}; font-display: swap; '
            f'src: url("{data_uri(Path(path), "font/ttf")}") format("truetype"); }}'
        )
    notices = []
    for title, path in [
        ("System24", args.system24 / "LICENSE"),
        ("Midnight", args.midnight / "LICENSE"),
        ("DM Mono", args.font_license),
    ]:
        notices.append(f"/* {title}\n{path.read_text().strip()}\n*/")
    header = """/**
 * @name System24 Reactive
 * @description System24 with a wallpaper-derived palette and embedded assets.
 * @author refact0r
 * @version 2.1.0
 * @website https://github.com/refact0r/system24
 */"""
    result = "\n\n".join([
        header, *notices, *fonts, midnight, system24,
        args.overrides.read_text(), args.palette.read_text(),
    ]) + "\n"
    if re.search(r"(?m)^\s*@import\b|url\(\s*['\"]?https?://", result):
        raise ValueError("Bundled theme still contains a runtime import or remote asset")
    args.output.write_text(result)


if __name__ == "__main__":
    main()
