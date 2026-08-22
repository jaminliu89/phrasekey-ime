import Foundation

/// Pinyin syllable utility: built-in standard pinyin syllable table (no tones) for greedy segmentation.
/// Cross-platform: uses built-in hanzi_pinyin.tsv (11072 chars) instead of CoreFoundation CFStringTransform,
/// so the engine can be reused on iOS/Windows/Linux.
enum PinyinSyllable {
    /// Standard Mandarin syllable set (toneless), 417 entries.
    /// Derived from the full CJK-Unified-Ideographs reading table (pypinyin), so it contains
    /// exactly the syllables that really occur — no Cartesian-product garbage like "fai"/"ruang".
    static let all: Set<String> = [
        "a", "ai", "an", "ang", "ao", "ba", "bai", "ban", "bang", "bao", "bei", "ben", "beng",
        "bi", "bian", "biao", "bie", "bin", "bing", "bo", "bu", "ca", "cai", "can", "cang",
        "cao", "ce", "cei", "cen", "ceng", "cha", "chai", "chan", "chang", "chao", "che",
        "chen", "cheng", "chi", "chong", "chou", "chu", "chua", "chuai", "chuan", "chuang",
        "chui", "chun", "chuo", "ci", "cong", "cou", "cu", "cuan", "cui", "cun", "cuo", "da",
        "dai", "dan", "dang", "dao", "de", "den", "deng", "di", "dia", "dian", "diao", "die",
        "ding", "diu", "dong", "dou", "du", "duan", "dui", "dun", "duo", "e", "ei", "en", "eng",
        "er", "fa", "fan", "fang", "fei", "fen", "feng", "fiao", "fo", "fou", "fu", "ga", "gai",
        "gan", "gang", "gao", "ge", "gei", "gen", "geng", "gong", "gou", "gu", "gua", "guai",
        "guan", "guang", "gui", "gun", "guo", "ha", "hai", "han", "hang", "hao", "he", "hei",
        "hen", "heng", "hm", "hong", "hou", "hu", "hua", "huai", "huan", "huang", "hui", "hun",
        "huo", "ji", "jia", "jian", "jiang", "jiao", "jie", "jin", "jing", "jiong", "jiu", "ju",
        "juan", "jue", "jun", "ka", "kai", "kan", "kang", "kao", "ke", "kei", "ken", "keng",
        "kong", "kou", "ku", "kua", "kuai", "kuan", "kuang", "kui", "kun", "kuo", "la", "lai",
        "lan", "lang", "lao", "le", "lei", "leng", "li", "lia", "lian", "liang", "liao", "lie",
        "lin", "ling", "liu", "lo", "long", "lou", "lu", "luan", "lun", "luo", "lv", "lve", "m",
        "ma", "mai", "man", "mang", "mao", "me", "mei", "men", "meng", "mi", "mian", "miao",
        "mie", "min", "ming", "miu", "mo", "mou", "mu", "n", "na", "nai", "nan", "nang", "nao",
        "ne", "nei", "nen", "neng", "ni", "nia", "nian", "niang", "niao", "nie", "nin", "ning",
        "niu", "nong", "nou", "nu", "nuan", "nun", "nuo", "nv", "nve", "o", "ou", "pa", "pai",
        "pan", "pang", "pao", "pei", "pen", "peng", "pi", "pian", "piao", "pie", "pin", "ping",
        "po", "pou", "pu", "qi", "qia", "qian", "qiang", "qiao", "qie", "qin", "qing", "qiong",
        "qiu", "qu", "quan", "que", "qun", "ran", "rang", "rao", "re", "ren", "reng", "ri",
        "rong", "rou", "ru", "rua", "ruan", "rui", "run", "ruo", "sa", "sai", "san", "sang",
        "sao", "se", "sen", "seng", "sha", "shai", "shan", "shang", "shao", "she", "shei",
        "shen", "sheng", "shi", "shou", "shu", "shua", "shuai", "shuan", "shuang", "shui",
        "shun", "shuo", "si", "song", "sou", "su", "suan", "sui", "sun", "suo", "ta", "tai",
        "tan", "tang", "tao", "te", "tei", "teng", "ti", "tian", "tiao", "tie", "ting", "tong",
        "tou", "tu", "tuan", "tui", "tun", "tuo", "wa", "wai", "wan", "wang", "wei", "wen",
        "weng", "wo", "wu", "xi", "xia", "xian", "xiang", "xiao", "xie", "xin", "xing", "xiong",
        "xiu", "xu", "xuan", "xue", "xun", "ya", "yan", "yang", "yao", "ye", "yi", "yin",
        "ying", "yo", "yong", "you", "yu", "yuan", "yue", "yun", "za", "zai", "zan", "zang",
        "zao", "ze", "zei", "zen", "zeng", "zha", "zhai", "zhan", "zhang", "zhao", "zhe",
        "zhei", "zhen", "zheng", "zhi", "zhong", "zhou", "zhu", "zhua", "zhuai", "zhuan",
        "zhuang", "zhui", "zhun", "zhuo", "zi", "zong", "zou", "zu", "zuan", "zui", "zun",
        "zuo"
    ]

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
            // 最长优先匹配（最长合法音节为 6 字符，如 chuang/zhuang）
            for len in [6, 5, 4, 3, 2, 1] {
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
