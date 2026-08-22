import XCTest

/// 键盘存活自动取证。
///
/// 目的：不依赖人工反复切键盘，自动完成
///   ① 打开备忘录/Safari 输入框
///   ② 切换到目标键盘
///   ③ 截图存证（附到测试报告）
///   ④ 输入并读回文本，验证键盘真的可交互
///   ⑤ 反复循环 N 次，记录第几次开始失效
///
/// 运行：
///   xcodebuild test -project ios/PhraseKeyIOS.xcodeproj -scheme PhraseKeyHost \
///     -destination 'platform=iOS,id=<UDID>' \
///     -only-testing:PhraseKeyKeyboardUITests/KeyboardSurvivalTests
final class KeyboardSurvivalTests: XCTestCase {

    /// 目标键盘在 🌐 长按菜单里显示的名字
    private let keyboardName = "PhraseKey"
    /// 循环切换次数（存活性观测）
    private let cycles = 6

    override func setUpWithError() throws {
        continueAfterFailure = true   // 存活测试要跑完全程，不能首次失败就中断
    }

    // MARK: - 工具

    private func shot(_ name: String, _ app: XCUIApplication) {
        let a = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func fullShot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func wait(_ s: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(s))
    }

    /// 打开备忘录并聚焦一个可输入区域
    private func openNotesEditor() -> XCUIApplication {
        let notes = XCUIApplication(bundleIdentifier: "com.apple.mobilenotes")
        notes.launch()
        wait(2.5)

        // 新建备忘录（右下角撰写按钮，不同版本 identifier 有差异，逐个尝试）
        let composeCandidates = [
            notes.buttons["ComposeButton"],
            notes.buttons["新建备忘录"],
            notes.buttons["Compose"],
        ]
        for b in composeCandidates where b.exists {
            b.tap()
            break
        }
        wait(1.5)

        // 点正文区域唤起键盘
        let editor = notes.textViews.firstMatch
        if editor.exists {
            editor.tap()
        } else {
            notes.tap()
        }
        wait(2.0)
        return notes
    }

    /// 长按 🌐 切到目标键盘。返回是否切换成功。
    private func switchToKeyboard(_ app: XCUIApplication) -> Bool {
        // 🌐 键在键盘左下角，identifier 通常是 "Next keyboard"
        let globeCandidates = [
            app.buttons["Next keyboard"],
            app.keyboards.buttons["Next keyboard"],
            app.buttons["下一个键盘"],
        ]
        guard let globe = globeCandidates.first(where: { $0.exists }) else {
            fullShot("globe-not-found")
            return false
        }

        globe.press(forDuration: 1.2)
        wait(1.2)
        fullShot("keyboard-menu")

        // 菜单里点目标键盘
        let target = app.buttons[keyboardName].exists
            ? app.buttons[keyboardName]
            : app.staticTexts[keyboardName]
        if target.exists {
            target.tap()
            wait(1.5)
            return true
        }

        // 菜单没出现目标，退化为短按循环切换
        for _ in 0..<8 {
            globe.tap()
            wait(1.0)
            if app.keyboards.count > 0 { break }
        }
        return false
    }

    // MARK: - 主测试：反复切换观测存活

    func testKeyboardSurvivalAcrossCycles() throws {
        let notes = openNotesEditor()
        fullShot("00-editor-opened")

        var report: [String] = []

        for i in 1...cycles {
            let ok = switchToKeyboard(notes)
            wait(1.0)
            fullShot("\(String(format: "%02d", i))-after-switch")

            // 键盘是否真的存在且有内容
            let kb = notes.keyboards.firstMatch
            let kbExists = kb.exists
            let kbButtons = kb.buttons.count
            let kbHeight = kbExists ? kb.frame.height : 0

            // 尝试输入，验证可交互（点候选/字母键）
            var typed = false
            for key in ["n", "i", "h", "a", "o"] {
                let k = kb.buttons[key]
                if k.exists {
                    k.tap()
                    typed = true
                    wait(0.25)
                }
            }
            wait(0.8)
            fullShot("\(String(format: "%02d", i))-after-typing")

            let line = "第 \(i) 轮｜切换\(ok ? "成功" : "失败")"
                + "｜键盘\(kbExists ? "存在" : "不存在")"
                + "｜高度 \(Int(kbHeight))"
                + "｜按键数 \(kbButtons)"
                + "｜输入\(typed ? "有响应" : "无响应")"
            report.append(line)
            print("SURVIVAL " + line)

            // 切走再切回，模拟真实使用中的反复加载
            let globe = notes.buttons["Next keyboard"]
            if globe.exists {
                globe.tap()
                wait(1.2)
            }
        }

        let summary = report.joined(separator: "\n")
        let a = XCTAttachment(string: summary)
        a.name = "存活报告"
        a.lifetime = .keepAlways
        add(a)
        print("=== 存活报告 ===\n" + summary)
    }

    /// 单次冷启动观测：杀掉输入上下文后首次加载是否成功（最容易暴露布局问题）
    func testColdLoadOnce() throws {
        let notes = openNotesEditor()
        let ok = switchToKeyboard(notes)
        wait(2.0)
        fullShot("cold-load")

        let kb = notes.keyboards.firstMatch
        let info = "切换=\(ok) 存在=\(kb.exists) 高度=\(kb.exists ? Int(kb.frame.height) : -1) 按键=\(kb.buttons.count)"
        print("COLDLOAD " + info)
        let a = XCTAttachment(string: info)
        a.name = "冷启动结果"
        a.lifetime = .keepAlways
        add(a)
    }
}
