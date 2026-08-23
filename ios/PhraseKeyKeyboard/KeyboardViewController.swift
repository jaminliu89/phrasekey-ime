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
    /// 短语面板是否展开。核心卖点的入口 —— 518 条常用语靠背简码不现实，
    /// 必须有可浏览的面板（微信/搜狗都有，见 00-research.md §6）。
    private var isPhrasePad = false

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

    // MARK: - 配色

    /// 键盘配色（集中定义，不要在各处写死颜色）。
    ///
    /// 坑（用户实测报告「待选字体黑色 字母蓝色」），根因不是「忘了适配深色」，
    /// 而是 **iOS 系统级 bug**（KeyboardKit issue #305，已报 Apple）：
    ///   编辑**深色外观文本框**时，iOS 会给键盘扩展**错误的 color scheme** ——
    ///   即使系统是浅色，扩展也被告知是深色。
    ///
    /// 这否决了两种想当然的修法：
    ///   ❌ 硬编码颜色（原实现：候选字 .black、拼音串蓝色）→ 深色下不可读
    ///   ❌ 改用 .label / .systemBackground 语义色 → **系统给的外观信号本身是错的**
    ///
    /// 与 macOS 端那个坑**同源**：不能信任框架给的外观判定
    ///   （macOS 那次是 NSApp.effectiveAppearance 判的是输入法进程自身外观）。
    ///
    /// 采用方案：照拄 Hamster 仓输入法 / KeyboardKit 生产验证过的**半透明白**变通色。
    ///   半透明白叠在任何底色上都产生对比 → 即使外观判定错了，
    ///   也不会出现「黑字配深底」这种不可读组合。
    ///   色值来源：Hamster `Colors.xcassets/*.colorset`（MIT，1621★，已实测读取）。
    ///   详见 `.pi/plans/00-research.md` §8。
    private enum Palette {
        /// 字母键背景：浅色纯白 / 深色半透明白 30%
        static let keyBackground = UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.30)
                : UIColor.white
        }

        /// 功能键背景（shift / 删除 / 符号切换）：比字母键暗一档
        static let fnKeyBackground = UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.10)
                : UIColor(red: 0.702, green: 0.718, blue: 0.753, alpha: 1)
        }

        /// 键盘底板
        static let keyboardBackground = UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(white: 0.173, alpha: 1)
                : UIColor(red: 0.835, green: 0.839, blue: 0.867, alpha: 1)
        }

        /// 键帽 / 候选字文字：深色下纯白，浅色下纯黑
        /// （文字不能用半透明 —— 会发糊降低可读性）
        static let foreground = UIColor { tc in
            tc.userInterfaceStyle == .dark ? .white : .black
        }

        /// 常用语候选（需要区分于普通候选）：加粗字重，不用彩色
        /// （不用系统蓝 — 对齐 PhraseKeyTheme 灰度字重体系，靠字重区分层级）
        static let accent = UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor.white
                : UIColor.black
        }
        static let accentWeight: UIFont.Weight = .semibold

        /// 拼音串（次要信息，比候选字弱但仍须清楚可读）
        static let composeText = UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(white: 0.85, alpha: 1)
                : UIColor(white: 0.25, alpha: 1)
        }
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
        // 键盘底板色：此前**从未设置**，依赖系统默认 ——
        // 这是用户报「字母看不清」的另一半原因：底板与键帽可能同色，
        // 键与键的边界完全消失。底板必须比字母键暗，才能读出键位形状。
        host.backgroundColor = Palette.keyboardBackground

        // ── 顶部：拼音显示 + 候选滚动条 ──
        composeLabel.font = .systemFont(ofSize: 15, weight: .medium)
        composeLabel.textColor = Palette.composeText
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

        // 拼音行：左边 logo 按钮 + 拼音串
        let logo = UIButton(type: .system)
        logo.setTitle("P", for: .normal)
        logo.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        logo.setTitleColor(Palette.foreground, for: .normal)
        logo.layer.cornerRadius = 4
        logo.layer.borderWidth = 1.5
        logo.layer.borderColor = Palette.foreground.cgColor
        logo.addTarget(self, action: #selector(logoTapped), for: .touchUpInside)
        logo.widthAnchor.constraint(equalToConstant: 22).isActive = true
        logo.heightAnchor.constraint(equalToConstant: 22).isActive = true
        logoButton = logo

        let composeRow = UIStackView(arrangedSubviews: [logo, composeLabel, UIView()])
        composeRow.axis = .horizontal
        composeRow.spacing = 8
        composeRow.isLayoutMarginsRelativeArrangement = true
        composeRow.layoutMargins = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)

        let topBar = UIStackView(arrangedSubviews: [composeRow, candidateScroll])
        topBar.axis = .vertical
        topBar.spacing = 2
        candidateScrollView = candidateScroll

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
        b.setTitleColor(Palette.foreground, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: title.count > 1 ? 15 : 21, weight: .regular)
        b.titleLabel?.adjustsFontSizeToFitWidth = true
        b.titleLabel?.minimumScaleFactor = 0.7
        b.backgroundColor = dark ? Palette.fnKeyBackground : Palette.keyBackground
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

        // 短语面板：替换字母区，底行保留（用户可随时切回）
        if isPhrasePad {
            rowsStack.addArrangedSubview(makePhrasePad())
            buildBottomRow()
            return
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
            // 第 2 行末尾补 ' 分隔符（Gboard 中文键盘同做法）。
            // 坑（用户实测报告）：此前无此键 —— 用户要按分隔符必须切到符号面板，
            //   而符号面板一按就退出拼音上下文，等于用不了。
            // 位置理由：第 2 行原本只 9 键（asdfghjkl），末尾天然有位；
            //   放这里不挤压任何字母键宽度，肌肉记忆不受影响。
            rows = [["q","w","e","r","t","y","u","i","o","p"],
                    ["a","s","d","f","g","h","j","k","l","'"],
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
                // shift 选中态：按下时用字母键的亮色，未按用功能键暗色
                b.backgroundColor = isShifted ? Palette.keyBackground : Palette.fnKeyBackground
                shiftButton = b
            }
            // 用 tag 标记功能键，供下面筛字母键用。
            // 坑（已定性）：原实现靠 `backgroundColor == .white` 反推字母键 ——
            //   靠颜色识别控件类型是脆弱写法：改配色就会连带把布局搞坏
                //   （本次改深色适配时就会踩上）。改用显式 tag。
            b.tag = isFn ? -1 : 0
            r3.addArrangedSubview(b)
            if isFn { b.widthAnchor.constraint(equalToConstant: 44).isActive = true }
        }
        // 让字母键平分剩余空间（靠 tag 而非颜色识别，见上方注释）
        let letters = r3.arrangedSubviews.filter { ($0 as? UIButton)?.tag == 0 }
        for v in letters.dropFirst() {
            v.widthAnchor.constraint(equalTo: letters[0].widthAnchor).isActive = true
        }
        rowsStack.addArrangedSubview(r3)

        buildBottomRow()
    }

    /// 底行独立成函数：短语面板也要用它（面板只替换字母区，底行保留）。
    private func buildBottomRow() {
        // 底行：数字/符号 | 短语 | 🌐 | 方案 | 空格 | 回车
        let bottom = UIStackView()
        bottom.axis = .horizontal
        bottom.spacing = Metric.keySpacing

        // 短语键：项目核心卖点的可见入口。
        // 坑（用户反馈「放功能那一块全是黑的啥也没有」）：此前键盘上**没有任何**
        //   常用语入口 —— 518 条短语只能靠记简码触发，等于核心功能不可发现。
        let phraseKey = makeKey(isPhrasePad ? "返回" : "短语", dark: true)
        phraseKey.removeTarget(nil, action: nil, for: .allEvents)
        phraseKey.addTarget(self, action: #selector(togglePhrasePad), for: .touchUpInside)

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

        [numKey, phraseKey, globe, scheme, space, ret].forEach { bottom.addArrangedSubview($0) }
        numKey.widthAnchor.constraint(equalToConstant: 40).isActive = true
        phraseKey.widthAnchor.constraint(equalToConstant: 48).isActive = true
        globe.widthAnchor.constraint(equalToConstant: 36).isActive = true
        scheme.widthAnchor.constraint(equalToConstant: 44).isActive = true
        ret.widthAnchor.constraint(equalToConstant: 60).isActive = true

        rowsStack.addArrangedSubview(bottom)
        bottom.heightAnchor.constraint(equalToConstant: Metric.bottomHeight).isActive = true
    }

    // MARK: - 顶部工具栏 & 快捷面板

    /// 快捷面板开关状态：true = 面板展开，false = 正常候选栏
    private var quickPanelOpen = false

    /// 快捷面板按钮（键盘左上角 logo 位）
    private var logoButton: UIButton?

    /// 快捷面板容器（替代 candidateScroll 的位置）
    private var quickPanelView: UIView?

    /// 候选栏滚动视图（用于显隐切换）
    private var candidateScrollView: UIScrollView?

    // MARK: - 快捷面板交互

    @objc private func logoTapped() {
        quickPanelOpen.toggle()
        toggleQuickPanel(open: quickPanelOpen)
    }

    private func toggleQuickPanel(open: Bool) {
        guard let scrollView = candidateScrollView,
              let superview = scrollView.superview else { return }

        if open {
            let panel = makeQuickPanel()
            panel.translatesAutoresizingMaskIntoConstraints = false
            superview.insertSubview(panel, belowSubview: scrollView)
            quickPanelView = panel
            NSLayoutConstraint.activate([
                panel.topAnchor.constraint(equalTo: scrollView.topAnchor),
                panel.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
                panel.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
                panel.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            ])
            scrollView.isHidden = true
        } else {
            quickPanelView?.removeFromSuperview()
            quickPanelView = nil
            scrollView.isHidden = false
        }
    }

    private func makeQuickPanel() -> UIView {
        let panel = UIView()
        panel.backgroundColor = Palette.keyBackground

        let phrasesBtn = makeQuickButton(title: "常用语", subtitle: "快捷短语与模板")
        phrasesBtn.addTarget(self, action: #selector(quickPhrasesTapped), for: .touchUpInside)

        let settingsBtn = makeQuickButton(title: "设置", subtitle: "方案 / 主题")
        settingsBtn.addTarget(self, action: #selector(quickSettingsTapped), for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [phrasesBtn, settingsBtn])
        row.axis = .horizontal
        row.spacing = 8
        row.distribution = .fillEqually
        row.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: panel.topAnchor, constant: 6),
            row.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -12),
            row.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -6),
        ])
        return panel
    }

    private func makeQuickButton(title: String, subtitle: String) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(Palette.foreground, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        btn.backgroundColor = Palette.fnKeyBackground
        btn.layer.cornerRadius = 6
        return btn
    }

    @objc private func quickPhrasesTapped() {
        quickPanelOpen = false
        toggleQuickPanel(open: false)
        isPhrasePad = true
        rebuildKeys()
    }

    @objc private func quickSettingsTapped() {
        let next: InputScheme = scheme == .flypy ? .pinyin : .flypy
        scheme = next
        schemeButton?.setTitle(schemeShort(), for: .normal)
        UserDefaults.standard.set(scheme.rawValue, forKey: "scheme")
        quickPanelOpen = false
        toggleQuickPanel(open: false)
        inputBuffer = ""
        renderCandidates()
    }

    /// 短语面板显示类型：全部 / 短常用语 / 长文本
    /// 长文本不参与正常打字候选，只能在面板里手动选择，避免误触。
    private enum PhrasePadFilter: Int {
        case all = 0
        case short = 1
        case long = 2
    }
    private var phrasePadFilter: PhrasePadFilter = .all

    /// 当前面板选中的分类（nil = 全部）。分类取自简码首字母，见 phraseCategories。
    private var phraseCategory: String?

    @objc private func togglePhrasePad() {
        isPhrasePad.toggle()
        if isPhrasePad {
            // 进面板时清掉未完成的拼音，避免面板上屏后残留拼音串
            engine?.reset()
            composeLabel.text = ""
            phraseCategory = nil
        }
        rebuildKeys()
        renderCandidates()
    }

    /// 短语面板：上方分类条 + 下方可滚动短语列表。
    ///
    /// 为什么要做（用户反馈「放功能那一块全是黑的啥也没有」）：
    ///   此前键盘上**没有任何**常用语入口 —— 518 条短语只能靠记简码触发。
    ///   记不住 = 核心功能不可发现 = 等于没做。
    ///   微信/搜狗都有可浏览的短语面板（见 00-research.md §6）。
    ///
    /// 设计取舍：
    ///   · 长文本必须能看清 → 用多行文本 + 左对齐，不是候选条那种单行截断
    ///   · 518 条必须可筛 → 顶部按简码首字母分类，避免无限滚动
    ///   · 点一下直接上屏 → 短语的价值就在省手打，不做二次确认
    private func makePhrasePad() -> UIView {
        let container = UIView()

        let all = HotwordsStore.shared.items
        guard !all.isEmpty else {
            // 空库要说清怎么办，不能只给一片黑（用户原话「全是黑的啥也没有」）
            let tip = UILabel()
            tip.text = "还没有短语\n在 PhraseKey App 里添加，或用 Scripts/phrase.py 批量导入"
            tip.numberOfLines = 0
            tip.textAlignment = .center
            tip.font = .systemFont(ofSize: 13)
            tip.textColor = Palette.composeText
            container.addSubview(tip)
            tip.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                tip.centerXAnchor.constraint(equalTo: container.centerX),
                tip.centerYAnchor.constraint(equalTo: container.centerY),
                tip.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 16),
                tip.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16),
            ])
            return container
        }

        // ── 类型切换：全部 / 短常用语 / 长文本
        let filterControl = UISegmentedControl(items: ["全部", "短语", "长文本"])
        filterControl.selectedSegmentIndex = phrasePadFilter.rawValue
        filterControl.addTarget(self, action: #selector(phraseFilterChanged(_:)), for: .valueChanged)
        filterControl.setTitleTextAttributes([
            .font: UIFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: Palette.foreground
        ], for: .normal)
        filterControl.setTitleTextAttributes([
            .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: Palette.foreground
        ], for: .selected)

        // ── 分类条 ──
        let catScroll = UIScrollView()
        catScroll.showsHorizontalScrollIndicator = false
        let catStack = UIStackView()
        catStack.axis = .horizontal
        catStack.spacing = 6
        catStack.translatesAutoresizingMaskIntoConstraints = false
        catScroll.addSubview(catStack)
        catScroll.translatesAutoresizingMaskIntoConstraints = false

        for cat in phraseCategories(all) {
            let b = UIButton(type: .system)
            b.setTitle(cat.isEmpty ? "全部" : cat.uppercased(), for: .normal)
            let selected = (phraseCategory ?? "") == cat
            b.setTitleColor(selected ? Palette.foreground : Palette.composeText, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 13, weight: selected ? .semibold : .medium)
            b.backgroundColor = selected ? Palette.keyBackground : Palette.fnKeyBackground
            b.layer.cornerRadius = 6
            b.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
            b.accessibilityHint = cat
            b.addTarget(self, action: #selector(phraseCategoryTapped(_:)), for: .touchUpInside)
            catStack.addArrangedSubview(b)
        }

        // ── 短语列表 ──
        let listScroll = UIScrollView()
        let listStack = UIStackView()
        listStack.axis = .vertical
        listStack.spacing = 4
        listStack.translatesAutoresizingMaskIntoConstraints = false
        listScroll.addSubview(listStack)
        listScroll.translatesAutoresizingMaskIntoConstraints = false

        // 按类型 + 分类双重过滤
        let typeFiltered: [Hotword]
        switch phrasePadFilter {
        case .all: typeFiltered = all
        case .short: typeFiltered = all.filter { !$0.isLongText }
        case .long: typeFiltered = all.filter { $0.isLongText }
        }
        let shown = typeFiltered.filter { hw in
            guard let c = phraseCategory, !c.isEmpty else { return true }
            return hw.key.lowercased().hasPrefix(c)
        }
        for (i, hw) in shown.enumerated() {
            let b = UIButton(type: .system)
            // 简码 + 文本首行，长文本截断但给出足够信息判断是哪条
            let head = hw.key.isEmpty ? "" : "\(hw.key.uppercased())  "
            let oneLine = hw.text.replacingOccurrences(of: "\n", with: " ")
            b.setTitle(head + oneLine, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 14)
            b.titleLabel?.lineBreakMode = .byTruncatingTail
            b.contentHorizontalAlignment = .left
            b.setTitleColor(Palette.foreground, for: .normal)
            b.backgroundColor = Palette.keyBackground
            b.layer.cornerRadius = 6
            b.contentEdgeInsets = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
            b.tag = i
            b.accessibilityValue = hw.text      // 上屏取这里，避免用被截断的 title
            b.addTarget(self, action: #selector(phraseTapped(_:)), for: .touchUpInside)
            listStack.addArrangedSubview(b)
            b.heightAnchor.constraint(equalToConstant: 38).isActive = true
        }

        container.addSubview(filterControl)
        container.addSubview(catScroll)
        container.addSubview(listScroll)
        NSLayoutConstraint.activate([
            filterControl.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            filterControl.centerXAnchor.constraint(equalTo: container.centerX),
            filterControl.widthAnchor.constraint(equalToConstant: 220),
            filterControl.heightAnchor.constraint(equalToConstant: 28),

            catScroll.topAnchor.constraint(equalTo: filterControl.bottomAnchor, constant: 4),
            catScroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            catScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            catScroll.heightAnchor.constraint(equalToConstant: 30),
            catStack.topAnchor.constraint(equalTo: catScroll.topAnchor),
            catStack.bottomAnchor.constraint(equalTo: catScroll.bottomAnchor),
            catStack.leadingAnchor.constraint(equalTo: catScroll.leadingAnchor),
            catStack.trailingAnchor.constraint(equalTo: catScroll.trailingAnchor),

            listScroll.topAnchor.constraint(equalTo: catScroll.bottomAnchor, constant: 4),
            listScroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            listScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            listScroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            listStack.topAnchor.constraint(equalTo: listScroll.topAnchor),
            listStack.bottomAnchor.constraint(equalTo: listScroll.bottomAnchor),
            listStack.leadingAnchor.constraint(equalTo: listScroll.leadingAnchor),
            listStack.trailingAnchor.constraint(equalTo: listScroll.trailingAnchor),
            listStack.widthAnchor.constraint(equalTo: listScroll.widthAnchor),
        ])
        return container
    }

    /// 分类 = 简码首字母。518 条无限滚动找不到东西，按首字母分组最直观
    /// （用户的简码本来就是按内容首字母取的，如 wmd/wrd 都是「我…」开头）。
    private func phraseCategories(_ all: [Hotword]) -> [String] {
        let list: [Hotword]
        switch phrasePadFilter {
        case .all: list = all
        case .short: list = all.filter { !$0.isLongText }
        case .long: list = all.filter { $0.isLongText }
        }
        var set = Set<String>()
        for hw in list {
            if let f = hw.key.lowercased().first, f.isLetter { set.insert(String(f)) }
        }
        return [""] + set.sorted()
    }

    @objc private func phraseCategoryTapped(_ sender: UIButton) {
        let c = sender.accessibilityHint ?? ""
        phraseCategory = c.isEmpty ? nil : c
        rebuildKeys()
    }

    @objc private func phraseFilterChanged(_ sender: UISegmentedControl) {
        phrasePadFilter = PhrasePadFilter(rawValue: sender.selectedSegmentIndex) ?? .all
        phraseCategory = nil // 切换类型时重置分类
        rebuildKeys()
    }

    @objc private func phraseTapped(_ sender: UIButton) {
        guard let text = sender.accessibilityValue, !text.isEmpty else { return }
        textDocumentProxy.insertText(text)
        // 上屏后退出面板：短语通常是一次性长文本，插完就该回到打字状态
        isPhrasePad = false
        rebuildKeys()
        renderCandidates()
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
            // 常用语靠字重区分（semibold），不用彩色
            let isHotword = c.type == "hotword"
            b.setTitleColor(Palette.foreground, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 17, weight: isHotword ? Palette.accentWeight : (i == 0 ? .semibold : .regular))
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
        // 例外 1：分号 ; 是双拼模式下的选词键（选第 2 个）
        // 例外 2：撇号 ' 是双拼选词键（选第 3 个）兼音节分隔符
        // 优先级：选词 > 分隔 > 上屏
        if raw == ";" {
            if let e = engine, e.scheme.isFlypy, e.candidates.count >= 2,
               let text = e.commit(at: 1) {
                textDocumentProxy.insertText(text)
                renderCandidates()
                return
            }
            // 非双拼或候选不足 → 上屏分号
            if let e = engine, !e.composing.isEmpty {
                textDocumentProxy.insertText(e.commitRaw())
            }
            textDocumentProxy.insertText(";")
            return
        }

        // 撇号 '：双拼下选第 3 个；候选不足时当音节分隔符；空串时直接上屏
        if raw == "'" {
            if let e = engine, e.scheme.isFlypy, e.candidates.count >= 3,
               let text = e.commit(at: 2) {
                textDocumentProxy.insertText(text)
                renderCandidates()
                return
            }
            if let e = engine, !e.composing.isEmpty {
                // 作为音节分隔符：计入组词串（引擎层会剥离，但拼音栏显示）
                e.append("'")
                renderCandidates()
                return
            }
            textDocumentProxy.insertText("'")
            return
        }
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
