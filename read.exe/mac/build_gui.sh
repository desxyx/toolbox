#!/usr/bin/env bash
# Build read.app — double-clickable macOS GUI for the read scanner.
# Usage: bash build_gui.sh
set -e
cd "$(dirname "$0")"

SRC=main_gui.mm
BINARY=read_gui
APP=read.app

echo "Compiling $SRC..."
clang++ -O2 -std=c++17 -framework Cocoa -o "$BINARY" "$SRC"
echo "[OK] Compiled"

echo "Packaging $APP..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp "$BINARY" "$APP/Contents/MacOS/$BINARY"

cat > "$APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>      <string>read_gui</string>
    <key>CFBundleIdentifier</key>      <string>com.desxyx.read</string>
    <key>CFBundleName</key>            <string>read</string>
    <key>CFBundleDisplayName</key>     <string>read</string>
    <key>CFBundleVersion</key>         <string>1.0</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "[OK] Built: $APP"
echo "     Double-click $APP to open, or: open $APP"
echo ""
echo "Note: first launch may need right-click → Open to bypass Gatekeeper."
