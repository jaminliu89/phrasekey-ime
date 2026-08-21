import SwiftUI

/// PhraseKey Host App：引导启用键盘 + 常用语数据预览。
/// 数据与键盘扩展共享 App Group 容器（group.com.phrasekey.ime）。
@main
struct PhraseKeyHostApp: App {
    init() {
        // 数据目录指向 App Group 容器
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.phrasekey.ime") {
            PhraseKeySettings.overrideDefaultDir = container.appendingPathComponent("PhraseKey")
            AppSettings.current = PhraseKeySettings.load()
        }
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }
}

struct HomeView: View {
    @State private var hotwords: [Hotword] = []
    @State private var scheme = AppSettings.current.scheme

    var body: some View {
        NavigationView {
            List {
                Section("启用步骤") {
                    Label("设置 → 通用 → 键盘 → 添加新键盘 → PhraseKey", systemImage: "keyboard")
                    Label("开启「允许完全访问」以支持完整功能", systemImage: "lock.open")
                    Label("数据与 macOS 版通过 iCloud/同步目录互通", systemImage: "arrow.triangle.2.circlepath")
                }
                Section("输入方案") {
                    Picker("方案", selection: $scheme) {
                        ForEach(InputScheme.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .onChange(of: scheme) { newValue in
                        AppSettings.current.scheme = newValue
                        AppSettings.save()
                    }
                }
                Section("常用语（\(hotwords.count) 条）") {
                    ForEach(hotwords.prefix(30), id: \.hw_id) { hw in
                        VStack(alignment: .leading, spacing: 4) {
                            if !hw.key.isEmpty {
                                Text("简码 \(hw.key)").font(.caption).foregroundColor(.blue)
                            }
                            Text(hw.text).font(.body).lineLimit(2)
                        }
                    }
                }
            }
            .navigationTitle("PhraseKey")
            .onAppear { hotwords = HotwordsStore.shared.items }
        }
    }
}
