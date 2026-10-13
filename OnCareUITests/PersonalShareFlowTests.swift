import XCTest
final class PersonalShareFlowTests: XCTestCase {
    func screenshot(_ name: String) throws { let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]; try XCUIScreen.main.screenshot().pngRepresentation.write(to: directory.appendingPathComponent(name + ".png")) }
    func testPreviewSelectionVersionAndCameraFallback() throws {
        let app = XCUIApplication(); app.launch(); app.tabBars.buttons["기록"].tap()
        let open = app.buttons["personal-share-open"]
        for _ in 0..<10 { if open.isHittable { break }; app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(open.isHittable); open.tap()
        XCTAssertEqual(app.switches["share-kind-마음"].value as? String, "0"); XCTAssertEqual(app.switches["share-kind-체중"].value as? String, "0")
        app.buttons["share-preview"].tap(); XCTAssertTrue(app.staticTexts["share-preview-text"].waitForExistence(timeout: 3))
        let text = app.staticTexts["share-preview-text"].label
        XCTAssertFalse(text.contains("체중")); XCTAssertFalse(text.contains("마음")); XCTAssertFalse(text.contains("oncare1:")); XCTAssertTrue(app.buttons["share-send"].exists)
        try screenshot("25-personal-share-preview")
        app.buttons["돌아가기"].firstMatch.tap(); app.buttons["닫기"].firstMatch.tap()
        for _ in 0..<5 { if app.staticTexts["app-version"].isHittable { break }; app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(app.staticTexts["app-version"].label.contains("3.9.0 · 빌드 13"))
        XCUIDevice.shared.system.open(URL(string: "oncare://open/connect")!)
        XCTAssertTrue(app.buttons["sync-qr-scan"].waitForExistence(timeout: 5)); app.buttons["sync-qr-scan"].tap()
        XCTAssertTrue(app.navigationBars["연결 QR 스캔"].waitForExistence(timeout: 5)); try screenshot("26-qr-scanner-fallback")
        app.buttons["취소"].firstMatch.tap(); XCTAssertTrue(app.textFields["sync-code"].exists || app.textViews["sync-code"].exists)
    }
}
