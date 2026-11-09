#!/bin/bash
# Builds a self-contained BrewBar.app from the Swift package.
#
#   ./Scripts/package_app.sh              # release build (native arch)
#   UNIVERSAL=1 ./Scripts/package_app.sh  # arm64 + x86_64
#   CONFIGURATION=debug ./Scripts/package_app.sh
#   VERSION=1.2.0 ./Scripts/package_app.sh
#
# The result is an ad-hoc signed app bundle suitable for local use and
# sharing. Distribution outside your Mac still requires Developer ID signing
# and notarization.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="BrewBar"
APP="$ROOT/$APP_NAME.app"

cd "$ROOT"

echo "==> Building $APP_NAME ($CONFIGURATION)"
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    swift build -c "$CONFIGURATION" --product "$APP_NAME" --arch arm64 --arch x86_64
    if [[ "$CONFIGURATION" == "release" ]]; then
        BIN="$ROOT/.build/apple/Products/Release/$APP_NAME"
    else
        BIN="$ROOT/.build/apple/Products/Debug/$APP_NAME"
    fi
else
    swift build -c "$CONFIGURATION" --product "$APP_NAME"
    BIN="$ROOT/.build/$CONFIGURATION/$APP_NAME"
fi

if [[ ! -x "$BIN" ]]; then
    echo "error: built executable not found at $BIN" >&2
    exit 1
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Packaging/Info.plist "$APP/Contents/Info.plist"

if [[ -f Assets/AppIcon.icns ]]; then
    cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

if [[ -n "${VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi

printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing (ad-hoc)"
codesign --force --sign - --entitlements BrewBar.entitlements "$APP"

codesign --verify --verbose "$APP"
echo "==> Done: $APP"
