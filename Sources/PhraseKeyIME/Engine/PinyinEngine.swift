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
    private var userEntries: [DictEntry] = []  // 用户词典（自学习 + 手动添加）
    private var byInitials: [String: [Int32]] = [:]     // 简拼索引（存 entries 下标）
    private var byPinyin: [String: [Int32]] = [:]       // 全拼索引（去掉空格，存下标）
    private var byFlypy: [String: [Int32]] = [:]        // 小鹤双拼索引（存下标）

    private let userDictQueue = DispatchQueue(label: "com.phrasekey.userdict")
    private var userDictDirty = false
    private var saveWorkItem: DispatchWorkItem?

    private init() {
        loadBuiltinDict()
        loadUserDict()
        loadExternalDictIfAny()
        buildIndex()
    }

    // MARK: - Dictionary Loading

    /// Built-in dict: format `pinyin\tword\tfrequency`
    /// 资源名优先级：dict_mobile（iOS 键盘扩展的 3 万条精简版）→ dict（桌面 20 万条）。
    /// 键盘扩展内存预算约 30-60MB，存在 dict_mobile 时必须优先用它。
    private func loadBuiltinDict() {
        let candidates = ["dict_mobile", "dict"]
        for name in candidates {
            if let url = Bundle.main.url(forResource: name, withExtension: "tsv"),
               let content = try? String(contentsOf: url, encoding: .utf8) {
                parseDict(content)
                return
            }
        }
        // 调试/命令行环境下 bundle 拿不到资源时，尝试工作目录旁路
        let alt = FileManager.default.currentDirectoryPath + "/Sources/PhraseKeyIME/Resources/dict.tsv"
        if let c = try? String(contentsOfFile: alt, encoding: .utf8) {
            parseDict(c)
        }
    }

    /// External user dict (optional): <dataDir>/user_dict.tsv
    /// Users can add full custom dictionaries. Syncs via shared data directory.
    private func loadExternalDictIfAny() {
        // 键盘扩展受限沙盒：访问 AppSettings.current 会触发 FileManager 查询宿主目录，
        // 被拦截阻塞 → watchdog 杀进程 → 键盘"能弹但不持久"的真凶。外部用户词典仅宿主/桌面端用。
        guard !AppSettings.isKeyboardExtension else { return }
        let url = AppSettings.current.resolvedDataDir.appendingPathComponent("user_dict.tsv")
        if let c = try? String(contentsOf: url, encoding: .utf8) {
            parseDict(c)
        }
    }

    // MARK: - 用户词典（自学习）

    /// 用户词典路径：<dataDir>/learned_dict.tsv
    /// 与 user_dict.tsv 分开 — learned 是自学习产物，user_dict.tsv 是手动维护的外部词库
    private var userDictURL: URL? {
        guard !AppSettings.isKeyboardExtension else { return nil }
        return AppSettings.current.resolvedDataDir.appendingPathComponent("learned_dict.tsv")
    }

    private func loadUserDict() {
        guard let url = userDictURL,
              let c = try? String(contentsOf: url, encoding: .utf8) else { return }
        for line in c.components(separatedBy: .newlines) {
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 2 else { continue }
            let pinyin = parts[0].trimmingCharacters(in: .whitespaces)
            let word = parts[1].trimmingCharacters(in: .whitespaces)
            guard !pinyin.isEmpty, !word.isEmpty else { continue }
            let freq = parts.count > 2 ? (Int(parts[2].trimmingCharacters(in: .whitespaces)) ?? 1) : 1
            userEntries.append(DictEntry(pinyin: pinyin, word: word, freq: freq))
        }
    }

    private func saveUserDict() {
        guard let url = userDictURL else { return }
        userDictQueue.async { [weak self] in
            guard let self else { return }
            let lines = self.userEntries
                .sorted { $0.freq > $1.freq }
                .map { "\($0.pinyin)\t\($0.word)\t\($0.freq)" }
                .joined(separator: "\n")
            try? lines.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// 记录一次选词（自学习入口）。
    /// - word: 上屏的词
    /// - pinyin: 该词的拼音（空格分隔）
    /// 词频 +1；新词从 1 开始。内存索引实时更新，磁盘异步 debounce 写。
    func learn(word: String, pinyin: String) {
        guard !AppSettings.isKeyboardExtension else { return }
        let normPinyin = pinyin.trimmingCharacters(in: .whitespaces)
        guard !normPinyin.isEmpty, !word.isEmpty else { return }

        if let idx = userEntries.firstIndex(where: { $0.word == word && $0.pinyin == normPinyin }) {
            userEntries[idx] = DictEntry(pinyin: normPinyin, word: word, freq: userEntries[idx].freq + 1)
        } else {
            userEntries.append(DictEntry(pinyin: normPinyin, word: word, freq: 1))
        }

        // 更新索引（用户词典量小，全量重建代价可接受）
        rebuildUserDictIndex()

        // debounce 写盘（3 秒内多次学习合并一次）
        userDictDirty = true
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.userDictDirty else { return }
            self.saveUserDict()
            self.userDictDirty = false
        }
        saveWorkItem = item
        userDictQueue.asyncAfter(deadline: .now() + 3.0, execute: item)
    }

    private func rebuildUserDictIndex() {
        // 用户词典单独索引，查询时与内置词典合并 + 加权
        var userByPinyin: [String: [DictEntry]] = [:]
        var userByInitials: [String: [DictEntry]] = [:]
        var userByFlypy: [String: [DictEntry]] = [:]

        for e in userEntries {
            userByPinyin[e.pinyin.replacingOccurrences(of: " ", with: ""), default: []].append(e)
            userByInitials[e.initials, default: []].append(e)
            let syls = e.pinyin.split(separator: " ").map(String.init)
            let flypy = FlypyCodec.encode(syls)
            if !flypy.isEmpty {
                userByFlypy[flypy, default: []].append(e)
            }
        }

        // 用户词典权重 = freq * 1000，确保自学习的词排在前面
        for k in userByPinyin.keys { userByPinyin[k]?.sort { $0.freq > $1.freq } }
        for k in userByInitials.keys { userByInitials[k]?.sort { $0.freq > $1.freq } }
        for k in userByFlypy.keys { userByFlypy[k]?.sort { $0.freq > $1.freq } }

        // 合并到主索引：用户词典条目插在前面（通过高 freq 实现排序优势）
        // 但主索引 entries 不直接改，而是在 query 时拼接 — 更干净
        _userByPinyin = userByPinyin
        _userByInitials = userByInitials
        _userByFlypy = userByFlypy
    }

    private var _userByPinyin: [String: [DictEntry]] = [:]
    private var _userByInitials: [String: [DictEntry]] = [:]
    private var _userByFlypy: [String: [DictEntry]] = [:]

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

    /// 索引只存 entries 的下标（Int32），不存 DictEntry 副本。
    /// 原实现三份索引各持一份结构体副本，20 万词条会膨胀到 ~110MB，
    /// 远超 iOS 键盘扩展的内存预算；改存下标后三份索引只占 4 字节/条。
    private func buildIndex() {
        for (i, e) in entries.enumerated() {
            let idx = Int32(i)
            byPinyin[e.pinyin.replacingOccurrences(of: " ", with: ""), default: []].append(idx)
            byInitials[e.initials, default: []].append(idx)
            // 小鹤双拼编码：全拼音节 → 双拼串
            let syls = e.pinyin.split(separator: " ").map(String.init)
            let flypy = FlypyCodec.encode(syls)
            if !flypy.isEmpty {
                byFlypy[flypy, default: []].append(idx)
            }
        }
        // 排序：词频高优先（比较时回表取 freq）
        let byFreq: (Int32, Int32) -> Bool = { [entries] a, b in
            entries[Int(a)].freq > entries[Int(b)].freq
        }
        for k in byPinyin.keys { byPinyin[k]?.sort(by: byFreq) }
        for k in byInitials.keys { byInitials[k]?.sort(by: byFreq) }
        for k in byFlypy.keys { byFlypy[k]?.sort(by: byFreq) }
    }

    /// 下标列表 → 词条列表（取前 limit 条）
    private func resolve(_ idxs: [Int32], limit: Int = 50) -> [DictEntry] {
        idxs.prefix(limit).map { entries[Int($0)] }
    }

    // MARK: - Diagnostics

    /// 已加载词条数（内置 + 外部 + 自学习）。基准/诊断用。
    var entryCount: Int { entries.count + userEntries.count }

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
        return resolve(list)
    }

    /// 简拼查询：输入首字母串 → 词（多音字简拼命中后按词频排）
    func searchInitials(_ input: String) -> [DictEntry] {
        let norm = input.lowercased()
        guard let list = byInitials[norm] else { return [] }
        return resolve(list)
    }

    /// 小鹤双拼查询：输入双拼串 → 词（由词库条目的双拼编码精确匹配）
    func searchFlypy(_ input: String) -> [DictEntry] {
        let norm = input.lowercased()
        guard let list = byFlypy[norm] else { return [] }
        return resolve(list)
    }

    /// 渐进式查询：输入尚不构成完整词时的兜底，保证任何长度都有候选。
    ///
    /// 策略（按质量降序）：
    ///   ① 音节切分后，用「已完整的前缀音节」查词（niha → ni + ha，取 ni 的词）
    ///   ② 整串当拼音前缀，扫描索引找以它开头的键（覆盖 niha → nihao）
    ///   ③ 首字母串当简拼
    /// 目的：消除"打到第三个字候选就空"的断档。
    func searchProgressive(_ input: String) -> [DictEntry] {
        let norm = input.lowercased().replacingOccurrences(of: " ", with: "")
        guard !norm.isEmpty else { return [] }
        var out: [DictEntry] = []
        var seen = Set<String>()

        func push(_ list: [DictEntry]) {
            for e in list where !seen.contains(e.word) {
                seen.insert(e.word)
                out.append(e)
                if out.count >= 60 { return }
            }
        }

        // ① 前缀匹配优先：以整串开头的更长词才是用户想打的
        //    （zhongguoren 尚未成词时，应先给「中国人」而不是单字「钟」）
        //    按键长度升序 = 与输入最接近的词优先。
        var prefixHits: [(String, [Int32])] = []
        for (k, v) in byPinyin where k.count > norm.count && k.hasPrefix(norm) {
            prefixHits.append((k, v))
            if prefixHits.count >= 400 { break }
        }
        prefixHits.sort { $0.0.count < $1.0.count }
        var pidx: [Int32] = []
        for (_, v) in prefixHits.prefix(40) { pidx.append(contentsOf: v.prefix(2)) }
        push(resolve(pidx, limit: 30))

        // ② 音节切分兜底：前缀无命中时，用已完整音节的最长前缀组合查词。
        //    注意顺序：必须放在前缀匹配「之后」。曾把它插到最前，
        //    结果 zhongguoren 的「中国人民解放军」被单字「忠」压掉，已回退。
        let segs = PinyinSyllable.segment(norm)
        if out.count < 25, segs.count > 1 {
            for take in stride(from: segs.count - 1, through: 1, by: -1) {
                let key = segs.prefix(take).joined()
                if let l = byPinyin[key] { push(resolve(l, limit: 15)) }
                if out.count >= 25 { break }
            }
        }

        // ③ 简拼兜底
        if out.isEmpty, let l = byInitials[norm] { push(resolve(l, limit: 20)) }

        return Array(out.prefix(50))
    }

    /// 综合查询（不含常用语）：优先全拼精确，其次简拼。
    /// scheme：全拼模式（.pinyin）用全拼/简拼；双拼/音形模式用双拼编码。
    /// 返回结果前面会带上用户词典的条目（学过的词优先）。
    func query(_ input: String, scheme: InputScheme = .pinyin) -> [DictEntry] {
        switch scheme {
        case .pinyin:
            let user = _userByPinyin[input.lowercased()] ?? []
            let py = searchPinyin(input)
            if user.isEmpty && py.isEmpty {
                let ini = _userByInitials[input.lowercased()] ?? searchInitials(input)
                if !ini.isEmpty { return ini }
                // 三级回退：字典是精确匹配，输入到「不完整音节组合」时（如 niha）
                // 键不存在 → 候选全空 → 键盘只剩字母。真实输入法必须能在半途给出候选。
                return searchProgressive(input)
            }
            return user + py
        case .flypy, .flypyXing:
            let user = _userByFlypy[input.lowercased()] ?? []
            let fp = searchFlypy(input)
            if user.isEmpty && fp.isEmpty {
                let decoded = FlypyCodec.decode(input).joined()
                return _userByPinyin[decoded] ?? searchPinyin(decoded)
            }
            return user + fp
        }
    }
}
