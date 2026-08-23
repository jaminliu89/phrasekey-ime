import Cocoa

/// 常用语面板：列表展示所有常用语，点击直接插入到当前输入框。
/// 对标微信键盘左上角「常用语」入口：浏览式调用，不需要记简码。
final class PhrasesPanelController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {

    private let store = HotwordsStore.shared
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let searchField = NSSearchField()
    private var filtered: [Hotword] = []

    /// 显示过滤：全部 / 短常用语 / 长文本
    /// 长文本不参与打字候选，只在面板里手动浏览和插入。
    private enum Filter: Int {
        case all = 0
        case short = 1
        case long = 2
    }
    private var filter: Filter = .all

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "PhraseKey · 常用语"
        window.center()
        self.init(window: window)
        buildUI()
        reloadData()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        // 搜索框
        searchField.frame = NSRect(x: 16, y: 480, width: 300, height: 28)
        searchField.placeholderString = "搜索常用语..."
        searchField.target = self
        searchField.action = #selector(searchChanged)
        content.addSubview(searchField)

        // 类型切换：全部 / 短常用语 / 长文本
        let seg = NSSegmentedControl(labels: ["全部", "短语", "长文本"],
                                     trackingMode: .selectOne,
                                     target: self,
                                     action: #selector(filterChanged(_:)))
        seg.frame = NSRect(x: 326, y: 480, width: 140, height: 28)
        seg.selectedSegment = filter.rawValue
        seg.tag = 201
        content.addSubview(seg)

        // 提示
        let tip = NSTextField(labelWithString: "双击或按回车插入到当前输入框")
        tip.font = .systemFont(ofSize: 11)
        tip.textColor = .secondaryLabelColor
        tip.frame = NSRect(x: 16, y: 456, width: 300, height: 16)
        content.addSubview(tip)

        // 数量
        let countLabel = NSTextField(labelWithString: "")
        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right
        countLabel.frame = NSRect(x: 320, y: 456, width: 144, height: 16)
        countLabel.tag = 99
        content.addSubview(countLabel)

        // 表格
        let colText = NSTableColumn(identifier: .init("text"))
        colText.title = "Phrase"
        colText.width = 350
        let colKey = NSTableColumn(identifier: .init("key"))
        colKey.title = "Key"
        colKey.width = 100
        tableView.addTableColumn(colText)
        tableView.addTableColumn(colKey)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 36
        tableView.target = self
        tableView.doubleAction = #selector(rowDoubleClicked)
        tableView.intercellSpacing = NSSize(width: 0, height: 4)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.frame = NSRect(x: 16, y: 56, width: 448, height: 388)
        scrollView.autoresizingMask = [.width, .height]
        content.addSubview(scrollView)

        // 底部按钮
        let addBtn = NSButton(title: "从剪贴板添加", target: self, action: #selector(addFromClipboard))
        addBtn.frame = NSRect(x: 16, y: 16, width: 120, height: 28)
        content.addSubview(addBtn)

        let delBtn = NSButton(title: "删除", target: self, action: #selector(deleteSelected))
        delBtn.frame = NSRect(x: 144, y: 16, width: 80, height: 28)
        content.addSubview(delBtn)
    }

    private func reloadData() {
        let q = searchField.stringValue.lowercased().trimmingCharacters(in: .whitespaces)
        var items = store.items
        // 类型过滤
        switch filter {
        case .short: items = items.filter { !$0.isLongText }
        case .long: items = items.filter { $0.isLongText }
        case .all: break
        }
        if q.isEmpty {
            filtered = items
        } else {
            filtered = items.filter {
                $0.text.localizedCaseInsensitiveContains(q) ||
                $0.key.lowercased().contains(q)
            }
        }
        tableView.reloadData()
        // 更新数量
        if let countLabel = window?.contentView?.viewWithTag(99) as? NSTextField {
            countLabel.stringValue = "\(filtered.count) / \(store.items.count) 条"
        }
    }

    // MARK: - Actions

    @objc private func searchChanged() {
        reloadData()
    }

    @objc private func filterChanged(_ sender: NSSegmentedControl) {
        filter = Filter(rawValue: sender.selectedSegment) ?? .all
        reloadData()
    }

    @objc private func rowDoubleClicked() {
        insertSelected()
    }

    private func insertSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < filtered.count else { return }
        let hw = filtered[row]
        // 插入到当前应用的输入框（通过系统粘贴板模拟粘贴）
        insertText(hw.text)
        // 关窗
        window?.close()
    }

    /// 将文本插入到当前活跃应用的输入框：模拟 Cmd+V 粘贴
    private func insertText(_ text: String) {
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.pasteboardItems?.map { $0.string(forType: .string) ?? "" } ?? []
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 模拟 Cmd+V
        let source = CGEventSource(stateID: .combinedSessionState)
        let vkey: CGKeyCode = 9 // v 键
        let down = CGEvent(keyboardEventSource: source, virtualKey: vkey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vkey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)

        // 恢复粘贴板（延迟，等粘贴完成）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            pasteboard.clearContents()
            for s in oldContents {
                pasteboard.setString(s, forType: .string)
            }
        }
    }

    @objc private func addFromClipboard() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        guard !text.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "剪贴板为空"
            alert.informativeText = "先复制一段文字再来添加。"
            alert.runModal()
            return
        }
        // 自动生成简码：前 4 个汉字拼音首字母
        let key = PinyinSyllable.initials(String(text.prefix(8))).prefix(4).lowercased()
        let hw = store.add(text: text, key: String(key))
        reloadData()
        // 选中刚加的
        if let idx = filtered.firstIndex(where: { $0.hw_id == hw.hw_id }) {
            tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
            tableView.scrollRowToVisible(idx)
        }
    }

    @objc private func deleteSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < filtered.count else { return }
        let hw = filtered[row]
        store.remove(id: hw.hw_id)
        reloadData()
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = tableColumn?.identifier.rawValue ?? ""
        let hw = filtered[row]
        let cell = NSTextField(labelWithString: "")
        cell.lineBreakMode = .byTruncatingTail
        cell.font = .systemFont(ofSize: 13)
        if id == "key" {
            cell.stringValue = hw.key
            cell.textColor = .systemBlue
            cell.font = .systemFont(ofSize: 12, weight: .medium)
        } else {
            // 长文本：显示前 60 字符，换行替换成 ↵
            let display = hw.text.replacingOccurrences(of: "\n", with: " ↵ ")
            cell.stringValue = String(display.prefix(60)) + (display.count > 60 ? "…" : "")
            cell.toolTip = hw.text
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { true }

    // MARK: - Static

    static func show() {
        let c = PhrasesPanelController()
        c.showWindow(nil)
        c.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        PhrasesPanelController.shared = c
    }

    static var shared: PhrasesPanelController?
}
