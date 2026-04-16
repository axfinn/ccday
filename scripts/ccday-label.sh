#!/bin/bash
# ccday-label.sh — 天气 + 节假日倒计时 → claude-hud customLine
# 项目: https://github.com/axfinn/ccday
#
# 配置文件（任选其一，均在 HOME 目录，不进入项目）:
#   ~/.ccday.conf / ~/.ccday.env  — shell 格式 KEY=VALUE
#   ~/.ccday.yaml                 — YAML 格式
#
# 配置项:
#   QWEATHER_API_HOST   和风天气 API Host（控制台-设置）
#   QWEATHER_KID        凭据ID
#   QWEATHER_PROJECT_ID 项目ID
#   QWEATHER_PRIVATE_KEY 私钥路径（默认 ~/.ccday-private.pem）
#   QWEATHER_LOCATION   经纬度或城市ID（默认 116.38,39.91）

CLAUDE_HUD_CONFIG="$HOME/.claude/plugins/claude-hud/config.json"
HOLIDAYS_JSON="$(dirname "$0")/holidays.json"

# 加载配置：优先 .ccday.conf，其次 .ccday.env，最后 .ccday.yaml
for f in "$HOME/.ccday.conf" "$HOME/.ccday.env"; do
    [ -f "$f" ] && source "$f" && break
done
# YAML 支持（简单 key: value 格式）
if [ -z "$QWEATHER_API_HOST" ] && [ -f "$HOME/.ccday.yaml" ]; then
    eval "$(grep -E '^\s*\w+\s*:' "$HOME/.ccday.yaml" | sed 's/\s*:\s*/=/' | sed 's/^/export /')"
fi

QWEATHER_API_HOST="${QWEATHER_API_HOST:-}"
QWEATHER_KID="${QWEATHER_KID:-}"
QWEATHER_PROJECT_ID="${QWEATHER_PROJECT_ID:-}"
QWEATHER_PRIVATE_KEY="${QWEATHER_PRIVATE_KEY:-$HOME/.ccday-private.pem}"
QWEATHER_LOCATION="${QWEATHER_LOCATION:-121.47,31.23}"  # 默认上海

