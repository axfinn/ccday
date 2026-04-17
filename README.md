# ccday

> Claude Code 状态栏插件 — 天气 · 节假日 · 周末倒计时 · 番茄钟 · 今日目标 · Git状态 · 出行灵感

**版本：v0.4.0**

在 Claude Code 底部状态栏实时显示两行信息：

```
🌫 18° 雾  🔨 劳动节·14天  🏖 还8h  🍅24:59 写文档  🎯 完成登录模块  🌊 厦门鼓浪屿工作日人少
📊 ctx 76%  │  🗺️ 长兴岛郊野公园 22km·1天后 · 带足够的水  │  💰5%  │  📝3 ⬇1
```

**第一行**：天气 · 节假日倒计时 · 周末倒计时 · 🍅番茄钟 · 🎯今日目标 · 出行灵感/段子  
**第二行**：📊上下文占用 · 🗺️旅行计划 · 💰每日用量 · 📝Git状态

- **macOS** — open-meteo 免费天气，无需任何配置
- **Linux** — 优先和风天气 API，无配置时自动 fallback 到 open-meteo
- **天气缓存** — 30分钟内不重复请求，状态栏不卡顿
- **调休感知** — 周末倒计时识别调休上班日和节假日

---

## 快速开始

```bash
git clone https://github.com/axfinn/ccday.git
cd ccday && bash install.sh
```

重启 Claude Code，状态栏自动生效。

---

## 功能说明

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
- `⬇2` — 落后远端2个提交
- `⬆1` — 领先远端1个提交

无需配置，开箱即用。

### 出行灵感 & AI 段子

每次会话结束（Stop hook）自动更新：

- **每 5 次会话**（`CCDAY_TIP_ROTATE`）：从静态池随机换一条
- **每 20 次会话**（`CCDAY_AI_JOKE_ROTATE`）：调用 `claude` CLI 根据对话内容生成专属段子

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

# ── 下班时间 ────────────────────────────────────────────────
CCDAY_WORK_END=19:00                  # 默认 19:00

# ── Tip/段子刷新频率 ────────────────────────────────────────
CCDAY_AI_JOKE=1                       # 启用 AI 生成段子
CCDAY_TIP_ROTATE=5                    # 每 N 次会话随机换 tip
CCDAY_AI_JOKE_ROTATE=20               # 每 N 次会话 AI 生成
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
├── uninstall.sh
├── ccday.conf.example          # 完整示例配置
├── README.md
├── scripts/
│   ├── ccday-label.sh          # 主脚本（状态栏输出）
│   ├── ccday-joke-gen.sh       # Stop hook（更新 tip/段子缓存）
│   └── holidays.json           # 节假日 + 调休 + 出行灵感 + 段子
└── skills/
    └── ccday.md                # Claude Code skill
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

---

## 版本历史

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
