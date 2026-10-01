#!/bin/bash
# Builds MenubarTimer.app into ./build
# Usage: ./build.sh [version]   (default: 1.0.0)
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-1.0.0}"
APP="build/MenubarTimer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

# Workaround: some Command Line Tools installs ship a stale
# usr/include/swift/module.modulemap that duplicates bridging.modulemap and
# breaks `import Cocoa`. Hide it with a VFS overlay instead of touching /Library.
EXTRA_FLAGS=()
CLT_SWIFT_INCLUDE="/Library/Developer/CommandLineTools/usr/include/swift"
if [[ -f "$CLT_SWIFT_INCLUDE/module.modulemap" && -f "$CLT_SWIFT_INCLUDE/bridging.modulemap" ]]; then
  mkdir -p build/vfs
  : > build/vfs/empty.modulemap
  cat > build/vfs/overlay.yaml <<YAML
{
  "version": 0,
  "case-sensitive": "false",
  "roots": [{
    "type": "file",
    "name": "$CLT_SWIFT_INCLUDE/module.modulemap",
    "external-contents": "$PWD/build/vfs/empty.modulemap"
  }]
}
YAML
  EXTRA_FLAGS+=(-vfsoverlay build/vfs/overlay.yaml -Xcc -ivfsoverlay -Xcc build/vfs/overlay.yaml)
fi

swiftc -O -swift-version 5 \
  -target "$(uname -m)-apple-macos13.0" \
  ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"} \
  Sources/main.swift -o "$APP/Contents/MacOS/MenubarTimer"

# App icon: built from the first PNG layer inside ICON/*.icon/Assets/ (an
# Icon Composer package). We don't run it through Icon Composer's own
# Xcode-asset-catalog pipeline (actool/Assets.car) — this is a plain
# swiftc build, not an Xcode target — so the gradient/shadow/translucency
# defined in icon.json aren't applied; we just render the flat PNG at
# every size .icns needs. Skipped entirely if no source PNG is found.
ICON_SRC="$(find ICON -maxdepth 3 -path '*.icon/Assets/*.png' 2>/dev/null | head -1)"
ICON_PLIST_KEY=""
if [[ -n "$ICON_SRC" ]]; then
  ICONSET="build/AppIcon.iconset"
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET" "$APP/Contents/Resources"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  ICON_PLIST_KEY="  <key>CFBundleIconFile</key><string>AppIcon</string>"
  echo "App icon: $ICON_SRC"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>MenubarTimer</string>
  <key>CFBundleIdentifier</key><string>com.dohywu.menubartimer</string>
  <key>CFBundleExecutable</key><string>MenubarTimer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
$ICON_PLIST_KEY
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# A real (Apple Development / Developer ID) signing identity is required for
# UNUserNotificationCenter to work at all — macOS silently refuses the
# permission request for ad-hoc signed apps. Falls back to ad-hoc so the
# build still works on a machine with no Xcode signing identity set up
# (notifications just won't be available there).
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 -oE '"[^"]+"' | tr -d '"')"
if [[ -n "$IDENTITY" ]]; then
  # Stripping extended attrs (e.g. resource forks) occasionally doesn't "take"
  # before codesign reads the files — a timing quirk of this environment's
  # filesystem layer, not a real detritus problem — so retry a couple of times.
  for attempt in 1 2 3; do
    xattr -cr "$APP"
    if codesign --force --sign "$IDENTITY" "$APP" >/dev/null 2>/tmp/codesign-err.$$; then
      echo "Signed with: $IDENTITY"
      break
    elif [[ "$attempt" == 3 ]]; then
      cat /tmp/codesign-err.$$ >&2
      rm -f /tmp/codesign-err.$$
      exit 1
    fi
    rm -f /tmp/codesign-err.$$
    sleep 0.5
  done
else
  codesign --force --sign - "$APP" >/dev/null 2>&1 || true
  echo "No signing identity found — signed ad-hoc (Notification Center won't work)"
fi
echo "Built $APP (v$VERSION)"
