# ccday

> Claude Code 状态栏插件 — 天气 · 节假日 · 周末倒计时 · 下班倒计时 · 番茄钟 · 休息/喝水/饭点提醒 · 今日目标 · Git状态 · 出行灵感

**版本：v0.6.6**

在 Claude Code 底部状态栏实时显示两行信息：

```
🌫 18° 雾  🔨 劳动节·14天  🏖 还8h  🕔 下班 3h45m·60%  🍅24:59 写文档  🧘 站起来伸个懒腰!  🍚 去吃午饭!  🎯 完成登录模块
📊 ctx 76%  │  🗺️ 长兴岛郊野公园 22km·1天后 · 带足够的水  │  💰余213¥  │  📝3 ✓5 ⬇1
```

**第一行**：天气 · 节假日倒计时 · 周末倒计时 · 🕔下班倒计时 · 🍅番茄钟 · 🧘休息提醒 · 💧喝水提醒 · 🍚饭点提醒 · 🎯今日目标 · 出行灵感/段子
**第二行**：📊上下文占用 · 🗺️旅行计划 · 💰每日用量/余额 · 📝Git状态

- **macOS** — open-meteo 免费天气，无需任何配置
- **Linux** — 优先和风天气 API，无配置时自动 fallback 到 open-meteo
- **天气缓存** — 30分钟内不重复请求，状态栏不卡顿
- **调休感知** — 周末/下班倒计时识别调休上班日和节假日
- **下班倒计时** — 弹性工作制：早上首次用户活动记为上班（macOS 读 `pmset` 真实活动时间），下班点 = 上班 + 9h，进度百分比 + 最后半小时高亮，过点显示加班时长
- **上下文自适应** — 按当前模型窗口计算（1M / 200k），不再按固定 200k 估算
- **休息提醒** — 每隔 N 分钟提醒活动，支持强确认（有倒计时）或自动消失两种模式
- **喝水提醒** — 每隔 N 分钟自动显示 5 分钟后消失，无需确认
- **饭点提醒** — 午饭/晚饭到点显示 30 分钟后自动消失，同时触发系统通知
- **用量插件** — 独立脚本，token/接口探测到就显示 💰，探测不到自动静默，接口不通时负缓存不重试

---

## 快速开始

```bash
git clone https://github.com/axfinn/ccday.git
cd ccday && bash install.sh
```

重启 Claude Code，状态栏自动生效。

## 更新

```bash
cd ccday && bash update.sh
```

拉取远端新版本并更新脚本/skill，**不覆盖用户配置**（`~/.ccday.conf`）。

即使远端没有新提交，只要已安装的文件和仓库不一致（改过本地代码、装了一半），
也会重新安装；工作区有未提交改动或有未推送的提交时**不会** `git pull` 覆盖你的代码。
另外会检查 `settings.json` 的挂载点是否齐全，缺 statusLine / Stop hook 时提示跑 `install.sh`。

---

## 功能说明

### 下班倒计时（弹性工作制）

**默认按当天第一次用户活动打卡**：早上 06:00–12:00 之间的首次活动记为上班时间，
下班点 = 上班 + `CCDAY_WORK_HOURS`。晚到晚走，不按死的 10:00 算。

```bash
CCDAY_WORK_PUNCH=1        # 1=按首次用户活动打卡（默认），0=用固定 WORK_START/END
CCDAY_WORK_HOURS=9        # 工时（默认 9 小时）
CCDAY_PUNCH_START=06:00   # 打卡有效窗口开始
CCDAY_PUNCH_END=12:00     # 打卡有效窗口结束
CCDAY_PUNCH_SHOW=1        # 1=倒计时带上 (10:22→19:22)，0=只显示剩余时间
CCDAY_OFFWORK=1           # 0 可关闭整个倒计时
```

**上班时间怎么取**（按优先级）：

1. **macOS** — `pmset -g log` 里当天窗口内第一次真实用户活动：显示器点亮、
   `Created UserIsActive` 断言、HID 活动。比"状态栏首次刷新"准，早上先开邮件、
   晚点才开 Claude Code 也不会把上班时间记晚。
   后台进程断言（`cloudd` / `coreaudiod` / `runningboardd` 之类）和 `DarkWake` 不算
   —— 机器自己醒来收邮件不等于人到了
2. **其他平台**（或 `pmset` 取不到）— 退回状态栏在窗口内的首次刷新时刻

