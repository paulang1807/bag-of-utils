#!/bin/bash

# Exit immediately if any command exits with a non-zero status
set -e

echo "=== Bag of Utils Build Script ==="

# Define paths
WORKSPACE_DIR="/Users/pauls/Documents/_000.Code/Pauls/git/bag-of-utils"
BUILD_DIR="$WORKSPACE_DIR/build"
APP_DIR="$BUILD_DIR/BagOfUtils.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
WEB_DIR="$RESOURCES_DIR/web"
SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
GEN_ICON_PATH="/Users/pauls/.gemini/antigravity-ide/brain/799610b7-1816-4ea7-b038-b437b8b87e69/bag_of_utils_icon_clean.png"

echo "1. Cleaning previous build structures..."
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$WEB_DIR"

echo "2. Copying web interface resources..."
cp "$WORKSPACE_DIR/src/web/index.html" "$WEB_DIR/"
cp "$WORKSPACE_DIR/src/web/style.css" "$WEB_DIR/"
cp "$WORKSPACE_DIR/src/web/renamer.js" "$WEB_DIR/"
cp "$WORKSPACE_DIR/src/web/renderer.js" "$WEB_DIR/"

echo "3. Copying bundle metadata (Info.plist)..."
cp "$WORKSPACE_DIR/Info.plist" "$CONTENTS_DIR/"

# Generate application icon (.icns) if the generated high-resolution PNG is available
if [ -f "$GEN_ICON_PATH" ]; then
    echo "4. Generating native macOS .icns file from generated asset..."
    ICONSET_DIR="$WORKSPACE_DIR/AppIcon.iconset"
    mkdir -p "$ICONSET_DIR"
    
    # Resize to all macOS standard sizes using sips
    sips -s format png -z 16 16     "$GEN_ICON_PATH" --out "$ICONSET_DIR/icon_16x16.png" > /dev/null 2>&1
    sips -s format png -z 32 32     "$GEN_ICON_PATH" --out "$ICONSET_DIR/icon_16x16@2x.png" > /dev/null 2>&1
    sips -s format png -z 32 32     "$GEN_ICON_PATH" --out "$ICONSET_DIR/icon_32x32.png" > /dev/null 2>&1
    sips -s format png -z 64 64     "$GEN_ICON_PATH" --out "$ICONSET_DIR/icon_32x32@2x.png" > /dev/null 2>&1
    sips -s format png -z 128 128   "$GEN_ICON_PATH" --out "$ICONSET_DIR/icon_128x128.png" > /dev/null 2>&1
    sips -s format png -z 256 256   "$GEN_ICON_PATH" --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null 2>&1
    sips -s format png -z 256 256   "$GEN_ICON_PATH" --out "$ICONSET_DIR/icon_256x256.png" > /dev/null 2>&1
    sips -s format png -z 512 512   "$GEN_ICON_PATH" --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null 2>&1
    sips -s format png -z 512 512   "$GEN_ICON_PATH" --out "$ICONSET_DIR/icon_512x512.png" > /dev/null 2>&1
    sips -s format png -z 1024 1024 "$GEN_ICON_PATH" --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null 2>&1
    
    # Compile iconset to .icns
    iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
    
    # Clean up temporary iconset directory
    rm -rf "$ICONSET_DIR"
    echo "   AppIcon.icns successfully compiled and bundled."
else
    echo "4. Warning: High-res app icon asset not found. Skipping icon packaging..."
fi

echo "5. Compiling Swift app wrapper..."
swiftc -sdk "$SDK_PATH" "$WORKSPACE_DIR/src/swift/main.swift" -o "$MACOS_DIR/BagOfUtils"

echo "6. Making binary executable..."
chmod +x "$MACOS_DIR/BagOfUtils"

echo "=== Build Complete: build/BagOfUtils.app created successfully! ==="
