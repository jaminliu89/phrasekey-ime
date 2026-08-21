#!/bin/bash
# -*- coding: utf-8 -*-
# 构建并安装 PhraseKey 输入法到 ~/Library/Input Methods/
# 用法：bash Scripts/install.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

bash "$ROOT/Scripts/build_app.sh" release

DEST="$HOME/Library/Input Methods/PhraseKey.app"
echo "==> 安装到 $DEST"
rm -rf "$DEST"
cp -R "$ROOT/dist/PhraseKey.app" "$DEST"
codesign --force --deep --sign - "$DEST" 2>/dev/null || true

echo ""
echo "✅ 已安装 PhraseKey 输入法"
echo ""
echo "   启用步骤："
echo "   1) 注销当前用户并重新登录（或重启），让系统注册输入法"
echo "   2) 系统设置 → 键盘 → 文本输入 → 编辑 → 添加 → 选「PhraseKey」"
echo "   3) 切换输入法后：字母输入拼音，数字选词，空格上屏首选"
echo "   4) 菜单栏输入法图标 → PhraseKey 设置 → 导入常用语"
echo ""
echo "   卸载：rm -rf \"$DEST\"，再注销登录即可"
