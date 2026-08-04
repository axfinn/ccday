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

常用 key：`CCDAY_WORK_START` `CCDAY_WORK_END` `CCDAY_OFFWORK` `CCDAY_LUNCH`
`CCDAY_DINNER` `CCDAY_MEAL_WINDOW` `CCDAY_BREAK_INTERVAL` `CCDAY_WATER_INTERVAL` `CCDAY_GOAL`

## 下班倒计时

工作日按 `CCDAY_WORK_START`（默认 10:00）和 `CCDAY_WORK_END`（默认 19:30）显示：

- 上班前 `🕘 待上班 1h45m`
- 工作中 `🕔 下班 3h45m·60%`（最后半小时换 🔥）
- 下班后 `🎉 下班了!`，5 分钟后转 `🌙 加班 2h15m`

周末和法定节假日不显示，调休上班日照常显示。支持跨天班。

用户说"我 18 点下班"、"改成 20:00 下班"等，用上面「修改配置项」的方法改 `CCDAY_WORK_END`。
关闭下班倒计时则设 `CCDAY_OFFWORK=0`。

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
