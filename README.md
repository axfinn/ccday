# ccday

> Claude Code 状态栏插件 — 天气 · 节假日倒计时 · 周末倒计时 · 出行灵感

在 Claude Code 底部状态栏（claude-hud）实时显示：

```
🌧14°小雨 │ 🔨劳动节还有15天 │ 🏖周末还有2天 │ 🌊 厦门鼓浪屿避开周末，工作日人少体验翻倍
```

- **macOS** — 直接读取系统天气，无需配置
- **Linux/其他** — 调用和风天气 API（免费，需注册）

---

## 快速开始

### 1. 克隆项目

```bash
git clone https://github.com/axfinn/ccday.git
cd ccday
bash install.sh
```

### 2. 配置天气（Linux 用户）

编辑 `~/.ccday.conf`，填入和风天气凭据：

```bash
QWEATHER_API_HOST=xxxxxx.re.qweatherapi.com
QWEATHER_KID=你的凭据ID
QWEATHER_PROJECT_ID=你的项目ID
QWEATHER_PRIVATE_KEY=~/.ccday-private.pem
QWEATHER_LOCATION=116.38,39.91   # 经纬度，或城市ID如 101010100
```

### 3. 重启 Claude Code

状态栏自动显示天气和倒计时。

---

## 申请和风天气 API（免费）

> macOS 用户跳过此步骤，系统天气自动生效。

### 第一步：注册账号

前往 [https://id.qweather.com/register](https://id.qweather.com/register) 注册，免费额度 **1000次/天**，够个人使用。

### 第二步：创建项目

1. 登录 [控制台](https://console.qweather.com)
2. 左侧菜单 → **项目管理** → 新建项目
3. 记下 **项目ID**（格式如 `3K85Y9JGHF`）

### 第三步：生成 Ed25519 密钥对

```bash
openssl genpkey -algorithm ED25519 -out ~/.ccday-private.pem \
  && openssl pkey -pubout -in ~/.ccday-private.pem -out /tmp/ccday-public.pem \
  && chmod 600 ~/.ccday-private.pem \
  && cat /tmp/ccday-public.pem
```

输出的公钥内容（`-----BEGIN PUBLIC KEY-----` 开头）备用。

### 第四步：创建 JWT 凭据

1. 控制台 → 项目管理 → 点开你的项目 → **添加凭据**
2. 认证方式选 **JSON Web Token**
3. 粘贴上一步的公钥内容 → 保存
4. 记下 **凭据ID**（格式如 `TMB2M4VR9V`）

### 第五步：获取 API Host

1. 控制台 → 左侧菜单 → **设置**
2. 找到 **API Host**（格式如 `mv4gkk5acy.re.qweatherapi.com`）

### 第六步：填写配置

```bash
# 编辑 ~/.ccday.conf
QWEATHER_API_HOST=mv4gkk5acy.re.qweatherapi.com   # 第五步获取
QWEATHER_KID=TMB2M4VR9V                            # 第四步凭据ID
QWEATHER_PROJECT_ID=3K85Y9JGHF                     # 第二步项目ID
QWEATHER_PRIVATE_KEY=~/.ccday-private.pem
QWEATHER_LOCATION=116.38,39.91                     # 你的城市经纬度
```

---

## Claude Code Skill

ccday 提供一个 `/ccday` skill，在对话中快速查看当前状态栏内容：

```bash
# 安装 skill（install.sh 已自动完成）
# 手动安装：
cp skills/ccday.md ~/.claude/skills/ccday.md
```

在 Claude Code 中输入 `/ccday` 即可查看当前天气和倒计时。

---

## 文件结构

```
ccday/
├── install.sh
├── uninstall.sh
├── README.md
├── scripts/
│   ├── ccday-label.sh      # 主脚本
│   └── holidays.json       # 节假日 + 出行灵感数据
└── skills/
    └── ccday.md            # Claude Code skill
```

## 卸载

```bash
bash uninstall.sh
```

## License

MIT
