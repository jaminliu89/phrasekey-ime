#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 PhraseKey 全量词库（格式：全拼\t词\t词频）。

数据源：
  - jieba dict.txt（349k 词条 + 真实语料词频）
  - pypinyin（带短语库，词语上下文多音字读音更准）

产出两档：
  - dict.tsv         桌面端全量（默认取 top N_DESKTOP）
  - dict_mobile.tsv  iOS 键盘扩展精简档（内存预算小，取 top N_MOBILE）

用法：
  python3 Scripts/gen_dict_full.py
  python3 Scripts/gen_dict_full.py --desktop 200000 --mobile 60000
"""
from __future__ import annotations

import argparse
import os
import re
import sys

BASE = os.path.normpath(
    os.path.join(os.path.dirname(__file__), "..", "Sources", "PhraseKeyIME", "Resources")
)

# 默认档位（实测后可调）
N_DESKTOP = 200_000
N_MOBILE = 60_000

# 只保留纯中文词条（jieba 词典里混有 "AT&T" "c++" "B超" 等）
HANZI_ONLY = re.compile(r"^[\u4e00-\u9fff]+$")

# 手工高频兜底：确保这些常用表达一定在词库里且排名靠前
MANUAL_BOOST: dict[str, int] = {
    "你好": 2_000_000,
    "谢谢": 1_800_000,
    "好的": 1_700_000,
    "收到": 1_600_000,
    "辛苦了": 1_500_000,
    "没问题": 1_400_000,
    "没关系": 1_300_000,
    "早上好": 1_200_000,
    "晚上好": 1_200_000,
    "中午好": 1_100_000,
    "明白了": 1_000_000,
    "不好意思": 1_000_000,
    "麻烦你": 900_000,
    "非常感谢": 900_000,
    "稍后联系": 800_000,
    "合作愉快": 800_000,
    "新年快乐": 800_000,
    "生日快乐": 800_000,
    "恭喜发财": 700_000,
    "周末愉快": 700_000,
    "人工智能": 700_000,
    "大语言模型": 600_000,
    "机器学习": 600_000,
    "开源社区": 500_000,
    "输入法": 500_000,
    "常用语": 400_000,
    "剪贴板": 400_000,
    "快捷键": 400_000,
    "会议纪要": 400_000,
}


def load_jieba_dict() -> list[tuple[str, int]]:
    """读 jieba dict.txt → [(词, 词频)]，只保留纯汉字词。"""
    try:
        import jieba
    except ImportError:
        sys.exit("需要 jieba：pip3 install jieba")

    path = os.path.join(os.path.dirname(jieba.__file__), "dict.txt")
    if not os.path.exists(path):
        sys.exit(f"找不到 jieba 词典：{path}")

    out: list[tuple[str, int]] = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            parts = line.split()
            if len(parts) < 2:
                continue
            word, freq = parts[0], parts[1]
            if not HANZI_ONLY.match(word):
                continue
            if len(word) > 8:  # 超长词对输入法价值低，且拖慢索引
                continue
            try:
                out.append((word, int(freq)))
            except ValueError:
                continue
    return out


def to_pinyin(word: str) -> str | None:
    """词 → 空格分隔无调全拼。任一字取不到拼音则返回 None（丢弃该词）。"""
    from pypinyin import Style, lazy_pinyin

    syls = lazy_pinyin(word, style=Style.NORMAL, errors="ignore")
    if len(syls) != len(word):
        return None  # 有字没拼出来（生僻字/异体字），丢弃
    for s in syls:
        if not s or not s.isalpha() or not s.isascii():
            return None
    return " ".join(syls)


def write_tsv(rows: list[tuple[str, str, int]], filename: str) -> None:
    path = os.path.join(BASE, filename)
    with open(path, "w", encoding="utf-8") as f:
        for pinyin, word, freq in rows:
            f.write(f"{pinyin}\t{word}\t{freq}\n")
    size_mb = os.path.getsize(path) / 1024 / 1024
    print(f"✅ {filename}：{len(rows):,} 条，{size_mb:.2f} MB")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--desktop", type=int, default=N_DESKTOP, help="桌面档条数")
    ap.add_argument("--mobile", type=int, default=N_MOBILE, help="移动档条数")
    args = ap.parse_args()

    os.makedirs(BASE, exist_ok=True)

    print("读取 jieba 词典…")
    words = load_jieba_dict()
    print(f"  纯汉字词条：{len(words):,}")

    # 词频归一：jieba 词频跨度大（1 ~ 2000w），压到便于 Swift Int 排序的区间
    max_freq = max(f for _, f in words)
    print(f"  最大词频：{max_freq:,}")

    print("转拼音（pypinyin，带短语库）…")
    rows: list[tuple[str, str, int]] = []
    seen: set[tuple[str, str]] = set()
    skipped = 0
    for i, (word, freq) in enumerate(words):
        if i and i % 50_000 == 0:
            print(f"  …{i:,}/{len(words):,}")
        pinyin = to_pinyin(word)
        if pinyin is None:
            skipped += 1
            continue
        boosted = MANUAL_BOOST.get(word)
        norm_freq = boosted if boosted else max(1, int(freq * 1_000_000 / max_freq))
        key = (pinyin, word)
        if key in seen:
            continue
        seen.add(key)
        rows.append((pinyin, word, norm_freq))

    # 手工兜底里 jieba 没有的词，补进去
    have = {w for _, w, _ in rows}
    for word, freq in MANUAL_BOOST.items():
        if word in have:
            continue
        pinyin = to_pinyin(word)
        if pinyin:
            rows.append((pinyin, word, freq))

    print(f"  转换完成：{len(rows):,} 条（丢弃 {skipped:,} 条无法转拼音）")

    # 按词频降序 —— 引擎按 top N 截断时拿到的就是最有价值的词
    rows.sort(key=lambda r: -r[2])

    write_tsv(rows[: args.desktop], "dict.tsv")
    write_tsv(rows[: args.mobile], "dict_mobile.tsv")

    # 抽查
    print("\n抽查（前 15 条）：")
    for pinyin, word, freq in rows[:15]:
        print(f"  {pinyin}\t{word}\t{freq}")

    print("\n关键词覆盖检查：")
    index = {w for _, w, _ in rows[: args.mobile]}
    for probe in ["明天", "开会", "辛苦了", "人工智能", "谢谢", "项目", "输入法", "婚礼"]:
        print(f"  {probe}: {'✅ 移动档内' if probe in index else '⚠️ 不在移动档'}")


if __name__ == "__main__":
    main()
