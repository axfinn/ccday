#!/bin/bash
# ccday-label.sh — 天气 + 节假日 + 周末 + 番茄钟 + 休息/喝水提醒 + Git + 目标 + 旅行计划 + 上下文
# 项目: https://github.com/axfinn/ccday
# 版本: v0.5.2
#
# 配置项（~/.ccday.conf）:
#   QWEATHER_*          和风天气 API（可选，不填用 open-meteo）
#   QWEATHER_LOCATION   经纬度，如 121.47,31.23
#   CCDAY_WORK_END      下班时间，默认 19:00
#   CCDAY_GOAL          今日目标，如 "完成登录模块"
#   TRIP_*              旅行计划（可选）

HOLIDAYS_JSON="$(dirname "$0")/holidays.json"

for f in "$HOME/.ccday.conf" "$HOME/.ccday.env"; do
    [ -f "$f" ] && source "$f" && break
done
if [ -z "$QWEATHER_API_HOST" ] && [ -f "$HOME/.ccday.yaml" ]; then
    eval "$(grep -E '^\s*\w+\s*:' "$HOME/.ccday.yaml" | sed 's/\s*:\s*/=/' | sed 's/^/export /')"
fi

QWEATHER_API_HOST="${QWEATHER_API_HOST:-}"
QWEATHER_KID="${QWEATHER_KID:-}"
QWEATHER_PROJECT_ID="${QWEATHER_PROJECT_ID:-}"
QWEATHER_PRIVATE_KEY="${QWEATHER_PRIVATE_KEY:-$HOME/.ccday-private.pem}"
QWEATHER_LOCATION="${QWEATHER_LOCATION:-121.47,31.23}"
CCDAY_WORK_END="${CCDAY_WORK_END:-19:00}"
CCDAY_GOAL="${CCDAY_GOAL:-}"
CCDAY_BREAK_INTERVAL="${CCDAY_BREAK_INTERVAL:-50}"
CCDAY_BREAK_DURATION="${CCDAY_BREAK_DURATION:-10}"
CCDAY_BREAK_START="${CCDAY_BREAK_START:-09:00}"
CCDAY_BREAK_END="${CCDAY_BREAK_END:-22:00}"
CCDAY_BREAK_CONFIRM="${CCDAY_BREAK_CONFIRM:-1}"   # 1=需要主动确认，0=定时自动消失（同喝水）
CCDAY_WATER_INTERVAL="${CCDAY_WATER_INTERVAL:-60}"
export CCDAY_WORK_END CCDAY_GOAL CCDAY_BREAK_INTERVAL CCDAY_BREAK_DURATION CCDAY_BREAK_START CCDAY_BREAK_END CCDAY_BREAK_CONFIRM CCDAY_WATER_INTERVAL

