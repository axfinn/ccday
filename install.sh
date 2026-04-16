#!/bin/bash
# install.sh — ccday 一键安装脚本
# 项目: https://github.com/axfinn/ccday
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.claude/scripts/ccday"
SKILLS_DIR="$HOME/.claude/skills"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
IS_MAC=false
[[ "$(uname)" == "Darwin" ]] && IS_MAC=true

echo "📦 安装 ccday..."

# 1. 复制脚本
mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/scripts/ccday-label.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/scripts/holidays.json" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/ccday-label.sh"
echo "✅ 脚本已安装到 $INSTALL_DIR"

# 2. 安装 skill
mkdir -p "$SKILLS_DIR"
cp "$SCRIPT_DIR/skills/ccday.md" "$SKILLS_DIR/"
echo "✅ Skill 已安装: /ccday"

# 3. 配置文件（仅在 HOME，不进项目）
if [ ! -f "$HOME/.ccday.conf" ]; then
    if $IS_MAC; then
        cat > "$HOME/.ccday.conf" <<'EOF'
# ccday 配置文件 — 此文件在 HOME 目录，不会进入项目仓库
# macOS 用户：系统天气自动生效，无需填写 API 配置
# 如需使用和风天气 API，参考 README 申请并填写以下配置：
# QWEATHER_API_HOST=xxxxxx.re.qweatherapi.com
# QWEATHER_KID=你的凭据ID
# QWEATHER_PROJECT_ID=你的项目ID
# QWEATHER_PRIVATE_KEY=~/.ccday-private.pem
QWEATHER_LOCATION=116.38,39.91
EOF
        echo "✅ 配置文件已创建: ~/.ccday.conf（macOS 无需额外配置）"
    else
        cat > "$HOME/.ccday.conf" <<'EOF'
# ccday 配置文件 — 此文件在 HOME 目录，不会进入项目仓库
# 申请和风天气免费 API: https://console.qweather.com
# 详细教程: 在 Claude Code 中输入 /ccday
QWEATHER_API_HOST=
QWEATHER_KID=
QWEATHER_PROJECT_ID=
QWEATHER_PRIVATE_KEY=~/.ccday-private.pem
QWEATHER_LOCATION=116.38,39.91
EOF
        echo "✅ 配置文件已创建: ~/.ccday.conf"
    fi
else
    echo "ℹ️  配置文件已存在: ~/.ccday.conf"
fi

# 4. 注入 statusLine 到 claude settings.json
if [ ! -f "$CLAUDE_SETTINGS" ]; then
    echo "⚠️  未找到 $CLAUDE_SETTINGS，请手动配置 statusLine（见 README）"
    exit 0
fi

if python3 -c "import json; d=json.load(open('$CLAUDE_SETTINGS')); exit(0 if 'statusLine' in d else 1)" 2>/dev/null; then
    echo "ℹ️  settings.json 已有 statusLine，跳过"
else
    python3 - "$CLAUDE_SETTINGS" "$INSTALL_DIR/ccday-label.sh" <<'PYEOF'
import json, sys
settings_path = sys.argv[1]
script_path = sys.argv[2]

with open(settings_path) as f:
    cfg = json.load(f)

hud_cmd = (
    f"bash -c '{script_path} 2>/dev/null; "
    "plugin_dir=$(ls -d \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null "
    "| awk -F/ \'{ print $(NF-1) \"\\t\" $0 }\' | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1 | cut -f2-); "
    "[ -n \"$plugin_dir\" ] && exec bun --env-file /dev/null \"${plugin_dir}src/index.ts\"'"
)

cfg["statusLine"] = {"padding": 0, "command": hud_cmd, "type": "command"}

with open(settings_path, 'w') as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)

print(f"✅ statusLine 已写入 {settings_path}")
PYEOF
fi

echo ""
echo "🎉 安装完成！"
echo ""
if $IS_MAC; then
    echo "macOS 用户直接重启 Claude Code 即可，系统天气自动生效。"
else
    echo "下一步："
    echo "  1. 在 Claude Code 中输入 /ccday 按向导申请和风天气 API"
    echo "  2. 重启 Claude Code"
fi
echo ""
echo "状态栏效果: 🌧14°小雨 │ 🔨劳动节还有15天 │ 🏖周末还有2天 │ 🌊 厦门鼓浪屿..."
