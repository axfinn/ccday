# ccday

> Claude Code 状态栏插件 — 天气 · 节假日 · 周末倒计时 · 下班倒计时 · 番茄钟 · 休息/喝水/饭点提醒 · 今日目标 · Git状态 · 出行灵感

**版本：v0.6.1**

在 Claude Code 底部状态栏实时显示两行信息：

```
🌫 18° 雾  🔨 劳动节·14天  🏖 还8h  🕔 下班 3h45m·60%  🍅24:59 写文档  🧘 站起来伸个懒腰!  🍚 去吃午饭!  🎯 完成登录模块
📊 ctx 76%  │  🗺️ 长兴岛郊野公园 22km·1天后 · 带足够的水  │  💰5%  │  📝3 ✓5 ⬇1
```

**第一行**：天气 · 节假日倒计时 · 周末倒计时 · 🕔下班倒计时 · 🍅番茄钟 · 🧘休息提醒 · 💧喝水提醒 · 🍚饭点提醒 · 🎯今日目标 · 出行灵感/段子
**第二行**：📊上下文占用 · 🗺️旅行计划 · 💰每日用量 · 📝Git状态

- **macOS** — open-meteo 免费天气，无需任何配置
- **Linux** — 优先和风天气 API，无配置时自动 fallback 到 open-meteo
- **天气缓存** — 30分钟内不重复请求，状态栏不卡顿
- **调休感知** — 周末/下班倒计时识别调休上班日和节假日
- **下班倒计时** — 默认 10:00–19:30，进度百分比 + 最后半小时高亮，过点显示加班时长
- **上下文自适应** — 按当前模型窗口计算（1M / 200k），不再按固定 200k 估算
- **休息提醒** — 每隔 N 分钟提醒活动，支持强确认（有倒计时）或自动消失两种模式
- **喝水提醒** — 每隔 N 分钟自动显示 5 分钟后消失，无需确认
- **饭点提醒** — 午饭/晚饭到点显示 30 分钟后自动消失，同时触发系统通知

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

自动检测远端版本，有新版本时拉取并更新脚本/skill，**不覆盖用户配置**（`~/.ccday.conf`）。

---

## 功能说明

### 下班倒计时

在 `~/.ccday.conf` 设置上下班时间：

```bash
CCDAY_WORK_START=10:00    # 上班时间（默认 10:00）
CCDAY_WORK_END=19:30      # 下班时间（默认 19:30）
CCDAY_OFFWORK=1           # 0 可关闭
```

状态栏按当前时间显示四种状态：

| 时段 | 显示 | 说明 |
|------|------|------|
| 上班前 | `🕘 待上班 1h45m` | 距离上班时间 |
| 工作中 | `🕔 下班 3h45m·60%` | 剩余时长 + 当日进度 |
| 最后半小时 | `🔥 下班 25m·95%` | 换成 🔥 提示收尾 |
| 过了下班点 | `🎉 下班了!` → `🌙 加班 2h15m` | 5 分钟内庆祝，之后计加班 |

只在**工作日**显示：自动跳过周末和法定节假日，识别调休上班日。支持跨天班（如 `22:00`→`06:00`）。

超过下班点后每 30 分钟触发一次系统通知提醒收工。

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

### 休息提醒

每隔 `CCDAY_BREAK_INTERVAL` 分钟（默认50分钟），状态栏显示 `🧘 站起来伸个懒腰!` 等随机提示，同时触发提醒弹窗。

macOS 会弹出**全屏提醒页面**（Safari），带30秒倒计时、随机段子，倒计时结束前点击会被怼，双击可强制关闭。Linux 使用 `notify-send` 系统通知。

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

# ── 出发地（用于计算旅行距离）──────────────────────────────
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

# ── 上下班时间 ──────────────────────────────────────────────
CCDAY_WORK_START=10:00                # 上班时间（默认 10:00）
CCDAY_WORK_END=19:30                  # 下班时间（默认 19:30）
CCDAY_OFFWORK=1                       # 1=显示下班倒计时，0=隐藏

# ── Tip/段子刷新频率 ────────────────────────────────────────
CCDAY_AI_JOKE=1                       # 启用 AI 生成段子
CCDAY_TIP_ROTATE=5                    # 每 N 次会话随机换 tip
CCDAY_AI_JOKE_ROTATE=20               # 每 N 次会话 AI 生成

# ── 休息提醒 ────────────────────────────────────────────────
CCDAY_BREAK_INTERVAL=50               # 每隔 N 分钟提醒休息（默认 50）
CCDAY_BREAK_DURATION=10               # 休息时长 N 分钟（默认 10，仅 CONFIRM=1 时有效）
CCDAY_BREAK_CONFIRM=1                 # 1=需要主动确认（有倒计时），0=定时自动消失
CCDAY_BREAK_START=09:00               # 提醒生效开始时间（默认 09:00）
CCDAY_BREAK_END=22:00                 # 提醒生效结束时间（默认 22:00）

# ── 喝水提醒 ────────────────────────────────────────────────
CCDAY_WATER_INTERVAL=60               # 每隔 N 分钟提醒喝水（默认 60，设 0 关闭）

# ── 饭点提醒 ────────────────────────────────────────────────
CCDAY_LUNCH=12:00                     # 午饭时间（默认 12:00，留空关闭）
CCDAY_DINNER=18:00                    # 晚饭时间（默认 18:00，留空关闭）
CCDAY_MEAL_WINDOW=30                  # 到点后持续显示 N 分钟（默认 30）

# ── 用量显示 ────────────────────────────────────────────────
CCDAY_BILLING=1                       # 1=显示 💰 用量，0=隐藏
CCDAY_BILLING_BUDGET=1000             # 每日预算（元），显示"💰余X.X¥"；设 0 显示百分比
CCDAY_BILLING_TTL=300                 # 用量接口缓存秒数（默认 300）
```

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
│   └── holidays.json           # 节假日 + 调休 + 出行灵感 + 段子
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
| `~/.ccday-billing-cache.json` | 用量接口缓存（默认5分钟） |
| `~/.ccday-notif-break.json` | 休息系统通知去重标记 |
| `~/.ccday-notif-water.json` | 喝水系统通知去重标记 |
| `~/.ccday-notif-offwork.json` | 下班/加班系统通知去重标记 |
| `~/.ccday-notif-meal-lunch.json` | 午饭系统通知去重标记 |
| `~/.ccday-notif-meal-dinner.json` | 晚饭系统通知去重标记 |

---

## 版本历史

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

## License

MIT
