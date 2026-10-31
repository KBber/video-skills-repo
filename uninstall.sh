#!/usr/bin/env bash
# 卸载本合集安装的技能目录（macOS / Linux）
#   bash uninstall.sh [--data-dir <path>] [--force] [--keep-runtime]

set -euo pipefail

DATA_DIR="${VIDEO_SKILLS_DATA_DIR:-$HOME/.minimax}"
FORCE=0
KEEP_RUNTIME=0
while [ $# -gt 0 ]; do
  case "$1" in
    --data-dir)     DATA_DIR="$2"; shift 2 ;;
    --force)        FORCE=1; shift ;;
    --keep-runtime) KEEP_RUNTIME=1; shift ;;
    -h|--help)      sed -n '2,4p' "$0"; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$DATA_DIR/skills"
MANIFEST="$SCRIPT_DIR/manifest.json"

if [ ! -f "$MANIFEST" ]; then
  echo "找不到 manifest.json，无法确定要卸载的内容。" >&2
  exit 1
fi

# 每个技能的 installedPath 第一段 = 该技能独占的顶层目录
# 注意：Windows 的 Git Bash 里 python3 可能只是 Microsoft Store 的占位别名，
# 直接调用会失败，所以这里要真正跑一次 import json 验证。
PY=""
for cand in python3 python; do
  if command -v "$cand" >/dev/null 2>&1 && "$cand" -c "import json" >/dev/null 2>&1; then
    PY="$cand"
    break
  fi
done
if [ -z "$PY" ]; then
  echo "需要 Python 才能读取 manifest.json，请先安装 Python 3。" >&2
  exit 1
fi

TARGETS="$("$PY" - "$MANIFEST" "$SKILLS_DIR" <<'PY'
import json, os, sys
m = json.load(open(sys.argv[1], encoding='utf-8'))
skills_dir = sys.argv[2]
seen = set()
for g in m.get('groups', []):
    for s in g.get('skills', []):
        rel = s['installedPath'].replace('\\', '/').strip('/')
        if not rel:
            continue
        top = rel.split('/')[0]
        if top and top not in seen:
            seen.add(top)
            print(os.path.join(skills_dir, top))
PY
)"

echo
echo "将删除以下顶层目录（位于 $SKILLS_DIR 下）："
echo "$TARGETS" | sed 's/^/  /'
echo

if [ "$FORCE" -ne 1 ]; then
  read -r -p "确认删除？输入 yes 继续: " ans
  [ "$ans" = "yes" ] || { echo "已取消。"; exit 0; }
fi

echo "$TARGETS" | while IFS= read -r t; do
  [ -n "$t" ] || continue
  if [ -d "$t" ]; then
    rm -rf "$t" && echo "已删除 $t"
  fi
done

if [ "$KEEP_RUNTIME" -ne 1 ] && [ -d "$HOME/.chengfeng-videocut" ]; then
  echo
  echo "Video Cut Runtime 仍保留在 $HOME/.chengfeng-videocut"
  echo "如需一并删除：rm -rf \"$HOME/.chengfeng-videocut\""
fi

echo
echo "卸载完成。重开一个会话后技能列表会刷新。"
