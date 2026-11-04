#!/bin/sh
# Build BootcardMaker.app from the SwiftPM release executable.
#
# Requires macOS with Command Line Tools only (no full Xcode install).
# This script cannot run on Linux: it needs xcode-select, swift, and
# the macOS SDK. On this Linux VM it fails at the preflight step.
# macOS verification of this script is owner-gated.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/BootcardMaker.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "BootcardMaker build"
echo "==================="

# Preflight: Command Line Tools.
if ! xcode-select -p >/dev/null 2>&1; then
    echo "Error: Command Line Tools are not installed." >&2
    echo "Install them with this command, then run this script again:" >&2
    echo "  xcode-select --install" >&2
    exit 1
fi

# Preflight: Swift toolchain.
if ! command -v swift >/dev/null 2>&1; then
    echo "Error: 'swift' was not found even though Command Line Tools are installed." >&2
    echo "Run 'xcode-select --install' again, then run this script again." >&2
    exit 1
fi
swift --version

# Preflight: free disk space (warn only, the owner's disk is nearly full).
FREE_KB="$(df -k "$ROOT" | awk 'NR==2 {print $4}')"
if [ "$FREE_KB" -lt 512000 ]; then
    echo "Warning: less than 500 MB free on the build volume ($FREE_KB KB)." >&2
    echo "The build may fail. Free some space and try again." >&2
fi

# Build.
cd "$ROOT"
swift build -c release

EXECUTABLE="$ROOT/.build/release/BootcardMakerApp"
if [ ! -x "$EXECUTABLE" ]; then
    echo "Error: expected executable not found at $EXECUTABLE" >&2
    exit 1
fi

# Assemble the .app bundle.
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$EXECUTABLE" "$MACOS_DIR/BootcardMaker"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>BootcardMaker</string>
	<key>CFBundleIdentifier</key>
	<string>com.example.bootcardmaker</string>
	<key>CFBundleName</key>
	<string>BootcardMaker</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSRequiresNativeExecution</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

# Ad-hoc sign. Best effort: warn, do not fail the build.
# NOTE: com.example.bootcardmaker is a placeholder identifier.
# Change it before publishing.
if codesign --force --deep -s - "$APP_DIR" 2>/dev/null; then
    echo "Ad-hoc signed: $APP_DIR"
else
    echo "Warning: ad-hoc signing failed. The app may still run after a right-click Open." >&2
fi

echo ""
echo "Built: $APP_DIR"
echo "To run an unsigned build: right-click BootcardMaker.app, choose Open, then Open again."
echo "NOTE: CFBundleIdentifier 'com.example.bootcardmaker' is a placeholder."
echo "Change it before publishing."
