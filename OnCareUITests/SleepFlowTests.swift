import XCTest

final class SleepFlowTests: XCTestCase {
    private func tap(_ app: XCUIApplication, _ id: String) {
        let element = app.descendants(matching: .any).matching(identifier: id).firstMatch
        for _ in 0..<8 { if element.exists && element.isHittable { element.tap(); return }; app.swipeUp() }
        XCTFail("Missing control: " + id)
    }
    private func reset(_ app: XCUIApplication, discard: Bool) {
        tap(app, "sleep-tracking-reset")
        let alert = app.alerts["취침 기록을 초기화할까요?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        let action = alert.buttons[discard ? "초기화" : "계속 기록"].firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 5)); XCTAssertTrue(action.isHittable)
        action.tap()
    }
    private func open(_ app: XCUIApplication) {
        app.tabBars.buttons["건강"].tap(); tap(app, "sleep-routine-open")
        XCTAssertTrue(app.segmentedControls["sleep-mode"].waitForExistence(timeout: 5))
    }
    private func shot(_ name: String) throws {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: directory.appendingPathComponent(name + ".png"))
    }
    func testSleepTrackingRecoveryResetAndPatternAnalysis() throws {
        let app = XCUIApplication(); app.launch(); open(app)
        app.segmentedControls["sleep-mode"].buttons["수면 기록"].tap()
        if app.buttons["sleep-tracking-reset"].exists { reset(app, discard: true) }
        tap(app, "sleep-tracking-start")
        XCTAssertTrue(app.staticTexts["sleep-tracking-state"].waitForExistence(timeout: 5))
        tap(app, "sleep-tracking-finish")
        XCTAssertTrue(app.staticTexts["sleep-tracking-message"].label.contains("1분 이상"))
        try shot("14-sleep-tracking")
        app.terminate(); app.launch(); open(app)
        app.segmentedControls["sleep-mode"].buttons["수면 기록"].tap()
        XCTAssertTrue(app.staticTexts["sleep-tracking-state"].waitForExistence(timeout: 5))
        reset(app, discard: false)
        XCTAssertTrue(app.staticTexts["sleep-tracking-state"].exists)
        reset(app, discard: true)
        XCTAssertTrue(app.buttons["sleep-tracking-start"].waitForExistence(timeout: 5))
        app.buttons["닫기"].tap(); open(app)
        app.segmentedControls["sleep-mode"].buttons["수면 분석"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "sleep-pattern-summary").firstMatch.waitForExistence(timeout: 5))
        try shot("15-sleep-analysis")
        app.buttons["닫기"].tap()
    }
}