`pmset` 每天只在首次判定时调用一次，之后读缓存，不会每次刷新状态栏都去拉日志。

效果：

```
09:30 首次活动 → 🕔 下班 8h30m·10% (09:30→18:30)
10:22 首次活动 → 🕔 下班 1h10m·86% (10:22→19:22)
11:40 首次活动 → 🕔 下班 3h08m·67% (11:40→20:40)
```

打卡记录在 `~/.ccday-punch.json`（含 `source` 字段标明来自 `pmset` 还是 `refresh`），
**只对当天有效**，隔夜不沿用。记错了就 `rm ~/.ccday-punch.json`，下次刷新（仍在窗口内）重新打卡。

**退回固定时间**的三种情况——都用下面这组配置：

- `CCDAY_WORK_PUNCH=0` 手动关闭打卡
- 首次活动晚于 `CCDAY_PUNCH_END`（下午才开电脑，没法推断上班时间）
- 跨天班（`CCDAY_WORK_END` ≤ `CCDAY_WORK_START`，早上开屏是在下班而不是上班）

```bash
CCDAY_WORK_START=10:00    # 固定上班时间
CCDAY_WORK_END=19:30      # 固定下班时间
```

状态栏按当前时间显示四种状态：

| 时段 | 显示 | 说明 |
|------|------|------|
| 上班前 | `🕘 待上班 1h45m` | 距离上班时间 |
| 工作中 | `🕔 下班 3h45m·60% (10:22→19:22)` | 剩余时长 + 当日进度（括号仅打卡模式） |
| 最后半小时 | `🔥 下班 25m·95%` | 换成 🔥 提示收尾 |
| 过了下班点 | `🎉 下班了!` → `🌙 加班 2h15m` | 5 分钟内庆祝，之后计加班 |

只在**工作日**显示：自动跳过周末和法定节假日，识别调休上班日。支持跨天班（如 `22:00`→`06:00`）。

超过下班点后每 30 分钟触发一次系统通知提醒收工。
🏖 周末倒计时在"明天就休息"时也按同一个下班点算，晚到的话周末也晚来一点。

### 番茄钟

用 `/ccday` skill 启动，或直接运行：

```bash
# 启动 25 分钟番茄钟
python3 -c "
import json, time
with open('$HOME/.ccday-pomodoro.json', 'w') as f:
    json.dump({'end': time.time() + 25*60, 'label': '写代码'}, f)
"

# 停止
rm -f ~/.ccday-pomodoro.json
```

状态栏显示 `🍅24:59 写代码`，到时显示 `🍅 时间到!`。

### 今日目标

在 `~/.ccday.conf` 设置：

```bash
CCDAY_GOAL=完成登录模块
```

状态栏显示 `🎯 完成登录模块`。标记完成：

```bash
python3 -c "
import json, datetime
with open('$HOME/.ccday-goal.json', 'w') as f:
    json.dump({'date': str(datetime.date.today()), 'done': True}, f)
"
```

完成后变为 `✅ 完成登录模块`，次日自动重置。

### Git 状态

自动读取当前工作目录的 git 状态，显示在第二行：

- `📝3` — 3个未提交文件
- `✓5` — **今天已提交5次**（只统计 `git config user.email` 本人的提交）
- `⬇2` — 落后远端2个提交
- `⬆1` — 领先远端1个提交

无需配置，开箱即用。各项为 0 时自动隐藏。

### 出行灵感 & AI 段子

每次会话结束（Stop hook）自动更新：

- **每 5 次会话**（`CCDAY_TIP_ROTATE`）：从静态池随机换一条
- **每 20 次会话**（`CCDAY_AI_JOKE_ROTATE`）：调用 `claude` CLI 根据对话内容生成专属段子

周末灵感（🎒）按 `HOME_LAT`/`HOME_LNG` 找最近的城市圈，给**具体目的地 + 车程 + 去干什么**：

```
🎒 苏州 30分·平江路+园林      # 上海
🎒 天津 35分·五大道+煎饼      # 北京
🎒 都江堰 35分·青城山爬山     # 成都
```

内置 10 个城市圈：上海、北京、广州、深圳、杭州、成都、武汉、西安、南京、重庆。离这些城市都超过 400km 时不硬凑目的地，退回通用的近郊建议。想加自己的城市，编辑 `holidays.json` 的 `weekend_trips`。

### 休息提醒

每隔 `CCDAY_BREAK_INTERVAL` 分钟（默认50分钟），状态栏显示 `🧘 站起来伸个懒腰!` 等随机提示，同时触发提醒弹窗。

