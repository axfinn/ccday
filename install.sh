#!/bin/bash
# install.sh — ccday 一键安装脚本
# 项目: https://github.com/axfinn/ccday
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.claude/scripts/ccday"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

echo "📦 安装 ccday..."

# 1. 复制脚本
mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/scripts/ccday-label.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/scripts/holidays.json" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/ccday-label.sh"
echo "✅ 脚本已安装到 $INSTALL_DIR"

# 2. 配置文件
if [ ! -f "$HOME/.ccday.conf" ]; then
    cat > "$HOME/.ccday.conf" <<'EOF'
# ccday 配置文件
# 和风天气 API Key（免费注册：https://dev.qweather.com）
QWEATHER_KEY=

# 城市 ID（北京=101010100，上海=101020100，广州=101280101，深圳=101280601）
# 查询城市ID: https://github.com/qwd/LocationList
QWEATHER_LOCATION=101010100
EOF
    echo "✅ 配置文件已创建: ~/.ccday.conf（请填入 QWEATHER_KEY）"
else
    echo "ℹ️  配置文件已存在: ~/.ccday.conf"
fi

# 3. 更新 claude settings.json — 注入 statusLine
if [ ! -f "$CLAUDE_SETTINGS" ]; then
    echo "⚠️  未找到 $CLAUDE_SETTINGS，请手动配置 statusLine（见 README）"
    exit 0
fi

# 检查是否已有 statusLine
if python3 -c "import json; d=json.load(open('$CLAUDE_SETTINGS')); exit(0 if 'statusLine' in d else 1)" 2>/dev/null; then
    echo "ℹ️  settings.json 已有 statusLine 配置，跳过（请手动合并，见 README）"
else
    python3 - "$CLAUDE_SETTINGS" "$INSTALL_DIR/ccday-label.sh" <<'PYEOF'
import json, sys
settings_path = sys.argv[1]
script_path = sys.argv[2]

with open(settings_path) as f:
    cfg = json.load(f)

# 尝试找 claude-hud 插件路径
hud_cmd = (
    f"bash -c '{script_path} 2>/dev/null; "
    "plugin_dir=$(ls -d \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null "
    "| awk -F/ \'{ print $(NF-1) \"\\t\" $0 }\' | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1 | cut -f2-); "
    "[ -n \"$plugin_dir\" ] && exec bun --env-file /dev/null \"${plugin_dir}src/index.ts\"'"
)

cfg["statusLine"] = {
    "padding": 0,
    "command": hud_cmd,
    "type": "command"
}

with open(settings_path, 'w') as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)

print(f"✅ statusLine 已写入 {settings_path}")
PYEOF
fi

echo ""
echo "🎉 安装完成！"
echo ""
echo "下一步："
echo "  1. 编辑 ~/.ccday.conf，填入 QWEATHER_KEY"
echo "  2. 重启 Claude Code"
echo "  3. 状态栏将显示: ☀️25°/15°晴 │ 🔨劳动节还有15天 │ 🏖周末还有2天 │ 🌸张家界四月云海最美"
echo ""
echo "获取和风天气免费 Key: https://dev.qweather.com"
