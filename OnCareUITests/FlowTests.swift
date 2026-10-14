import XCTest

final class FlowTests: XCTestCase {
    func screenshot(_ name: String) throws {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        let folder = FileManager.default.urls(for: .documentDirectory,in: .userDomainMask)[0]
        try data.write(to: folder.appendingPathComponent(name+".png"))
    }
    func tap(_ app: XCUIApplication,_ id: String) {
        if id == "practice-open" {
            let today = app.tabBars.buttons["오늘"]
            if today.waitForExistence(timeout: 10) { today.tap() }
            let scroll = app.scrollViews.firstMatch
            for _ in 0..<10 {
                if app.staticTexts["오늘도, 나답게"].isHittable { break }
                guard scroll.exists else { break }; scroll.swipeDown()
            }
        }
        let element = app.descendants(matching: .any).matching(identifier: id).firstMatch
        for _ in 0..<8 { if element.exists && element.isHittable { element.tap(); return }; app.swipeUp() }
        print("Missing control snapshot: " + app.debugDescription)
        try? screenshot("failed-control-" + id)
        XCTFail("Missing control: "+id)
    }
    func assertWorkoutReset(_ app: XCUIApplication) {
        let start = app.buttons["workout-start"], state = app.staticTexts["workout-state"]
        let immediatelyVisible = start.exists, confirmationVisible = app.buttons["workout-reset-confirm"].exists
        print("RESET transition: start=\(immediatelyVisible), sessionState=\(state.exists), confirmation=\(confirmationVisible)")
        // The confirmation dismissal and the replacement controls have separate accessibility updates.
        // If the old card's scroll position hides the replacement, reveal it before asserting.
        var found = start.waitForExistence(timeout: 5)
        if !found || !start.isHittable {
            print("RESET before scrolling:\n" + app.debugDescription)
            let scroll = app.scrollViews.firstMatch
            for _ in 0..<4 {
                if start.exists && start.isHittable { break }
                guard scroll.exists else { break }
                if app.staticTexts["오늘의 작은 실천"].isHittable { scroll.swipeUp() } else { scroll.swipeDown() }
            }
            found = start.waitForExistence(timeout: 5)
            print("RESET after scrolling: start=\(found), hittable=\(start.isHittable), sessionState=\(state.exists)")
        }
        XCTAssertTrue(found, "Reset must replace the active timer with its start control.\n" + app.debugDescription)
        if found { XCTAssertTrue(start.isEnabled); XCTAssertTrue(start.isHittable) }
        XCTAssertFalse(state.exists, "A reset timer must no longer show an active or paused session")
        let message = app.staticTexts["workout-message"]
        XCTAssertTrue(message.waitForExistence(timeout: 5), "Reset must report its successful state change")
        if message.exists { XCTAssertTrue(message.label.contains("새 운동을 시작할 수 있어요"), "Reset may not silently retain a session after a storage error") }
    }
    func testRecordRoutineReportAndSearch() throws {
        let app = XCUIApplication(); app.launch(); XCTAssertTrue(app.staticTexts["오늘도, 나답게"].waitForExistence(timeout: 15))
        try screenshot("01-home-empty")
        tap(app,"open-weight"); let value = app.textFields["record-value"]; XCTAssertTrue(value.waitForExistence(timeout: 5)); value.tap(); value.typeText("72.4"); tap(app,"record-save")
        app.terminate(); app.launch(); app.tabBars.buttons["건강"].tap(); XCTAssertTrue(app.staticTexts["72.4 kg"].waitForExistence(timeout: 5))
        app.tabBars.buttons["오늘"].tap(); tap(app,"goals-open"); app.textFields["goal-weight"].tap(); app.textFields["goal-weight"].typeText("68"); tap(app,"goals-save")
        app.tabBars.buttons["마음"].tap(); tap(app,"mood-choice-4"); tap(app,"record-save")
        app.tabBars.buttons["오늘"].tap(); tap(app,"open-exercise"); app.textFields["record-value"].tap(); app.textFields["record-value"].typeText("30"); tap(app,"record-save")
        // All example records are entered on the simulator, never bundled in the application.
        app.terminate(); app.launch(); tap(app,"routine-edit"); app.textFields["routine-title"].tap(); app.textFields["routine-title"].typeText("저녁 산책"); tap(app,"routine-add"); tap(app,"routine-check-0")
        app.terminate(); app.launch(); XCTAssertTrue(app.buttons["routine-check-0"].label.contains("완료")); try screenshot("02-home-routine")
        app.tabBars.buttons["건강"].tap(); XCTAssertTrue(app.staticTexts["내 목표 68 kg"].waitForExistence(timeout: 5)); try screenshot("03-health")
        app.tabBars.buttons["마음"].tap(); try screenshot("04-mind")
        app.tabBars.buttons["오늘"].tap(); tap(app,"report-open"); XCTAssertTrue(app.navigationBars["나의 주간 리포트"].waitForExistence(timeout: 5)); try screenshot("05-weekly-report"); app.buttons["닫기"].tap()
        app.tabBars.buttons["기록"].tap(); let search = app.textFields["journal-search"]; search.tap(); search.typeText("걷기"); if app.buttons["완료"].exists { app.buttons["완료"].tap() }; XCTAssertEqual(app.staticTexts["search-count"].label,"1개 기록"); try screenshot("06-search")
        app.terminate(); app.launch(); tap(app,"reminders-open"); try screenshot("07-reminder-settings"); app.buttons["닫기"].tap()
        app.terminate(); app.launch(); tap(app,"intelligence-open"); XCTAssertTrue(app.staticTexts["기록에서 발견하는 나"].waitForExistence(timeout: 5)); XCTAssertTrue(app.buttons["intelligence-generate"].exists); try screenshot("08-intelligence"); app.buttons["닫기"].tap()
    }
    func testSleepAndInvalidConnectionFlow() throws {
        let app = XCUIApplication(); app.launch(); app.tabBars.buttons["건강"].tap(); tap(app,"sleep-routine-open");
        XCTAssertTrue(app.staticTexts["내 생활에 맞춘 수면 루틴"].waitForExistence(timeout: 5)); tap(app,"sleep-plan-save"); XCTAssertTrue(app.staticTexts["sleep-message"].label.contains("저장")); try screenshot("09-sleep-routine"); let modes = app.segmentedControls["sleep-mode"]; for _ in 0..<6 { if modes.exists && modes.isHittable { break }; app.scrollViews.firstMatch.swipeDown() }; XCTAssertTrue(modes.waitForExistence(timeout: 5)); modes.buttons["수면 기록"].tap(); let awake=app.textFields["sleep-awake"]; tap(app,"sleep-awake"); awake.typeText("30"); if app.buttons["완료"].exists { app.buttons["완료"].tap() }; tap(app,"sleep-measured-save"); XCTAssertTrue(app.staticTexts["sleep-message"].label.contains("7.5시간")); try screenshot("10-sleep-record"); app.buttons["닫기"].tap();
        app.terminate(); app.launch(); app.tabBars.buttons["건강"].tap(); tap(app,"body-sync-open"); let field=app.descendants(matching: .any)["sync-code"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("invalid-code"); tap(app,"sync-connect"); XCTAssertTrue(app.staticTexts["연결 코드 또는 저장 상태를 확인해주세요. Android에서 새 코드를 복사할 수 있어요."].waitForExistence(timeout: 5)); app.buttons["닫기"].tap();
    }
    func testPracticeTimerPauseAndRestoration() throws {
        let app = XCUIApplication(); app.launch(); tap(app, "practice-open")
        XCTAssertTrue(app.staticTexts["오늘의 작은 실천"].waitForExistence(timeout: 5))
        if app.buttons["workout-reset"].exists { tap(app, "workout-reset"); tap(app, "workout-reset-confirm"); assertWorkoutReset(app) }
        try screenshot("11-practice-center")
        tap(app, "workout-start"); XCTAssertTrue(app.staticTexts["workout-state"].waitForExistence(timeout: 5)); XCTAssertEqual(app.staticTexts["workout-state"].label, "운동 진행 중")
        tap(app, "workout-finish"); XCTAssertTrue(app.staticTexts["workout-message"].label.contains("1분 미만"))
        tap(app, "workout-toggle"); XCTAssertEqual(app.staticTexts["workout-state"].label, "일시정지")
        let paused = app.staticTexts["workout-elapsed"].label
        app.terminate(); app.launch(); tap(app, "practice-open")
        XCTAssertEqual(app.staticTexts["workout-state"].label, "일시정지"); XCTAssertEqual(app.staticTexts["workout-elapsed"].label, paused)
        tap(app, "workout-toggle"); XCTAssertEqual(app.staticTexts["workout-state"].label, "운동 진행 중")
        app.terminate(); app.launch(); tap(app, "practice-open")
        XCTAssertEqual(app.staticTexts["workout-state"].label, "운동 진행 중"); try screenshot("12-workout-timer")
        tap(app, "workout-reset"); tap(app, "workout-reset-confirm"); assertWorkoutReset(app)
        // Reopening reads the session file again; a hidden active timer must not pass this check.
        app.terminate(); app.launch(); tap(app, "practice-open")
        XCTAssertTrue(app.buttons["workout-start"].waitForExistence(timeout: 5)); XCTAssertTrue(app.buttons["workout-start"].isEnabled)
        XCTAssertFalse(app.staticTexts["workout-state"].exists); XCTAssertFalse(app.buttons["workout-reset"].exists)
        app.buttons["닫기"].tap(); app.tabBars.buttons["건강"].tap(); tap(app, "body-practice-open")
        XCTAssertTrue(app.navigationBars["실천 센터"].waitForExistence(timeout: 5))
        app.segmentedControls["practice-section"].buttons["루틴"].tap(); XCTAssertTrue(app.staticTexts["최근 7일의 루틴"].exists)
        app.segmentedControls["practice-section"].buttons["기록 분석"].tap(); XCTAssertTrue(app.staticTexts["완료된 7일을 돌아봐요"].exists)
        let period = app.segmentedControls["insights-window"]
        period.buttons["30일"].tap()
        XCTAssertEqual(app.staticTexts["insights-heading"].label, "완료된 30일을 돌아봐요")
        let share = app.buttons["insights-share"]
        for _ in 0..<5 { if share.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(share.exists); XCTAssertTrue(share.isEnabled)
        tap(app, "insights-details")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "운동 기록 없음")).firstMatch.exists)
        try screenshot("13-thirty-day-analysis")
        app.buttons["닫기"].tap()
    }
}

