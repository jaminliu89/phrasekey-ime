import Foundation

/// 常用语条目。字段与主流输入法常用语导出格式兼容（hotword 数组）：
///   {"hw_id": "毫秒时间戳", "text": "完整内容", "key": "简码"}
/// 这样可以直接导入其他输入法导出的 JSON/CSV。
struct Hotword: Codable, Identifiable, Equatable {
    var hw_id: String
    var text: String
    var key: String
    var id: String { hw_id }

    var initials: String { PinyinSyllable.initials(text) }
    var pinyin: String { PinyinSyllable.pinyin(text) }
    /// 文本拼音 → 小鹤双拼编码（如「你好」→ nihc）
    var flypy: String {
        FlypyCodec.encode(pinyin.split(separator: " ").map(String.init))
    }

    /// 是否为长文本（段落级模板）。长文本不参与候选栏匹配，
    /// 只在短语面板里可见，避免打字时误触长文章。
    /// 阈值 100 字：大概 2-3 句话以内算常用短语，超过算模板。
    var isLongText: Bool { text.count > 100 }
}

/// Phrase store: JSON persistence + CRUD + search + import.
/// Storage: ~/Library/Application Support/PhraseKey/hotwords.json
final class HotwordsStore {
    static let shared = HotwordsStore()

    private(set) var items: [Hotword] = []
    private let fileURL: URL

