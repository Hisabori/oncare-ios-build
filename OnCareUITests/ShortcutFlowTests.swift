import XCTest

final class ShortcutFlowTests: XCTestCase {
    @MainActor func testColdLinkWarmModalReplacementAndInvalidLink() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Direct application URL automation needs the current simulator SDK") }
        let app = XCUIApplication()
        app.launch(); app.terminate()
        app.open(URL(string: "oncare://open/sleep")!)
        XCTAssertTrue(app.navigationBars["수면 루틴"].waitForExistence(timeout: 10), "A cold link must reach the requested form")
        XCUIDevice.shared.system.open(URL(string: "oncare://open/workout")!)
        XCTAssertTrue(app.navigationBars["실천 센터"].waitForExistence(timeout: 10), "A warm link must replace the previous sheet")
        XCTAssertFalse(app.navigationBars["수면 루틴"].exists)
        XCUIDevice.shared.system.open(URL(string: "oncare://open/mood")!)
        XCTAssertTrue(app.navigationBars["마음 기록"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["실천 센터"].exists)
        XCUIDevice.shared.system.open(URL(string: "oncare://open/connect")!)
        XCTAssertTrue(app.navigationBars["Android 건강 연결"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["마음 기록"].exists)
        XCUIDevice.shared.system.open(URL(string: "oncare://open/mood?save=true")!)
        XCTAssertTrue(app.navigationBars["Android 건강 연결"].waitForExistence(timeout: 5), "An unsupported command must not replace the current form")
        app.buttons["닫기"].tap()
        XCTAssertTrue(app.tabBars.buttons["건강"].waitForExistence(timeout: 5))
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: folder.appendingPathComponent("14-shortcut-navigation.png"))
    }
}
