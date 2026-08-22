import UIKit

/// iOS 键盘扩展主控制器。
///
/// 布局铁律（经对照实验确认）：
/// **全程使用 Auto Layout / UIStackView，禁止手动 frame 布局。**
/// 键盘扩展内 `view.bounds` 在 viewDidLoad 阶段为 0，`UIScreen.main` 也不代表键盘尺寸；
/// 依赖它们做 frame 计算会得到错乱布局，系统判定键盘无效 → 惩罚性停止加载
/// （表现："偶尔能弹、活不久"）。空壳对照组 BareKB 全程用约束，可长期存活。
///
/// 存活铁律：viewDidLoad 必须同步建完整个可交互 UI，词库异步补。
final class KeyboardViewController: UIInputViewController {

    // MARK: - 状态

    private var engine: MobileEngine?
    private var isNumberPad = false
    private var isSymbolPad = false
    private var isShifted = false

    // MARK: - 视图

    private let composeLabel = UILabel()          // 拼音显示区
    private let candidateScroll = UIScrollView()  // 候选横向滚动
    private let candidateStack = UIStackView()
    private let rowsStack = UIStackView()         // 字母区 + 底行
    private var schemeButton: UIButton?
    private var shiftButton: UIButton?

    private enum Metric {
        static let kbHeight: CGFloat = 290
        static let composeHeight: CGFloat = 20
        static let candidateHeight: CGFloat = 42
        static let rowSpacing: CGFloat = 6
        static let keySpacing: CGFloat = 5
        static let sideInset: CGFloat = 3
        static let bottomHeight: CGFloat = 44
    }

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()

        // 键盘扩展的根视图由输入系统托管，其宽度已被系统铺满，不要自己动它的宽度；
        // 只需给一个高度约束（优先级留一档，避免旋转/浮动键盘时与系统约束冲突）。
        //
        // 历史坑（两次都栽在同一件事上）：
        //   自建 UIInputView(frame:) 并关掉 translatesAutoresizingMaskIntoConstraints 后，
        //   frame 里的宽和高**同时**失效。第一次只补了 heightAnchor，
        //   宽度仍无约束来源 → Auto Layout 按内容固有宽度收缩 → 键盘成窄条（"单手键盘"）。
        // 结论：直接用系统给的 self.view 作为容器最稳，宽度交给系统。
        let host = view!
        let hc = host.heightAnchor.constraint(equalToConstant: Metric.kbHeight)
        hc.priority = UILayoutPriority(999)
        hc.isActive = true

        buildUI(in: host)

