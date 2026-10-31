#!/usr/bin/env bash
# 视频 Skills 体检（macOS / Linux）
# 复刻 MiniMax Code 运行时的 skill 发现规则，列出实际可调用的技能并与 manifest.json 比对。
#
#   bash verify.sh [--data-dir <path>] [--json]

set -euo pipefail

DATA_DIR="${VIDEO_SKILLS_DATA_DIR:-$HOME/.minimax}"
JSON=0
while [ $# -gt 0 ]; do
  case "$1" in
    --data-dir) DATA_DIR="$2"; shift 2 ;;
    --json)     JSON=1; shift ;;
    -h|--help)  sed -n '2,5p' "$0"; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$DATA_DIR/skills"

name_of() {
  # 从 SKILL.md 的 frontmatter 取 name，取不到就用目录名
  local f="$1" d="$2"
  local n
  n="$(awk '/^---[[:space:]]*$/{c++; next} c==1 && /^name:[[:space:]]*/{sub(/^name:[[:space:]]*/,""); gsub(/^["'"'"']|["'"'"']$/,""); print; exit}' "$f" 2>/dev/null || true)"
  [ -n "$n" ] && printf '%s' "$n" || basename "$d"
}

desc_of() {
  local f="$1"
  awk '/^---[[:space:]]*$/{c++; next} c==1 && /^description:[[:space:]]*/{sub(/^description:[[:space:]]*/,""); gsub(/^["'"'"']|["'"'"']$/,""); print; exit}' "$f" 2>/dev/null || true
}

FOUND=()
declare -A FOUND_PATH

scan() {
  local dir="$1" is_top="$2"
  [ -d "$dir" ] || return 0
  if [ -f "$dir/SKILL.md" ]; then
    local d
    d="$(desc_of "$dir/SKILL.md")"
    if [ -n "$d" ]; then
      local n
      n="$(name_of "$dir/SKILL.md" "$dir")"
      FOUND+=("$n")
      FOUND_PATH["$n"]="$dir/SKILL.md"
    fi
    return 0
  fi
  local f
  for f in "$dir"/*; do
    [ -e "$f" ] || continue
    local base
    base="$(basename "$f")"
    case "$base" in
      .*|node_modules) continue ;;
    esac
    if [ -d "$f" ]; then
      scan "$f" 0
    elif [ "$is_top" = "1" ] && [ "${base##*.}" = "md" ]; then
      local d
      d="$(desc_of "$f")"
      if [ -n "$d" ]; then
        local n
        n="$(name_of "$f" "$dir")"
        FOUND+=("$n")
        FOUND_PATH["$n"]="$f"
      fi
    fi
  done
}

scan "$SKILLS_DIR" 1

# 与 manifest 比对
EXPECTED_COUNT=0
MISSING=""
PATH_MISSING=""
if [ -f "$SCRIPT_DIR/manifest.json" ] && command -v python3 >/dev/null 2>&1; then
  REPORT="$(python3 - "$SCRIPT_DIR/manifest.json" "$SKILLS_DIR" ${FOUND[@]+"${FOUND[@]}"} <<'PY'
import json, os, sys
m = json.load(open(sys.argv[1], encoding='utf-8'))
skills_dir = sys.argv[2]
found = set(sys.argv[3:])
expected, missing, path_missing = [], [], []
for g in m.get('groups', []):
    for s in g.get('skills', []):
        expected.append(s['name'])
        if s['name'] not in found:
            missing.append(s['name'])
        p = os.path.join(skills_dir, s['installedPath'])
        if not os.path.isdir(p):
            path_missing.append('%s -> %s' % (s['name'], p))
print('expected=%d' % len(expected))
print('missing=' + ','.join(missing))
print('paths=' + '; '.join(path_missing))
PY
)"
  EXPECTED_COUNT="$(printf '%s\n' "$REPORT" | sed -n 's/^expected=//p')"
  MISSING="$(printf '%s\n' "$REPORT" | sed -n 's/^missing=//p')"
  PATH_MISSING="$(printf '%s\n' "$REPORT" | sed -n 's/^paths=//p')"
fi

if [ "$JSON" = "1" ]; then
  printf '{"skillsDir":"%s","count":%s,"skills":[' "$SKILLS_DIR" "${#FOUND[@]}"
  for i in "${!FOUND[@]}"; do
    [ $i -gt 0 ] && printf ','
    printf '{"name":"%s","path":"%s"}' "${FOUND[$i]}" "${FOUND_PATH[${FOUND[$i]}]}"
  done
  printf '],"expected":%s,"missing":"%s","pathsMissing":"%s"}\n' \
    "${EXPECTED_COUNT:-0}" "$MISSING" "$PATH_MISSING"
  [ -z "$MISSING" ] && [ -z "$PATH_MISSING" ] && exit 0 || exit 1
fi

echo
echo "技能目录: $SKILLS_DIR"
echo "发现技能: ${#FOUND[@]} 个"
if [ "${EXPECTED_COUNT:-0}" -gt 0 ]; then
  if [ -z "$MISSING" ]; then
    echo "清单比对: $EXPECTED_COUNT/$EXPECTED_COUNT 全部就位"
  else
    echo "清单比对: 缺少 -> $MISSING"
  fi
fi
if [ -n "$PATH_MISSING" ]; then
  echo "落地路径缺失:"
  printf '%s\n' "$PATH_MISSING" | sed 's/; /\n  /g'
fi
echo
for n in "${FOUND[@]}"; do
  echo "  $n"
  echo "    ${FOUND_PATH[$n]}"
done
echo
[ -z "$MISSING" ] && [ -z "$PATH_MISSING" ] && exit 0 || exit 1