macOS 会弹出**全屏提醒页面**（Safari），带随机段子，双击可强制关闭。Linux 使用 `notify-send` 系统通知。

只有久坐提醒带强制停留倒计时（`CCDAY_BREAK_HOLD`，默认 30 秒，倒计时结束前点击会被怼）。
下班、喝水、饭点提醒看完即可关闭——提醒你别久坐的东西不该再把你按在屏幕前。
四种提醒各用独立的临时文件与标题/图标/段子，不会出现「休息一下！」配「已加班 2m」这种错配。

两种模式（`CCDAY_BREAK_CONFIRM`）：

- **`1`（默认）强确认模式** — 需要主动确认才重置计时器，状态栏持续显示直到确认
- **`0` 自动消失模式** — 到点显示5分钟后自动消失，无需操作

```bash
# 确认已休息（重置计时器）
python3 -c "import json,time; open('$HOME/.ccday-break.json','w').write(json.dumps({'ts':time.time(),'resting':False}))"

# 开始休息（状态栏显示倒计时）
python3 -c "import json,time; open('$HOME/.ccday-break.json','w').write(json.dumps({'ts':time.time(),'resting':True}))"
```

用 `/ccday` skill 可一键操作。

### 喝水提醒

每隔 `CCDAY_WATER_INTERVAL` 分钟（默认60分钟），状态栏自动显示 `💧 喝杯水!`，持续5分钟后自动消失，同时触发系统通知弹窗。设置 `CCDAY_WATER_INTERVAL=0` 可关闭。

### 饭点提醒

到点后状态栏显示 `🍚 去吃午饭!` / `🍜 去吃晚饭!`，持续 `CCDAY_MEAL_WINDOW` 分钟（默认30）自动消失，同时触发一次系统通知。

```bash
CCDAY_LUNCH=12:00         # 午饭时间（默认 12:00）
CCDAY_DINNER=18:00        # 晚饭时间（默认 18:00）
CCDAY_MEAL_WINDOW=30      # 持续显示 N 分钟
```

留空即关闭该餐，如 `CCDAY_LUNCH=` 只保留晚饭提醒。文案每天一换，同一餐内不变。

---

## 完整配置说明

`~/.ccday.conf` 所有配置项（参考 `ccday.conf.example`）：

