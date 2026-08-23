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

    else:
        print(__doc__); return 1
    return 0

sys.exit(main())
