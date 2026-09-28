#!/bin/bash
# Builds MenubarTimer.app into ./build
set -euo pipefail
cd "$(dirname "$0")"

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

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>MenubarTimer</string>
  <key>CFBundleIdentifier</key><string>com.dohywu.menubartimer</string>
  <key>CFBundleExecutable</key><string>MenubarTimer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