    private init() {
        // 键盘扩展：从 App Group 共享容器读宿主写入的常用语（只读，不写）。
        // 注：此处原先完全跳过文件访问，依据是"文件访问会被沙盒拦截造成 watchdog 杀进程"，
        // 该猜想已被对照实验证伪 —— 真因是 Info.plist 缺 PrimaryLanguage 导致扩展未被拉起。
        // App Group 容器已验证可用（设备端容器存在且被宿主写入过）。
        // 常用语是 PhraseKey 的核心卖点，键盘用不到等于产品没意义。
        if AppSettings.isKeyboardExtension {
            if let shared = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: HotwordsStore.appGroupID) {
                fileURL = shared
                    .appendingPathComponent("PhraseKey")
                    .appendingPathComponent("hotwords.json")
                load()
            } else {
                fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("hotwords.json")
                items = []
            }
            return
        }
        let folder = AppSettings.current.resolvedDataDir
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("hotwords.json")
        load()
    }

    /// App Group：宿主写、键盘扩展读。与 ios/*.entitlements 保持一致。
    static let appGroupID = "group.com.phrasekey.ime"

    // MARK: - Persistence

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let arr = try? JSONDecoder().decode([Hotword].self, from: data) else {
            items = []
            return
        }
        items = arr
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(items) else { return }
        // 必须先确保父目录存在：App Group 容器下的 PhraseKey/ 子目录不会自动创建，
        // 缺目录时 write 失败而 try? 会静默吞掉错误 → 表现为"常用语加不进去"。
        let dir = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[PhraseKey] 常用语写入失败 %@: %@", fileURL.path, String(describing: error))
        }
    }

    // MARK: - CRUD

    @discardableResult
    func add(text: String, key: String = "") -> Hotword {
        let hw = Hotword(hw_id: String(Int(Date().timeIntervalSince1970 * 1000)),
                         text: text, key: key)
        items.append(hw)
        save()
        return hw
    }

    func remove(id: String) {
        items.removeAll { $0.hw_id == id }
        save()
    }

    func update(id: String, text: String? = nil, key: String? = nil) {
        guard let idx = items.firstIndex(where: { $0.hw_id == id }) else { return }
        if let text { items[idx].text = text }
        if let key { items[idx].key = key }
        save()
    }

    // MARK: - 导入（兼容常见输入法导出格式）

    /// 从常见输入法导出的 CSV 导入（utf-8-sig，列：序号,hw_id,简码,内容）
    @discardableResult
    func importFromCSV(url: URL) -> Int {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        var count = 0
        for line in content.components(separatedBy: .newlines).dropFirst() {
            guard !line.isEmpty else { continue }
            let cols = line.components(separatedBy: ",")
            guard cols.count >= 2 else { continue }
            // CSV 可能被 Excel 拆分：取最后一段为内容更稳，简码在倒数第二
            let text = cols.last ?? ""
            let key = cols.count >= 3 ? cols[cols.count - 2] : ""
            add(text: text, key: key)
            count += 1
        }
        save()
        return count
    }

    /// 从常见输入法导出的 JSON 导入（[{hw_id,text,key},...]）
    @discardableResult
    func importFromJSON(url: URL) -> Int {
        guard let data = try? Data(contentsOf: url),
              let arr = try? JSONDecoder().decode([Hotword].self, from: data) else { return 0 }
        // 按 hw_id 去重后并入
        let existing = Set(items.map { $0.hw_id })
        var count = 0
        for hw in arr where !existing.contains(hw.hw_id) {
            items.append(hw)
            count += 1
        }
        save()
        return count
    }

    // MARK: - Search

    enum SearchType {
        case key        // 简码精确（用户打了某常用语完整 key）
        case keyPrefix  // 简码前缀（key 以输入开头，但不等于输入）
        case pinyin     // 完整拼音前缀匹配（5-12 字中长短语，更精准）
        case initials   // 拼音首字母（≤4 字短短语）
        case contains   // 文本子串
    }

    /// 综合搜索常用语：返回 (type, hotword)。
    /// scheme 决定文本匹配方式：
    ///   - 全拼：拼音首字母 + 子串
    ///   - 小鹤双拼/音形：双拼编码前缀（key 匹配始终优先）
    // 默认参数必须跟随产品默认方案（InputScheme.default），不许写死 .pinyin。
    // 坑（已定性）：写死 .pinyin 时，调用方漏传 scheme 就静默按全拼查 —— 不报错、
    //   结果只是「候选不对」，极难定位。iOS 键盘硬编码 .pinyin 与此同源（见 7c49895）。
    private enum Limits {
        /// 参与「拼音前缀匹配」的常用语最大文本长度（字数）。
        /// 超过此长度的常用语**只能用自定义简码触发** —— 见 search 内注释。
        /// 4 字：覆盖「你好/我们/收到/好的」这类短语，又挡住话术类长句。
        static let maxPinyinMatchChars = 4
        /// 参与「全拼前缀匹配」的常用语最大字数。
        /// 比首字母匹配更长的短语（4-12 字）用完整拼音前缀也能找到，
        /// 对齐微信输入法「前 N 字拼音联想」的体验。
        static let maxFullPinyinMatchChars = 12
    }

    func search(_ input: String, scheme: InputScheme = .default) -> [(SearchType, Hotword)] {
        let norm = input.lowercased()
        var out: [(SearchType, Hotword)] = []

        // 1. 简码精确匹配置顶（所有方案通用，key 就是用户自定义的形码）
        for hw in items where hw.key.lowercased() == norm {
            out.append((.key, hw))
        }
        // 2. 简码前缀
        for hw in items where !hw.key.isEmpty && hw.key.lowercased().hasPrefix(norm) && hw.key.lowercased() != norm {
            out.append((.keyPrefix, hw))
        }

        if scheme.isFlypy {
            // 3. 双拼编码前缀（短语，≤4 字）
            //
            // 坑（被回归拦下）：长文本常用语若也参与拼音前缀匹配，会**吃掉正常输入**。
            //   实例：种子里 kh2 →「我们开个会同步一下」，其文本双拼码以 womf 开头，
            //   于是打 womf 时首选变成整句，「我们」被挤掉 —— 用户日常打字直接被毁。
            //   越是有用的长话术，破坏力越大（前缀越长，覆盖的正常输入越多）。
            // 修法：只有**短文本**（≤ 4 字）才参与拼音前缀匹配。
            //   长文本本来就是靠自定义简码触发的（那才是它的设计用途），
            //   靠拼音打整句既不现实也无意义。
            for hw in items where hw.text.count <= Limits.maxPinyinMatchChars
                              && hw.flypy.hasPrefix(norm) {
                out.append((.initials, hw))
            }
            // 4. 双拼编码前缀（中长短语，5-12 字）
            // 对齐微信输入法「前 N 字拼音联想」：5-12 字的常用语，
            // 打前几个字的双拼编码也能联想出来。
            for hw in items where hw.text.count > Limits.maxPinyinMatchChars
                              && hw.text.count <= Limits.maxFullPinyinMatchChars
                              && hw.flypy.hasPrefix(norm) {
                out.append((.pinyin, hw))
            }
        } else {
            // 3. 文本拼音首字母（≤4字短语）
            for hw in items where hw.text.count <= Limits.maxPinyinMatchChars
                              && hw.initials.hasPrefix(norm) {
                out.append((.initials, hw))
            }
            // 4. 全拼前缀（中长短语，5-12 字）
            // 对齐微信输入法「前 N 字拼音联想」
            for hw in items where hw.text.count > Limits.maxPinyinMatchChars
                              && hw.text.count <= Limits.maxFullPinyinMatchChars
                              && hw.pinyin.replacingOccurrences(of: " ", with: "").hasPrefix(norm) {
                out.append((.pinyin, hw))
            }
            // 5. 文本子串（兜底）—— 需 ≥2 字符，避免单字母命中一大堆
            for hw in items where norm.count >= 2
                              && hw.text.localizedCaseInsensitiveContains(norm) {
                out.append((.contains, hw))
            }
        }
        // 去重
        var seen = Set<String>()
        return out.filter { seen.insert($0.1.hw_id).inserted }
    }
}
