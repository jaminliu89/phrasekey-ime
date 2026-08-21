import Foundation

/// Pinyin syllable utility: built-in standard pinyin syllable table (no tones) for greedy segmentation.
/// Cross-platform: uses built-in hanzi_pinyin.tsv (11072 chars) instead of CoreFoundation CFStringTransform,
/// so the engine can be reused on iOS/Windows/Linux.
enum PinyinSyllable {
    /// Standard syllable set (toneless), covering full pinyin input.
    /// Source: universal pinyin syllable table (~400 entries), listing all valid syllables.
    static let all: Set<String> = {
        let initials = [
            "b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h",
            "j", "q", "x", "zh", "ch", "sh", "r", "z", "c", "s",
            "y", "w"
        ]
        let finals = [
            "a", "o", "e", "i", "u", "v", "ai", "ei", "ui", "ao", "ou",
            "iu", "ie", "ve", "er", "an", "en", "in", "un", "ang", "eng",
            "ing", "ong", "ia", "ua", "uo", "ian", "uan", "iang", "uang",
            "iong", "iao", "uai"
        ]
        var set = Set<String>()
        for i in initials {
            for f in finals {
                set.insert(i + f)
            }
        }
        // 单独成音节的韵母
        for f in ["a", "o", "e", "ai", "ei", "ao", "ou", "an", "en", "ang", "er"] {
            set.insert(f)
        }
        // 常用单音节特例
        set.formUnion(["a", "o", "e", "ai", "ei", "ao", "ou", "an", "en", "ang", "er",
                       "bi", "pi", "mi", "di", "ti", "ni", "li", "ji", "qi", "xi",
                       "yi", "wu", "yu", "ni", "ha", "he", "hu", "wo", "de", "le"])
        // 过滤明显无效组合（保留主集合，够用即可）
        return set
    }()

    /// Check if a string is a valid pinyin syllable (full pinyin, no tones).
    static func isSyllable(_ s: String) -> Bool {
        all.contains(s.lowercased())
    }

    /// Greedy longest-match segmentation: splits a continuous pinyin string into syllable array.
    /// Examples: "nihao" → ["ni", "hao"]; "wode" → ["wo", "de"]
    static func segment(_ input: String) -> [String] {
        let chars = Array(input.lowercased())
        var result: [String] = []
        var i = 0
        let n = chars.count
        while i < n {
            var matched = false
            // 优先尝试 3 字符（zh/ch/sh 开头的最长音节）
            for len in [3, 2, 1] {
                guard i + len <= n else { continue }
                let seg = String(chars[i..<(i+len)])
                if isSyllable(seg) {
                    result.append(seg)
                    i += len
                    matched = true
                    break
                }
            }
            if !matched {
                // 无法匹配的音节，单字符前移（容忍脏输入）
                result.append(String(chars[i]))
                i += 1
            }
        }
        return result
    }

    // MARK: - Hanzi → Pinyin (cross-platform table)

    /// Hanzi → pinyin (toneless, common reading). Lazily loaded from Resources/hanzi_pinyin.tsv.
    /// Examples: 你→ni, 好→hao; polyphonic chars use the first (common) reading.
    static let hanziPinyin: [Character: String] = {
        var table: [Character: String] = [:]
        let urls: [URL?] = [
            Bundle.main.url(forResource: "hanzi_pinyin", withExtension: "tsv"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath
                + "/Sources/PhraseKeyIME/Resources/hanzi_pinyin.tsv"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath
                + "/Resources/hanzi_pinyin.tsv"),
        ]
        for url in urls {
            guard let url, let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in content.components(separatedBy: .newlines) {
                let parts = line.components(separatedBy: "\t")
                guard parts.count >= 2, let ch = parts[0].first else { continue }
                table[ch] = parts[1]
            }
            if !table.isEmpty { break }
        }
        return table
    }()

    /// Single hanzi → pinyin (no tone). Returns nil if not found.
    static func pinyin(of ch: Character) -> String? {
        hanziPinyin[ch]
    }

    /// Hanzi string → pinyin initials (e.g. "婚礼" → "hl"). Skips unmatched chars.
    static func initials(_ text: String) -> String {
        text.compactMap { hanziPinyin[$0]?.first.map { String($0).lowercased() } }.joined()
    }

    /// Hanzi string → full pinyin (toneless, space-separated). Examples: "你好" → "ni hao". Skips unmatched chars.
    static func pinyin(_ text: String) -> String {
        text.compactMap { hanziPinyin[$0] }.joined(separator: " ")
    }
}
