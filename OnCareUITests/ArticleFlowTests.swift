import XCTest

final class ArticleFlowTests: XCTestCase {
    func screenshot(_ name: String) throws {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: directory.appendingPathComponent(name + ".png"))
    }
    func testInterestReadingBookmarkAndRestoration() throws {
        let app = XCUIApplication(); app.launch()
        app.tabBars.buttons["읽을거리"].tap()
        XCTAssertTrue(app.staticTexts["나를 알아가는 시간"].waitForExistence(timeout: 5))
        let interest = app.buttons["interest-마음"]
        if interest.value as? String != "선택됨" { interest.tap() }
        XCTAssertEqual(interest.value as? String, "선택됨")
        try screenshot("17-articles-library")
        let tile = app.buttons["article-mind-five"]
        for _ in 0..<5 { if tile.isHittable { break }; app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(tile.exists); tile.tap()
        XCTAssertEqual(app.staticTexts["article-title"].label, "마음에도, 작은 여유를")
        let save = app.buttons["article-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        if save.label == "저장 취소" { save.tap() }
        save.tap(); XCTAssertEqual(save.label, "저장 취소")
        try screenshot("18-article-detail")
        app.buttons["article-close"].tap()
        app.terminate(); app.launch(); app.tabBars.buttons["읽을거리"].tap()
        XCTAssertEqual(app.buttons["interest-마음"].value as? String, "선택됨")
        let filter = app.segmentedControls["articles-filter"]
        for _ in 0..<4 { if filter.isHittable { break }; app.scrollViews.firstMatch.swipeUp() }
        filter.buttons["저장한 글"].tap()
        XCTAssertTrue(app.buttons["article-mind-five"].waitForExistence(timeout: 5))
        try screenshot("19-articles-saved")
    }
}
