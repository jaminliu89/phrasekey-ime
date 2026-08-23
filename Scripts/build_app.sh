#!/bin/bash
# -*- coding: utf-8 -*-
# 构建 PhraseKey.app（SwiftPM 编译 + 组装 macOS 输入法 bundle）
# 用法：bash Scripts/build_app.sh [release|debug]  默认 release
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
APP_NAME="PhraseKey"
CONFIG="${1:-release}"

echo "==> [1/4] 生成词库"
# 坑（已定性，造成“本地测全过 / 用户装上没候选”的落差）：
#   原本无条件跑 gen_dict.py —— 它只生成 **108 条示例词库**，
#   会把 gen_dict_full.py 生成的 20 万条真词库**覆盖掉**。
#   后果：debug 环境有全量词库测什么都对，而打包安装的只有 108 条，
#   表现为“打两个字就无候选 / 不能连续输入”。
# 现在：已有全量词库则不动；没有才生成（优先全量，失败才退到示例）。
DICT_SRC="$ROOT/Sources/PhraseKeyIME/Resources/dict.tsv"
DICT_MIN_LINES=10000   # 低于此数视为“示例词库”，不得打包

if [ -f "$DICT_SRC" ] && [ "$(wc -l < "$DICT_SRC")" -ge "$DICT_MIN_LINES" ]; then
  echo "    已有全量词库 $(wc -l < "$DICT_SRC") 条，跳过生成"
else
  echo "    词库缺失或过小，尝试生成全量词库…"
  python3 Scripts/gen_dict_full.py || {
    echo "    ⚠️  全量词库生成失败（缺 jieba?），退到示例词库"
    python3 Scripts/gen_dict.py
  }
fi

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

# ---- 出厂门禁：验证产物真的可用，不只是“构建成功” ----
# 坑（已定性）：曾把只包含 108 条示例词库的包装给用户，
#   自己本地 debug 环境却是 20 万条 —— “测都过了”与“用不了”同时成立。
#   以后任何产物必须过下面这几道，不过就算构建失败。
echo "==> 出厂门禁"
GATE_FAIL=0

_gate() {  # _gate "说明" 条件命令…
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "    ✅ $desc"
  else
    echo "    ❌ $desc"
    GATE_FAIL=1
  fi
}

APP_DICT="$APP/Contents/Resources/dict.tsv"
APP_HANZI="$APP/Contents/Resources/hanzi_pinyin.tsv"

_gate "二进制存在且可执行" test -x "$APP/Contents/MacOS/PhraseKeyIME"
_gate "Info.plist 存在" test -f "$APP/Contents/Info.plist"
_gate "词库存在" test -f "$APP_DICT"
_gate "汉字拼音表存在" test -f "$APP_HANZI"

if [ -f "$APP_DICT" ]; then
  DICT_N=$(wc -l < "$APP_DICT" | tr -d ' ')
  if [ "$DICT_N" -ge "$DICT_MIN_LINES" ]; then
    echo "    ✅ 词库规模 ${DICT_N} 条（>= ${DICT_MIN_LINES}）"
  else
    echo "    ❌ 词库只有 ${DICT_N} 条 —— 这是示例词库，装上去打两个字就无候选"
    GATE_FAIL=1
  fi
  # 抽查常用词：这些打不出来就不可能日常使用
  # 注意词库列序为「拼音 \t 词 \t 词频」，词在**第 2 列**，不是第 1 列。
  #   坑：最初写成 grep "^$w\t" 按第 1 列匹配 → 全部误报缺失，
  #       差点把一个完好的 20 万词库判为不可交付。断言写错比没有断言更坏。
  for w in 你好 我们 中国 明天 什么 因为; do
    if awk -F'\t' -v w="$w" '$2 == w { found = 1; exit } END { exit !found }' "$APP_DICT"; then
      echo "    ✅ 词库含 ${w}"
    else
      echo "    ❌ 词库缺 ${w} —— 常用词缺失，不可交付"
      GATE_FAIL=1
    fi
  done
fi

if [ "$GATE_FAIL" -ne 0 ]; then
  echo ""
  echo "❌ 出厂门禁未过 —— 不得安装此产物。"
  exit 1
fi

echo ""
echo "✅ 构建完成（门禁全绿）：$APP"
echo "   安装：bash Scripts/install.sh"
