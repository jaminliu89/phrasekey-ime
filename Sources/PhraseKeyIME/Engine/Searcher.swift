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
                out.append(Candidate(text: hw.text, type: "hotword", score: score, hotword: hw, pinyin: ""))
            }
            // 词库（用户词典 + 内置，用户词典 freq 更高自然靠前）
            for e in PinyinEngine.shared.query(norm, scheme: scheme) {
                let pinyinExact = e.pinyin.replacingOccurrences(of: " ", with: "") == norm
                let baseScore = pinyinExact ? 2000 : 1000
                // 词频加成：freq 越高排越前，用户词典 freq 通常远大于内置
                let freqBonus = min(e.freq, 999)
                out.append(Candidate(text: e.word, type: "word", score: baseScore + freqBonus, hotword: nil, pinyin: e.pinyin))
            }
            // 音形模式：对词库候选做形码过滤（若装了码表）
            if scheme == .flypyXing {
                out = applyXingmaFilter(out, input: norm)
            }
        } else {
            // 直接输入中文（如粘贴）：按子串找常用语
            for (type, hw) in HotwordsStore.shared.search(norm, scheme: scheme) {
                let score = type == .contains ? 1000 : 2000
                out.append(Candidate(text: hw.text, type: "hotword", score: score, hotword: hw, pinyin: ""))
            }
        }

        // 去重（同文本保留最高分）后排序
        var best: [String: Candidate] = [:]
        for c in out {
            if let old = best[c.text] {
                if c.score > old.score { best[c.text] = c }
            } else {
                best[c.text] = c
            }
        }
        return best.values.sorted { $0.score > $1.score }.prefix(50).map { $0 }
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
