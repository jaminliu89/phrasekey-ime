import Cocoa

/// 灰度字重主题体系（Parchment 风格）。
/// 设计原则：只用灰度 + 字重做层次，不用彩色做装饰。
/// 选中态靠浅灰背景 + 字重区分，一目了然。
enum PhraseKeyTheme {
    // Light mode
    static let bgLight           = NSColor(calibratedWhite: 1.00, alpha: 1.00)  // #FFFFFF
    static let highlightBgLight  = NSColor(calibratedWhite: 0.94, alpha: 1.00)  // #EFEFEF 选中背景
    static let textLight         = NSColor(calibratedWhite: 0.10, alpha: 1.00)  // 正文
    static let textSelectedLight = NSColor(calibratedWhite: 0.10, alpha: 1.00)  // 选中同色，靠字重
    static let subLight          = NSColor(calibratedWhite: 0.55, alpha: 1.00)  // 次要文字（序号、标记、拼音串）
    static let subSelectedLight  = NSColor(calibratedWhite: 0.35, alpha: 1.00)  // 选中时次要文字加重
    static let borderLight       = NSColor(calibratedWhite: 0.88, alpha: 1.00)  // 边框

    // Dark mode
    static let bgDark            = NSColor(calibratedWhite: 0.17, alpha: 1.00)  // #2C2C2E
    static let highlightBgDark   = NSColor(calibratedWhite: 0.28, alpha: 1.00)  // 选中背景
    static let textDark          = NSColor(calibratedWhite: 0.92, alpha: 1.00)  // 正文
    static let textSelectedDark  = NSColor(calibratedWhite: 0.92, alpha: 1.00)
    static let subDark           = NSColor(calibratedWhite: 0.55, alpha: 1.00)  // 次要
    static let subSelectedDark   = NSColor(calibratedWhite: 0.75, alpha: 1.00)
    static let borderDark        = NSColor(calibratedWhite: 0.30, alpha: 1.00)

    /// 系统深色判定（输入法进程独立，不能信 NSApp.effectiveAppearance）
    static var isDark: Bool {
        if let style = UserDefaults.standard.string(forKey: "AppleInterfaceStyle"),
           style.lowercased().contains("dark") {
            return true
        }
        return false
    }

    static var bg: NSColor { isDark ? bgDark : bgLight }
    static var highlightBg: NSColor { isDark ? highlightBgDark : highlightBgLight }
    static var text: NSColor { isDark ? textDark : textLight }
    static var textSelected: NSColor { isDark ? textSelectedDark : textSelectedLight }
    static var sub: NSColor { isDark ? subDark : subLight }
    static var subSelected: NSColor { isDark ? subSelectedDark : subSelectedLight }
    static var border: NSColor { isDark ? borderDark : borderLight }

    // 字重体系：选中靠字重区分，不靠颜色
    enum Weight {
        static let text = NSFont.Weight.regular
        static let textSelected = NSFont.Weight.medium
        static let sub = NSFont.Weight.semibold  // 小字号需要更粗才能看清
    }
}

/// Candidate bar content view: self-drawn Google Gboard style (rounded cards + highlight + index + type badge).
final class CandidateBarView: NSView {
    var candidates: [(text: String, type: String)] = []
    var selectedIndex = 0

    static let cellHeight: CGFloat = 36
    /// 预编辑区高度（仅在有拼音串时占位）
    static let preeditHeight: CGFloat = 20
    static let cellPaddingX: CGFloat = 14
    static let cellMaxWidth: CGFloat = 200    // 单个候选最大宽度，长文本截断
    static let cornerRadius: CGFloat = 12
    static let maxVisible = 10
    /// 右侧翻页指示区宽度
    static let pagerWidth: CGFloat = 18

    /// 当前可视窗口的起始下标（全局候选列表中），给序号显示用。
    private(set) var windowStart = 0
    /// 是否还有上一页/下一页。学鼠须管 SquirrelView.canPageUp/canPageDown。
    /// 缺它的后果：候选超过 10 个时用户不知道还有，等于翻页功能不可发现。
    /// 预编辑区：当前已输入的拼音串（学鼠须管 SquirrelView.preeditRange）。
    /// 缺它的后果：用户打字时面板上看不到自己输了什么，
    /// 双拼尤其致命 —— 打错一个字母整个音节就变了，没有回显无法自查。
    var preedit = ""
    private(set) var canPageUp = false
    private(set) var canPageDown = false

