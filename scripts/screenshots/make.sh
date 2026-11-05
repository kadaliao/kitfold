#!/bin/bash
# Regenerate release screenshots from a fictional demo home.
#   scripts/screenshots/make.sh [en] [zh-Hans]      (default: en)
# English: full-size PNGs (3200×2000) go to build/screenshots/, README-sized JPEGs (1920×1200) to docs/assets/screenshots/.
# Chinese: the same under build/screenshots/zh-CN/ and docs/assets/screenshots/zh-CN/ (used by README.zh-CN.md).
set -euo pipefail
cd "$(dirname "$0")/../.."

WORK="$(mktemp -d)/kitfold-shots"
for lang in "${@:-en}"; do
  case "$lang" in
    en) OUT=build/screenshots DOCS=docs/assets/screenshots ;;
    zh-Hans) OUT=build/screenshots/zh-CN DOCS=docs/assets/screenshots/zh-CN ;;
    *) echo "unknown language $lang (en, zh-Hans)" >&2; exit 1 ;;
  esac
  DEMO="$WORK/$lang/home"
  KITFOLD_LANG="$lang" scripts/demo/make-demo-home.sh "$DEMO" >/dev/null
  for theme in dark light; do
    KITFOLD_LANG="$lang" scripts/lib/snapshot-app.sh "$DEMO" marketing "$theme" "$WORK/$lang/$theme"
  done
  mkdir -p "$OUT" "$DOCS"
  frame() {  # frame <name> <theme> <shot> <title> <subtitle> [overlay]
    local args=(--in "$WORK/$lang/$2/$3.png" --out "$OUT/$1.png" --theme "$2" --title "$4" --subtitle "$5")
    [[ -n "${6:-}" ]] && args+=(--overlay "$WORK/$lang/$2/$6.png")
    swift scripts/screenshots/frame.swift "${args[@]}" >/dev/null
    sips -Z 1920 -s format jpeg -s formatOptions 88 "$OUT/$1.png" --out "$DOCS/$1.jpg" >/dev/null
  }
  if [[ "$lang" == en ]]; then
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
  else
    frame 01-agents    dark  agent     "看清每个 Agent 实际加载了什么。" \
      "自己的目录、共享目录、插件，还有在设置里被关掉的技能，每一个都能追到来源。"
    frame 02-matrix    dark  matrix    "一张表，所有 Agent。" \
      "把技能给一个、几个或全部 Agent。每个格子都说明它是怎么到达的。"
    frame 03-review    dark  pending   "每处改动先预览，每次应用都能撤销。" \
      "写入磁盘之前先看 diff。有备份、前置检查和完整的历史记录。" review-sheet
    frame 04-skill     light skill     "每个技能在哪，一清二楚。" \
      "谁会用到它、各 Agent 从哪加载它、它有什么问题。"
    frame 05-profiles  light profile   "Profile 连同技能一起带上。" \
      "可复用的指令，写进各 Agent 自己的文件，每个 Profile 一个带标记的块。"
    frame 06-dashboard light dashboard "整套配置，一眼看全。" \
      "这台 Mac 上每个 Agent 的版本、上下文大小和健康状况。"
  fi
  echo "Screenshots ($lang): $OUT (full size), $DOCS (README)"
done
rm -rf "$(dirname "$WORK")"
