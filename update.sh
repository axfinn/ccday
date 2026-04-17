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

# 拉取最新代码
cd "$SCRIPT_DIR"
git fetch origin master --quiet

LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/master)

if [ "$LOCAL" = "$REMOTE" ]; then
    echo "✅ 已是最新版本${CURRENT:+（$CURRENT）}"
    exit 0
fi

echo "📦 发现新版本，正在更新..."
git pull origin master --quiet

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
NEW_VERSION=$(grep '^VERSION=' "$SCRIPT_DIR/install.sh" | head -1 | cut -d= -f2 | tr -d '"')
[ -n "$NEW_VERSION" ] && echo "$NEW_VERSION" > "$VERSION_FILE"

echo "✅ 更新完成${NEW_VERSION:+（$NEW_VERSION）}"
echo "   重启 Claude Code 生效"
