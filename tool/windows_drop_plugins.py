#!/usr/bin/env python3
"""Drops the Windows part of plugins SARCADE does not use on Windows.

firebase_core ships its Windows C++ SDK for x64 only: the ARM64 build cannot
link it (LNK2019, card « Client Windows : écran gris au démarrage », 31 Oct
2026). Firebase serves the wake-up of Android and iPhone only
(lib/src/services/wakeup_fcm.dart), so its Windows plugin is not needed.
Run after `flutter pub get`; edits the plugin's pubspec in the pub cache of
the CI machine, then `flutter pub get` must run again.
"""
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlparse, unquote

PLUGINS = ["firebase_core", "firebase_messaging"]


def package_dirs() -> dict:
    cfg = json.loads(Path(".dart_tool/package_config.json").read_text(encoding="utf-8"))
    out = {}
    for p in cfg["packages"]:
        uri = p["rootUri"]
        if uri.startswith("file://"):
            path = unquote(urlparse(uri).path)
            if re.match(r"^/[A-Za-z]:", path):
                path = path[1:]
            out[p["name"]] = Path(path)
    return out


def drop_windows(pubspec: Path) -> bool:
    lines = pubspec.read_text(encoding="utf-8").splitlines(keepends=True)
    out, i, dropped = [], 0, False
    while i < len(lines):
        m = re.match(r"^(\s+)windows:\s*$", lines[i])
        if m:
            indent = len(m.group(1))
            i += 1
            while i < len(lines) and (not lines[i].strip() or len(lines[i]) - len(lines[i].lstrip()) > indent):
                i += 1
            dropped = True
            continue
        out.append(lines[i])
        i += 1
    if dropped:
        pubspec.write_text("".join(out), encoding="utf-8")
    return dropped


def main() -> int:
    dirs = package_dirs()
    for name in PLUGINS:
        d = dirs.get(name)
        if d is None:
            continue
        done = drop_windows(d / "pubspec.yaml")
        print(f"{name}: windows {'dropped' if done else 'not declared'} ({d})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
