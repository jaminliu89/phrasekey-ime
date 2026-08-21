import SwiftUI

/// PhraseKey Host App: keyboard setup guide + phrase preview.
/// Data local to the keyboard sandbox (free Apple ID: no App Group, no cross-process sharing).
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

    var body: some View {
        NavigationView {
            List {
                Section("Setup Guide") {
                    Label("Settings → General → Keyboard → Add New Keyboard → PhraseKey", systemImage: "keyboard")
                    Label("Enable Full Access for complete features", systemImage: "lock.open")
                    Label("Data syncs with macOS via iCloud / shared directory", systemImage: "arrow.triangle.2.circlepath")
                }
                Section("Input Scheme") {
                    Picker("Scheme", selection: $scheme) {
                        ForEach(InputScheme.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .onChange(of: scheme) { newValue in
                        AppSettings.current.scheme = newValue
                        AppSettings.save()
                    }
                }
                Section("Phrases (\(hotwords.count) items)") {
                    ForEach(hotwords.prefix(30), id: \.hw_id) { hw in
                        VStack(alignment: .leading, spacing: 4) {
                            if !hw.key.isEmpty {
                                Text("Key: \(hw.key)").font(.caption).foregroundColor(.blue)
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