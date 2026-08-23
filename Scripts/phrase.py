#!/usr/bin/env python3
"""常用语命令行管理 —— 项目核心功能的批量入口。

为什么要它（定位文档 01-positioning.md「为什么换过来」第③条）：
  「数据在我自己的目录里，可 git、可脚本批处理」是本项目三个核心要求之一。
  靠 GUI 一条条加不叫可批处理 —— 那正是主流输入法「藏得深」的毛病。

用法：
  phrase.py list                       列出全部
  phrase.py add <简码> <文本>           加一条
  phrase.py rm  <简码|id>               删一条
  phrase.py import <file.tsv>          批量导入（简码\\t文本，# 开头为注释）
  phrase.py export [file.tsv]          导出为 TSV（默认 stdout）
  phrase.py seed                       写入内置种子集（不覆盖已有简码）
  phrase.py wetype [--replace]         从微信输入法导入常用语（只读，见下）

微信输入法导入（wetype）：
  数据源 ~/Library/Application Support/WeType/mmkv/wetype.settings 的 hotWordList，
  字段结构与本项目 hotwords.json **完全一致**（hw_id/text/key）—— 可直接搬。
  全程只读，绝不写 WeType 任何文件（参考 wetype-hotwords-export skill 的风控规范）。
  默认「合并」：已存在的简码跳过，不覆盖你在本项目里改过的内容。
  --replace 则用微信侧内容覆盖同简码条目。
"""
import json, os, sys, uuid, pathlib

STORE = pathlib.Path.home() / "Library/Application Support/PhraseKey/hotwords.json"

