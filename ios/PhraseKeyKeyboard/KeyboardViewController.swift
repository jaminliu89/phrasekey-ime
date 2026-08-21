import UIKit

/// iOS 键盘扩展入口。
///
/// 关键修复（基于多轮真机实验的结论）：
/// - 最小版（1 按钮 + Auto Layout 约束）稳定弹出；所有"零 Auto Layout 约束"的纯 frame 版
///   都间歇性不弹/闪烁。结论：**键盘扩展的 view 必须有 Auto Layout 约束**，系统才能正确
///   计算键盘尺寸并加载；无约束时系统不知道 view 有内容 → 间歇性加载失败。
/// - 本版：keyArea 用 4 条 Auto Layout 约束填满 view（给系统锚点，不设固定高度，高度交系统默认），
///   keyArea **内部全部 frame 手工布局**（候选条 + 键区 + 按钮）——零内部约束冲突。
/// - 候选条用普通 UIView（键盘容器自带下滑收起手势，嵌套 UIScrollView 会拦截导致顶部闪烁）。
/// - 加载路径零文件访问（受限沙盒文件 I/O 会阻塞加载），完全访问开关已正确暴露（RequestsOpenAccess）。
final class KeyboardViewController: UIInputViewController {

    private var engine = MobileEngine(scheme: .pinyin)
    private var candidateBar: UIView!
    private var candidateButtons: [UIButton] = []
    private var keyArea: UIView!
    private var keyRows: [[UIButton]] = []
    private var bottomKeys: [UIButton] = []
    private var isNumberPad = false

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        engine = MobileEngine(scheme: .pinyin)  // 零文件访问，纯内存
        buildUI()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutFrames()
        if !candidateButtons.isEmpty { layoutCandidates() }
    }

    // MARK: - 构建 UI

    private func buildUI() {
        view.backgroundColor = UIColor(red: 0.784, green: 0.800, blue: 0.824, alpha: 1) // #C8CCD2

        // 锚点容器：Auto Layout 填满 view（给系统尺寸锚点，无固定高度、无内部约束）
        keyArea = UIView()
        keyArea.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyArea)
        NSLayoutConstraint.activate([
            keyArea.topAnchor.constraint(equalTo: view.topAnchor),
            keyArea.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            keyArea.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyArea.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        // 候选条（顶部 40，frame 布局）
        candidateBar = UIView()
        candidateBar.backgroundColor = .white
        keyArea.addSubview(candidateBar)

        rebuildKeys()
    }

    private func makeKey(_ title: String) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(.black, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 20, weight: .regular)
        btn.backgroundColor = .white
        btn.layer.cornerRadius = 6
        btn.addTarget(self, action: #selector(keyPressed(_:)), for: .touchUpInside)
        return btn
    }

    private func rebuildKeys() {
        keyArea.subviews.forEach { $0.removeFromSuperview() }
        keyRows = []
        bottomKeys = []
        // 候选条先重加（被清掉了）
        candidateBar = UIView()
        candidateBar.backgroundColor = .white
        keyArea.addSubview(candidateBar)
        candidateButtons = []

        let rows: [[String]] = isNumberPad
            ? [["1","2","3","4","5","6","7","8","9","0"],
               ["-","/",":",";","(",")","$","&","@","\""],
               [".#+=", ".", ",", "?", "!", "'", "⌫"]]
            : [["q","w","e","r","t","y","u","i","o","p"],
               ["a","s","d","f","g","h","j","k","l"],
               ["123", "z","x","c","v","b","n","m", "⌫"]]
        for row in rows {
            var btns: [UIButton] = []
            for key in row {
                let b = makeKey(key)
                keyArea.addSubview(b)
                btns.append(b)
            }
            keyRows.append(btns)
        }
        // 底行：方案 | 空格 | 回车
        let schemeBtn = makeKey(schemeShort())
        schemeBtn.addTarget(self, action: #selector(cycleScheme), for: .touchUpInside)
        keyArea.addSubview(schemeBtn)
        bottomKeys.append(schemeBtn)

        let spaceBtn = makeKey("空格")
        spaceBtn.addTarget(self, action: #selector(spacePressed), for: .touchUpInside)
        keyArea.addSubview(spaceBtn)
        bottomKeys.append(spaceBtn)

        let returnBtn = makeKey("⏎")
        returnBtn.addTarget(self, action: #selector(returnPressed), for: .touchUpInside)
        keyArea.addSubview(returnBtn)
        bottomKeys.append(returnBtn)
    }

    // MARK: - frame 布局（唯一布局入口）

    private func layoutFrames() {
        let w = view.bounds.width
        let h = view.bounds.height
        guard w > 0, h > 0 else { return }
        let kw = keyArea.bounds.width
        let kh = keyArea.bounds.height
        guard kw > 0, kh > 0 else { return }

        candidateBar.frame = CGRect(x: 0, y: 0, width: kw, height: 40)
        let keysTop: CGFloat = 46
        let sp: CGFloat = 6
        let bottomH: CGFloat = 44
        let keysH = max(kh - keysTop - sp, 80)
        let mainH = keyRows.isEmpty ? 0 : (keysH - bottomH - sp * 2) / CGFloat(keyRows.count)
        var y: CGFloat = keysTop
        for btns in keyRows {
            let n = btns.count
            let btnW = n > 0 ? (kw - sp * CGFloat(n - 1)) / CGFloat(n) : 0
            var x: CGFloat = 0
            for b in btns {
                b.frame = CGRect(x: x, y: y, width: btnW, height: mainH)
                x += btnW + sp
            }
            y += mainH + sp
        }
        // 底行
        let bw = bottomKeys.isEmpty ? 0 : (kw - sp * 2) / CGFloat(bottomKeys.count)
        for (i, b) in bottomKeys.enumerated() {
            b.frame = CGRect(x: CGFloat(i) * (bw + sp), y: y, width: bw, height: bottomH)
        }
    }

    // MARK: - 候选条

    private func layoutCandidates() {
        var x: CGFloat = 6
        let cbw = max(candidateBar.bounds.width - 12, 100)
        for b in candidateButtons {
            if x + b.frame.width > cbw + 8 { b.isHidden = true; continue }
            b.isHidden = false
            b.frame.origin.x = x
            x += b.frame.width + 8
        }
    }

    private func renderCandidates() {
        candidateButtons.forEach { $0.removeFromSuperview() }
        candidateButtons = []
        var x: CGFloat = 6
        let h: CGFloat = 34
        let maxW = max(candidateBar.bounds.width - 12, 100)
        for c in engine.candidates.prefix(12) {
            let btn = UIButton(type: .system)
            let mark = c.type == "hotword" ? "⌘ " : ""
            btn.setTitle(mark + (c.text.count > 14 ? String(c.text.prefix(14)) + "…" : c.text), for: .normal)
            btn.setTitleColor(c.type == "hotword" ? UIColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1) : .black, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
            btn.sizeToFit()
            let w = min(btn.frame.width + 24, maxW)
            if x + w > maxW + 8 { break }
            btn.frame = CGRect(x: x, y: 3, width: w, height: h)
            btn.addTarget(self, action: #selector(candidateTapped(_:)), for: .touchUpInside)
            candidateBar.addSubview(btn)
            candidateButtons.append(btn)
            x += w + 8
        }
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
            rebuildKeys()
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
        // 方案切换仅内存生效；不碰 AppSettings（受限沙盒文件访问问题，持久化后续处理）
        renderCandidates()
        rebuildKeys()
    }

    private func schemeShort() -> String {
        switch engine.scheme {
        case .pinyin: return "全拼"
        case .flypy: return "双拼"
        case .flypyXing: return "音形"
        }
    }
}
