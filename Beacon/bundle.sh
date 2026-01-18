#!/bin/bash
# Build script for Beacon - Creates a proper macOS .app bundle from SPM executable
# This is required for URL scheme handling (Google OAuth callback)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build"
APP_NAME="Beacon"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
ARTIFACTS_DIR="$BUILD_DIR/artifacts"

echo "Building Beacon..."

# Build the executable with SPM
swift build -c debug

# Determine architecture
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    EXECUTABLE_PATH="$BUILD_DIR/arm64-apple-macosx/debug/$APP_NAME"
else
    EXECUTABLE_PATH="$BUILD_DIR/x86_64-apple-macosx/debug/$APP_NAME"
fi

# Verify executable exists
if [ ! -f "$EXECUTABLE_PATH" ]; then
    echo "Error: Executable not found at $EXECUTABLE_PATH"
    exit 1
fi

echo "Creating app bundle..."

# Create .app bundle structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

# Copy executable
cp "$EXECUTABLE_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy Info.plist
cp "$SCRIPT_DIR/Info.plist" "$APP_BUNDLE/Contents/"

# Create PkgInfo file
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "Copying frameworks..."

# Copy MSAL.framework
MSAL_FRAMEWORK="$ARTIFACTS_DIR/microsoft-authentication-library-for-objc/MSAL/MSAL.xcframework/macos-arm64_x86_64/MSAL.framework"
if [ -d "$MSAL_FRAMEWORK" ]; then
    cp -R "$MSAL_FRAMEWORK" "$APP_BUNDLE/Contents/Frameworks/"
    echo "  - MSAL.framework"
fi

# Update executable's rpath to find frameworks in the bundle
echo "Updating rpath..."
install_name_tool -add_rpath @executable_path/../Frameworks "$APP_BUNDLE/Contents/MacOS/$APP_NAME" 2>/dev/null || true

# Ad-hoc sign the frameworks first, then the app bundle
echo "Signing app bundle..."
if [ -d "$APP_BUNDLE/Contents/Frameworks/MSAL.framework" ]; then
    codesign --force --sign - "$APP_BUNDLE/Contents/Frameworks/MSAL.framework"
fi
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "Build complete!"
echo "App bundle created at: $APP_BUNDLE"
echo ""
echo "To run the app:"
echo "  open $APP_BUNDLE"
echo ""
echo "Or run directly:"
echo "  $APP_BUNDLE/Contents/MacOS/$APP_NAME"