        // 词库异步加载：不阻塞首帧。就绪前按键降级为直接上屏字符。
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // 方案必须读用户配置，不能硬编码。
            // 坑（已定性）：此处原为 MobileEngine(scheme: .pinyin) 硬编码，而
            //   ① 产品默认方案是 .flypy（InputScheme.default）—— 两端默认不一致；
            //   ② 用户在键盘上切了方案也不持久化，重启键盘就回到全拼。
            // 根因：宿主 App 把数据目录指向了 App Group，键盘扩展没指 →
            //   扩展读的是自己沙盒里的空目录，拿不到 config.json。
            let scheme = KeyboardViewController.loadScheme()
            let eng = MobileEngine(scheme: scheme)
            DispatchQueue.main.async {
                guard let self else { return }
                self.engine = eng
                self.schemeButton?.setTitle(self.schemeShort(), for: .normal)
                self.renderCandidates()
            }
        }
    }

    /// 从 App Group 共享配置读输入方案（与 macOS 同一份 config.json 格式）。
    /// 读不到时回退到产品默认方案，而不是写死的 .pinyin。
    private static func loadScheme() -> InputScheme {
        if let shared = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: HotwordsStore.appGroupID) {
            PhraseKeySettings.overrideDefaultDir = shared.appendingPathComponent("PhraseKey")
        }
        return PhraseKeySettings.load().scheme
    }

    // MARK: - UI 构建（全约束，无 frame 计算）

    private func buildUI(in host: UIView) {
        // ── 顶部：拼音显示 + 候选滚动条 ──
        composeLabel.font = .systemFont(ofSize: 15, weight: .medium)
        composeLabel.textColor = UIColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1)
        composeLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        candidateStack.axis = .horizontal
        candidateStack.spacing = 4
        candidateStack.alignment = .fill
        candidateStack.translatesAutoresizingMaskIntoConstraints = false

        candidateScroll.showsHorizontalScrollIndicator = false
        candidateScroll.translatesAutoresizingMaskIntoConstraints = false
        candidateScroll.addSubview(candidateStack)
        NSLayoutConstraint.activate([
            candidateStack.leadingAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.leadingAnchor),
            candidateStack.trailingAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.trailingAnchor),
            candidateStack.topAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.topAnchor),
            candidateStack.bottomAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.bottomAnchor),
            candidateStack.heightAnchor.constraint(equalTo: candidateScroll.frameLayoutGuide.heightAnchor),
        ])

        // 拼音行与候选行必须上下分层：若并排放在同一横向 stack，
        // composeLabel 的抗压缩优先级会把候选区挤到几乎没有宽度
        // （表现：候选放不下、无法连续选词，像"单手键盘"）。
        let composeRow = UIStackView(arrangedSubviews: [composeLabel, UIView()])
        composeRow.axis = .horizontal
        composeRow.isLayoutMarginsRelativeArrangement = true
        composeRow.layoutMargins = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)

        let topBar = UIStackView(arrangedSubviews: [composeRow, candidateScroll])
        topBar.axis = .vertical
        topBar.spacing = 2

        // ── 按键区 ──
        rowsStack.axis = .vertical
        rowsStack.spacing = Metric.rowSpacing
        rowsStack.distribution = .fillEqually

        let root = UIStackView(arrangedSubviews: [topBar, rowsStack])
        root.axis = .vertical
        root.spacing = 4
        root.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(root)

        // 贴 safeArea：底部要避开 Home 指示条，否则最后一行按键被压在指示条下点不准
        let guide = host.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: host.topAnchor, constant: 4),
            root.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -4),
            root.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: Metric.sideInset),
            root.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -Metric.sideInset),
            composeRow.heightAnchor.constraint(equalToConstant: Metric.composeHeight),
            candidateScroll.heightAnchor.constraint(equalToConstant: Metric.candidateHeight),
        ])

        rebuildKeys()
    }

    private func makeKey(_ title: String, wide: Bool = false, dark: Bool = false) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.setTitleColor(.black, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: title.count > 1 ? 15 : 21, weight: .regular)
        b.titleLabel?.adjustsFontSizeToFitWidth = true
        b.titleLabel?.minimumScaleFactor = 0.7
        b.backgroundColor = dark ? UIColor(white: 0.68, alpha: 1) : .white
        b.layer.cornerRadius = 6
        b.layer.shadowColor = UIColor.black.withAlphaComponent(0.25).cgColor
        b.layer.shadowOffset = CGSize(width: 0, height: 1)
        b.layer.shadowRadius = 0
        b.layer.shadowOpacity = 1
        b.addTarget(self, action: #selector(keyPressed(_:)), for: .touchUpInside)
        if wide { b.setContentCompressionResistancePriority(.defaultLow, for: .horizontal) }
        return b
    }

    private func makeRow(_ keys: [String], inset: CGFloat = 0) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = Metric.keySpacing
        row.distribution = .fillEqually
        for k in keys { row.addArrangedSubview(makeKey(displayTitle(k))) }
        guard inset > 0 else { return row }
        let wrap = UIStackView(arrangedSubviews: [row])
        wrap.isLayoutMarginsRelativeArrangement = true
        wrap.layoutMargins = UIEdgeInsets(top: 0, left: inset, bottom: 0, right: inset)
        return wrap
    }

    private func displayTitle(_ k: String) -> String {
        guard !isNumberPad, !isSymbolPad, k.count == 1, k.first!.isLetter else { return k }
        return isShifted ? k.uppercased() : k
    }

    private func rebuildKeys() {
        rowsStack.arrangedSubviews.forEach {
            rowsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let rows: [[String]]
        if isNumberPad {
            rows = [["1","2","3","4","5","6","7","8","9","0"],
                    ["-","/",":",";","(",")","¥","&","@","\""],
                    ["#+=",".",",","?","!","'","⌫"]]
        } else if isSymbolPad {
            rows = [["[","]","{","}","#","%","^","*","+","="],
                    ["_","\\","|","~","<",">","€","£","•","·"],
                    ["123",".",",","?","!","'","⌫"]]
        } else {
            rows = [["q","w","e","r","t","y","u","i","o","p"],
                    ["a","s","d","f","g","h","j","k","l"],
                    ["⇧","z","x","c","v","b","n","m","⌫"]]
        }

        rowsStack.addArrangedSubview(makeRow(rows[0]))
        rowsStack.addArrangedSubview(makeRow(rows[1], inset: isNumberPad || isSymbolPad ? 0 : 18))

        // 第三行：功能键需要不等宽，单独组装
        let r3 = UIStackView()
        r3.axis = .horizontal
        r3.spacing = Metric.keySpacing
        for k in rows[2] {
            let isFn = k.count > 1 || k == "⇧" || k == "⌫"
            let b = makeKey(displayTitle(k), dark: isFn)
            if k == "⇧" {
                b.backgroundColor = isShifted ? UIColor(white: 0.95, alpha: 1) : UIColor(white: 0.68, alpha: 1)
                shiftButton = b
            }
            r3.addArrangedSubview(b)
            if isFn { b.widthAnchor.constraint(equalToConstant: 44).isActive = true }
        }
        // 让字母键平分剩余空间
        let letters = r3.arrangedSubviews.filter { ($0 as? UIButton)?.backgroundColor == .white }
        for v in letters.dropFirst() {
            v.widthAnchor.constraint(equalTo: letters[0].widthAnchor).isActive = true
        }
        rowsStack.addArrangedSubview(r3)

        // 底行：数字/符号 | 🌐 | 方案 | 空格 | 回车
        let bottom = UIStackView()
        bottom.axis = .horizontal
        bottom.spacing = Metric.keySpacing

        let numKey = makeKey(isNumberPad || isSymbolPad ? "ABC" : "123", dark: true)
        let globe = makeKey("🌐", dark: true)
        globe.removeTarget(nil, action: nil, for: .allEvents)
        globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        let scheme = makeKey(schemeShort(), dark: true)
        scheme.removeTarget(nil, action: nil, for: .allEvents)
        scheme.addTarget(self, action: #selector(cycleScheme), for: .touchUpInside)
        schemeButton = scheme
        let space = makeKey("空格", wide: true)
        space.removeTarget(nil, action: nil, for: .allEvents)
        space.addTarget(self, action: #selector(spacePressed), for: .touchUpInside)
        let ret = makeKey("⏎", dark: true)
        ret.removeTarget(nil, action: nil, for: .allEvents)
        ret.addTarget(self, action: #selector(returnPressed), for: .touchUpInside)

        [numKey, globe, scheme, space, ret].forEach { bottom.addArrangedSubview($0) }
        numKey.widthAnchor.constraint(equalToConstant: 44).isActive = true
        globe.widthAnchor.constraint(equalToConstant: 40).isActive = true
        scheme.widthAnchor.constraint(equalToConstant: 48).isActive = true
        ret.widthAnchor.constraint(equalToConstant: 60).isActive = true

        rowsStack.addArrangedSubview(bottom)
        bottom.heightAnchor.constraint(equalToConstant: Metric.bottomHeight).isActive = true
    }

    // MARK: - 候选与拼音显示

    private func renderCandidates() {
        candidateStack.arrangedSubviews.forEach {
            candidateStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        composeLabel.text = engine?.composing.isEmpty == false ? engine?.composing : nil

        guard let engine, !engine.candidates.isEmpty else { return }
        for (i, c) in engine.candidates.prefix(30).enumerated() {
            let b = UIButton(type: .system)
            let mark = c.type == "hotword" ? "⌘ " : ""
            b.setTitle(mark + c.text, for: .normal)
            b.setTitleColor(c.type == "hotword"
                            ? UIColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1) : .black,
                            for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 17, weight: i == 0 ? .semibold : .regular)
            b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
            b.tag = i
            b.addTarget(self, action: #selector(candidateTapped(_:)), for: .touchUpInside)
            candidateStack.addArrangedSubview(b)
        }
        candidateScroll.setContentOffset(.zero, animated: false)
    }

    @objc private func candidateTapped(_ sender: UIButton) {
        guard let engine, let text = engine.commit(at: sender.tag) else { return }
        textDocumentProxy.insertText(text)
        renderCandidates()
    }

    // MARK: - 按键处理

    @objc private func keyPressed(_ sender: UIButton) {
        guard let raw = sender.title(for: .normal) else { return }
        let title = raw.lowercased()

        switch raw {
        case "⌫":
            if let engine, !engine.composing.isEmpty {
                engine.deleteLast()
            } else {
                textDocumentProxy.deleteBackward()
            }
            renderCandidates()
            return
        case "⇧":
            isShifted.toggle()
            rebuildKeys()
            return
        case "123", "ABC":
            isNumberPad.toggle()
            isSymbolPad = false
            rebuildKeys()
            return
        case "#+=":
            isSymbolPad = true
            isNumberPad = false
            rebuildKeys()
            return
        default:
            break
        }

        // 非字母（数字/符号）直接上屏
        guard raw.count == 1, raw.first!.isLetter else {
            textDocumentProxy.insertText(raw)
            return
        }

        // 大写状态：视为直接输入字母（不进拼音引擎），符合系统键盘习惯
        if isShifted {
            textDocumentProxy.insertText(raw)
            isShifted = false
            rebuildKeys()
            return
        }

        // 引擎未就绪时降级直接上屏，保证按键始终有反馈
        guard let engine else {
            textDocumentProxy.insertText(title)
            return
        }
        engine.append(title.first!)
        renderCandidates()
    }

    @objc private func spacePressed() {
        guard let engine else {
            textDocumentProxy.insertText(" ")
            return
        }
        textDocumentProxy.insertText(engine.space())
        renderCandidates()
    }

    @objc private func returnPressed() {
        guard let engine else {
            textDocumentProxy.insertText("\n")
            return
        }
        let t = engine.commitRaw()
        textDocumentProxy.insertText(t.isEmpty ? "\n" : t)
        renderCandidates()
    }

    @objc private func cycleScheme() {
        guard let engine else { return }
        let all = InputScheme.allCases
        let next = all[((all.firstIndex(of: engine.scheme) ?? 0) + 1) % all.count]
        self.engine = MobileEngine(scheme: next)
        schemeButton?.setTitle(schemeShort(), for: .normal)
        renderCandidates()
        // 持久化：否则键盘下次拉起又回到默认方案，用户每次都要重新切。
        // 写到 App Group 共享配置，宿主 App 与键盘共用同一份。
        var s = PhraseKeySettings.load()
        s.scheme = next
        s.save()
    }

    private func schemeShort() -> String {
        switch engine?.scheme {
        case .pinyin: return "全拼"
        case .flypy: return "双拼"
        case .flypyXing: return "音形"
        case nil: return "…"
        }
    }
}
