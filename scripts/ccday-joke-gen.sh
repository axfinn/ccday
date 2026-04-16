#!/bin/bash
# ccday-joke-gen.sh — 会话结束时更新 tip/段子缓存
# Stop hook 调用；配置项见 ~/.ccday.conf

for f in "$HOME/.ccday.conf" "$HOME/.ccday.env"; do
    [ -f "$f" ] && source "$f" && break
done

# 默认值
CCDAY_AI_JOKE="${CCDAY_AI_JOKE:-1}"
CCDAY_TIP_ROTATE="${CCDAY_TIP_ROTATE:-5}"       # 每N次会话随机换一条 tip
CCDAY_AI_JOKE_ROTATE="${CCDAY_AI_JOKE_ROTATE:-20}" # 每N次会话用 AI 生成

COUNT_FILE="$HOME/.ccday-session-count"
TIP_CACHE="$HOME/.ccday-tip-cache.json"
TODAY=$(date +%Y-%m-%d)

# 读取并递增计数
COUNT=$(cat "$COUNT_FILE" 2>/dev/null | tr -d '[:space:]')
COUNT=$(( ${COUNT:-0} + 1 ))
echo "$COUNT" > "$COUNT_FILE"

# 读 Stop hook 传入的 transcript，提取工作上下文
CONTEXT=$(cat 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    msgs = data.get('transcript', [])
    user_msgs = [str(m.get('content',''))[:60] for m in msgs if m.get('role')=='user'][-4:]
    print(' '.join(user_msgs)[:150])
except:
    print('')
" 2>/dev/null)

# 判断是否需要刷新
NEED_AI=false
NEED_ROTATE=false

[ "$CCDAY_AI_JOKE" = "1" ] && [ $(( COUNT % CCDAY_AI_JOKE_ROTATE )) -eq 0 ] && NEED_AI=true
[ $(( COUNT % CCDAY_TIP_ROTATE )) -eq 0 ] && NEED_ROTATE=true

# AI 生成
if $NEED_AI; then
    if [ -n "$CONTEXT" ]; then
        PROMPT="程序员今天在做：${CONTEXT}。根据这个写一条幽默段子或打气的话，15字以内，带emoji开头，直接输出"
    else
        PROMPT="写一条程序员段子或打气的话，幽默接地气，15字以内，带emoji开头，直接输出"
    fi
    JOKE=$(claude -p "$PROMPT" --output-format text 2>/dev/null | head -1 \
        | python3 -c "import sys; print(sys.stdin.read().strip().strip('\"').strip(\"'\"))")
    if [ -n "$JOKE" ]; then
        python3 -c "
import json, sys
with open(sys.argv[1], 'w') as f:
    json.dump({'date': sys.argv[2], 'count': int(sys.argv[3]), 'tip': sys.argv[4], 'source': 'ai'}, f, ensure_ascii=False)
" "$TIP_CACHE" "$TODAY" "$COUNT" "$JOKE"
        exit 0
    fi
fi

# 随机换 tip（从 holidays.json 静态池）
if $NEED_ROTATE; then
    HOLIDAYS_JSON="$HOME/.claude/scripts/ccday/holidays.json"
    [ ! -f "$HOLIDAYS_JSON" ] && exit 0
    python3 - "$TIP_CACHE" "$TODAY" "$COUNT" "$HOLIDAYS_JSON" <<'PYEOF'
import json, sys, random

cache_path, today, count, hfile = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
with open(hfile) as f:
    hdata = json.load(f)

jokes = hdata.get("jokes", [])
tips = hdata.get("travel_tips", [])
import datetime
month = datetime.date.today().month
season = "spring" if 3<=month<=5 else "summer" if 6<=month<=8 else "autumn" if 9<=month<=11 else "winter"

random.seed(count)
r = random.random()
if jokes and r < 0.5:
    tip = random.choice(jokes)
elif r < 0.7:
    pool = [t for t in tips if t.get("type") == "annual" and t.get("season") in (season, "all")]
    tip = random.choice(pool)["tip"] if pool else random.choice(jokes) if jokes else None
else:
    pool = [t for t in tips if t.get("type") == "nearby"]
    tip = random.choice(pool)["tip"] if pool else random.choice(jokes) if jokes else None

if tip:
    with open(cache_path, "w") as f:
        json.dump({"date": today, "count": count, "tip": tip, "source": "static"}, f, ensure_ascii=False)
PYEOF
fi
