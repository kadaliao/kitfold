#!/bin/bash
# Build Kitfold.app (release) into ./build/Kitfold.app, ad-hoc signed.
#   ARCHS="arm64 x86_64" scripts/bundle.sh    # universal (what scripts/release.sh does)
# The version is set below; scripts/release.sh reads it from the built Info.plist.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="0.5.0"
BUILD="6"  # add 1 for every release

FLAGS=(-c release)
for arch in ${ARCHS:-}; do FLAGS+=(--arch "$arch"); done
swift build "${FLAGS[@]}" --product KitfoldApp
swift build "${FLAGS[@]}" --product kitfold
BIN="$(swift build "${FLAGS[@]}" --show-bin-path)"

APP=build/Kitfold.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/KitfoldApp" "$APP/Contents/MacOS/Kitfold"
cp "$BIN/kitfold" "$APP/Contents/Resources/kitfold"

# Icon
ICONSET=build/Kitfold.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
swift scripts/make-icon.swift build/icon-1024.png >/dev/null
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Kitfold.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Kitfold</string>
  <key>CFBundleDisplayName</key><string>Kitfold</string>
  <key>CFBundleIdentifier</key><string>app.kitfold.Kitfold</string>
  <key>CFBundleExecutable</key><string>Kitfold</string>
  <key>CFBundleIconFile</key><string>Kitfold</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <!-- Kitfold translates its own text (Sources/KitfoldCore/Localization). Listing the languages lets macOS
       offer them under System Settings › Language & Region › Applications and localize its own menus. -->
  <key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string></array>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD}</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>One library. Every agent. Your rules.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
