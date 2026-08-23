import Cocoa
import InputMethodKit

/// PhraseKey 输入法控制器：拼音输入状态机 + 常用语优先候选。
///
/// 交互设计（对齐 Google 输入法候选体验）：
///  - 字母输入 → 累积拼音，弹候选条
///  - 数字 1-9 → 选候选并上屏
///  - 空格 → 上屏第一个候选（常用语一键出）
///  - 退格 → 删拼音；回车 → 上屏拼音原文
///  - 常用语条目带 ⌘ 角标，命中简码时直接置顶
final class PhraseKeyController: IMKInputController {

    private var composing = ""
    private var candidates: [Searcher.Candidate] = []
    private var selected = 0
    private let panel = CandidatePanel()

    // MARK: - Init

    override init!(server: IMKServer!, delegate: Any!, client: Any!) {
        super.init(server: server, delegate: delegate, client: client)
    }

    // MARK: - Key Handler

    override func handle(_ event: NSEvent!, client: Any!) -> Bool {
        guard event.type == .keyDown else { return false }
        guard let textInput = client as? IMKTextInput else { return false }

        // 系统级快捷键（Cmd 等）放行，避免拦截 cmd+space 切换
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        guard mods.isEmpty else { return false }

        guard let chars = event.charactersIgnoringModifiers, chars.count >= 1 else { return false }

        if composing.isEmpty {
            // ---- 空闲状态 ----
            if isPinyinInput(chars) {
                composing = chars.lowercased()
                refresh()
                return true
            }
            return false // 非拼音输入，交给系统（英文/其他输入法语义）
        }

        // ---- 输入中 ----
        // 先处理功能键（方向键/Esc 等无可打印字符，要看 keyCode）
        switch event.keyCode {
        case 53:                  // Esc：取消当前输入（不上屏）
            reset()
            return true
        case 123:                 // ← 上一个候选
            if !candidates.isEmpty {
                selected = selected > 0 ? selected - 1 : candidates.count - 1
                refreshPanelOnly()
            }
            return true
        case 124:                 // → 下一个候选
            if !candidates.isEmpty {
                selected = (selected + 1) % candidates.count
                refreshPanelOnly()
            }
            return true
        case 126:                 // ↑ 上翻一页
            if !candidates.isEmpty {
                selected = max(0, selected - CandidateBarView.maxVisible)
                refreshPanelOnly()
            }
            return true
        case 125:                 // ↓ 下翻一页
            if !candidates.isEmpty {
                selected = min(candidates.count - 1, selected + CandidateBarView.maxVisible)
                refreshPanelOnly()
            }
            return true
        default:
            break
        }

        switch chars {
        case " ":                 // 空格：上屏首选
            commitSelected(textInput)
            return true
        case "\u{7F}":            // 退格
            composing.removeLast()
            refresh()
            return true
        case "\r":                // 回车：上屏拼音原文（不转中文）
            textInput.insertText(composing, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            reset()
            return true
        case "-", "[":            // 上翻页（常见输入法习惯）
            if !candidates.isEmpty {
                selected = max(0, selected - CandidateBarView.maxVisible)
                refreshPanelOnly()
            }
            return true
        case "=", "]":            // 下翻页
            if !candidates.isEmpty {
                selected = min(candidates.count - 1, selected + CandidateBarView.maxVisible)
                refreshPanelOnly()
            }
            return true
        case ";":                 // 双拼分号选词：选第 2 个候选
            if AppSettings.current.scheme.isFlypy && candidates.count >= 2 {
                commitCandidate(at: 1, textInput)
                return true
            }
            // 非双拼或候选不足 → 先提交拼音再放行标点
            if !composing.isEmpty {
                textInput.insertText(composing, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                reset()
            }
            return false
        case "'":                 // 撇号：双拼选第 3 个 / 音节分隔符 / 直接上屏
            if AppSettings.current.scheme.isFlypy && candidates.count >= 3 {
                commitCandidate(at: 2, textInput)
                return true
            }
            // 作为音节分隔符：计入拼音串（Searcher 层会剥离，但拼音栏显示用户按了）
            // 仅在已有输入时当分隔符；空串时直接上屏撇号
            if !composing.isEmpty {
                composing += "'"
                refresh()
                return true
            }
            return false // 空输入时放行给系统（英文上下文打 don't 等）
        default:
            if let n = Int(chars), (1...9).contains(n) {
                // 数字键选词必须基于**当前可视窗口**，而非全局下标。
                // 否则翻页后按 1 选到的还是第一页的第一个。
                let idx = panel.windowStart + (n - 1)
                if idx < candidates.count {
                    commitCandidate(at: idx, textInput)
                    return true
                }
            }
            if isPinyinInput(chars) {
                composing += chars.lowercased()
                refresh()
                return true
            }
            // 其他字符（标点等）：先提交拼音串，再放行给系统
            if !composing.isEmpty {
                textInput.insertText(composing, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                reset()
            }
            return false
        }
    }

    // MARK: - Candidates & Commit

    /// 只刷面板选中态，不重查词库（方向键/翻页用）。
    /// 否则每次按方向键都重新 search，既浪费也会把 selected 重置成 0。
    private func refreshPanelOnly() {
        guard !candidates.isEmpty else { return }
        let list = candidates.map { ($0.text, $0.type) }
        panel.update(candidates: list, selected: selected, at: insertionPoint(), preedit: composing)
    }

    private func refresh() {
        candidates = Searcher.shared.search(composing, scheme: AppSettings.current.scheme)
        selected = 0
        if candidates.isEmpty {
            panel.hide()
            return
        }
        let list = candidates.map { ($0.text, $0.type) }
        panel.update(candidates: list, selected: 0, at: insertionPoint(), preedit: composing)
    }

    private func commitSelected(_ client: IMKTextInput) {
        guard !candidates.isEmpty else {
            // 无候选：上屏拼音原文
            client.insertText(composing, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            reset()
            return
        }
        commitCandidate(at: selected, client)
    }

    private func commitCandidate(at index: Int, _ client: IMKTextInput) {
        guard index < candidates.count else { return }
        let c = candidates[index]
        client.insertText(c.text, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        // 自学习：词库候选上屏后记录，下次位置靠前
        if c.type == "word", !c.pinyin.isEmpty {
            PinyinEngine.shared.learn(word: c.text, pinyin: c.pinyin)
        }
        reset()
    }

    /// 把第 index 个候选存为常用语（不提交上屏）。
    /// 自动生成简码 = 拼音首字母（与输入串相同则取前 4 位作 key）
    @objc func saveAsPhrase(_ sender: Any?) {
        // sender 可能是 NSMenuItem，tag 存候选 index
        guard let item = sender as? NSMenuItem else { return }
        let idx = item.tag
        guard idx >= 0, idx < candidates.count else { return }
        let c = candidates[idx]
        // 自动生成简码：有 key 的保留，没有的用拼音首字母前 4 位
        let autoKey = c.hotword?.key ?? String(PinyinSyllable.initials(c.text).prefix(4))
        HotwordsStore.shared.add(text: c.text, key: autoKey)
        // 存完继续显示候选，不打断输入
        refresh()
    }

    private func reset() {
        composing = ""
        candidates = []
        selected = 0
        panel.hide()
    }

    // MARK: - Cursor

    /// 取输入光标锚点：直接用鼠标位置（最可靠，接近光标）；极端情况退回屏幕底部中央。
    private func insertionPoint() -> NSPoint {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.main, screen.visibleFrame.contains(mouse) {
            return mouse
        }
        if let screen = NSScreen.main {
            return NSPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.minY + 80)
        }
        return mouse
    }

    // MARK: - Utilities

    private func isPinyinInput(_ s: String) -> Bool {
        guard let scalar = s.unicodeScalars.first else { return false }
        return CharacterSet.lowercaseLetters.contains(scalar)
    }

    // MARK: - Menu (right-click / menu bar)

    override func menu() -> NSMenu! {
        let m = NSMenu(title: "PhraseKey")
        let about = NSMenuItem(title: "PhraseKey Settings…", action: #selector(openSettings), keyEquivalent: "")
        about.target = self
        m.addItem(about)
        let importItem = NSMenuItem(title: "导入常用语…", action: #selector(importHotwords), keyEquivalent: "")
        importItem.target = self
        m.addItem(importItem)
        return m
    }

    @objc private func openSettings() {
        SettingsWindowController.show()
    }

    @objc private func importHotwords() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .commaSeparatedText]
        panel.message = "选择从其他输入法导出的常用语文件（CSV/JSON）"
        if panel.runModal() == .OK, let url = panel.url {
            let imported: Int
            if url.pathExtension.lowercased() == "json" {
                imported = HotwordsStore.shared.importFromJSON(url: url)
            } else {
                imported = HotwordsStore.shared.importFromCSV(url: url)
            }
            let alert = NSAlert()
            alert.messageText = "导入完成"
            alert.informativeText = "已导入 \(imported) 条常用语。"
            alert.runModal()
        }
    }
}
