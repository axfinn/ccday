#!/bin/bash
# ccday-label.sh — 天气 + 节假日 + 周末 + 下班倒计时 + 番茄钟 + 休息/喝水/饭点提醒 + Git + 目标 + 旅行计划 + 上下文
# 项目: https://github.com/axfinn/ccday
# 版本: v0.6.7
#
# 配置项（~/.ccday.conf）:
#   QWEATHER_*          和风天气 API（可选，不填用 open-meteo）
#   QWEATHER_LOCATION   经纬度，如 121.47,31.23
#   CCDAY_WORK_START    上班时间，默认 10:00（未打卡时的兜底）
#   CCDAY_WORK_END      下班时间，默认 19:30（未打卡时的兜底）
#   CCDAY_WORK_PUNCH    1=按首次开屏时间打卡（默认），下班=上班+CCDAY_WORK_HOURS
#   CCDAY_WORK_HOURS    打卡模式工时，默认 9
#   CCDAY_GOAL          今日目标，如 "完成登录模块"
#   TRIP_*              旅行计划（可选）

HOLIDAYS_JSON="$(dirname "$0")/holidays.json"

# Claude Code 通过 stdin 传入会话 JSON（transcript_path / model / cost）。
# 手动在终端运行时 stdin 是 tty，跳过读取避免阻塞。
CCDAY_STDIN=""
if [ ! -t 0 ]; then
    CCDAY_STDIN=$(timeout 0.3 cat 2>/dev/null || true)
fi
export CCDAY_STDIN

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
CCDAY_WORK_START="${CCDAY_WORK_START:-10:00}"
CCDAY_WORK_END="${CCDAY_WORK_END:-19:30}"
CCDAY_OFFWORK="${CCDAY_OFFWORK:-1}"               # 1=显示下班倒计时，0=隐藏
CCDAY_WORK_PUNCH="${CCDAY_WORK_PUNCH:-1}"         # 1=按首次开屏时间打卡，0=用固定 WORK_START
CCDAY_WORK_HOURS="${CCDAY_WORK_HOURS:-9}"         # 打卡模式下的工时，下班=上班+此值
CCDAY_PUNCH_START="${CCDAY_PUNCH_START:-06:00}"   # 打卡有效窗口开始
CCDAY_PUNCH_END="${CCDAY_PUNCH_END:-12:00}"       # 打卡有效窗口结束
CCDAY_PUNCH_SHOW="${CCDAY_PUNCH_SHOW:-1}"         # 1=下班倒计时带上 (上班→下班) 时间
CCDAY_GOAL="${CCDAY_GOAL:-}"
CCDAY_BREAK_INTERVAL="${CCDAY_BREAK_INTERVAL:-50}"
CCDAY_BREAK_DURATION="${CCDAY_BREAK_DURATION:-10}"
CCDAY_BREAK_START="${CCDAY_BREAK_START:-09:00}"
CCDAY_BREAK_END="${CCDAY_BREAK_END:-22:00}"
CCDAY_BREAK_CONFIRM="${CCDAY_BREAK_CONFIRM:-1}"   # 1=需要主动确认，0=定时自动消失（同喝水）
CCDAY_WATER_INTERVAL="${CCDAY_WATER_INTERVAL:-60}"
CCDAY_LUNCH="${CCDAY_LUNCH:-12:00}"               # 午饭提醒时间，留空关闭
CCDAY_DINNER="${CCDAY_DINNER:-18:00}"             # 晚饭提醒时间，留空关闭
CCDAY_MEAL_WINDOW="${CCDAY_MEAL_WINDOW:-30}"      # 饭点提醒持续 N 分钟
export CCDAY_WORK_START CCDAY_WORK_END CCDAY_OFFWORK CCDAY_GOAL
export CCDAY_WORK_PUNCH CCDAY_WORK_HOURS CCDAY_PUNCH_START CCDAY_PUNCH_END CCDAY_PUNCH_SHOW
export CCDAY_BREAK_INTERVAL CCDAY_BREAK_DURATION CCDAY_BREAK_START CCDAY_BREAK_END CCDAY_BREAK_CONFIRM CCDAY_WATER_INTERVAL
export CCDAY_LUNCH CCDAY_DINNER CCDAY_MEAL_WINDOW
# 周边出行灵感需要知道你在哪，否则只能输出"高铁2小时内的城市"这种废话
export HOME_LAT="${HOME_LAT:-31.28}" HOME_LNG="${HOME_LNG:-121.52}"

