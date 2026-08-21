import UIKit

/// iOS 键盘扩展入口。Gboard 风格：候选条 + 字母/数字层 + 常用语优先。
/// 复用桌面端引擎（MobileEngine → Searcher），数据走 App Group 容器（跨端同步）。
final class KeyboardViewController: UIInputViewController {

    private var engine: MobileEngine!
    private var candidateBar: UIScrollView!
    private var candidateButtons: [UIButton] = []
    private var keys: [String] = []
    private var isNumberPad = false
    private var schemeLabel: UILabel!
    private var keyArea: UIView!

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        // App Group 数据容器（与 macOS/宿主共享 hotwords.json 等）
        // 未开启「允许完全访问」时容器不可用：优雅降级到本地沙盒目录，绝不能崩溃
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.phrasekey.ime") {
            PhraseKeySettings.overrideDefaultDir = container.appendingPathComponent("PhraseKey")
        }
        AppSettings.current = PhraseKeySettings.load()
        engine = MobileEngine(scheme: AppSettings.current.scheme)
        buildUI()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // 键盘高度交给系统管理。
        // 不要在布局回调里修改高度约束：每次改约束都会触发新的布局，
        // 形成死循环导致键盘界面不断重绘闪烁。
    }

    // MARK: - 构建 UI

    private func buildUI() {
        view.backgroundColor = UIColor(red: 0.784, green: 0.800, blue: 0.824, alpha: 1) // #C8CCD2
        // 高度约束
        let heightConstraint = view.heightAnchor.constraint(equalToConstant: 300)
        heightConstraint.priority = .defaultHigh
        view.addConstraint(heightConstraint)

        // 候选条
        candidateBar = UIScrollView()
        candidateBar.backgroundColor = .white
        candidateBar.showsHorizontalScrollIndicator = false
        candidateBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(candidateBar)

        // 键盘键区（字母/数字层 + 底行）
        keyArea = UIView()
        keyArea.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyArea)

        NSLayoutConstraint.activate([
            candidateBar.topAnchor.constraint(equalTo: view.topAnchor),
            candidateBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            candidateBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            candidateBar.heightAnchor.constraint(equalToConstant: 40),
            keyArea.topAnchor.constraint(equalTo: candidateBar.bottomAnchor, constant: 6),
            keyArea.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            keyArea.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            keyArea.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
        ])

        buildKeyArea(in: keyArea)
    }

    private func buildKeyArea(in container: UIView) {
        container.subviews.forEach { $0.removeFromSuperview() }
        // 4 行：3 行主键 + 1 行底行
        let rows: [[String]] = isNumberPad
            ? [["1","2","3","4","5","6","7","8","9","0"],
               ["-","/",":",";","(",")","$","&","@","\""],
               [".#+=", ".", ",", "?", "!", "'", "⌫"]]
            : [["q","w","e","r","t","y","u","i","o","p"],
               ["a","s","d","f","g","h","j","k","l"],
               ["123", "z","x","c","v","b","n","m", "⌫"]]

        let stack = UIStackView()
        stack.axis = .vertical
        stack.distribution = .fillEqually
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        for (i, row) in rows.enumerated() {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.distribution = .fillEqually
            rowStack.spacing = 6
            for key in row {
                let btn = makeKey(key)
                rowStack.addArrangedSubview(btn)
            }
            // 第三行字母的 z/x/c/v/b/n/m 上移（标准键盘布局偏移）
            if !isNumberPad && i == 2 {
                let pad = UIView()
                rowStack.insertArrangedSubview(pad, at: 0)
            }
            stack.addArrangedSubview(rowStack)
        }

        // 底行：方案 | 空格 | 回车
        let bottom = UIStackView()
        bottom.axis = .horizontal
        bottom.distribution = .fill
        bottom.spacing = 6
        bottom.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bottom)
        NSLayoutConstraint.activate([
            bottom.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 6),
            bottom.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bottom.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bottom.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            bottom.heightAnchor.constraint(equalToConstant: 46),
        ])

        // 方案切换按钮（显示当前方案）
        let schemeBtn = makeKey("\(schemeShort())")
        schemeBtn.addTarget(self, action: #selector(cycleScheme), for: .touchUpInside)
        schemeBtn.widthAnchor.constraint(equalToConstant: 90).isActive = true
        bottom.addArrangedSubview(schemeBtn)

        let spaceBtn = makeKey("空格")
        spaceBtn.addTarget(self, action: #selector(spacePressed), for: .touchUpInside)
        spaceBtn.widthAnchor.constraint(equalToConstant: 200).isActive = true
        bottom.addArrangedSubview(spaceBtn)

        let returnBtn = makeKey("⏎")
        returnBtn.addTarget(self, action: #selector(returnPressed), for: .touchUpInside)
        returnBtn.widthAnchor.constraint(equalToConstant: 90).isActive = true
        bottom.addArrangedSubview(returnBtn)
    }

    private func makeKey(_ title: String) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(.black, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 20, weight: .regular)
        btn.backgroundColor = .white
        btn.layer.cornerRadius = 6
        btn.layer.shadowColor = UIColor.black.cgColor
        btn.layer.shadowOpacity = 0.2
        btn.layer.shadowOffset = CGSize(width: 0, height: 1)
        btn.layer.shadowRadius = 0
        btn.heightAnchor.constraint(equalToConstant: 46).isActive = true
        btn.addTarget(self, action: #selector(keyPressed(_:)), for: .touchUpInside)
        return btn
    }

    private func schemeShort() -> String {
        switch engine.scheme {
        case .pinyin: return "全拼"
        case .flypy: return "双拼"
        case .flypyXing: return "音形"
        }
    }

    // MARK: - 候选条

    private func renderCandidates() {
        candidateButtons.forEach { $0.removeFromSuperview() }
        candidateButtons = []
        var x: CGFloat = 6
        let height: CGFloat = 34
        for c in engine.candidates.prefix(12) {
            let btn = UIButton(type: .system)
            let mark = c.type == "hotword" ? "⌘ " : ""
            btn.setTitle(mark + (c.text.count > 14 ? String(c.text.prefix(14)) + "…" : c.text), for: .normal)
            btn.setTitleColor(c.type == "hotword" ? UIColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1) : .black, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
            btn.sizeToFit()
            let w = btn.frame.width + 24
            btn.frame = CGRect(x: x, y: 3, width: min(w, candidateBar.bounds.width - 24), height: height)
            btn.addTarget(self, action: #selector(candidateTapped(_:)), for: .touchUpInside)
            candidateBar.addSubview(btn)
            candidateButtons.append(btn)
            x += btn.frame.width + 8
        }
        candidateBar.contentSize = CGSize(width: x + 6, height: height)
    }

    @objc private func candidateTapped(_ sender: UIButton) {
        if let idx = candidateButtons.firstIndex(of: sender),
           let text = engine.commit(at: idx) {
            textDocumentProxy.insertText(text)
        }
        renderCandidates()
    }

    // MARK: - 按键

    @objc private func keyPressed(_ sender: UIButton) {
        guard let title = sender.title(for: .normal) else { return }
        switch title {
        case "⌫":
            if engine.composing.isEmpty {
                textDocumentProxy.deleteBackward()
            } else {
                engine.deleteLast()
            }
        case "123", "ABC":
            isNumberPad.toggle()
            buildKeyArea(in: keyArea)
            renderCandidates()
            return
        case ".#+=":
            return
        default:
            if title.count == 1 {
                engine.append(title.first!)
            }
        }
        renderCandidates()
    }

    @objc private func spacePressed() {
        let t = engine.space()
        textDocumentProxy.insertText(t)
        renderCandidates()
    }

    @objc private func returnPressed() {
        let t = engine.commitRaw()
        textDocumentProxy.insertText(t.isEmpty ? "\n" : t)
        renderCandidates()
    }

    @objc private func cycleScheme() {
        let all = InputScheme.allCases
        let cur = all.firstIndex(of: engine.scheme) ?? 0
        let next = all[(cur + 1) % all.count]
        engine = MobileEngine(scheme: next)
        AppSettings.current.scheme = next
        AppSettings.save()
        renderCandidates()
        rebuildBottom()
    }

    private func rebuildBottom() {
        // 刷新底行方案按钮标题（简单方案：整体重建键盘区）
        buildKeyArea(in: keyArea)
    }
}
