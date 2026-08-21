import Foundation

/// 综合搜索器：把「常用语」与「拼音词库」融合成一个候选列表。
/// 排序优先级（差异化核心：常用语永远压过普通词）：
///   1. 常用语·简码精确命中（所有方案，key 即用户自定义形码）
///   2. 常用语·简码前缀
///   3. 词库·全拼精确 / 双拼精确
///   4. 常用语·文本拼音首字母 / 双拼编码
///   5. 词库·简拼
///   6. 常用语·文本子串
final class Searcher {
    static let shared = Searcher()

    struct Candidate: Identifiable {
        let id = UUID()
        let text: String
        let type: String   // "hotword" | "word"
        let score: Int
        let hotword: Hotword?
    }

    /// 综合搜索。scheme：全拼/小鹤双拼/小鹤音形。
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
                out.append(Candidate(text: hw.text, type: "hotword", score: score, hotword: hw))
            }
            // 词库
            for e in PinyinEngine.shared.query(norm, scheme: scheme) {
                let pinyinExact = e.pinyin.replacingOccurrences(of: " ", with: "") == norm
                let score = pinyinExact ? 2000 : 1000
                out.append(Candidate(text: e.word, type: "word", score: score, hotword: nil))
            }
            // 音形模式：对词库候选做形码过滤（若装了码表）
            if scheme == .flypyXing {
                out = applyXingmaFilter(out, input: norm)
            }
        } else {
            // 直接输入中文（如粘贴）：按子串找常用语
            for (type, hw) in HotwordsStore.shared.search(norm, scheme: scheme) {
                let score = type == .contains ? 1000 : 2000
                out.append(Candidate(text: hw.text, type: "hotword", score: score, hotword: hw))
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

    /// 音形过滤：双拼部分已出候选后，用剩余形码键过滤。
    /// 规则：输入串 = 双拼(2·字数) + 形码(1~2)。当输入长度超过双拼长度时，
    /// 多出的键作为形码前缀；候选逐字匹配形码。未装码表则退化为双拼。
    private func applyXingmaFilter(_ cands: [Candidate], input: String) -> [Candidate] {
        let codeTable = CodeTable.shared
        guard codeTable.hasLoaded else { return cands } // 未装码表 → 退化为双拼

        let chars = Array(input)
        guard chars.count > 2 else { return cands }
        // 尝试把末 1~2 键作为形码，取能命中候选的组合
        for len in [1, 2] where chars.count - len >= 2 {
            let flypyLen = chars.count - len
            guard flypyLen.isMultiple(of: 2) else { continue }
            let flypyPart = String(chars[0..<flypyLen])
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
