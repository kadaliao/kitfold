#!/bin/bash
# Render the app's own window into PNGs (snapshot mode), against a demo home.
#   scripts/lib/snapshot-app.sh <demo-home> <script: tour|marketing|video> <light|dark> <out-dir> [1440x900]
# The binary is wrapped in a throwaway .app and launched through LaunchServices, so its window is
# frontmost and renders as active (colored traffic lights, accent selection). The app quits by
# itself; a watchdog is the safety net.
set -euo pipefail
cd "$(dirname "$0")/../.."
DEMO="$(cd "$1" && pwd -P)" SCRIPT="$2" APPEARANCE="$3" OUT="$4" SIZE="${5:-1440x900}"
swift build --product KitfoldApp >/dev/null
WORK="$(mktemp -d)"
APP="$WORK/Kitfold Snapshots.app"
mkdir -p "$APP/Contents/MacOS" "$OUT"
cp "$(swift build --show-bin-path)/KitfoldApp" "$APP/Contents/MacOS/Kitfold"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>app.kitfold.Kitfold.snapshots</string>
  <key>CFBundleName</key><string>Kitfold</string>
  <key>CFBundleExecutable</key><string>Kitfold</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
( sleep 150; pkill -f "$APP/Contents/MacOS/Kitfold" ) >/dev/null 2>&1 &
watchdog=$!
open -W -n "$APP" --env KITFOLD_FAKE_HOME="$DEMO" --env PATH="$DEMO/.local/bin:/usr/bin:/bin" \
  --env KITFOLD_SNAPSHOT_DIR="$OUT" --env KITFOLD_SNAPSHOT_SCRIPT="$SCRIPT" \
  --env KITFOLD_SNAPSHOT_APPEARANCE="$APPEARANCE" --env KITFOLD_SNAPSHOT_SIZE="$SIZE" || true
pkill -P "$watchdog" 2>/dev/null || true
{ kill "$watchdog" && wait "$watchdog"; } >/dev/null 2>&1 || true
rm -rf "$WORK"