LINE=$(/usr/bin/python3 - \
  "$QWEATHER_API_HOST" "$QWEATHER_KID" "$QWEATHER_PROJECT_ID" \
  "$QWEATHER_PRIVATE_KEY" "$QWEATHER_LOCATION" "$HOLIDAYS_JSON" <<'PYEOF'
import sys, json, datetime, random, urllib.request, base64, time, os, platform, gzip as gzipmod, subprocess
from cryptography.hazmat.primitives.serialization import load_pem_private_key

api_host      = sys.argv[1]
kid           = sys.argv[2]
sub           = sys.argv[3]
key_path      = os.path.expanduser(sys.argv[4])
location      = sys.argv[5]
holidays_file = sys.argv[6]

today   = datetime.date.today()
parts   = []

def send_fullscreen_alert(title, msg, key="break", hold=30):
    """macOS 全屏 HTML 提醒，用 Safari 打开

    title 显示在页面标题上——四种提醒（休息/下班/喝水/饭点）共用这个函数，
    标题写死会出现"休息一下！"配"已加班 2m"的错配。
    hold 是必须停留的秒数，只有久坐提醒需要拖住人；下班/喝水/饭点给 0，
    提醒完可以立刻关掉，别把"叫你别久坐"变成"再按你坐 30 秒"。
    key 决定临时文件名，避免两个提醒同一分钟到期时互相覆写内容。
    """
    import random as _r
    JOKES = {
        "break": [
            "久坐伤身，代码再香也要站起来闻闻空气",
            "你的椎间盘正在用沉默抗议",
            "程序员三大错觉：再坐一会儿、马上就好、这个 bug 很简单",
            "站起来！不然你的腰会比你的代码先崩溃",
            "眼睛也是 CPU，过热需要散热",
            "活动一下，回来思路更清晰，bug 自己会消失（大概）",
            "你已经坐了很久了，连椅子都累了",
            "起来走走，顺便想想那个困扰你的 bug",
        ],
        "offwork": [
            "代码明天还在，今天的地铁不等人",
            "没有什么 bug 值得你留到深夜",
            "加班解决不了的问题，睡一觉往往能",
            "下班不是逃跑，是可持续开发",
        ],
        "water": [
            "咖啡不算水，续命液也需要稀释",
            "身体 60% 是水，不是咖啡因",
            "喝口水，顺便让眼睛离屏幕一会儿",
        ],
        "meal": [
            "空腹调 bug，容易把自己也调没了",
            "饭要按时吃，bug 可以慢慢改",
            "低血糖写出来的代码，明天你自己也看不懂",
        ],
    }
    EMOJI = {"break": "🧘", "offwork": "🌙", "water": "💧", "meal": "🍚"}
    kind  = key.split("-")[0]          # meal-lunch / meal-dinner 归到 meal
    joke  = _r.choice(JOKES.get(kind, JOKES["break"]))
    emoji = EMOJI.get(kind, "🧘")

    def esc(s):
        """提醒文案会进 HTML，先转义——文案里出现 < & 不该把页面搞坏"""
        return (str(s).replace("&", "&amp;").replace("<", "&lt;")
                      .replace(">", "&gt;").replace('"', "&quot;"))

    try:
        js = r"""
var total=__HOLD__, clicks=0;
var taunts=["才{n}秒？你在逗我？","认真的吗？才{n}秒！","椎间盘表示不服","{n}秒就够了？骗谁呢","再等等，就快了","你的腰还没谢谢你呢"];
var el=document.getElementById('sec'), btn=document.getElementById('btn'), timerEl=document.getElementById('timer');
if(total<=0){timerEl.style.display='none'}
var iv=setInterval(function(){
  if(total<=0){clearInterval(iv);return}
  total--;
  el.textContent=total;
  if(total<=0){clearInterval(iv);timerEl.style.display='none';btn.textContent='好了，继续工作 ✓';btn.onclick=function(){window.close()}};
},1000);
function tryClose(){
  if(total<=0){window.close();return}
  clicks++;
  var t=taunts[Math.min(clicks-1,taunts.length-1)].replace('{n}',total);
  btn.textContent=t;
  btn.style.background='#8a4a4a';
  setTimeout(function(){btn.textContent='好了，继续工作';btn.style.background='#4a4a8a'},1500);
}
btn.addEventListener('dblclick',function(){window.close()});
"""
        js = js.replace("__HOLD__", str(int(hold)))
        html = (
            '<!DOCTYPE html><html><head><meta charset="utf-8"><style>'
            '*{margin:0;padding:0;box-sizing:border-box}'
            'body{background:#1a1a2e;color:white;display:flex;flex-direction:column;'
            'align-items:center;justify-content:center;height:100vh;'
            'font-family:-apple-system,sans-serif;text-align:center;padding:40px}'
            '.emoji{font-size:120px;margin-bottom:20px}'
            'h1{font-size:72px;font-weight:bold;margin-bottom:16px}'
            '.activity{font-size:36px;color:#7eb8f7;margin-bottom:20px}'
            'p{font-size:26px;color:#aaaacc;margin-bottom:40px;max-width:800px}'
            'button{font-size:24px;padding:16px 48px;background:#4a4a8a;color:white;'
            'border:none;border-radius:12px;cursor:pointer}'
            '</style></head><body>'
            '<div class="emoji">' + emoji + '</div>'
            '<h1>' + esc(title) + '</h1>'
            '<div class="activity">' + esc(msg) + '</div>'
            '<p>' + esc(joke) + '</p>'
            '<div id="timer" style="font-size:20px;color:#666;margin-bottom:20px">'
            '还需休息 <span id="sec">' + str(int(hold)) + '</span> 秒</div>'
            '<button id="btn" onclick="tryClose()">好了，继续工作</button>'
            '<div style="font-size:14px;color:#555;margin-top:12px">双击可强制关闭</div>'
            '<script>' + js + '</script>'
            '</body></html>'
        )
        html_path = os.path.expanduser(f"~/.ccday-alert-{key}.html")
        with open(html_path, "w") as f:
            f.write(html)
        # 窗口尺寸跟着主屏走，写死 1440x900 在外接/高分屏上会错位
        applescript = f'''tell application "Finder" to set sb to bounds of window of desktop
tell application "Safari"
  activate
  open POSIX file "{html_path}"
  delay 0.5
  tell window 1 to set bounds to sb
end tell'''
        subprocess.Popen(["osascript", "-e", applescript],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass

def send_notification(title, msg, key="break", hold=30):
    """跨平台系统通知：macOS 用全屏提醒，Linux 用 notify-send"""
    try:
        sys_name = platform.system()
        if sys_name == "Darwin":
            send_fullscreen_alert(title, msg, key, hold)
        elif sys_name == "Linux":
            subprocess.Popen(
                ["notify-send", title, msg, "--urgency=normal", "--expire-time=10000"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
    except Exception:
        pass

def notify_once(key, title, msg, cooldown, hold=0):
    """用标记文件防重复弹，cooldown 秒内只弹一次

    hold 默认 0——只有久坐提醒需要强制停留，其余提醒看完就能关。
    """
    notif_file = os.path.expanduser(f"~/.ccday-notif-{key}.json")
    try:
        with open(notif_file) as f:
            last_ts = json.load(f).get("ts", 0)
    except Exception:
        last_ts = 0
    if time.time() - last_ts > cooldown:
        send_notification(title, msg, key, hold)
        try:
            with open(notif_file, "w") as f:
                json.dump({"ts": time.time()}, f)
        except Exception:
            pass

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

# 判断今天是否实际需要上班（调休上班日 / 法定节假日）
is_extra_workday = today_str in workdays
is_holiday_today = any(h.get("date") == today_str for h in hdata.get("holidays", []))
is_workday_today = is_extra_workday or (weekday < 5 and not is_holiday_today)

def parse_hhmm(raw, dft_h, dft_m):
    try:
        h, m = raw.split(":")
        return int(h), int(m)
    except Exception:
        return dft_h, dft_m

def fmt_span(seconds):
    """秒 → 3h55m / 45m，用于倒计时展示"""
    mins = int(seconds // 60)
    if mins >= 60:
        return f"{mins // 60}h{mins % 60:02d}m"
    return f"{mins}m"

# ── 上班打卡（当天第一次真实用户活动）──────────────────
# 弹性工作制：CCDAY_PUNCH_START–CCDAY_PUNCH_END（默认 06:00–12:00）内的首次用户活动
# 记为上班时间，下班点 = 上班 + CCDAY_WORK_HOURS。晚到晚走，不再按死的 10:00 算。
#
# 上班时间怎么取（按优先级）：
#   1. macOS: pmset -g log 里当天窗口内第一次真实用户活动（显示器点亮 / UserIsActive
#      断言 / HID 活动）。比"状态栏首次刷新"准——早上先开邮件、晚点才开 Claude Code
#      也不会把上班时间记晚
#   2. macOS 但 pmset 一条活动都查不到: 只有 HID 空闲时间显示人此刻真在操作
#      （PUNCH_IDLE_MAX 秒内动过键鼠）才拿当前时间打卡
#   3. 其他平台: 退回状态栏在窗口内的首次刷新时刻
# 关键前提：状态栏刷新不等于人在。机器整夜没关、挂着会话空转时状态栏照样会刷，
# 那一刷不能当上班时间（会把上班记成 06:00），所以 pmset / 键鼠都说人不在时宁可
# 不打卡。兜底值也只是暂定，之后每次刷新都再给 pmset 一次纠正机会。
# 首次活动晚于窗口（下午才开电脑）或非工作日 → 退回固定的 CCDAY_WORK_START/END。
PUNCH_FILE = os.path.expanduser("~/.ccday-punch.json")
PUNCH_PROBE_GAP = 300    # pmset 空结果的复查间隔（秒）：拉日志约 0.7s，不能每次刷新都做
PUNCH_IDLE_MAX  = 120    # 键鼠空闲不超过这么多秒，才认为人此刻真的在机器前


def load_punch():
    """今天的打卡记录 dict，没有/隔夜返回 None

    source 取值：pmset=日志里的真实首次活动（权威，认定后不改）；hid=pmset 查不到
    但键鼠显示人在，取当时时间；refresh=没有空闲信号可用时的状态栏首刷兜底；
    idle=窗口内确认还没人动过机器；closed=窗口已关，就地冻结不再重试。
    """
    try:
        with open(PUNCH_FILE) as f:
            d = json.load(f)
    except Exception:
        return None
    if d.get("date") != today_str:
        return None      # 隔夜挂着不关机也不会沿用昨天的打卡
    return d


def punch_dt(rec):
    """记录里的上班 datetime，没打上卡（idle/closed）返回 None"""
    try:
        return _dt.datetime.fromtimestamp(float(rec["ts"]))
    except Exception:
        return None


def save_punch(dt, source, probe=None):
    rec = {"date": today_str, "source": source}
    if dt is not None:
        rec["ts"] = dt.timestamp()
        rec["time"] = dt.strftime("%H:%M")
    if probe:
        rec["probe"] = probe      # 上次问过 pmset 的时刻，用来节流
    try:
        with open(PUNCH_FILE, "w") as f:
            json.dump(rec, f)
    except Exception:
        pass


def hid_idle_seconds():
    """macOS: 距上次键鼠活动的秒数，取不到返回 None（约 6ms，每次刷新都调也没事）"""
    if platform.system() != "Darwin":
        return None
    try:
        # HIDIdleTime 挂在 IOHIDSystem 下三层，-d 4 才够深（-d 1 什么都取不到）
        out = subprocess.run(["ioreg", "-c", "IOHIDSystem", "-d", "4", "-w", "0"],
                             capture_output=True, text=True, timeout=3).stdout
    except Exception:
        return None
    for line in out.splitlines():
        if "HIDIdleTime" not in line:
            continue
        try:
            return int(line.split("=")[-1].strip().strip('"')) / 1e9   # 纳秒
        except Exception:
            return None
    return None


def detect_mac_punch(win_start, win_end, now_p):
    """macOS: 从 pmset -g log 找当天窗口内第一次真实用户活动。

    只认"人真的在操作"的信号：显示器点亮、UserIsActive 断言、HID 活动。
    后台进程（cloudd / coreaudiod / runningboardd 之类）的电源断言和 DarkWake
    都不算——机器自己醒来收邮件不等于人到了。
    """
    if platform.system() != "Darwin":
        return None
    try:
        out = subprocess.run(["pmset", "-g", "log"], capture_output=True,
                             text=True, timeout=4).stdout
    except Exception:
        return None

    markers = ("Display is turned on", "Created UserIsActive", "HID Activity")
    best = None
    for line in out.splitlines():
        # pmset 每行以 "2026-08-04 10:22:55 +0800 ..." 开头
        if not line.startswith(today_str):
            continue
        if "DarkWake" in line:
            continue          # 后台维护唤醒，屏幕没亮，人不在
        if not any(m in line for m in markers):
            continue
        try:
            ts = _dt.datetime.strptime(line[:19], "%Y-%m-%d %H:%M:%S")
        except Exception:
            continue
        # 不能晚于当前时间（日志时区异常时的兜底），也必须落在打卡窗口内
        if win_start <= ts <= min(now_p, win_end) and (best is None or ts < best):
            best = ts
    return best


def resolve_punch():
    if os.environ.get("CCDAY_WORK_PUNCH", "1") != "1" or not is_workday_today:
        return None

    cfg_s = parse_hhmm(os.environ.get("CCDAY_WORK_START", "10:00"), 10, 0)
    cfg_e = parse_hhmm(os.environ.get("CCDAY_WORK_END", "19:30"), 19, 30)
    if cfg_e <= cfg_s:
        return None      # 跨天班（22:00→06:00）：早上开屏是在下班，不是上班

    rec = load_punch()
    if rec and rec.get("source") in ("pmset", "closed"):
        return punch_dt(rec)     # 权威值/已冻结，不再查

    ps_h, ps_m = parse_hhmm(os.environ.get("CCDAY_PUNCH_START", "06:00"), 6, 0)
    pe_h, pe_m = parse_hhmm(os.environ.get("CCDAY_PUNCH_END", "12:00"), 12, 0)
    now_p = _dt.datetime.now()
    win_start = now_p.replace(hour=ps_h, minute=ps_m, second=0, microsecond=0)
    win_end   = now_p.replace(hour=pe_h, minute=pe_m, second=59, microsecond=0)
    if now_p < win_start:
        return None      # 窗口还没开始，今天的班还没上

    # pmset 读的是历史日志，过了窗口照样能查到早上的首次活动——所以先试它。
    # 上一轮没查到时按 PUNCH_PROBE_GAP 节流复查：早上 6 点空转时日志里还没有活动，
    # 人 10 点到了才有，一次查不到就永久放弃会把上班时间永远钉在兜底值上。
    prev_probe = float(rec.get("probe") or 0) if rec else 0
    if not rec or now_p.timestamp() - prev_probe >= PUNCH_PROBE_GAP:
        detected = detect_mac_punch(win_start, win_end, now_p)
        if detected:
            save_punch(detected, "pmset")
            return detected
        probe_at = now_p.timestamp()
    else:
        probe_at = prev_probe     # 还在节流期内，沿用上次的探测时刻

    # 窗口已关且 pmset 交白卷：此刻不能当上班时间。有暂定值就地冻结（早上确实在，
    # 只是 pmset 没留痕），没有就退回固定 WORK_START/END
    if now_p > win_end:
        pending = punch_dt(rec) if rec else None
        save_punch(pending, "closed")
        return pending

    idle = hid_idle_seconds()
    if idle is not None:
        # macOS 有键鼠信号可用：人此刻在动才打卡，空闲就等着，别把空转的刷新记成上班
        if idle <= PUNCH_IDLE_MAX:
            prior = punch_dt(rec) if rec else None
            stamp = prior if (prior and rec.get("source") == "hid") else now_p
            save_punch(stamp, "hid", probe=probe_at)
            return stamp
        save_punch(None, "idle", probe=probe_at)
        return None

    # 非 macOS：没有空闲信号，只能沿用首次刷新时刻，且首刷之后不再前移
    prior = punch_dt(rec) if rec else None
    stamp = prior or now_p
    save_punch(stamp, "refresh", probe=probe_at)
    return stamp


def resolve_worktime():
    """(上班 datetime, 下班 datetime, 是否来自打卡)"""
    now_w = _dt.datetime.now()
    punch = resolve_punch()
    if punch:
        try:
            hours = float(os.environ.get("CCDAY_WORK_HOURS", "9"))
        except ValueError:
            hours = 9.0
        return punch, punch + _dt.timedelta(hours=hours), True

    ws_h, ws_m = parse_hhmm(os.environ.get("CCDAY_WORK_START", "10:00"), 10, 0)
    we_h, we_m = parse_hhmm(os.environ.get("CCDAY_WORK_END", "19:30"), 19, 30)
    start_dt = now_w.replace(hour=ws_h, minute=ws_m, second=0, microsecond=0)
    end_dt   = now_w.replace(hour=we_h, minute=we_m, second=0, microsecond=0)
    if end_dt <= start_dt:
        # 跨天班（如 22:00→06:00）：凌晨还在昨天开始的这一班里
        if now_w < end_dt:
            start_dt -= _dt.timedelta(days=1)
        else:
            end_dt += _dt.timedelta(days=1)
    return start_dt, end_dt, False


WORK_START_DT, WORK_END_DT, FROM_PUNCH = resolve_worktime()

if weekday == 5 and today_str not in workdays:
    parts.append("🏖 休息!")
elif weekday == 6 and today_str not in workdays:
    parts.append("🏖 最后一天")
else:
    # 找下一个真正的休息日（非工作日且不是调休上班日）
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
        # 明天就休息，精确到小时（下班点跟打卡走，晚到的话周末也晚来一点）
        diff = WORK_END_DT - now
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

# ── 下班倒计时 ────────────────────────────────────────
# 只在工作日显示：上班前 🕘 待上班、工作中 🕔 剩余、过点后 🌙 加班时长
try:
    if os.environ.get("CCDAY_OFFWORK", "1") == "1" and is_workday_today:
        now_w    = _dt.datetime.now()
        start_dt = WORK_START_DT
        end_dt   = WORK_END_DT

        if now_w < start_dt:
            parts.append(f"🕘 待上班 {fmt_span((start_dt - now_w).total_seconds())}")
        elif now_w < end_dt:
            left  = (end_dt - now_w).total_seconds()
            total = (end_dt - start_dt).total_seconds()
            # 最后半小时给个更醒目的提示
            icon  = "🔥" if left <= 1800 else "🕔"
            done_pct = int((total - left) / total * 100) if total > 0 else 0
            # 打卡模式下带上实际上班时间，让人知道下班点是怎么算出来的
            tail = f"·{done_pct}%"
            if FROM_PUNCH and os.environ.get("CCDAY_PUNCH_SHOW", "1") == "1":
                tail = f"·{done_pct}% ({start_dt.strftime('%H:%M')}→{end_dt.strftime('%H:%M')})"
            parts.append(f"{icon} 下班 {fmt_span(left)}{tail}")
        else:
            over = (now_w - end_dt).total_seconds()
            if over < 300:
                parts.append("🎉 下班了!")
            else:
                parts.append(f"🌙 加班 {fmt_span(over)}")
            # 超过下班点，每 30 分钟提醒一次收工
            notify_once("offwork", "该下班了",
                        "🌙 已加班 " + fmt_span(over) + "，收个尾吧", 1800, 0)
except Exception:
    pass

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
            parts.append(f"🍅 {mins}:{secs:02d}{label}")
        else:
            parts.append("🍅 时间到!")
except Exception:
    pass

# ── 休息提醒 ──────────────────────────────────────────
try:
    break_interval = int(os.environ.get("CCDAY_BREAK_INTERVAL", "50")) * 60
    break_duration = int(os.environ.get("CCDAY_BREAK_DURATION", "10")) * 60
    break_confirm  = os.environ.get("CCDAY_BREAK_CONFIRM", "1") == "1"
    # 全屏提醒里强制停留的秒数，0=看完可以马上关
    break_duration_hold = int(os.environ.get("CCDAY_BREAK_HOLD", "30"))
    break_start_h, break_start_m = map(int, os.environ.get("CCDAY_BREAK_START", "09:00").split(":"))
    break_end_h,   break_end_m   = map(int, os.environ.get("CCDAY_BREAK_END",   "22:00").split(":"))

    now_dt   = _dt.datetime.now()
    now_time = now_dt.time()
    in_range = _dt.time(break_start_h, break_start_m) <= now_time <= _dt.time(break_end_h, break_end_m)

    if in_range:
        if break_confirm:
            # 需要主动确认：读文件判断上次休息时间
            break_file = os.path.expanduser("~/.ccday-break.json")

            def save_break(ts, resting_flag):
                try:
                    with open(break_file, "w") as f:
                        json.dump({"ts": ts, "resting": resting_flag}, f)
                except Exception:
                    pass

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

            # 长时间没确认过休息（关机、请假、压根没用这功能）时 elapsed 会一直涨，
            # 提醒就永久常驻状态栏、弹窗还按冷却一轮轮弹。超过 2 轮就当没在用，
            # 把计时重新对齐到现在，恢复"每 interval 提醒一次"的节奏。
            if elapsed > break_interval * 2:
                save_break(time.time(), False)
                last_break = time.time()
                elapsed    = 0

            if resting:
                rest_left = int((break_duration - (time.time() - last_break)) / 60) + 1
                parts.append(f"🧘 休息中 {rest_left}min")
            elif elapsed >= break_interval:
                activities = [
                    "站起来伸个懒腰", "眺望远处20秒", "做10个深蹲",
                    "走动走动", "活动一下脖子", "闭眼休息一下",
                    "去趟洗手间", "做几个肩膀绕环",
                ]
                # 用上次休息时刻作为种子，同一轮提醒内文案固定，不随刷新闪烁
                random.seed(int(last_break // 60))
                activity = random.choice(activities)
                parts.append(f"🧘 {activity}!")
                notify_once("break", "休息一下！", "🧘 " + activity,
                            break_interval, break_duration_hold)
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
                activity = random.choice(activities)
                parts.append(f"🧘 {activity}!")
                notify_once("break", "休息一下！", "🧘 " + activity,
                            break_interval, break_duration_hold)
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
            msg = random.choice(msgs)
            parts.append(f"💧 {msg}!")
            notify_once("water", "喝水提醒", "💧 " + msg, water_interval * 60, 0)
except Exception:
    pass

# ── 饭点提醒 ──────────────────────────────────────────
# 到点后持续 CCDAY_MEAL_WINDOW 分钟显示，超时自动消失（同喝水逻辑）
try:
    meal_window = int(os.environ.get("CCDAY_MEAL_WINDOW", "30"))
    meals = [
        ("lunch",  os.environ.get("CCDAY_LUNCH",  "12:00"), "🍚", "午饭",
         ["去吃午饭", "该干饭了", "别饿着写代码", "先吃饭再改 bug"]),
        ("dinner", os.environ.get("CCDAY_DINNER", "18:00"), "🍜", "晚饭",
         ["去吃晚饭", "该干饭了", "别空着肚子加班", "先吃饭，bug 不会跑"]),
    ]
    now_m = _dt.datetime.now()
    for key, raw, icon, label, msgs in meals:
        if not raw.strip():
            continue
        mh, mm = parse_hhmm(raw, -1, -1)
        if mh < 0:
            continue
        meal_dt = now_m.replace(hour=mh, minute=mm, second=0, microsecond=0)
        late_min = (now_m - meal_dt).total_seconds() / 60
        if 0 <= late_min < meal_window:
            random.seed(today.toordinal() + mh)
            msg = random.choice(msgs)
            parts.append(f"{icon} {msg}!")
            notify_once(f"meal-{key}", f"{label}时间", f"{icon} {msg}", meal_window * 60, 0)
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
def pick_weekend_trip(hubs, seed):
    """按 HOME_LAT/LNG 找最近的 hub，返回具体城市而不是"高铁2小时内的城市"。
    离所有 hub 都超过 400km 时返回 None——宁可不显示，也别给无效信息。"""
    if not hubs:
        return None
    try:
        hlat = float(os.environ.get("HOME_LAT", "31.28"))
        hlng = float(os.environ.get("HOME_LNG", "121.52"))
    except ValueError:
        return None

    import math
    def dist(lat, lng):
        r1, r2 = math.radians(hlat), math.radians(lat)
        da = math.radians(lat - hlat)
        do = math.radians(lng - hlng)
        a = math.sin(da/2)**2 + math.cos(r1)*math.cos(r2)*math.sin(do/2)**2
        return 6371 * 2 * math.asin(math.sqrt(a))

    hub = min(hubs, key=lambda h: dist(h.get("lat", 0), h.get("lng", 0)))
    if dist(hub.get("lat", 0), hub.get("lng", 0)) > 400:
        return None
    spots = hub.get("spots", [])
    if not spots:
        return None
    # 加盐：调用方已用同一个 seed 抽过一次，直接复用会让相邻日期反复出现同一城市
    random.seed(seed * 2654435761 % 2**32)
    s = random.choice(spots)
    return f"🎒 {s['name']} {s['rail']}·{s['why']}"

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
            # 周末去哪：优先给出具体城市 + 车程，没有匹配 hub 才退回通用 nearby
            tip = pick_weekend_trip(hdata.get("weekend_trips", []), today.toordinal())
            if not tip:
                pool = [t for t in tips if t.get("type") == "nearby"
                        and t.get("season") in (season, "all")]
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

# 今日提交数：只统计当前用户，避免把同事的提交算进来
try:
    email = subprocess.check_output(
        ['git', 'config', 'user.email'],
        cwd=root, stderr=subprocess.DEVNULL, text=True
    ).strip()
    cmd = ['git', 'log', '--since=midnight', '--oneline']
    if email:
        cmd.append(f'--author={email}')
    out = subprocess.check_output(
        cmd, cwd=root, stderr=subprocess.DEVNULL, text=True
    ).strip()
    commits = len([l for l in out.splitlines() if l.strip()]) if out else 0
except Exception:
    commits = 0

parts = []
if changed:  parts.append(f'📝 {changed}')
if commits:  parts.append(f'✓ {commits}')
if behind:   parts.append(f'⬇ {behind}')
if ahead:    parts.append(f'⬆ {ahead}')
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

# ── Billing 插件（有即用，没有不用）────────────────────
# 拆到独立脚本：token/接口探测不到就静默，装了这份脚本的非 bilibili 用户不会看到报错。
# 缓存与降级逻辑都在插件内部，这里只负责拼接。
BILLING_PLUGIN="$(dirname "$0")/ccday-billing.sh"
if [ -f "$BILLING_PLUGIN" ]; then
    BILLING=$(bash "$BILLING_PLUGIN" 2>/dev/null | head -1)
    [ -n "$BILLING" ] && LINE2="${LINE2:+${LINE2} │ }${BILLING}"
fi

# ── 上下文占用 ────────────────────────────────────────
# 优先用 Claude Code 通过 stdin 传入的 transcript_path 和 model.id：
# 前者定位当前会话（而非最近改动的任意会话），后者决定窗口大小（1M / 200k）。
CTX=$(python3 -c "
import json, os, glob, time

WINDOW_1M   = 1000000
WINDOW_200K = 200000

transcript, model_id = None, ''
raw = os.environ.get('CCDAY_STDIN', '')
if raw:
    try:
        payload    = json.loads(raw)
        transcript = payload.get('transcript_path') or None
        model_id   = (payload.get('model') or {}).get('id', '') or ''
    except Exception:
        pass

if transcript and not os.path.exists(os.path.expanduser(transcript)):
    transcript = None

if transcript:
    latest = os.path.expanduser(transcript)
else:
    # 回退：扫描 projects 目录挑最近修改的会话
    files = glob.glob(os.path.expanduser('~/.claude/projects') + '/**/*.jsonl', recursive=True)
    if not files:
        exit()
    now    = time.time()
    recent = [f for f in files if now - os.path.getmtime(f) < 300]
    latest = max(recent or files, key=os.path.getmtime)

usage = None
try:
    with open(latest) as f:
        for line in f:
            try:
                d = json.loads(line)
                u = d.get('message', {}).get('usage')
                if u and u.get('input_tokens'):
                    usage = u
                if not model_id:
                    model_id = d.get('message', {}).get('model', '') or model_id
            except Exception:
                pass
except Exception:
    exit()

if not usage:
    exit()

total = (usage.get('input_tokens', 0)
       + usage.get('cache_read_input_tokens', 0)
       + usage.get('cache_creation_input_tokens', 0))

# 模型 ID 带 1m 标记的是 100 万上下文窗口，如 claude-opus-5[1m]
window = WINDOW_1M if '1m' in model_id.lower() else WINDOW_200K
pct    = round(total / window * 100)
tag    = '1M' if window == WINDOW_1M else ''
print(f'📊 ctx {pct}%{tag and \" \" + tag}')
" 2>/dev/null)
[ -n "$CTX" ] && LINE2="${CTX}${LINE2:+ │ ${LINE2}}"

# ── Git 拼入第二行 ────────────────────────────────────
[ -n "$GIT" ] && LINE2="${LINE2:+${LINE2} │ }${GIT}"

# 输出
echo "$LINE"
[ -n "${LINE2:-}" ] && echo "$LINE2"
