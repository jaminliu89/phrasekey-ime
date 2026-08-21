import Foundation

/// 小鹤音形码表：`汉字 → 形码（首形+末形）`。
/// 加载外部码表文件 xingma.tsv（格式：`字\t形码`，可放完整小鹤音形码表）。
/// 未装码表时音形模式退化为小鹤双拼（不丢失输入能力）。
final class CodeTable {
    static let shared = CodeTable()

    private var table: [Character: String] = [:]
    private(set) var hasLoaded = false

    private init() {
        load()
    }

    private func load() {
        let urls: [URL?] = [
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("PhraseKey/xingma.tsv"),
            Bundle.main.url(forResource: "xingma", withExtension: "tsv"),
        ]
        for url in urls {
            guard let url, let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in content.components(separatedBy: .newlines) {
                let parts = line.components(separatedBy: "\t")
                guard parts.count >= 2, let ch = parts[0].first else { continue }
                let code = parts[1].trimmingCharacters(in: .whitespaces)
                if !code.isEmpty { table[ch] = code }
            }
            if !table.isEmpty { break }
        }
        hasLoaded = !table.isEmpty
    }

    /// 单字形码（未收录返回 nil）
    func code(of ch: Character) -> String? {
        table[ch]
    }

    /// 词/字是否匹配形码前缀（逐字比较，第一字优先；词按首字形码前缀过滤）
    func matches(word: String, xingPrefix: String) -> Bool {
        guard let first = word.first, let code = table[first] else { return false }
        return code.hasPrefix(xingPrefix)
    }
}
