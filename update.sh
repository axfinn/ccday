#!/bin/bash
# update.sh — ccday 一键更新脚本
# 用法: bash update.sh
# 项目: https://github.com/axfinn/ccday

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.claude/scripts/ccday"
VERSION_FILE="$HOME/.ccday-version"

echo "🔄 检查 ccday 更新..."

# 读取当前版本
CURRENT=""
[ -f "$VERSION_FILE" ] && CURRENT=$(cat "$VERSION_FILE")

REPO_VERSION=$(grep '^VERSION=' "$SCRIPT_DIR/install.sh" | head -1 | cut -d= -f2 | tr -d '"')

# 拉取最新代码
cd "$SCRIPT_DIR"
git fetch origin master --quiet 2>/dev/null || echo "⚠️  拉取远端失败，仅用本地代码"

LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/master 2>/dev/null || echo "$LOCAL")

if [ "$LOCAL" != "$REMOTE" ]; then
    # 远端有新提交：先确认不会覆盖本地未推送的改动
    if [ -n "$(git status --porcelain)" ]; then
        echo "⚠️  工作区有未提交的改动，跳过 git pull（只重装当前代码）"
    elif ! git merge-base --is-ancestor HEAD origin/master 2>/dev/null; then
        echo "⚠️  本地有未推送的提交，跳过 git pull（只重装当前代码）"
    else
        echo "📦 发现远端新版本，正在拉取..."
        git pull origin master --quiet
        REPO_VERSION=$(grep '^VERSION=' "$SCRIPT_DIR/install.sh" | head -1 | cut -d= -f2 | tr -d '"')
    fi
fi

# 已安装版本与仓库版本一致，且脚本内容也没变，才算真的最新
NEED_INSTALL=false
if [ "$CURRENT" != "$REPO_VERSION" ]; then
    NEED_INSTALL=true
else
    for f in ccday-label.sh ccday-joke-gen.sh holidays.json; do
        if ! cmp -s "$SCRIPT_DIR/scripts/$f" "$INSTALL_DIR/$f"; then
            NEED_INSTALL=true
            break
        fi
    done
fi

if ! $NEED_INSTALL; then
    echo "✅ 已是最新版本${CURRENT:+（$CURRENT）}"
    exit 0
fi

echo "📦 正在更新已安装的脚本${REPO_VERSION:+（$CURRENT → $REPO_VERSION）}..."
mkdir -p "$INSTALL_DIR"

# 更新脚本和 skill（不覆盖用户配置）
cp "$SCRIPT_DIR/scripts/ccday-label.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/scripts/ccday-joke-gen.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/scripts/holidays.json" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/ccday-label.sh"
chmod +x "$INSTALL_DIR/ccday-joke-gen.sh"

SKILLS_DIR="$HOME/.claude/skills"
mkdir -p "$SKILLS_DIR/ccday"
rm -f "$SKILLS_DIR/ccday.md"   # 清理旧版单文件形式
cp "$SCRIPT_DIR/skills/ccday.md" "$SKILLS_DIR/ccday/SKILL.md"

# 记录新版本
[ -n "$REPO_VERSION" ] && echo "$REPO_VERSION" > "$VERSION_FILE"

# 检查 settings.json 里的挂载点是否齐全
# 从早期版本升级的用户可能缺 Stop hook（v0.3 才引入），update 不注入配置，提示跑 install
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
if [ -f "$CLAUDE_SETTINGS" ]; then
    python3 - "$CLAUDE_SETTINGS" <<'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as f:
        cfg = json.load(f)
except Exception:
    sys.exit(0)

missing = []
if "ccday-label.sh" not in cfg.get("statusLine", {}).get("command", ""):
    missing.append("statusLine（状态栏）")
if not any("ccday-joke-gen.sh" in h.get("command", "")
           for e in cfg.get("hooks", {}).get("Stop", [])
           for h in e.get("hooks", [])):
    missing.append("Stop hook（tip 轮换）")

if missing:
    print("⚠️  settings.json 缺少: " + "、".join(missing))
    print("   跑一次 bash install.sh 补上（不会覆盖 ~/.ccday.conf）")
PYEOF
fi

echo "✅ 更新完成${REPO_VERSION:+（$REPO_VERSION）}"
echo "   重启 Claude Code 生效"
