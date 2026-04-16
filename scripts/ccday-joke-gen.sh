#!/bin/bash
# ccday-joke-gen.sh — 用 claude CLI 生成今日段子，缓存到 ~/.ccday-joke-cache.json
# 由 Claude Code Stop hook 调用，或手动执行
# 配置：~/.ccday.conf 中设置 CCDAY_AI_JOKE=1 启用

for f in "$HOME/.ccday.conf" "$HOME/.ccday.env"; do
    [ -f "$f" ] && source "$f" && break
done

[ "${CCDAY_AI_JOKE:-0}" != "1" ] && exit 0

JOKE_CACHE="$HOME/.ccday-joke-cache.json"
TODAY=$(date +%Y-%m-%d)

# 已有今天的就跳过
if [ -f "$JOKE_CACHE" ]; then
    CACHED=$(python3 -c "import json; print(json.load(open('$JOKE_CACHE')).get('date',''))" 2>/dev/null)
    [ "$CACHED" = "$TODAY" ] && exit 0
fi

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

if [ -n "$CONTEXT" ]; then
    PROMPT="程序员今天在做：${CONTEXT}。根据这个写一条幽默段子或打气的话，15字以内，带emoji开头，直接输出"
else
    PROMPT="写一条程序员段子或打气的话，幽默接地气，15字以内，带emoji开头，直接输出"
fi

JOKE=$(claude -p "$PROMPT" --output-format text 2>/dev/null | head -1 | python3 -c "import sys; print(sys.stdin.read().strip().strip('\"').strip(\"'\"))")

if [ -n "$JOKE" ]; then
    python3 -c "
import json, sys
joke, today, path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, 'w') as f:
    json.dump({'date': today, 'joke': joke}, f, ensure_ascii=False)
" "$JOKE" "$TODAY" "$JOKE_CACHE"
fi
