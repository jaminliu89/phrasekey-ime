import UIKit

/// iOS 键盘扩展入口。
///
/// 布局策略：**纯 frame 手工布局**（viewDidLayoutSubviews 里按 view.bounds 计算每个视图位置），
/// 键盘内部不引入任何 Auto Layout 约束——彻底消灭「约束冲突 → 布局死循环 → 顶部闪烁 / 键盘不弹」。
/// 键盘高度完全交给系统管理（不设任何高度约束）。
///
/// 加载路径零文件访问：绝不触碰 AppSettings.current（其静态初始化会 load() 读文件，
/// 键盘扩展受限沙盒下文件访问会阻塞加载）。引擎用默认方案，词库延迟到首次输入时才可能加载。
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

    // MARK: - 构建 UI（仅创建子视图，位置全部交给 layoutFrames）

    private func buildUI() {
        view.backgroundColor = UIColor(red: 0.784, green: 0.800, blue: 0.824, alpha: 1) // #C8CCD2

        candidateBar = UIView()
        candidateBar.backgroundColor = .white
        view.addSubview(candidateBar)

        keyArea = UIView()
        view.addSubview(keyArea)

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

        candidateBar.frame = CGRect(x: 0, y: 0, width: w, height: 40)
        keyArea.frame = CGRect(x: 4, y: 46, width: w - 8, height: max(h - 52, 120))
        let kr = keyArea.bounds
        let sp: CGFloat = 6
        let bottomH: CGFloat = 44
        let mainH = keyRows.isEmpty ? 0 : (kr.height - bottomH - sp * 2) / CGFloat(keyRows.count)
        var y: CGFloat = 0
        for btns in keyRows {
            let n = btns.count
            let btnW = n > 0 ? (kr.width - sp * CGFloat(n - 1)) / CGFloat(n) : 0
            var x: CGFloat = 0
            for b in btns {
                b.frame = CGRect(x: x, y: y, width: btnW, height: mainH)
                x += btnW + sp
            }
            y += mainH + sp
        }
        // 底行
        let bw = bottomKeys.isEmpty ? 0 : (kr.width - sp * 2) / CGFloat(bottomKeys.count)
        for (i, b) in bottomKeys.enumerated() {
            b.frame = CGRect(x: CGFloat(i) * (bw + sp), y: y, width: bw, height: bottomH)
        }
    }

    // MARK: - 候选条

    private func layoutCandidates() {
        // 候选按钮 frame 由 renderCandidates 计算，这里仅在 bounds 变化时由布局回调触发重排
        var x: CGFloat = 6
        for b in candidateButtons {
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
            layoutFrames()
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
        layoutFrames()
    }

    private func schemeShort() -> String {
        switch engine.scheme {
        case .pinyin: return "全拼"
        case .flypy: return "双拼"
        case .flypyXing: return "音形"
        }
    }
}
