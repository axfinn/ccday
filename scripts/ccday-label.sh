#!/bin/bash
# ccday-label.sh — 天气 + 节假日倒计时 → claude-hud customLine
# 项目: https://github.com/axfinn/ccday
#
# 配置（任选其一）:
#   ~/.ccday.conf 文件:
#     QWEATHER_KEY=your_key
#     QWEATHER_LOCATION=101010100   # 城市ID，北京=101010100
#   或环境变量: QWEATHER_KEY / QWEATHER_LOCATION

CONFIG_FILE="$HOME/.ccday.conf"
CLAUDE_HUD_CONFIG="$HOME/.claude/plugins/claude-hud/config.json"
HOLIDAYS_JSON="$(dirname "$0")/holidays.json"

# 加载配置
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

QWEATHER_KEY="${QWEATHER_KEY:-}"
QWEATHER_LOCATION="${QWEATHER_LOCATION:-101010100}"

# 用 python3 生成状态栏文本
LINE=$(/usr/bin/python3 - "$QWEATHER_KEY" "$QWEATHER_LOCATION" "$HOLIDAYS_JSON" <<'PYEOF'
import sys, json, datetime, random, urllib.request, urllib.error

key = sys.argv[1]
location = sys.argv[2]
holidays_file = sys.argv[3]

today = datetime.date.today()
parts = []

# ── 天气 ──────────────────────────────────────────────
weather_text = ""
if key:
    try:
        url = f"https://devapi.qweather.com/v7/weather/3d?location={location}&key={key}&lang=zh&unit=m"
        req = urllib.request.Request(url, headers={"User-Agent": "ccday/1.0"})
        with urllib.request.urlopen(req, timeout=4) as r:
            data = json.loads(r.read())
        if data.get("code") == "200":
            d = data["daily"][0]
            icon_map = {
                "晴": "☀️", "多云": "⛅", "阴": "☁️", "小雨": "🌧",
                "中雨": "🌧", "大雨": "⛈", "暴雨": "⛈", "雷阵雨": "⛈",
                "小雪": "🌨", "中雪": "❄️", "大雪": "❄️", "雾": "🌫",
                "霾": "😷", "沙尘": "🌪",
            }
            cond = d.get("textDay", "")
            icon = next((v for k, v in icon_map.items() if k in cond), "🌡")
            weather_text = f"{icon}{d['tempMax']}°/{d['tempMin']}°{cond}"
    except Exception:
        pass

if weather_text:
    parts.append(weather_text)

# ── 节假日 + 周末倒计时 ───────────────────────────────
try:
    with open(holidays_file, encoding="utf-8") as f:
        hdata = json.load(f)
    holidays = hdata.get("holidays", [])

    # 找下一个节假日
    next_holiday = None
    min_days = 9999
    for h in holidays:
        hdate = datetime.date.fromisoformat(h["date"])
        diff = (hdate - today).days
        if 0 <= diff < min_days:
            min_days = diff
            next_holiday = h

    if next_holiday:
        if min_days == 0:
            parts.append(f"{next_holiday['emoji']}今天{next_holiday['name']}!")
        else:
            parts.append(f"{next_holiday['emoji']}{next_holiday['name']}还有{min_days}天")
except Exception:
    pass

# ── 周末倒计时 ────────────────────────────────────────
weekday = today.weekday()  # 0=周一 ... 6=周日
if weekday == 5:
    parts.append("🏖周末快乐!")
elif weekday == 6:
    parts.append("🏖周末最后一天")
else:
    days_to_sat = 5 - weekday
    parts.append(f"🏖周末还有{days_to_sat}天")

# ── 出行灵感（每天固定一条，基于日期seed）────────────
# 周末 → 周边游 tips；节假日/平时 → 年度旅行计划 tips
try:
    with open(holidays_file, encoding="utf-8") as f:
        hdata = json.load(f)
    tips = hdata.get("travel_tips", [])
    month = today.month
    if 3 <= month <= 5:
        season = "spring"
    elif 6 <= month <= 8:
        season = "summer"
    elif 9 <= month <= 11:
        season = "autumn"
    else:
        season = "winter"

    is_weekend = weekday >= 5
    if is_weekend:
        # 周末 → 周边游（短途）
        pool = [t for t in tips if t.get("type") == "nearby" or t["season"] in (season, "all")]
        # 如果没有 nearby 标签，fallback 到 all
        nearby_pool = [t for t in tips if t.get("type") == "nearby"]
        if nearby_pool:
            pool = nearby_pool
        else:
            pool = [t for t in tips if t["season"] == "all"]
    else:
        # 平时/节假日 → 年度旅行计划（远途）
        pool = [t for t in tips if t.get("type") != "nearby" and t["season"] in (season, "all")]

    if not pool:
        pool = tips  # fallback

    random.seed(today.toordinal())
    tip = random.choice(pool)["tip"]
    if len(tip) > 28:
        tip = tip[:27] + "…"
    parts.append(tip)
except Exception:
    pass

print(" │ ".join(parts))
PYEOF
)

[ -z "$LINE" ] && exit 0

# 写入 claude-hud config.json
/usr/bin/python3 -c "
import json, sys, os
p = sys.argv[1]
os.makedirs(os.path.dirname(p), exist_ok=True)
try:
    with open(p) as f: cfg = json.load(f)
except Exception: cfg = {}
if not isinstance(cfg.get('display'), dict): cfg['display'] = {}
cfg['display']['customLine'] = sys.argv[2]
with open(p, 'w') as f: json.dump(cfg, f, ensure_ascii=False, indent=2)
" "$CLAUDE_HUD_CONFIG" "$LINE"
