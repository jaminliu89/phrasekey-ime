#!/bin/bash
# -*- coding: utf-8 -*-
# 构建 PhraseKey.app（SwiftPM 编译 + 组装 macOS 输入法 bundle）
# 用法：bash Scripts/build_app.sh [release|debug]  默认 release
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
APP_NAME="PhraseKey"
CONFIG="${1:-release}"

echo "==> [1/4] 生成基础词库"
python3 Scripts/gen_dict.py

echo "==> [2/4] swift build (-c $CONFIG)"
swift build -c "$CONFIG"

echo "==> [3/4] 组装 ${APP_NAME}.app"
BIN="$ROOT/.build/$CONFIG/PhraseKeyIME"
APP="$ROOT/dist/${APP_NAME}.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PhraseKeyIME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# 资源：词库 + 拼音表 + 图标（无论 SwiftPM bundle 是否生成，直接复制源码资源）
for RES in dict.tsv hanzi_pinyin.tsv; do
  if [ -f "$ROOT/Sources/PhraseKeyIME/Resources/$RES" ]; then
    cp "$ROOT/Sources/PhraseKeyIME/Resources/$RES" "$APP/Contents/Resources/$RES"
  fi
done
# 品牌图标
if [ -f "$ROOT/BrandAssets/PhraseKey.icns" ]; then
  cp "$ROOT/BrandAssets/PhraseKey.icns" "$APP/Contents/Resources/PhraseKey.icns"
fi
# 图标（可选）
if [ -f "$ROOT/Resources/icon.icns" ]; then
  cp "$ROOT/Resources/icon.icns" "$APP/Contents/Resources/icon.icns"
fi

echo "==> [4/4] ad-hoc 签名（IMK 输入法需要签名）"
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "（签名跳过，请手动 codesign）"

echo ""
echo "✅ 构建完成：$APP"
echo "   安装：bash Scripts/install.sh"
