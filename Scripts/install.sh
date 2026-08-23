#!/bin/bash
# -*- coding: utf-8 -*-
# 构建并安装 PhraseKey 输入法到 /Library/Input Methods/（系统级）
#
# ★ 为什么装系统级而不是 ~/Library/Input Methods/（用户级）
#   实测（2026-08-24）：此前装用户级，结果
#     · 进程能被 open 拉起（PID 77829 存在）
#     · 但 `defaults read com.apple.HIToolbox AppleEnabledInputSources`
#       里 PhraseKey **0 条记录** —— 系统从未注册它
#     · 系统设置 → 键盘 → 文本输入 → 添加，列表里找不到
#   对照标本：本机正常工作的鼠须管 /Library/Input Methods/Squirrel.app
#   是**系统级**。macOS 对用户级输入法的注册不可靠（尤其 Ventura+）。
#   → 面板做得再漂亮，输入法用不上等于零。先解决可达性。
#
# 用法：bash Scripts/install.sh        （会请求 sudo，因为要写 /Library）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

bash "$ROOT/Scripts/build_app.sh" release

SYS_DEST="/Library/Input Methods/PhraseKey.app"
OLD_USER_DEST="$HOME/Library/Input Methods/PhraseKey.app"

# 清掉用户级旧安装，否则两份并存会让系统看到重复 bundle ID
if [ -d "$OLD_USER_DEST" ]; then
  echo "==> 移除用户级旧安装 $OLD_USER_DEST"
  # 先杀掉正在跑的旧进程，否则删不干净
  pkill -f "$OLD_USER_DEST" 2>/dev/null || true
  rm -rf "$OLD_USER_DEST"
fi

echo "==> 安装到 $SYS_DEST（需要管理员密码）"
sudo rm -rf "$SYS_DEST"
sudo cp -R "$ROOT/dist/PhraseKey.app" "$SYS_DEST"
sudo codesign --force --deep --sign - "$SYS_DEST" 2>/dev/null || true
sudo chown -R root:wheel "$SYS_DEST"

# ── 出厂验证：不能只说「装好了」──
echo ""
echo "==> 安装后验证"
fail=0
[ -d "$SYS_DEST" ] && echo "   ✅ bundle 存在" || { echo "   ❌ bundle 不存在"; fail=1; }
codesign -v "$SYS_DEST" 2>/dev/null && echo "   ✅ 签名有效" || { echo "   ❌ 签名无效"; fail=1; }
# 与鼠须管对照的 5 个 IMK 关键结构（缺任一都不会被注册，见 28aa050）
for k in ComponentInputModeDict tsInputModeListKey InputMethodConnectionName tsInputModeCharacterRepertoireKey; do
  if plutil -p "$SYS_DEST/Contents/Info.plist" 2>/dev/null | grep -q "$k"; then
    echo "   ✅ Info.plist 含 $k"
  else
    echo "   ❌ Info.plist 缺 $k"; fail=1
  fi
done
# 词库不能是示例集（曾发生 gen_dict.py 108 条覆盖 20 万条，见 722972b）
n=$(wc -l < "$SYS_DEST/Contents/Resources/dict.tsv" 2>/dev/null || echo 0)
[ "$n" -ge 10000 ] && echo "   ✅ 词库 $n 条" || { echo "   ❌ 词库仅 $n 条（疑被示例集覆盖）"; fail=1; }

[ "$fail" -eq 0 ] || { echo ""; echo "❌ 验证未通过，不要声称可用"; exit 1; }

echo ""
echo "✅ 已安装 PhraseKey 输入法（系统级）"
echo ""
echo "   ⚠️ 必须先注销重登，系统才会扫描到新输入法："
echo "      苹果菜单 →  注销  →  重新登录"
echo ""
echo "   重登后："
echo "   1) 系统设置 → 键盘 → 文本输入 → 输入法「编辑…」→ + → 中文（简体）→ PhraseKey"
echo "   2) 用 Ctrl+Space 切到 PhraseKey"
echo "   3) 验证是否真被注册（重登后跑这条，应能看到 PhraseKey）："
echo "      defaults read com.apple.HIToolbox AppleEnabledInputSources | grep -A2 PhraseKey"
echo ""
echo "   卸载：sudo rm -rf \"$SYS_DEST\"，再注销重登"
