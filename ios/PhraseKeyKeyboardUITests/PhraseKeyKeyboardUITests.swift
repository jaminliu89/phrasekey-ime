import XCTest

/// 完整自动化：在设备上自动完成
/// 1. 设置 → 键盘 → 添加 PhraseKey（若未添加）
/// 2. PhraseKey → 打开「允许完全访问」
/// 3. Safari 输入框 → 切到 PhraseKey 键盘
/// 4. 输入 nihao → 验证候选出现
final class PhraseKeyKeyboardUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func waitFor(_ element: XCUIElement, timeout: TimeInterval = 6) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        return element.exists
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8) -> Bool {
        if element.exists { return true }
        for _ in 0..<maxSwipes {
            app.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            if element.exists { return true }
        }
        return element.exists
    }

    private func backToRoot(_ settings: XCUIApplication) {
        for _ in 0..<6 {
            let back = settings.navigationBars.buttons.element(boundBy: 0)
            if back.exists {
                back.tap()
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            } else {
                break
            }
        }
    }

    func testFullSetupAndType() throws {
        // ========== 1) 设置：确保 PhraseKey 已添加 ==========
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        backToRoot(settings)

        let general = settings.staticTexts["通用"].firstMatch
        if waitFor(general, timeout: 3) { general.tap() }
        let keyboardRow = settings.staticTexts["键盘"].firstMatch
        _ = scrollTo(keyboardRow, in: settings)
        if keyboardRow.exists { keyboardRow.tap() }
        let keyboardsRow = settings.cells.staticTexts["键盘"].firstMatch
        _ = scrollTo(keyboardsRow, in: settings)
        if keyboardsRow.exists { keyboardsRow.tap() }
        RunLoop.current.run(until: Date().addingTimeInterval(1))

        // 如果没有 PhraseKey → 添加
        if !settings.staticTexts["PhraseKey"].exists {
            let addBtnText = settings.staticTexts["添加新键盘"].firstMatch
            let addBtnButton = settings.buttons["添加新键盘"].firstMatch
            let addBtn: XCUIElement = waitFor(addBtnButton, timeout: 2) ? addBtnButton : addBtnText
            if waitFor(addBtn) {
                addBtn.tap()
                let pk = settings.staticTexts["PhraseKey"].firstMatch
                if waitFor(pk) {
                    pk.tap()
                    RunLoop.current.run(until: Date().addingTimeInterval(1))
                }
                backToRoot(settings)
                // 重新导航到键盘列表确认
                let g2 = settings.staticTexts["通用"].firstMatch
                if waitFor(g2, timeout: 3) { g2.tap() }
                let kr2 = settings.staticTexts["键盘"].firstMatch
                _ = scrollTo(kr2, in: settings)
                if kr2.exists { kr2.tap() }
                let kk2 = settings.cells.staticTexts["键盘"].firstMatch
                _ = scrollTo(kk2, in: settings)
                if kk2.exists { kk2.tap() }
                RunLoop.current.run(until: Date().addingTimeInterval(1))
            }
        }

        // ========== 2) 打开 PhraseKey 的「允许完全访问」 ==========
        let pkRow = settings.staticTexts["PhraseKey"].firstMatch
        if waitFor(pkRow, timeout: 3) {
            pkRow.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(1))
            for sw in settings.switches.allElementsBoundByIndex {
                if sw.label.contains("完全访问") || sw.label.contains("Full Access") {
                    if sw.value as? String == "0" {
                        sw.tap()
                        RunLoop.current.run(until: Date().addingTimeInterval(1))
                    }
                    break
                }
            }
        }
        let shotSetup = XCTAttachment(screenshot: settings.screenshot())
        shotSetup.name = "full-access-setup"
        shotSetup.lifetime = .keepAlways
        add(shotSetup)

        // ========== 3) Safari：切到 PhraseKey 键盘 ==========
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.launch()
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        let field = safari.textFields.firstMatch
        XCTAssertTrue(waitFor(field), "Safari 地址栏未找到")
        field.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(2))

        func isPhraseKey() -> Bool {
            safari.buttons["双拼"].exists || safari.buttons["全拼"].exists
                || safari.buttons["音形"].exists || safari.buttons["空格"].exists
        }

        var switched = isPhraseKey()
        for _ in 0..<12 where !switched {
            let allow = safari.alerts.buttons["允许"].firstMatch
            if allow.exists { allow.tap(); RunLoop.current.run(until: Date().addingTimeInterval(1)) }
            let next = safari.buttons["下一个键盘"].firstMatch
            if !next.exists { break }
            next.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(1.5))
            switched = isPhraseKey()
        }
        XCTAssertTrue(switched, "未能切换到 PhraseKey 键盘")

        // ========== 4) 输入 nihao，验证候选出现 ==========
        safari.typeText("nihao")
        RunLoop.current.run(until: Date().addingTimeInterval(2))

        let shot = XCTAttachment(screenshot: safari.screenshot())
        shot.name = "phrasekey-typing"
        shot.lifetime = .keepAlways
        add(shot)

        // 候选条出现（PhraseKey 候选是按钮/文本，找任何含字的候选）
        let hasCandidates = safari.buttons["你好"].exists
            || safari.buttons["你好。"].exists
            || safari.staticTexts["你好"].exists
        XCTAssertTrue(hasCandidates, "输入 nihao 后候选条未出现候选词")
    }
}
