import Cocoa
import InputMethodKit

/// IMKServer 委托：提供输入法菜单（右键候选/输入法栏可见）。
/// Info.plist 的 InputMethodServerDelegateClass 指向本类。
/// 注：IMKServerDelegate 在 Swift 中不可见，系统通过 ObjC 动态派发调用 menu()，
///     故这里仅继承 NSObject 并暴露 @objc 方法。
final class PhraseKeyServerDelegate: NSObject {

    /// 输入法菜单（显示在输入法切换栏/候选窗右键）
    func menu() -> NSMenu! {
        let m = NSMenu(title: "PhraseKey")

        // 输入方案切换
        let schemeMenu = NSMenu(title: "输入方案")
        for s in InputScheme.allCases {
            let item = NSMenuItem(title: s.rawValue, action: #selector(switchScheme(_:)), keyEquivalent: "")
            item.tag = InputScheme.allCases.firstIndex(of: s) ?? 0
            item.state = (s == AppSettings.current.scheme) ? .on : .off
            item.target = self
            schemeMenu.addItem(item)
        }
        let schemeItem = NSMenuItem(title: "输入方案", action: nil, keyEquivalent: "")
        schemeItem.submenu = schemeMenu
        m.addItem(schemeItem)

        m.addItem(.separator())

        let settings = NSMenuItem(title: "PhraseKey 设置…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        m.addItem(settings)

        let importItem = NSMenuItem(title: "导入 WeType 常用语…", action: #selector(importWeType), keyEquivalent: "")
        importItem.target = self
        m.addItem(importItem)

        m.addItem(.separator())

        let about = NSMenuItem(title: "PhraseKey IME · 开源 · 常用语优先", action: nil, keyEquivalent: "")
        m.addItem(about)

        return m
    }

    @objc private func switchScheme(_ sender: NSMenuItem) {
        let idx = sender.tag
        guard InputScheme.allCases.indices.contains(idx) else { return }
        AppSettings.current.scheme = InputScheme.allCases[idx]
        AppSettings.save()
    }

    @objc private func openSettings() {
        SettingsWindowController.show()
    }

    @objc private func importWeType() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["json", "csv"]
        panel.message = "选择从微信输入法导出的常用语文件（CSV/JSON）"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let n = url.pathExtension.lowercased() == "json"
            ? HotwordsStore.shared.importFromWeTypeJSON(url: url)
            : HotwordsStore.shared.importFromWeTypeCSV(url: url)
        let alert = NSAlert()
        alert.messageText = "导入完成"
        alert.informativeText = "已导入 \(n) 条常用语。"
        alert.runModal()
    }
}
