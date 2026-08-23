import Foundation

/// 移动端输入引擎封装：复用桌面端 Searcher/FlypyCodec/HotwordsStore。
/// 无 AppKit 依赖，纯 Foundation，可在 iOS 键盘扩展内运行。
final class MobileEngine {
    let scheme: InputScheme
    private(set) var composing = ""
    private(set) var candidates: [Searcher.Candidate] = []

    init(scheme: InputScheme) {
        self.scheme = scheme
    }

    /// 输入一个字符（字母/数字/符号）
    func append(_ ch: Character) {
        composing += String(ch)
        refresh()
    }

    func deleteLast() {
        if !composing.isEmpty {
            composing.removeLast()
            refresh()
        }
    }

    /// 空格：首选上屏（有候选）或插入空格
    /// 常用语精确匹配时自动展开全文（可配置，默认开）
    func space() -> String {
        // 自动展开：精确匹配常用语 key → 直接上屏全文
        let settings = PhraseKeySettings.load()
        if settings.autoExpandHotwords,
           let hw = Searcher.shared.findExactHotword(composing, scheme: scheme) {
            reset()
            return hw.text
        }
        if !candidates.isEmpty {
            return commit(at: 0) ?? " "
        }
        return " "
    }

    /// 提交第 index 个候选（不重置时返回文本）
    func commit(at index: Int) -> String? {
        guard candidates.indices.contains(index) else { return nil }
        let c = candidates[index]
        // 自学习：词库候选记录到用户词典
        if c.type == "word", !c.pinyin.isEmpty {
            PinyinEngine.shared.learn(word: c.text, pinyin: c.pinyin)
        }
        reset()
        return c.text
    }

    /// 回车/原样上屏拼音串
    func commitRaw() -> String {
        let s = composing.isEmpty ? "" : composing
        reset()
        return s
    }

    func reset() {
        composing = ""
        candidates = []
    }

    private func refresh() {
        candidates = Searcher.shared.search(composing, scheme: scheme)
    }
}
