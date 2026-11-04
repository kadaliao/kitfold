#!/bin/bash
# Regenerate release screenshots from a fictional demo home.
#   scripts/screenshots/make.sh
# Full-size PNGs (3200×2000) go to build/screenshots/, README-sized JPEGs (1920×1200) to docs/assets/screenshots/.
set -euo pipefail
cd "$(dirname "$0")/../.."

WORK="$(mktemp -d)/kitfold-shots"
DEMO="$WORK/home"
scripts/demo/make-demo-home.sh "$DEMO" >/dev/null
swift build --product KitfoldApp >/dev/null

# Wrap the binary in a throwaway .app and launch it through LaunchServices, so its window is
# frontmost and renders as active (colored traffic lights, accent selection).
APP="$WORK/Kitfold Screenshots.app"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build --show-bin-path)/KitfoldApp" "$APP/Contents/MacOS/Kitfold"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>app.kitfold.Kitfold.screenshots</string>
  <key>CFBundleName</key><string>Kitfold</string>
  <key>CFBundleExecutable</key><string>Kitfold</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

capture() {  # capture <appearance>; the app quits by itself, the watchdog is a safety net
  ( sleep 120; pkill -f "$APP/Contents/MacOS/Kitfold" ) >/dev/null 2>&1 &
  local watchdog=$!
  open -W -n "$APP" --env KITFOLD_FAKE_HOME="$DEMO" --env PATH="$DEMO/.local/bin:/usr/bin:/bin" \
    --env KITFOLD_SNAPSHOT_DIR="$WORK/$1" --env KITFOLD_SNAPSHOT_SCRIPT=marketing \
    --env KITFOLD_SNAPSHOT_APPEARANCE="$1" --env KITFOLD_SNAPSHOT_SIZE=1440x900 || true
  pkill -P "$watchdog" 2>/dev/null || true
  { kill "$watchdog" && wait "$watchdog"; } >/dev/null 2>&1 || true
}
capture dark
capture light

OUT=build/screenshots
DOCS=docs/assets/screenshots
mkdir -p "$OUT" "$DOCS"
frame() {  # frame <name> <theme> <shot> <title> <subtitle> [overlay]
  local args=(--in "$WORK/$2/$3.png" --out "$OUT/$1.png" --theme "$2" --title "$4" --subtitle "$5")
  [[ -n "${6:-}" ]] && args+=(--overlay "$WORK/$2/$6.png")
  swift scripts/screenshots/frame.swift "${args[@]}" >/dev/null
  sips -Z 1920 -s format jpeg -s formatOptions 88 "$OUT/$1.png" --out "$DOCS/$1.jpg" >/dev/null
}
frame 01-agents    dark  agent     "See what every agent actually loads." \
  "Own folders, shared folders, plugins, and skills switched off in settings — each one traced to where it comes from."
frame 02-matrix    dark  matrix    "One grid. Every agent." \
  "Give a skill to one agent, a few, or all of them. Every cell shows how it gets there."
frame 03-review    dark  pending   "Preview every change. Undo any of them." \
  "Diffs before anything touches disk. Backups, preconditions and a full history." review-sheet
frame 04-skill     light skill     "Know where every skill lives." \
  "Who gets it, where each agent loads it from, and what's wrong with it."
frame 05-profiles  light profile   "Profiles that bring their skills along." \
  "Reusable instructions, written into each agent's own file — one marked block per profile."
frame 06-dashboard light dashboard "Your whole setup at a glance." \
  "Versions, context size and health for every agent on this Mac."
echo "Screenshots: $OUT (full size), $DOCS (README)"
rm -rf "$(dirname "$WORK")"
