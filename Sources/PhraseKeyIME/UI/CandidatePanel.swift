import Cocoa

/// Google Gboard theme colors.
enum GBoardTheme {
    // Light mode
    static let bgLight        = NSColor(calibratedRed: 1.00, green: 1.00, blue: 1.00, alpha: 1.00)   // #FFFFFF
    static let highlightBgLight = NSColor(calibratedRed: 0.91, green: 0.94, blue: 0.99, alpha: 1.00) // #E8F0FE
    static let accentLight    = NSColor(calibratedRed: 0.26, green: 0.52, blue: 0.96, alpha: 1.00)   // #4285F4
    static let textLight      = NSColor(calibratedWhite: 0.10, alpha: 1.00)
    static let subLight       = NSColor(calibratedWhite: 0.45, alpha: 1.00)

    // Dark mode
    static let bgDark         = NSColor(calibratedRed: 0.17, green: 0.17, blue: 0.18, alpha: 1.00)   // #2C2C2E
    static let highlightBgDark = NSColor(calibratedRed: 0.24, green: 0.25, blue: 0.27, alpha: 1.00)  // #3C4043
    static let accentDark     = NSColor(calibratedRed: 0.54, green: 0.71, blue: 0.97, alpha: 1.00)   // #8AB4F8
    static let textDark       = NSColor(calibratedWhite: 0.92, alpha: 1.00)
    static let subDark        = NSColor(calibratedWhite: 0.60, alpha: 1.00)

    static var isDark: Bool {
        // 坑（已定性）：原用 NSApp.effectiveAppearance 判深色 —— 但输入法是**独立后台进程**，
        //   它的 NSApp 外观与用户当前前台 app 无关，也不一定跟随系统设置，
        //   常被判为 aqua（浅色）→ 深色背景配深色字，候选条文字看不见。
        // 改用系统级偏好（AppleInterfaceStyle），这是全局值，不依赖本进程外观。
        if let style = UserDefaults.standard.string(forKey: "AppleInterfaceStyle"),
           style.lowercased().contains("dark") {
            return true
        }
        return false
    }
    static var bg: NSColor { isDark ? bgDark : bgLight }
    static var highlightBg: NSColor { isDark ? highlightBgDark : highlightBgLight }
    static var accent: NSColor { isDark ? accentDark : accentLight }
    static var text: NSColor { isDark ? textDark : textLight }
    static var sub: NSColor { isDark ? subDark : subLight }
}

/// Candidate bar content view: self-drawn Google Gboard style (rounded cards + highlight + index + type badge).
final class CandidateBarView: NSView {
    var candidates: [(text: String, type: String)] = []
    var selectedIndex = 0

    static let cellHeight: CGFloat = 36
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
    private(set) var canPageUp = false
    private(set) var canPageDown = false

    func configure(candidates: [(String, String)], selected: Int) {
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
        frame = NSRect(x: 0, y: 0, width: Self.width(for: self.candidates), height: Self.cellHeight)
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

    static func width(for cands: [(String, String)]) -> CGFloat {
        guard !cands.isEmpty else { return 60 }
        var w: CGFloat = 16
        for c in cands.prefix(maxVisible) {
            let attr = [NSAttributedString.Key.font: NSFont.systemFont(ofSize: 16, weight: .medium)]
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
        GBoardTheme.bg.setFill()
        bg.fill()
        // Thin border（深色下用白边，否则黑边在深色背景上看不见）
        if GBoardTheme.isDark {
            NSColor.white.withAlphaComponent(0.12).setStroke()
        } else {
            NSColor.black.withAlphaComponent(0.08).setStroke()
        }
        bg.lineWidth = 1
        bg.stroke()

        // Draw each candidate
        var x: CGFloat = 8
        let y: CGFloat = 0
        let h = Self.cellHeight
        let font = NSFont.systemFont(ofSize: 16, weight: .medium)
        let subFont = NSFont.systemFont(ofSize: 9, weight: .semibold)

        for (i, c) in candidates.enumerated() {
            let textW = (c.text as NSString).size(withAttributes: [.font: font]).width
            let cellW = min(textW + Self.cellPaddingX * 2, Self.cellMaxWidth)
            let cellRect = NSRect(x: x, y: y + 4, width: cellW, height: h - 8)

            if i == selectedIndex {
                let hl = NSBezierPath(roundedRect: cellRect, xRadius: 8, yRadius: 8)
                GBoardTheme.highlightBg.setFill()
                hl.fill()
            }

            // Index (Google blue when selected)
            let numColor = i == selectedIndex ? GBoardTheme.accent : GBoardTheme.sub
            let numStr = NSAttributedString(string: "\(i + 1)",
                                            attributes: [.font: subFont, .foregroundColor: numColor])
            numStr.draw(at: NSPoint(x: x + 5, y: y + (h - 10) / 2))

            // Text (accent color when selected, Gboard style)
            let color = i == selectedIndex ? GBoardTheme.accent : GBoardTheme.text
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
                                                  attributes: [.font: subFont, .foregroundColor: GBoardTheme.sub])
                badgeStr.draw(at: NSPoint(x: x + cellW - 14, y: y + (h - 12) / 2))
            }

            x += cellW
        }

        drawPager(x: x, height: h)
    }

    /// 右侧翻页指示 ▲▼（学鼠须管 SquirrelView 的 upPath/downPath）。
    /// 可用时用 accent 色，不可用时不画 —— 用户一眼知道能不能翻。
    private func drawPager(x: CGFloat, height h: CGFloat) {
        guard canPageUp || canPageDown else { return }
        let cx = min(x + 8, bounds.maxX - 10)
        let font = NSFont.systemFont(ofSize: 8, weight: .bold)
        if canPageUp {
            let s = NSAttributedString(string: "▲",
                attributes: [.font: font, .foregroundColor: GBoardTheme.accent])
            s.draw(at: NSPoint(x: cx, y: h / 2 + 1))
        }
        if canPageDown {
            let s = NSAttributedString(string: "▼",
                attributes: [.font: font, .foregroundColor: GBoardTheme.accent])
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
    func update(candidates: [(String, String)], selected: Int, at screenPoint: NSPoint) {
        guard !candidates.isEmpty else { hide(); return }
        barView.configure(candidates: candidates, selected: selected)
        let w = barView.frame.width
        let h = CandidateBarView.cellHeight
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
