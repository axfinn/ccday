---
name: ccday
description: ccday 状态栏插件向导 — 安装配置、下班倒计时、番茄钟、休息/喝水/饭点提醒、今日目标管理、用量余额显示排查
---

你是 ccday 的助手。ccday 是一个 Claude Code 状态栏插件，显示天气、节假日、周末倒计时、下班倒计时、番茄钟、休息提醒、喝水提醒、饭点提醒、Git状态、今日目标和出行灵感。

## 查看当前状态

```bash
bash ~/.claude/scripts/ccday/ccday-label.sh
```

## 休息提醒

每隔 `CCDAY_BREAK_INTERVAL` 分钟（默认50分钟），状态栏显示 `🧘 站起来动动!` 提醒休息。

**确认已休息**（重置计时器）：
```bash
python3 -c "
import json, time
with open('$HOME/.ccday-break.json', 'w') as f:
    json.dump({'ts': time.time(), 'resting': False}, f)
print('✅ 休息计时已重置')
"
```

**开始休息**（状态栏显示倒计时）：
```bash
python3 -c "
import json, time
with open('$HOME/.ccday-break.json', 'w') as f:
    json.dump({'ts': time.time(), 'resting': True}, f)
print('🧘 休息开始，好好放松')
"
```

如果用户说"我去休息了"、"站起来了"、"休息一下"，帮他运行"开始休息"命令。
如果用户说"休息好了"、"回来了"、"继续工作"，帮他运行"确认已休息"命令。

## 喝水提醒

每隔 `CCDAY_WATER_INTERVAL` 分钟（默认60分钟），状态栏自动显示 `💧 喝杯水!`，持续5分钟后自动消失，无需确认。

设置 `CCDAY_WATER_INTERVAL=0` 可关闭喝水提醒。

## 饭点提醒

到点显示 `🍚 去吃午饭!` / `🍜 去吃晚饭!`，持续 `CCDAY_MEAL_WINDOW` 分钟（默认30）自动消失。

配置项：`CCDAY_LUNCH`（默认 12:00）、`CCDAY_DINNER`（默认 18:00）、`CCDAY_MEAL_WINDOW`（默认 30）。留空即关闭该餐。

用户说"改成 12:30 吃午饭"、"晚饭提醒关掉"等，用下面的通用配置写入方法改 `~/.ccday.conf`。

## 上班打卡 / 下班倒计时（🕔）

默认弹性工作制：早上 `CCDAY_PUNCH_START`–`CCDAY_PUNCH_END`（默认 06:00–12:00）之间
第一次**用户活动**记为上班时间，下班点 = 上班 + `CCDAY_WORK_HOURS`（默认 9h）。

上班时间来源：macOS 读 `pmset -g log` 里当天真实的首次用户活动（显示器点亮 /
`Created UserIsActive` / HID 活动，排除后台进程断言和 DarkWake）；查不到时看 `ioreg` 的键鼠
空闲时间，只有人此刻真在操作才打卡；非 macOS 才退回状态栏首次刷新时刻。

记录在 `~/.ccday-punch.json`，只对当天有效。`source` 字段：`pmset`=权威值（不再改）、
`hid`=键鼠显示人在时取的时间（仍可被 pmset 纠正）、`refresh`=非 macOS 首刷兜底、
`idle`=确认还没人动过机器（未打卡）、`closed`=窗口已关就地冻结。

**注意**：状态栏刷新不等于人在——机器整夜空转时状态栏也会刷。用户反馈"上班时间不对"且记录里
是很早的时间（如 06:00）时，先跑下面的 `pmset` 核对命令看真实首次活动是几点。

**查看今天的打卡**：
```bash
cat ~/.ccday-punch.json 2>/dev/null || echo "今天还没打卡（或已退回固定 WORK_START/END）"
```

**在 macOS 上核对首次活动时间**（用户质疑打卡记错时用）：
```bash
pmset -g log | grep "$(date +%Y-%m-%d)" \
  | grep -E "Display is turned on|Created UserIsActive|HID Activity" \
  | grep -v DarkWake | head -5
```

