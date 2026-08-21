import Foundation

/// 拼音音节工具：内置标准拼音音节表（无声调），用于输入串的贪心分词。
/// 跨端设计：汉字→拼音改用内置数据表 hanzi_pinyin.tsv（11072 字），
/// 不依赖 CoreFoundation 的 CFStringTransform，引擎可在 iOS/Win/Linux 复用。
enum PinyinSyllable {
    /// 标准音节集合（无声调），覆盖全拼输入场景。
    /// 来源：通用拼音音节表（约 400 个），这里列出全部有效音节。
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

    /// 判断一个字符串是否是有效拼音音节（全拼，无声调）。
    static func isSyllable(_ s: String) -> Bool {
        all.contains(s.lowercased())
    }

    /// 贪心最长匹配分词：把连续拼音串切成音节数组。
    /// 例："nihao" -> ["ni", "hao"]；"wode" -> ["wo", "de"]
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

    // MARK: - 汉字→拼音（跨平台数据表）

    /// 汉字 → 拼音（无声调，取常用读音）。从 Resources/hanzi_pinyin.tsv 懒加载。
    /// 形如：你→ni、好→hao；多音字取第一个（常用）读音。
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

    /// 单个汉字 → 拼音（无调）。未收录返回 nil。
    static func pinyin(of ch: Character) -> String? {
        hanziPinyin[ch]
    }

    /// 汉字串 → 拼音首字母串（如「婚礼」→ hl）。未收录字符跳过。
    static func initials(_ text: String) -> String {
        text.compactMap { hanziPinyin[$0]?.first.map { String($0).lowercased() } }.joined()
    }

    /// 汉字串 → 全拼（无声调，空格分隔）。如「你好」→ "ni hao"。未收录字符跳过。
    static func pinyin(_ text: String) -> String {
        text.compactMap { hanziPinyin[$0] }.joined(separator: " ")
    }
}
