#!/usr/bin/env bash
# 抓取键盘扩展加载相关的设备日志（iOS 真机）
# 用法：bash Scripts/capture_keyboard_log.sh <输出文件> <抓取秒数>
set -uo pipefail

OUT="${1:-/tmp/pk-keyboard.log}"
SECS="${2:-40}"

command -v idevicesyslog >/dev/null || { echo "需要 idevicesyslog：brew install libimobiledevice"; exit 1; }

echo "开始抓取 ${SECS}s → $OUT"
: > "$OUT"
idevicesyslog > "$OUT" 2>/dev/null &
PID=$!
trap 'kill $PID 2>/dev/null' EXIT
sleep "$SECS"
kill $PID 2>/dev/null || true
wait $PID 2>/dev/null || true

echo
echo "=== 总行数：$(wc -l < "$OUT") ==="
echo
echo "=== PhraseKey 相关 ==="
grep -i "phrasekey" "$OUT" || echo "（无 —— 系统完全没有提到这个扩展）"
echo
echo "=== 扩展生命周期 / PlugInKit / 加载拒绝 ==="
grep -iE "pkd|plugin ?kit|extensionKit|invalidat|denied|reject|not entitled|Sandbox|codesign|amfi" "$OUT" \
  | grep -viE "Spotlight|GenerativeModels|Siri" | head -40 || echo "（无）"
echo
echo "=== 键盘子系统 ==="
grep -iE "keyboard|TextInput|inputMode|UIKBRemote|remoteTextInput" "$OUT" \
  | grep -viE "Spotlight|GenerativeModels" | head -40 || echo "（无）"
echo
echo "完整日志：$OUT"