    func configure(candidates: [(String, String)], selected: Int, preedit: String = "") {
        self.preedit = preedit
        // 坑（已定性）：原为 `prefix(maxVisible)` 硬截前 10 个 —— 翻页后
        //   第 11 个以后的候选**永远画不出来**，等于翻页功能形同虚设。
        // 改为按 selected 滑动窗口：选中项总在可视范围内。
        let total = candidates.count
        let sel = min(max(0, selected), max(0, total - 1))
        var start = (sel / Self.maxVisible) * Self.maxVisible
        if start >= total { start = max(0, total - Self.maxVisible) }
        let end = min(total, start + Self.maxVisible)
        self.windowStart = start
        self.canPageUp = start > 0
        self.canPageDown = end < total
        self.candidates = start < end ? Array(candidates[start..<end]) : []
        self.selectedIndex = sel - start
        needsDisplay = true
        frame = NSRect(x: 0, y: 0, width: Self.width(for: self.candidates), height: Self.totalHeight(preedit: preedit))
    }

    /// 长文本截断显示（末尾加 …）
    private func truncated(_ text: String, font: NSFont, maxWidth: CGFloat) -> String {
        let ellipsis = "…"
        let attr = [NSAttributedString.Key.font: font]
        let ellipsisW = (ellipsis as NSString).size(withAttributes: attr).width
        var result = ""
        for ch in text {
            let test = result + String(ch)
            let w = (test as NSString).size(withAttributes: attr).width
            if w + ellipsisW > maxWidth { break }
            result = test
        }
        return result + ellipsis
    }

    /// 面板总高 = 候选行 + （有拼音串时）预编辑行
    static func totalHeight(preedit: String) -> CGFloat {
        preedit.isEmpty ? cellHeight : cellHeight + preeditHeight
    }

    static func width(for cands: [(String, String)]) -> CGFloat {
        guard !cands.isEmpty else { return 60 }
        var w: CGFloat = 16
        for c in cands.prefix(maxVisible) {
            let attr = [NSAttributedString.Key.font: NSFont.systemFont(ofSize: 16, weight: .regular)]
            w += (c.0 as NSString).size(withAttributes: attr).width + Self.cellPaddingX * 2 + 6
        }
        // 给翻页箭头留出宽度（画在最右侧）
        w += Self.pagerWidth
        return min(w, 720)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !candidates.isEmpty else { return }
        // Rounded card background
        let bg = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                              xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
        PhraseKeyTheme.bg.setFill()
        bg.fill()
        // Thin border
        PhraseKeyTheme.border.setStroke()
        bg.lineWidth = 1
        bg.stroke()

        drawPreedit()

        // Draw each candidate
        var x: CGFloat = 8
        let y: CGFloat = 0
        let h = Self.cellHeight
        let textFont = NSFont.systemFont(ofSize: 16, weight: PhraseKeyTheme.Weight.text)
        let textSelectedFont = NSFont.systemFont(ofSize: 16, weight: PhraseKeyTheme.Weight.textSelected)
        let subFont = NSFont.systemFont(ofSize: 9, weight: PhraseKeyTheme.Weight.sub)

        for (i, c) in candidates.enumerated() {
            let isSel = i == selectedIndex
            let font = isSel ? textSelectedFont : textFont
            let textW = (c.text as NSString).size(withAttributes: [.font: font]).width
            let cellW = min(textW + Self.cellPaddingX * 2, Self.cellMaxWidth)
            let cellRect = NSRect(x: x, y: y + 4, width: cellW, height: h - 8)

            if isSel {
                let hl = NSBezierPath(roundedRect: cellRect, xRadius: 8, yRadius: 8)
                PhraseKeyTheme.highlightBg.setFill()
                hl.fill()
            }

            // Index（选中时字重加重，颜色用 subSelected）
            let numColor = isSel ? PhraseKeyTheme.subSelected : PhraseKeyTheme.sub
            let numStr = NSAttributedString(string: "\(i + 1)",
                                            attributes: [.font: subFont, .foregroundColor: numColor])
            numStr.draw(at: NSPoint(x: x + 5, y: y + (h - 10) / 2))

            // Text（选中态靠字重 + 背景区分，颜色同正文）
            let color = isSel ? PhraseKeyTheme.textSelected : PhraseKeyTheme.text
            let displayText = textW > (Self.cellMaxWidth - Self.cellPaddingX * 2)
                ? truncated(c.text, font: font, maxWidth: Self.cellMaxWidth - Self.cellPaddingX * 2 - 4)
                : c.text
            let str = NSAttributedString(string: displayText,
                                         attributes: [.font: font, .foregroundColor: color])
            str.draw(at: NSPoint(x: x + 16, y: y + (h - 20) / 2))

            // Type badge: ⌘ for hotword (phrase items)
            if c.type == "hotword" {
                let badge = "⌘"
                let badgeStr = NSAttributedString(string: badge,
                                                  attributes: [.font: subFont, .foregroundColor: PhraseKeyTheme.sub])
                badgeStr.draw(at: NSPoint(x: x + cellW - 14, y: y + (h - 12) / 2))
            }

            x += cellW
        }

        drawPager(x: x, height: h)
    }

