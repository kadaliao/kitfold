#!/bin/bash
# Regenerate release screenshots from a fictional demo home.
#   scripts/screenshots/make.sh
# Full-size PNGs (3200×2000) go to build/screenshots/, README-sized JPEGs (1920×1200) to docs/assets/screenshots/.
set -euo pipefail
cd "$(dirname "$0")/../.."

WORK="$(mktemp -d)/kitfold-shots"
DEMO="$WORK/home"
scripts/demo/make-demo-home.sh "$DEMO" >/dev/null
capture() {  # capture <appearance>
  scripts/lib/snapshot-app.sh "$DEMO" marketing "$1" "$WORK/$1"
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
