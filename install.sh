#!/usr/bin/env bash
# 视频 Skills 一键部署器（macOS / Linux）
#
#   curl -fsSL https://raw.githubusercontent.com/KBber/video-skills-repo/main/install.sh | bash
#   或本地： bash install.sh
#
# 可用环境变量：
#   VIDEO_SKILLS_REPO     仓库地址，默认 KBber/video-skills-repo
#   VIDEO_SKILLS_BRANCH   分支，默认 main
#   VIDEO_SKILLS_DATA_DIR 数据目录，默认 ~/.minimax
#   VIDEO_SKILLS_TOKEN    私有仓库令牌（可选）
#   VIDEO_SKILLS_TARBALL_URL 直接指定仓库 tarball 地址（内网镜像 / 离线部署）
# 参数：--skip-deps / --skip-runtime / --data-dir <path> / --repo <owner/name>

set -euo pipefail

REPO="${VIDEO_SKILLS_REPO:-KBber/video-skills-repo}"
BRANCH="${VIDEO_SKILLS_BRANCH:-main}"
DATA_DIR="${VIDEO_SKILLS_DATA_DIR:-$HOME/.minimax}"
SKIP_DEPS=0
SKIP_RUNTIME=0

while [ $# -gt 0 ]; do
  case "$1" in
    --skip-deps)    SKIP_DEPS=1; shift ;;
    --skip-runtime) SKIP_RUNTIME=1; shift ;;
    --data-dir)     DATA_DIR="$2"; shift 2 ;;
    --repo)         REPO="$2"; shift 2 ;;
    --branch)       BRANCH="$2"; shift 2 ;;
    -h|--help)      sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done

SKILLS_DIR="$DATA_DIR/skills"
REPO_ROOT=""
TMPDIR_REPO=""

step() { printf '[%-4s] %s  %s\n' "$1" "$2" "$3"; }
ok()   { step OK   "$1" "$2"; }
warn() { step WARN "$1" "$2"; }
fail() { step FAIL "$1" "$2"; }

