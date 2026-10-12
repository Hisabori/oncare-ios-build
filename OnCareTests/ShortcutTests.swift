import XCTest
@testable import OnCare

final class ShortcutTests: XCTestCase {
    func testWidgetURLsOnlyOpenKnownForms() {
        for destination in CareDestination.allCases {
            XCTAssertEqual(CareDestination.parse(destination.url), destination)
            XCTAssertEqual(CareDestination.parse(quickActionType: destination.quickActionType), destination)
            XCTAssertNil(URLComponents(url: destination.url, resolvingAgainstBaseURL: false)?.query)
        }
        XCTAssertEqual(Set(CareDestination.allCases.map(\.url)).count, 4)
        let rejected = [
            "https://open/sleep", "oncare://unknown/sleep", "oncare://open/unknown",
            "oncare://open/sleep/", "oncare://open/sleep/mood", "oncare://open/%73leep",
            "oncare://open/../sleep", "oncare://open/sleep?save=true", "oncare://open/connect?token=private",
            "oncare://open/mood#save", "oncare://user:secret@open/sleep", "oncare://open:8766/sleep",
            "oncare:open/sleep", "oncare://open/", "oncare://open/workout?start=true",
            "oncare://open/" + String(repeating: "a", count: 200)
        ]
        for text in rejected { if let url = URL(string: text) { XCTAssertNil(CareDestination.parse(url), text) } }
        for type in ["sleep", "app.oncare.open.unknown", "app.oncare.open.sleep.extra", "app.oncare.open.connect?token=secret"] {
            XCTAssertNil(CareDestination.parse(quickActionType: type))
        }
    }
    @MainActor func testColdRequestWaitsAndNewestRequestWins() {
        let router = CareShortcutRouter()
        router.open(.sleep); let first = router.pending!
        XCTAssertEqual(first.destination, .sleep)
        router.open(.workout); let second = router.pending!
        XCTAssertNotEqual(first.id, second.id)
        router.complete(first.id)
        XCTAssertEqual(router.pending, second, "A dismissed older form may not consume the new request")
        XCTAssertFalse(router.open(URL(string: "oncare://open/connect?token=secret")!))
        XCTAssertEqual(router.pending, second, "An invalid link must not replace a valid pending action")
        router.complete(second.id); XCTAssertNil(router.pending)
        XCTAssertTrue(router.open(quickActionType: CareDestination.mood.quickActionType))
        XCTAssertEqual(router.pending?.destination, .mood)
    }
    @MainActor func testAllShortcutIntentsUseTheSameNavigationQueue() async throws {
        let router = CareShortcutRouter.shared
        defer { if let request = router.pending { router.complete(request.id) } }
        _ = try await OpenCareSleepIntent().perform(); XCTAssertEqual(router.pending?.destination, .sleep)
        _ = try await OpenCareWorkoutIntent().perform(); XCTAssertEqual(router.pending?.destination, .workout)
        _ = try await OpenCareMoodIntent().perform(); XCTAssertEqual(router.pending?.destination, .mood)
        _ = try await OpenCareConnectionIntent().perform(); XCTAssertEqual(router.pending?.destination, .connect)
        XCTAssertTrue(OpenCareSleepIntent.openAppWhenRun); XCTAssertTrue(OpenCareWorkoutIntent.openAppWhenRun)
        XCTAssertTrue(OpenCareMoodIntent.openAppWhenRun); XCTAssertTrue(OpenCareConnectionIntent.openAppWhenRun)
    }
    @MainActor func testDestinationMappingPreservesExistingForms() {
        XCTAssertEqual(CareDestination.sleep.sheet, .sleepRoutine)
        XCTAssertEqual(CareDestination.workout.sheet, .practice)
        XCTAssertEqual(CareDestination.mood.sheet, .mood)
        XCTAssertEqual(CareDestination.connect.sheet, .healthConnection)
        XCTAssertEqual(CareDestination.mood.tab, 1)
        XCTAssertEqual(CareDestination.sleep.tab, 2)
    }
}
