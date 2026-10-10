#!/bin/sh
# Builds sarcade-linux-x86_64.AppImage from the Flutter Linux release bundle.
# Run from the repository root after `flutter build linux --release`.
set -eu
BUNDLE=build/linux/x64/release/bundle
APPDIR=build/AppDir
rm -rf "$APPDIR" && mkdir -p "$APPDIR/usr/bin"
cp -r "$BUNDLE"/. "$APPDIR/usr/bin/"
cat > "$APPDIR/AppRun" <<'RUN'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/bin/sarcade_app" "$@"
RUN
chmod +x "$APPDIR/AppRun"
cat > "$APPDIR/sarcade.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=SARCADE
Comment=Coordination opérationnelle ADRASEC
Exec=sarcade_app
Icon=sarcade
Categories=Utility;Network;
Terminal=false
DESKTOP
python3 tool/make_icon.py "$APPDIR/sarcade.png" 256
curl -fsSL -o build/appimagetool https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
chmod +x build/appimagetool
ARCH=x86_64 build/appimagetool --appimage-extract-and-run "$APPDIR" sarcade-linux-x86_64.AppImage
