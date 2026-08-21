import Cocoa

/// PhraseKey Settings Panel: Phrase Manager (Google Material style).
/// Features: list, add, delete, edit key, import phrases from other IMEs.
final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {

    private let store = HotwordsStore.shared
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private var keyField = NSTextField()
    private var textField = NSTextField()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        window.title = "PhraseKey · Phrase Manager"
        window.center()
        self.init(window: window)
        buildUI()
        reloadData()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        // 输入方案选择
        let schemeLabel = NSTextField(labelWithString: "Input Scheme:")
        schemeLabel.frame = NSRect(x: 16, y: 468, width: 80, height: 22)
        content.addSubview(schemeLabel)

        let schemePop = NSPopUpButton(frame: NSRect(x: 100, y: 464, width: 180, height: 26))
        schemePop.addItems(withTitles: InputScheme.allCases.map { $0.rawValue })
        schemePop.selectItem(withTitle: AppSettings.current.scheme.rawValue)
        schemePop.target = self
        schemePop.action = #selector(schemeChanged(_:))
        schemePop.tag = 100
        content.addSubview(schemePop)

        let schemeTip = NSTextField(labelWithString: "Xingma = Shuangpin + shape codes (requires xingma.tsv)")
        schemeTip.font = .systemFont(ofSize: 11)
        schemeTip.textColor = .secondaryLabelColor
        schemeTip.frame = NSRect(x: 292, y: 468, width: 380, height: 20)
        content.addSubview(schemeTip)

        // 顶部说明
        let tip = NSTextField(labelWithString: "Phrases = type a key (shortcut) to insert long text instantly. Compatible with mainstream IME formats.")
        tip.font = .systemFont(ofSize: 12)
        tip.textColor = .secondaryLabelColor
        tip.frame = NSRect(x: 16, y: 436, width: 688, height: 20)
        content.addSubview(tip)

        // 工具栏：添加 / 导入
        let addBtn = NSButton(title: "+ Add", target: self, action: #selector(addPressed))
        addBtn.frame = NSRect(x: 16, y: 396, width: 90, height: 28)
        content.addSubview(addBtn)

        let importBtn = NSButton(title: "Import Phrases…", target: self, action: #selector(importPressed))
        importBtn.frame = NSRect(x: 116, y: 396, width: 110, height: 28)
        content.addSubview(importBtn)

        let delBtn = NSButton(title: "Delete", target: self, action: #selector(deletePressed))
        delBtn.frame = NSRect(x: 236, y: 396, width: 90, height: 28)
        content.addSubview(delBtn)

        // 表格
        let colKey = NSTableColumn(identifier: .init("key"))
        colKey.title = "Key"
        colKey.width = 90
        let colText = NSTableColumn(identifier: .init("text"))
        colText.title = "Phrase"
        colText.width = 500
        tableView.addTableColumn(colKey)
        tableView.addTableColumn(colText)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 30

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.frame = NSRect(x: 16, y: 80, width: 688, height: 308)
        scrollView.autoresizingMask = [.width, .height]
        content.addSubview(scrollView)

        // 底部编辑区：简码 + 内容
        let keyLabel = NSTextField(labelWithString: "Key:")
        keyLabel.frame = NSRect(x: 16, y: 44, width: 46, height: 20)
        content.addSubview(keyLabel)
        keyField.placeholderString = "your shortcut (3-6 chars)"
        keyField.frame = NSRect(x: 64, y: 42, width: 110, height: 24)
        content.addSubview(keyField)

        let textLabel = NSTextField(labelWithString: "Text:")
        textLabel.frame = NSRect(x: 184, y: 44, width: 46, height: 20)
        content.addSubview(textLabel)
        textField.placeholderString = "your phrase text (multiline)"
        textField.frame = NSRect(x: 232, y: 42, width: 360, height: 24)
        content.addSubview(textField)

        let saveBtn = NSButton(title: "Save", target: self, action: #selector(saveCurrent))
        saveBtn.frame = NSRect(x: 600, y: 40, width: 104, height: 28)
        content.addSubview(saveBtn)
    }

    private func reloadData() {
        store.load()
        tableView.reloadData()
    }

    // MARK: - Actions

    @objc private func schemeChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.titleOfSelectedItem,
              let scheme = InputScheme(rawValue: raw) else { return }
        AppSettings.current.scheme = scheme
        AppSettings.save()
    }

    @objc private func addPressed() {
        store.add(text: textField.stringValue.isEmpty ? "新常用语" : textField.stringValue,
                  key: keyField.stringValue)
        reloadData()
    }

    @objc private func deletePressed() {
        let row = tableView.selectedRow
        guard row >= 0, row < store.items.count else { return }
        store.remove(id: store.items[row].hw_id)
        reloadData()
    }

    @objc private func saveCurrent() {
        let row = tableView.selectedRow
        guard row >= 0, row < store.items.count else {
            // 未选中：直接新增
            addPressed(); return
        }
        store.update(id: store.items[row].hw_id,
                     text: textField.stringValue,
                     key: keyField.stringValue)
        reloadData()
    }

    @objc private func importPressed() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .commaSeparatedText]
        panel.message = "选择从其他输入法导出的常用语文件（CSV/JSON）"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let n = url.pathExtension.lowercased() == "json"
            ? store.importFromJSON(url: url)
            : store.importFromCSV(url: url)
        let alert = NSAlert()
        alert.messageText = "Import Complete"
        alert.informativeText = "Imported \(n) phrases."
        alert.runModal()
        reloadData()
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { store.items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = tableColumn?.identifier.rawValue ?? ""
        let cell = NSTextField(labelWithString: "")
        cell.lineBreakMode = .byTruncatingTail
        if id == "key" {
            cell.stringValue = store.items[row].key
        } else {
            cell.stringValue = store.items[row].text.replacingOccurrences(of: "\n", with: " ⏎ ")
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, row < store.items.count else { return }
        keyField.stringValue = store.items[row].key
        textField.stringValue = store.items[row].text
    }

    // MARK: - Static Entry

    static func show() {
        let c = SettingsWindowController()
        c.showWindow(nil)
        c.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // 保持引用（简化：用 App 级持有，避免被释放）
        SettingsWindowController.shared = c
    }

    static var shared: SettingsWindowController?
}