def load():
    if not STORE.exists(): return []
    try:
        d = json.loads(STORE.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return []
    return d if isinstance(d, list) else d.get("items", [])

def save(items):
    STORE.parent.mkdir(parents=True, exist_ok=True)
    # 与 Swift 侧 Codable 对齐：顶层就是数组，字段名 hw_id/text/key
    STORE.write_text(json.dumps(items, ensure_ascii=False, indent=2), encoding="utf-8")

def add_one(items, key, text, quiet=False):
    key = key.strip().lower()
    for it in items:
        if it.get("key", "").lower() == key:
            if not quiet: print(f"  跳过（简码已存在）{key} → {it['text']}")
            return False
    items.append({"hw_id": str(uuid.uuid4()), "text": text, "key": key})
    if not quiet: print(f"  + {key:12} → {text}")
    return True

WETYPE_MMKV = pathlib.Path.home() / "Library/Application Support/WeType/mmkv/wetype.settings"

def read_wetype_hotwords():
    """从微信输入法 MMKV 只读提取常用语。

    为什么能直接搬：实测其 hotWordList 的结构就是 [{"hw_id","text","key"}]，
    与本项目 hotwords.json 字段**完全一致** —— 同一套模型，不需要转换。

    风控红线（照 wetype-hotwords-export skill 的规范，不可违反）：
      · 只读打开，绝不写 WeType 目录下任何文件
      · 不碰加密库（DataBase/common.db、mmkv/wetype.common1 是剪贴板等敏感数据）
      · 不启动 WeType UI、不做 UI 自动化
    """
    if not WETYPE_MMKV.exists():
        print(f"  找不到微信输入法数据：{WETYPE_MMKV}")
        print("  （需已安装并使用过微信输入法 macOS 版）")
        return []
    raw = WETYPE_MMKV.read_bytes()          # 只读
    # MMKV 是紧凑二进制，hotWordList 的值是一段 UTF-8 JSON 数组。
    # 不解析 MMKV 全格式（没必要且易碎），直接定位 JSON 数组：
    #   从 "hw_id" 首次出现处向前找 '['，再做括号配平找到结尾。
    key = b'"hw_id"'
    at = raw.find(key)
    if at < 0:
        print("  未在数据中找到 hotWordList（可能微信输入法版本变了）")
        return []
    start = raw.rfind(b"[", 0, at)
    if start < 0:
        return []
    depth, end = 0, -1
    for i in range(start, len(raw)):
        c = raw[i]
        if c == 0x5B: depth += 1            # [
        elif c == 0x5D:                     # ]
            depth -= 1
            if depth == 0:
                end = i + 1
                break
    if end < 0:
        return []
    try:
        return json.loads(raw[start:end].decode("utf-8", errors="strict"))
    except (json.JSONDecodeError, UnicodeDecodeError) as e:
        print(f"  解析失败（可能正在被输入法写入，稍后重试）：{e}")
        return []

def import_wetype(items, replace=False):
    src = read_wetype_hotwords()
    if not src:
        return 0
    by_key = {i.get("key", "").lower(): i for i in items if i.get("key", "").strip()}
    added = updated = skipped = nokey = 0
    for s in src:
        text = (s.get("text") or "").strip()
        k = (s.get("key") or "").strip().lower()
        if not text:
            continue
        if not k:
            # 微信侧允许无简码（靠拼音/子串命中）。本项目同样支持，直接收。
            if any(i["text"] == text for i in items):
                skipped += 1
            else:
                items.append({"hw_id": s.get("hw_id") or str(uuid.uuid4()), "text": text, "key": ""})
                nokey += 1
            continue
        if k in by_key:
            if replace and by_key[k]["text"] != text:
                by_key[k]["text"] = text
                updated += 1
            else:
                skipped += 1
            continue
        rec = {"hw_id": s.get("hw_id") or str(uuid.uuid4()), "text": text, "key": k}
        items.append(rec)
        by_key[k] = rec
        added += 1
    print(f"  微信输入法共 {len(src)} 条")
    print(f"    新增(带简码) {added}   新增(无简码) {nokey}   覆盖 {updated}   跳过 {skipped}")
    return added + updated + nokey

def main():
    if len(sys.argv) < 2:
        print(__doc__); return 1
    cmd, args = sys.argv[1], sys.argv[2:]
    items = load()

    if cmd == "list":
        if not items:
            print("（空）用 phrase.py seed 写入种子集，或 phrase.py add <简码> <文本>")
            return 0
        w = max(len(i.get("key","")) for i in items) + 2
        for i in items:
            print(f"  {i.get('key',''):<{w}} {i['text']}")
        print(f"\n  共 {len(items)} 条 → {STORE}")

    elif cmd == "add":
        if len(args) < 2: print("用法: add <简码> <文本>"); return 1
        if add_one(items, args[0], " ".join(args[1:])): save(items)

    elif cmd == "rm":
        t = args[0].lower() if args else ""
        before = len(items)
        items = [i for i in items if i.get("key","").lower() != t and i.get("hw_id") != args[0]]
        if len(items) < before: save(items); print(f"  已删 {before - len(items)} 条")
        else: print(f"  没找到：{t}")

    elif cmd == "import":
        if not args: print("用法: import <file.tsv>"); return 1
        n = 0
        for line in pathlib.Path(args[0]).read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#"): continue
            parts = line.split("\t")
            if len(parts) < 2: continue
            if add_one(items, parts[0], parts[1]): n += 1
        save(items); print(f"\n  导入 {n} 条，现共 {len(items)} 条")

    elif cmd == "export":
        lines = [f"{i.get('key','')}\t{i['text']}" for i in items]
        out = "\n".join(lines)
        if args: pathlib.Path(args[0]).write_text(out + "\n", encoding="utf-8"); print(f"  已导出 {len(lines)} 条 → {args[0]}")
        else: print(out)

    elif cmd == "seed":
        seed_file = pathlib.Path(__file__).parent / "phrases_seed.tsv"
        if not seed_file.exists(): print(f"缺种子文件 {seed_file}"); return 1
        n = 0
        for line in seed_file.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#"): continue
            parts = line.split("\t")
            if len(parts) >= 2 and add_one(items, parts[0], parts[1]): n += 1
        save(items); print(f"\n  新增 {n} 条，现共 {len(items)} 条 → {STORE}")

    elif cmd == "wetype":
        n = import_wetype(items, replace="--replace" in args)
        if n: save(items)
        print(f"\n  现共 {len(items)} 条 → {STORE}")

    else:
        print(__doc__); return 1
    return 0

sys.exit(main())
