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

def fetch_weather_openmeteo(loc):
    """open-meteo.com — 免费无需 key，按经纬度"""
    try:
        # loc 格式: "lat,lng" 或 城市ID（城市ID无法用，跳过）
        if "," not in loc:
            return None
        lat, lng = loc.split(",", 1)
        url = (f"https://api.open-meteo.com/v1/forecast"
               f"?latitude={lat.strip()}&longitude={lng.strip()}"
               f"&current=temperature_2m,weathercode&timezone=auto")
        req = urllib.request.Request(url, headers={"User-Agent": "ccday/1.0"})
        with urllib.request.urlopen(req, timeout=5) as r:
            data = json.loads(r.read())
        cur = data.get("current", {})
        temp = round(cur.get("temperature_2m", 0))
        code = cur.get("weathercode", 0)
        # WMO weather code → emoji + 描述
        if code == 0:                      desc = "☀️ 晴"
        elif code <= 2:                    desc = "⛅ 多云"
        elif code == 3:                    desc = "☁️ 阴"
        elif code in (45, 48):             desc = "🌫 雾"
        elif code in (51,53,55,56,57):     desc = "🌦 小雨"
        elif code in (61,63):              desc = "🌧 雨"
        elif code in (65,66,67):           desc = "⛈ 大雨"
        elif code in (71,73,75,77):        desc = "🌨 雪"
        elif code in (80,81,82):           desc = "🌧 阵雨"
        elif code in (85,86):              desc = "🌨 阵雪"
        elif code in (95,96,99):           desc = "⛈ 雷雨"
        else:                              desc = "🌡 未知"
        return f"{desc}{temp}°"
    except Exception:
        return None

def fetch_weather_mac():
    """macOS 天气：优先 open-meteo，无需任何配置"""
    return fetch_weather_openmeteo(location)

is_mac = platform.system() == "Darwin"
weather_text = fetch_weather_mac() if is_mac else fetch_weather_api()
if not weather_text:
    weather_text = fetch_weather_openmeteo(location)

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

# ── 出行灵感 / 段子（周末=周边游，平时=20%年度旅游，50%段子）────
try:
    tips = hdata.get("travel_tips", [])
    jokes = hdata.get("jokes", [])
    month = today.month
    season = "spring" if 3<=month<=5 else "summer" if 6<=month<=8 else "autumn" if 9<=month<=11 else "winter"
    random.seed(today.toordinal())
    r = random.random()

    # 尝试读 AI 生成的今日段子缓存
    ai_joke = None
    joke_cache = os.path.expanduser("~/.ccday-joke-cache.json")
    try:
        with open(joke_cache) as jf:
            jdata = json.load(jf)
            if jdata.get("date") == str(today):
                ai_joke = jdata.get("joke")
    except Exception:
        pass

    joke_pool = ([ai_joke] if ai_joke else []) + jokes

    if joke_pool and r < 0.5:
        tip = random.choice(joke_pool)
    elif r < 0.7 and not (weekday >= 5):
        pool = [t for t in tips if t.get("type") == "annual" and t["season"] in (season, "all")]
        tip = random.choice(pool)["tip"] if pool else None
    else:
        pool = [t for t in tips if t.get("type") == "nearby"]
        tip = random.choice(pool)["tip"] if pool else None
    if tip:
        if len(tip) > 22: tip = tip[:21] + "…"
        parts.append(tip)
except Exception:
    pass

print(" ".join(parts))
PYEOF
)

