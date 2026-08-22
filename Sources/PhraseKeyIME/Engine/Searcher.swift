import Foundation

/// Combined searcher: merges phrases and pinyin dictionary into one candidate list.
/// Ranking (differentiator: phrases always beat dictionary words):
///   1. Phrase·key exact match (all schemes, key = user's personal shape code)
///   2. Phrase·key prefix
///   3. Dictionary·full pinyin exact / shuangpin exact
///   4. Phrase·pinyin initials / shuangpin code
///   5. Dictionary·initial pinyin
///   6. Phrase·text substring
final class Searcher {
    static let shared = Searcher()

    struct Candidate: Identifiable {
        let id = UUID()
        let text: String
        let type: String   // "hotword" | "word"
        let score: Int
        let hotword: Hotword?
        let pinyin: String // 拼音（空格分隔，空格分隔音节），type=word 时有值
        /// 原始词频，仅用作同分时的稳定 tiebreak（不参与 score 计算）。
        let freq: Int
    }

    /// 词频 → tiebreak 用的归一化值。
    /// 坑（经实测确认）：曾经用 min(freq, 999) 直接截断做主排序信号。两重错：
    ///   ① 字典真实词频最大 2000000，其中 7987 条 freq>999，截断后全变 999
    ///     → score 全部并列 1999。对照证据：「我」372146 / 「我们」111743 / 「斞」1017
    ///     真实差 300 倍却同分，womenz 时「我们」被生冗字「斞/卧/窝」压到后面。
    ///   ② 即使不截断，词频也不该当主信号 —— 见 coverBonus。
    /// 现在只做 tiebreak，用对数压缩保留量级差异。
    ///   freq=3 → 71   freq=1017 → 454   freq=111743 → 762   freq=2000000 → 951
    private func freqBonus(_ freq: Int) -> Int {
        guard freq > 0 else { return 0 }
        // log10(2_000_000) ≈ 6.301，×151 后封顶约 951
        return min(Int(log10(Double(freq)) * 151), 999)
    }

    /// 覆盖度 → 主排序信号（候选拼音与输入的公共前缀占输入的比例）。
    /// 为何覆盖度才是主信号：用户多敲一个字母就是在缩小意图范围。
    ///   输入 womenz（ 6 字母）时「我」只覆盖 wo（2）、「我们」覆盖 women（5），
    ///   即使「我」词频高 3 倍，用户想打的也显然是「我们」—— 否则他不会接着敲 menz。
    /// 用比例而非绝对长度：避开长输入时加成穿透 baseScore 分档。
    private func coverBonus(candidatePinyin: String, input: String) -> Int {
        guard !input.isEmpty else { return 0 }
        let flat = candidatePinyin.replacingOccurrences(of: " ", with: "")
        var n = 0
        var a = flat.startIndex, b = input.startIndex
        while a < flat.endIndex, b < input.endIndex, flat[a] == input[b] {
            n += 1
            a = flat.index(after: a)
            b = input.index(after: b)
        }
        return Int(Double(n) / Double(input.count) * 999)
    }

    /// Combined search. scheme: pinyin / xiaohe shuangpin / xiaohe xingma.
    func search(_ input: String, scheme: InputScheme = .pinyin) -> [Candidate] {
        let norm = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !norm.isEmpty else { return [] }
        var out: [Candidate] = []

        // 拼音字符判定：全字母（含 v 代替 ü）走拼音/简码；含中文直接当子串
        let isAlphabetic = norm.unicodeScalars.allSatisfy { CharacterSet.lowercaseLetters.contains($0) }

        if isAlphabetic {
            // 常用语优先
            for (type, hw) in HotwordsStore.shared.search(norm, scheme: scheme) {
                let score: Int
                switch type {
                case .key: score = 10000
                case .initials: score = 3000
                case .contains: score = 100
                }
                out.append(Candidate(text: hw.text, type: "hotword", score: score, hotword: hw, pinyin: "", freq: 0))
            }
            // 词库（用户词典 + 内置，用户词典 freq 更高自然靠前）
            for e in PinyinEngine.shared.query(norm, scheme: scheme) {
                let pinyinExact = e.pinyin.replacingOccurrences(of: " ", with: "") == norm
                let baseScore = pinyinExact ? 2000 : 1000
                // 主信号 = 覆盖度；freq 已下沉为 sorted 里的 tiebreak。
                let cover = coverBonus(candidatePinyin: e.pinyin, input: norm)
                out.append(Candidate(text: e.word, type: "word", score: baseScore + cover, hotword: nil, pinyin: e.pinyin, freq: e.freq))
            }
            // 音形模式：对词库候选做形码过滤（若装了码表）
            if scheme == .flypyXing {
                out = applyXingmaFilter(out, input: norm)
            }
        } else {
            // 直接输入中文（如粘贴）：按子串找常用语
            for (type, hw) in HotwordsStore.shared.search(norm, scheme: scheme) {
                let score = type == .contains ? 1000 : 2000
                out.append(Candidate(text: hw.text, type: "hotword", score: score, hotword: hw, pinyin: "", freq: 0))
            }
        }

        // 去重（同文本保留最高分）后排序。
        // 坑（经实测确认）：原先直接 best.values.sorted { $0.score > $1.score }。
        //   Dictionary.values 遍历顺序不保证，Swift sorted 也不是稳定排序，
        //   同分候选的相对顺序会逐次进程变化。
        //   实测：同一个 womenz 连续跑三次，「我们」分别落在第 6 / 1 / 3 位。
        //   候选位置随机 = 用户无法建立背记式背编号，比排得不准更致命。
        // 因此排序必须全序：score（精确匹配 + 覆盖度）→ 词频 → 词长 → text 字典序。
        // 最后一级 text 保证完全确定，同输入永远同顺序。
        var best: [String: Candidate] = [:]
        for c in out {
            if let old = best[c.text] {
                if c.score > old.score { best[c.text] = c }
            } else {
                best[c.text] = c
            }
        }
        let sorted = best.values.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            let fa = freqBonus(a.freq), fb = freqBonus(b.freq)
            if fa != fb { return fa > fb }
            if a.text.count != b.text.count { return a.text.count > b.text.count }
            return a.text < b.text
        }
        return Array(sorted.prefix(50))
    }

    /// Xingma filter: after shuangpin candidates are produced, filter by remaining shape-code keys.
    /// Rule: input = shuangpin(2·wordLen) + xingma(1~2). When input exceeds shuangpin length,
    /// extra keys are shape-code prefix; candidates matched per-character. Falls back to shuangpin if no table.
    private func applyXingmaFilter(_ cands: [Candidate], input: String) -> [Candidate] {
        let codeTable = CodeTable.shared
        guard codeTable.hasLoaded else { return cands } // 未装码表 → 退化为双拼

        let chars = Array(input)
        guard chars.count > 2 else { return cands }
        // 尝试把末 1~2 键作为形码，取能命中候选的组合
        for len in [1, 2] where chars.count - len >= 2 {
            let flypyLen = chars.count - len
            guard flypyLen.isMultiple(of: 2) else { continue }
            let xingPart = String(chars[flypyLen...])
            guard !xingPart.isEmpty else { continue }
            let filtered = cands.filter { codeTable.matches(word: $0.text, xingPrefix: xingPart) }
            if !filtered.isEmpty {
                return filtered
            }
        }
        return cands
    }
}
