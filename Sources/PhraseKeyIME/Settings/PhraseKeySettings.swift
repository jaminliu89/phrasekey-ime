import Foundation

/// PhraseKey 设置（开放格式 config.json，可随数据目录跨端同步）。
/// 存储：<数据目录>/config.json
/// 数据目录默认 ~/Library/Application Support/PhraseKey，
/// 可设置为 iCloud Drive / 云盘 / git 目录 → 多端数据自动同步。
struct PhraseKeySettings: Codable {
    var scheme: InputScheme = .flypy
    /// 数据目录绝对路径；空字符串 = 默认目录
    var dataDir: String = ""
    /// 是否启用剪贴板历史（规划中，字段预留）
    var clipboardHistory: Bool = false

    // MARK: - 目录

    /// 默认数据目录：~/Library/Application Support/PhraseKey（macOS）
    /// iOS 端启动时用 overrideDefaultDir 指向 App Group 容器，实现多端同数据
    static var overrideDefaultDir: URL?
    static var defaultDir: URL {
        if let d = overrideDefaultDir { return d }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PhraseKey", isDirectory: true)
    }

    /// 解析后的数据目录（用户设置优先）
    var resolvedDataDir: URL {
        if !dataDir.isEmpty {
            let expanded = (dataDir as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
        return Self.defaultDir
    }

    // MARK: - 存取

    static func load() -> PhraseKeySettings {
        let url = defaultDir.appendingPathComponent("config.json")
        if let data = try? Data(contentsOf: url),
           let s = try? JSONDecoder().decode(PhraseKeySettings.self, from: data) {
            return s
        }
        return PhraseKeySettings()
    }

    func save() {
        let dir = resolvedDataDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("config.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(self) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

/// 当前设置（单例，IMK 进程内共享）
final class AppSettings {
    static var current = PhraseKeySettings.load()
    static func save() { current.save() }
}
