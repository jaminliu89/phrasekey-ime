#!/usr/bin/env bash
# PhraseKey 候选探针：看任意输入的候选顺序与词频，用于排序调优。
# 用法：
#   bash Scripts/probe_query.sh womenz zhongguor niha
#   bash Scripts/probe_query.sh --step nihaoshijie
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="$ROOT/.build/probe"
mkdir -p "$OUT"

SRC=(
  Sources/PhraseKeyIME/Engine/CodeTable.swift
  Sources/PhraseKeyIME/Engine/FlypyCodec.swift
  Sources/PhraseKeyIME/Engine/PinyinEngine.swift
  Sources/PhraseKeyIME/Engine/PinyinSyllable.swift
  Sources/PhraseKeyIME/Engine/Searcher.swift
  Sources/PhraseKeyIME/Hotwords/HotwordsStore.swift
  Sources/PhraseKeyIME/Settings/InputScheme.swift
  Sources/PhraseKeyIME/Settings/PhraseKeySettings.swift
  Tests/Probe/main.swift
)

# 只在源码比产物新时重编，省时间
NEED_BUILD=1
if [[ -x "$OUT/probe" ]]; then
  NEED_BUILD=0
  for f in "${SRC[@]}"; do
    if [[ "$f" -nt "$OUT/probe" ]]; then NEED_BUILD=1; break; fi
  done
fi
if [[ $NEED_BUILD -eq 1 ]]; then
  echo "编译探针…" >&2
  swiftc -O -o "$OUT/probe" "${SRC[@]}"
fi

cd "$ROOT"
"$OUT/probe" "$@"