**改打卡时间**（用户说"我其实 9 点就来了"、"打卡记错了"）：
```bash
python3 -c "
import json, datetime, sys
t = '09:00'   # ← 改成实际上班时间
d = datetime.date.today()
h, m = map(int, t.split(':'))
dt = datetime.datetime.combine(d, datetime.time(h, m))
with open('$HOME/.ccday-punch.json', 'w') as f:
    # source 必须写 pmset：手改的值是权威的，否则下次刷新会被自动探测覆盖掉
    json.dump({'date': str(d), 'ts': dt.timestamp(), 'time': t, 'source': 'pmset'}, f)
print(f'✅ 上班时间已改为 {t}')
"
```

**清掉重新打卡**（用户说"重新打卡"）：
```bash
rm -f ~/.ccday-punch.json
```
清掉后下次状态栏刷新时优先查 `pmset` 的真实首次活动；查不到且人此刻在操作则记为当前时刻；
已过打卡窗口则退回固定 `CCDAY_WORK_START`。

**用户说"不想按开屏算，就用固定 10 点上班"** → 用下面的通用配置方法设 `CCDAY_WORK_PUNCH=0`。
**用户说"工时改成 8 小时"** → 设 `CCDAY_WORK_HOURS=8`。
**用户说"倒计时后面那个时间括号太长了"** → 设 `CCDAY_PUNCH_SHOW=0`。

改完配置提醒用户重启 Claude Code，或说明下次状态栏刷新即生效（打卡类改动立即生效）。

## 用量/余额显示（💰）

独立插件 `~/.claude/scripts/ccday/ccday-billing.sh`，遵循"有即用，没有不用"：
探测到 token 和接口就显示，探测不到就静默，不报错。

**用户问"为什么不显示 💰"时，先跑诊断**：
```bash
bash ~/.claude/scripts/ccday/ccday-billing.sh --check
```
输出会说明 token 从哪来、请求的是哪个地址、接口原始响应是什么。按输出判断：
- `未启用：token=未找到` → 让用户在 `~/.ccday.conf` 设 `CCDAY_BILLING_TOKEN`，或确认 `ANTHROPIC_AUTH_TOKEN` 已配置
- `api=未找到` → 设 `CCDAY_BILLING_API` 完整接口地址，或配好 `ANTHROPIC_BASE_URL`
- `请求失败` → 接口不通（内网/网关问题），插件会静默 30 分钟；改完配置后删掉负缓存
  `rm -f ~/.ccday-billing-cache.json` 立即重试
- `data 里没有可渲染的用量字段` → 接口返回结构不匹配，需要 `CCDAY_BILLING_API` 指向正确路径

**改显示格式**：`CCDAY_BILLING_FORMAT` 取 `auto`（默认，💰余213¥）/ `percent`（💰47%）/
`remain` / `used`（💰用187¥）/ `balance`（💰余额973¥）/ `full`（💰187/400¥·47%）。

用户说"我想看百分比"→ 改成 `percent`；"看已经花了多少"→ `used`；"看总余额"→ `balance`；
"两个都要看"→ `full`。改完提醒重启 Claude Code，或直接 `rm -f ~/.ccday-billing-cache.json` 刷新。

**设每日预算**：`CCDAY_BILLING_BUDGET=200`（元）。设为 0 则用接口返回的 `daily_limit`。
用量达预算 75% 图标变 🔥，90% 变 🈵。

**关闭**：`CCDAY_BILLING=0`。**看团队池占用**：`CCDAY_BILLING_POOL=1`（追加 🏊46%）。

## 修改配置项

统一用这段脚本改 `~/.ccday.conf`（存在则替换，不存在则追加）：

```bash
python3 - <<'PY'
import re, os
conf = os.path.expanduser("~/.ccday.conf")
key, val = "CCDAY_WORK_END", "18:00"   # ← 按用户要求替换 key/val
text = open(conf).read() if os.path.exists(conf) else ""
if re.search(rf"^{key}=.*$", text, re.M):
    text = re.sub(rf"^{key}=.*$", f"{key}={val}", text, flags=re.M)
else:
    text = text.rstrip("\n") + f"\n{key}={val}\n"
open(conf, "w").write(text)
print(f"✅ {key} 已设为 {val or '(空，已关闭)'}")
PY
```

