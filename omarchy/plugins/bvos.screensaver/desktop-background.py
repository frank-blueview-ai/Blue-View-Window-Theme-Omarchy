#!/usr/bin/env python3
# Copyright (c) 2026 The Blue View Group Corporation.
# Licensed under the PolyForm Noncommercial License 1.0.0. See LICENSE.
"""Apply Blue View desktop backgrounds through Omarchy."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
from tempfile import NamedTemporaryFile
from urllib.parse import unquote, urlsplit
import zlib


HOME = Path.home()
CURRENT = HOME / ".local/state/omarchy/current"
COLORS = HOME / ".local/state/bvos/backgrounds"
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp"}


def report_status():
    background = (CURRENT / "background").resolve()
    color = re.fullmatch(r"([0-9a-f]{6})\.png", background.name)
    print(json.dumps({
        "wallpaper": background.as_uri() if background.suffix.lower() in IMAGE_EXTENSIONS
        and background.is_file() and background.parent != COLORS else "",
        "color": "#" + color[1] if background.parent == COLORS and color else "",
        "themeFolder": (CURRENT / "theme/backgrounds").as_uri(),
    }))


def apply_wallpaper(url):
    parsed = urlsplit(url)
    if parsed.scheme != "file" or parsed.netloc not in ("", "localhost"):
        raise ValueError("Choose a local image file.")

    source = Path(unquote(parsed.path)).resolve(strict=True)
    if source.suffix.lower() not in IMAGE_EXTENSIONS or not source.is_file():
        raise ValueError("Choose a JPEG, PNG, GIF, BMP, or WebP image.")

    theme = (CURRENT / "theme.name").read_text().strip()
    if not theme or theme in {".", ".."} or Path(theme).name != theme:
        raise ValueError("Could not identify the current Omarchy theme.")

    folder = HOME / ".config/omarchy/backgrounds" / theme
    folder.mkdir(parents=True, exist_ok=True)
    if source.parent in (folder.resolve(), (CURRENT / "theme/backgrounds").resolve()):
        return source

    with NamedTemporaryFile(dir=folder, delete=False) as temporary:
        pending = Path(temporary.name)
        try:
            with source.open("rb") as original:
                shutil.copyfileobj(original, temporary)
            temporary.flush()
            with pending.open("rb") as image:
                digest = hashlib.file_digest(image, "sha256").hexdigest()
            destination = folder / f"{source.stem[:50]}-{digest[:16]}{source.suffix.lower()}"
            pending.replace(destination)
        finally:
            pending.unlink(missing_ok=True)
    return destination


def png_chunk(kind, data):
    return (struct.pack(">I", len(data)) + kind + data
            + struct.pack(">I", zlib.crc32(kind + data)))


def solid_color(value):
    if not re.fullmatch(r"#[a-fA-F0-9]{6}", value):
        raise ValueError("Enter a color in #RRGGBB format.")

    rgb = value[1:].lower()
    destination = COLORS / f"{rgb}.png"
    COLORS.mkdir(parents=True, exist_ok=True)
    pixels = (b"\x00" + bytes.fromhex(rgb) * 16) * 16
    png = (b"\x89PNG\r\n\x1a\n"
           + png_chunk(b"IHDR", struct.pack(">IIBBBBB", 16, 16, 8, 2, 0, 0, 0))
           + png_chunk(b"IDAT", zlib.compress(pixels))
           + png_chunk(b"IEND", b""))
    with NamedTemporaryFile(dir=COLORS, delete=False) as temporary:
        pending = Path(temporary.name)
        try:
            temporary.write(png)
            temporary.flush()
            pending.replace(destination)
        finally:
            pending.unlink(missing_ok=True)
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="mode", required=True)
    commands.add_parser("status")
    commands.add_parser("wallpaper").add_argument("url")
    commands.add_parser("color").add_argument("hex")
    args = parser.parse_args()

    try:
        if args.mode == "status":
            report_status()
            return 0
        path = apply_wallpaper(args.url) if args.mode == "wallpaper" else solid_color(args.hex)
        subprocess.run(["omarchy", "theme", "bg", "set", str(path)], check=True)
        subprocess.run(["omarchy-shell", "bvos-screensaver", "desktop", "off"], check=True)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
