import SwiftUI

/// PhraseKey 宿主 App 首页：设置引导 + 输入方案 + 常用语管理。
/// 常用语通过 App Group 共享给键盘扩展。
@main
struct PhraseKeyHostApp: App {
    init() {
        // Point data directory to App Group container (shared with keyboard)
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
    @State private var showAddSheet = false
    @State private var editingHotword: Hotword?
    @State private var searchText = ""

    var body: some View {
        NavigationView {
            List {
                setupSection
                schemeSection
                phrasesSection
            }
            .navigationTitle("PhraseKey")
            .searchable(text: $searchText, prompt: "Search phrases...")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        editingHotword = nil
                        showAddSheet = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddPhraseView(hotword: editingHotword) {
                    refresh()
                }
            }
            .onAppear { refresh() }
        }
    }

    // MARK: - 引导

    private var setupSection: some View {
        Section("Setup Guide") {
            Label("Settings → General → Keyboard → Add New Keyboard → PhraseKey", systemImage: "keyboard")
            Label("Enable Full Access for complete features", systemImage: "lock.open")
            Label("Data syncs with macOS via iCloud / shared directory", systemImage: "arrow.triangle.2.circlepath")
        }
    }

    // MARK: - 输入方案

    private var schemeSection: some View {
        Section("Input Scheme") {
            Picker("Scheme", selection: $scheme) {
                ForEach(InputScheme.allCases, id: \.self) { s in
                    Text(s.displayName).tag(s)
                }
            }
            .onChange(of: scheme) { newValue in
                AppSettings.current.scheme = newValue
                AppSettings.save()
            }
        }
    }

    // MARK: - 常用语

    private var phrasesSection: some View {
        Section("Phrases (\(filtered.count) items)") {
            if filtered.isEmpty && !searchText.isEmpty {
                Text("No results")
                    .foregroundColor(.secondary)
            }
            ForEach(filtered, id: \.hw_id) { hw in
                Button {
                    editingHotword = hw
                    showAddSheet = true
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        if !hw.key.isEmpty {
                            Text("Key: \(hw.key)")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        Text(hw.text)
                            .font(.body)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                    }
                }
            }
            .onDelete(perform: delete)
        }
    }

    private var filtered: [Hotword] {
        let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return hotwords }
        return hotwords.filter {
            $0.text.localizedCaseInsensitiveContains(q) ||
            $0.key.lowercased().contains(q)
        }
    }

    private func refresh() {
        hotwords = HotwordsStore.shared.items
    }

    private func delete(at offsets: IndexSet) {
        for idx in offsets {
            guard idx < hotwords.count else { continue }
            HotwordsStore.shared.remove(id: hotwords[idx].hw_id)
        }
        refresh()
    }
}

// MARK: - 添加/编辑常用语

struct AddPhraseView: View {
    @Environment(\.dismiss) private var dismiss
    let hotword: Hotword?
    let onSave: () -> Void

    @State private var keyText = ""
    @State private var phraseText = ""
    @State private var showPasteAlert = false

    var body: some View {
        NavigationView {
            Form {
                Section("Key (shortcut)") {
                    TextField("e.g. jtj (auto-generated if empty)", text: $keyText)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                Section("Phrase") {
                    TextEditor(text: $phraseText)
                        .frame(minHeight: 120)
                        .font(.body)
                }

                Section {
                    Button {
                        if let paste = UIPasteboard.general.string {
                            phraseText = paste
                            if keyText.isEmpty {
                                keyText = String(PinyinSyllable.initials(String(paste.prefix(8))).prefix(4)).lowercased()
                            }
                        }
                    } label: {
                        Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                    }
                }
            }
            .navigationTitle(hotword == nil ? "Add Phrase" : "Edit Phrase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(phraseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let hw = hotword {
                    keyText = hw.key
                    phraseText = hw.text
                }
            }
        }
    }

    private func save() {
        let text = phraseText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let key = keyText.trimmingCharacters(in: .whitespaces).lowercased()

        if let hw = hotword {
            HotwordsStore.shared.update(id: hw.hw_id, text: text, key: key)
        } else {
            HotwordsStore.shared.add(text: text, key: key)
        }
        onSave()
        dismiss()
    }
}

// MARK: - InputScheme 显示名

extension InputScheme {
    var displayName: String {
        switch self {
        case .pinyin: return "Pinyin"
        case .flypy: return "Xiaohe Shuangpin"
        case .flypyXing: return "Xiaohe Xingma"
        }
    }
}