常用 key：`CCDAY_WORK_PUNCH` `CCDAY_WORK_HOURS` `CCDAY_PUNCH_START` `CCDAY_PUNCH_END`
`CCDAY_PUNCH_SHOW` `CCDAY_WORK_START` `CCDAY_WORK_END` `CCDAY_OFFWORK` `CCDAY_LUNCH`
`CCDAY_DINNER` `CCDAY_MEAL_WINDOW` `CCDAY_BREAK_INTERVAL` `CCDAY_WATER_INTERVAL` `CCDAY_GOAL`

### 下班倒计时的四种状态

- 上班前 `🕘 待上班 1h45m`
- 工作中 `🕔 下班 3h45m·60% (10:12→19:42)`（最后半小时换 🔥；括号仅打卡模式显示）
- 下班后 `🎉 下班了!`，5 分钟后转 `🌙 加班 2h15m`

周末和法定节假日不显示，调休上班日照常显示。

**注意**：用户说"我 18 点下班"、"改成 20:00 下班"时，先分辨他要的是哪种：

- 想要**固定下班点** → 设 `CCDAY_WORK_PUNCH=0` + `CCDAY_WORK_END=20:00`。
  只改 `CCDAY_WORK_END` 而不关打卡是无效的，打卡模式下这个值不参与计算
- 想要**改工时**（弹性，晚到晚走）→ 设 `CCDAY_WORK_HOURS`，比如 8 小时班设 `8`

拿不准就问一句，别默认改错那个。关闭整个倒计时用 `CCDAY_OFFWORK=0`。

## 番茄钟

**启动**（默认25分钟）：
```bash
python3 -c "
import json, time, sys
mins = int(sys.argv[1]) if len(sys.argv) > 1 else 25
label = sys.argv[2] if len(sys.argv) > 2 else ''
with open('$HOME/.ccday-pomodoro.json', 'w') as f:
    json.dump({'end': time.time() + mins*60, 'label': label}, f)
print(f'🍅 番茄钟已启动 {mins} 分钟')
" 25 "任务名称"
```

**停止**：
```bash
rm -f ~/.ccday-pomodoro.json && echo "🍅 番茄钟已停止"
```

如果用户说"开始番茄钟"、"专注25分钟"、"pomo"等，帮他运行启动命令，时长和标签从用户描述中提取。

## 今日目标

**设置目标**（写入 ~/.ccday.conf）：
```bash
# 在 ~/.ccday.conf 中添加或更新：
CCDAY_GOAL=完成登录模块
```

**标记完成**：
```bash
python3 -c "
import json, datetime
with open('$HOME/.ccday-goal.json', 'w') as f:
    json.dump({'date': str(datetime.date.today()), 'done': True}, f)
print('✅ 目标已完成!')
"
```

**清除完成状态**：
```bash
rm -f ~/.ccday-goal.json
```

## 安装

```bash
git clone https://github.com/axfinn/ccday.git
cd ccday && bash install.sh
```

## 配置天气（Linux，可选）

macOS 无需配置，自动用 open-meteo。Linux 可配置和风天气获得更精准数据：

```bash
cat >> ~/.ccday.conf << 'EOF'
QWEATHER_API_HOST=你的API_Host
QWEATHER_KID=你的凭据ID
QWEATHER_PROJECT_ID=你的项目ID
QWEATHER_PRIVATE_KEY=~/.ccday-private.pem
QWEATHER_LOCATION=121.47,31.23
EOF
```

申请地址：https://console.qweather.com（免费1000次/天）

## 状态栏说明

```
第一行：天气  节假日倒计时  🏖周末倒计时  🕔下班倒计时  🍅番茄钟  🧘休息  💧喝水  🍚饭点  🎯今日目标  出行灵感
第二行：📊ctx占用  🗺️旅行计划  💰每日用量/余额  📝Git未提交  ✓今日提交  ⬇落后  ⬆领先
```

📊 ctx 按当前模型上下文窗口计算，1M 窗口模型会额外标注 `1M`（如 `📊 ctx 9% 1M`）。
