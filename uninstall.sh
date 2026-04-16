#!/bin/bash
# uninstall.sh — ccday 卸载脚本
set -e

INSTALL_DIR="$HOME/.claude/scripts/ccday"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

echo "🗑  卸载 ccday..."

# 删除脚本
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    echo "✅ 已删除 $INSTALL_DIR"
fi

# 从 settings.json 移除 statusLine（仅当是 ccday 注入的）
if [ -f "$CLAUDE_SETTINGS" ]; then
    python3 - "$CLAUDE_SETTINGS" <<'PYEOF'
import json, sys
p = sys.argv[1]
with open(p) as f: cfg = json.load(f)
sl = cfg.get("statusLine", {})
cmd = sl.get("command", "")
if "ccday-label.sh" in cmd:
    del cfg["statusLine"]
    with open(p, 'w') as f: json.dump(cfg, f, ensure_ascii=False, indent=2)
    print("✅ 已从 settings.json 移除 statusLine")
else:
    print("ℹ️  statusLine 不是 ccday 注入的，跳过")
PYEOF
fi

echo "✅ 卸载完成"
