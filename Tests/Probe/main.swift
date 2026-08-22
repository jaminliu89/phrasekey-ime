import Foundation

// PhraseKey 候选探针：打印任意输入的候选列表（含词频与来源），用于排序调优。
// 用法：bash Scripts/probe_query.sh womenz zhongguor niha
//      bash Scripts/probe_query.sh --step nihaoshijie   # 逐字母展开

let args = Array(CommandLine.arguments.dropFirst())
guard !args.isEmpty else {
    print("用法：probe <输入> [输入...]        打印候选")
    print("      probe --step <输入>          逐字母展开")
    exit(2)
}

let stepMode = args.contains("--step")
let inputs = args.filter { $0 != "--step" }

_ = PinyinEngine.shared.entryCount   // 触发加载

/// 打印一行候选，带权重与类型（hotword 标 ★）。
func dump(_ input: String, indent: String = "") {
    let res = Searcher.shared.search(input, scheme: .pinyin)
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
        print("=== \(input) 逐字母 ===")
        var chars = ""
        for ch in input {
            chars.append(ch)
            dump(chars, indent: "  ")
        }
        print("")
    } else {
        print("=== \(input) ===")
        let segs = PinyinSyllable.segment(input.lowercased())
        print("  切分：\(segs.joined(separator: "/"))")
        dump(input, indent: "  ")
        print("")
    }
}