LINE=$(/usr/bin/python3 - \
  "$QWEATHER_API_HOST" "$QWEATHER_KID" "$QWEATHER_PROJECT_ID" \
  "$QWEATHER_PRIVATE_KEY" "$QWEATHER_LOCATION" "$HOLIDAYS_JSON" <<'PYEOF'
import sys, json, datetime, random, urllib.request, base64, time, os, platform, gzip as gzipmod
from cryptography.hazmat.primitives.serialization import load_pem_private_key

api_host  = sys.argv[1]
kid       = sys.argv[2]
sub       = sys.argv[3]
key_path  = os.path.expanduser(sys.argv[4])
location  = sys.argv[5]
holidays_file = sys.argv[6]

today = datetime.date.today()
parts = []

# ── 天气 ──────────────────────────────────────────────
def make_jwt():
    try:
        with open(key_path, "rb") as f:
            pk = load_pem_private_key(f.read(), password=None)
        def b64u(d):
            if isinstance(d, str): d = d.encode()
            return base64.urlsafe_b64encode(d).rstrip(b"=").decode()
        now = int(time.time())
        hdr = json.dumps({"alg":"EdDSA","kid":kid}, separators=(',',':'))
        pld = json.dumps({"sub":sub,"iat":now-30,"exp":now+3600}, separators=(',',':'))
        msg = f"{b64u(hdr)}.{b64u(pld)}"
        sig = pk.sign(msg.encode())
        return f"{msg}.{b64u(sig)}"
    except Exception:
        return None

def fetch_weather_api():
    """和风天气 JWT 方式"""
    if not (api_host and kid and sub):
        return None
    jwt = make_jwt()
    if not jwt:
        return None
    try:
        url = f"https://{api_host}/v7/weather/now?location={location}&lang=zh"
        req = urllib.request.Request(url, headers={
            "Authorization": f"Bearer {jwt}",
            "Accept-Encoding": "gzip",
        })
        with urllib.request.urlopen(req, timeout=5) as r:
            body = r.read()
            if r.headers.get("Content-Encoding") == "gzip":
                body = gzipmod.decompress(body)
        d = json.loads(body).get("now", {})
        if not d:
            return None
        icon_map = {
            "晴":"☀️ ","多云":"⛅ ","阴":"☁️ ","小雨":"🌧 ","中雨":"🌧 ",
            "大雨":"⛈ ","暴雨":"⛈ ","雷阵雨":"⛈ ","小雪":"🌨 ","中雪":"❄️ ",
            "大雪":"❄️ ","雾":"🌫 ","霾":"😷 ","沙尘":"🌪 ",
        }
        cond = d.get("text","")
        icon = next((v for k,v in icon_map.items() if k in cond), "🌡 ")
        return f"{icon}{d['temp']}° {cond}"
    except Exception:
        return None

def fetch_weather_mac():
    """macOS 系统天气（WeatherKit via weatherd plist）"""
    try:
        import subprocess, plistlib
        # 读 WeatherKit 缓存 plist
        result = subprocess.run(
            ["defaults", "read", "com.apple.weather", "WeatherCurrentConditions"],
            capture_output=True, text=True, timeout=3
        )
        if result.returncode != 0:
            return None
        # 尝试解析 JSON 格式
        data = json.loads(result.stdout)
        temp = round(data.get("temperature", {}).get("value", 0))
        cond_code = data.get("conditionCode", "")
        cond_map = {
            "Clear":"☀️ 晴","MostlyClear":"🌤 晴","PartlyCloudy":"⛅ 多云",
            "MostlyCloudy":"☁️ 多云","Cloudy":"☁️ 阴","Drizzle":"🌦 小雨",
            "Rain":"🌧 雨","HeavyRain":"⛈ 大雨","Thunderstorm":"⛈ 雷雨",
            "Snow":"🌨 雪","Sleet":"🌨 雨夹雪","Fog":"🌫 雾","Haze":"😷 霾",
            "Windy":"💨 大风","Breezy":"🌬 微风",
        }
        desc = cond_map.get(cond_code, f"🌡{cond_code}")
        return f"{desc}{temp}°"
    except Exception:
        pass
    try:
        # 备用：wttr.in 本地查询
        req = urllib.request.Request(
            "https://wttr.in/?format=%t+%C&lang=zh",
            headers={"User-Agent": "curl/7.81.0"}
        )
        with urllib.request.urlopen(req, timeout=4) as r:
            text = r.read().decode().strip()
        return f"🌡{text}"
    except Exception:
        return None

is_mac = platform.system() == "Darwin"
weather_text = fetch_weather_mac() if is_mac else fetch_weather_api()
if not weather_text and not is_mac:
    weather_text = fetch_weather_api()

if weather_text:
    parts.append(weather_text)

# ── 节假日倒计时 ──────────────────────────────────────
try:
    with open(holidays_file, encoding="utf-8") as f:
        hdata = json.load(f)
    holidays = hdata.get("holidays", [])
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
            parts.append(f"{next_holiday['emoji']} 今天{next_holiday['name']}!")
        else:
            parts.append(f"{next_holiday['emoji']} {next_holiday['name']}·{min_days}天")
except Exception:
    pass

# ── 周末倒计时 ────────────────────────────────────────
weekday = today.weekday()
if weekday == 5:
    parts.append("🏖 休息!")
elif weekday == 6:
    parts.append("🏖 最后一天")
else:
    parts.append(f"🏖 {5-weekday}天")

# ── 出行灵感 / 段子（周末=周边游，平时=20%年度旅游，10%段子）────
try:
    tips = hdata.get("travel_tips", [])
    jokes = hdata.get("jokes", [])
    month = today.month
    season = "spring" if 3<=month<=5 else "summer" if 6<=month<=8 else "autumn" if 9<=month<=11 else "winter"
    random.seed(today.toordinal())
    r = random.random()
    if jokes and r < 0.1:
        tip = random.choice(jokes)
    elif r < 0.3 and not (weekday >= 5):
        pool = [t for t in tips if t.get("type") == "annual" and t["season"] in (season, "all")]
        tip = random.choice(pool)["tip"] if pool else None
    else:
        pool = [t for t in tips if t.get("type") == "nearby"]
        tip = random.choice(pool)["tip"] if pool else None
    if tip:
        if len(tip) > 20: tip = tip[:19] + "…"
        parts.append(tip)
except Exception:
    pass

print(" ".join(parts))
PYEOF
)

# ── Billing（bilibili 内网）────────────────────────────
TOKEN="${ANTHROPIC_AUTH_TOKEN:-}"
if [ -n "$TOKEN" ]; then
    BILLING=$(curl -s --max-time 3 "http://api-ai-coding.bilibili.co/api/v1/billing/usage" \
      -H "Authorization: Bearer $TOKEN" 2>/dev/null | /usr/bin/python3 -c '
import sys,json
try:
    d=json.load(sys.stdin).get("data",{})
    u=d.get("daily_usage",0)
    l=d.get("daily_limit",0)
    p=d.get("daily_percent",0)
    b=d.get("balance",0)
    print(f"💰{p:.0f}%")
except: pass
' 2>/dev/null)
    [ -n "$BILLING" ] && LINE="${LINE} │ ${BILLING}"
fi

[ -z "$LINE" ] && exit 0

# 输出到 stdout（供 statusLine type:command 直接显示）
echo "$LINE"

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
