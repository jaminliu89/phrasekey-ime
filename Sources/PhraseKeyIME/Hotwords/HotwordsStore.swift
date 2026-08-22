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
        if let data = try? encoder.encode(items) {
            try? data.write(to: fileURL, options: .atomic)
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
        case key      // 简码精确（用户打了某常用语 key）
        case initials // 文本拼音首字母
        case contains // 文本子串
    }

    /// 综合搜索常用语：返回 (type, hotword)。
    /// scheme 决定文本匹配方式：
    ///   - 全拼：拼音首字母 + 子串
    ///   - 小鹤双拼/音形：双拼编码前缀（key 匹配始终优先）
    func search(_ input: String, scheme: InputScheme = .pinyin) -> [(SearchType, Hotword)] {
        let norm = input.lowercased()
        var out: [(SearchType, Hotword)] = []

        // 1. 简码精确匹配置顶（所有方案通用，key 就是用户自定义的形码）
        for hw in items where hw.key.lowercased() == norm {
            out.append((.key, hw))
        }
        // 2. 简码前缀
        for hw in items where !hw.key.isEmpty && hw.key.lowercased().hasPrefix(norm) && hw.key.lowercased() != norm {
            out.append((.key, hw))
        }

        if scheme.isFlypy {
            // 3. 双拼编码前缀（如输入 nihc 命中「你好」开头）
            for hw in items where hw.flypy.hasPrefix(norm) {
                out.append((.initials, hw))
            }
        } else {
            // 3. 文本拼音首字母
            for hw in items where hw.initials.hasPrefix(norm) {
                out.append((.initials, hw))
            }
            // 4. 文本子串（兜底）
            for hw in items where hw.text.localizedCaseInsensitiveContains(norm) {
                out.append((.contains, hw))
            }
        }
        // 去重
        var seen = Set<String>()
        return out.filter { seen.insert($0.1.hw_id).inserted }
    }
}
