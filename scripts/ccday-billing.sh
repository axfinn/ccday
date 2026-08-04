#!/bin/bash
# ccday-billing.sh — 用量/余额插件（有即用，没有不用）
# 项目: https://github.com/axfinn/ccday
# 版本: v0.6.5
#
# 设计原则：能拿到就显示，拿不到就完全静默，绝不拖慢状态栏。
#   1. token 从多处按序探测，一个都没有 → 不输出
#   2. 接口地址跟随 ANTHROPIC_BASE_URL，不是内网也能用
#   3. 请求失败/接口不存在 → 负缓存，默认 30 分钟内不再重试
#   4. 字段有就渲染，没有就跳过（daily_limit / balance / pool 都是可选的）
#
# 用法:
#   bash ccday-billing.sh            # 输出一行状态栏文本，失败则无输出
#   bash ccday-billing.sh --check    # 诊断模式：打印 token 来源、接口、原始响应
#
# 配置项（~/.ccday.conf）:
#   CCDAY_BILLING          1=启用（默认），0=关闭
#   CCDAY_BILLING_TOKEN    显式指定 token，留空则自动探测
#   CCDAY_BILLING_API      完整接口地址，留空则用 $ANTHROPIC_BASE_URL/v1/billing/usage
#   CCDAY_BILLING_BUDGET   每日预算（元），0=用接口返回的 daily_limit
#   CCDAY_BILLING_FORMAT   auto|percent|remain|used|balance|full（默认 auto）
#   CCDAY_BILLING_POOL     1=额外显示团队池占用，0=不显示（默认 0）
#   CCDAY_BILLING_TTL      成功结果缓存秒数（默认 300）
#   CCDAY_BILLING_FAIL_TTL 失败后静默秒数（默认 1800）

CHECK_MODE=false
[ "${1:-}" = "--check" ] && CHECK_MODE=true

for f in "$HOME/.ccday.conf" "$HOME/.ccday.env"; do
    [ -f "$f" ] && source "$f" && break
done

[ "${CCDAY_BILLING:-1}" != "1" ] && { $CHECK_MODE && echo "CCDAY_BILLING=0，插件已关闭"; exit 0; }

export CCDAY_BILLING_TOKEN CCDAY_BILLING_API CCDAY_BILLING_BUDGET
export CCDAY_BILLING_FORMAT CCDAY_BILLING_POOL CCDAY_BILLING_TTL CCDAY_BILLING_FAIL_TTL
export CCDAY_BILLING_CHECK="$CHECK_MODE"

python3 - <<'PYEOF'
import json, os, sys, time, urllib.request, urllib.error

CHECK = os.environ.get("CCDAY_BILLING_CHECK") == "true"
CACHE = os.path.expanduser("~/.ccday-billing-cache.json")


def log(msg):
    if CHECK:
        print(msg)


def conf(key, dft=""):
    v = os.environ.get(key, "")
    return v.strip() if v and v.strip() else dft


def num(key, dft=0.0):
    try:
        return float(conf(key) or dft)
    except ValueError:
        return dft

# ── token 探测：按可靠性排序，先命中先用 ────────────────
def resolve_token():
    explicit = conf("CCDAY_BILLING_TOKEN")
    if explicit:
        return explicit, "CCDAY_BILLING_TOKEN"

    for var in ("ANTHROPIC_AUTH_TOKEN", "AICODING_API_KEY", "ANTHROPIC_API_KEY"):
        v = os.environ.get(var, "").strip()
        if v:
            return v, f"env:{var}"

    # settings.json 的 env 段：statusLine 子进程未必继承到这些变量
    for path in ("~/.claude/settings.json", "~/.claude/settings.local.json"):
        p = os.path.expanduser(path)
        try:
            with open(p) as f:
                env = (json.load(f) or {}).get("env") or {}
        except Exception:
            continue
        for var in ("ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY"):
            v = str(env.get(var, "")).strip()
            if v:
                return v, f"{path}:{var}"

    # bilibili live-code 登录态兜底
    try:
        with open(os.path.expanduser("~/.claude/live-code.json")) as f:
            v = str((json.load(f) or {}).get("token", "")).strip()
        if v:
            return v, "~/.claude/live-code.json:token"
    except Exception:
        pass

    return None, None


def resolve_api():
    explicit = conf("CCDAY_BILLING_API")
    if explicit:
        return explicit, "CCDAY_BILLING_API"
    base = conf("ANTHROPIC_BASE_URL") or os.environ.get("ANTHROPIC_BASE_URL", "").strip()
    if not base:
        return None, None
    return base.rstrip("/") + "/v1/billing/usage", "ANTHROPIC_BASE_URL"


