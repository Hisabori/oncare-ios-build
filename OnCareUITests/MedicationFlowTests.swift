import XCTest

final class MedicationFlowTests: XCTestCase {
    func tap(_ app: XCUIApplication,_ id: String) {
        let element = app.descendants(matching: .any).matching(identifier: id).firstMatch
        for _ in 0..<12 { if element.exists && element.isHittable { element.tap();return };app.scrollViews.firstMatch.swipeUp() };XCTFail("Missing " + id)
    }
    func screenshot(_ name: String) throws { try XCUIScreen.main.screenshot().pngRepresentation.write(to: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(name + ".png")) }
    func testMedicationScheduleAndTakenRestore() throws {
        let app = XCUIApplication();app.launch();tap(app,"medication-open");tap(app,"medication-add")
        let name = app.textFields["medication-name"];XCTAssertTrue(name.waitForExistence(timeout: 5));name.tap();name.typeText("처방 약 테스트")
        tap(app,"medication-save");XCTAssertTrue(app.staticTexts["처방 약 테스트"].firstMatch.waitForExistence(timeout: 5))
        let taken = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "medication-taken-")).firstMatch
        for _ in 0..<8 { if taken.isHittable { break };app.scrollViews.firstMatch.swipeDown() }
        XCTAssertTrue(taken.exists);taken.tap();XCTAssertTrue(app.staticTexts["복용 확인됨"].firstMatch.waitForExistence(timeout: 5));try screenshot("20-medication-schedule")
        app.terminate();app.launch();tap(app,"medication-open");XCTAssertTrue(app.staticTexts["복용 확인됨"].firstMatch.waitForExistence(timeout: 5))
        tap(app,"medication-history-open");XCTAssertTrue(app.navigationBars["복용 확인 기록"].waitForExistence(timeout: 5));try screenshot("23-medication-history");app.buttons["닫기"].firstMatch.tap();
        tap(app,"medication-backup-open");XCTAssertTrue(app.buttons["medication-export"].waitForExistence(timeout: 5));XCTAssertTrue(app.buttons["medication-import"].exists);try screenshot("24-medication-backup");app.buttons["닫기"].firstMatch.tap();
        app.buttons["닫기"].firstMatch.tap();XCTAssertTrue(app.staticTexts["medication-home-count"].label.contains("1 / 1"));tap(app,"widget-help-open")
        let status = app.descendants(matching: .any).matching(identifier: "widget-install-status").firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5));XCTAssertTrue(status.label.contains("위젯 확장이 설치되어 있어요"))
        try screenshot("21-widget-install-check")
    }
}
