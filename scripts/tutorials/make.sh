#!/bin/bash
# Regenerate the tutorials' screenshots from the fictional demo home, in English and Chinese.
#   scripts/tutorials/make.sh
# JPEGs go to docs/tutorials/images/en/ and docs/tutorials/images/zh-CN/.
set -euo pipefail
cd "$(dirname "$0")/../.."

WORK="$(mktemp -d)/kitfold-tutorial"
for lang in en zh-Hans; do
  folder=en
  [[ "$lang" == zh-Hans ]] && folder=zh-CN
  DEMO="$WORK/$lang/home"
  # The demo's history is written in the same language as the app.
  KITFOLD_LANG="$lang" scripts/demo/make-demo-home.sh "$DEMO" >/dev/null
  KITFOLD_LANG="$lang" scripts/lib/snapshot-app.sh "$DEMO" tutorial light "$WORK/$lang/shots" 1280x800
  OUT="docs/tutorials/images/$folder"
  mkdir -p "$OUT"
  for f in "$WORK/$lang/shots"/*.png; do
    sips -Z 1600 -s format jpeg -s formatOptions 82 "$f" --out "$OUT/$(basename "${f%.png}").jpg" >/dev/null
  done
  echo "Tutorial screenshots ($lang): $OUT"
done
rm -rf "$(dirname "$WORK")"
