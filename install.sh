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
cp "$SCRIPT_DIR/scripts/ccday-joke-gen.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/scripts/holidays.json" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/ccday-label.sh"
chmod +x "$INSTALL_DIR/ccday-joke-gen.sh"
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

# 出发地（用于计算旅行距离，默认北京）
HOME_LAT=39.91
HOME_LNG=116.38

# 旅行计划（可选）
# TRIP_NAME=目的地名称
# TRIP_LAT=目的地纬度
# TRIP_LNG=目的地经度
# TRIP_DATE=2026-05-01
# TRIP_TIPS="带防晒霜;穿舒适的鞋;早点出发"

# AI 段子（每天一次，会话结束自动生成）
CCDAY_AI_JOKE=1
CCDAY_TIP_ROTATE=5
CCDAY_AI_JOKE_ROTATE=20

# 下班时间（用于计算周末倒计时）
CCDAY_WORK_END=19:00

# 休息提醒
CCDAY_BREAK_INTERVAL=50   # 每隔 N 分钟提醒休息
CCDAY_BREAK_DURATION=10   # 休息时长 N 分钟（CONFIRM=1 时有效）
CCDAY_BREAK_CONFIRM=1     # 1=需要主动确认，0=定时自动消失
CCDAY_BREAK_START=09:00   # 提醒生效开始时间
CCDAY_BREAK_END=22:00     # 提醒生效结束时间

# 喝水提醒（设 0 关闭）
CCDAY_WATER_INTERVAL=60
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

# 出发地（用于计算旅行距离，默认北京）
HOME_LAT=39.91
HOME_LNG=116.38

# 旅行计划（可选）
# TRIP_NAME=目的地名称
# TRIP_LAT=目的地纬度
# TRIP_LNG=目的地经度
# TRIP_DATE=2026-05-01
# TRIP_TIPS="带防晒霜;穿舒适的鞋;早点出发"

# Tip/段子刷新频率（按会话次数）
CCDAY_AI_JOKE=1           # 启用 AI 生成段子
CCDAY_TIP_ROTATE=5        # 每 N 次会话随机换一条 tip
CCDAY_AI_JOKE_ROTATE=20   # 每 N 次会话用 AI 生成新段子

# 下班时间（用于计算周末倒计时）
CCDAY_WORK_END=19:00

# 休息提醒
CCDAY_BREAK_INTERVAL=50   # 每隔 N 分钟提醒休息
CCDAY_BREAK_DURATION=10   # 休息时长 N 分钟（CONFIRM=1 时有效）
CCDAY_BREAK_CONFIRM=1     # 1=需要主动确认，0=定时自动消失
CCDAY_BREAK_START=09:00   # 提醒生效开始时间
CCDAY_BREAK_END=22:00     # 提醒生效结束时间

# 喝水提醒（设 0 关闭）
CCDAY_WATER_INTERVAL=60
EOF
        echo "✅ 配置文件已创建: ~/.ccday.conf"
    fi
else
    echo "ℹ️  配置文件已存在: ~/.ccday.conf（跳过，不覆盖）"
fi

# 4. 注入 statusLine 到 claude settings.json
if [ ! -f "$CLAUDE_SETTINGS" ]; then
    echo "⚠️  未找到 $CLAUDE_SETTINGS，请手动配置 statusLine（见 README）"
else
    python3 - "$CLAUDE_SETTINGS" "$INSTALL_DIR/ccday-label.sh" <<'PYEOF'
import json, sys
settings_path, script_path = sys.argv[1], sys.argv[2]

with open(settings_path) as f:
    cfg = json.load(f)

import os
home = os.path.expanduser("~")
# 用 $HOME 变量而不是硬编码路径，跨用户可用
cmd = "bash $HOME/.claude/scripts/ccday/ccday-label.sh"

if "statusLine" in cfg:
    # 如果已有但路径是旧的硬编码路径，也更新
    existing = cfg["statusLine"].get("command", "")
    if "ccday-label.sh" in existing and existing != cmd:
        cfg["statusLine"]["command"] = cmd
        with open(settings_path, "w") as f:
            json.dump(cfg, f, ensure_ascii=False, indent=2)
        print(f"✅ statusLine 路径已更新为 $HOME 变量形式")
    else:
        print("ℹ️  settings.json 已有 statusLine，跳过")
else:
    cfg["statusLine"] = {
        "padding": 0,
        "command": cmd,
        "type": "command"
    }
    with open(settings_path, "w") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)
    print(f"✅ statusLine 已写入 {settings_path}")
PYEOF
fi

# 5. 注入 Stop hook 到 claude settings.json
if [ -f "$CLAUDE_SETTINGS" ]; then
    python3 - "$CLAUDE_SETTINGS" "$INSTALL_DIR/ccday-joke-gen.sh" <<'PYEOF'
import json, sys
settings_path, gen_script = sys.argv[1], sys.argv[2]

with open(settings_path) as f:
    cfg = json.load(f)

hook_cmd = "bash $HOME/.claude/scripts/ccday/ccday-joke-gen.sh"
hooks = cfg.setdefault("hooks", {})
stop_hooks = hooks.setdefault("Stop", [])

# 检查是否已存在（匹配 ccday-joke-gen.sh 即可，不管路径形式）
already = any(
    "ccday-joke-gen.sh" in h.get("command", "")
    for entry in stop_hooks
    for h in entry.get("hooks", [])
)

if already:
    print("ℹ️  Stop hook 已存在，跳过")
else:
    stop_hooks.append({
        "matcher": "",
        "hooks": [{"type": "command", "command": hook_cmd}]
    })
    with open(settings_path, "w") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)
    print(f"✅ Stop hook 已写入 {settings_path}")
PYEOF
fi

echo ""
echo "🎉 安装完成！"
echo ""
if $IS_MAC; then
    echo "macOS 用户直接重启 Claude Code 即可，系统天气自动生效。"
else
    echo "下一步："
    echo "  1. 编辑 ~/.ccday.conf，填入和风天气 API 配置"
    echo "  2. 重启 Claude Code"
    echo ""
    echo "  申请免费 API: https://console.qweather.com"
    echo "  详细教程: 在 Claude Code 中输入 /ccday"
fi
echo ""
echo "状态栏效果:"
echo "  ☁️ 16° 阴  🔨 劳动节·15天  🏖 2天  🤖 让AI写段子，我摸鱼！"
echo "  📊 ctx 53%  │  🗺️ 目的地 22km·2天后  │  💰72%"
