import Foundation

/// Dictionary entry
struct DictEntry {
    let pinyin: String   // 全拼（无调，空格分隔，如 "ni hao"）
    let word: String     // 词
    let freq: Int        // 词频
    var initials: String { pinyin.split(separator: " ").map { String($0.first!) }.joined() }
}

/// Pinyin engine: loads dictionary, provides full pinyin / initials / shuangpin queries.
final class PinyinEngine {
    static let shared = PinyinEngine()

    private var entries: [DictEntry] = []
    private var byInitials: [String: [DictEntry]] = [:]     // 简拼索引
    private var byPinyin: [String: [DictEntry]] = [:]       // 全拼索引（去掉空格）
    private var byFlypy: [String: [DictEntry]] = [:]        // 小鹤双拼索引

    private init() {
        loadBuiltinDict()
        loadExternalDictIfAny()
        buildIndex()
    }

    // MARK: - Dictionary Loading

    /// Built-in dict (Resources/dict.tsv): format `pinyin\tword\tfrequency`
    private func loadBuiltinDict() {
        guard let url = Bundle.main.url(forResource: "dict", withExtension: "tsv"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            // 调试/命令行环境下 bundle 拿不到资源时，尝试工作目录旁路
            let alt = FileManager.default.currentDirectoryPath + "/Sources/PhraseKeyIME/Resources/dict.tsv"
            if let c = try? String(contentsOfFile: alt, encoding: .utf8) {
                parseDict(c)
            }
            return
        }
        parseDict(content)
    }

    /// External user dict (optional): <dataDir>/user_dict.tsv
    /// Users can add full custom dictionaries. Syncs via shared data directory.
    private func loadExternalDictIfAny() {
        let url = AppSettings.current.resolvedDataDir.appendingPathComponent("user_dict.tsv")
        if let c = try? String(contentsOf: url, encoding: .utf8) {
            parseDict(c)
        }
    }

    private func parseDict(_ content: String) {
        for line in content.components(separatedBy: .newlines) {
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 2 else { continue }
            let pinyin = parts[0].trimmingCharacters(in: .whitespaces)
            let word = parts[1].trimmingCharacters(in: .whitespaces)
            guard !pinyin.isEmpty, !word.isEmpty else { continue }
            let freq = parts.count > 2 ? (Int(parts[2].trimmingCharacters(in: .whitespaces)) ?? 0) : 0
            entries.append(DictEntry(pinyin: pinyin, word: word, freq: freq))
        }
    }

    private func buildIndex() {
        for e in entries {
            byPinyin[e.pinyin.replacingOccurrences(of: " ", with: ""), default: []].append(e)
            byInitials[e.initials, default: []].append(e)
            // 小鹤双拼编码：全拼音节 → 双拼串
            let syls = e.pinyin.split(separator: " ").map(String.init)
            let flypy = FlypyCodec.encode(syls)
            if !flypy.isEmpty {
                byFlypy[flypy, default: []].append(e)
            }
        }
        // 排序：词频高优先
        for k in byPinyin.keys { byPinyin[k]?.sort { $0.freq > $1.freq } }
        for k in byInitials.keys { byInitials[k]?.sort { $0.freq > $1.freq } }
        for k in byFlypy.keys { byFlypy[k]?.sort { $0.freq > $1.freq } }
    }

    // MARK: - Query

    struct Result {
        let text: String
        let type: String   // "word" | "hotword"
        let score: Int
    }

    /// 全拼查询：输入拼音串（无调）→ 词
    func searchPinyin(_ input: String) -> [DictEntry] {
        let norm = input.lowercased().replacingOccurrences(of: " ", with: "")
        guard let list = byPinyin[norm] else { return [] }
        return Array(list.prefix(50))
    }

    /// 简拼查询：输入首字母串 → 词（多音字简拼命中后按词频排）
    func searchInitials(_ input: String) -> [DictEntry] {
        let norm = input.lowercased()
        guard let list = byInitials[norm] else { return [] }
        return Array(list.prefix(50))
    }

    /// 小鹤双拼查询：输入双拼串 → 词（由词库条目的双拼编码精确匹配）
    func searchFlypy(_ input: String) -> [DictEntry] {
        let norm = input.lowercased()
        guard let list = byFlypy[norm] else { return [] }
        return Array(list.prefix(50))
    }

    /// 综合查询（不含常用语）：优先全拼精确，其次简拼。
    /// scheme：全拼模式（.pinyin）用全拼/简拼；双拼/音形模式用双拼编码。
    func query(_ input: String, scheme: InputScheme = .pinyin) -> [DictEntry] {
        switch scheme {
        case .pinyin:
            let py = searchPinyin(input)
            return py.isEmpty ? searchInitials(input) : py
        case .flypy, .flypyXing:
            let fp = searchFlypy(input)
            return fp.isEmpty ? searchPinyin(FlypyCodec.decode(input).joined()) : fp
        }
    }
}
