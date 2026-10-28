#!/usr/bin/env python3
"""Gives the web code file the build in its name (after `flutter build web`).

Flutter always names it main.dart.js: a copy kept by the browser, Cloudflare
or the service worker could run an old version under the same name (« Mettre
à jour » that came back endlessly, 28 October 2026). Renamed main.<build>.dart.js,
a new build can only load its own code.

Usage: python3 tool/version_web.py build/web <build>   (build: main@0925d01)
"""
import re
import sys
from pathlib import Path


def main(root: str, build: str) -> int:
    web = Path(root)
    tag = re.sub(r"[^A-Za-z0-9._-]", "-", build)
    main_js = web / "main.dart.js"
    bootstrap = web / "flutter_bootstrap.js"
    sw = web / "sarcade_sw.js"
    if not main_js.is_file() or not bootstrap.is_file() or not sw.is_file():
        print("error: build/web incomplete (main.dart.js, flutter_bootstrap.js, sarcade_sw.js)", file=sys.stderr)
        return 1
    name = f"main.{tag}.dart.js"
    text = bootstrap.read_text(encoding="utf-8")
    if '"mainJsPath":"main.dart.js"' not in text:
        print("error: mainJsPath not found in flutter_bootstrap.js", file=sys.stderr)
        return 1
    if "serviceWorker" in text[text.rfind("_flutter.loader.load("):]:
        print("error: flutter_bootstrap.js still registers the Flutter service worker", file=sys.stderr)
        return 1
    bootstrap.write_text(text.replace('"mainJsPath":"main.dart.js"', f'"mainJsPath":"{name}"'), encoding="utf-8")
    main_js.rename(web / name)
    for extra in web.glob("main.dart.js*"):  # source map, deferred parts
        extra.rename(web / extra.name.replace("main.dart.js", name, 1))
    worker = sw.read_text(encoding="utf-8")
    worker = worker.replace("'main.dart.js'", f"'{name}'").replace("sarcade-shell-dev", f"sarcade-shell-{tag}")
    sw.write_text(worker, encoding="utf-8")
    print(f"web code: {name}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
