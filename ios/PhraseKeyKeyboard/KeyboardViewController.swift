import UIKit

/// iOS 键盘扩展主控制器。
///
/// 注意：免费 Apple ID 签名的开发版本，锁屏后扩展会被系统收回（签名验证问题），
/// 这是 iOS 免费开发者账号的固有特性，不是 bug。付费开发者账号无此问题。
final class KeyboardViewController: UIInputViewController {

    private var engine: MobileEngine?
    private var candidateBar: UIView!
    private var candidateButtons: [UIButton] = []
    private var keyArea: UIView!
    private var keyRows: [[UIButton]] = []
    private var bottomKeys: [UIButton] = []
    private var isNumberPad = false
    private var didBuildContent = false

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()

        let kbView = UIInputView(frame: CGRect(x: 0, y: 0, width: 0, height: 260), inputViewStyle: .keyboard)
        kbView.translatesAutoresizingMaskIntoConstraints = false
        kbView.backgroundColor = UIColor(red: 0.784, green: 0.800, blue: 0.824, alpha: 1)
        self.inputView = kbView

        keyArea = UIView()
        keyArea.translatesAutoresizingMaskIntoConstraints = false
        kbView.addSubview(keyArea)
        NSLayoutConstraint.activate([
            keyArea.topAnchor.constraint(equalTo: kbView.topAnchor),
            keyArea.bottomAnchor.constraint(equalTo: kbView.bottomAnchor),
            keyArea.leadingAnchor.constraint(equalTo: kbView.leadingAnchor),
            keyArea.trailingAnchor.constraint(equalTo: kbView.trailingAnchor),
        ])

        // 后台加载引擎，避免启动时卡主线程被 watchdog 杀
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let eng = MobileEngine(scheme: .pinyin)
            DispatchQueue.main.async {
                guard let self else { return }
                self.engine = eng
                self.buildContent()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if didBuildContent {
            layoutFrames()
            if !candidateButtons.isEmpty { layoutCandidates() }
        }
    }

    // MARK: - 构建内容

    private func buildContent() {
        rebuildKeys()
        didBuildContent = true
        layoutFrames()
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

        // 候选条
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

        // 底行：🌐 切换 | 方案 | 空格 | 回车
        let globeBtn = makeKey("🌐")
        globeBtn.addTarget(self, action: #selector(advanceToNextInputMode), for: .touchUpInside)
        keyArea.addSubview(globeBtn)
        bottomKeys.append(globeBtn)

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

    // MARK: - 布局

    private func layoutFrames() {
        let w = keyArea.bounds.width > 0 ? keyArea.bounds.width : UIScreen.main.bounds.width
        let h = keyArea.bounds.height > 0 ? keyArea.bounds.height : 260
        guard w > 0, h > 0 else { return }

        candidateBar.frame = CGRect(x: 0, y: 0, width: w, height: 40)
        let keysTop: CGFloat = 46
        let sp: CGFloat = 5
        let bottomH: CGFloat = 42
        let keysH = max(h - keysTop - sp, 80)
        let mainH = keyRows.isEmpty ? 0 : (keysH - bottomH - sp * 2) / CGFloat(keyRows.count)
        var y: CGFloat = keysTop
        for btns in keyRows {
            let n = btns.count
            let btnW = n > 0 ? (w - sp * CGFloat(n - 1)) / CGFloat(n) : 0
            var x: CGFloat = 0
            for b in btns {
                b.frame = CGRect(x: x, y: y, width: btnW, height: mainH)
                x += btnW + sp
            }
            y += mainH + sp
        }
        // 底行
        let bottomY = y
        let globeW: CGFloat = 40
        let schemeW: CGFloat = 50
        let returnW: CGFloat = 50
        let spaceW = w - globeW - schemeW - returnW - sp * 3
        var bx: CGFloat = 0
        bottomKeys[0].frame = CGRect(x: bx, y: bottomY, width: globeW, height: bottomH); bx += globeW + sp
        bottomKeys[1].frame = CGRect(x: bx, y: bottomY, width: schemeW, height: bottomH); bx += schemeW + sp
        bottomKeys[2].frame = CGRect(x: bx, y: bottomY, width: spaceW, height: bottomH); bx += spaceW + sp
        bottomKeys[3].frame = CGRect(x: bx, y: bottomY, width: returnW, height: bottomH)
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
        guard let engine else { return }
        var x: CGFloat = 6
        let h: CGFloat = 34
        let maxW = max(candidateBar.bounds.width - 12, 100)
        for c in engine.candidates.prefix(12) {
            let btn = UIButton(type: .system)
            let mark = c.type == "hotword" ? "⌘ " : ""
            let txt = c.text.count > 14 ? String(c.text.prefix(14)) + "…" : c.text
            btn.setTitle(mark + txt, for: .normal)
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
        guard let engine else { return }
        if let idx = candidateButtons.firstIndex(of: sender),
           let text = engine.commit(at: idx) {
            textDocumentProxy.insertText(text)
        }
        renderCandidates()
    }

    // MARK: - 按键

    @objc private func keyPressed(_ sender: UIButton) {
        guard let engine else { return }
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
        guard let engine else { return }
        let t = engine.space()
        textDocumentProxy.insertText(t)
        renderCandidates()
    }

    @objc private func returnPressed() {
        guard let engine else { return }
        let t = engine.commitRaw()
        textDocumentProxy.insertText(t.isEmpty ? "\n" : t)
        renderCandidates()
    }

    @objc private func cycleScheme() {
        guard let engine else { return }
        let all = InputScheme.allCases
        let cur = all.firstIndex(of: engine.scheme) ?? 0
        let next = all[(cur + 1) % all.count]
        self.engine = MobileEngine(scheme: next)
        renderCandidates()
        rebuildKeys()
    }

    private func schemeShort() -> String {
        guard let engine else { return "..." }
        switch engine.scheme {
        case .pinyin: return "全拼"
        case .flypy: return "双拼"
        case .flypyXing: return "音形"
        }
    }
}
