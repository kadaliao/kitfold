#!/bin/bash
# Render the launch video from a fictional demo home (never your real one).
#   scripts/video/make.sh [variant ...]    variants: en, zh, en-portrait, zh-portrait (default: en)
#   MUSIC=<file>   background music (optional, not part of the repo; the published cut uses
#                  "Focus on Yourself" by Eugenio Mininni, Mixkit Stock Music Free License)
#   VOICE=0        no narration. Narration otherwise needs GEMINI_API_KEY or AIHUBMIX_API_KEY
#                  (see voice.mjs); its lines are in narration.json.
# Writes to build/video/, per variant: kitfold-launch-<variant>.mp4 (60 fps),
# kitfold-launch-<variant>-small.mp4 (30 fps, for upload limits) and kitfold-launch-<variant>.srt
# (the narration's subtitles; portrait variants also have them burned in). The en variant also
# makes kitfold-launch.gif (the whole video) and kitfold-demo.gif (a short cut for the README).
# Needs Google Chrome, Node 22+ and ffmpeg.
set -euo pipefail
cd "$(dirname "$0")/../.."
VARIANTS=("${@:-en}")
for v in "${VARIANTS[@]}"; do
  case "$v" in en|zh|en-portrait|zh-portrait) ;; *) echo "unknown variant: $v" >&2; exit 2 ;; esac
done
WORK="$(mktemp -d)/kitfold-video"
DEMO="$WORK/home" ASSETS="$WORK/assets" OUT=build/video
mkdir -p "$ASSETS" "$OUT"

# App states and the agents' logos, rendered by the app itself.
scripts/demo/make-demo-home.sh "$DEMO" >/dev/null
scripts/lib/snapshot-app.sh "$DEMO" video dark "$ASSETS"
swift scripts/make-icon.swift "$ASSETS/icon.png" >/dev/null

gif() {  # gif <video> <start> <length> <fps> <width> <colors> <out>
  ffmpeg -y -loglevel error -ss "$2" -t "$3" -i "$1" -vf \
    "fps=$4,scale=$5:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=$6:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
    "$7"
}
at() {  # at <timeline.json> <scene time> → video time
  node -e 'const { from, to } = require(process.argv[1]).map, s = +process.argv[2]; let i = 0;
    while (i < from.length - 2 && s > from[i + 1]) i++;
    console.log((to[i] + (s - from[i]) * (to[i + 1] - to[i]) / (from[i + 1] - from[i])).toFixed(2))' "$1" "$2"
}

for v in "${VARIANTS[@]}"; do
  lang="${v%%-*}" dir="$WORK/$v" name="$OUT/kitfold-launch-$v"
  layout=landscape size=1920x1080 subs=0
  if [[ "$v" == *-portrait ]]; then layout=portrait size=1080x1920 subs=1; fi
  echo "== $v"
  if [[ "${VOICE:-1}" == 0 ]]; then
    duration=$(node scripts/video/voice.mjs --lang "$lang" --out "$dir" --silent)
  else
    duration=$(node scripts/video/voice.mjs --lang "$lang" --out "$dir")
  fi
  node scripts/video/render.mjs --assets "$ASSETS" --out "$dir/silent.mp4" --fps 60 --duration "$duration" --size "$size" \
    --query "lang=$lang&layout=$layout&subs=$subs&timeline=$dir/timeline.js"
  node scripts/video/mix.mjs --video "$dir/silent.mp4" --timeline "$dir/timeline.json" ${MUSIC:+--music "$MUSIC"} --out "$name.mp4"
  # A smaller cut for upload limits (GitHub, chat apps): 30 fps, stronger compression.
  ffmpeg -y -loglevel error -i "$name.mp4" -c:v libx264 -preset slow -crf 27 -r 30 -pix_fmt yuv420p \
    -c:a aac -b:a 128k -movflags +faststart "$name-small.mp4"
  if [[ -s "$dir/subs.srt" ]]; then cp "$dir/subs.srt" "$name.srt"; fi

  if [[ "$v" == en ]]; then
    gif "$dir/silent.mp4" 0 "$duration" 10 720 128 "$OUT/kitfold-launch.gif"
    # README cut: the grid, hiding a skill through OpenCode's own setting, every agent's switch.
    a=$(at "$dir/timeline.json" 18.0) b=$(at "$dir/timeline.json" 33.9)
    gif "$dir/silent.mp4" "$a" "$(echo "$b - $a" | bc)" 12 900 144 "$OUT/kitfold-demo.gif"
  fi
done

ls -lh "$OUT"
rm -rf "$(dirname "$WORK")"
