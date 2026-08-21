#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成跨平台汉字→拼音表 Resources/hanzi_pinyin.tsv（字\\t拼音，无声调，取常用读音）。
数据源：mozillazg/pinyin-data 的 kXHC1983.txt（新华字典拼音表，11072 汉字）。
替换 CFStringTransform，让引擎不依赖 Apple 专属 API，可跨端复用（macOS/iOS/未来 Win/Linux）。
用法：python3 Scripts/gen_pinyin_map.py [kxhc.txt] [输出.tsv]
"""
import os, re, sys

TONE = {
    "ā": "a", "á": "a", "ǎ": "a", "à": "a",
    "ē": "e", "é": "e", "ě": "e", "è": "e",
    "ī": "i", "í": "i", "ǐ": "i", "ì": "i",
    "ō": "o", "ó": "o", "ǒ": "o", "ò": "o",
    "ū": "u", "ú": "u", "ǔ": "u", "ù": "u",
    "ǖ": "ü", "ǘ": "ü", "ǚ": "ü", "ǜ": "ü", "ü": "ü",
    "ń": "n", "ň": "n", "": "m",
}

def strip_tone(py: str) -> str:
    return "".join(TONE.get(c, c) for c in py)

def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "/tmp/kxhc.txt"
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
        root, "Sources", "PhraseKeyIME", "Resources", "hanzi_pinyin.tsv")

    table = {}  # 字 -> 拼音（多音取第一个出现）
    pattern = re.compile(r"U\+([0-9A-Fa-f]+):\s*(\S+)(?:\s+#\s*(\S+))?")
    with open(src, encoding="utf-8") as f:
        for line in f:
            m = pattern.match(line)
            if not m:
                continue
            cp = int(m.group(1), 16)
            ch = chr(cp)
            # 多读音逗号分隔，取第一个（常用读音）
            py = strip_tone(m.group(2).split(",")[0].split()[0])
            if ch not in table:
                table[ch] = py

    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        for ch in sorted(table.keys()):
            f.write(f"{ch}\t{table[ch]}\n")
    print(f"✅ 已生成 {out}（{len(table)} 个汉字）")

if __name__ == "__main__":
    main()
