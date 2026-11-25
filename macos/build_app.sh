#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(dirname "$DIR")"
APP_NAME="Phone Mirroring.app"
DEST_APP="$WORKSPACE_ROOT/$APP_NAME"
TARGET_OS="macosx13.0"

echo "==> Building Phone Mirroring Universal macOS App (macOS 13.0+)..."

SDK_PATH="$(xcrun --show-sdk-path)"
echo "==> Using SDK: $SDK_PATH"

TEMP_ARM64="/tmp/PhoneMirroring_arm64"
TEMP_X86_64="/tmp/PhoneMirroring_x86_64"
TEMP_UNIVERSAL="/tmp/PhoneMirroring_universal"

SWIFT_SOURCES=()
while IFS= read -r -d $'\0' file; do
    SWIFT_SOURCES+=("$file")
done < <(find "$DIR/Sources/Screen Sharing" -name "*.swift" -print0)

echo "==> Found ${#SWIFT_SOURCES[@]} Swift source files."

echo "==> [1/4] Compiling native arm64 binary (-target arm64-apple-$TARGET_OS)..."
swiftc \
    -target "arm64-apple-$TARGET_OS" \
    -sdk "$SDK_PATH" \
    -module-cache-path /tmp/mcache \
    -parse-as-library \
    "${SWIFT_SOURCES[@]}" \
    -o "$TEMP_ARM64"

echo "==> [2/4] Compiling x86_64 binary (-target x86_64-apple-$TARGET_OS)..."
swiftc \
    -target "x86_64-apple-$TARGET_OS" \
    -sdk "$SDK_PATH" \
    -module-cache-path /tmp/mcache \
    -parse-as-library \
    "${SWIFT_SOURCES[@]}" \
    -o "$TEMP_X86_64"

echo "==> [3/4] Creating Universal Binary (arm64 + x86_64)..."
lipo -create "$TEMP_ARM64" "$TEMP_X86_64" -o "$TEMP_UNIVERSAL"

echo "==> [4/4] Assembling and signing $APP_NAME..."
rm -rf "$DEST_APP"
mkdir -p "$DEST_APP/Contents/MacOS"
mkdir -p "$DEST_APP/Contents/Resources/bin"

cp "$TEMP_UNIVERSAL" "$DEST_APP/Contents/MacOS/PhoneMirroring"
chmod +x "$DEST_APP/Contents/MacOS/PhoneMirroring"
cp "$DIR/Resources/Info.plist" "$DEST_APP/Contents/Info.plist"
if [ -f "$DIR/Resources/AppIcon.icns" ]; then
    cp "$DIR/Resources/AppIcon.icns" "$DEST_APP/Contents/Resources/AppIcon.icns"
fi
if [ -f "$DIR/Resources/THIRD_PARTY_LICENSES.txt" ]; then
    cp "$DIR/Resources/THIRD_PARTY_LICENSES.txt" "$DEST_APP/Contents/Resources/THIRD_PARTY_LICENSES.txt"
fi

# Bundle adb, scrcpy, and scrcpy-server
if [ -d "$DIR/Resources/bin" ]; then
    cp -R "$DIR/Resources/bin/"* "$DEST_APP/Contents/Resources/bin/"
    chmod +x "$DEST_APP/Contents/Resources/bin/adb" "$DEST_APP/Contents/Resources/bin/scrcpy" 2>/dev/null || true
fi

echo -n "APPL????" > "$DEST_APP/Contents/PkgInfo"

# Clear quarantine and ad-hoc sign nested binaries and main bundle
xattr -cr "$DEST_APP"
find "$DEST_APP/Contents/Resources/bin" -type f -perm +111 -exec codesign --force --sign - {} + 2>/dev/null || true
codesign --force --deep --sign - --entitlements "$DIR/Resources/Screen Sharing.entitlements" "$DEST_APP"

echo "==> Successfully built $DEST_APP"
echo "Main Binary Architectures: $(lipo -archs "$DEST_APP/Contents/MacOS/PhoneMirroring")"
echo "Bundled adb Architectures: $(lipo -archs "$DEST_APP/Contents/Resources/bin/adb")"
echo "Bundled scrcpy Architectures: $(lipo -archs "$DEST_APP/Contents/Resources/bin/scrcpy")"
vtool -show-build "$DEST_APP/Contents/MacOS/PhoneMirroring"
