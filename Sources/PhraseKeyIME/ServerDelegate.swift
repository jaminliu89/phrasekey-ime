import Cocoa
import InputMethodKit

/// IMKServer delegate: provides the IME menu (right-click / menu bar).
/// Referenced by Info.plist InputMethodServerDelegateClass.
/// Note: IMKServerDelegate is not exposed in Swift; the system calls menu()
///       via ObjC dynamic dispatch, so we just subclass NSObject + @objc methods.
final class PhraseKeyServerDelegate: NSObject {

    /// 输入法菜单（显示在输入法切换栏/候选窗右键）
    func menu() -> NSMenu! {
        let m = NSMenu(title: "PhraseKey")

        // 输入方案切换
        let schemeMenu = NSMenu(title: "Input Scheme")
        for s in InputScheme.allCases {
            let item = NSMenuItem(title: s.rawValue, action: #selector(switchScheme(_:)), keyEquivalent: "")
            item.tag = InputScheme.allCases.firstIndex(of: s) ?? 0
            item.state = (s == AppSettings.current.scheme) ? .on : .off
            item.target = self
            schemeMenu.addItem(item)
        }
        let schemeItem = NSMenuItem(title: "Input Scheme", action: nil, keyEquivalent: "")
        schemeItem.submenu = schemeMenu
        m.addItem(schemeItem)

        m.addItem(.separator())

        let settings = NSMenuItem(title: "PhraseKey Settings…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        m.addItem(settings)

        let importItem = NSMenuItem(title: "导入常用语…", action: #selector(importHotwords), keyEquivalent: "")
        importItem.target = self
        m.addItem(importItem)

        m.addItem(.separator())

        let about = NSMenuItem(title: "PhraseKey IME · Open Source · Phrases First", action: nil, keyEquivalent: "")
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

    @objc private func importHotwords() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .commaSeparatedText]
        panel.message = "Select phrase export file from another IME (CSV/JSON)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let n = url.pathExtension.lowercased() == "json"
            ? HotwordsStore.shared.importFromJSON(url: url)
            : HotwordsStore.shared.importFromCSV(url: url)
        let alert = NSAlert()
        alert.messageText = "Import Complete"
        alert.informativeText = "Imported \(n) phrases."
        alert.runModal()
    }
}
