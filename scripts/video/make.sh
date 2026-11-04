#!/bin/bash
# Render the launch video from a fictional demo home (never your real one).
#   scripts/video/make.sh [music.mp3]
# Writes to build/video/: kitfold-launch.mp4 (1920×1080, 60 fps), kitfold-launch-small.mp4,
# kitfold-launch.gif (the whole video) and kitfold-demo.gif (a short cut for the README).
# Needs Google Chrome, Node 22+ and ffmpeg. Music is optional and isn't part of the repo; the
# published cut uses "Focus on Yourself" by Eugenio Mininni (Mixkit Stock Music Free License).
set -euo pipefail
cd "$(dirname "$0")/../.."
MUSIC="${1:-}"
DURATION=55
WORK="$(mktemp -d)/kitfold-video"
DEMO="$WORK/home" ASSETS="$WORK/assets" OUT=build/video
mkdir -p "$ASSETS" "$OUT"

# App states and the agents' logos, rendered by the app itself.
scripts/demo/make-demo-home.sh "$DEMO" >/dev/null
scripts/lib/snapshot-app.sh "$DEMO" video dark "$ASSETS"
swift scripts/make-icon.swift "$ASSETS/icon.png" >/dev/null

node scripts/video/render.mjs --assets "$ASSETS" --out "$WORK/silent.mp4" --fps 60 --duration "$DURATION"

if [[ -n "$MUSIC" ]]; then
  ffmpeg -y -loglevel error -i "$WORK/silent.mp4" -i "$MUSIC" -filter_complex \
    "[1:a]atrim=0:$DURATION,asetpts=PTS-STARTPTS,afade=t=in:d=0.6,afade=t=out:st=$((DURATION - 3)):d=3,loudnorm=I=-16:TP=-1.5:LRA=11[a]" \
    -map 0:v -map "[a]" -c:v copy -c:a aac -b:a 192k -shortest -movflags +faststart "$OUT/kitfold-launch.mp4"
else
  cp "$WORK/silent.mp4" "$OUT/kitfold-launch.mp4"
fi

# A smaller cut for upload limits (GitHub, chat apps): 30 fps, stronger compression.
ffmpeg -y -loglevel error -i "$OUT/kitfold-launch.mp4" -c:v libx264 -preset slow -crf 27 -r 30 -pix_fmt yuv420p \
  -c:a aac -b:a 128k -movflags +faststart "$OUT/kitfold-launch-small.mp4"

gif() {  # gif <start> <length> <fps> <width> <colors> <out>
  ffmpeg -y -loglevel error -ss "$1" -t "$2" -i "$WORK/silent.mp4" -vf \
    "fps=$3,scale=$4:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=$5:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
    "$6"
}
gif 0 "$DURATION" 10 720 128 "$OUT/kitfold-launch.gif"
# README cut: the grid, hiding a skill through OpenCode's own setting, every agent's switch.
gif 18.0 15.9 12 900 144 "$OUT/kitfold-demo.gif"

ls -lh "$OUT"
rm -rf "$(dirname "$WORK")"
