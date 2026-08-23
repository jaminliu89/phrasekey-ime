import Foundation

// PhraseKey 候选探针：打印任意输入的候选列表（含词频与来源），用于排序调优。
// 用法：bash Scripts/probe_query.sh womenz zhongguor niha
//      bash Scripts/probe_query.sh --step nihaoshijie   # 逐字母展开

let args = Array(CommandLine.arguments.dropFirst())
guard !args.isEmpty else {
    print("用法：probe <输入> [输入...]        打印候选（默认全拼）")
    print("      probe --step <输入>          逐字母展开")
    print("      probe <输入>                  默认方案（当前：\(InputScheme.default.rawValue)）")
    print("      probe --pinyin <输入>        全拼")
    print("      probe --flypy <输入>         小鹤双拼")
    print("      probe --xing <输入>          小鹤音形方案")
    exit(2)
}

let stepMode = args.contains("--step")
// 方案开关：默认方案是小鹤双拼，探针必须能按方案跑，否则测的根本不是用户实际路径。
// 方案选择：不传时跟随产品默认（InputScheme.default）。
// 坑（已定性第 4 次）：此处原为写死 `: .pinyin` —— 探针默认测的不是
//   用户默认路径，导致「验证默认方案」时实际验的是全拼，结论完全不作数。
//   同根因已在 iOS 键盘、HotwordsStore.search、Searcher.search、PinyinEngine.query
//   出现过 —— 默认参数写死是本仓库的家族性缺陷，改之前先 grep 全仓。
let scheme: InputScheme = args.contains("--pinyin") ? .pinyin
    : (args.contains("--flypy") ? .flypy
    : (args.contains("--xing") ? .flypyXing : InputScheme.default))
let inputs = args.filter { !$0.hasPrefix("--") }

_ = PinyinEngine.shared.entryCount   // 触发加载

/// 打印一行候选，带权重与类型（hotword 标 ★）。
func dump(_ input: String, indent: String = "") {
    let res = Searcher.shared.search(input, scheme: scheme)
    if res.isEmpty {
        print("\(indent)\(input)  ⚠️ 候选为空（断档）")
        return
    }
    let head = res.prefix(10).enumerated().map { i, e in
        let mark = e.type == "hotword" ? "★" : ""
        // score 与 freq 均打印：只看 score 会误以为同分就是没排序（我自己踩过）
        return "\(i + 1).\(mark)\(e.text)[s\(e.score)/f\(e.freq)]"
    }.joined(separator: "  ")
    print("\(indent)\(input)  共\(res.count)  \(head)")
}

for input in inputs {
    if stepMode {
        print("=== \(input) 逐字母（\(scheme.rawValue)）===")
        var chars = ""
        for ch in input {
            chars.append(ch)
            dump(chars, indent: "  ")
        }
        print("")
    } else {
        print("=== \(input)（\(scheme.rawValue)）===")
        if scheme == .pinyin {
            print("  切分：\(PinyinSyllable.segment(input.lowercased()).joined(separator: "/"))")
        } else {
            print("  双拼解码：\(FlypyCodec.decode(input.lowercased()).joined(separator: "/"))")
        }
        dump(input, indent: "  ")
        print("")
    }
}
