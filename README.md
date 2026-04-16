# ccday

> Claude Code 状态栏插件 — 天气 · 节假日倒计时 · 周末倒计时 · 出行灵感 · 旅行计划 · 上下文占用

在 Claude Code 底部状态栏实时显示两行信息：

```
☁️ 16° 阴  🔨 劳动节·15天  🏖 2天  🤖 让AI写段子，我摸鱼！
📊 ctx 53%  │  🗺️ 长兴岛郊野公园 22km·2天后 · 带足够的水  │  💰72%
```

**第一行**：天气 · 节假日倒计时 · 周末倒计时 · 出行灵感/段子  
**第二行**：上下文占用 · 旅行计划（可选）· 每日用量（可选）

- **macOS** — 使用 open-meteo 免费天气，无需任何配置
- **Linux/其他** — 优先和风天气 API（免费，需注册），无配置时自动 fallback 到 open-meteo

---

## 快速开始

### 1. 克隆并安装

```bash
git clone https://github.com/axfinn/ccday.git
cd ccday
bash install.sh
```

### 2. 配置天气（可选，Linux 用户获得更精准天气）

编辑 `~/.ccday.conf`，填入和风天气凭据：

```bash
QWEATHER_API_HOST=xxxxxx.re.qweatherapi.com
QWEATHER_KID=你的凭据ID
QWEATHER_PROJECT_ID=你的项目ID
QWEATHER_PRIVATE_KEY=~/.ccday-private.pem
QWEATHER_LOCATION=121.47,31.23   # 经纬度，或城市ID如 101020100
```

### 3. 重启 Claude Code

状态栏自动显示。

---

## 完整配置说明

`~/.ccday.conf` 所有可用配置项：

```bash
# ── 天气（和风天气 API，可选，不填自动用 open-meteo）──────────
QWEATHER_API_HOST=mv4gkk5acy.re.qweatherapi.com   # API Host（控制台-设置）
QWEATHER_KID=TMB2M4VR9V                            # 凭据ID
QWEATHER_PROJECT_ID=3K85Y9JGHF                     # 项目ID
QWEATHER_PRIVATE_KEY=~/.ccday-private.pem          # Ed25519 私钥路径
QWEATHER_LOCATION=121.47,31.23                     # 经纬度（open-meteo 也用此项）

# ── 出发地（用于计算旅行距离）────────────────────────────────
HOME_LAT=31.28
HOME_LNG=121.52

# ── 旅行计划（可选）──────────────────────────────────────────
# 设置后第二行显示：🗺️ 长兴岛郊野公园 22km·2天后 · 带足够的水
TRIP_NAME=长兴岛郊野公园
TRIP_LAT=31.38
TRIP_LNG=121.72
TRIP_DATE=2026-04-18                               # 出发日期，过期后自动隐藏
TRIP_TIPS="带防晒霜;穿舒适的鞋;早点出发避开堵车;带足够的水"  # 用分号分隔，每天轮换一条

# ── Tip/段子刷新频率（按会话次数）────────────────────────────
CCDAY_AI_JOKE=1           # 启用 AI 生成段子（需要 claude CLI）
CCDAY_TIP_ROTATE=5        # 每 N 次会话随机换一条 tip（默认 5）
CCDAY_AI_JOKE_ROTATE=20   # 每 N 次会话用 AI 生成新段子（默认 20）
```

> **注意**：`TRIP_TIPS` 多条内容用 `;` 分隔，不要用 `|`（会被 shell 当管道符）

---

## 出行灵感 & AI 段子

每次会话结束时（Stop hook），自动更新 tip 缓存：

- **每 `CCDAY_TIP_ROTATE` 次会话**（默认 5 次）：从静态池随机换一条
- **每 `CCDAY_AI_JOKE_ROTATE` 次会话**（默认 20 次）：调用 `claude` CLI，根据本次对话内容生成一条专属段子

内容来自 `scripts/holidays.json`，可自行编辑添加。

---

## 上下文占用

自动读取当前 Claude Code 会话的 token 用量，显示占 200k 上下文窗口的百分比：

```
📊 ctx 53%
```

无需任何配置，开箱即用。

---

## 申请和风天气 API（可选，Linux 用户）

> macOS 用户和不需要精准天气的用户可跳过，open-meteo 自动生效。

### 第一步：注册账号

前往 [https://id.qweather.com/register](https://id.qweather.com/register) 注册，免费额度 **1000次/天**。

### 第二步：创建项目

1. 登录 [控制台](https://console.qweather.com)
2. **项目管理** → 新建项目
3. 记下 **项目ID**（如 `3K85Y9JGHF`）

### 第三步：生成 Ed25519 密钥对

```bash
openssl genpkey -algorithm ED25519 -out ~/.ccday-private.pem \
  && openssl pkey -pubout -in ~/.ccday-private.pem -out /tmp/ccday-public.pem \
  && chmod 600 ~/.ccday-private.pem \
  && cat /tmp/ccday-public.pem
```

### 第四步：创建 JWT 凭据

1. 控制台 → 项目管理 → 点开项目 → **添加凭据**
2. 认证方式选 **JSON Web Token**
3. 粘贴公钥内容 → 保存
4. 记下 **凭据ID**（如 `TMB2M4VR9V`）

### 第五步：获取 API Host

控制台 → **设置** → 找到 **API Host**（如 `mv4gkk5acy.re.qweatherapi.com`）

---

## Claude Code Skill

输入 `/ccday` 在对话中快速查看当前状态栏内容：

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
├── README.md
├── scripts/
│   ├── ccday-label.sh      # 主脚本（状态栏输出）
│   ├── ccday-joke-gen.sh   # Stop hook 脚本（更新 tip/段子缓存）
│   └── holidays.json       # 节假日 + 出行灵感 + 段子数据
└── skills/
    └── ccday.md            # Claude Code skill
```

## 卸载

```bash
bash uninstall.sh
```

## License

MIT