LINE=$(/usr/bin/python3 - \
  "$QWEATHER_API_HOST" "$QWEATHER_KID" "$QWEATHER_PROJECT_ID" \
  "$QWEATHER_PRIVATE_KEY" "$QWEATHER_LOCATION" "$HOLIDAYS_JSON" <<'PYEOF'
import sys, json, datetime, random, urllib.request, base64, time, os, platform, gzip as gzipmod
from cryptography.hazmat.primitives.serialization import load_pem_private_key

api_host      = sys.argv[1]
kid           = sys.argv[2]
sub           = sys.argv[3]
key_path      = os.path.expanduser(sys.argv[4])
location      = sys.argv[5]
holidays_file = sys.argv[6]

today   = datetime.date.today()
parts   = []

# ── 天气（带30分钟缓存）──────────────────────────────────
WEATHER_CACHE = os.path.expanduser("~/.ccday-weather-cache.json")

def load_weather_cache():
    try:
        with open(WEATHER_CACHE) as f:
            d = json.load(f)
        if time.time() - d.get("ts", 0) < 1800:  # 30分钟
            return d.get("text")
    except Exception:
        pass
    return None

def save_weather_cache(text):
    try:
        with open(WEATHER_CACHE, "w") as f:
            json.dump({"ts": time.time(), "text": text}, f)
    except Exception:
        pass

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
    try:
        if "," not in loc:
            return None
        lng, lat = loc.split(",", 1)  # QWEATHER_LOCATION 格式是 经度,纬度
        url = (f"https://api.open-meteo.com/v1/forecast"
               f"?latitude={lat.strip()}&longitude={lng.strip()}"
               f"&current=temperature_2m,weathercode&timezone=auto")
        req = urllib.request.Request(url, headers={"User-Agent": "ccday/1.0"})
        with urllib.request.urlopen(req, timeout=5) as r:
            data = json.loads(r.read())
        cur  = data.get("current", {})
        temp = round(cur.get("temperature_2m", 0))
        code = cur.get("weathercode", 0)
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

weather_text = load_weather_cache()
if not weather_text:
    is_mac = platform.system() == "Darwin"
    weather_text = (None if is_mac else fetch_weather_api()) or fetch_weather_openmeteo(location)
    if weather_text:
        save_weather_cache(weather_text)

if weather_text:
    parts.append(weather_text)

# ── 节假日倒计时 ──────────────────────────────────────
try:
    with open(holidays_file, encoding="utf-8") as f:
        hdata = json.load(f)
    holidays    = hdata.get("holidays", [])
    workdays    = set(hdata.get("extra_workdays", []))   # 调休上班日
    next_holiday = None
    min_days = 9999
    for h in holidays:
        hdate = datetime.date.fromisoformat(h["date"])
        diff  = (hdate - today).days
        if 0 <= diff < min_days:
            min_days = diff
            next_holiday = h
    if next_holiday:
        if min_days == 0:
            parts.append(f"{next_holiday['emoji']} 今天{next_holiday['name']}!")
        else:
            parts.append(f"{next_holiday['emoji']} {next_holiday['name']}·{min_days}天")
except Exception:
    hdata    = {}
    workdays = set()

# ── 周末倒计时（感知调休）────────────────────────────────
import datetime as _dt
weekday  = today.weekday()
today_str = str(today)

# 判断今天是否实际需要上班（调休）
is_extra_workday = today_str in workdays

if weekday == 5 and today_str not in workdays:
    parts.append("🏖 休息!")
elif weekday == 6 and today_str not in workdays:
    parts.append("🏖 最后一天")
else:
    # 找下一个真正的休息日（非工作日且不是调休上班日）
    work_end = os.environ.get("CCDAY_WORK_END", "19:00")
    try:
        end_h, end_m = map(int, work_end.split(":"))
    except Exception:
        end_h, end_m = 19, 0
    now = _dt.datetime.now()

    # 找下一个休息日
    next_off = None
    for delta in range(1, 14):
        d = today + _dt.timedelta(days=delta)
        if d.weekday() >= 5 and str(d) not in workdays:
            next_off = d
            break
        # 节假日也算休息
        if any(h.get("date") == str(d) for h in hdata.get("holidays", [])):
            next_off = d
            break

    if next_off and (next_off - today).days == 1:
        # 明天就休息，精确到小时
        end_dt = now.replace(hour=end_h, minute=end_m, second=0, microsecond=0)
        diff   = end_dt - now
        total_hours = diff.total_seconds() / 3600
        if total_hours <= 0:
            parts.append("🏖 快到了!")
        elif total_hours < 1:
            parts.append(f"🏖 {int(diff.total_seconds()/60)}分钟")
        else:
            parts.append(f"🏖 还{round(total_hours)}h")
    elif next_off:
        days_to = (next_off - today).days
        parts.append(f"🏖 还{days_to}天")
    else:
        parts.append("🏖 撑住")

# ── 番茄钟 ────────────────────────────────────────────
try:
    pomo_file = os.path.expanduser("~/.ccday-pomodoro.json")
    with open(pomo_file) as f:
        pomo = json.load(f)
    pomo_end = pomo.get("end")
    pomo_label = pomo.get("label", "")
    if pomo_end:
        remaining = pomo_end - time.time()
        if remaining > 0:
            mins = int(remaining // 60)
            secs = int(remaining % 60)
            label = f" {pomo_label}" if pomo_label else ""
            parts.append(f"🍅{mins}:{secs:02d}{label}")
        else:
            parts.append("🍅 时间到!")
except Exception:
    pass

# ── 休息提醒 ──────────────────────────────────────────
try:
    break_interval = int(os.environ.get("CCDAY_BREAK_INTERVAL", "50")) * 60
    break_duration = int(os.environ.get("CCDAY_BREAK_DURATION", "10")) * 60
    break_confirm  = os.environ.get("CCDAY_BREAK_CONFIRM", "1") == "1"
    break_start_h, break_start_m = map(int, os.environ.get("CCDAY_BREAK_START", "09:00").split(":"))
    break_end_h,   break_end_m   = map(int, os.environ.get("CCDAY_BREAK_END",   "22:00").split(":"))

    now_dt   = _dt.datetime.now()
    now_time = now_dt.time()
    in_range = _dt.time(break_start_h, break_start_m) <= now_time <= _dt.time(break_end_h, break_end_m)

    if in_range:
        if break_confirm:
            # 需要主动确认：读文件判断上次休息时间
            break_file = os.path.expanduser("~/.ccday-break.json")
            last_break = 0
            resting    = False
            try:
                with open(break_file) as f:
                    bd = json.load(f)
                last_break = bd.get("ts", 0)
                if bd.get("resting") and time.time() - last_break < break_duration:
                    resting = True
            except Exception:
                pass

            elapsed = time.time() - last_break if last_break else break_interval + 1

            if resting:
                rest_left = int((break_duration - (time.time() - last_break)) / 60) + 1
                parts.append(f"🧘 休息中{rest_left}min")
            elif elapsed >= break_interval:
                activities = [
                    "站起来伸个懒腰", "眺望远处20秒", "做10个深蹲",
                    "走动走动", "活动一下脖子", "闭眼休息一下",
                    "去趟洗手间", "做几个肩膀绕环",
                ]
                random.seed(int(elapsed))
                parts.append(f"🧘 {random.choice(activities)}!")
        else:
            # 不需要确认：纯按时间，到点显示5分钟自动消失（同喝水逻辑）
            day_start  = now_dt.replace(hour=break_start_h, minute=break_start_m, second=0, microsecond=0)
            elapsed_min = int((now_dt - day_start).total_seconds() / 60)
            slot_min   = elapsed_min % (break_interval // 60)
            if slot_min < 5:
                activities = [
                    "站起来伸个懒腰", "眺望远处20秒", "做10个深蹲",
                    "走动走动", "活动一下脖子", "闭眼休息一下",
                    "去趟洗手间", "做几个肩膀绕环",
                ]
                random.seed(elapsed_min // (break_interval // 60))
                parts.append(f"🧘 {random.choice(activities)}!")
except Exception:
    pass

# ── 喝水提醒 ──────────────────────────────────────────
try:
    water_interval = int(os.environ.get("CCDAY_WATER_INTERVAL", "60"))  # 分钟
    water_start_h, water_start_m = map(int, os.environ.get("CCDAY_BREAK_START", "09:00").split(":"))
    water_end_h,   water_end_m   = map(int, os.environ.get("CCDAY_BREAK_END",   "22:00").split(":"))

    now_dt2  = _dt.datetime.now()
    now_time2 = now_dt2.time()
    in_range2 = _dt.time(water_start_h, water_start_m) <= now_time2 <= _dt.time(water_end_h, water_end_m)

    if in_range2 and water_interval > 0:
        # 从今天 BREAK_START 开始，每 water_interval 分钟的第5分钟内提醒
        day_start = now_dt2.replace(hour=water_start_h, minute=water_start_m, second=0, microsecond=0)
        elapsed_min = int((now_dt2 - day_start).total_seconds() / 60)
        slot_min = elapsed_min % water_interval  # 当前在本轮的第几分钟
        if slot_min < 5:  # 每轮开始的前5分钟显示提醒
            msgs = ["喝杯水", "补充水分", "记得喝水", "来杯水吧"]
            random.seed(elapsed_min // water_interval)
            parts.append(f"💧 {random.choice(msgs)}!")
except Exception:
    pass

# ── 今日目标 ──────────────────────────────────────────
try:
    goal_raw = os.environ.get("CCDAY_GOAL", "")
    if goal_raw:
        goal_file = os.path.expanduser("~/.ccday-goal.json")
        done = False
        try:
            with open(goal_file) as f:
                gdata = json.load(f)
            if gdata.get("date") == str(today) and gdata.get("done"):
                done = True
        except Exception:
            pass
        label = goal_raw if len(goal_raw) <= 10 else goal_raw[:9] + "…"
        parts.append(f"✅ {label}" if done else f"🎯 {label}")
except Exception:
    pass

# ── 出行灵感 / 段子 ───────────────────────────────────
try:
    tip = None
    tip_cache = os.path.expanduser("~/.ccday-tip-cache.json")
    try:
        with open(tip_cache) as jf:
            tip = json.load(jf).get("tip")
    except Exception:
        pass

    if not tip:
        tips  = hdata.get("travel_tips", [])
        jokes = hdata.get("jokes", [])
        month  = today.month
        season = "spring" if 3<=month<=5 else "summer" if 6<=month<=8 else "autumn" if 9<=month<=11 else "winter"
        random.seed(today.toordinal())
        r = random.random()
        if jokes and r < 0.5:
            tip = random.choice(jokes)
        elif r < 0.7 and weekday < 5:
            pool = [t for t in tips if t.get("type") == "annual" and t.get("season") in (season, "all")]
            tip  = random.choice(pool)["tip"] if pool else None
        else:
            pool = [t for t in tips if t.get("type") == "nearby"]
            tip  = random.choice(pool)["tip"] if pool else None

    if tip:
        if len(tip) > 22: tip = tip[:21] + "…"
        parts.append(tip)
except Exception:
    pass

print(" ".join(parts))
PYEOF
)

# ── Git 状态感知 ──────────────────────────────────────
GIT=$(python3 -c "
import subprocess, os, sys

cwd = os.getcwd()
try:
    # 找 git 根目录
    root = subprocess.check_output(
        ['git', 'rev-parse', '--show-toplevel'],
        cwd=cwd, stderr=subprocess.DEVNULL, text=True
    ).strip()
except Exception:
    sys.exit(0)

try:
    status = subprocess.check_output(
        ['git', 'status', '--porcelain'],
        cwd=root, stderr=subprocess.DEVNULL, text=True
    ).strip()
    changed = len([l for l in status.splitlines() if l.strip()]) if status else 0
except Exception:
    changed = 0

try:
    ahead_behind = subprocess.check_output(
        ['git', 'rev-list', '--left-right', '--count', 'HEAD...@{upstream}'],
        cwd=root, stderr=subprocess.DEVNULL, text=True
    ).strip().split()
    ahead  = int(ahead_behind[0]) if len(ahead_behind) > 0 else 0
    behind = int(ahead_behind[1]) if len(ahead_behind) > 1 else 0
except Exception:
    ahead = behind = 0

parts = []
if changed:  parts.append(f'📝{changed}')
if behind:   parts.append(f'⬇{behind}')
if ahead:    parts.append(f'⬆{ahead}')
if parts:
    print(' '.join(parts))
" 2>/dev/null)

# ── 旅行计划 ──────────────────────────────────────────
if [ -n "${TRIP_NAME:-}" ] && [ -n "${TRIP_LAT:-}" ] && [ -n "${TRIP_LNG:-}" ]; then
    TRIP=$(python3 -c "
import math, datetime, sys, random

name     = sys.argv[1]
tlat     = float(sys.argv[2])
tlng     = float(sys.argv[3])
hlat     = float(sys.argv[4])
hlng     = float(sys.argv[5])
tdate    = sys.argv[6]
tips_raw = sys.argv[7]

R = 6371
lat1,lat2 = math.radians(hlat), math.radians(tlat)
dlat = math.radians(tlat - hlat)
dlng = math.radians(tlng - hlng)
a  = math.sin(dlat/2)**2 + math.cos(lat1)*math.cos(lat2)*math.sin(dlng/2)**2
km = round(R * 2 * math.asin(math.sqrt(a)))

today     = datetime.date.today()
days_left = ''
if tdate:
    try:
        td   = datetime.date.fromisoformat(tdate)
        diff = (td - today).days
        if diff > 0:    days_left = f'·{diff}天后'
        elif diff == 0: days_left = '·就是今天!'
    except: pass

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
    p=d.get("daily_percent",0)
    print(f"💰{p:.0f}%")
except: pass
' 2>/dev/null)
    [ -n "$BILLING" ] && LINE2="${LINE2:+${LINE2} │ }${BILLING}"
fi

# ── 上下文占用 ────────────────────────────────────────
CTX=$(python3 -c "
import json, os, glob, time

proj_dir = os.path.expanduser('~/.claude/projects')
files = glob.glob(f'{proj_dir}/**/*.jsonl', recursive=True)
if not files:
    exit()

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

# ── Git 拼入第二行 ────────────────────────────────────
[ -n "$GIT" ] && LINE2="${LINE2:+${LINE2} │ }${GIT}"

# 输出
echo "$LINE"
[ -n "${LINE2:-}" ] && echo "$LINE2"
