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

    /// 双拼渐进式查询：消除双拼在「奇数键位」的断档。
    ///
    /// 为什么双拼比全拼更需要这个：双拼每字固定 2 键，用户打词时**必然**逐键经过奇数长度。
    /// 实测（修复前）：默认方案小鹤双拼下 wourfg 6 步有 5 步候选为空、nihc 4 步有 1 步为空，
    /// 表现为「打词过程中键盘几乎全程只剩字母」。默认方案断档 = 新用户开箱第一印象就是坏的。
    ///
    /// 策略（按质量降序）：
    ///   ① 双拼码前缀匹配：找以整串开头的更长双拼键（nih → nihc「你好」）
    ///      奇数位时末键是声母，前缀匹配天然能补齐它的韵母，这是双拼最合适的兜底。
    ///   ② 偶数前缀成词：取前 2⌊n/2⌋ 键（已完整的音节部分）查词（nih → ni「你」）
    ///   ③ decode 成全拼后走全拼渐进（借用全拼的音节切分能力）
    ///
    /// 顺序同全拼的教训：前缀匹配必须在「更短的已成词部分」之前，
    /// 否则长词会被短词/单字压掉（见 searchProgressive 注释里记录的回退事故）。
    func searchFlypyProgressive(_ input: String) -> [DictEntry] {
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

        // ① 双拼码前缀匹配（主力）
        var prefixHits: [(String, [Int32])] = []
        for (k, v) in byFlypy where k.count > norm.count && k.hasPrefix(norm) {
            prefixHits.append((k, v))
            if prefixHits.count >= 400 { break }
        }
        prefixHits.sort { $0.0.count < $1.0.count }
        var pidx: [Int32] = []
        for (_, v) in prefixHits.prefix(40) { pidx.append(contentsOf: v.prefix(2)) }
        push(resolve(pidx, limit: 30))

        // ② 偶数前缀（已完整音节部分）逐段回退
        if out.count < 25, norm.count >= 2 {
            var take = (norm.count / 2) * 2
            if take == norm.count { take -= 2 }   // 整串已在 searchFlypy 查过，跳过
            while take >= 2 {
                let key = String(norm.prefix(take))
                if let l = byFlypy[key] { push(resolve(l, limit: 15)) }
                if out.count >= 25 { break }
                take -= 2
            }
        }

        // ③ decode 成全拼后借用全拼渐进
        if out.isEmpty {
            let decoded = FlypyCodec.decode(norm).joined()
            push(searchProgressive(decoded))
        }

        return Array(out.prefix(50))
    }

    /// 综合查询（不含常用语）：优先全拼精确，其次简拼。
    /// scheme：全拼模式（.pinyin）用全拼/简拼；双拼/音形模式用双拼编码。
    /// 返回结果前面会带上用户词典的条目（学过的词优先）。
    // 默认参数必须跟随产品默认方案（InputScheme.default），不许写死 .pinyin。
    // 坑（已定性）：写死 .pinyin 时，调用方漏传 scheme 就静默按全拼查 —— 不报错、
    //   结果只是「候选不对」，极难定位。iOS 键盘硬编码 .pinyin 与此同源（见 7c49895）。
    func query(_ input: String, scheme: InputScheme = .default) -> [DictEntry] {
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

            // 全拼兼容：保留但**不首选**（用户明确要求）。
            // 场景：多年小鹤用户偶尔会下意识敲全拼（或拷贝全拼串），
            //   此时宁可给个傅下，也不能让它抢双拼的首选 —— 双拼用户盲打，
            //   首选被全拼结果顶掉会直接上错字。
            // 做法：双拼结果在前，全拼结果去重后追加在后。
            let plainPinyin = pinyinFallbackEntries(input)

            // 整句切分（多字连打）：用户一口气打一句时，
            // 整串查词典必然未命中（词典里没有「我是中国」这个词），
            // 靠切分拼接。它自带长度/奇偶守卫，不适用时返回空。
            let sentence = segmentSentence(input, scheme: scheme)

            if user.isEmpty && fp.isEmpty {
                let decoded = FlypyCodec.decode(input).joined()
                if let u = _userByPinyin[decoded] { return u + plainPinyin }
                let py = searchPinyin(decoded)
                if !py.isEmpty { return py + plainPinyin }

                // 整句切分成功时**直接返回**，不走渐进兜底。
                //
                // 性能理由（实测定位，不是猜）：渐进兜底内部是 **byFlypy 全表扫描**
                //   （`for (k,v) in byFlypy where k.hasPrefix(norm)`，十几万个键）。
                //   分段计时（20 键 = 10 字）：
                //     segmentSentence        0.011 ms
                //     searchFlypyProgressive 7.647 ms  ← 占 93%
                //   慢的不是新加的切分，是旧的性能债。此前没暴露是因为短输入
                //   前缀命中多、400 条上限能早退；长输入命中少 → 退不了 → 扫完全表。
                // 修法取舍：**不重构** searchFlypyProgressive（它功能正确，
                //   短输入断档全靠它，改它风险大于收益），只在不需要时不调它。
                //   切分不适用的输入（奇数长度 / 太短 / 超长）路径完全不变。
                // 切分成功时，先拿切分结果，但**必须保留短词候选** ——
                // 坑（实测被回归拦下）：初版直接 return dedupAppend(sentence, plainPinyin)，
                //   把其他候选全砍了 —— womfzd（6 键）只剩「我们在」一条，
                //   「我们」完全消失。用户正在打字中途时这是災难性的：
                //   他可能只想选「我们」然后接着打，结果选不到。
                // 修法：切分结果在前，但仍把渐进兜底追在后面。
                //   仅当切分覆盖的字数 ≥ 3 时才跳过兜底（长串才有性能问题，
                //   且长串下用户意图明确是整句）；短串仍走完整路径。
                if !sentence.isEmpty {
                    let sentenceChars = sentence[0].word.count
                    if sentenceChars >= 4 {
                        // 四字及以上：意图明确是整句，且此时兜底全表扫描最慢
                        return dedupAppend(sentence, plainPinyin)
                    }
                    // 三字以下：仍跑兜底，保证短词候选不丢
                    let prog = searchFlypyProgressive(input)
                    return dedupAppend(dedupAppend(sentence, plainPinyin), prog)
                }

                // 双拼同样需要渐进式兜底：双拼每字定长 2 键，用户必然经过奇数长度，
                // 此前无此回退 → 奇数位候选全空（实测 wourfg 6 步 5 空）。
                let prog = searchFlypyProgressive(input)
                // 顺序：全拼实词 **先于** 渐进兜底。
                // 理由（实测）：输入 zhongguo 时双拼强行解码为 zang/on/geng/shuo，
                //   渐进兜底产出 12 条生僻字（葬/脏/臧/賍… 均 s1249），
                //   全拼的「中国」若追在后面会被埋到第 13 位 —— 等于没保留。
                //   渐进兜底本质是「宁可给点东西也不要空」的低质量候选，
                //   而全拼命中是用户真实意图，质量高于前者 → 应排在其前。
                //   但仍在双拼精确命中（user/fp）之后 —— 双拼永远优先。
                return dedupAppend(plainPinyin, prog)
            }
            // 双拼精确命中：双拼结果在前，全拼去重后追加。
            // 但坑（实测）：输入 zhongguo（8 键）时 byFlypy 竟然命中 —— 它被当成
            //   4 个双拼音节 zang/on/geng/shuo，产出 12 条生僻字（均 s1249）。
            //   全拼的「中国」追在后面会被埋掉 → 等于没保留。
            // 判据：双拼结果若**全是单字**而全拼能出多字词，说明这串更像全拼，
            //   此时全拼的多字词应提到双拼单字之前（仍在 user 词典之后）。
            //   不直接比得分：得分由 Searcher 算，引擎层只能给顺序建议。
            let fpAllSingleChar = !fp.isEmpty && fp.allSatisfy { $0.word.count == 1 }
            let plainHasPhrase = plainPinyin.contains { $0.word.count > 1 }
            if fpAllSingleChar && plainHasPhrase {
                return dedupAppend(dedupAppend(user + plainPinyin, sentence), fp)
            }
            // 整句候选插在精确命中之后、全拼之前。
            // 理由：用户连打 wouivsgo 时，整串精确命中只能出「我是」（前缀），
            //   而整句「我是中国」才是用户真实意图 —— 但不能抢精确命中的首选，
            //   因为用户也可能真只想打「我是」然后继续打下一个词。
            //   放第二位：一眼能看到，按一下右箭头/数字 2 就能选。
            return dedupAppend(dedupAppend(user + fp, sentence), plainPinyin)
        }
    }

    /// 双拼模式下的「全拼兼容候选」：把输入当作全拼串查一次。
    /// 只在输入看起来**像全拼**时才查，避免无谓开销：
    ///   双拼码长必为偶数且通常 ≤4 键；长于 4 键的字母串大概率是全拼。
    /// 不做简拼（searchInitials）—— 双拼模式下简拼与双拼码冲突严重。
    private func pinyinFallbackEntries(_ input: String) -> [DictEntry] {
        let s = input.lowercased()
        guard s.count >= 4 else { return [] }   // 太短不像全拼，且易与双拼碰撞
        return searchPinyin(s)
    }

    /// 把补充候选去重后追加到主候选尾部（主候选顺序不变）。
    private func dedupAppend(_ primary: [DictEntry], _ extra: [DictEntry]) -> [DictEntry] {
        guard !extra.isEmpty else { return primary }
        var seen = Set(primary.map { $0.word })
        var out = primary
        for e in extra where !seen.contains(e.word) {
            out.append(e)
            seen.insert(e.word)
        }
        return out
    }
    // MARK: - 整句切分（多字连打）

    /// 把一长串双拼码切成若干个词，用动态规划取「整体最优」的一种切法。
    ///
    /// 为什么需要它（用户实测报「不能多字连打」）：
    ///   原实现只会「拿整串去查词典」，词典没这个组合就退化成最长前缀 ——
    ///   `wouivsgo`（我是中国）只出「我是」，后半截 `vsgo` **被静默丢弃**。
    ///   而用户的实际姿势是「一口气打一句、空格上屏」，这是所有成熟输入法的默认交互。
    ///
    /// 算法来源：McBopomofo 的 `walk()`（见 `.pi/plans/00-research.md` §7①）。
    ///   本质是 DAG 最短路径 —— 每个「切点」是图上一个节点，
    ///   每个「能查到的词」是一条带权边，求总权重最大的一条路径。
    ///
    /// 打分必须带**长词加权**（§7③），否则会退化成一串单字：
    ///   「我是中国」= 我是(2字) + 中国(2字)  ← 期望
    ///   若只按词频加总，四个高频单字的总分很容易超过两个双字词。
    ///   McBopomofo 用 `log10(2.7^(字数-1) × count / norm)`，
    ///   即每多一个字，分数乘 2.7 —— 这个系数直接沿用（它是被生产验证过的）。
    ///
    /// 复杂度：O(n × maxWordSyllables)，n = 音节数。
    ///   双拼每字定长 2 键，故 n = 键数 / 2；maxWordSyllables 设上限 6。
    ///   实测见 `bench_engine.sh` 的「整句切分」段。
    ///
    /// **它只在整串查不到时才被调用**（见 `query` 内注释）——
    /// 保证任何现在能打出来的输入，路径完全不变。
    func segmentSentence(_ input: String, scheme: InputScheme) -> [DictEntry] {
        let s = input.lowercased()
        // 双拼每字 2 键：奇数长度说明用户还在打一个字的中途，交给渐进兜底更合适
        guard s.count >= 4, s.count % 2 == 0, s.count <= Limits.maxSentenceKeys else { return [] }

        let n = s.count / 2                       // 音节数

        // best[i] = 覆盖前 i 个音节的最优解；从 i 出发向后尝试各种词长
        // score 用 Double 累加对数分，path 存 (词, 起点)
        var bestScore = [Double](repeating: -.infinity, count: n + 1)
        var bestFrom  = [Int](repeating: -1, count: n + 1)
        var bestWord  = [DictEntry?](repeating: nil, count: n + 1)
        bestScore[0] = 0

        // 性能：DP 内会对同一个 (i, len) 反复拼字符串并查词典。
        // 坑（实测被性能门禁拦下）：初版每次都 codes[i..<i+len].joined()，
        //   20 键（10 字）单次查询 **7.75ms**，超过 5ms 门禁 —— 用户会感到卡顿。
        //   原因不是 DP 本身（O(n×6) 很小），而是 60 次字符串构建 + 字典查询。
        // 修法：① 用累积前缀直接切片，避免 joined()；② 查询结果缓存。
        var lookupCache = [String: DictEntry?](minimumCapacity: n * Limits.maxWordSyllables)

        for i in 0..<n where bestScore[i] > -.infinity {
            // 从位置 i 开始，尝试取 len 个音节组成一个词
            for len in 1...min(Limits.maxWordSyllables, n - i) {
                // 直接在原串上切片（双拼每音节定长 2 键，下标可算），不做数组 joined
                let lo = s.index(s.startIndex, offsetBy: i * 2)
                let hi = s.index(lo, offsetBy: len * 2)
                let code = String(s[lo..<hi])
                let hit: DictEntry?
                if let c = lookupCache[code] {
                    hit = c
                } else {
                    hit = bestEntry(forFlypyCode: code)
                    lookupCache[code] = hit
                }
                guard let e = hit else { continue }
                // 打分模型：log10(词频) + 成词奖励 × (字数 - 1)
                //
                // 为什么不能只用 McBopomofo 的 log10(fscale^(字数-1) × freq)：
                //   实测证伪 —— 该式在本项目词库上**完全无效**。
                //   路径分是「相加」的，词数多的路径凭空多加一项 log10(freq)（约 5 分），
                //   而 fscale 加权项在总字数相同时两边贡献几乎一致，抵不掉这个偏差。
                //   实测：fscale 从 2.7 调到 1000，「我是中国」始终输给「我是中+过」
                //   （单字「中」27万、「过」11万，词频本身就极高）。
                //   → 这是「分数相加」的**结构性偏差**，不是参数问题，调参无解。
                //
                // 改用显式「成词奖励」：每多一个字加固定分，直接对抗切碎倾向。
                // 奖励值 8 由**真实词库上的 10 例 DP 全路径实测**定出，非估算：
                //   bonus=0/2 → 1/10 正确；4 → 3/10；5 → 5/10；6 → 8/10；**≥7 → 10/10**
                //   取 8（比临界值 7 留一档余量，避免词库更新后落回临界）。
                //   实测用例：我是中国 / 你好我们 / 知道我要 / 安全第一 / 今天天气 /
                //     工作顺利 / 中国人民 / 明天开会 / 我是学生 / 谢谢你
                //   复现脚本见 `bench_engine.sh` 的「整句切分」段。
                let charCount = e.word.count
                let weighted = log10(Double(max(e.freq, 1)))
                             + Limits.phraseBonus * Double(charCount - 1)
                let cand = bestScore[i] + weighted
                if cand > bestScore[i + len] {
                    bestScore[i + len] = cand
                    bestFrom[i + len]  = i
                    bestWord[i + len]  = e
                }
            }
        }

        // 未能完整覆盖 → 不返回半截结果（半截结果会误导用户以为打完了）
        guard bestScore[n] > -.infinity else { return [] }

        // 回溯路径拼成一个整句候选
        var parts: [DictEntry] = []
        var cur = n
        while cur > 0, let w = bestWord[cur] {
            parts.append(w)
            cur = bestFrom[cur]
        }
        guard cur == 0, !parts.isEmpty else { return [] }
        parts.reverse()

        // 单个词时不必走切分（整串查询已覆盖），避免产出重复候选
        guard parts.count >= 2 else { return [] }

        let sentence = parts.map { $0.word }.joined()
        let pinyin   = parts.map { $0.pinyin }.joined(separator: " ")
        // 整句候选的 freq 取各部分最小值 —— 它不是词典里的真实词，
        // 不应凭「拼接」获得高于其最弱环节的权重。
        let freq = parts.map { $0.freq }.min() ?? 1
        return [DictEntry(pinyin: pinyin, word: sentence, freq: freq)]
    }

    /// 取某个双拼码下词频最高的一条词典项（切分打分用）。
    private func bestEntry(forFlypyCode code: String) -> DictEntry? {
        if let u = _userByFlypy[code]?.first { return u }
        guard let list = byFlypy[code] else { return nil }
        return resolve(list, limit: 1).first
    }

    private enum Limits {
        /// 参与切分的最大键数。超过则不切分（防 O(n²) 在超长脏输入上卡顿）。
        /// 24 键 = 12 个字，远超正常一次连打的长度。
        static let maxSentenceKeys = 24
        /// 单个词最多几个音节（词典里 6 字以上的词极少，且都是成语/专名）。
        static let maxWordSyllables = 6
        /// 成词奖励：每多一个字加多少分。见 segmentSentence 内的实测记录。
        /// 改这个值必须重跑 bench_engine.sh 的整句切分段（8 例断言会拦住退化）。
        static let phraseBonus: Double = 8
    }

}
