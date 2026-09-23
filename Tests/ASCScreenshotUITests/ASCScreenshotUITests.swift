import XCTest

/// One-shot ASC screenshot capture for Simulator (not a product regression suite).
final class ASCScreenshotUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureASCScreenshots() throws {
        let env = ProcessInfo.processInfo.environment
        let vaultPath = env["ASC_VAULT_PATH"]
            ?? "/Users/guille/dev/cryptomako-ios/fixtures/vault"
        let passwordFile = env["ASC_PASSWORD_FILE"]
            ?? "/Users/guille/dev/cryptomako-ios/fixtures/PASSWORD"
        let outDir = env["ASC_OUT_DIR"]
            ?? "/Users/guille/dev/cryptomako-ios/docs/asc-screenshots"
        let prefix = env["ASC_PREFIX"] ?? "69"

        let password = (try? String(contentsOfFile: passwordFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        XCTAssertFalse(password.isEmpty, "Could not read password from \(passwordFile)")

        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let nav = app.navigationBars["CryptoMako"]
        XCTAssertTrue(nav.waitForExistence(timeout: 15), "App did not show CryptoMako nav")

        // Prefer S3 form for marketing unlock shot
        let s3 = app.buttons["S3 (HTTPS)"]
        if s3.waitForExistence(timeout: 5) { s3.tap() }
        Thread.sleep(forTimeInterval: 0.5)
        saveShot(dir: outDir, name: "\(prefix)-01-unlock.png")

        // Switch to Local fixtures (path may already be seeded)
        let local = app.buttons["Local fixtures"]
        XCTAssertTrue(local.waitForExistence(timeout: 5))
        local.tap()

        let pathField = app.textFields["Absolute path to vault/"]
        XCTAssertTrue(pathField.waitForExistence(timeout: 5))
        let current = (pathField.value as? String) ?? ""
        if current != vaultPath {
            replaceText(in: pathField, with: vaultPath, app: app)
        }

        let pw = app.secureTextFields["Password"]
        XCTAssertTrue(pw.waitForExistence(timeout: 5))
        replaceText(in: pw, with: password, app: app)

        dismissKeyboard(app)
        Thread.sleep(forTimeInterval: 0.3)
        saveShot(dir: outDir, name: "\(prefix)-01b-unlock-fixtures.png")

        let unlock = app.buttons["Unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 3))
        XCTAssertTrue(unlock.isEnabled, "Unlock disabled")
        unlock.tap()

        let lock = app.buttons["Lock"]
        XCTAssertTrue(lock.waitForExistence(timeout: 25), statusDump(app))
        Thread.sleep(forTimeInterval: 1.0)
        saveShot(dir: outDir, name: "\(prefix)-02-browse.png")

        let notesBtn = app.buttons["notes"].firstMatch
        XCTAssertTrue(notesBtn.waitForExistence(timeout: 5), "notes folder missing")
        notesBtn.tap()
        Thread.sleep(forTimeInterval: 1.0)
        saveShot(dir: outDir, name: "\(prefix)-03-folder.png")

        // Open todo.md if present
        let todo = app.buttons["todo.md"].firstMatch
        if todo.waitForExistence(timeout: 3) {
            todo.tap()
            let close = app.navigationBars.buttons["Close"]
            if close.waitForExistence(timeout: 8) {
                Thread.sleep(forTimeInterval: 0.5)
                saveShot(dir: outDir, name: "\(prefix)-05-preview.png")
                close.tap()
                Thread.sleep(forTimeInterval: 0.4)
            }
        }

        let up = app.buttons[".."].firstMatch
        if up.exists {
            up.tap()
            Thread.sleep(forTimeInterval: 0.7)
        }

        // Actions at root
        if !app.buttons["Backup folder into vault…"].exists {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.4)
        }
        saveShot(dir: outDir, name: "\(prefix)-04-actions.png")

        // hello preview if we skipped todo
        if !FileManager.default.fileExists(atPath: (outDir as NSString).appendingPathComponent("\(prefix)-05-preview.png")) {
            app.swipeDown()
            let hello = app.buttons["hello.txt"].firstMatch
            if hello.waitForExistence(timeout: 3) {
                hello.tap()
                let close = app.navigationBars.buttons["Close"]
                if close.waitForExistence(timeout: 8) {
                    Thread.sleep(forTimeInterval: 0.5)
                    saveShot(dir: outDir, name: "\(prefix)-05-preview.png")
                    close.tap()
                }
            }
        }
    }

    private func replaceText(in field: XCUIElement, with value: String, app: XCUIApplication) {
        field.tap()
        // Select-all via menu if possible; else delete chars
        field.press(forDuration: 1.2)
        if app.menuItems["Select All"].waitForExistence(timeout: 1.5) {
            app.menuItems["Select All"].tap()
        } else {
            // fallback: delete up to 300 chars
            let existing = (field.value as? String) ?? ""
            let n = max(existing.count, 1)
            let dels = String(repeating: XCUIKeyboardKey.delete.rawValue, count: min(n + 5, 300))
            field.typeText(dels)
        }
        // Paste via pasteboard for reliability (avoids soft-keyboard mangling)
        UIPasteboard.general.string = value
        field.press(forDuration: 1.0)
        if app.menuItems["Paste"].waitForExistence(timeout: 2) {
            app.menuItems["Paste"].tap()
        } else {
            field.typeText(value)
        }
    }

    private func dismissKeyboard(_ app: XCUIApplication) {
        if app.keyboards.buttons["Return"].exists {
            app.keyboards.buttons["Return"].tap()
        } else if app.keyboards.buttons["done"].exists {
            app.keyboards.buttons["done"].tap()
        } else if app.keyboards.count > 0 {
            app.swipeDown()
        }
    }

    private func statusDump(_ app: XCUIApplication) -> String {
        let texts = app.staticTexts.allElementsBoundByAccessibilityElement.prefix(12).map { $0.label }
        return "Unlock did not reach browse. Visible: \(texts)"
    }

    private func saveShot(dir: String, name: String) {
        let shot = XCUIScreen.main.screenshot()
        let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: dir),
                withIntermediateDirectories: true
            )
            try shot.pngRepresentation.write(to: url)
            let attach = XCTAttachment(screenshot: shot)
            attach.name = name
            attach.lifetime = .keepAlways
            add(attach)
            NSLog("ASC_SHOT_OK %@", url.path)
        } catch {
            XCTFail("Failed writing \(name): \(error)")
        }
    }
}
