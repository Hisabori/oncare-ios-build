import XCTest
final class HealthBrowserFlowTests: XCTestCase {
    func testBrowseEmptyHealthRecordsAndSearch() throws {
        let app = XCUIApplication(); app.launch(); app.tabBars.buttons["건강"].tap()
        let browser = app.buttons["health-records-open"].firstMatch
        XCTAssertTrue(browser.waitForExistence(timeout: 5)); browser.tap()
        XCTAssertTrue(app.staticTexts["연결된 건강 정보"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["표시할 기록이 없어요. Android에서 권한과 원본 데이터 공유를 확인해주세요."].exists)
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: directory.appendingPathComponent("25-health-browser.png"))
        app.buttons["생체"].firstMatch.tap(); XCTAssertTrue(app.staticTexts["연결된 건강 정보"].exists)
        app.terminate()
    }
}
