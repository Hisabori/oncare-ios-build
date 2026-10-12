import XCTest

final class WidgetGalleryTests: XCTestCase {
    func testWidgetIsOfferedInSystemGallery() throws {
        let app = XCUIApplication();app.launch();XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let icon = springboard.icons["온케어 3"].firstMatch
        for _ in 0..<4 { if icon.exists { break };springboard.swipeLeft() }
        XCTAssertTrue(icon.waitForExistence(timeout: 5),springboard.debugDescription);icon.press(forDuration: 1.5)
        let editHome = springboard.buttons["Edit Home Screen"].firstMatch
        XCTAssertTrue(editHome.waitForExistence(timeout: 5),springboard.debugDescription);editHome.tap()
        let edit = springboard.buttons["Edit"].firstMatch
        // SpringBoard can retain the context menu after the first synthetic tap.
        // Retry only while that exact menu item is still visibly available.
        if !edit.waitForExistence(timeout: 10), editHome.exists && editHome.isHittable { editHome.tap() }
        guard edit.waitForExistence(timeout: 10) else {
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: FileManager.default.urls(for: .documentDirectory,in: .userDomainMask)[0].appendingPathComponent("22-widget-gallery-failure.png"))
            XCTFail("Home screen edit menu unavailable after entering edit mode.\n" + springboard.debugDescription); return
        }; edit.tap()
        let add = springboard.buttons["Add Widget"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5),springboard.debugDescription);add.tap()
        let search = springboard.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5),springboard.debugDescription);search.tap();search.typeText("온케어")
        let offered = springboard.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "온케어 3")).firstMatch
        XCTAssertTrue(offered.waitForExistence(timeout: 10),springboard.debugDescription)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("22-widget-system-gallery.png"))
        XCUIDevice.shared.press(.home)
    }
}