# ── 缓存：成功结果和失败状态用同一个文件，靠 ok 字段区分 ──
def load_cache():
    try:
        with open(CACHE) as f:
            d = json.load(f)
    except Exception:
        return None
    if "ok" not in d:
        return None      # v0.6.3 及更早的缓存没有 ok 字段，当未命中重新请求
    age = time.time() - d.get("ts", 0)
    if d.get("ok"):
        return d.get("text") if age < num("CCDAY_BILLING_TTL", 300) else None
    # 失败过就先安静一会儿，别每次刷新都去撞一个不通的接口
    return "" if age < num("CCDAY_BILLING_FAIL_TTL", 1800) else None


def save_cache(ok, text=""):
    try:
        with open(CACHE, "w") as f:
            json.dump({"ts": time.time(), "ok": ok, "text": text}, f, ensure_ascii=False)
    except Exception:
        pass


def fetch(api, token):
    req = urllib.request.Request(api, headers={
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
        "User-Agent": "ccday-billing/0.6.4",
    })
    with urllib.request.urlopen(req, timeout=3) as r:
        return json.loads(r.read())


def fmt_money(v):
    """金额取整到 0.1，超过 1 万压成 1.2w 免得挤爆状态栏"""
    if abs(v) >= 10000:
        return f"{v / 10000:.1f}w"
    if abs(v) >= 100:
        return f"{v:.0f}"
    return f"{v:.1f}"


def render(data):
    """按可用字段拼装。budget 优先取用户配置，其次接口 daily_limit。"""
    used = data.get("daily_usage")
    if used is None:
        used = data.get("daily_used")          # 兼容早期字段名
    pct = data.get("daily_percent")
    limit = data.get("daily_limit")
    balance = data.get("balance")

    own_budget = num("CCDAY_BILLING_BUDGET", 0)
    budget = own_budget or (float(limit) if limit else 0)
    fmt = conf("CCDAY_BILLING_FORMAT", "auto")

    # 有预算又有用量时才能算余额，否则退回百分比
    can_remain = budget > 0 and used is not None
    # 用户自定义预算时按自己的预算算百分比，接口的 daily_percent 是按 daily_limit 算的，
    # 直接沿用会让预警阈值失效（比如预算 200 已用 187，接口只报 47%）
    if can_remain and (pct is None or own_budget > 0):
        pct = float(used) / budget * 100

    seg = None
    if fmt == "balance" and balance is not None:
        seg = f"💰余额{fmt_money(float(balance))}¥"
    elif fmt == "used" and used is not None:
        seg = f"💰用{fmt_money(float(used))}¥"
    elif fmt == "percent" and pct is not None:
        seg = f"💰{float(pct):.0f}%"
    elif fmt == "full" and can_remain:
        seg = f"💰{fmt_money(float(used))}/{fmt_money(budget)}¥·{float(pct):.0f}%"
    elif fmt in ("remain", "auto") and can_remain:
        seg = f"💰余{fmt_money(budget - float(used))}¥"
    elif pct is not None:
        seg = f"💰{float(pct):.0f}%"
    elif balance is not None:
        seg = f"💰余额{fmt_money(float(balance))}¥"

    if seg is None:
        return None

    # 快用完了给个视觉预警，光看数字容易忽略
    if pct is not None:
        # 用四舍五入后的值判断，避免显示 75% 却不亮 🔥 这种自相矛盾
        p = round(float(pct))
        if p >= 90:
            seg = "🈵" + seg[1:]
        elif p >= 75:
            seg = "🔥" + seg[1:]

    if conf("CCDAY_BILLING_POOL") == "1" and data.get("pool_percent") is not None:
        seg += f" 🏊{float(data['pool_percent']):.0f}%"
    return seg


token, token_src = resolve_token()
api, api_src = resolve_api()

if not token or not api:
    # 没 token 或没接口地址就是"没有"，静默退出，不写缓存
    log(f"未启用：token={token_src or '未找到'} api={api_src or '未找到'}")
    sys.exit(0)

log(f"token 来源: {token_src}")
log(f"接口地址: {api}  (来源 {api_src})")

if not CHECK:
    cached = load_cache()
    if cached is not None:
        if cached:
            print(cached)
        sys.exit(0)

try:
    payload = fetch(api, token)
except Exception as e:
    log(f"请求失败: {type(e).__name__}: {e}")
    save_cache(False)
    sys.exit(0)

if CHECK:
    print("原始响应:")
    print(json.dumps(payload, ensure_ascii=False, indent=2))

data = payload.get("data") if isinstance(payload, dict) else None
if not isinstance(data, dict) or not data:
    log("响应里没有 data 字段，判定为接口不可用")
    save_cache(False)
    sys.exit(0)

text = render(data)
if not text:
    log("data 里没有可渲染的用量字段")
    save_cache(False)
    sys.exit(0)

save_cache(True, text)
print(("状态栏输出: " if CHECK else "") + text)
PYEOF