# ── 旅行计划 ──────────────────────────────────────────
if [ -n "${TRIP_NAME:-}" ] && [ -n "${TRIP_LAT:-}" ] && [ -n "${TRIP_LNG:-}" ]; then
    TRIP=$(python3 -c "
import math, datetime, sys, random

name  = sys.argv[1]
tlat  = float(sys.argv[2])
tlng  = float(sys.argv[3])
hlat  = float(sys.argv[4])
hlng  = float(sys.argv[5])
tdate = sys.argv[6]
tips_raw = sys.argv[7]

# 球面距离（km）
R = 6371
lat1,lat2 = math.radians(hlat), math.radians(tlat)
dlat = math.radians(tlat - hlat)
dlng = math.radians(tlng - hlng)
a = math.sin(dlat/2)**2 + math.cos(lat1)*math.cos(lat2)*math.sin(dlng/2)**2
km = round(R * 2 * math.asin(math.sqrt(a)))

# 倒计时
today = datetime.date.today()
days_left = ''
if tdate:
    try:
        td = datetime.date.fromisoformat(tdate)
        diff = (td - today).days
        if diff > 0:    days_left = f'·{diff}天后'
        elif diff == 0: days_left = '·就是今天!'
    except: pass

# 注意事项轮换
tip = ''
if tips_raw:
    tips = [t.strip() for t in tips_raw.split(';') if t.strip()]
    if tips:
        random.seed(today.toordinal())
        tip = ' · ' + random.choice(tips)

if days_left or not tdate:
    print(f'🗺️  {name} {km}km{days_left}{tip}')
" "$TRIP_NAME" "$TRIP_LAT" "$TRIP_LNG" \
  "${HOME_LAT:-31.28}" "${HOME_LNG:-121.52}" \
  "${TRIP_DATE:-}" "${TRIP_TIPS:-}" 2>/dev/null)
    [ -n "$TRIP" ] && LINE2="${TRIP}"
fi

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
    if [ -n "$BILLING" ]; then
        LINE2="${LINE2:+${LINE2} │ }${BILLING}"
    fi
fi

# ── AI 段子生成（后台，每天一次，缓存到 ~/.ccday-joke-cache.json）──
JOKE_CACHE="$HOME/.ccday-joke-cache.json"
TODAY=$(date +%Y-%m-%d)
NEED_GEN=false
if [ ! -f "$JOKE_CACHE" ]; then
    NEED_GEN=true
else
    CACHED_DATE=$(python3 -c "import json; print(json.load(open('$JOKE_CACHE')).get('date',''))" 2>/dev/null)
    [ "$CACHED_DATE" != "$TODAY" ] && NEED_GEN=true
fi

if $NEED_GEN && [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]; then
    (python3 - "$JOKE_CACHE" "$TODAY" \
      "${ANTHROPIC_BASE_URL:-https://api.anthropic.com}" \
      "$ANTHROPIC_AUTH_TOKEN" <<'JOKEEOF'
import sys, json, urllib.request, urllib.error

cache_path, today, base_url, token = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
base_url = base_url.rstrip('/')

payload = json.dumps({
    "model": "claude-haiku-4-5-20251001",
    "max_tokens": 80,
    "messages": [{
        "role": "user",
        "content": "写一条程序员段子或打气的话，要幽默接地气，15字以内，直接输出内容不要加引号或解释，可以带一个emoji开头"
    }]
}).encode()

req = urllib.request.Request(
    f"{base_url}/v1/messages",
    data=payload,
    headers={
        "Authorization": f"Bearer {token}",
        "anthropic-version": "2023-06-01",
        "content-type": "application/json"
    }
)
try:
    with urllib.request.urlopen(req, timeout=8) as r:
        data = json.load(r)
    joke = data["content"][0]["text"].strip().strip('"').strip("'")
    if joke:
        with open(cache_path, "w") as f:
            json.dump({"date": today, "joke": joke}, f, ensure_ascii=False)
except Exception:
    pass
JOKEEOF
    ) &>/dev/null &
fi

[ -z "$LINE" ] && exit 0

# ── 上下文占用 ────────────────────────────────────────
CTX=$(python3 -c "
import json, os, glob, time

proj_dir = os.path.expanduser('~/.claude/projects')
files = glob.glob(f'{proj_dir}/**/*.jsonl', recursive=True)
if not files:
    exit()

# 取5分钟内修改的文件，没有则取最近的
now = time.time()
recent = [f for f in files if now - os.path.getmtime(f) < 300]
candidates = recent if recent else files
latest = max(candidates, key=os.path.getmtime)

usage = None
with open(latest) as f:
    for line in f:
        try:
            d = json.loads(line)
            u = d.get('message', {}).get('usage')
            if u and u.get('input_tokens'):
                usage = u
        except: pass

if not usage:
    exit()

total = (usage.get('input_tokens', 0)
       + usage.get('cache_read_input_tokens', 0)
       + usage.get('cache_creation_input_tokens', 0))
pct = round(total / 200000 * 100)
print(f'📊 ctx {pct}%')
" 2>/dev/null)
[ -n "$CTX" ] && LINE2="${CTX}${LINE2:+ │ ${LINE2}}"

# 输出到 stdout（供 statusLine type:command 直接显示）
echo "$LINE"
[ -n "${LINE2:-}" ] && echo "$LINE2"
