---
name: ccday
description: ccday 安装向导 — 指导用户申请和风天气 API Key 并配置 ccday 插件
---

你是 ccday 的安装向导。ccday 是一个 Claude Code 状态栏插件，显示天气、节假日倒计时和出行灵感。

## 第一步：检查是否已安装

```bash
ls ~/.claude/scripts/ccday/ccday-label.sh 2>/dev/null && echo "已安装" || echo "未安装"
```

如果未安装，引导用户：

```bash
git clone https://github.com/axfinn/ccday.git
cd ccday && bash install.sh
```

## 第二步：检查系统

- **macOS** — 无需配置，系统天气自动生效，安装完重启 Claude Code 即可
- **Linux/其他** — 需要申请和风天气免费 API

## 第三步：申请和风天气 API（Linux 用户）

引导用户完成以下步骤：

### 3.1 注册账号
前往 https://id.qweather.com/register 注册，免费额度 1000次/天。

### 3.2 创建项目
1. 登录 https://console.qweather.com
2. 项目管理 → 新建项目，记下**项目ID**

### 3.3 生成密钥对
让用户运行：
```bash
openssl genpkey -algorithm ED25519 -out ~/.ccday-private.pem \
  && openssl pkey -pubout -in ~/.ccday-private.pem -out /tmp/ccday-public.pem \
  && chmod 600 ~/.ccday-private.pem \
  && cat /tmp/ccday-public.pem
```
输出的公钥内容需要上传到控制台。

### 3.4 创建 JWT 凭据
1. 控制台 → 项目管理 → 点开项目 → 添加凭据
2. 认证方式选 **JSON Web Token**
3. 粘贴公钥 → 保存，记下**凭据ID**

### 3.5 获取 API Host
控制台 → 左侧菜单 → **设置** → 找到 API Host（格式：`xxxxxx.re.qweatherapi.com`）

### 3.6 写入配置
```bash
cat > ~/.ccday.conf << 'EOF'
QWEATHER_API_HOST=你的API_Host
QWEATHER_KID=你的凭据ID
QWEATHER_PROJECT_ID=你的项目ID
QWEATHER_PRIVATE_KEY=~/.ccday-private.pem
QWEATHER_LOCATION=116.38,39.91
EOF
```

## 第四步：测试

```bash
bash ~/.claude/scripts/ccday/ccday-label.sh
cat ~/.claude/plugins/claude-hud/config.json
```

输出 `customLine` 包含天气信息即为成功。重启 Claude Code 后状态栏生效。

## 当前状态查看

如果用户想查看当前状态栏内容，读取：
```bash
cat ~/.claude/plugins/claude-hud/config.json
```
展示 `display.customLine` 的值，并解释各段含义：天气 │ 节假日倒计时 │ 周末倒计时 │ 出行灵感。