```bash
# ── 天气（可选，不填自动用 open-meteo）──────────────────────
QWEATHER_API_HOST=mv4gkk5acy.re.qweatherapi.com
QWEATHER_KID=你的凭据ID
QWEATHER_PROJECT_ID=你的项目ID
QWEATHER_PRIVATE_KEY=~/.ccday-private.pem
QWEATHER_LOCATION=121.47,31.23        # 经纬度（open-meteo 也用此项）

# ── 出发地（旅行距离 + 🎒周末出行灵感的目的地都按此坐标算）──
HOME_LAT=31.28
HOME_LNG=121.52

# ── 旅行计划（可选）────────────────────────────────────────
TRIP_NAME=长兴岛郊野公园
TRIP_LAT=31.38
TRIP_LNG=121.72
TRIP_DATE=2026-05-01
TRIP_TIPS="带防晒霜;穿舒适的鞋;早点出发;带足够的水"   # 分号分隔，每天轮换

# ── 今日目标（可选）────────────────────────────────────────
CCDAY_GOAL=完成登录模块

# ── 上下班时间（弹性工作制）─────────────────────────────────
CCDAY_OFFWORK=1                       # 1=显示下班倒计时，0=隐藏
CCDAY_WORK_PUNCH=1                    # 1=按首次用户活动打卡（默认），0=用固定时间
CCDAY_WORK_HOURS=9                    # 打卡模式工时（默认 9 小时）
CCDAY_PUNCH_START=06:00               # 打卡有效窗口开始（默认 06:00）
CCDAY_PUNCH_END=12:00                 # 打卡有效窗口结束（默认 12:00）
CCDAY_PUNCH_SHOW=1                    # 1=倒计时带上 (10:22→19:22)
CCDAY_WORK_START=10:00                # 固定上班时间（未打卡时兜底）
CCDAY_WORK_END=19:30                  # 固定下班时间（未打卡时兜底）

# ── Tip/段子刷新频率 ────────────────────────────────────────
CCDAY_AI_JOKE=1                       # 启用 AI 生成段子
CCDAY_TIP_ROTATE=5                    # 每 N 次会话随机换 tip
CCDAY_AI_JOKE_ROTATE=20               # 每 N 次会话 AI 生成

# ── 休息提醒 ────────────────────────────────────────────────
CCDAY_BREAK_INTERVAL=50               # 每隔 N 分钟提醒休息（默认 50）
CCDAY_BREAK_DURATION=10               # 休息时长 N 分钟（默认 10，仅 CONFIRM=1 时有效）
CCDAY_BREAK_HOLD=30                   # 久坐全屏提醒强制停留秒数（默认 30，0=可立即关闭）
CCDAY_BREAK_CONFIRM=1                 # 1=需要主动确认（有倒计时），0=定时自动消失
CCDAY_BREAK_START=09:00               # 提醒生效开始时间（默认 09:00）
CCDAY_BREAK_END=22:00                 # 提醒生效结束时间（默认 22:00）

# ── 喝水提醒 ────────────────────────────────────────────────
CCDAY_WATER_INTERVAL=60               # 每隔 N 分钟提醒喝水（默认 60，设 0 关闭）

# ── 饭点提醒 ────────────────────────────────────────────────
CCDAY_LUNCH=12:00                     # 午饭时间（默认 12:00，留空关闭）
CCDAY_DINNER=18:00                    # 晚饭时间（默认 18:00，留空关闭）
CCDAY_MEAL_WINDOW=30                  # 到点后持续显示 N 分钟（默认 30）

# ── 用量/余额插件（有即用，没有不用）──────────────────────────
CCDAY_BILLING=1                       # 1=启用 💰 用量，0=关闭
# CCDAY_BILLING_TOKEN=                # 显式指定 token，留空自动探测
# CCDAY_BILLING_API=                  # 完整接口地址，留空按 ANTHROPIC_BASE_URL 推导
CCDAY_BILLING_BUDGET=0                # 每日预算（元），0=用接口返回的 daily_limit
CCDAY_BILLING_FORMAT=auto             # auto|percent|remain|used|balance|full
CCDAY_BILLING_POOL=0                  # 1=额外显示团队池占用 🏊
CCDAY_BILLING_TTL=300                 # 成功结果缓存秒数（默认 300）
CCDAY_BILLING_FAIL_TTL=1800           # 请求失败后静默秒数（默认 1800）
```

---

## 用量/余额插件

独立脚本 `scripts/ccday-billing.sh`，**有即用，没有不用**：探测到 token 和接口就在第二行显示 `💰`，
探测不到就完全静默，不报错、不拖慢状态栏。所以这份配置对所有人都是安全默认值，不需要按环境改。

**token 探测顺序**（先命中先用）：

1. `CCDAY_BILLING_TOKEN`（配置文件里显式指定）
2. 环境变量 `ANTHROPIC_AUTH_TOKEN` → `AICODING_API_KEY` → `ANTHROPIC_API_KEY`
3. `~/.claude/settings.json` / `settings.local.json` 的 `env` 段
   （statusLine 子进程未必继承到这些变量，所以直接读文件兜底）
4. `~/.claude/live-code.json` 的 `token` 字段

**接口地址**默认取 `$ANTHROPIC_BASE_URL` + `/v1/billing/usage`，跟着你的网关走；
自建网关路径不同时用 `CCDAY_BILLING_API` 写完整地址。

**诊断**：

```bash
bash ~/.claude/scripts/ccday/ccday-billing.sh --check
```

会打印 token 来源、实际请求地址、接口原始响应和最终状态栏文本，
排查"为什么不显示 💰"时先跑这个。

**显示格式**（`CCDAY_BILLING_FORMAT`）：

| 值 | 效果 | 说明 |
|----|------|------|
| `auto` | `💰余213¥` | 默认。能算余额就显示余额，否则退回百分比 |
| `percent` | `💰47%` | 只看百分比 |
| `remain` | `💰余213¥` | 剩余额度 |
| `used` | `💰用187¥` | 今日已用 |
| `balance` | `💰余额973¥` | 账户总余额 |
| `full` | `💰187/400¥·47%` | 已用/预算·百分比 |

用量达预算 **75%** 图标变 🔥，**90%** 变 🈵。
`CCDAY_BILLING_POOL=1` 再追加团队池占用 `🏊46%`。