    /// 预编辑区：面板顶部回显已输入的拼音串（学鼠须管 preeditRange）。
    /// 双拼用户尤其需要 —— 打错一个字母整个音节就变了，
    /// 没有回显根本没法自查是手误还是词库没词。
    private func drawPreedit() {
        guard !preedit.isEmpty else { return }
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let s = NSAttributedString(string: preedit,
            attributes: [.font: font, .foregroundColor: PhraseKeyTheme.sub])
        s.draw(at: NSPoint(x: 12, y: bounds.maxY - Self.preeditHeight + 4))

        let line = NSBezierPath()
        let ly = bounds.maxY - Self.preeditHeight
        line.move(to: NSPoint(x: 8, y: ly))
        line.line(to: NSPoint(x: bounds.maxX - 8, y: ly))
        PhraseKeyTheme.border.setStroke()
        line.lineWidth = 1
        line.stroke()
    }

    /// 右侧翻页指示 ▲▼（学鼠须管 SquirrelView 的 upPath/downPath）。
    /// 用 sub 色，不可用时不画 —— 用户一眼知道能不能翻。
    private func drawPager(x: CGFloat, height h: CGFloat) {
        guard canPageUp || canPageDown else { return }
        let cx = min(x + 8, bounds.maxX - 10)
        let font = NSFont.systemFont(ofSize: 8, weight: .bold)
        if canPageUp {
            let s = NSAttributedString(string: "▲",
                attributes: [.font: font, .foregroundColor: PhraseKeyTheme.sub])
            s.draw(at: NSPoint(x: cx, y: h / 2 + 1))
        }
        if canPageDown {
            let s = NSAttributedString(string: "▼",
                attributes: [.font: font, .foregroundColor: PhraseKeyTheme.sub])
            s.draw(at: NSPoint(x: cx, y: h / 2 - 9))
        }
    }
}


/// Candidate window: borderless floating NSPanel, follows input cursor.
final class CandidatePanel: NSPanel {
    private let barView = CandidateBarView()

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 200, height: CandidateBarView.cellHeight),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        contentView = barView
    }

    /// 当前可视窗口起始下标（透传 barView，供数字键选词换算全局下标）。
    var windowStart: Int { barView.windowStart }

    /// Update and show candidates.
    func update(candidates: [(String, String)], selected: Int, at screenPoint: NSPoint, preedit: String = "") {
        guard !candidates.isEmpty else { hide(); return }
        barView.configure(candidates: candidates, selected: selected, preedit: preedit)
        let w = barView.frame.width
        let h = CandidateBarView.totalHeight(preedit: preedit)
        // Position: default below cursor, move up if off-screen
        var origin = NSPoint(x: screenPoint.x, y: screenPoint.y - h - 6)
        if let screen = NSScreen.main {
            if origin.x + w > screen.visibleFrame.maxX { origin.x = screen.visibleFrame.maxX - w - 8 }
            if origin.y < screen.visibleFrame.minY { origin.y = screenPoint.y + 8 }
        }
        setFrame(NSRect(origin: origin, size: NSSize(width: w, height: h)), display: true)
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
    }
}
