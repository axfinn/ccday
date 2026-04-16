# ccday

> Claude Code 状态栏插件 — 天气 · 节假日倒计时 · 周末倒计时 · 出行灵感

在 Claude Code 底部状态栏（claude-hud）实时显示：

```
☀️25°/15°晴 │ 🔨劳动节还有15天 │ 🏖周末还有2天 │ 🌸张家界四月云海最美，赶在五一前去
```

## 功能

- **天气** — 和风天气 API，显示今日气温和天气状况
- **节假日倒计时** — 中国法定节假日 + 国际节日，自动找下一个
- **周末倒计时** — 距离周六还有几天
- **出行灵感** — 每天一条当季旅行 tips，基于日期固定（不随机跳变）

## 安装

### 前置条件

- Claude Code（已安装 claude-hud 插件）
- Python 3（系统自带）
- 和风天气免费 API Key（[注册地址](https://dev.qweather.com)，免费额度 1000次/天）

### 一键安装

```bash
git clone git@github.com:axfinn/ccday.git
cd ccday
bash install.sh
```

### 配置

编辑 `~/.ccday.conf`：

```bash
# 和风天气 API Key
QWEATHER_KEY=your_key_here

# 城市 ID（默认北京）
# 北京=101010100  上海=101020100  广州=101280101  深圳=101280601
# 查询更多城市: https://github.com/qwd/LocationList
QWEATHER_LOCATION=101010100
```

重启 Claude Code 即可看到效果。

## 手动配置 statusLine

如果 `install.sh` 检测到已有 `statusLine` 配置，需手动合并。在 `~/.claude/settings.json` 的 `statusLine.command` 开头加入：

```json
{
  "statusLine": {
    "padding": 0,
    "command": "bash -c '$HOME/.claude/scripts/ccday/ccday-label.sh 2>/dev/null; <原有命令>'",
    "type": "command"
  }
}
```

## 自定义颜色

编辑 `~/.claude/plugins/claude-hud/config.json`：

```json
{
  "colors": {
    "custom": "cyan"
  }
}
```

支持颜色名（`green`/`cyan`/`yellow`）、256色索引（`208`）、hex（`"#FF6600"`）。

## 节假日数据

内置 `scripts/holidays.json`，覆盖 2025–2027 年：

| 类型 | 节日 |
|------|------|
| 中国法定 | 元旦、春节、清明、劳动节、端午、中秋、国庆 |
| 中国传统 | 除夕、七夕 |
| 国际节日 | 情人节、母亲节、父亲节、万圣节、圣诞节 |

## 卸载

```bash
bash uninstall.sh
```

## 文件结构

```
ccday/
├── install.sh              # 一键安装
├── uninstall.sh            # 卸载
├── README.md
└── scripts/
    ├── ccday-label.sh      # 主脚本（写入 claude-hud customLine）
    └── holidays.json       # 节假日 + 出行灵感数据
```

## License

MIT