**降级策略**：成功结果缓存 `CCDAY_BILLING_TTL` 秒（默认 300）；
请求失败或接口返回结构不认识时写入负缓存，`CCDAY_BILLING_FAIL_TTL` 秒（默认 1800）内不再重试，
避免每次刷新状态栏都去撞一个不通的接口。单次请求超时 3 秒。

> 字段按需渲染：`daily_usage` / `daily_limit` / `daily_percent` / `balance` / `pool_percent`
> 哪个有就用哪个，接口只返回一部分也能正常显示。

---

## 申请和风天气 API（可选，Linux 用户）

> macOS 和不需要精准天气的用户可跳过。

1. 注册：[https://id.qweather.com/register](https://id.qweather.com/register)（免费 1000次/天）
2. 控制台 → 项目管理 → 新建项目，记下**项目ID**
3. 生成密钥对：
   ```bash
   openssl genpkey -algorithm ED25519 -out ~/.ccday-private.pem \
     && openssl pkey -pubout -in ~/.ccday-private.pem -out /tmp/ccday-public.pem \
     && chmod 600 ~/.ccday-private.pem \
     && cat /tmp/ccday-public.pem
   ```
4. 控制台 → 项目 → 添加凭据 → JWT → 粘贴公钥 → 记下**凭据ID**
5. 控制台 → 设置 → 找到 **API Host**

---

## Claude Code Skill

输入 `/ccday` 可快速查看状态、启动番茄钟、管理今日目标：

```bash
# install.sh 已自动安装，手动安装：
cp skills/ccday.md ~/.claude/skills/ccday.md
```

---

## 文件结构

```
ccday/
├── install.sh
├── update.sh                       # 一键更新
├── uninstall.sh
├── ccday.conf.example          # 完整示例配置
├── README.md
├── scripts/
│   ├── ccday-label.sh          # 主脚本（状态栏输出）
│   ├── ccday-joke-gen.sh       # Stop hook（更新 tip/段子缓存）
│   ├── ccday-billing.sh        # 用量插件（有即用没有不用，--check 可诊断）
│   └── holidays.json           # 节假日 + 调休 + 出行灵感 + 周末城市圈 + 段子
└── skills/
    └── ccday.md                # Claude Code skill 源文件
```

### 运行时缓存文件（~/ 目录，不进入项目）

| 文件 | 说明 |
|------|------|
| `~/.ccday.conf` | 用户配置 |
| `~/.ccday-weather-cache.json` | 天气缓存（30分钟） |
| `~/.ccday-tip-cache.json` | 当前 tip/段子缓存 |
| `~/.ccday-session-count` | 会话计数 |
| `~/.ccday-pomodoro.json` | 番茄钟状态 |
| `~/.ccday-goal.json` | 今日目标完成状态 |
| `~/.ccday-break.json` | 休息提醒状态（CONFIRM=1 时使用） |
| `~/.ccday-punch.json` | 当天上班打卡时间（首次用户活动），隔夜自动作废 |
| `~/.ccday-billing-cache.json` | 用量缓存（成功 5 分钟 / 失败 30 分钟负缓存） |
| `~/.ccday-notif-*.json` | 通知去重标记（break/water/meal-*） |
| `~/.ccday-version` | 已安装版本号 |
| `~/.ccday-private.pem` | 和风天气私钥（用户自备） |

`uninstall.sh` 会清理上表中的缓存类文件，只保留 `~/.ccday.conf` 和 `~/.ccday-private.pem`。
| `~/.ccday-notif-break.json` | 休息系统通知去重标记 |
| `~/.ccday-notif-water.json` | 喝水系统通知去重标记 |
| `~/.ccday-notif-offwork.json` | 下班/加班系统通知去重标记 |
| `~/.ccday-notif-meal-lunch.json` | 午饭系统通知去重标记 |
| `~/.ccday-notif-meal-dinner.json` | 晚饭系统通知去重标记 |

---

## 版本历史

- **v0.6.6** — 修三个提醒相关的问题。① 全屏弹窗标题写死「休息一下！」，四种提醒共用后会出现标题配错内容（如「休息一下！」配「🌙 已加班 2m」）——现在标题/图标/段子按提醒类型走，临时文件按 key 分开（`~/.ccday-alert-<key>.html`），两个提醒同时到期不再互相覆写。② 30 秒强制停留原先加在所有提醒上，下班/喝水/饭点也要干等——现在只有久坐提醒保留（`CCDAY_BREAK_HOLD`，默认 30），其余看完即可关。③ `CONFIRM=1` 模式下久没确认休息时 `elapsed` 无上界，提醒会永久常驻状态栏且按冷却反复弹窗——超过 2 轮间隔视为未使用，计时重新对齐到当前。另外：弹窗尺寸跟随主屏而非写死 1440×900，文案进 HTML 前做转义，休息/喝水弹窗冷却由 `interval*0.9` 改为 `interval`（实际节奏与标称的 50/60 分钟一致）。🕔 打卡修复：macOS 读 `pmset` 历史日志本可在任意时刻查到早上首次活动，但外层窗口判断卡的是「当前时间」，上午没开过 Claude Code 的那天弹性工时会静默退回固定档——现在先查 `pmset`，仅 `refresh` 兜底才要求当前仍在窗口内
- **v0.6.5** — 🕔 下班倒计时改为弹性工作制：`CCDAY_PUNCH_START`–`CCDAY_PUNCH_END`（默认 06:00–12:00）间首次用户活动记为上班时间，下班点 = 上班 + `CCDAY_WORK_HOURS`（默认 9h），倒计时带上 `(10:22→19:22)`。macOS 用 `pmset -g log` 取真实首次活动（显示器点亮 / UserIsActive / HID），排除后台进程断言和 DarkWake，每天只调一次；其他平台退回状态栏首次刷新时刻。打卡记录只对当天有效，隔夜作废；首次活动晚于窗口、跨天班、`CCDAY_WORK_PUNCH=0` 时退回固定 `WORK_START/END`。🏖 周末倒计时同步跟随打卡下班点
- **v0.6.4** — 💰 用量拆成独立插件 `ccday-billing.sh`，遵循"有即用，没有不用"：token 四级探测（配置/环境变量/settings.json/live-code.json）、接口地址跟随 `ANTHROPIC_BASE_URL`、失败写负缓存 30 分钟内不重试、`--check` 诊断模式、6 种显示格式、75%/90% 用量预警。**修复**：旧版读的是 `daily_used` 而接口返回的是 `daily_usage`，导致配了预算时余额永远显示为满额
- **v0.6.3** — 修复 `uninstall.sh` 删不掉 skill（还在找 v0.3 的单文件路径）；`update.sh` 支持"远端无新提交但本地已安装版本过期"的情况，并检查 settings.json 挂载点是否齐全；卸载时清理运行时缓存
- **v0.6.2** — 🎒 周末灵感改为按 `HOME_LAT/LNG` 给具体城市+车程+玩法（内置 10 个城市圈），删掉"高铁2小时内的城市""携程比价"这类无信息量的空话
- **v0.6.1** — 🍚 午饭/晚饭提醒（默认 12:00 / 18:00，可留空关闭）；Git 状态新增 `✓N` 今日提交数（仅本人）
- **v0.6.0** — 🕔 下班倒计时（默认 19:30，含进度/加班/跨天班）；ctx 按模型窗口自适应（1M/200k）并改用 stdin 的 transcript_path 定位当前会话；billing 加 5 分钟缓存；修复休息提示语每次刷新都变的问题
- **v0.5.5** — macOS 全屏休息提醒（Safari），30秒倒计时 + 随机段子 + 双击强制关闭
- **v0.5.4** — 休息/喝水提醒触发系统通知弹窗（macOS osascript / Linux notify-send），修复 emoji 与数字间距
- **v0.5.3** — 新增 `CCDAY_BILLING` 开关和 `CCDAY_BILLING_BUDGET` 预算配置，支持显示剩余金额
- **v0.5.2** — 修复 macOS open-meteo 经纬度顺序错误导致天气获取失败
- **v0.5.1** — 修复 `/ccday` skill 找不到（目录结构 + SKILL.md 大写）、支持 `bash update.sh` 一键更新
- **v0.5.0** — 休息提醒（可配置强确认/自动消失）、喝水提醒（自动消失）
- **v0.4.0** — 天气缓存、调休感知、番茄钟、Git状态、今日目标
- **v0.3.0** — tip 每5次随机换，每20次AI生成；mac天气改open-meteo
- **v0.2.0** — 周末倒计时改为剩余工作小时数
- **v0.1.0** — 天气、节假日、出行灵感、旅行计划、上下文占用

## 卸载

```bash
bash uninstall.sh
```

移除脚本、skill、`settings.json` 里的 statusLine 和 Stop hook，清理运行时缓存。
保留 `~/.ccday.conf` 和 `~/.ccday-private.pem`，需要彻底删除时手动 `rm`。

## License

MIT
