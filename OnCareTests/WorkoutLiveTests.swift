import XCTest
@testable import OnCare

@MainActor final class WorkoutLiveTests: XCTestCase {
    func testRunningAndPausedSnapshotExcludesPausedTime() throws {
        guard #available(iOS 16.2, *) else { return }
        let start = Date(timeIntervalSince1970: 10000)
        var session = WorkoutSession(type: "걷기", goalMinutes: 20, createdAt: start, checkpointAt: start, segmentStartedAt: start)
        let state = try WorkoutLiveStatus.state(for: session, at: start.addingTimeInterval(90))
        XCTAssertTrue(state.running); XCTAssertEqual(state.elapsedSeconds, 90); XCTAssertEqual(state.timerStart, start)
        session.elapsedSeconds = 90; session.segmentStartedAt = nil; session.checkpointAt = start.addingTimeInterval(90)
        let paused = try WorkoutLiveStatus.state(for: session, at: start.addingTimeInterval(300))
        XCTAssertFalse(paused.running); XCTAssertEqual(paused.elapsedSeconds, 90)
        XCTAssertEqual(try JSONDecoder().decode(CareWorkoutAttributes.ContentState.self, from: JSONEncoder().encode(paused)), paused)
    }
    func testClockRollbackDoesNotProduceLiveSnapshot() throws {
        guard #available(iOS 16.2, *) else { return }
        let start = Date(timeIntervalSince1970: 10000)
        let session = WorkoutSession(type: "걷기", goalMinutes: 20, createdAt: start, checkpointAt: start, segmentStartedAt: start)
        XCTAssertThrowsError(try WorkoutLiveStatus.state(for: session, at: start.addingTimeInterval(-1)))
    }
}
