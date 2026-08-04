#!/bin/bash
# install.sh — ccday 一键安装脚本
# 项目: https://github.com/axfinn/ccday
set -e

VERSION="v0.6.5"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.claude/scripts/ccday"
SKILLS_DIR="$HOME/.claude/skills"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
IS_MAC=false
[[ "$(uname)" == "Darwin" ]] && IS_MAC=true

echo "📦 安装 ccday $VERSION..."

# 1. 复制脚本
mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/scripts/ccday-label.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/scripts/ccday-joke-gen.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/scripts/ccday-billing.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/scripts/holidays.json" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/ccday-label.sh"
chmod +x "$INSTALL_DIR/ccday-joke-gen.sh"
chmod +x "$INSTALL_DIR/ccday-billing.sh"
echo "✅ 脚本已安装到 $INSTALL_DIR"

# 1.1 探测 billing 插件是否可用（探测不到不算错误，只是不显示）
if bash "$INSTALL_DIR/ccday-billing.sh" 2>/dev/null | grep -q .; then
    echo "✅ 用量插件可用: $(bash "$INSTALL_DIR/ccday-billing.sh" 2>/dev/null | head -1)"
else
    echo "ℹ️  用量插件未启用（未探测到 token/接口，状态栏不显示 💰）"
    echo "   诊断: bash $INSTALL_DIR/ccday-billing.sh --check"
fi

# 2. 安装 skill（目录结构：~/.claude/skills/ccday/skill.md）
mkdir -p "$SKILLS_DIR/ccday"
rm -f "$SKILLS_DIR/ccday.md"          # 清理旧版单文件形式
cp "$SCRIPT_DIR/skills/ccday.md" "$SKILLS_DIR/ccday/SKILL.md"
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

# 出发地（旅行距离 + 🎒周末出行灵感的目的地都按此坐标算，默认北京）
# 已内置城市圈：上海/北京/广州/深圳/杭州/成都/武汉/西安/南京/重庆
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

# 下班倒计时（弹性工作制：打卡窗口内首次用户活动记为上班，下班=上班+工时）
# macOS 用 pmset -g log 取真实首次活动；其他平台用状态栏首次刷新时刻
CCDAY_OFFWORK=1           # 1=显示下班倒计时，0=隐藏
CCDAY_WORK_PUNCH=1        # 1=按首次用户活动打卡（默认），0=用固定 WORK_START/END
CCDAY_WORK_HOURS=9        # 打卡模式工时（默认 9 小时）
CCDAY_PUNCH_START=06:00   # 打卡有效窗口开始
CCDAY_PUNCH_END=12:00     # 打卡有效窗口结束
CCDAY_PUNCH_SHOW=1        # 1=倒计时带上 (10:22→19:22)

# 固定上下班时间（PUNCH=0 或当天未打卡时生效，支持跨天班）
CCDAY_WORK_START=10:00
CCDAY_WORK_END=19:30

# 休息提醒
CCDAY_BREAK_INTERVAL=50   # 每隔 N 分钟提醒休息
CCDAY_BREAK_DURATION=10   # 休息时长 N 分钟（CONFIRM=1 时有效）
CCDAY_BREAK_CONFIRM=1     # 1=需要主动确认，0=定时自动消失
CCDAY_BREAK_START=09:00   # 提醒生效开始时间
CCDAY_BREAK_END=22:00     # 提醒生效结束时间

# 喝水提醒（设 0 关闭）
CCDAY_WATER_INTERVAL=60

# 饭点提醒（留空关闭）
CCDAY_LUNCH=12:00
CCDAY_DINNER=18:00
CCDAY_MEAL_WINDOW=30      # 到点后持续显示 N 分钟

# 用量/余额插件（探测不到 token 或接口就自动不显示，无需手动关）
CCDAY_BILLING=1           # 1=启用 💰 用量，0=关闭
CCDAY_BILLING_BUDGET=0    # 每日预算（元），0=用接口返回的 daily_limit
CCDAY_BILLING_FORMAT=auto # auto|percent|remain|used|balance|full
CCDAY_BILLING_POOL=0      # 1=额外显示团队池占用 🏊
CCDAY_BILLING_TTL=300     # 成功结果缓存秒数
CCDAY_BILLING_FAIL_TTL=1800 # 请求失败后静默秒数，避免反复打不通的接口
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

# 出发地（旅行距离 + 🎒周末出行灵感的目的地都按此坐标算，默认北京）
# 已内置城市圈：上海/北京/广州/深圳/杭州/成都/武汉/西安/南京/重庆
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

# 下班倒计时（弹性工作制：打卡窗口内首次用户活动记为上班，下班=上班+工时）
# macOS 用 pmset -g log 取真实首次活动；其他平台用状态栏首次刷新时刻
CCDAY_OFFWORK=1           # 1=显示下班倒计时，0=隐藏
CCDAY_WORK_PUNCH=1        # 1=按首次用户活动打卡（默认），0=用固定 WORK_START/END
CCDAY_WORK_HOURS=9        # 打卡模式工时（默认 9 小时）
CCDAY_PUNCH_START=06:00   # 打卡有效窗口开始
CCDAY_PUNCH_END=12:00     # 打卡有效窗口结束
CCDAY_PUNCH_SHOW=1        # 1=倒计时带上 (10:22→19:22)

# 固定上下班时间（PUNCH=0 或当天未打卡时生效，支持跨天班）
CCDAY_WORK_START=10:00
CCDAY_WORK_END=19:30

# 休息提醒
CCDAY_BREAK_INTERVAL=50   # 每隔 N 分钟提醒休息
CCDAY_BREAK_DURATION=10   # 休息时长 N 分钟（CONFIRM=1 时有效）
CCDAY_BREAK_CONFIRM=1     # 1=需要主动确认，0=定时自动消失
CCDAY_BREAK_START=09:00   # 提醒生效开始时间
CCDAY_BREAK_END=22:00     # 提醒生效结束时间

# 喝水提醒（设 0 关闭）
CCDAY_WATER_INTERVAL=60

# 饭点提醒（留空关闭）
CCDAY_LUNCH=12:00
CCDAY_DINNER=18:00
CCDAY_MEAL_WINDOW=30      # 到点后持续显示 N 分钟

# 用量/余额插件（探测不到 token 或接口就自动不显示，无需手动关）
CCDAY_BILLING=1           # 1=启用 💰 用量，0=关闭
CCDAY_BILLING_BUDGET=0    # 每日预算（元），0=用接口返回的 daily_limit
CCDAY_BILLING_FORMAT=auto # auto|percent|remain|used|balance|full
CCDAY_BILLING_POOL=0      # 1=额外显示团队池占用 🏊
CCDAY_BILLING_TTL=300     # 成功结果缓存秒数
CCDAY_BILLING_FAIL_TTL=1800 # 请求失败后静默秒数，避免反复打不通的接口
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

# 6. 记录版本号
echo "$VERSION" > "$HOME/.ccday-version"

echo ""
echo "🎉 安装完成！（$VERSION）"
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
echo "  ☁️ 16° 阴  🔨 劳动节·15天  🏖 2天  🕔 下班 3h45m·60%  🧘 站起来伸个懒腰!  💧 喝杯水!"
echo "  📊 ctx 53%  │  🗺️ 目的地 22km·2天后  │  💰余214¥  │  📝3 ✓5"
echo ""
echo "更新方式: bash update.sh"
