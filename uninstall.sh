#!/bin/bash
# uninstall.sh — ccday 卸载脚本
set -e

INSTALL_DIR="$HOME/.claude/scripts/ccday"
SKILLS_DIR="$HOME/.claude/skills"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

echo "🗑  卸载 ccday..."

# 1. 删除脚本目录
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    echo "✅ 已删除 $INSTALL_DIR"
fi

# 2. 删除 skill
if [ -f "$SKILLS_DIR/ccday.md" ]; then
    rm "$SKILLS_DIR/ccday.md"
    echo "✅ 已删除 skill: /ccday"
fi

# 3. 从 settings.json 移除 statusLine 和 Stop hook
if [ -f "$CLAUDE_SETTINGS" ]; then
    python3 - "$CLAUDE_SETTINGS" <<'PYEOF'
import json, sys
p = sys.argv[1]
with open(p) as f:
    cfg = json.load(f)

changed = False

# 移除 statusLine（仅当是 ccday 注入的）
sl = cfg.get("statusLine", {})
if "ccday-label.sh" in sl.get("command", ""):
    del cfg["statusLine"]
    print("✅ 已从 settings.json 移除 statusLine")
    changed = True
else:
    print("ℹ️  statusLine 不是 ccday 注入的，跳过")

# 移除 Stop hook 中的 ccday-joke-gen.sh
hooks = cfg.get("hooks", {})
stop_hooks = hooks.get("Stop", [])
new_stop = []
removed = False
for entry in stop_hooks:
    new_hooks = [h for h in entry.get("hooks", []) if "ccday-joke-gen.sh" not in h.get("command", "")]
    if len(new_hooks) != len(entry.get("hooks", [])):
        removed = True
    if new_hooks:
        entry["hooks"] = new_hooks
        new_stop.append(entry)

if removed:
    hooks["Stop"] = new_stop
    if not hooks["Stop"]:
        del hooks["Stop"]
    if not hooks:
        del cfg["hooks"]
    print("✅ 已从 settings.json 移除 Stop hook")
    changed = True

if changed:
    with open(p, "w") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)
PYEOF
fi

echo ""
echo "✅ 卸载完成"
echo "ℹ️  配置文件 ~/.ccday.conf 和段子缓存 ~/.ccday-joke-cache.json 已保留，如需删除请手动执行："
echo "   rm ~/.ccday.conf ~/.ccday-joke-cache.json"
