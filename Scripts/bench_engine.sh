#!/usr/bin/env bash
# PhraseKey 引擎基准 + 回归测试
# 只编译平台无关的引擎层（纯 Foundation），不碰 AppKit / IMK，所以能直接跑 CLI。
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="$ROOT/.build/bench"
mkdir -p "$OUT"

echo "编译引擎基准…"
swiftc -O \
  -o "$OUT/bench" \
  Sources/PhraseKeyIME/Engine/CodeTable.swift \
  Sources/PhraseKeyIME/Engine/FlypyCodec.swift \
  Sources/PhraseKeyIME/Engine/PinyinEngine.swift \
  Sources/PhraseKeyIME/Engine/PinyinSyllable.swift \
  Sources/PhraseKeyIME/Engine/Searcher.swift \
  Sources/PhraseKeyIME/Hotwords/HotwordsStore.swift \
  Sources/PhraseKeyIME/Settings/InputScheme.swift \
  Sources/PhraseKeyIME/Settings/PhraseKeySettings.swift \
  Tests/Bench/main.swift

echo "运行（工作目录 = 仓库根，引擎会从 Sources/.../Resources 旁路加载词库）"
echo
cd "$ROOT"
"$OUT/bench"
