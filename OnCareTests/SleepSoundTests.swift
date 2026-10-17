import XCTest
@testable import OnCare
final class SleepSoundTests: XCTestCase {
    func testMeteringUsesRelativeEnergyAndHasNoSilentInfinity() {
        XCTAssertEqual(SleepSoundAccumulator.db(0), -120)
        XCTAssertEqual(SleepSoundAccumulator.db(0.5), -6.0206, accuracy: 0.001)
        let collector = SleepSoundAccumulator()
        let samples = Array(repeating: Float(0.5), count: 600)
        let bin = samples.withUnsafeBufferPointer { collector.add($0, rate: 10) }
        XCTAssertEqual(bin?.seconds, 60)
        XCTAssertEqual(bin!.rmsDBFS, -6.0206, accuracy: 0.001)
        XCTAssertNil(collector.finish())
    }
    func testPartialMinuteDoesNotBecomeSleepDuration() throws {
        let collector = SleepSoundAccumulator()
        let samples = Array(repeating: Float(0), count: 100)
        XCTAssertNil(samples.withUnsafeBufferPointer { collector.add($0, rate: 10) })
        let bin = try XCTUnwrap(collector.finish())
        let session = SleepSoundSession(threshold: -35, bins: [bin])
        XCTAssertEqual(session.measuredMinutes, 10.0/60, accuracy: 0.0001)
        XCTAssertEqual(session.loudMinutes, 0)
        XCTAssertEqual(try JSONDecoder().decode(SleepSoundBin.self, from: JSONEncoder().encode(bin)), bin)
    }
}
