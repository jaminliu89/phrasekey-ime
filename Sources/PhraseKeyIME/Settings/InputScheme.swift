import Foundation

/// 输入方案（跨端：数据格式开放，各端共享同一套方案枚举）
enum InputScheme: String, CaseIterable, Codable {
    case pinyin = "全拼"
    case flypy = "小鹤双拼"
    case flypyXing = "小鹤音形"

    /// 默认方案
    static let `default` = InputScheme.flypy

    var isFlypy: Bool { self == .flypy || self == .flypyXing }
}
