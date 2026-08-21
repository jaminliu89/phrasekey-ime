import Cocoa
import InputMethodKit

// PhraseKey IME process entry: starts IMKServer and stays in RunLoop.
// The system launches this process as an IMKServer, providing the controller and candidate UI.

let connectionName = "PhraseKey_Connection"

// 保持强引用避免被释放
var server: IMKServer?

// bundleIdentifier 在 .app 内为 PhraseKey 的 bundle id；调试裸跑时给个默认值
let bundleID = Bundle.main.bundleIdentifier ?? "com.phrasekey.ime"
server = IMKServer(name: connectionName, bundleIdentifier: bundleID)

// 让设置窗口能独立出现
NSApplication.shared.setActivationPolicy(.accessory)

print("PhraseKey IME started (server=\(String(describing: server != nil)))")

RunLoop.current.run()