# 递归数文件。不用 find：Windows 的 Git Bash 里 find 可能命中 system32\find.exe（文本搜索工具）
count_files() {
  local dir="$1" n=0 e
  for e in "$dir"/*; do
    [ -e "$e" ] || continue
    if [ -d "$e" ]; then
      n=$((n + $(count_files "$e")))
    else
      n=$((n + 1))
    fi
  done
  printf '%s' "$n"
}

echo
echo "=== 视频 Skills 一键部署 ==="
echo "数据目录: $DATA_DIR"
echo "仓库:     $REPO ($BRANCH)"
echo

# ---------- 0. 定位仓库内容 ----------
# 只有当脚本本身是一个真实文件、且同目录下同时存在 skills/ 与 manifest.json 时，
# 才算「本地模式」；`curl ... | bash` 这种管道执行一律走远程模式。
SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
if [ -n "$SCRIPT_DIR" ] && [ -d "$SCRIPT_DIR/skills" ] && [ -f "$SCRIPT_DIR/manifest.json" ]; then
  REPO_ROOT="$SCRIPT_DIR"
  ok "获取仓库内容" "本地模式: $REPO_ROOT"
else
  step INFO "获取仓库内容" "远程模式：从 GitHub 下载 $REPO@$BRANCH"
  TMPDIR_REPO="$(mktemp -d)"
  trap 'rm -rf "$TMPDIR_REPO"' EXIT
  if [ -n "${VIDEO_SKILLS_TARBALL_URL:-}" ]; then
    TAR_URL="$VIDEO_SKILLS_TARBALL_URL"
  else
    TAR_URL="https://codeload.github.com/$REPO/tar.gz/refs/heads/$BRANCH"
  fi
  TOKEN="${VIDEO_SKILLS_TOKEN:-${GITHUB_TOKEN:-}}"
  if [ -n "$TOKEN" ]; then
    curl -fsSL -H "Authorization: token $TOKEN" "$TAR_URL" | tar -xz -C "$TMPDIR_REPO"
  else
    curl -fsSL "$TAR_URL" | tar -xz -C "$TMPDIR_REPO"
  fi
  # 取解压后的仓库根：优先含 skills/ 且含 manifest.json 的那一层
  # （GitHub 的归档会多套一层 <repo>-<branch>/，镜像站可能直接是仓库根，两种都要认）
  REPO_ROOT=""
  for d in "$TMPDIR_REPO" "$TMPDIR_REPO"/*/; do
    d="${d%/}"
    if [ -d "$d/skills" ] && [ -f "$d/manifest.json" ]; then
      REPO_ROOT="$d"
      break
    fi
  done
  if [ -z "$REPO_ROOT" ]; then
    for d in "$TMPDIR_REPO"/*/; do
      d="${d%/}"
      if [ -d "$d/skills" ]; then
        REPO_ROOT="$d"
        break
      fi
    done
  fi
  [ -n "$REPO_ROOT" ] || { fail "获取仓库内容" "解压后未找到仓库目录"; exit 1; }
  ok "获取仓库内容" "已解压到 $REPO_ROOT"
fi

if [ ! -d "$REPO_ROOT/skills" ]; then
  fail "校验仓库结构" "缺少 skills 目录: $REPO_ROOT/skills"
  exit 1
fi

# ---------- 1. 复制 ----------
mkdir -p "$SKILLS_DIR"
for group in skills plugins; do
  [ -d "$REPO_ROOT/$group" ] || continue
  for item in "$REPO_ROOT/$group"/*/; do
    [ -d "$item" ] || continue
    name="$(basename "$item")"
    mkdir -p "$SKILLS_DIR/$name"
    cp -R "$item." "$SKILLS_DIR/$name/"
    n="$(count_files "$SKILLS_DIR/$name")"
    ok "复制 $name" "$n 个文件 -> $SKILLS_DIR/$name"
  done
done

# ---------- 2. 体检 ----------
if [ -f "$REPO_ROOT/verify.sh" ]; then
  if bash "$REPO_ROOT/verify.sh" --data-dir "$DATA_DIR" >/dev/null 2>&1; then
    ok "技能体检" "清单内技能全部就位"
  else
    warn "技能体检" "有缺失项，运行 verify.sh 查看详情"
  fi
fi

# ---------- 3. 基础依赖 ----------
if [ "$SKIP_DEPS" -eq 0 ]; then
  if command -v node >/dev/null 2>&1; then
    NV="$(node --version)"; MAJOR="${NV#v}"; MAJOR="${MAJOR%%.*}"
    if [ "$MAJOR" -ge 22 ]; then ok "Node.js" "$NV"; else warn "Node.js" "$NV 低于 22，HyperFrames 需升级"; fi
  else
    fail "Node.js" "未安装，HyperFrames 需要 >= 22"
  fi

  if command -v ffmpeg >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1; then
    ok "FFmpeg" "$(ffmpeg -version 2>&1 | head -1)"
  else
    fail "FFmpeg" "未找到 ffmpeg / ffprobe（brew install ffmpeg）"
  fi

  if command -v python3 >/dev/null 2>&1; then
    VU="$SKILLS_DIR/video-use"
    if [ ! -x "$VU/.venv/bin/python" ]; then
      echo "  · 为 video-use 创建虚拟环境（首次约 1-3 分钟）..."
      python3 -m venv "$VU/.venv"
    fi
    if [ -x "$VU/.venv/bin/python" ]; then
      "$VU/.venv/bin/python" -m pip install --quiet --upgrade pip
      if "$VU/.venv/bin/python" -m pip install --quiet -e "$VU"; then
        if "$VU/.venv/bin/python" -c "import requests,numpy,librosa,matplotlib,PIL" 2>/dev/null; then
          ok "video-use 依赖" "venv: $VU/.venv/bin/python"
        else
          warn "video-use 依赖" "部分依赖导入失败，可稍后手动 pip install -e"
        fi
      else
        fail "video-use 依赖" "pip install -e 失败"
      fi
    else
      fail "video-use 依赖" "venv 创建失败"
    fi
  else
    fail "Python" "未安装，video-use 需要 >= 3.10"
  fi
fi

# ---------- 4. Bun + Video Cut Runtime ----------
if [ "$SKIP_RUNTIME" -eq 0 ]; then
  BUN_BIN="$HOME/.bun/bin/bun"
  if ! command -v bun >/dev/null 2>&1 && [ ! -x "$BUN_BIN" ]; then
    echo "  · 安装 Bun ..."
    curl -fsSL https://bun.sh/install | bash >/dev/null 2>&1 || true
    [ -x "$BUN_BIN" ] && export PATH="$HOME/.bun/bin:$PATH"
  fi
  if command -v bun >/dev/null 2>&1 || [ -x "$BUN_BIN" ]; then
    ok "Bun" "$( (bun --version 2>/dev/null || "$BUN_BIN" --version) )"
  else
    fail "Bun" "未能安装 Bun，Video Cut Runtime 将无法激活"
  fi

  ENSURE="$SKILLS_DIR/chengfeng-videocut/scripts/ensure-runtime.cjs"
  if [ -f "$ENSURE" ]; then
    echo "  · 激活 chengfeng-videocut Runtime ..."
    if node "$ENSURE" --install-if-missing --json >/dev/null 2>&1; then
      ok "Video Cut Runtime" "已安装并激活"
    else
      fail "Video Cut Runtime" "安装失败，运行 doctor 查看详情"
    fi
  else
    fail "Video Cut Runtime" "找不到 $ENSURE"
  fi
fi

echo
echo "完成。下一步："
echo "  1. 重开一个会话 —— 技能目录在会话启动时扫描，新装技能才可调用"
echo "  2. 配密钥：video-use 需要 ELEVENLABS_API_KEY（写入 $SKILLS_DIR/video-use/.env）"
echo "             videocut 需要火山引擎 key：node '<插件根>/scripts/videocut-cli.cjs' config set transcription.apiKey <key>"
echo "  3. 随时体检：bash verify.sh"
echo
