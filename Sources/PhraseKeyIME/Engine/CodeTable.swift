import Foundation

/// Xiaohe Xingma (shape code) table: `hanzi → shape code (first+last stroke)`.
/// Loads external xingma.tsv (format: `char\tcode`, can hold full Xiaohe Xingma table).
/// Without a code table, Xingma mode gracefully degrades to Shuangpin (no input loss).
final class CodeTable {
    static let shared = CodeTable()

    private var table: [Character: String] = [:]
    private(set) var hasLoaded = false

    private init() {
        load()
    }

    private func load() {
        // 键盘扩展受限沙盒：跳过外部码表（AppSettings.current 触发 FileManager 查询被拦截阻塞）。
        // 未装码表 → hasLoaded=false → 音形模式退化为双拼（无输入丢失）。
        guard !AppSettings.isKeyboardExtension else { return }
        let urls: [URL?] = [
            AppSettings.current.resolvedDataDir.appendingPathComponent("xingma.tsv"),
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

    /// Shape code for a single character (nil if not in table)
    func code(of ch: Character) -> String? {
        table[ch]
    }

    /// Check if a word/char matches the shape-code prefix (first char priority; word checks first char's code)
    func matches(word: String, xingPrefix: String) -> Bool {
        guard let first = word.first, let code = table[first] else { return false }
        return code.hasPrefix(xingPrefix)
    }
}
