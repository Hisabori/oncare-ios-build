import XCTest
@testable import OnCare

@MainActor private final class MedicationCenterFake: MedicationNotifications {
    var permission = true
    var fails = false
    var applied: [MedicationPlan] = []
    func authorize() async throws -> Bool { permission }
    func allowed() async -> Bool { permission }
    func apply(_ plans: [MedicationPlan]) async throws { if fails { throw CareError.invalid }; applied = plans }
}
final class MedicationTests: XCTestCase {
    func directory() throws -> URL { let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url }
    func testInvalidSchedulesAndNotificationBudget() throws {
        var plan = MedicationPlan(name: "처방 약")
        XCTAssertEqual(plan.notificationIDs.count, 7)
        var state = MedicationState();state.plans = (0..<8).map { _ in MedicationPlan(name: "처방 약") }
        try state.validate();XCTAssertEqual(Set(state.plans.flatMap(\.notificationIDs)).count, 56)
        state.plans.append(plan);XCTAssertThrowsError(try state.validate())
        plan.weekdays = [];XCTAssertThrowsError(try plan.validate())
        plan.weekdays = [2,8];XCTAssertThrowsError(try plan.validate())
        plan.weekdays = [2];plan.hour = 24;XCTAssertThrowsError(try plan.validate())
        plan.hour = 9;plan.name = " ";XCTAssertThrowsError(try plan.validate())
    }
    @MainActor func testPermissionDenialDoesNotSaveAnEnabledSchedule() async throws {
        let d = try directory();defer { try? FileManager.default.removeItem(at: d) }
        let center = MedicationCenterFake();center.permission = false
        let store = MedicationStore(directory: d, notifications: center)
        let saved = await store.save(MedicationPlan(name: "처방 약"))
        XCTAssertFalse(saved);XCTAssertTrue(store.state.plans.isEmpty);XCTAssertNotNil(store.message)
        let disabled = await store.save(MedicationPlan(name: "처방 약", enabled: false))
        XCTAssertTrue(disabled);XCTAssertEqual(store.state.plans.count,1)
    }
    @MainActor func testPersistenceEditingAndDeletionRemoveOnlyOwnSchedule() async throws {
        let d = try directory();defer { try? FileManager.default.removeItem(at: d) }
        let center = MedicationCenterFake(), store = MedicationStore(directory: d, notifications: MedicationCenterFake())
        var plan = MedicationPlan(name: "처방 약", hour: 7, weekdays: [2,4,6])
        let added = await store.save(plan);XCTAssertTrue(added)
        let restored = MedicationStore(directory: d, notifications: center)
        XCTAssertEqual(restored.state.plans, [plan]);await restored.refresh();XCTAssertEqual(center.applied, [plan])
        plan.hour = 10;plan.enabled = false
        let edited = await restored.save(plan);XCTAssertTrue(edited);XCTAssertEqual(center.applied.first?.notificationIDs, [])
        await restored.remove(plan.id);XCTAssertTrue(center.applied.isEmpty);XCTAssertTrue(MedicationStore(directory: d, notifications: center).state.plans.isEmpty)
    }
    @MainActor func testTakenCheckRolloverAndDeletion() async throws {
        let d = try directory();defer { try? FileManager.default.removeItem(at: d) }
        let store = MedicationStore(directory: d, notifications: MedicationCenterFake()), plan = MedicationPlan(name: "처방 약", enabled: false)
        let saved = await store.save(plan);XCTAssertTrue(saved)
        let now = Date();store.toggleTaken(plan.id, now: now);XCTAssertTrue(store.checked(plan.id, now: now))
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        XCTAssertFalse(store.checked(plan.id, now: tomorrow))
        XCTAssertTrue(MedicationStore(directory: d, notifications: MedicationCenterFake()).checked(plan.id, now: now))
        await store.remove(plan.id);XCTAssertFalse(store.checked(plan.id, now: now))
    }
    @MainActor func testCorruptOriginalIsPreserved() async throws {
        let d = try directory();defer { try? FileManager.default.removeItem(at: d) }
        let file = d.appendingPathComponent("medications-v1.json"), raw = Data("broken".utf8);try raw.write(to: file)
        let store = MedicationStore(directory: d, notifications: MedicationCenterFake());XCTAssertFalse(store.readable)
        let saved = await store.save(MedicationPlan(name: "처방 약", enabled: false));XCTAssertFalse(saved);XCTAssertEqual(try Data(contentsOf: file), raw)
    }
    @MainActor func testSchedulingFailureIsVisibleAndRetryKeepsSavedPlan() async throws {
        let d = try directory();defer { try? FileManager.default.removeItem(at: d) }
        let center = MedicationCenterFake();center.fails = true
        let store = MedicationStore(directory: d, notifications: center)
        let saved = await store.save(MedicationPlan(name: "처방 약"));XCTAssertTrue(saved)
        XCTAssertTrue(store.status.contains("재시도"));XCTAssertNotNil(store.message)
        center.fails = false;await store.refresh();XCTAssertEqual(center.applied.count,1);XCTAssertTrue(store.status.contains("허용"));XCTAssertNil(store.message)
    }
}
